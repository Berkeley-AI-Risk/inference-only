"""Independently reconstruct component derivation, query and observer boundaries.

Fresh Yosys replay must be byte-identical. This audits recorded results without
changing their solver status, and rejects production feedback from observers.
"""
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


def sha(raw): return hashlib.sha256(raw).hexdigest()
def bitset(values): return {bit for bit in values if isinstance(bit, int)}


def expected_recipe(sources, top, count, observers):
    commands = ['read_verilog -formal -sv -nosynthesis -D SYNTHESIS -defer ' + ' '.join(sources),
        f'prep -top {top} -flatten', 'async2sync', 'chformal -lower', 'opt_clean', 'dffunmap',
        f'select -assert-count {count} t:$assert', 'select -assert-none t:$assume',
        'select -assert-none t:$anyseq', f'select -assert-count {observers} t:$anyconst',
        'check -assert', 'write_json elaborated.json', 'write_rtlil elaborated.il', 'write_smt2 -wires design.smt2']
    return ('\n'.join(commands) + '\n').encode()


def observer_cone(module, roots, permitted_reads):
    nets, cells = module['netnames'], module['cells']
    selectors = set().union(*(bitset(nets[name]['bits']) for name in roots))
    addresses = {name: bitset(nets[slot]['bits']) for name, slot in permitted_reads.items()}
    edges, sinks, observed = [], set(), []
    for name, cell in cells.items():
        ports = cell['connections']
        if cell['type'] == '$mem_v2':
            params = cell['parameters']
            width, abits, reads = [int(params[key], 2) for key in ('WIDTH', 'ABITS', 'RD_PORTS')]
            writes = set().union(*(bitset(values) for key, values in ports.items() if key.startswith('WR_')))
            sinks |= writes
            edges.append((writes, bitset(ports['RD_DATA'])))
            for index in range(reads):
                address = bitset(ports['RD_ADDR'][abits * index:abits * (index + 1)])
                source = address | set().union(*(bitset([ports[key][index]]) for key in ('RD_CLK', 'RD_EN', 'RD_ARST', 'RD_SRST')))
                target = bitset(ports['RD_DATA'][width * index:width * (index + 1)])
                edges.append((source, target))
                if name in addresses and address == addresses[name]: observed.append(name)
                else: sinks |= source
        else:
            directions = cell['port_directions']
            source = set().union(*(bitset(values) for key, values in ports.items() if directions[key] == 'input'))
            target = set().union(*(bitset(values) for key, values in ports.items() if directions[key] == 'output'))
            edges.append((source, target))
    assert sorted(observed) == sorted(permitted_reads)
    reached = set(selectors)
    while True:
        more = set().union(*(target for source, target in edges if source & reached))
        if more <= reached: break
        reached |= more
    protected = {name: bitset(row['bits']) for name, row in nets.items()
                 if not row['hide_name'] and not name.split('.')[-1].startswith('f_')}
    protected.update({name: bitset(row['bits']) for name, row in module['ports'].items()})
    hits = sorted(name for name, values in protected.items() if values & reached)
    assert not hits and not (sinks & reached), (hits, sorted(sinks & reached))
    return dict(roots=roots, reached_bits=len(reached), read_only_memory_ports=observed,
                production_net_port_or_memory_hits=[])


def canonical_query(smt, top, reset, k, phase):
    initial = phase == 'base'
    parts = ['(set-option :produce-models true)', smt]
    for step in range(k + 1):
        parts += [f'(declare-fun s{step} () {top}_s)', f'(assert ({top}_h s{step}))',
                  f'(assert ({top}_u s{step}))',
                  f'(assert (= ({top}_is s{step}) {"true" if initial and step == 0 else "false"}))']
        if step: parts.append(f'(assert ({top}_t s{step-1} s{step}))')
    if initial:
        parts += [f'(assert ({top}_i s0))', f'(assert (not (|{top}_n {reset}| s0)))',
                  f'(assert (not (|{top}_n {reset}| s1)))', '(check-sat)',
                  '(assert (not (and ' + ' '.join(f'({top}_a s{step})' for step in range(k + 1)) + ')))', '(check-sat)']
    else:
        parts += [f'(assert ({top}_a s{step}))' for step in range(k)]
        parts += [f'(assert (not ({top}_a s{k})))', '(check-sat)']
    return '\n'.join(parts) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--proof', type=Path, required=True)
    parser.add_argument('--run', type=Path, required=True)
    args = parser.parse_args()
    proof, run = args.proof.absolute(), args.run.absolute()
    spec = importlib.util.spec_from_file_location('driver', HERE / 'run_proof.py')
    driver = importlib.util.module_from_spec(spec); spec.loader.exec_module(driver)
    raw = (proof / 'INPUTS.json').read_bytes(); inputs = json.loads(raw)
    finished = json.loads((proof / 'FINISHED.json').read_text())
    assert finished['inputs_sha256'] == sha(raw) and finished['yosys_exit'] == 0
    assert finished['source_files_unchanged'] and finished['assumption_cells'] == 0
    case = inputs['case']
    files, origins, sources, top, reset, count, _ = driver.prepare(case)
    assert origins == inputs['origins']
    assert top == inputs['top'] and reset == inputs['reset'] and count == inputs['assertion_cells_expected']
    assert set(inputs['files']) == set(files) | {'prove.ys', 'runner.py'}
    assert (proof / 'runner.py').read_bytes() == (HERE / 'run_proof.py').read_bytes()
    observers = 1 if case in ('shell', 'selector-buffer') else 0
    assert (proof / 'prove.ys').read_bytes() == expected_recipe(sources, top, count, observers)
    for name, entry in inputs['files'].items():
        data = (proof / name).read_bytes()
        assert len(data) == entry['bytes'] and sha(data) == entry['sha256'], name
    # The historical driver snapshot is itself hash-pinned. Current derivation
    # must reproduce all source and monitor bytes; driver text can gain cases.
    for name, data in files.items(): assert data == (proof / name).read_bytes(), name
    run.mkdir(parents=True, exist_ok=False)
    (run / 'auditor.py').write_bytes(Path(__file__).read_bytes())
    replay = run / 'elaboration-replay'; replay.mkdir()
    for name in inputs['files']:
        target = replay / name; target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes((proof / name).read_bytes())
    with (replay / 'yosys.log').open('w') as stream:
        code = subprocess.run(['yosys', '-Q', 'prove.ys'], cwd=replay, stdout=stream, stderr=subprocess.STDOUT).returncode
    assert code == 0
    artifacts = {}
    for name in ('design.smt2', 'elaborated.json', 'elaborated.il'):
        data = (proof / name).read_bytes()
        assert data == (replay / name).read_bytes(), name
        artifacts[name] = sha(data)
    smt = (proof / 'design.smt2').read_text()
    for label, result in finished['solver_results'].items():
        query = (proof / (label + '.smt2')).read_bytes()
        log = (proof / (label + '.log')).read_bytes()
        assert sha(query) == result['query_sha256'] and sha(log) == result['log_sha256']
        text = re.sub(r'^\(set-(?:option :(?:timeout|tlimit-per) [0-9]+|logic [^)]+)\)\n', '', query.decode(), flags=re.M)
        assert text == canonical_query(smt, top, reset, inputs['induction_length'], label.split('-')[-1])
        answers = [line for line in log.decode().splitlines() if line in ('sat', 'unsat', 'unknown')]
        assert answers == result['answers']
        if result['passed']: assert result['exit'] == 0 and answers == result['expected'] and '(error ' not in log.decode()
    design = json.loads((replay / 'elaborated.json').read_text())
    assert set(design['modules']) == {top}
    module = design['modules'][top]
    types = [row['type'] for row in module['cells'].values()]
    assert types.count('$assert') == count and not {'$assume', '$anyseq', '$blackbox'} & set(types)
    assert all(kind.startswith('$') for kind in types)
    assert types.count('$anyconst') == inputs.get('observer_constants_expected', 0)
    memories = {name: dict(width=int(cell['parameters']['WIDTH'], 2), size=int(cell['parameters']['SIZE'], 2))
                for name, cell in module['cells'].items() if cell['type'] == '$mem_v2'}
    expected_memories = 20 if case == 'shell' else 3 if case.startswith('selector') else 0
    assert len(memories) == expected_memories
    cones = []
    if case == 'shell':
        cones.append(observer_cone(module, ['f_tape_slot'], {'token_tape_q': 'f_tape_slot'}))
    if case == 'selector-buffer':
        cones.append(observer_cone(module, ['f_buffer_slot'], {'logits': 'f_buffer_slot', 'mass': 'f_buffer_slot'}))
        cones.append(observer_cone(module, ['u_original_argmax.f_accepted_rows'], {}))
    roms = {}
    for name, cell in module['cells'].items():
        if cell['type'] != '$mem_v2' or not name.endswith(('exponential', 'norm_rom')): continue
        basename = 'exp_neg_q30.memh' if name.endswith('exponential') else 'norm_rom34.memh'
        native = next(path for path in inputs['files'] if Path(path).name == basename)
        words = [int(word, 16) for word in (proof / native).read_text().split()]
        params = cell['parameters']; width = int(params['WIDTH'], 2)
        assert len(words) == int(params['SIZE'], 2) and len(params['INIT']) == width * len(words)
        for index, word in enumerate(words):
            low = len(params['INIT']) - width * (index + 1)
            assert int(params['INIT'][low:low + width], 2) == word
        roms[name] = dict(words=len(words), width=width, exact_every_word=True)
    row = dict(schema='seeded-component-audit-v1', passed=True, case=case,
        proof_inputs_sha256=sha(raw), proof_finished_sha256=sha((proof / 'FINISHED.json').read_bytes()),
        derivation_reproduced=True, elaboration_byte_identical=True, assertions=count,
        assumption_cells=0, internal_value_or_handshake_cuts=[], actual_memories=memories,
        observer_cones=cones, exact_initialized_roms=roms, replay_artifacts_sha256=artifacts,
        canonical_reset_and_induction_queries=True, solver_status_relabelled=False,
        hardware_access=False, network_access=False, whole_machine_refinement=False)
    (run / 'FINISHED.json').write_text(json.dumps(row, indent=2, sort_keys=True) + '\n')
    print(f'COMPONENT_AUDIT_PASS {case} assertions={count} memories={len(memories)}', flush=True)


if __name__ == '__main__': main()
