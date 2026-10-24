"""Cvc5 base and per-conclusion replay of an identical connected induction.

Only the final conclusion conjunction is split; every joint prior assertion,
transition, source, reset premise, actual memory and arbitrary port is retained.
HO_ALL permits cvc5's preprocessing of the Yosys retained-array/function model.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import time

assert sys.flags.isolated and sys.flags.dont_write_bytecode and sys.flags.no_site and not sys.flags.optimize
HERE = Path(__file__).resolve().parent

def sha(raw): return hashlib.sha256(raw).hexdigest()
def put(path, value): path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--proof', type=Path, required=True)
    parser.add_argument('--run', type=Path, required=True)
    parser.add_argument('--timeout', type=int, default=60)
    parser.add_argument('--workers', type=int, default=4)
    parser.add_argument('--only', help='Comma-separated assertion indexes; base is always included.')
    parser.add_argument('--mode', choices=('arrays', 'ho-elim'), default='arrays')
    args = parser.parse_args()
    assert 1 <= args.timeout <= 900 and 1 <= args.workers <= 8
    proof, run = args.proof.absolute(), args.run.absolute()
    assert HERE.parent in proof.parents and HERE.parent in run.parents
    inputs_raw = (proof / 'INPUTS.json').read_bytes()
    inputs = json.loads(inputs_raw)
    finished_raw = (proof / 'FINISHED.json').read_bytes()
    finished = json.loads(finished_raw)
    assert finished['passed'] and finished['inputs_sha256'] == sha(inputs_raw)
    assert finished['assertion_cells'] == inputs['assertions'] == 196
    assert finished['assumption_cells'] == 0 and len(inputs['private_semantic_output_cuts']) == 37
    for name, row in inputs['files'].items(): assert sha((proof / name).read_bytes()) == row['sha256'], name
    for name, digest in finished['proof_artifacts_sha256'].items(): assert sha((proof / name).read_bytes()) == digest, name
    for label in ('z3-base', 'z3-induction'):
        row = finished['solver_results'][label]
        assert row['passed'] and sha((proof / (label + '.smt2')).read_bytes()) == row['query_sha256']
        assert sha((proof / (label + '.log')).read_bytes()) == row['log_sha256']
    top, k = inputs['top'], inputs['induction_length']
    smt = (proof / 'design.smt2').read_text()
    labels = dict(re.findall(r'^; yosys-smt2-assert (\d+) ([^\n]+)', smt, re.M))
    assert set(map(int, labels)) == set(range(inputs['assertions']))
    goal = f'(assert (not ({top}_a s{k})))'
    induction = (proof / 'z3-induction.smt2').read_text()
    base = (proof / 'z3-base.smt2').read_text()
    assert induction.count(goal) == 1 and base.count('(check-sat)') == 2
    def converted(query):
        query = '\n'.join(line for line in query.splitlines() if not (
            line.startswith('(set-option :timeout ') or line.startswith('(set-option :produce-models ')
            or line.startswith('(set-option :tlimit-per ') or line.startswith('(set-logic '))) + '\n'
        return f'(set-logic HO_ALL)\n(set-option :produce-models false)\n(set-option :tlimit-per {args.timeout*1000})\n' + query
    indexes = list(range(inputs['assertions'])) if args.only is None else list(map(int, args.only.split(',')))
    assert len(indexes) == len(set(indexes)) and set(indexes) <= set(range(inputs['assertions']))
    queries = {'base': converted(base.replace('(check-sat)\n', '', 1))}
    queries.update({f'conclusion-{index:03}': converted(induction).replace(goal, f'(assert (not (|{top}_a {index}| s{k})))') for index in indexes})
    run.mkdir(parents=True, exist_ok=False)
    (run / 'checker.py').write_bytes(Path(__file__).read_bytes())
    for name, query in queries.items(): (run / (name + '.smt2')).write_text(query)
    put(run / 'INPUTS.json', dict(schema='seeded-connected-secondary-inputs-v1',
        primary_inputs_sha256=sha(inputs_raw), primary_finished_sha256=sha(finished_raw),
        primary_design_sha256=sha(smt.encode()), top=top, induction_length=k,
        source_locations=labels, conclusions=indexes, assertion_count=inputs['assertions'],
        same_joint_prior_assertions=True, added_assumptions=0, solver_mode=args.mode,
        query_files={name + '.smt2': sha(query.encode()) for name, query in queries.items()},
        base_nonvacuity='The unchanged primary Z3 base contains sat reachability; secondary checks the identical asserted base counterexample after removing only the first check-sat command.',
        hardware_access=False, network_access=False))
    print(f'CONNECTED_SECONDARY_STARTED queries={len(queries)} workers={args.workers}', flush=True)
    started = time.monotonic()
    def solve(name):
        query_path = run / (name + '.smt2')
        begin = time.monotonic()
        command = ['cvc5', '--lang=smt2', '--incremental']
        if args.mode == 'ho-elim': command.append('--ho-elim')
        command.append(str(query_path))
        code, timed_out = None, False
        with (run / (name + '.log')).open('w') as output:
            try: code = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT, timeout=args.timeout+20).returncode
            except subprocess.TimeoutExpired: timed_out = True
        raw = (run / (name + '.log')).read_bytes()
        text = raw.decode(errors='replace')
        answers = [line for line in text.splitlines() if line in ('sat', 'unsat', 'unknown')]
        row = dict(passed=code == 0 and answers == ['unsat'] and '(error ' not in text,
            exit=code, timed_out=timed_out, answers=answers, argv=command, seconds=time.monotonic()-begin,
            query_sha256=sha(query_path.read_bytes()), log_sha256=sha(raw))
        put(run / (name + '-RESULT.json'), row)
        print(name + ' ' + json.dumps(row), flush=True)
        return name, row
    with ThreadPoolExecutor(max_workers=args.workers) as pool: results = dict(pool.map(solve, queries))
    record = dict(schema='seeded-connected-secondary-result-v1',
        passed=all(row['passed'] for row in results.values()),
        conclusions=len(indexes), passed_conclusions=sum(results[f'conclusion-{i:03}']['passed'] for i in indexes),
        complete_conclusion_set=set(indexes) == set(range(inputs['assertions'])),
        seconds=time.monotonic()-started, inputs_sha256=sha((run / 'INPUTS.json').read_bytes()),
        same_joint_prior_assertions=True, added_assumptions=0, results=results,
        hardware_access=False, network_access=False, whole_machine_refinement=False)
    put(run / 'FINISHED.json', record)
    print(json.dumps({key: value for key, value in record.items() if key != 'results'}), flush=True)
    return 0 if record['passed'] else 1

if __name__ == '__main__': raise SystemExit(main())
