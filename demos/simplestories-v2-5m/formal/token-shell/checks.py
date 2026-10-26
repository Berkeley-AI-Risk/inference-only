"""Cross-check tape0, with bounded tape faults and reset/CLEAR witnesses.

Only fresh verification copies are written. Cover constraints request example
traces; they are never premises of the unbounded proof. No hardware or network.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import time


def sha(data): return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--run', required=True, type=Path)
    parser.add_argument('--proof', required=True, type=Path)
    parser.add_argument('--yosys', default='yosys')
    parser.add_argument('--z3', default='z3')
    parser.add_argument('--cvc5', default='cvc5')
    parser.add_argument('--covers-only', action='store_true', help='Only rerun the two existential reuse traces.')
    args = parser.parse_args()
    here = Path(__file__).absolute().parent
    proof = args.proof.absolute()
    raw_inputs = (proof / 'INPUTS.json').read_bytes()
    raw_finished = (proof / 'FINISHED.json').read_bytes()
    inputs, finished = json.loads(raw_inputs), json.loads(raw_finished)
    assert finished['passed'] and finished['assertion_cells'] == 48
    assert finished['assumption_cells'] == 0 and finished['observer_constant_cells'] == 1
    assert inputs['cutpoints'] == []
    for name, row in inputs['files'].items():
        assert sha((proof / name).read_bytes()) == row['sha256']
    for label, row in finished['solver_results'].items():
        assert sha((proof / (label + '.smt2')).read_bytes()) == row['query_sha256']
        assert sha((proof / (label + '.log')).read_bytes()) == row['log_sha256']
    run = args.run.absolute()
    run.mkdir(parents=True, exist_ok=False)
    (run / 'checker.py').write_bytes(Path(__file__).read_bytes())
    shell = next(name for name in inputs['files'] if name.endswith('/board1_context2048_token_shell.sv'))
    source = (proof / shell).read_text()
    def replace(old, new):
        assert source.count(old) == 1, old
        return source.replace(old, new)
    append = 'token_tape_q[tape_count_q] <= append_token_i;'
    read = 'tape_read_q <= token_tape_q[replay_position_q];'
    skip = 'if (replay_is_needed)\n                                state_q <= ST_TAPE_READ;'
    variants = {
        'actual-bmc': source,
        'append-wrong-slot': replace(append, "token_tape_q[tape_count_q + 12'd1] <= append_token_i;"),
        'append-flips-data': replace(append, "token_tape_q[tape_count_q] <= append_token_i ^ 12'd1;"),
        'append-overwrites-first-slot': replace(append, "token_tape_q[12'd0] <= append_token_i;"),
        'read-next-slot': replace(read, "tape_read_q <= token_tape_q[replay_position_q + 12'd1];"),
        'step-bypasses-tape-read': replace(skip, skip.replace('ST_TAPE_READ', 'ST_EMBED_START')),
    }
    inventory = {'parent_inputs_sha256': sha(raw_inputs), 'parent_finished_sha256': sha(raw_finished),
                 'checker_sha256': sha(Path(__file__).read_bytes()), 'jobs': {},
                 'hardware_access': False, 'network_access': False}
    for label, candidate in ([] if args.covers_only else variants.items()):
        assert candidate.count((proof / 'monitor.inc.sv').read_text()) == 1
        job = run / label
        job.mkdir()
        files = {}
        for name in inputs['files']:
            if name in ('runner.py', 'production_shell.sv'): continue
            data = candidate.encode() if name == shell else (proof / name).read_bytes()
            target = job / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            files[name] = sha(data)
        inventory['jobs'][label] = {'files': files, 'kind': 'eight-state BMC',
                                    'expected': ['sat', 'unsat'] if label == 'actual-bmc' else ['sat', 'sat']}
    top = 'board1_context2048_token_shell'
    smt = (proof / 'design.smt2').read_text()
    induction = (proof / 'induction.smt2').read_text()
    labels = re.findall(r'^; yosys-smt2-assert (\d+) ([^\n]+)', smt, re.M)
    assert len(labels) == 48 and {int(index) for index, _ in labels} == set(range(48))
    def add_query(label, query, kind, expected, **extra):
        job = run / label
        job.mkdir()
        (job / 'query.smt2').write_text(query)
        inventory['jobs'][label] = {'files': {'query.smt2': sha(query.encode())},
                                    'kind': kind, 'expected': expected, **extra}
    def cvc5_query(query):
        assert query.count('(set-option :timeout 120000)') == 1
        return '(set-logic QF_AUFBV)\n' + query.replace('(set-option :timeout 120000)', '(set-option :tlimit-per 30000)')
    if not args.covers_only:
        add_query('cvc5-base', cvc5_query((proof / 'base.smt2').read_text()),
                  'second solver base', ['sat', 'unsat'])
    goal = f'(assert (not ({top}_a s2)))'
    assert induction.count(goal) == 1
    for index, label in ([] if args.covers_only else labels):
        query = cvc5_query(induction).replace(goal, f'(assert (not (|{top}_a {index}| s2)))')
        add_query(f'cvc5-induction-{int(index):02d}', query, 'same joint induction, one conclusion',
                  ['unsat'], assertion=int(index), source=label)
    def chain(design, last):
        parts = ['(set-option :produce-models true)', '(set-option :timeout 120000)', design]
        for step in range(last + 1):
            parts += [f'(declare-fun s{step} () {top}_s)', f'(assert ({top}_h s{step}))',
                      f'(assert ({top}_u s{step}))',
                      f'(assert (= ({top}_is s{step}) {"true" if step == 0 else "false"}))']
            if step: parts.append(f'(assert ({top}_t s{step-1} s{step}))')
        parts += [f'(assert ({top}_i s0))', f'(assert (not (|{top}_n rst_n| s0)))',
                  f'(assert (not (|{top}_n rst_n| s1)))']
        return parts
    def bit(signal, step, value):
        expression = f'(|{top}_n {signal}| s{step})'
        return f'(assert {expression if value else "(not " + expression + ")"})'
    def word(signal, step, value):
        return f'(assert (= (|{top}_n {signal}| s{step}) (_ bv{value} 12)))'
    signals = ['rst_n', 'clear_i', 'state_q', 'tape_count_q', 'replay_position_q',
               'append_transfer', 'append_token_i', 'step_transfer', 'embed_start_valid',
               'f_tape_slot', 'f_slot_written', 'f_slot_expected', 'f_slot_observed',
               'f_read_is_selected', 'f_read_expected', 'tape_read_q', 'fail_q']
    def values(last):
        return '(get-value (' + ' '.join(f'(|{top}_n {signal}| s{step})'
            for step in range(last + 1) for signal in signals) + '))'
    for label, repeated_reset in [('cover-clear-reuse', False), ('cover-reset-reuse', True)]:
        # Even with no outstanding work, the embedding wrapper enters DRAIN
        # on CLEAR. At s4 it returns to IDLE; the shell sees that at s5 and
        # returns to IDLE at s6. Reset, unlike CLEAR, directly resets both.
        append_again = 5 if repeated_reset else 6
        step_again, last = append_again + 1, append_again + 3
        parts = chain(smt, last)
        parts += [word('f_tape_slot', 0, 0)]
        for step in range(2, last + 1):
            parts += [bit('rst_n', step, not (repeated_reset and step == 3)),
                      bit('clear_i', step, not repeated_reset and step == 3),
                      bit('append_valid_i', step, step in (2, append_again)),
                      bit('step_valid_i', step, step == step_again)]
        parts += [bit('append_transfer', 2, True), word('append_token_i', 2, 17),
                  word('tape_count_q', 4, 0), bit('f_slot_written', 4, False),
                  word('f_slot_observed', 4, 17),
                  bit('append_transfer', append_again, True), word('append_token_i', append_again, 29),
                  bit('step_transfer', step_again, True), word('f_slot_observed', step_again, 29),
                  bit('embed_start_valid', last, True), bit('f_read_is_selected', last, True),
                  word('tape_read_q', last, 29), '(check-sat)', values(last)]
        add_query(label, '\n'.join(parts) + '\n',
                  'existential reuse witness, not a safety-proof premise', ['sat'], states=last + 1)
    (run / 'INPUTS.json').write_text(json.dumps(inventory, indent=2) + '\n')
    def check(label):
        job, entry = run / label, inventory['jobs'][label]
        start = time.time()
        if label in variants:
            with (job / 'yosys.log').open('w') as output:
                code = subprocess.run([shutil.which(args.yosys), '-Q', 'prove.ys'], cwd=job,
                                      stdout=output, stderr=subprocess.STDOUT).returncode
            assert code == 0, label
            cells = [cell['type'] for module in json.loads((job / 'elaborated.json').read_text())['modules'].values()
                     for cell in module.get('cells', {}).values()]
            assert cells.count('$assert') == 48 and '$assume' not in cells and '$mem_v2' in cells
            assert '$anyseq' not in cells and cells.count('$anyconst') == 1
            parts = chain((job / 'design.smt2').read_text(), 7)
            parts += ['(check-sat)', '(assert (not (and ' + ' '.join(
                f'({top}_a s{step})' for step in range(8)) + ')))', '(check-sat)']
            if label != 'actual-bmc': parts.append(values(7))
            (job / 'query.smt2').write_text('\n'.join(parts) + '\n')
        argv = ([shutil.which(args.cvc5), '--lang=smt2', '--incremental', 'query.smt2']
                if label.startswith('cvc5-') else [shutil.which(args.z3), '-smt2', 'query.smt2'])
        with (job / 'solver.log').open('w') as output:
            child = subprocess.run(argv, cwd=job, stdout=output, stderr=subprocess.STDOUT)
        log = (job / 'solver.log').read_text()
        answers = [line for line in log.splitlines() if line in ('sat', 'unsat', 'unknown')]
        unchanged = all(sha((job / name).read_bytes()) == digest for name, digest in entry['files'].items())
        row = {'passed': child.returncode == 0 and answers == entry['expected'] and '(error ' not in log and unchanged,
               'exit': child.returncode, 'answers': answers, 'seconds': time.time() - start,
               'source_unchanged': unchanged, 'query_sha256': sha((job / 'query.smt2').read_bytes()),
               'log_sha256': sha(log.encode())}
        (job / 'FINISHED.json').write_text(json.dumps(row, indent=2) + '\n')
        print('TAPE_CHECK ' + label + ' ' + json.dumps(row), flush=True)
        return label, row
    with ThreadPoolExecutor(max_workers=12) as pool:
        records = dict(pool.map(check, inventory['jobs']))
    record = {'passed': all(row['passed'] for row in records.values()), 'jobs': records,
              'input_sha256': sha((run / 'INPUTS.json').read_bytes()),
              'hardware_access': False, 'network_access': False,
              'scope': ('Reset/CLEAR retained-memory reuse witnesses only.' if args.covers_only else
                        'Full cvc5 base + 48-conclusion cross-check; unchanged eight-state BMC; five bounded tape mutants; reset/CLEAR retained-memory reuse witnesses.')}
    (run / 'FINISHED.json').write_text(json.dumps(record, indent=2) + '\n')
    print('TAPE_CHECKS_FINISHED passed=' + str(record['passed']), flush=True)
    raise SystemExit(0 if record['passed'] else 1)


if __name__ == '__main__': main()
