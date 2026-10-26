"""Fresh source/structure audit and two-solver cross-check of the front-end proof."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

assert sys.flags.isolated and sys.flags.dont_write_bytecode and sys.flags.no_site and not sys.flags.optimize
ROOT = Path(__file__).resolve().parent
TOP = 'board1_public_command_frontend'


def sha(path):
    assert path.is_file() and not path.is_symlink()
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--run', required=True, type=Path)
    parser.add_argument('--proof', required=True, type=Path)
    parser.add_argument('--traces', required=True, type=Path)
    parser.add_argument('--z3', default='z3')
    parser.add_argument('--cvc5', default='cvc5')
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    run = args.run.absolute()
    proof, traces = args.proof.absolute(), args.traces.absolute()
    anchor = Path(os.path.commonpath([ROOT, proof, traces, run]))
    if args.verify_only:
        result = json.loads((run / 'FINISHED.json').read_text())
        assert result['audit_passed'] and sha(run / 'auditor.py') == sha(Path(__file__))
        for name, digest in result['checked_sha256'].items(): assert sha(anchor / name) == digest, name
        for name, row in result['solver_results'].items():
            assert sha(run / (name + '.log')) == row['log_sha256'] and row['passed']
            assert sha(run / (name.split('-', 1)[1] + '.smt2')) == row['query_sha256']
        spec = importlib.util.spec_from_file_location('frontend_reverification', ROOT / 'run_proof.py')
        deriver = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(deriver)
        current, origins, bindings = deriver.sources()
        primary = json.loads((proof / 'INPUTS.json').read_text())
        assert origins == primary['origins'] and bindings == primary['backend_operation_bindings']
        for name, data in current.items(): assert (proof / name).read_bytes() == data
        print('COMMAND_COMPOSITION_AUDIT_VERIFY PASS')
        return
    checked = {}
    def read(path, digest=None):
        identity = sha(path)
        if digest is not None: assert identity == digest, path
        checked[str(path.relative_to(anchor))] = identity
        return path.read_bytes()
    inputs = json.loads(read(proof / 'INPUTS.json'))
    finished = json.loads(read(proof / 'FINISHED.json'))
    assert finished['passed'] and finished['input_hashes_unchanged'] and finished['assertions'] == 60
    assert finished['inputs_sha256'] == sha(proof / 'INPUTS.json')
    for name, row in inputs['files'].items(): read(proof / name, row['sha256'])
    log = read(proof / 'yosys.log', finished['yosys_log_sha256']).decode()
    assert finished['exit'] == 0 and 'Induction step proven: SUCCESS!' in log and 'ERROR:' not in log
    spec = importlib.util.spec_from_file_location('audited_frontend_source_deriver', ROOT / 'run_proof.py')
    derivation = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(derivation)
    source, origins, bindings = derivation.sources()
    assert origins == inputs['origins'] and bindings == inputs['backend_operation_bindings']
    assert read(ROOT / 'run_proof.py') == (proof / 'runner.py').read_bytes()
    assert read(ROOT / 'monitor.inc.sv') == (proof / 'monitor.inc.sv').read_bytes()
    for name, data in source.items(): assert (proof / name).read_bytes() == data
    design = json.loads(read(proof / 'elaborated.json'))
    assert set(design['modules']) == {TOP}
    module = design['modules'][TOP]
    expected_inputs = {'core_clk_i': 1, 'reset_n_i': 1, 'uart_rx_i': 1, 'append_ready': 1,
                       'step_ready': 1, 'token_valid': 1, 'token': 12}
    expected_outputs = {'uart_tx_o': 1, 'append_valid': 1, 'step_valid': 1, 'clear': 1,
                        'token_ready': 1, 'append_token': 12}
    for direction, expected in [('input', expected_inputs), ('output', expected_outputs)]:
        assert {name: len(port['bits']) for name, port in module['ports'].items() if port['direction'] == direction} == expected
    types = [cell['type'] for cell in module['cells'].values()]
    assert types.count('$assert') == 60
    assert not {'$assume', '$anyseq', '$anyconst', '$blackbox'} & set(types)
    smt = read(proof / 'design.smt2').decode()
    assert len(re.findall(r'^; yosys-smt2-assert ', smt, re.M)) == 60
    assert '; yosys-smt2-assume ' not in smt
    trace_inputs = json.loads(read(traces / 'INPUTS.json'))
    trace_result = json.loads(read(traces / 'FINISHED.json'))
    assert trace_result['passed'] and len(trace_result['jobs']) == 6
    assert trace_result['inputs_sha256'] == sha(traces / 'INPUTS.json')
    assert read(traces / 'checker.py', trace_inputs['checker_sha256']) == read(ROOT / 'check_traces.py')
    assert read(traces / 'deriver.py', trace_inputs['deriver_sha256']) == (proof / 'runner.py').read_bytes()
    read(ROOT / 'tb_frontend.sv', trace_inputs['testbench_sha256'])
    for label, row in trace_result['jobs'].items():
        assert row['passed'] and row['source_unchanged'] and row['compile_exit'] == 0
        for name, digest in trace_inputs['jobs'][label]['files'].items(): read(traces / label / name, digest)
        trace = read(traces / label / 'trace.log', row['trace_log_sha256']).decode()
        read(traces / label / 'compile.log', row['compile_log_sha256'])
        if label == 'actual':
            assert row['trace_exit'] == 0 and trace.count('PASS_COMMAND_FRONTEND cases=10 bytes=45 operations=5 cpb=217') == 1
            assert 'FATAL:' not in trace
            for name, data in source.items(): assert (traces / label / name).read_bytes() == data
        else:
            assert row['trace_exit'] != 0 and trace_inputs['jobs'][label]['expected_error'] in trace
            assert 'GLOBAL_TIMEOUT' not in trace and 'PASS_COMMAND_FRONTEND' not in trace
    def chain(initial, conclusion=None):
        result = ['(set-logic QF_UFBV)', smt]
        for index in range(3):
            result += [f'(declare-fun s{index} () {TOP}_s)', f'(assert ({TOP}_h s{index}))',
                       f'(assert ({TOP}_u s{index}))', f'(assert (= ({TOP}_is s{index}) {"true" if initial and index == 0 else "false"}))']
            if index: result.append(f'(assert ({TOP}_t s{index-1} s{index}))')
        if initial:
            result += [f'(assert ({TOP}_i s0))', f'(assert (not (|{TOP}_n reset_n_i| s0)))',
                       f'(assert (not (|{TOP}_n reset_n_i| s1)))', '(check-sat)',
                       f'(assert (not (and ({TOP}_a s0) ({TOP}_a s1) ({TOP}_a s2))))']
        else:
            target = f'({TOP}_a s2)' if conclusion is None else f'(|{TOP}_a {conclusion}| s2)'
            result += [f'(assert ({TOP}_a s0))', f'(assert ({TOP}_a s1))', f'(assert (not {target}))']
        return '\n'.join(result + ['(check-sat)']) + '\n'
    run.mkdir(parents=True, exist_ok=False)
    (run / 'auditor.py').write_bytes(Path(__file__).read_bytes())
    for phase in ('base', 'induction'): (run / (phase + '.smt2')).write_text(chain(phase == 'base'))
    for index in range(60): (run / f'induction-{index:02}.smt2').write_text(chain(False, index))
    def solve(job):
        solver, phase = job.split('-', 1)
        query = run / (phase + '.smt2')
        options = ['-T:120', '-smt2'] if solver == 'z3' else (
            ['--lang=smt2', '--incremental', '--tlimit=120000'] if phase == 'base' else
            ['--lang=smt2', '--bitblast=eager', '--ackermann', '--tlimit=120000'])
        argv = [shutil.which(getattr(args, solver))] + options + [str(query)]
        with (run / (job + '.log')).open('w') as output:
            result = subprocess.run(argv, stdout=output, stderr=subprocess.STDOUT, timeout=150)
        output = (run / (job + '.log')).read_text()
        answers = [line for line in output.splitlines() if line in ('sat', 'unsat', 'unknown')]
        expected = ['sat', 'unsat'] if phase == 'base' else ['unsat']
        return job, {'passed': result.returncode == 0 and answers == expected and '(error' not in output,
                     'exit': result.returncode, 'answers': answers, 'argv': argv,
                     'query_sha256': sha(query), 'log_sha256': sha(run / (job + '.log'))}
    jobs = ['z3-base', 'z3-induction', 'cvc5-base'] + [f'cvc5-induction-{index:02}' for index in range(60)]
    with ThreadPoolExecutor(max_workers=12) as pool:
        results = dict(pool.map(solve, jobs))
    passed = all(row['passed'] for row in results.values())
    result = {'audit_passed': passed, 'assertions': 60, 'solver_results': results,
        'checked_sha256': checked, 'backend_primary_inputs': expected_inputs,
        'ten_reachable_serial_scenarios_pass': True, 'five_faulty_controls_detected': True,
        'hardware_access': False, 'whole_machine_refinement': False,
        'scope': 'Source/structure/log audit; Z3 joint induction and cvc5 each of all 60 conclusions under the identical joint prior invariant. Explicit frontend component only; backend excluded. No independent reviewer or physical/numerical/full-machine guarantee.'}
    (run / 'FINISHED.json').write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(json.dumps({'audit_passed': passed, 'assertions': 60, 'solver_queries': len(results),
        'failed': [name for name, row in results.items() if not row['passed']],
        'scope': result['scope']}, indent=2), flush=True)
    return 0 if passed else 1


if __name__ == '__main__': raise SystemExit(main())
