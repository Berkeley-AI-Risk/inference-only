"""Check actual released handoff RTL with Yosys SMTBMC, BMC and k-induction.

No source mutation is applied to the qualified release. Deliberately faulty
controls are separate generated inputs and must produce a BMC counterexample.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import time

HERE = Path(__file__).resolve().parent
DEFAULT_PACKAGE = HERE.parents[1] / 'fpga-demo/public-release'


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def safe(root, relative):
    parts = PurePosixPath(relative)
    if parts.is_absolute() or '..' in parts.parts or '\\' in relative:
        raise ValueError('Unsafe source path: ' + relative)
    path = root
    for part in parts.parts:
        path = path / part
        if path.is_symlink():
            raise ValueError('Symlink input: ' + relative)
    if not path.is_file():
        raise ValueError('Missing source: ' + relative)
    return path


def model_package(package):
    """Resolve the model namespace without changing recorded logical paths."""
    package = Path(package).resolve(strict=True)
    name = 'demos/simplestories-v2-5m/MANIFEST.json'
    if (package / name).is_file():
        manifest = safe(package, name)
        if json.loads(manifest.read_bytes()).get('model_scope') != 'simplestories-v2-5m':
            raise ValueError('Unexpected relocated model scope')
        return manifest.parent
    return package


def binding(package, variant):
    package = model_package(package)
    pins_raw = (HERE / 'SOURCES.json').read_bytes()
    pin = json.loads(pins_raw)['variants'][variant]
    raw = safe(package, pin['native_inventory']).read_bytes()
    if len(raw) != pin['native_inventory_bytes'] or sha(raw) != pin['native_inventory_sha256']:
        raise ValueError('Selected native inventory changed')
    inventory = json.loads(raw)
    if len(inventory) != pin['native_inputs']:
        raise ValueError('Native input count changed')
    root = package / pin['hardware_root']
    checked = {}
    for name, digest in inventory.items():
        if name in pin['omitted_vendor_inputs']:
            if pin['omitted_vendor_inputs'][name] != digest:
                raise ValueError('Omitted vendor provenance changed')
            continue
        data = safe(root, name).read_bytes()
        if sha(data) != digest:
            raise ValueError('Distributed source changed: ' + name)
        checked[name] = digest
    image = safe(package, pin['image']).read_bytes()
    if len(image) != pin['image_bytes'] or sha(image) != pin['image_sha256']:
        raise ValueError('Selected image changed')
    source_list = (root / 'project/production_sources.f').read_text().splitlines()
    if 'handoff.sv' not in source_list or 'booted_memory.sv' not in source_list:
        raise ValueError('Handoff missing from production source list')
    parent = (root / 'project/booted_memory.sv').read_text()
    if parent.count('board1_private_ddr_boot_handoff u_handoff (') != 1:
        raise ValueError('Production handoff instance changed')
    return pin, root, dict(source_pins_sha256=sha(pins_raw),
        distributed_files_verified=len(checked), native_inputs=pin['native_inputs'],
        native_inventory_sha256=pin['native_inventory_sha256'],
        image_sha256=pin['image_sha256'], omitted_vendor_inputs=pin['omitted_vendor_inputs'],
        distributed_inputs=checked)


MUTATIONS = {
    'allow-model-write': (
        '((selected_read && model_address) || kv_address)',
        '(model_address || kv_address)'),
    'return-to-boot': (
        'if(can_switch && quiet_q) runtime_q<=1;',
        'if(can_switch && quiet_q) runtime_q<=1;\n            if(runtime_q && !boot_locked_i) runtime_q<=0;'),
    'forget-fault': (
        'if(terminal_now) fault_o<=1;',
        'if(terminal_now) fault_o<=1; else fault_o<=0;'),
    'bypass-command-check': (
        'assign app_cmd_en_o=selected_en && enabled && !terminal_now;',
        'assign app_cmd_en_o=selected_en && enabled;'),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', type=Path, default=DEFAULT_PACKAGE)
    parser.add_argument('--variant', choices=('baseline', 'kv-protected', 'encrypted-memory', 'seeded-sampling'), required=True)
    parser.add_argument('--run', type=Path, required=True)
    parser.add_argument('--mutant', choices=tuple(MUTATIONS))
    parser.add_argument('--depth', type=int, default=8)
    parser.add_argument('--timeout', type=int, default=90)
    args = parser.parse_args()
    if not 4 <= args.depth <= 32 or not 1 <= args.timeout <= 600:
        parser.error('depth 4..32 and timeout 1..600 required')
    pin, root, bound = binding(args.package.resolve(), args.variant)
    original = (root / 'project/handoff.sv').read_bytes()
    source = original.decode()
    if args.mutant:
        old, new = MUTATIONS[args.mutant]
        if source.count(old) != 1:
            raise ValueError('Mutation site changed')
        source = source.replace(old, new)
    monitor = (HERE / 'handoff-monitor.inc.sv').read_text().replace('__KV_LIMIT__', str(pin['kv_limit']))
    if source.count('\nendmodule') != 1:
        raise ValueError('Module insertion boundary changed')
    source = '`undef FORMAL\n' + source.replace('\nendmodule', '\n' + monitor + '\nendmodule')
    assertions, covers = monitor.count('assert('), monitor.count('cover(')
    if assertions != 21 or covers != 4 or 'assume(' in monitor:
        raise ValueError('Monitor inventory changed')
    run = args.run.absolute()
    run.mkdir(parents=True, exist_ok=False)
    files = {'handoff.sv': source.encode(), 'production-handoff.sv': original,
             'monitor.inc.sv': monitor.encode(), 'runner.py': Path(__file__).read_bytes(),
             'SOURCES.json': (HERE / 'SOURCES.json').read_bytes()}
    top = 'board1_private_ddr_boot_handoff'
    script = '\n'.join([
        'read_verilog -formal -sv -nosynthesis -D SYNTHESIS handoff.sv',
        'prep -top ' + top + ' -flatten', 'async2sync', 'chformal -lower', 'opt_clean',
        'dffunmap', f'select -assert-count {assertions} t:$assert',
        f'select -assert-count {covers} t:$cover', 'select -assert-none t:$assume',
        'select -assert-none t:$anyseq', 'select -assert-none t:$anyconst', 'check -assert',
        'write_json elaborated.json', 'write_rtlil elaborated.il', 'write_smt2 -wires design.smt2',
    ]) + '\n'
    files['prove.ys'] = script.encode()
    # Only reset is constrained, at the two base states. Induction receives
    # no reset assumptions. All request/status/data ports stay arbitrary.
    files['reset.smtc'] = b'initial\nassume (= [reset_n] false)\nstate 1\nassume (= [reset_n] false)\n'
    tools = {}
    for tool in ('yosys', 'yosys-smtbmc', 'z3', 'cvc5'):
        path = shutil.which(tool)
        if not path:
            raise ValueError('Missing tool: ' + tool)
        tools[tool] = dict(path=str(Path(path).resolve()), sha256=sha(Path(path).read_bytes()))
    inputs = dict(schema='current-handoff-implementation-proof-inputs-v1', variant=args.variant,
        mutant=args.mutant, binding=bound, tools=tools, top=top,
        assertion_cells=assertions, cover_cells=covers, assumption_cells=0,
        internal_cuts=[], changed_production_parameters=[], induction_depth=args.depth,
        reset_constraints='base/cover only: reset_n low in states 0 and 1; unrestricted thereafter and throughout induction',
        semantics='two-state clocked digital RTL, simulation-only X detectors excluded; full production watchdog and address dimensions',
        source_to_bitstream_equivalence=False, physical_transport_composed=False,
        claim='Model-region writes blocked at semantic DDR handoff after runtime ownership; one-way epoch and fail-closed command issue.',
        files={name: dict(bytes=len(raw), sha256=sha(raw)) for name, raw in files.items()})
    for name, raw in files.items():
        (run / name).write_bytes(raw)
    (run / 'INPUTS.json').write_text(json.dumps(inputs, indent=2, sort_keys=True) + '\n')
    start = time.monotonic()
    def execute(label, command, expected_status):
        began = time.monotonic()
        timed_out = False
        with (run / (label + '.log')).open('w') as out:
            try:
                result = subprocess.run(command, cwd=run, stdout=out, stderr=subprocess.STDOUT,
                                        timeout=args.timeout + 20)
                code = result.returncode
            except subprocess.TimeoutExpired:
                code, timed_out = None, True
        raw = (run / (label + '.log')).read_bytes()
        output = raw.decode(errors='replace')
        statuses = re.findall(r'Status: (\w+)', output)
        witness = sorted(run.glob(label + '*.yw'))
        passed = (not timed_out and statuses == [expected_status] and
                  code == (1 if expected_status == 'FAILED' else 0) and
                  (expected_status != 'FAILED' or bool(witness)))
        return dict(command=command, exit=code, timed_out=timed_out, status=statuses,
                    passed=passed, seconds=time.monotonic()-began, log_sha256=sha(raw),
                    witnesses={p.name: sha(p.read_bytes()) for p in witness})
    with (run / 'yosys.log').open('w') as out:
        compile_result = subprocess.run(['yosys', '-Q', 'prove.ys'], cwd=run, stdout=out,
                                        stderr=subprocess.STDOUT, timeout=60)
    rows = {}
    if compile_result.returncode == 0:
        design = json.loads((run / 'elaborated.json').read_text())
        cells = [c['type'] for m in design['modules'].values() for c in m.get('cells',{}).values()]
        if cells.count('$assert') != assertions or cells.count('$cover') != covers or '$assume' in cells:
            raise ValueError('Elaborated property inventory changed')
        if any(c in cells for c in ('$mem_v2', '$anyconst', '$anyseq')):
            raise ValueError('Unexpected abstraction cell')
        for solver in ('z3', 'cvc5'):
            for phase in (('bmc',) if args.mutant else ('bmc', 'induction', 'cover')):
                label = solver + '-' + phase
                command = ['yosys-smtbmc', '-s', solver, '--timeout', str(args.timeout),
                           '-t', str(args.depth), '-m', top, '--dump-yw', label + '-%.yw']
                if phase != 'induction':
                    command += ['--smtc', 'reset.smtc', '--presat']
                if phase == 'induction':
                    command += ['-i']
                if phase == 'cover':
                    command += ['-c']
                command += ['design.smt2']
                rows[label] = execute(label, command, 'FAILED' if args.mutant else 'PASSED')
                print(label + ' ' + json.dumps(rows[label]), flush=True)
    unchanged = all(sha((run / name).read_bytes()) == row['sha256'] for name,row in inputs['files'].items())
    passed = compile_result.returncode == 0 and bool(rows) and all(row['passed'] for row in rows.values()) and unchanged
    finished = dict(schema='current-handoff-implementation-proof-result-v1', passed=passed,
        variant=args.variant, mutant=args.mutant, mutation_detected=bool(args.mutant and passed),
        yosys_exit=compile_result.returncode, source_files_unchanged=unchanged,
        assertion_cells=assertions, cover_cells=covers, results=rows,
        inputs_sha256=sha((run/'INPUTS.json').read_bytes()),
        yosys_log_sha256=sha((run/'yosys.log').read_bytes()),
        smt_sha256=sha((run/'design.smt2').read_bytes()) if (run/'design.smt2').exists() else None,
        seconds=time.monotonic()-start, whole_machine_theorem=False,
        physical_transport_composed=False, hardware_access=False)
    (run / 'FINISHED.json').write_text(json.dumps(finished,indent=2,sort_keys=True)+'\n')
    print('FINISHED ' + json.dumps(finished), flush=True)
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
