#!/usr/bin/env python3
"""Portable finite paired-prefetch comparison; no model, downloads or retries."""
if not __debug__:
    raise RuntimeError('Run the prefetch runner with Python assertions enabled')
import sys
if sys.version_info < (3, 9):
    raise RuntimeError('The prefetch package requires Python 3.9 or newer')
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time

HERE = Path(__file__).resolve().parent
VARIANT = HERE.parent
MODEL = VARIANT.parents[1]
REPOSITORY = MODEL.parents[1]
CONFIGURATIONS = ('baseline', 'anchor', 'candidate', 'fault')
JOBS = [(f'{c}-s{s}-w{w}', c, s, w)
        for c in CONFIGURATIONS[:3] for s in range(2) for w in range(3)]
JOBS += [(f'fault-s{s}', 'fault', s, None) for s in range(2)]
JOBS += [(f'candidate-s0-w{w}', 'candidate', 0, w) for w in (3, 4, 5)]


def need(ok, why):
    if not ok:
        raise ValueError(why)


def identity(path):
    with Path(path).open('rb') as stream:
        digest = hashlib.sha256()
        for block in iter(lambda: stream.read(65536), b''):
            digest.update(block)
        return dict(bytes=Path(path).stat().st_size, sha256=digest.hexdigest())


def read(path):
    return json.loads(Path(path).read_text())


def save(path, value):
    with Path(path).open('x') as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write('\n')


def check_sources():
    manifest = read(HERE / 'INPUTS.json')
    for key, root in (('package_files', HERE), ('public_files', REPOSITORY)):
        for name, expected in manifest[key].items():
            path = root / name
            need(not Path(name).is_absolute() and '..' not in Path(name).parts
                 and not path.is_symlink() and path.resolve().is_relative_to(root.resolve()),
                 'Unsafe source input: ' + name)
            need(identity(path) == expected, 'Changed source input: ' + name)
    # Every compiler-looking file in the selected directories must be listed.
    # Adding a source file must never silently expand compiler admission.
    for directory, root, pins in ((MODEL / 'hardware/design', REPOSITORY, manifest['public_files']),
                                  (VARIANT / 'rtl', REPOSITORY, manifest['public_files']),
                                  (HERE / 'numeric', HERE, manifest['package_files']),
                                  (HERE / 'fault', HERE, manifest['package_files'])):
        for path in directory.iterdir():
            if path.is_file() and path.suffix in ('.sv', '.v', '.vi', '.vh', '.cpp', '.h', '.hpp'):
                need(path.relative_to(root).as_posix() in pins, 'Unlisted compiler source: ' + str(path))
    return manifest


def source_map(configuration):
    need(configuration in CONFIGURATIONS, 'Unknown configuration')
    manifest = check_sources()
    selected = {}
    for name in manifest['compiler_public_files']:
        need(name in manifest['public_files'], 'Unpinned compiler input: ' + name)
        path = REPOSITORY / name
        need(path.name not in selected, 'Duplicate compiler filename: ' + path.name)
        selected[path.name] = path.read_bytes()
    reader = (HERE / 'baselines' / configuration / 'qwen_kvp_reader.sv'
              if configuration in ('baseline', 'anchor') else VARIANT / 'rtl/qwen_kvp_reader.sv')
    selected['qwen_kvp_reader.sv'] = reader.read_bytes()
    fixture = HERE / ('fault' if configuration == 'fault' else 'numeric')
    for name in ('top.sv', 'test.cpp') + (() if configuration == 'fault' else ('numeric_fixture.hpp',)):
        path = fixture / name
        need(path.name not in selected, 'Duplicate fixture filename: ' + path.name)
        selected[path.name] = path.read_bytes()
    # The unused fixed header is retained in the fault stage too, matching the
    # sealed experiment's compiler-input map exactly.
    selected.setdefault('numeric_fixture.hpp', (HERE / 'numeric/numeric_fixture.hpp').read_bytes())
    return selected


def prepare(output):
    output = output.resolve()
    need(not output.is_relative_to(REPOSITORY.resolve()), 'Output must be outside the repository/source tree')
    check_sources()
    need(not output.exists(), 'Output already exists; use a new directory')
    output.mkdir(parents=True)
    maps = {}
    for configuration in CONFIGURATIONS:
        directory = output / configuration
        source = directory / 'source'
        source.mkdir(parents=True)
        for name, data in source_map(configuration).items():
            (source / name).write_bytes(data)
        shutil.copyfile(MODEL / 'hardware/design/rom/softmax-exp2.hex', directory / 'softmax-exp2.hex')
        maps[configuration] = {p.name: identity(p) for p in source.iterdir()}
    save(output / 'PREPARED.json', dict(schema='qwen17-prefetch-prepared-v1',
         inputs=identity(HERE / 'INPUTS.json'), source_files=maps,
         runtime=identity(MODEL / 'hardware/design/rom/softmax-exp2.hex'),
         jobs=JOBS, external_cwd=str(output),
         external_commands={j[0]: external_invocation(output, j[0]) for j in JOBS},
         native_jobs_started=0))


def prepared(output):
    check_sources()
    record = read(output / 'PREPARED.json')
    need(record['inputs'] == identity(HERE / 'INPUTS.json') and record['jobs'] == [list(j) for j in JOBS],
         'Prepared input or fixed job plan changed')
    for c in CONFIGURATIONS:
        expected = {n: dict(bytes=len(data), sha256=hashlib.sha256(data).hexdigest())
                    for n, data in source_map(c).items()}
        need(record['source_files'][c] == expected, 'Prepared source derivation changed')
        need({p.name for p in (output / c / 'source').iterdir()} == set(expected), 'Staged source set changed')
        for name, pin in expected.items():
            need(identity(output / c / 'source' / name) == pin, 'Staged source changed: ' + name)
        need(identity(output / c / 'softmax-exp2.hex') == record['runtime'], 'Runtime ROM changed')
    return record


def child(argv, cwd, folder, seconds):
    folder.mkdir(parents=True, exist_ok=False)
    start = time.monotonic()
    receipt = dict(argv=list(map(str, argv)), cwd=str(cwd), automatic_retry=False,
                   started_utc=datetime.now(timezone.utc).isoformat(),
                   actual_child_exit=None, error=None, stop_reason=None)
    process = None
    try:
        with (folder / 'stdout.log').open('xb') as stdout, (folder / 'stderr.log').open('xb') as stderr:
            process = subprocess.Popen(argv, cwd=cwd, stdin=subprocess.DEVNULL,
                                       stdout=stdout, stderr=stderr, start_new_session=True)
            receipt['pid'] = process.pid
            try:
                receipt['actual_child_exit'] = process.wait(timeout=seconds)
            except subprocess.TimeoutExpired:
                receipt['stop_reason'] = 'finite_wall_time_limit'
    except BaseException as error:
        receipt['error'] = repr(error)
        raise
    finally:
        if process is not None and process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
        if process is not None:
            receipt['actual_child_exit'] = process.returncode
        receipt.update(elapsed_seconds=time.monotonic()-start,
                       stdout=identity(folder / 'stdout.log'), stderr=identity(folder / 'stderr.log'))
        save(folder / 'EXIT.json', receipt)
    need(receipt['actual_child_exit'] == 0 and not receipt['error'] and not receipt['stop_reason'],
         'Native child failed/stopped; preserve evidence and do not retry: ' + str(folder))
    return receipt


def build(output, seconds):
    record = prepared(output)
    need(not (output / 'BUILT.json').exists(), 'Existing build must not be overwritten')
    tool = shutil.which('verilator')
    need(tool, 'Verilator must be installed on PATH')
    binaries = {}; receipts = {}
    for c in CONFIGURATIONS:
        need(not (output / ('build-' + c)).exists(), 'Prior build attempt exists; no automatic retry')
        scratch = Path(tempfile.mkdtemp(prefix='qwen17-prefetch-'))
        need(not any(x.isspace() for x in str(scratch)), 'Compiler scratch path contains whitespace')
        source = scratch / 'source'
        shutil.copytree(output / c / 'source', source)
        flags = '-std=c++17 -O2 -ffp-contract=off -DPROTECTED_BUILD=1'
        argv = [tool, '--cc', '--exe', '--build', '--assert', '-Wno-fatal', '-j', '1', '--threads', '1',
                '--output-split', '12000', '--top-module', 'operand_test', '-I' + str(source),
                '-y', str(source), '+libext+.sv+.v', '-Mdir', str(scratch / 'obj'),
                '-o', 'operand-test', '-CFLAGS', flags, '+define+KV_PROTECTED']
        if c in ('candidate', 'fault'):
            argv.append('+define+FOLLOW_READER')
        argv += [str(p) for p in sorted(source.glob('*.v'))]
        argv += [str(source / 'top.sv'), str(source / 'test.cpp')]
        child(argv, scratch, output / ('build-' + c), seconds)
        warning = (output / ('build-' + c) / 'stderr.log').read_text()
        need('%Warning-UNOPTFLAT:' not in warning and '%Warning-MODDUP:' not in warning,
             'Feedback/duplicate-module compiler warning')
        for name, pin in record['source_files'][c].items():
            need(identity(source / name) == pin, 'Actual compiler copy changed')
        destination = output / c / 'operand-test'
        shutil.copyfile(scratch / 'obj/operand-test', destination)
        destination.chmod(0o755)
        binaries[c] = identity(destination)
        receipts[c] = identity(output / ('build-' + c) / 'EXIT.json')
    prepared(output)
    save(output / 'BUILT.json', dict(prepared=identity(output / 'PREPARED.json'), binaries=binaries, build_receipts=receipts,
                                   compile_workers=1, simulator_threads=1))


def checked_binary(output, configuration):
    prepared(output)
    built = read(output / 'BUILT.json')
    need(built['prepared'] == identity(output / 'PREPARED.json'), 'Build/preparation binding changed')
    receipt_path = output / ('build-' + configuration) / 'EXIT.json'
    need(identity(receipt_path) == built['build_receipts'][configuration], 'Build receipt changed')
    receipt = read(receipt_path)
    need(receipt['actual_child_exit'] == 0 and not receipt['stop_reason'] and not receipt['error'], 'Build did not pass')
    binary = output / configuration / 'operand-test'
    need(identity(binary) == built['binaries'][configuration], 'Executed binary changed')
    return binary


def job(name):
    found = [j for j in JOBS if j[0] == name]
    need(len(found) == 1, 'Unknown fixed case')
    return found[0]


def external_invocation(output, name):
    return [sys.executable, '-I', '-S', '-B', str(HERE / 'run.py'), 'exec',
            '--output', str(output), '--case', name]


def invocation(output, entry):
    _, configuration, stall, workload = entry
    argv = [str(checked_binary(output, configuration)), '+STALLS=' + str(stall)]
    if workload is not None:
        argv.append('+WORKLOAD=' + str(workload))
    return argv


def auditors():
    modules = []
    for name in ('audit_numeric', 'audit_fault', 'audit_security'):
        spec = importlib.util.spec_from_file_location(name, HERE / (name + '.py'))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        modules.append(module)
    return modules


def traffic(rows):
    result = {}
    for row in rows:
        if row['event'] == 'request':
            key = ('update' if row['update'] else 'attention') + ('_write' if row['write'] else '_read')
            value = result.setdefault(key, dict(requests=0, requested_bytes=0))
            value['requests'] += 1; value['requested_bytes'] += row['bytes']
    result['attention_return_bytes'] = 256 * sum(row['event'] == 'read_beat' for row in rows)
    return result


def queue_lifecycle(rows, workload):
    allocations = {row['cycle']: row for row in rows if row['event'] == 'allocation'}
    episodes = []; previous = None
    for row in (r for r in rows if r['event'] == 'follow_pending'):
        key = (row['phase'], row['head_index'], row['layer'], row['head'], row['group'])
        need(row['layer'] == 0 and row['head'] == [0, 1, 0][row['head_index']], 'Queued descriptor escaped head')
        context = 2 if workload < 2 else [16, 17, 33][row['phase']]
        need(0 < row['group'] < (context + 15)//16, 'Queued descriptor escaped committed prefix')
        if previous is None or previous[0] != key or previous[1] + 1 != row['cycle']:
            allocation = allocations.get(row['cycle'])
            need(allocation is not None and allocation['new_tag'] == row['head']*2048 + row['group'],
                 'Queued descriptor not bound to actual K allocation')
            episodes.append(dict(head=row['head'], group=row['group'], last_pending=row['cycle']))
        episodes[-1]['last_pending'] = row['cycle']; previous = (key, row['cycle'])
    for episode in episodes:
        allocation = allocations.get(episode['last_pending'] + 1)
        need(allocation is not None and allocation['new_tag'] == (episode['head'] + 8)*2048 + episode['group'],
             'Queued descriptor did not reserve matching V')
    need(len(episodes) == (0 if workload < 2 else 9), 'Wrong bounded queue episode count')
    return episodes


def audit_case(output, entry):
    name, configuration, stall, workload = entry
    folder = output / 'runs' / name
    receipt = read(folder / 'EXIT.json')
    need(receipt['actual_child_exit'] == 0 and not receipt.get('error') and not receipt.get('stop_reason')
         and receipt.get('passed', True), 'Actual native case failed: ' + name)
    actual = receipt.get('argv', receipt.get('command'))
    direct = invocation(output, entry)
    external = external_invocation(output, name)
    need((actual == direct and receipt['cwd'] == str(output / configuration))
         or (actual == external and receipt['cwd'] == str(output)), 'Native invocation identity differs')
    for leaf in ('stdout', 'stderr'):
        if leaf in receipt:
            need(identity(folder / (leaf + '.log')) == receipt[leaf], 'Native log binding changed')
    need(not (folder / 'stderr.log').read_bytes(), 'Native stderr is not empty')
    numeric, fault, security = auditors()
    if configuration == 'fault':
        rows = fault.read_rows(folder / 'stdout.log')
        need([x['scenario'] for x in rows if x['event'] == 'result'] == list(range(5)), 'Fault case ordering/count differs')
        detail = [fault.check_case([x for x in rows if x['scenario'] == s], s, stall) for s in range(5)]
    else:
        rows = numeric.read_rows(folder / 'stdout.log')
        detail = numeric.audit(rows, stall, workload) if workload < 3 else security.audit(rows, workload)
        if workload < 3 and configuration == 'candidate':
            detail['queue_episodes'] = queue_lifecycle(rows, workload)
    return rows, detail


def verify(output):
    prepared(output)
    need(not (output / 'VERIFIED.json').exists(), 'Existing verification must not be overwritten')
    details = {}; logs = {}; data = {}
    for entry in JOBS:
        rows, detail = audit_case(output, entry)
        data[entry[0]] = rows
        details[entry[0]] = detail
        logs[entry[0]] = {n: identity(output / 'runs' / entry[0] / n)
                         for n in ('EXIT.json', 'stdout.log', 'stderr.log')}
    comparisons = []
    for stall in range(2):
        for workload in range(3):
            group = {c: details[f'{c}-s{stall}-w{workload}'] for c in CONFIGURATIONS[:3]}
            baseline = group['baseline']
            for c, value in group.items():
                need(value['attention_policy_descriptors'] == baseline['attention_policy_descriptors'], 'Descriptor traffic/policy mismatch')
                need(len(value['sequences']) == len(baseline['sequences']), 'Sequence count differs')
                need(traffic(data[f'{c}-s{stall}-w{workload}']) == traffic(data[f'baseline-s{stall}-w{workload}']),
                     'Whole-case requested/accepted traffic mismatch')
            for c in ('anchor', 'candidate'):
                value = group[c]
                whole = baseline['case']['cycle'] - value['case']['cycle']
                sequences = [dict(context=a['context'], baseline=a, candidate=b,
                                  saved_through_quiescence=a['through_quiescence']-b['through_quiescence'])
                             for a, b in zip(baseline['sequences'], value['sequences'])]
                summed = sum(x['saved_through_quiescence'] for x in sequences)
                need(whole == summed, 'Work moved outside measured sequences')
                comparisons.append(dict(reader=c, stall=stall, workload=workload, sequences=sequences,
                                        whole_case_cycles_saved=whole, sum_sequence_cycles_saved=summed))
        for c in CONFIGURATIONS[:3]:
            first = [x['outputs'] for x in data[f'{c}-s{stall}-w0'] if x['event']=='numerical_result']
            changed = [x['outputs'] for x in data[f'{c}-s{stall}-w1'] if x['event']=='numerical_result']
            need(all(a != b for x,y in zip(first,changed) for p,q in zip(x,y) for a,b in zip(p,q)),
                 'K-only change did not change every output word')
    result = dict(schema='qwen17-prefetch-comparison-v1', passed=True,
                  verified_utc=datetime.now(timezone.utc).isoformat(), numeric_jobs=18,
                  fault_jobs=2, fault_cases=10, later_group_security_jobs=3,
                  numerical_words=sum(details[j[0]]['numerical_words_compared'] for j in JOBS[:18]),
                  comparisons=comparisons, cases=details, receipts=logs,
                  inputs=identity(HERE / 'INPUTS.json'), built=identity(output / 'BUILT.json'),
                  scope='Finite contexts 2/16/17/33, two KV heads, three groups; simulated cycles only. No model, board, physical timing or general proof.')
    save(output / 'VERIFIED.json', result)
    return result


def main():
    need(sys.flags.optimize == 0 and __debug__, 'Run with Python assertions enabled')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('check-sources', 'prepare', 'build', 'run', 'verify', 'exec'))
    parser.add_argument('--output', type=Path)
    parser.add_argument('--case', choices=[j[0] for j in JOBS])
    parser.add_argument('--max-seconds', type=int, default=3600, help='Finite per-child wall limit for build/run')
    args = parser.parse_args()
    check_sources()
    if args.action == 'check-sources':
        print(json.dumps(dict(source_checks_passed=True, native_jobs_started=0)))
        return
    need(args.output is not None, '--output is required')
    output = args.output.resolve()
    need(1 <= args.max_seconds <= 86400, 'Invalid wall limit')
    if args.action == 'prepare':
        prepare(output)
    elif args.action == 'build':
        build(output, args.max_seconds)
    elif args.action == 'verify':
        result = verify(output)
        print(json.dumps({k: result[k] for k in ('passed', 'numeric_jobs', 'fault_cases', 'later_group_security_jobs', 'numerical_words')}))
    elif args.action == 'exec':
        need(args.case is not None, '--case is required for one guarded direct child')
        entry = job(args.case)
        argv = invocation(output, entry)
        os.chdir(output / entry[1])
        os.execv(argv[0], argv)
    else:
        need(not (output / 'runs').exists(), 'Prior run attempt exists; use new evidence, never retry automatically')
        for entry in JOBS:
            child(invocation(output, entry), output / entry[1], output / 'runs' / entry[0], args.max_seconds)
            audit_case(output, entry)
        verify(output)


if __name__ == '__main__':
    main()
