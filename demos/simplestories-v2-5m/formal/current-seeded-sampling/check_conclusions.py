"""Second-solver check of every conclusion under the identical joint invariant.

Splits only the final conjunction, exactly as the baseline portable replay.
No prior assertion, input boundary, transition or memory is removed/assumed.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time


def sha(data): return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--proof', type=Path, required=True)
    parser.add_argument('--run', type=Path, required=True)
    parser.add_argument('--timeout', type=int, default=30)
    parser.add_argument('--workers', type=int, default=2)
    args = parser.parse_args()
    proof = args.proof.absolute()
    inputs = json.loads((proof / 'INPUTS.json').read_text())
    finished = json.loads((proof / 'FINISHED.json').read_text())
    if finished['yosys_exit'] != 0 or finished['assumption_cells'] != 0:
        raise ValueError('Parent elaboration is not a zero-assumption proof model')
    for name, entry in inputs['files'].items():
        if sha((proof / name).read_bytes()) != entry['sha256']:
            raise ValueError('Parent proof input changed: ' + name)
    top, k = inputs['top'], inputs['induction_length']
    smt = (proof / 'design.smt2').read_text()
    labels = re.findall(r'^; yosys-smt2-assert (\d+) ([^\n]+)', smt, re.M)
    if len(labels) != inputs['assertion_cells_expected']:
        raise ValueError('Parent assertion inventory changed')
    query_path = proof / 'z3-induction.smt2'
    if not query_path.is_file(): query_path = proof / 'cvc5-induction.smt2'
    query = query_path.read_text()
    goal = f'(assert (not ({top}_a s{k})))'
    if query.count(goal) != 1: raise ValueError('Expected exact joint induction goal')
    query = '\n'.join(line for line in query.splitlines() if not (
        line.startswith('(set-option :timeout ') or line.startswith('(set-option :tlimit-per ')
        or line.startswith('(set-option :produce-models ') or line.startswith('(set-logic '))) + '\n'
    run = args.run.absolute()
    run.mkdir(parents=True, exist_ok=False)
    (run / 'checker.py').write_bytes(Path(__file__).read_bytes())
    memory_count = finished['memory_cells']
    jobs = []
    for index, label in labels:
        text = query.replace(goal, f'(assert (not (|{top}_a {index}| s{k})))')
        text = ('(set-logic ' + ('QF_UFBV' if memory_count == 0 else 'QF_AUFBV') + ')\n'
                + f'(set-option :tlimit-per {args.timeout * 1000})\n' + text)
        name = 'conclusion-' + index.zfill(3)
        (run / (name + '.smt2')).write_text(text)
        jobs.append((name, index, label))
    (run / 'INPUTS.json').write_text(json.dumps(dict(
        parent_inputs_sha256=sha((proof / 'INPUTS.json').read_bytes()),
        parent_finished_sha256=sha((proof / 'FINISHED.json').read_bytes()),
        parent_query_sha256=sha(query_path.read_bytes()), design_sha256=sha(smt.encode()),
        assertion_count=len(labels), induction_length=k, memory_cells=memory_count,
        query_files={name + '.smt2': sha((run / (name + '.smt2')).read_bytes()) for name, _, _ in jobs},
        same_joint_prior_assertions=True, added_assumptions=0, hardware_access=False,
        scope='Each conclusion of the identical joint induction checked separately by cvc5; no separate lemma assumed.'),
        indent=2, sort_keys=True) + '\n')
    start = time.monotonic()
    def solve(job):
        name, index, label = job
        command = ['cvc5', '--lang=smt2']
        command += (['--bitblast=eager', '--ackermann'] if memory_count == 0 else ['--incremental'])
        command.append(str(run / (name + '.smt2')))
        begin = time.monotonic()
        code, timed_out = None, False
        with (run / (name + '.log')).open('w') as stream:
            try:
                child = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT,
                                       timeout=args.timeout + 15)
                code = child.returncode
            except subprocess.TimeoutExpired:
                timed_out = True
        data = (run / (name + '.log')).read_bytes()
        output = data.decode(errors='replace')
        answers = [line for line in output.splitlines() if line in ('sat', 'unsat', 'unknown')]
        result = dict(assertion=int(index), source=label, passed=code == 0 and answers == ['unsat'] and '(error ' not in output,
            exit=code, timed_out=timed_out, answers=answers, seconds=time.monotonic() - begin,
            query_sha256=sha((run / (name + '.smt2')).read_bytes()), log_sha256=sha(data))
        print(name + ' ' + json.dumps(result), flush=True)
        return name, result
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        results = dict(pool.map(solve, jobs))
    record = dict(passed=all(row['passed'] for row in results.values()),
        conclusions=len(results), passed_conclusions=sum(row['passed'] for row in results.values()),
        seconds=time.monotonic() - start, inputs_sha256=sha((run / 'INPUTS.json').read_bytes()),
        same_joint_prior_assertions=True, added_assumptions=0, results=results,
        hardware_access=False, whole_machine_refinement=False)
    (run / 'FINISHED.json').write_text(json.dumps(record, indent=2, sort_keys=True) + '\n')
    print(json.dumps({key: value for key, value in record.items() if key != 'results'}), flush=True)
    return 0 if record['passed'] else 1


if __name__ == '__main__': raise SystemExit(main())
