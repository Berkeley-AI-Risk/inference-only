#!/usr/bin/env python3
"""Offline exact-source controller/tape proof and two-solver sensitivity checks.

No production logic is cut, patched or constrained to ideal arithmetic values.
The only arbitrary constant selects a read-only verification observation slot.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import runpy
import shutil
import subprocess
import sys
import time

assert sys.flags.isolated and sys.flags.dont_write_bytecode and not sys.flags.optimize


def sha(data): return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', required=True, type=Path)
    parser.add_argument('--work', required=True, type=Path)
    parser.add_argument('--yosys', default='yosys')
    parser.add_argument('--z3', default='z3')
    parser.add_argument('--cvc5', default='cvc5')
    args = parser.parse_args()
    package, work = args.package.resolve(strict=True), args.work.resolve()
    assert work != package and not work.is_relative_to(package)
    manifest = json.loads((package / 'MANIFEST.json').read_text())
    def read(relative):
        path = package / relative
        assert not path.is_symlink()
        data = path.read_bytes()
        assert sha(data) == manifest['files'][relative]['sha256'], relative
        assert len(data) == manifest['files'][relative]['bytes'], relative
        return data
    sources = json.loads(read('formal/token-shell/sources.json'))
    for source in sources.values(): assert sha(read(source['package_source'])) == source['sha256']
    formal = package / 'formal/token-shell'
    for name in ('proof_driver.py', 'checks.py', 'observer.py', 'control_monitor.inc.sv', 'tape_monitor.inc.sv'):
        read('formal/token-shell/' + name)
    monitor = read('formal/token-shell/control_monitor.inc.sv') + b'\n' + read('formal/token-shell/tape_monitor.inc.sv')
    assert monitor.count(b'assert(') == 48 and b'assume(' not in monitor
    read('tools/replay_diagnostics.py')
    diagnostics = runpy.run_path(str(package / 'tools/replay_diagnostics.py'))
    work.mkdir(parents=False, exist_ok=False)
    shutil.copyfile(__file__, work / 'wrapper.py')
    python = [sys.executable, '-I', '-B', '-S']
    executions = {}
    def execute(name, argv):
        started = time.monotonic()
        with (work / (name + '.log')).open('w') as log:
            code = subprocess.run(argv, stdout=log, stderr=subprocess.STDOUT).returncode
        executions[name] = {'exit': code, 'seconds': time.monotonic() - started,
                            'log_sha256': sha((work / (name + '.log')).read_bytes())}
        assert code == 0, diagnostics['stage_failure'](
            name, code, work / (name + '.log'), work / 'checks' if name == 'checks' else None)
    proof, checks = work / 'proof', work / 'checks'
    execute('proof', python + [str(formal / 'proof_driver.py'), '--tape', '--run', str(proof),
                              '--yosys', args.yosys, '--z3', args.z3])
    inputs_raw, result_raw = (proof / 'INPUTS.json').read_bytes(), (proof / 'FINISHED.json').read_bytes()
    inputs, result = json.loads(inputs_raw), json.loads(result_raw)
    assert result['passed'] and result['assertion_cells'] == 48 and result['assumption_cells'] == 0
    assert result['observer_constant_cells'] == 1 and result['induction_length'] == 2
    assert inputs['origins'] == sources and inputs['cutpoints'] == []
    assert result['inputs_sha256'] == sha(inputs_raw)
    assert inputs['source_package_sha256'] == sha((package / 'MANIFEST.json').read_bytes())
    for name, row in inputs['files'].items(): assert sha((proof / name).read_bytes()) == row['sha256']
    assert (proof / 'monitor.inc.sv').read_bytes() == monitor
    for name, source in sources.items():
        original, observed = read(source['package_source']), (proof / name).read_bytes()
        if name.endswith('.sv'):
            assert observed.startswith(b'`undef FORMAL\n')
            observed = observed.removeprefix(b'`undef FORMAL\n')
        if name.endswith('/board1_context2048_token_shell.sv'):
            assert observed == original.replace(b'\nendmodule', b'\n' + monitor + b'\nendmodule')
        else: assert observed == original
    design = json.loads((proof / 'elaborated.json').read_text())
    top = 'board1_context2048_token_shell'
    assert set(design['modules']) == {top}
    module = design['modules'][top]
    kinds = [cell['type'] for cell in module['cells'].values()]
    assert kinds.count('$assert') == 48 and '$assume' not in kinds and '$anyseq' not in kinds
    assert kinds.count('$anyconst') == 1 and all(kind.startswith('$') for kind in kinds)
    observer = runpy.run_path(str(formal / 'observer.py'))['observer_cone'](module)
    (work / 'OBSERVER-CONE.json').write_text(json.dumps(observer, indent=2) + '\n')
    memories = {name: cell['parameters'] for name, cell in module['cells'].items() if cell['type'] == '$mem_v2'}
    assert len(memories) == 17
    assert int(memories['token_tape_q']['WIDTH'], 2) == 12 and int(memories['token_tape_q']['SIZE'], 2) == 2049
    assert set(memories['token_tape_q']['INIT']) == {'x'}
    norm = memories['u_final_rmsnorm.u_norm_rom.norm_rom']
    norm_source = next(source for name, source in sources.items() if name.endswith('/norm_rom34.memh'))
    words = [int(word, 16) for word in read(norm_source['package_source']).decode().split()]
    assert len(words) == 3328 and int(norm['WIDTH'], 2) == 34 and len(norm['INIT']) == 3328 * 34
    for index, word in enumerate(words):
        low = len(norm['INIT']) - 34 * (index + 1)
        assert int(norm['INIT'][low:low+34], 2) == word
    smt = (proof / 'design.smt2').read_text()
    labels = re.findall(r'^; yosys-smt2-assert (\d+) ', smt, re.M)
    assert {int(label) for label in labels} == set(range(48)) and len(labels) == 48
    constants = re.findall(r'^; yosys-smt2-anyconst (\S+) (\d+) ([^\n]+)', smt, re.M)
    assert len(constants) == 1 and constants[0][1] == '12' and constants[0][2].endswith(' f_tape_slot')
    constant = constants[0][0]
    assert f'(= (|{constant}| state) (|{constant}| next_state))' in smt.split(f'(define-fun |{top}_t|', 1)[1]
    assert f'(define-fun |{top}_u| ((state |{top}_s|)) Bool true)' in smt
    assert f'(define-fun |{top}_h| ((state |{top}_s|)) Bool true)' in smt
    assert f'|{constant}|' not in smt.split(f'(define-fun |{top}_i|', 1)[1].split(f'(define-fun |{top}_h|', 1)[0]
    for label, row in result['solver_results'].items():
        query = (proof / (label + '.smt2')).read_text()
        log = (proof / (label + '.log')).read_text()
        assert sha(query.encode()) == row['query_sha256'] and sha(log.encode()) == row['log_sha256']
        assert log.splitlines() == (['sat', 'unsat'] if label == 'base' else ['unsat'])
        expected = []
        for step in range(3):
            expected += [f'(declare-fun s{step} () {top}_s)', f'(assert ({top}_h s{step}))',
                         f'(assert ({top}_u s{step}))',
                         f'(assert (= ({top}_is s{step}) {"true" if label == "base" and step == 0 else "false"}))']
            if step: expected.append(f'(assert ({top}_t s{step-1} s{step}))')
        if label == 'base':
            expected += [f'(assert ({top}_i s0))', f'(assert (not (|{top}_n rst_n| s0)))',
                         f'(assert (not (|{top}_n rst_n| s1)))', '(check-sat)',
                         f'(assert (not (and ({top}_a s0) ({top}_a s1) ({top}_a s2))))', '(check-sat)']
        else:
            expected += [f'(assert ({top}_a s0))', f'(assert ({top}_a s1))',
                         f'(assert (not ({top}_a s2)))', '(check-sat)']
        assert query.count(smt) == 1 and query.partition(smt)[2].strip().splitlines() == expected
    execute('checks', python + [str(formal / 'checks.py'), '--proof', str(proof), '--run', str(checks),
                               '--yosys', args.yosys, '--z3', args.z3, '--cvc5', args.cvc5])
    checked = json.loads((checks / 'FINISHED.json').read_text())
    check_inputs = json.loads((checks / 'INPUTS.json').read_text())
    assert checked['passed'] and len(checked['jobs']) == 57
    assert check_inputs['parent_inputs_sha256'] == sha(inputs_raw) and check_inputs['parent_finished_sha256'] == sha(result_raw)
    assert {entry['assertion'] for entry in check_inputs['jobs'].values() if 'assertion' in entry} == set(range(48))
    for name, entry in check_inputs['jobs'].items():
        row = checked['jobs'][name]
        assert row['passed'] and row['answers'] == entry['expected']
        for filename, digest in entry['files'].items(): assert sha((checks / name / filename).read_bytes()) == digest
        query, log = (checks / name / 'query.smt2').read_text(), (checks / name / 'solver.log').read_text()
        assert sha(query.encode()) == row['query_sha256'] and sha(log.encode()) == row['log_sha256']
        assert '(error ' not in log
        if name.startswith('cvc5-'):
            primary = (proof / ('base.smt2' if name == 'cvc5-base' else 'induction.smt2')).read_text()
            expected = '(set-logic QF_AUFBV)\n' + primary.replace('(set-option :timeout 120000)', '(set-option :tlimit-per 30000)')
            if name != 'cvc5-base':
                expected = expected.replace(f'(assert (not ({top}_a s2)))', f'(assert (not (|{top}_a {entry["assertion"]}| s2)))')
            assert query == expected
    finished = {'passed': True, 'assertions': 48, 'new_tape_assertions': 13, 'assumption_cells': 0,
                'symbolic_observer_constants': 1, 'observer_drives_production': False,
                'proof_and_complete_second_solver_passed': True, 'tape_mutants_detected': 5,
                'reset_clear_reuse_witnesses': 2, 'actual_memories': 17, 'norm_rom_words_compared': 3328,
                'observer_cone_sha256': sha((work / 'OBSERVER-CONE.json').read_bytes()),
                'executions': executions, 'proof_finished_sha256': sha(result_raw),
                'checks_finished_sha256': sha((checks / 'FINISHED.json').read_bytes()),
                'hardware_access': False, 'network_access': False, 'whole_machine_refinement': False,
                'scope': 'Controller/tape component only. No numerical next-token, K/V/scratch erasure, liveness, UART composition or netlist/bitstream correspondence proof.'}
    (work / 'FINISHED.json').write_text(json.dumps(finished, indent=2) + '\n')
    print('TOKEN_SHELL_REPLAY_FINISHED passed=True', flush=True)
    return 0


if __name__ == '__main__': raise SystemExit(main())
