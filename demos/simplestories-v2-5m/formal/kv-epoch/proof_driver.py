"""Full actual typed-K/V controller and both actual address-mapper instances.

External typed DDR ports remain component inputs, not an assumed-correct memory
model. No value cutpoints. This proves local epoch/assembly/visibility properties,
not full post-CLEAR noninterference of the FPGA or mathematical token output.
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
    parser.add_argument('--run', type=Path, required=True)
    parser.add_argument('--yosys', default='yosys')
    parser.add_argument('--z3', default='z3')
    parser.add_argument('--induction', type=int, default=2)
    parser.add_argument('--split-induction', action='store_true')
    parser.add_argument('--jobs', type=int, default=8)
    args = parser.parse_args()
    assert 2 <= args.induction <= 8
    assert 1 <= args.jobs <= 16
    here = Path(__file__).absolute().parent
    package = here.parents[1]
    manifest_raw = (package / 'MANIFEST.json').read_bytes()
    manifest = json.loads(manifest_raw)['files']
    monitor = (here / 'epoch_monitor.inc.sv').read_bytes()
    assert b'assume(' not in monitor
    count = monitor.count(b'assert(')
    run = args.run.absolute()
    run.mkdir(parents=True, exist_ok=False)
    files = {'monitor.inc.sv': monitor, 'runner.py': Path(__file__).read_bytes()}
    origins = {}
    for basename in ('mapper_portable.sv', 'board1_context2048_atomic_kv_typed_clear_consistent.sv'):
        matches = [name for name in manifest if name.startswith('hardware/project/') and Path(name).name == basename]
        assert len(matches) == 1
        name = matches[0]
        data = (package / name).read_bytes()
        assert sha(data) == manifest[name]['sha256']
        origins[basename] = {'package_source': name, 'sha256': sha(data)}
        if basename.startswith('board1_'):
            files['production.sv'] = data
            assert data.count(b'\nendmodule') == 1
            data = data.replace(b'\nendmodule', b'\n' + monitor + b'\nendmodule')
        files[basename] = b'`undef FORMAL\n' + data
    assert origins == json.loads((here / 'sources.json').read_text())
    top = 'board1_context2048_atomic_kv_typed'
    commands = ['read_verilog -formal -sv -nosynthesis -D SYNTHESIS -defer ' + ' '.join(origins),
        f'prep -top {top} -flatten', 'async2sync', 'chformal -lower', 'opt_clean', 'dffunmap',
        f'select -assert-count {count} t:$assert', 'select -assert-none t:$assume t:$anyseq',
        'select -assert-count 1 t:$anyconst', 'check -assert',
        'write_json elaborated.json', 'write_rtlil elaborated.il', 'write_smt2 -wires design.smt2']
    files['prove.ys'] = ('\n'.join(commands) + '\n').encode()
    for name, data in files.items(): (run / name).write_bytes(data)
    inputs = {'source_package_sha256': sha(manifest_raw), 'origins': origins,
              'files': {name: {'sha256': sha(data), 'bytes': len(data)} for name, data in files.items()},
              'assertions': count, 'cutpoints': [], 'observer': {'name': 'f_coordinate', 'width': 7},
              'legacy_formal_blocks_enabled': False, 'induction_length': args.induction,
              'split_induction': args.split_induction, 'jobs': args.jobs,
              'environment': 'All component inputs arbitrary; only base reset at states 0 and 1. No induction input constraints.',
              'scope': 'Local K/V staging/typed-write completion/assembly visibility and logical CLEAR epoch safety. Not correctness of external DDR, whole-machine erasure, mathematical model output, liveness or mapped implementation.',
              'hardware_access': False, 'network_access': False}
    (run / 'INPUTS.json').write_text(json.dumps(inputs, indent=2) + '\n')
    print(f'KV_EPOCH_STARTED assertions={count} run={run}', flush=True)
    start = time.time()
    with (run / 'yosys.log').open('w') as output:
        code = subprocess.run([shutil.which(args.yosys), '-Q', 'prove.ys'], cwd=run,
                              stdout=output, stderr=subprocess.STDOUT).returncode
    records = {}
    if code == 0:
        module = json.loads((run / 'elaborated.json').read_text())['modules'][top]
        kinds = [cell['type'] for cell in module['cells'].values()]
        assert kinds.count('$assert') == count and '$assume' not in kinds and '$anyseq' not in kinds
        assert kinds.count('$anyconst') == 1 and all(kind.startswith('$') for kind in kinds)
        smt = (run / 'design.smt2').read_text()
        assert len(re.findall(r'^; yosys-smt2-assert ', smt, re.M)) == count
        k = args.induction
        def chain(initial):
            parts = ['(set-option :produce-models true)', '(set-option :timeout 120000)', smt]
            for step in range(k + 1):
                parts += [f'(declare-fun s{step} () {top}_s)', f'(assert ({top}_h s{step}))',
                          f'(assert ({top}_u s{step}))',
                          f'(assert (= ({top}_is s{step}) {"true" if initial and step == 0 else "false"}))']
                if step: parts.append(f'(assert ({top}_t s{step-1} s{step}))')
            if initial: parts += [f'(assert ({top}_i s0))', f'(assert (not (|{top}_n reset_n| s0)))',
                                  f'(assert (not (|{top}_n reset_n| s1)))']
            return parts
        base = chain(True) + ['(check-sat)', '(assert (not (and ' + ' '.join(f'({top}_a s{i})' for i in range(k+1)) + ')))', '(check-sat)']
        induction = chain(False) + [f'(assert ({top}_a s{i}))' for i in range(k)] + [f'(assert (not ({top}_a s{k})))', '(check-sat)']
        queries = {'base': '\n'.join(base) + '\n', 'induction': '\n'.join(induction) + '\n'}
        if args.split_induction:
            queries.pop('induction')
            prefix = chain(False) + [f'(assert ({top}_a s{i}))' for i in range(k)]
            for index in range(count):
                queries[f'induction-{index:02d}'] = '\n'.join(prefix + [
                    f'(assert (not (|{top}_a {index}| s{k})))', '(check-sat)']) + '\n'
        for label, query in queries.items(): (run / (label + '.smt2')).write_text(query)
        def solve(label):
            started = time.time()
            with (run / (label + '.log')).open('w') as output:
                result = subprocess.run([shutil.which(args.z3), '-smt2', str(run / (label + '.smt2'))], stdout=output, stderr=subprocess.STDOUT)
            log = (run / (label + '.log')).read_text()
            answers = [line for line in log.splitlines() if line in ('sat', 'unsat', 'unknown')]
            row = {'passed': result.returncode == 0 and answers == (['sat', 'unsat'] if label == 'base' else ['unsat']) and '(error ' not in log,
                   'exit': result.returncode, 'answers': answers, 'seconds': time.time() - started,
                   'query_sha256': sha(queries[label].encode()), 'log_sha256': sha(log.encode())}
            if answers and answers[-1] == 'sat':
                names = ['reset_n', 'clear_i', 'state_q', 'fault_q', 'terminal_fault_event',
                    'pending_persisted_q', 'pending_layer_q', 'pending_position_q',
                    'expected_coordinate_q', 'write_word_q', 'write_head_q', 'write_aborted_q',
                    'read_word_q', 'read_aborted_q', 'response_fault_q', 'response_from_pending_q',
                    'response_kind_q', 'response_position_q', 'f_seen', 'f_stage_active', 'f_stage_filled',
                    'f_coordinate', 'f_coordinate_written', 'f_completed_writes', 'f_read_mask',
                    'f_attention_owned', 'f_begin', 'f_payload', 'f_commit', 'f_attention',
                    'f_read_begin', 'f_read_piece', 'f_write_piece', 'stage_payload_legal',
                    'stage_payload_valid_i', 'stage_payload_ready_o', 'stage_coordinate_i']
                query = queries[label] + '(get-value (' + ' '.join(f'(|{top}_n {name}| s{i})'
                    for i in range(k+1) for name in names) + ' ' + ' '.join(f'(|{top}_a {i}| s{k})' for i in range(count)) + '))\n'
                (run / (label + '-model.smt2')).write_text(query)
                with (run / (label + '-model.log')).open('w') as output:
                    subprocess.run([shutil.which(args.z3), '-smt2', str(run / (label + '-model.smt2'))], stdout=output, stderr=subprocess.STDOUT)
            print('KV_EPOCH_' + label + ' ' + json.dumps(row), flush=True)
            return label, row
        with ThreadPoolExecutor(max_workers=args.jobs) as pool: records = dict(pool.map(solve, queries))
    unchanged = all(sha((run / name).read_bytes()) == row['sha256'] for name, row in inputs['files'].items())
    expected_queries = count + 1 if args.split_induction else 2
    passed = code == 0 and len(records) == expected_queries and all(row['passed'] for row in records.values()) and unchanged
    record = {'passed': passed, 'assertions': count, 'yosys_exit': code, 'seconds': time.time() - start,
              'inputs_sha256': sha((run / 'INPUTS.json').read_bytes()), 'source_unchanged': unchanged,
              'solver_results': records, 'hardware_access': False, 'network_access': False,
              'scope': inputs['scope'], 'failure_classification': None if passed else (
                  'BOUNDED_COUNTEREXAMPLE' if records.get('base', {}).get('answers') == ['sat', 'sat'] else 'UNRESOLVED_OR_SETUP_FAILURE')}
    (run / 'FINISHED.json').write_text(json.dumps(record, indent=2) + '\n')
    print('KV_EPOCH_FINISHED passed=' + str(passed), flush=True)
    raise SystemExit(0 if passed else 1)


if __name__ == '__main__': main()
