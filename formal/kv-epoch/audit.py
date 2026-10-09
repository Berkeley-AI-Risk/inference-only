"""Fresh source/elaboration/query/observer audit of the local K/V epoch proof."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess


def sha(data): return hashlib.sha256(data).hexdigest()


def observer_cone(module):
    def bits(values): return {bit for bit in values if isinstance(bit, int)}
    cells, nets = module['cells'], module['netnames']
    selector = bits(nets['f_coordinate']['bits'])
    constants = [cell for cell in cells.values() if cell['type'] == '$anyconst']
    assert len(constants) == 1 and int(constants[0]['parameters']['WIDTH'], 2) == 7
    assert bits(constants[0]['connections']['Y']) == selector and len(selector) == 7
    edges = []
    memory_sinks = set()
    for name, cell in cells.items():
        ports, directions = cell['connections'], cell['port_directions']
        if cell['type'] == '$mem_v2':
            params = cell['parameters']
            width, abits, reads = (int(params[key], 2) for key in ('WIDTH', 'ABITS', 'RD_PORTS'))
            writes = set().union(*(bits(value) for port, value in ports.items() if port.startswith('WR_')))
            memory_sinks |= writes
            edges.append((name + ':all-writes', writes, bits(ports['RD_DATA'])))
            for index in range(reads):
                inputs = bits(ports['RD_ADDR'][abits*index:abits*(index+1)]) | set().union(*(
                    bits([ports[port][index]]) for port in ('RD_CLK', 'RD_EN', 'RD_ARST', 'RD_SRST')))
                outputs = bits(ports['RD_DATA'][width*index:width*(index+1)])
                memory_sinks |= inputs
                edges.append((name + ':read-' + str(index), inputs, outputs))
        else:
            inputs = set().union(*(bits(value) for port, value in ports.items() if directions[port] == 'input'))
            outputs = set().union(*(bits(value) for port, value in ports.items() if directions[port] == 'output'))
            edges.append((name, inputs, outputs))
    reached = set(selector)
    while True:
        new = set().union(*(outputs for _, inputs, outputs in edges if reached & inputs))
        if new <= reached: break
        reached |= new
    protected = {name: bits(row['bits']) for name, row in nets.items()
                 if not row['hide_name'] and not name.startswith('f_')}
    protected.update({name: bits(row['bits']) for name, row in module['ports'].items()})
    hits = [name for name, value in protected.items() if reached & value]
    assert not hits and not (reached & memory_sinks), hits
    return {'selector_bits': sorted(selector), 'reached_bits': sorted(reached),
            'complete_reached_edges': [{'cell_or_memory_port': name, 'reached_inputs': sorted(inputs & reached),
                                       'outputs': sorted(outputs)} for name, inputs, outputs in edges if inputs & reached],
            'reached_visible_nets': [name for name, row in nets.items() if not row['hide_name'] and bits(row['bits']) & reached],
            'production_named_net_or_port_hits': hits, 'production_memory_sink_hits': []}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--run', required=True, type=Path)
    parser.add_argument('--proof', required=True, type=Path)
    parser.add_argument('--checks', required=True, type=Path)
    parser.add_argument('--package', required=True, type=Path)
    parser.add_argument('--yosys', default='yosys')
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    here = Path(__file__).absolute().parent
    root = Path(os.path.commonpath([args.package.absolute(), args.proof.absolute(), args.checks.absolute(), args.run.absolute()]))
    run = args.run.absolute()
    if args.verify_only:
        receipt = json.loads((run / 'FINISHED.json').read_text())
        assert receipt['audit_passed']
        for name, digest in receipt['checked_sha256'].items():
            assert sha((root / name).read_bytes()) == digest, name
        for name, digest in receipt['audit_outputs_sha256'].items():
            assert sha((run / name).read_bytes()) == digest, name
        print('KV_EPOCH_AUDIT_VERIFY_ONLY PASS')
        return
    proof, checks = args.proof.absolute(), args.checks.absolute()
    package = args.package.absolute()
    checked = {}
    def read(path, expected=None):
        assert not path.is_symlink(), path
        data = path.read_bytes()
        digest = sha(data)
        if expected is not None: assert digest == expected, path
        checked[str(path.relative_to(root))] = digest
        return data
    raw_inputs = read(proof / 'INPUTS.json')
    raw_finished = read(proof / 'FINISHED.json')
    inputs, finished = json.loads(raw_inputs), json.loads(raw_finished)
    assert finished['passed'] and finished['assertions'] == 59 and inputs['cutpoints'] == []
    assert inputs['induction_length'] == 2 and inputs['split_induction']
    assert finished['inputs_sha256'] == sha(raw_inputs)
    manifest = json.loads(read(package / 'MANIFEST.json', inputs['source_package_sha256']))['files']
    for name, row in inputs['files'].items(): assert len(read(proof / name, row['sha256'])) == row['bytes']
    monitor = read(proof / 'monitor.inc.sv', '8efd16d62e4135dd7243bb38bd14f66b641ce9a61794821f8f33ae23a6c6cace')
    assert monitor.count(b'assert(') == 59 and b'assume(' not in monitor
    # Remove balanced assert(...) expressions before checking nonblocking
    # assignment targets, so comparison <= is not mistaken for a write.
    clean = re.sub(r'//[^\n]*', '', monitor.decode())
    while 'assert(' in clean:
        begin = clean.index('assert(')
        end, depth = begin + len('assert('), 1
        while depth:
            depth += (clean[end] == '(') - (clean[end] == ')')
            end += 1
        clean = clean[:begin] + clean[end:]
    assignments = re.findall(r'\b(\w+)\s*(?:\[[^;]*?\])?\s*<=', clean)
    assert assignments and all(name.startswith('f_') for name in assignments), assignments
    for name, origin in inputs['origins'].items():
        original = read(package / origin['package_source'], origin['sha256'])
        assert origin['sha256'] == manifest[origin['package_source']]['sha256']
        observed = read(proof / name).removeprefix(b'`undef FORMAL\n')
        if name.startswith('board1_'):
            assert read(proof / 'production.sv') == original
            assert observed == original.replace(b'\nendmodule', b'\n' + monitor + b'\nendmodule')
        else: assert observed == original
    run.mkdir(parents=True, exist_ok=False)
    (run / 'auditor.py').write_bytes(Path(__file__).read_bytes())
    replay = run / 'elaboration-replay'
    replay.mkdir()
    for name in inputs['files']: (replay / name).write_bytes((proof / name).read_bytes())
    with (replay / 'yosys.log').open('w') as output:
        code = subprocess.run([shutil.which(args.yosys), '-Q', 'prove.ys'], cwd=replay,
                              stdout=output, stderr=subprocess.STDOUT).returncode
    assert code == 0
    for name in ('design.smt2', 'elaborated.json', 'elaborated.il'):
        assert read(proof / name) == (replay / name).read_bytes(), name
    top = 'board1_context2048_atomic_kv_typed'
    design = json.loads((replay / 'elaborated.json').read_text())
    assert set(design['modules']) == {top}
    module = design['modules'][top]
    kinds = [cell['type'] for cell in module['cells'].values()]
    assert kinds.count('$assert') == 59 and kinds.count('$anyconst') == 1
    assert '$assume' not in kinds and '$anyseq' not in kinds and all(kind.startswith('$') for kind in kinds)
    cone = observer_cone(module)
    (run / 'OBSERVER-CONE.json').write_text(json.dumps(cone, indent=2) + '\n')
    initialized = set()
    for row in module['netnames'].values():
        if 'init' in row['attributes']:
            initialized |= {bit for bit, value in zip(row['bits'], row['attributes']['init'][::-1]) if value in '01'}
    unreset = {}
    for name in ('staged_key_head0_q', 'staged_key_head1_q', 'staged_value_head0_q', 'staged_value_head1_q', 'assembled_row_q'):
        row = module['netnames'][name]
        assert not (set(row['bits']) & initialized), name
        unreset[name] = len(row['bits'])
    assert list(unreset.values()) == [1024, 1024, 1024, 1024, 2064]
    smt = (replay / 'design.smt2').read_text()
    constants = re.findall(r'^; yosys-smt2-anyconst (\S+) (\d+) ([^\n]+)', smt, re.M)
    assert len(constants) == 1 and constants[0][1] == '7' and constants[0][2].endswith(' f_coordinate')
    constant = constants[0][0]
    transition = smt.split(f'(define-fun |{top}_t|', 1)[1]
    assert f'(= (|{constant}| state) (|{constant}| next_state))' in transition
    for suffix in ('h', 'u'): assert f'(define-fun |{top}_{suffix}| ((state |{top}_s|)) Bool true)' in smt
    initial = smt.split(f'(define-fun |{top}_i|', 1)[1].split(f'(define-fun |{top}_h|', 1)[0]
    assert f'|{constant}|' not in initial
    expected_labels = {'base'} | {f'induction-{i:02d}' for i in range(59)}
    assert set(finished['solver_results']) == expected_labels
    for label, row in finished['solver_results'].items():
        assert row['passed'] and row['exit'] == 0
        query = read(proof / (label + '.smt2'), row['query_sha256']).decode()
        log = read(proof / (label + '.log'), row['log_sha256']).decode().splitlines()
        assert log == (['sat', 'unsat'] if label == 'base' else ['unsat'])
        assert query.count(smt) == 1
        assert query.partition(smt)[0] == '(set-option :produce-models true)\n(set-option :timeout 120000)\n'
        expected = []
        for step in range(3):
            expected += [f'(declare-fun s{step} () {top}_s)', f'(assert ({top}_h s{step}))',
                         f'(assert ({top}_u s{step}))',
                         f'(assert (= ({top}_is s{step}) {"true" if label == "base" and step == 0 else "false"}))']
            if step: expected.append(f'(assert ({top}_t s{step-1} s{step}))')
        if label == 'base':
            expected += [f'(assert ({top}_i s0))', f'(assert (not (|{top}_n reset_n| s0)))',
                         f'(assert (not (|{top}_n reset_n| s1)))', '(check-sat)',
                         f'(assert (not (and ({top}_a s0) ({top}_a s1) ({top}_a s2))))', '(check-sat)']
        else:
            index = int(label.split('-')[-1])
            expected += [f'(assert ({top}_a s0))', f'(assert ({top}_a s1))',
                         f'(assert (not (|{top}_a {index}| s2)))', '(check-sat)']
        assert query.partition(smt)[2].strip().splitlines() == expected, label
    check_inputs_raw = read(checks / 'INPUTS.json')
    check_inputs = json.loads(check_inputs_raw)
    check_finished = json.loads(read(checks / 'FINISHED.json'))
    assert check_finished['passed'] and check_finished['inputs_sha256'] == sha(check_inputs_raw)
    assert check_inputs['parent_inputs_sha256'] == sha(raw_inputs)
    assert check_inputs['parent_finished_sha256'] == sha(raw_finished)
    assert len(check_finished['jobs']) == 68 and set(check_finished['jobs']) == set(check_inputs['jobs'])
    for label, row in check_finished['jobs'].items():
        assert row['passed'] and row['exit'] == 0 and row['source_unchanged']
        job = checks / label
        entry = check_inputs['jobs'][label]
        for name, digest in entry['files'].items(): read(job / name, digest)
        query = read(job / 'query.smt2', row['query_sha256']).decode()
        log = read(job / 'solver.log', row['log_sha256']).decode()
        assert [line for line in log.splitlines() if line in ('sat', 'unsat', 'unknown')] == entry['expected']
        assert '(error ' not in log
        if label.startswith('cvc5-'):
            primary = (proof / (label.removeprefix('cvc5-') + '.smt2')).read_text()
            assert query == '(set-logic QF_AUFBV)\n' + primary.replace('(set-option :timeout 120000)', '(set-option :tlimit-per 120000)')
        elif label.startswith('cover-'):
            assert query.count(smt) == 1 and entry['expected'] == ['sat']
        else:
            assert (job / 'board1_context2048_atomic_kv_typed_clear_consistent.sv').read_text().count(monitor.decode()) == 1
            assert entry['expected'] == (['sat', 'unsat'] if label == 'actual-bmc' else ['sat', 'sat'])
    outputs = {str(path.relative_to(run)): sha(path.read_bytes()) for path in run.rglob('*') if path.is_file()}
    receipt = {'audit_passed': True, 'checked_sha256': checked, 'audit_outputs_sha256': outputs,
               'assertions': 59, 'assumption_cells': 0, 'observer_width': 7, 'observer_drives_production': False,
               'unreset_production_storage_bits': unreset, 'second_solver_all_60_queries_passed': True,
               'reset_reachable_faulty_controls_detected': 5, 'retained_staging_reuse_witnesses': 2,
               'hardware_access': False, 'network_access': False,
               'scope': 'Exact sources and fresh elaboration; no-input-cut local K/V safety induction, second solver, bounded sensitivity and observer fanout. Not whole-machine refinement, external DDR contents, liveness or mapped implementation.'}
    (run / 'FINISHED.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print('KV_EPOCH_AUDIT PASS')


if __name__ == '__main__': main()
