"""Second solver, bounded faulty controls, and retained-staging reuse witnesses.

The witness constraints are existential examples, not assumptions of the
unbounded safety proof. Only verification copies are changed.
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
    args = parser.parse_args()
    here = Path(__file__).absolute().parent
    proof = args.proof.absolute()
    raw_inputs, raw_finished = ((proof / name).read_bytes() for name in ('INPUTS.json', 'FINISHED.json'))
    inputs, finished = json.loads(raw_inputs), json.loads(raw_finished)
    assert finished['passed'] and finished['assertions'] == 59 and inputs['split_induction']
    assert inputs['cutpoints'] == [] and inputs['induction_length'] == 2
    assert finished['inputs_sha256'] == sha(raw_inputs)
    for name, row in inputs['files'].items():
        assert sha((proof / name).read_bytes()) == row['sha256']
    for label, row in finished['solver_results'].items():
        assert row['passed']
        assert sha((proof / (label + '.smt2')).read_bytes()) == row['query_sha256']
        assert sha((proof / (label + '.log')).read_bytes()) == row['log_sha256']
    run = args.run.absolute()
    run.mkdir(parents=True, exist_ok=False)
    (run / 'checker.py').write_bytes(Path(__file__).read_bytes())
    top = 'board1_context2048_atomic_kv_typed'
    source_name = 'board1_context2048_atomic_kv_typed_clear_consistent.sv'
    source = (proof / source_name).read_text()
    monitor = (proof / 'monitor.inc.sv').read_text()
    def replace(old, new):
        assert source.count(old) == 1, old
        return source.replace(old, new)
    key_write = 'staged_key_head0_q[coordinate*16 +: 16] <= stage_key_i;'
    variants = {
        'actual-bmc': source,
        'stage-flips-key': replace(key_write, key_write.replace('stage_key_i;', "stage_key_i ^ 16'd1;")),
        'stage-swaps-key-value': replace(key_write, key_write.replace('stage_key_i;', 'stage_value_i;')),
        'stage-skips-coordinate': replace("expected_coordinate_q + 1'b1;", "expected_coordinate_q + 7'd2;"),
        'spontaneous-response': replace('attention_rsp_valid_o = reset_n && (state_q == ST_RESPONSE);',
                                       'attention_rsp_valid_o = reset_n && (state_q == ST_RESPONSE || state_q == ST_IDLE);'),
        'clear-allows-write': replace('kv_write_req_valid_o = live && (state_q == ST_WRITE_REQ) &&',
                                     'kv_write_req_valid_o = clear_i || live && (state_q == ST_WRITE_REQ) &&'),
    }
    inventory = {'parent_inputs_sha256': sha(raw_inputs), 'parent_finished_sha256': sha(raw_finished),
                 'checker_sha256': sha(Path(__file__).read_bytes()), 'jobs': {},
                 'hardware_access': False, 'network_access': False}
    for label, candidate in variants.items():
        assert candidate.count(monitor) == 1
        job = run / label
        job.mkdir()
        files = {}
        for name in (source_name, 'mapper_portable.sv', 'prove.ys'):
            data = candidate.encode() if name == source_name else (proof / name).read_bytes()
            (job / name).write_bytes(data)
            files[name] = sha(data)
        inventory['jobs'][label] = {'files': files, 'kind': 'seven-state reset-reachable BMC',
                                   'expected': ['sat', 'unsat'] if label == 'actual-bmc' else ['sat', 'sat']}
    def add_query(label, query, kind, expected):
        job = run / label
        job.mkdir()
        (job / 'query.smt2').write_text(query)
        inventory['jobs'][label] = {'files': {'query.smt2': sha(query.encode())}, 'kind': kind, 'expected': expected}
    for label in finished['solver_results']:
        query = (proof / (label + '.smt2')).read_text()
        assert query.count('(set-option :timeout 120000)') == 1
        query = '(set-logic QF_AUFBV)\n' + query.replace('(set-option :timeout 120000)', '(set-option :tlimit-per 120000)')
        add_query('cvc5-' + label, query, 'same safety query with a second solver',
                  ['sat', 'unsat'] if label == 'base' else ['unsat'])
    def chain(design, last):
        parts = ['(set-option :produce-models true)', '(set-option :timeout 120000)', design]
        for step in range(last + 1):
            parts += [f'(declare-fun s{step} () {top}_s)', f'(assert ({top}_h s{step}))',
                      f'(assert ({top}_u s{step}))',
                      f'(assert (= ({top}_is s{step}) {"true" if step == 0 else "false"}))']
            if step: parts.append(f'(assert ({top}_t s{step-1} s{step}))')
        parts += [f'(assert ({top}_i s0))', f'(assert (not (|{top}_n reset_n| s0)))',
                  f'(assert (not (|{top}_n reset_n| s1)))']
        return parts
    def equal(signal, step, number, width):
        value = ('true' if number else 'false') if width == 1 else f'(_ bv{number} {width})'
        return f'(assert (= (|{top}_n {signal}| s{step}) {value}))'
    def values(last):
        signals = ('reset_n clear_i state_q fault_q terminal_fault_event pending_persisted_q '
                   'f_coordinate f_coordinate_written f_staged_key f_staged_value f_expected_key f_expected_value '
                   'f_stage_active f_stage_filled f_completed_writes f_read_mask '
                   'stage_begin_valid_i stage_begin_ready_o stage_payload_valid_i stage_payload_ready_o '
                   'stage_coordinate_i f_attention_owned attention_rsp_valid_o').split()
        return '(get-value (' + ' '.join(f'(|{top}_n {signal}| s{step})'
            for step in range(last + 1) for signal in signals) + '))'
    smt = (proof / 'design.smt2').read_text()
    module = json.loads((proof / 'elaborated.json').read_text())['modules'][top]
    for label, repeated_reset in [('cover-clear-staging-reuse', False), ('cover-reset-staging-reuse', True)]:
        parts = chain(smt, 7) + [equal('f_coordinate', 0, 0, 7)]
        for step in range(2, 8):
            selected = {'reset_n': int(not (repeated_reset and step == 4)), 'model_locked_i': 1,
                        'clear_i': int(not repeated_reset and step == 4),
                        'stage_begin_valid_i': int(step in (2, 5)),
                        'stage_payload_valid_i': int(step in (3, 6)),
                        'stage_key_i': 17 if step < 5 else 29,
                        'stage_value_i': 23 if step < 5 else 31}
            for name, port in module['ports'].items():
                if port['direction'] == 'input' and name != 'clk':
                    parts.append(equal(name, step, selected.get(name, 0), len(port['bits'])))
        parts += [equal('stage_begin_ready_o', 2, 1, 1), equal('stage_payload_ready_o', 3, 1, 1),
                  equal('f_staged_key', 5, 17, 16), equal('f_staged_value', 5, 23, 16),
                  equal('f_coordinate_written', 5, 0, 1), equal('f_stage_active', 5, 0, 1),
                  equal('stage_begin_ready_o', 5, 1, 1), equal('stage_payload_ready_o', 6, 1, 1),
                  equal('f_staged_key', 7, 29, 16), equal('f_staged_value', 7, 31, 16),
                  equal('f_coordinate_written', 7, 1, 1), equal('fault_q', 7, 0, 1),
                  '(check-sat)', values(7)]
        add_query(label, '\n'.join(parts) + '\n', 'existential retained-staging reuse, not a safety premise', ['sat'])
    (run / 'INPUTS.json').write_text(json.dumps(inventory, indent=2) + '\n')
    def check(label):
        job, entry = run / label, inventory['jobs'][label]
        started = time.time()
        if label in variants:
            with (job / 'yosys.log').open('w') as output:
                code = subprocess.run([shutil.which(args.yosys), '-Q', 'prove.ys'], cwd=job,
                                      stdout=output, stderr=subprocess.STDOUT).returncode
            assert code == 0, label
            cells = list(json.loads((job / 'elaborated.json').read_text())['modules'][top]['cells'].values())
            kinds = [cell['type'] for cell in cells]
            assert kinds.count('$assert') == 59 and kinds.count('$anyconst') == 1
            assert '$assume' not in kinds and '$anyseq' not in kinds
            parts = chain((job / 'design.smt2').read_text(), 6)
            parts += ['(check-sat)', '(assert (not (and ' + ' '.join(f'({top}_a s{i})' for i in range(7)) + ')))', '(check-sat)']
            if label != 'actual-bmc': parts.append(values(6))
            (job / 'query.smt2').write_text('\n'.join(parts) + '\n')
        argv = ([shutil.which(args.cvc5), '--lang=smt2', '--incremental', 'query.smt2']
                if label.startswith('cvc5-') else [shutil.which(args.z3), '-smt2', 'query.smt2'])
        with (job / 'solver.log').open('w') as output:
            result = subprocess.run(argv, cwd=job, stdout=output, stderr=subprocess.STDOUT)
        log = (job / 'solver.log').read_text()
        answers = [line for line in log.splitlines() if line in ('sat', 'unsat', 'unknown')]
        unchanged = all(sha((job / name).read_bytes()) == digest for name, digest in entry['files'].items())
        record = {'passed': result.returncode == 0 and answers == entry['expected'] and '(error ' not in log and unchanged,
                  'exit': result.returncode, 'answers': answers, 'seconds': time.time() - started,
                  'source_unchanged': unchanged, 'query_sha256': sha((job / 'query.smt2').read_bytes()),
                  'log_sha256': sha(log.encode())}
        (job / 'FINISHED.json').write_text(json.dumps(record, indent=2) + '\n')
        print('KV_CHECK ' + label + ' ' + json.dumps(record), flush=True)
        return label, record
    with ThreadPoolExecutor(max_workers=12) as pool: records = dict(pool.map(check, inventory['jobs']))
    finished = {'passed': all(row['passed'] for row in records.values()), 'jobs': records,
                'inputs_sha256': sha((run / 'INPUTS.json').read_bytes()),
                'hardware_access': False, 'network_access': False,
                'scope': 'Second-solver check of base and all 59 conclusions; seven-state unchanged BMC and five faulty controls; two retained-staging reuse witnesses. Not external DDR epoch integrity or whole-machine refinement.'}
    (run / 'FINISHED.json').write_text(json.dumps(finished, indent=2) + '\n')
    print('KV_CHECKS_FINISHED passed=' + str(finished['passed']), flush=True)
    raise SystemExit(0 if finished['passed'] else 1)


if __name__ == '__main__': main()
