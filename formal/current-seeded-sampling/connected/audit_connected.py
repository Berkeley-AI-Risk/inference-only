"""Source reversal, observer-cone, original-memory and elaboration audit."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys

assert sys.flags.isolated and sys.flags.no_site and sys.flags.dont_write_bytecode and not sys.flags.optimize
HERE = Path(__file__).resolve().parent
TOP = 'board1_seeded_shell_composition'
SHELL = 'u_machine.u_token_shell.'

def digest(raw): return hashlib.sha256(raw).hexdigest()
def put(path, row): path.write_text(json.dumps(row, indent=2, sort_keys=True) + '\n')

def observer_cone(module):
    """Conservative transitive dependency closure, including sequential cells.

    Write controls/data influence every memory read. Each read address/control
    influences its own port only. Other cell inputs influence all outputs.
    """
    def bits(values):
        return {bit for bit in values if isinstance(bit, int)}
    cells, nets = module['cells'], module['netnames']
    selector = bits(nets[SHELL + 'f_tape_slot']['bits'])
    constants = [cell for cell in cells.values() if cell['type'] == '$anyconst']
    assert len(constants) == 1 and int(constants[0]['parameters']['WIDTH'], 2) == 12
    assert bits(constants[0]['connections']['Y']) == selector and len(selector) == 12
    edges, sinks = [], set()
    observed_ports = 0
    for name, cell in cells.items():
        ports, directions = cell['connections'], cell['port_directions']
        if cell['type'] == '$mem_v2':
            p = cell['parameters']
            width, abits, reads = [int(p[key], 2) for key in ('WIDTH', 'ABITS', 'RD_PORTS')]
            writes = set().union(*(bits(v) for k, v in ports.items() if k.startswith('WR_')))
            sinks |= writes
            edges.append((name + ':writes', writes, bits(ports['RD_DATA'])))
            for index in range(reads):
                address = bits(ports['RD_ADDR'][abits * index:abits * (index + 1)])
                source = address | set().union(*(bits([ports[key][index]]) for key in ('RD_CLK', 'RD_EN', 'RD_ARST', 'RD_SRST')))
                target = bits(ports['RD_DATA'][width * index:width * (index + 1)])
                edges.append((name + ':read-' + str(index), source, target))
                if name == SHELL + 'token_tape_q' and address == selector:
                    assert target == bits(nets[SHELL + 'f_slot_observed']['bits'])
                    observed_ports += 1
                else:
                    sinks |= source
        else:
            source = set().union(*(bits(v) for k, v in ports.items() if directions[k] == 'input'))
            target = set().union(*(bits(v) for k, v in ports.items() if directions[k] == 'output'))
            edges.append((name, source, target))
    assert observed_ports == 1
    reached = set(selector)
    while True:
        new = set().union(*(target for _, source, target in edges if source & reached))
        if new <= reached:
            break
        reached |= new
    protected = {name: bits(row['bits']) for name, row in nets.items()
                 if not row['hide_name'] and not name.split('.')[-1].startswith('f_')}
    protected.update({name: bits(row['bits']) for name, row in module['ports'].items()})
    hits = [name for name, value in protected.items() if reached & value]
    assert not hits and not (reached & sinks), (hits, sorted(reached & sinks))
    return {'selector_bits': sorted(selector), 'reached_bits': sorted(reached),
            'reached_named_nets': sorted(n for n, row in nets.items() if not row['hide_name'] and reached & bits(row['bits'])),
            'production_net_port_or_memory_hits': [],
            'edges': [{'cell_or_port': n, 'reached_inputs': sorted(a & reached), 'outputs': sorted(b)}
                      for n, a, b in edges if a & reached]}


def original_baseline_binding(driver):
    baseline_path = driver.provider.reference_public_root() / 'formal/composed-shell/run_proof.py'
    assert digest(baseline_path.read_bytes()) == driver.PUBLIC_PINS['formal/composed-shell/run_proof.py']
    baseline_spec = importlib.util.spec_from_file_location('original_baseline_driver', baseline_path)
    baseline_driver = importlib.util.module_from_spec(baseline_spec); baseline_spec.loader.exec_module(baseline_driver)
    _, _, baseline_binding = baseline_driver.derive()
    return baseline_binding


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--proof', type=Path, required=True)
    parser.add_argument('--run', type=Path, required=True)
    args = parser.parse_args()
    proof, run = args.proof.absolute(), args.run.absolute()
    assert HERE.parent in proof.parents and HERE.parent in run.parents
    spec = importlib.util.spec_from_file_location('connected_driver', HERE / 'run_connected.py')
    driver = importlib.util.module_from_spec(spec); spec.loader.exec_module(driver)
    sources, compile_sources, binding = driver.derive()
    inputs_raw = (proof / 'INPUTS.json').read_bytes()
    inputs = json.loads(inputs_raw)
    result = json.loads((proof / 'FINISHED.json').read_text())
    assert result['passed'] and result['assertions'] == 196 and result['input_hashes_unchanged']
    assert result['inputs_sha256'] == digest(inputs_raw) and inputs['induction_length'] == 2
    assert {key: inputs[key] for key in binding} == json.loads(json.dumps(binding))
    expected_extra = {'prove.ys', 'runner.py', 'core-settings-monitor.inc.sv',
                      'connection-settings-monitor.inc.sv', 'baseline-driver.py'}
    assert set(inputs['files']) == set(sources) | expected_extra
    recipe = ['read_verilog -formal -sv -nosynthesis -D SYNTHESIS -defer ' + ' '.join(compile_sources),
        'prep -top ' + TOP + ' -flatten', 'async2sync', 'chformal -lower', 'opt_clean', 'dffunmap',
        'select -assert-count 196 t:$assert', 'select -assert-none t:$assume',
        'select -assert-none t:$anyseq', 'select -assert-count 1 t:$anyconst',
        'check -assert', 'write_json elaborated.json', 'write_rtlil elaborated.il', 'write_smt2 -wires design.smt2']
    assert (proof / 'prove.ys').read_bytes() == ('\n'.join(recipe) + '\n').encode()
    # Independently run the unchanged, hash-pinned baseline derivation and
    # require the entire external port list and private cut mapping to match.
    baseline_binding = original_baseline_binding(driver)
    assert baseline_binding['wrapper_ports'] == binding['wrapper_ports']
    assert baseline_binding['private_semantic_output_cuts'] == binding['private_semantic_output_cuts']
    for name, row in inputs['files'].items():
        raw = (proof / name).read_bytes()
        assert len(raw) == row['bytes'] and digest(raw) == row['sha256'], name
    assert (HERE / 'run_connected.py').read_bytes() == (proof / 'runner.py').read_bytes()
    for name, data in sources.items(): assert (proof / name).read_bytes() == data, name
    # Reverse every instrumentation change, and then require the complete
    # production statements and parameters to match the frozen originals.
    def same_nonblank(a, b):
        assert [line for line in a.splitlines() if line.strip()] == [line for line in b.splitlines() if line.strip()]
    core_path = driver.MACHINE_DIR + driver.CORE_NAME + '.sv'
    original = (proof / 'original' / core_path).read_text()
    restored = sources[core_path].decode().removeprefix('`undef FORMAL\n')
    core_monitor = (proof / 'core-monitor.inc.sv').read_text()
    assert restored.count('\n' + core_monitor + '\nendmodule') == 1
    restored = restored.replace('\n' + core_monitor + '\nendmodule', '\nendmodule')
    links = binding['read_only_connection_observers']
    def remove_links(text, link_shapes):
        for name, shape in link_shapes.items():
            declaration = ',\n    output wire ' + shape + 'f_link_' + name + '_o'
            assignment = '    assign f_link_' + name + '_o = ' + name + ';'
            assert text.count(declaration) == text.count(assignment) == 1
            text = text.replace(declaration, '').replace(assignment, '')
        return text
    restored = remove_links(restored, links['core'])
    original_instance, ordinary_bindings = driver.instance(original, driver.SHELL_NAME, 'u_token_shell')
    observed_instance, observed_bindings = driver.instance(restored, driver.SHELL_NAME, 'u_token_shell')
    assert observed_bindings == dict(ordinary_bindings, **{'f_link_' + name + '_o': 'f_shell_' + name for name in links['shell']})
    restored = restored.replace(observed_instance, original_instance)
    for name, shape in links['shell'].items():
        declaration = '    wire ' + shape + 'f_shell_' + name + ';\n'
        assert restored.count(declaration) == 1
        restored = restored.replace(declaration, '')
    cut_lines = []
    for net, row in binding['private_semantic_output_cuts'].items():
        declaration = ',\n    input wire ' + row['shape'] + row['verification_input']
        assert restored.count(declaration) == 1
        restored = restored.replace(declaration, '')
        cut_lines.append('    assign ' + net + ' = ' + row['verification_input'] + ';')
    layer_instance, _ = driver.instance(original, driver.LAYER_NAME, 'u_six_layers')
    assert restored.count('\n'.join(cut_lines)) == 1 and len(cut_lines) == 37
    restored = restored.replace('\n'.join(cut_lines), layer_instance)
    same_nonblank(restored, original)
    instrumented = {core_path}
    shell_path = driver.MACHINE_DIR + driver.SHELL_NAME + '.sv'
    shell = sources[shell_path].decode().removeprefix('`undef FORMAL\n')
    monitor = (proof / 'shell-monitor.inc.sv').read_text()
    assert shell.count('\n' + monitor + '\nendmodule') == 1
    shell = shell.replace('\n' + monitor + '\nendmodule', '\nendmodule')
    shell = remove_links(shell, links['shell'])
    same_nonblank(shell, (proof / 'original' / shell_path).read_text())
    instrumented.add(shell_path)
    for basename, monitor_name in (('board1_seeded_head_selector.sv', 'selector-monitor.inc.sv'),
        ('token_only_model0_uart_bridge.sv', 'uart-monitor.inc.sv')):
        name = next(name for name in binding['transformations'] if Path(name).name == basename)
        text = sources[name].decode().removeprefix('`undef FORMAL\n')
        monitor = (proof / monitor_name).read_text()
        assert text.count('\n' + monitor + '\nendmodule') == 1
        text = text.replace('\n' + monitor + '\nendmodule', '\nendmodule')
        assert text == (proof / 'original' / name).read_text()
        instrumented.add(name)
    for name in binding['transformations']:
        if name not in instrumented:
            assert sources[name] == b'`undef FORMAL\n' + (proof / 'original' / name).read_bytes()
    run.mkdir(parents=True, exist_ok=False)
    (run / 'auditor.py').write_bytes(Path(__file__).read_bytes())
    replay = run / 'elaboration-replay'; replay.mkdir()
    for name in inputs['files']:
        target = replay / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes((proof / name).read_bytes())
    with (replay / 'yosys.log').open('w') as log:
        code = subprocess.run(['yosys', '-Q', 'prove.ys'], cwd=replay, stdout=log, stderr=subprocess.STDOUT).returncode
    assert code == 0
    replay_sha = {}
    for name in ('design.smt2', 'elaborated.json', 'elaborated.il'):
        raw = (proof / name).read_bytes()
        assert raw == (replay / name).read_bytes()
        assert digest(raw) == result['proof_artifacts_sha256'][name]
        replay_sha[name] = digest(raw)
    design = json.loads((replay / 'elaborated.json').read_text())
    assert set(design['modules']) == {TOP}
    module = design['modules'][TOP]
    types = [row['type'] for row in module['cells'].values()]
    assert types.count('$assert') == 196 and types.count('$anyconst') == 1
    assert not {'$assume', '$anyseq', '$blackbox'} & set(types)
    assert all(kind.startswith('$') for kind in types)
    expected_ports = {}
    for name, (direction, shape) in binding['wrapper_ports'].items():
        dims = re.fullmatch(r'(?:signed\s+)?\[(\d+)(?:-(\d+))?:(\d+)\]\s*', shape)
        assert dims or not shape, (name, shape)
        width = abs(int(dims[1]) - int(dims[2] or 0) - int(dims[3])) + 1 if dims else 1
        expected_ports[name] = [direction, width]
    assert {name: [row['direction'], len(row['bits'])] for name, row in module['ports'].items()} == expected_ports
    cone = observer_cone(module)
    memories = {name: {'width': int(cell['parameters']['WIDTH'], 2), 'size': int(cell['parameters']['SIZE'], 2)}
        for name, cell in module['cells'].items() if cell['type'] == '$mem_v2'}
    assert len(memories) == 20 and memories[SHELL + 'token_tape_q'] == {'width': 12, 'size': 2049}
    assert memories[SHELL + 'u_exact_argmax.logits'] == {'width': 52, 'size': 4019}
    assert memories[SHELL + 'u_exact_argmax.mass'] == {'width': 31, 'size': 4019}
    for name in ('token_tape_q', 'u_exact_argmax.logits', 'u_exact_argmax.mass'):
        assert set(module['cells'][SHELL + name]['parameters']['INIT']) == {'x'}
    roms = {}
    for suffix, basename, width, words_expected in (
        ('u_final_rmsnorm.u_norm_rom.norm_rom', 'norm_rom34.memh', 34, 3328),
        ('u_exact_argmax.exponential', 'exp_neg_q30.memh', 32, 4097)):
        params = module['cells'][SHELL + suffix]['parameters']
        native = next(name for name in inputs['files'] if Path(name).name == basename)
        words = [int(word, 16) for word in (proof / native).read_text().split()]
        assert len(words) == words_expected and len(params['INIT']) == width * len(words)
        for index, word in enumerate(words):
            low = len(params['INIT']) - width * (index + 1)
            assert int(params['INIT'][low:low+width], 2) == word
        roms[suffix] = dict(width=width, words=len(words), exact_every_word=True)
    put(run / 'FINISHED.json', dict(schema='seeded-connected-audit-result-v1', passed=True,
        proof_inputs_sha256=digest(inputs_raw), original_source_reversal=True,
        unchanged_parameters=True, exact_baseline_private_output_cuts=37,
        entire_external_port_boundary_identical_to_baseline=True,
        no_extra_cuts=True, assumptions=0, assertion_cells=196, actual_memories=memories,
        observer_cone=cone, exact_initialized_roms=roms, replay_artifacts_sha256=replay_sha,
        hardware_access=False, network_access=False, whole_machine_refinement=False))
    print('CONNECTED_AUDIT_PASS original source reversal; exact elaboration replay; 37 baseline cuts; read-only observer cone; 20 memories; every ROM word', flush=True)
    return 0

if __name__ == '__main__': raise SystemExit(main())
