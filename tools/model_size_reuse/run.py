"""Generate two pinned private decoders and compare them with released RTL."""

if not __debug__:
    raise SystemExit("Verification requires Python assertions; do not use -O or -OO")
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent


def identity(path):
    raw = path.read_bytes()
    return {'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()}


def save(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def checked(root, name, expected):
    relative = PurePosixPath(name)
    assert not relative.is_absolute() and '..' not in relative.parts
    path = root / relative
    assert path.is_file() and not path.is_symlink() and identity(path) == expected, name
    return path


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module  # Dataclasses and the generator's existing import.
    spec.loader.exec_module(module)
    return module


def select_yosys(args):
    env = dict(os.environ)
    receipt = None
    if args.tool_receipt:
        path = args.tool_receipt.resolve(strict=True)
        receipt = json.loads(path.read_text())
        assert receipt['passed'] is True
        entries = [str(Path(p).resolve()) for p in receipt['path_entries']]
        assert entries and all(Path(p).is_relative_to(path.parent) for p in entries)
        env['PATH'] = os.pathsep.join(entries + [env.get('PATH', '')])
    launch = args.yosys or shutil.which('yosys', path=env.get('PATH'))
    assert launch, 'Install Yosys or supply the pinned Linux tool receipt'
    launch = Path(launch).absolute()
    binary = launch.resolve(strict=True)
    version = subprocess.run([str(launch), '-V'], env=env, check=True,
                             capture_output=True, text=True, timeout=10).stdout.strip()
    pin = identity(binary)
    if receipt:
        expected = receipt['executables']['yosys']
        assert binary == Path(expected['path']).resolve()
        assert pin['sha256'] == expected['sha256']
        assert version == receipt['versions']['yosys']
    return launch, env, {'launch': str(launch), 'binary': str(binary),
                         'identity': pin, 'version': version,
                         'managed_receipt': bool(receipt)}


def recipe(candidate, induction):
    common = f'''read_verilog -sv released.sv
rename qwen_model_address original
read_verilog -sv {candidate}
rename qwen_model_address generated
proc
memory
opt
miter -equiv -flatten -make_outputs original generated comparison
hierarchy -top comparison
opt
'''
    if induction:
        return common + ('sat -timeout 15 -tempinduct -maxsteps 5 '
                         '-set-at 1 in_rst_n 0 -prove trigger 0 -verify '
                         '-show-inputs -show-outputs comparison\n')
    return common + ('sat -timeout 15 -seq 3 -set-at 1 in_rst_n 0 '
                     '-prove trigger 0 -falsify -show-inputs -show-outputs '
                     '-dump_json counterexample.json comparison\n')


def run_yosys(tool, env, directory, name, script):
    path = directory / (name + '.ys')
    path.write_text(script)
    log = directory / (name + '.log')
    command = [str(tool), '-Q', '-T', '-s', path.name]
    started = time.monotonic()
    with log.open('w') as stream:
        result = subprocess.run(command, cwd=directory, env=env, stdout=stream,
                                stderr=subprocess.STDOUT, timeout=90)
    receipt = {'command': command, 'exit_code': result.returncode,
               'seconds': time.monotonic() - started,
               'script': identity(path), 'log': identity(log)}
    save(directory / (name + '-execution.json'), receipt)
    assert result.returncode == 0, f'Unresolved {name}; inspect {log}'
    return log.read_text(), receipt


def witness(log):
    samples = {}
    for line in log.splitlines():
        match = re.fullmatch(r'\s*(\d+)\s+\\(\S+)\s+(?:-?\d+|--)\s+\S+\s+([01]+)\s*', line)
        if match:
            samples.setdefault(int(match[1]), {})[match[2]] = int(match[3], 2)
    assert samples[1]['in_rst_n'] == 0
    for step, row in samples.items():
        before = samples.get(step - 1, {})
        if (row.get('trigger') == 1 and row.get('gold_result_valid') == row.get('gate_result_valid') == 1
                and row.get('gold_result_error') == row.get('gate_result_error') == 0
                and row['gold_result_address'] ^ row['gate_result_address'] == 32
                and before.get('in_request_valid') == 1 and before.get('in_request_region') == 0
                and before.get('gold_request_ready') == before.get('gate_request_ready') == 1):
            return {'accepted_request_step': step - 1, 'mismatch_step': step,
                    'released_address': row['gold_result_address'],
                    'mutant_address': row['gate_result_address'], 'differing_bit': 5}
    raise AssertionError('Missing accepted weight-request/address-bit counterexample')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', type=Path, default=HERE.parents[1])
    parser.add_argument('--output', type=Path, required=True)
    tools = parser.add_mutually_exclusive_group()
    tools.add_argument('--yosys', type=Path)
    tools.add_argument('--tool-receipt', type=Path)
    args = parser.parse_args()
    root, out = args.repository.resolve(strict=True), args.output.resolve()
    assert not out.exists() and not out.is_relative_to(root), 'Use a new output outside the source layout'
    source = json.loads((HERE / 'SOURCE.json').read_text())
    assert source['schema'] == 'pinned-private-model-address-reuse-v1'
    assert set(source['models']) == {'qwen3-1.7b', 'qwen3-8b'}
    generator_path = checked(root, source['generator_source'], source['generator_identity'])
    geometry_path = checked(root, source['geometry_source'], source['geometry_identity'])
    load('model_geometry', geometry_path)
    generator = load('fixed_decoder_generator', generator_path)
    tool, env, tool_record = select_yosys(args)
    out.mkdir(parents=True)
    save(out / 'TOOL.json', tool_record)
    started = time.monotonic()
    originals, rows = {}, []
    try:
        for name, profile in source['models'].items():
            config = checked(HERE, profile['config'], profile['config_identity'])
            released = checked(root, profile['released_source'], profile['released_identity'])
            originals[released] = identity(released)
            geometry = generator.Geometry.from_config(json.loads(config.read_text()))
            assert geometry.positions == source['fixed_positions'] == 32768
            directory = out / name
            directory.mkdir()
            generated = directory / 'generated'
            generated_receipt = generator.generate(config, generated)
            raw = (generated / 'qwen_model_address.sv').read_bytes()
            (directory / 'released.sv').write_bytes(released.read_bytes())
            (directory / 'generated.sv').write_bytes(raw)
            row = {'model': name, 'config': identity(config), 'released': identity(released),
                   'generated': identity(directory / 'generated.sv'),
                   'geometry': geometry.__dict__, 'generation': generated_receipt}
            if name == 'qwen3-8b':
                assert raw == released.read_bytes(), '8B generated source differs from the pinned release'
                row['result'] = 'byte-identical'
            else:
                log, proof = run_yosys(tool, env, directory, 'equivalence', recipe('generated.sv', True))
                assert 'Induction step proven: SUCCESS!' in log
                assert re.search(r'Base case for induction length \d+ proven\.', log)
                text = raw.decode()
                anchor = 'decoded_address=codes_base+tile_offset;'
                assert text.count(anchor) == 1
                mutant = text.replace(anchor, "decoded_address=(codes_base+tile_offset) ^ 32'd32;")
                (directory / 'mutant.sv').write_text(mutant)
                broken_log, broken = run_yosys(tool, env, directory, 'mutant', recipe('mutant.sv', False))
                assert 'SAT proof finished - model found: FAIL!' in broken_log
                assert (directory / 'counterexample.json').is_file()
                row.update(result='initial-reset-inductive-module-output-equivalence', proof=proof,
                           compiling_mutant_counterexample=broken, witness=witness(broken_log))
            checked(root, profile['released_source'], profile['released_identity'])
            checked(HERE, profile['config'], profile['config_identity'])
            rows.append(row)
            print(json.dumps({'model': name, 'result': row['result']}), flush=True)
        assert len(rows) == 2
        assert all(identity(path) == pin for path, pin in originals.items())
        assert identity(Path(tool_record['binary'])) == tool_record['identity']
        checked(root, source['generator_source'], source['generator_identity'])
        checked(root, source['geometry_source'], source['geometry_identity'])
        result = {'passed': True, 'cases': rows, 'tool': tool_record,
                  'source_manifest': identity(HERE / 'SOURCE.json'), 'runner': identity(Path(__file__)),
                  'released_sources_unchanged': True, 'seconds': time.monotonic() - started,
                  'scope': 'Decoder source reuse; no complete FPGA build or physical qualification'}
        save(out / 'RESULT.json', result)
        print(json.dumps({'passed': True, 'cases': 2, 'released_sources_unchanged': True}, indent=2))
    except Exception as error:
        save(out / 'FAILURE.json', {'passed': False, 'error': str(error)})
        raise


if __name__ == '__main__':
    main()
