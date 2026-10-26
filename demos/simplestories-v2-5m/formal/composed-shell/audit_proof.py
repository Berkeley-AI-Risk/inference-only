"""Re-elaborate and audit the exact composed public-shell proof and its seams."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

assert sys.flags.isolated and sys.flags.no_site and sys.flags.dont_write_bytecode
assert not sys.flags.optimize
ROOT = Path(__file__).resolve().parent
TOP = 'board1_public_shell_composition'
SHELL = 'u_machine.u_token_shell.'


def sha(path):
    assert path.is_file() and not path.is_symlink(), path
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text())


def put(path, value):
    with path.open('x') as stream:
        stream.write(json.dumps(value, indent=2, sort_keys=True) + '\n')


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


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


def formula(smt, initial, conclusion=None):
    rows = ['(set-option :produce-models true)', '(set-option :timeout 180000)', smt]
    for i in range(3):
        rows += [f'(declare-fun s{i} () {TOP}_s)', f'(assert ({TOP}_h s{i}))',
                 f'(assert ({TOP}_u s{i}))', f'(assert (= ({TOP}_is s{i}) {"true" if initial and i == 0 else "false"}))']
        if i:
            rows.append(f'(assert ({TOP}_t s{i-1} s{i}))')
    if initial:
        rows += [f'(assert ({TOP}_i s0))', f'(assert (not (|{TOP}_n reset_n_i| s0)))',
                 f'(assert (not (|{TOP}_n reset_n_i| s1)))', '(check-sat)',
                 f'(assert (not (and ({TOP}_a s0) ({TOP}_a s1) ({TOP}_a s2))))']
    else:
        term = f'({TOP}_a s2)' if conclusion is None else f'(|{TOP}_a {conclusion}| s2)'
        rows += [f'(assert ({TOP}_a s0))', f'(assert ({TOP}_a s1))', f'(assert (not {term}))']
    return '\n'.join(rows + ['(check-sat)']) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', required=True, type=Path)
    parser.add_argument('--proof', required=True, type=Path)
    parser.add_argument('--traces', required=True, type=Path)
    parser.add_argument('--yosys', default='yosys')
    parser.add_argument('--extra-check', type=Path, action='append', default=[])
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    run, proof, traces = args.run.absolute(), args.proof.absolute(), args.traces.absolute()
    anchor = Path(os.path.commonpath([ROOT, run, proof, traces] + [p.absolute() for p in args.extra_check]))
    checked = {}

    def bound(path, digest=None):
        value = sha(path)
        if digest is not None:
            assert value == digest, path
        checked[str(path.relative_to(anchor))] = value
        return path.read_bytes()

    driver = load('audited_composition_derivation', ROOT / 'run_proof.py')
    sources, _, binding = driver.derive()
    inputs = json.loads(bound(proof / 'INPUTS.json'))
    result = json.loads(bound(proof / 'FINISHED.json'))
    assert result['passed'] and result['assertions'] == 134 and result['input_hashes_unchanged']
    assert result['inputs_sha256'] == sha(proof / 'INPUTS.json') and inputs['induction_length'] == 2
    assert {k: inputs[k] for k in binding} == json.loads(json.dumps(binding))
    for name, row in inputs['files'].items():
        assert len(bound(proof / name, row['sha256'])) == row['bytes']
    assert bound(ROOT / 'run_proof.py') == (proof / 'runner.py').read_bytes()
    for name, data in sources.items():
        assert (proof / name).read_bytes() == data, name
    # Independently undo every permitted production-core instrumentation edit.
    # This checks the actual source, rather than accepting a prose cut list.
    original = (proof / 'production_core.sv').read_text()
    core_path = driver.MACHINE_DIR + driver.CORE_NAME + '.sv'
    restored = sources[core_path].decode().removeprefix('`undef FORMAL\n')
    monitor = bound(ROOT / 'core_monitor.inc.sv').decode()
    assert restored.count('\n' + monitor + '\nendmodule') == 1
    restored = restored.replace('\n' + monitor + '\nendmodule', '\nendmodule')
    links = binding['read_only_connection_observers']
    for name, shape in links['core'].items():
        declaration = ',\n    output wire ' + shape + 'f_link_' + name + '_o'
        assignment = '    assign f_link_' + name + '_o = ' + name + ';'
        assert restored.count(declaration) == restored.count(assignment) == 1
        restored = restored.replace(declaration, '').replace(assignment, '')
    shell_instance, _ = driver.instance(original, driver.SHELL_NAME, 'u_token_shell')
    observed_instance, observed_bindings = driver.instance(restored, driver.SHELL_NAME, 'u_token_shell')
    _, ordinary_bindings = driver.instance(original, driver.SHELL_NAME, 'u_token_shell')
    assert observed_bindings == dict(ordinary_bindings, **{'f_link_' + n + '_o': 'f_shell_' + n for n in links['shell']})
    restored = restored.replace(observed_instance, shell_instance)
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
    # Instrumentation adds blank lines only beyond the exact reversals above.
    assert [s for s in restored.splitlines() if s.strip()] == [s for s in original.splitlines() if s.strip()]
    if not args.verify_only:
        run.mkdir(parents=True, exist_ok=False)
        (run / 'auditor.py').write_bytes(Path(__file__).read_bytes())
        replay = run / 'elaboration-replay'
        replay.mkdir()
        for name in inputs['files']:
            target = replay / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((proof / name).read_bytes())
        with (replay / 'yosys.log').open('x') as log:
            code = subprocess.run([shutil.which(args.yosys), '-Q', 'prove.ys'], cwd=replay, stdout=log, stderr=subprocess.STDOUT).returncode
        assert code == 0
    replay = run / 'elaboration-replay'
    for name in ('design.smt2', 'elaborated.json', 'elaborated.il'):
        assert bound(proof / name) == (replay / name).read_bytes(), name
    design = read(replay / 'elaborated.json')
    assert set(design['modules']) == {TOP}
    module = design['modules'][TOP]
    types = [row['type'] for row in module['cells'].values()]
    assert types.count('$assert') == 134 and types.count('$anyconst') == 1
    assert not {'$assume', '$anyseq', '$blackbox'} & set(types)
    assert all(t.startswith('$') for t in types)
    expected_ports = {}
    for name, (direction, shape) in binding['wrapper_ports'].items():
        dims = re.fullmatch(r'(?:signed\s+)?\[(\d+)(?:-(\d+))?:(\d+)\]\s*', shape)
        assert dims or not shape, (name, shape)
        width = abs(int(dims[1]) - int(dims[2] or 0) - int(dims[3])) + 1 if dims else 1
        expected_ports[name] = [direction, width]
    assert {n: [r['direction'], len(r['bits'])] for n, r in module['ports'].items()} == expected_ports
    cone = observer_cone(module)
    memories = {n: {'width': int(c['parameters']['WIDTH'], 2), 'size': int(c['parameters']['SIZE'], 2)}
                for n, c in module['cells'].items() if c['type'] == '$mem_v2'}
    assert len(memories) == 17 and memories[SHELL + 'token_tape_q'] == {'width': 12, 'size': 2049}
    assert set(module['cells'][SHELL + 'token_tape_q']['parameters']['INIT']) == {'x'}
    norm = module['cells'][SHELL + 'u_final_rmsnorm.u_norm_rom.norm_rom']['parameters']
    rom = next(n for n in inputs['files'] if n.endswith('/norm_rom34.memh'))
    words = [int(word, 16) for word in (proof / rom).read_text().split()]
    assert len(words) == 3328 and len(norm['INIT']) == 34 * len(words)
    for i, word in enumerate(words):
        lo = len(norm['INIT']) - 34 * (i + 1)
        assert int(norm['INIT'][lo:lo + 34], 2) == word
    smt = (replay / 'design.smt2').read_text()
    assert len(re.findall(r'^; yosys-smt2-assert ', smt, re.M)) == 134
    assert '; yosys-smt2-assume ' not in smt
    for phase, row in result['solver_results'].items():
        assert row['passed'] and row['exit'] == 0
        assert bound(proof / (phase + '.smt2'), row['query_sha256']).decode() == formula(smt, phase == 'base')
        assert bound(proof / (phase + '.log'), row['log_sha256']).decode().splitlines() == (['sat', 'unsat'] if phase == 'base' else ['unsat'])
    ti, tr = json.loads(bound(traces / 'INPUTS.json')), json.loads(bound(traces / 'FINISHED.json'))
    assert tr['passed'] and tr['inputs_sha256'] == sha(traces / 'INPUTS.json') and len(tr['jobs']) == 6
    assert bound(traces / 'deriver.py') == (proof / 'runner.py').read_bytes()
    assert bound(traces / 'checker.py') == bound(ROOT / 'check_traces.py')
    assert bound(traces / 'tb_body.sv') == bound(ROOT / 'tb_body.sv')
    for label, row in tr['jobs'].items():
        assert row['passed'] and row['compile_exit'] == 0 and row['source_unchanged']
        inventory = ti['jobs'][label]
        for name, digest in inventory['files'].items():
            data = bound(traces / label / name, digest)
            if name in sources:
                expected = sources[name]
                mutation = inventory['mutation']
                if mutation and name == mutation[0]:
                    assert expected.count(mutation[1].encode()) == 1
                    expected = expected.replace(mutation[1].encode(), mutation[2].encode())
                assert data == expected, (label, name)
        bound(traces / label / 'compile.log', row['compile_log_sha256'])
        log = bound(traces / label / 'trace.log', row['trace_log_sha256']).decode()
        assert 'GLOBAL_TIMEOUT' not in log
        if label == 'actual':
            assert row['trace_exit'] == 0 and log.count('PASS_PUBLIC_SHELL cases=13 serial_bytes=60 operations=7 cpb=217') == 1
        else:
            assert row['trace_exit'] not in (0, 124) and inventory['expected_error'] in log and 'PASS_PUBLIC_SHELL' not in log
    conclusions, second_base = set(), False
    secondary = [p.absolute() for p in args.extra_check]
    for location in secondary:
        ci, cr = json.loads(bound(location / 'INPUTS.json')), json.loads(bound(location / 'FINISHED.json'))
        assert ci['proof_inputs_sha256'] == sha(proof / 'INPUTS.json')
        for name, row in cr['jobs'].items():
            query = bound(location / (name + '.smt2'), row['query_sha256']).decode()
            log = bound(location / (name + '.log'), row['log_sha256']).decode()
            normalized = re.sub(r'^\(set-(?:logic|option) [^\n]+\)\n', '', query, flags=re.M)
            index = None if name == 'base' else int(name.split('-')[-1])
            expected = formula(smt, name == 'base', index)
            expected = re.sub(r'^\(set-(?:logic|option) [^\n]+\)\n', '', expected, flags=re.M)
            if name == 'base':
                expected = expected.replace('(check-sat)\n', '', 1)
            assert normalized == expected, name
            if row['passed']:
                assert row['exit'] == 0 and row['answers'] == ['unsat'] and log.splitlines() == ['unsat']
                if name == 'base':
                    second_base = True
                else:
                    conclusions.add(index)
            else:
                assert row['answers'] != ['unsat'] or row['exit'] != 0
    complete = second_base and conclusions == set(range(134))
    receipt = {'source_structure_audit_passed': True, 'complete_second_solver': complete,
        'second_solver_conclusions': sorted(conclusions), 'second_solver_base': second_base,
        'checked_sha256': checked, 'replayed_elaboration': True, 'assertions': 134, 'memories': memories,
        'observer_cone': cone, 'private_output_cuts': binding['private_semantic_output_cuts'],
        'core_instrumentation_reversed_to_production': True, 'thirteen_serial_scenarios': True,
        'five_faulty_controls_detected': True, 'hardware_access': False, 'whole_machine_refinement': False,
        'scope': 'Exact-image source/cut/observer/ROM/query/raw-result audit of the composed UART/adapter/core/token-shell safety lemma. Excludes transformer numerical/private-memory/physical refinement. No independent reviewer.'}
    receipt = json.loads(json.dumps(receipt))
    if args.verify_only:
        assert read(run / 'FINISHED.json') == receipt and (run / 'auditor.py').read_bytes() == Path(__file__).read_bytes()
    else:
        put(run / 'FINISHED.json', receipt)
    print(json.dumps({'source_structure_audit_passed': True, 'complete_second_solver': complete,
                      'second_solver_conclusions': len(conclusions), 'hardware_access': False}), flush=True)


if __name__ == '__main__':
    main()
