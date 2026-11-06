"""Small frozen-source RTL arithmetic regressions; no model, FPGA or network.

Builds are sequential, with bounded compiler parallelism. Outputs must use a
fresh whitespace-free path because generated native makefiles require it.
This finite regression is not a formal proof or full-core qualification.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
DOT = ('private_dot8_accumulator.sv',)
SCALE = ('HardFloat_primitives.v', 'HardFloat_specialize.v', 'HardFloat_rawFN.v',
         'iNToRecFN.v', 'fNToRecFN.v', 'recFNToRecFN.v', 'recFNToFN.v', 'isSigNaNRecFN.v',
         'mulRecFN.v', 'qwen_fp32_mul_stage.sv', 'qwen_projection_scale.sv')
HEADERS = ('HardFloat_consts.vi', 'HardFloat_localFuncs.vi', 'HardFloat_specialize.vi')


def need(condition, message):
    if not condition:
        raise ValueError(message)


def identity(path):
    with path.open('rb') as stream:
        return dict(bytes=path.stat().st_size, sha256=hashlib.file_digest(stream, 'sha256').hexdigest())


def save(path, value):
    with path.open('x') as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write('\n')


def plans(suite):
    need(suite in ('all', 'dot8', 'scale'), 'Unknown suite')
    cases = []
    if suite in ('all', 'dot8'):
        for groups in (1, 512, 1536):
            cases.append(dict(name=f'dot8-g{groups}', top='private_dot8_accumulator',
                              groups=groups, sources=DOT, headers=(), bench='dot8.cpp'))
    if suite in ('all', 'scale'):
        cases.append(dict(name='scale', top='qwen_projection_scale', groups=None,
                          sources=SCALE, headers=HEADERS, bench='scale.cpp'))
    return cases


def verify_sources(cases, root=ROOT):
    manifest = json.loads((root/'SOURCE-INPUTS.json').read_text())
    required = {'qwen_projection_engine.sv'}
    for case in cases:
        required.update(case['sources']+case['headers'])
    result = {}
    for name in sorted(required):
        relative = 'hardware/design/'+name
        path = root/relative
        need(path.is_file() and not path.is_symlink() and path.resolve().is_relative_to(root.resolve()),
             'Missing/unsafe frozen RTL input: '+name)
        row = identity(path)
        need(row == manifest['frozen_hardware_inputs'][relative], 'Changed frozen RTL input: '+name)
        result[name] = row
    engine = (root/'hardware/design/qwen_projection_engine.sv').read_text()
    need('qwen_projection_tile32_overlap #(.GROUPS(512)) tile_short' in engine
         and 'qwen_projection_tile32_overlap #(.GROUPS(1536)) tile_long' in engine,
         'Selected production geometry changed')
    return dict(source_manifest=identity(root/'SOURCE-INPUTS.json'), files=result,
                production_groups=[512, 1536], parameter_edge_case_groups=[1])


def validate_summary(case, result):
    need(result.get('passed') is True, 'Native regression did not report success')
    need(all(type(value) is int and value >= 0 for key, value in result.items() if key != 'passed'),
         'Native counts must be nonnegative integers')
    if case['groups'] is not None:
        need(result['groups'] == case['groups'] and result['frames'] == 326
             and result['accepted_beats'] == case['groups']*326
             and result['checked_products'] == result['accepted_beats']*8
             and result['cancellations'] == 6
             and result['input_bubbles'] > 0 and result['held_checks'] > 0,
             'Incomplete dot8 arithmetic/protocol coverage')
    else:
        need(result['inputs'] == 12000 and result['checked']+result['cancelled'] == 12000
             and result['checked'] > 0 and result['clears'] > 0 and result['resets'] > 0
             and result['held_checks'] > 0 and result['error_results'] > 0,
             'Incomplete scaling arithmetic/protocol coverage')


def command(argv, cwd, directory, timeout):
    directory.mkdir()
    started = datetime.now(timezone.utc).isoformat()
    tick = time.monotonic()
    timed_out = False
    interruption = None
    with (directory/'stdout.log').open('xb') as stdout, (directory/'stderr.log').open('xb') as stderr:
        child = subprocess.Popen(argv, cwd=cwd, stdin=subprocess.DEVNULL, stdout=stdout, stderr=stderr,
                                 start_new_session=True)
        try:
            actual = child.wait(timeout=timeout)
        except BaseException as error:
            interruption = dict(type=type(error).__name__, message=str(error))
            # Only this unreaped child group is owned by this runner.
            if child.poll() is None:
                need(os.getpgid(child.pid) == child.pid, 'Owned native group identity changed')
                os.killpg(child.pid, signal.SIGTERM)
                try:
                    actual = child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    need(os.getpgid(child.pid) == child.pid, 'Owned native group identity changed')
                    os.killpg(child.pid, signal.SIGKILL)
                    actual = child.wait(timeout=5)
            else:
                actual = child.returncode
            timed_out = True
    record = dict(command=argv, started_utc=started, elapsed_seconds=time.monotonic()-tick,
                  actual_child_exit=actual, interrupted_or_timed_out=timed_out,
                  interruption=interruption,
                  stdout=identity(directory/'stdout.log'), stderr=identity(directory/'stderr.log'))
    save(directory/'EXIT.json', record)
    need(actual == 0 and not timed_out, 'Native stage failed/interrupted; preserve its actual logs')
    return record


def run_case(case, output, binding, verilator, jobs):
    folder = output/case['name']
    folder.mkdir()
    source = folder/'source'
    source.mkdir()
    inputs = {}
    for name in case['sources']+case['headers']:
        target = source/name
        shutil.copyfile(ROOT/'hardware/design'/name, target)
        need(identity(target) == binding['files'][name], 'Staged RTL input changed')
        inputs[name] = identity(target)
    bench = source/case['bench']
    shutil.copyfile(HERE/case['bench'], bench)
    need(identity(bench) == identity(HERE/case['bench']), 'Bench changed while staging')
    inputs[case['bench']] = identity(bench)
    flags = '-std=c++17 -O2 -ffp-contract=off'
    if case['groups'] is not None:
        flags += ' -DTEST_GROUPS='+str(case['groups'])
    argv = [str(verilator), '--cc', '--exe', '--build', '--assert', '-Wno-fatal',
            '--top-module', case['top'], '-j', str(jobs), '-Mdir', str(folder/'build'),
            '-I'+str(source), '-CFLAGS', flags]
    if case['groups'] is not None:
        argv += ['-GGROUPS='+str(case['groups'])]
    argv += [str(source/name) for name in case['sources']]+[str(bench)]
    save(folder/'INPUTS.json', dict(case=case, source_files=inputs))
    build = command(argv, folder, folder/'compile', 180)
    binary = folder/'build'/('V'+case['top'])
    binary_id = identity(binary)
    execute = command([str(binary)], folder, folder/'execute', 60)
    result = json.loads((folder/'execute/stdout.log').read_text())
    validate_summary(case, result)
    for name, expected in inputs.items():
        need(identity(source/name) == expected, 'Native input changed during execution')
    need(identity(binary) == binary_id, 'Native binary changed during execution')
    record = dict(passed=True, finite_regression_only=True, source_files=inputs, binary=binary_id,
                  compile=build, execute=execute, checks=result)
    save(folder/'FINISHED.json', record)
    return record


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--suite', choices=('all', 'dot8', 'scale'), default='all')
    parser.add_argument('--plan', action='store_true')
    parser.add_argument('--output', type=Path, help='Fresh whitespace-free directory outside the release')
    parser.add_argument('--jobs', type=int, choices=(1, 2, 3, 4), default=2)
    parser.add_argument('--verilator', type=Path)
    args = parser.parse_args(argv)
    cases = plans(args.suite)
    binding = verify_sources(cases)
    if args.plan:
        print(json.dumps(dict(cases=cases, binding=binding, native_tools_run=False,
                              hardware_access=False, network_access=False), indent=2))
        return 0
    need(args.output is not None, 'Choose a fresh --output directory')
    output = args.output.resolve()
    need(not output.exists() and not any(character.isspace() for character in str(output))
         and not output.is_relative_to(ROOT.resolve()), 'Output must be fresh, whitespace-free and outside the demo')
    executable = args.verilator or shutil.which('verilator')
    need(executable is not None, 'Install Verilator through its normal distribution; no automatic download')
    verilator = Path(executable).resolve()
    need(verilator.is_file() and os.access(verilator, os.X_OK), 'Verilator executable unavailable')
    output.mkdir()
    record = dict(started_utc=datetime.now(timezone.utc).isoformat(), binding=binding,
                  runner=identity(Path(__file__)), verilator=identity(verilator),
                  compiler_jobs=args.jobs, sequential_builds=True, automatic_retry=False,
                  FPGA_accessed=False, AWS_accessed=False, model_loaded=False,
                  scope='Finite dot8/scaling arithmetic and local synchronous protocol cases only; not full tile/core, authentication, CDC, timing or security qualification.',
                  cases=[])
    save(output/'STARTED.json', record)
    start = time.monotonic()
    try:
        command([str(verilator), '--version'], output, output/'tool-version', 10)
        for case in cases:
            record['cases'].append(dict(name=case['name'], result=run_case(case, output, binding, verilator, args.jobs)))
        need(verify_sources(cases) == binding, 'Original source binding changed during regression')
    except BaseException as error:
        record.update(passed=False, error=dict(type=type(error).__name__, message=str(error)),
                      elapsed_seconds=time.monotonic()-start)
        save(output/'FAILED.json', record)
        raise
    record.update(passed=True, elapsed_seconds=time.monotonic()-start)
    save(output/'FINISHED.json', record)
    print(json.dumps(dict(output=str(output), passed=True, cases=len(record['cases']),
                          elapsed_seconds=record['elapsed_seconds'], finite_regression_only=True,
                          FPGA_accessed=False, AWS_accessed=False), indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
