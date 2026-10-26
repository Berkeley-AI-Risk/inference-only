"""Second-solver check of the entire joint public-shell induction."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

assert sys.flags.isolated and sys.flags.dont_write_bytecode and sys.flags.no_site and not sys.flags.optimize
ROOT = Path(__file__).resolve().parent
TOP = 'board1_public_shell_composition'


def sha(data): return hashlib.sha256(data).hexdigest()
def put(path, obj): path.write_text(json.dumps(obj, indent=2, sort_keys=True) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', type=Path, required=True)
    parser.add_argument('--cvc5', default='cvc5')
    parser.add_argument('--seconds', type=int, default=900)
    parser.add_argument('--proof', type=Path, required=True)
    parser.add_argument('--verify-only', action='store_true')
    parser.add_argument('--mode', choices=('arrays', 'eager'), default='arrays')
    parser.add_argument('--only', help='Comma-separated assertion indexes; base is always included')
    args = parser.parse_args()
    assert 120 <= args.seconds <= 3600
    proof, run = args.proof.absolute(), args.run.absolute()
    spec = importlib.util.spec_from_file_location('current_composition_deriver', ROOT / 'run_proof.py')
    driver = importlib.util.module_from_spec(spec); spec.loader.exec_module(driver)
    sources, _, binding = driver.derive()
    inputs = json.loads((proof / 'INPUTS.json').read_text())
    result = json.loads((proof / 'FINISHED.json').read_text())
    assert result['passed'] and result['inputs_sha256'] == sha((proof / 'INPUTS.json').read_bytes())
    assert result['assertions'] == binding['assertions'] == 134
    assert (proof / 'runner.py').read_bytes() == (ROOT / 'run_proof.py').read_bytes()
    for name, data in sources.items(): assert (proof / name).read_bytes() == data, name
    for name, row in inputs['files'].items(): assert sha((proof / name).read_bytes()) == row['sha256']
    for name, row in result['solver_results'].items():
        assert row['passed'] and sha((proof / (name + '.log')).read_bytes()) == row['log_sha256']
        assert sha((proof / (name + '.smt2')).read_bytes()) == row['query_sha256']
    if args.verify_only:
        record = json.loads((run / 'FINISHED.json').read_text())
        assert record['passed'] and (run / 'checker.py').read_bytes() == Path(__file__).read_bytes()
        assert record['proof_inputs_sha256'] == result['inputs_sha256']
        for name, row in record['jobs'].items():
            assert row['passed'] and sha((run / (name + '.log')).read_bytes()) == row['log_sha256']
            assert sha((run / (name + '.smt2')).read_bytes()) == row['query_sha256']
        print('PUBLIC_SHELL_CROSS_VERIFY PASS conclusions=' + str(record['conclusions_checked']), flush=True)
        return 0
    smt = (proof / 'design.smt2').read_text()
    labels = dict(re.findall(r'^; yosys-smt2-assert (\d+) ([^\n]+)', smt, re.M))
    assert {int(index) for index in labels} == set(range(134))
    base, induction = [(proof / (name + '.smt2')).read_text() for name in ('base', 'induction')]
    def converted(query):
        assert query.count('(set-option :timeout 180000)') == 1
        # cvc5 introduces function-valued terms while preprocessing the
        # retained array/function encoding. HO_ALL permits that expansion;
        # it does not change any assertion, transition or reset premise.
        return '(set-logic HO_ALL)\n' + query.replace('(set-option :produce-models true)', '(set-option :produce-models false)').replace('(set-option :timeout 180000)', f'(set-option :tlimit-per {args.seconds * 1000})')
    indexes = list(range(134)) if args.only is None else [int(i) for i in args.only.split(',')]
    assert len(set(indexes)) == len(indexes) and set(indexes) <= set(range(134))
    goal = f'(assert (not ({TOP}_a s2)))'
    assert inputs['induction_length'] == 2 and induction.count(goal) == 1
    # The Z3 run already checks reset reachability (sat), and then the base
    # counterexample formula (unsat). cvc5's HO preprocessor can report
    # 'unknown' for the first existence question while refuting the second.
    # Ask it only the identical base counterexample formula here: deleting a
    # check-sat command does not remove or add any asserted premise.
    assert base.count('(check-sat)') == 2
    queries = {'base': converted(base.replace('(check-sat)\n', '', 1))}
    queries.update({f'induction-{i:03}': converted(induction).replace(goal, f'(assert (not (|{TOP}_a {i}| s2)))') for i in indexes})
    run.mkdir(parents=True, exist_ok=False)
    (run / 'checker.py').write_bytes(Path(__file__).read_bytes())
    for name, query in queries.items(): (run / (name + '.smt2')).write_text(query)
    put(run / 'INPUTS.json', {'proof_inputs_sha256': result['inputs_sha256'], 'conclusions': indexes,
        'mode': args.mode, 'all_joint_prior_assertions_retained': True, 'assertion_source_locations': labels,
        'queries': {name: sha(query.encode()) for name, query in queries.items()},
        'base_nonvacuity_checked_by': 'Primary Z3 sat result; cvc5 rechecks only the base counterexample formula', 'hardware_access': False})
    print('PUBLIC_SHELL_CROSS_STARTED queries=' + str(len(queries)) + ' workers=12', flush=True)
    def solve(name):
        start = time.monotonic()
        options = ['--lang=smt2', '--incremental'] if name == 'base' or args.mode == 'arrays' else ['--lang=smt2', '--bitblast=eager', '--ackermann']
        argv = [shutil.which(args.cvc5)] + options + [str(run / (name + '.smt2'))]
        with (run / (name + '.log')).open('w') as log:
            try: code = subprocess.run(argv, stdout=log, stderr=subprocess.STDOUT, timeout=args.seconds + 30).returncode
            except subprocess.TimeoutExpired: code = 124
        output = (run / (name + '.log')).read_text()
        answers = [line for line in output.splitlines() if line in ('sat', 'unsat', 'unknown')]
        expected = ['unsat']
        row = {'passed': code == 0 and answers == expected and '(error' not in output,
            'exit': code, 'answers': answers, 'seconds': time.monotonic()-start, 'argv': argv,
            'query_sha256': sha((run / (name + '.smt2')).read_bytes()), 'log_sha256': sha(output.encode())}
        put(run / (name + '-RESULT.json'), row)
        print('PUBLIC_SHELL_CROSS ' + name + ' ' + str(row['passed']) + ' ' + str(answers), flush=True)
        return name, row
    with ThreadPoolExecutor(max_workers=12) as pool: jobs = dict(pool.map(solve, queries))
    record = {'passed': all(row['passed'] for row in jobs.values()), 'jobs': jobs,
        'proof_inputs_sha256': result['inputs_sha256'], 'conclusions_checked': len(indexes),
        'complete_conclusion_set': set(indexes) == set(range(134)), 'all_joint_prior_assertions_retained': True,
        'hardware_access': False, 'whole_machine_refinement': False}
    put(run / 'FINISHED.json', record)
    print(json.dumps({'passed': record['passed'], 'conclusions_checked': len(indexes),
        'failed': [name for name, row in jobs.items() if not row['passed']]}), flush=True)
    return 0 if record['passed'] else 1


if __name__ == '__main__': raise SystemExit(main())
