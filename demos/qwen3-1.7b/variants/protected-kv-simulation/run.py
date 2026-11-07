#!/usr/bin/env python3
"""Offline elaboration and deterministic store-to-attention regression.

No private imports, model files, downloads, vendor tools or board access.
Each invocation creates new evidence; it never retries a failed process.
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
import sys
import tempfile
import time

HERE = Path(__file__).resolve().parent
MODEL = HERE.parents[1]
DESIGN = MODEL / 'hardware/design'
CONFIGURATIONS = ('plain', 'protected')


def need(condition, message):
    if not condition:
        raise RuntimeError(message)


def identity(path):
    data = path.read_bytes()
    return {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}


def save(path, value):
    with path.open('x') as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write('\n')


def check_sources():
    manifest = json.loads((HERE / 'SOURCE-INPUTS.json').read_text())
    for name, pin in manifest['variant_files'].items():
        need(identity(HERE / name) == pin, 'Variant source differs: ' + name)
    for name, pin in manifest['shared_public_files'].items():
        need(identity(MODEL / name) == pin, 'Shared public dependency differs: ' + name)
    plain = (DESIGN / 'qwen_verified_machine.sv').read_text()
    protected = (HERE / 'rtl/qwen_protected_machine.sv').read_text()
    # Compare every functional line. Only the module name and store selection differ.
    functional = lambda text: '\n'.join(line for line in text.splitlines()
                                        if not line.lstrip().startswith('//'))
    expected = plain.replace('module qwen_verified_machine #(', 'module qwen_protected_machine #(')
    expected = expected.replace(
        'qwen_kv_plain_store #(.CACHE_GROUPS(KV_CACHE_GROUPS),\n        .PREFETCH_GROUPS(KV_PREFETCH_GROUPS))',
        'qwen_kvp_store #(.CACHE_GROUPS(KV_CACHE_GROUPS),\n        .AUTH_SLOTS(KV_AUTH_SLOTS),.PREFETCH_GROUPS(KV_PREFETCH_GROUPS))')
    need(functional(protected) == functional(expected), 'Protected machine differs beyond its declared selection')
    need('qwen_kv_plain_store.sv' in (MODEL / 'hardware/build/scripts/qwen_sources.tcl').read_text(),
         'Published FPGA source selection is not plain')
    return manifest


def command(argv, cwd, directory, timeout):
    directory.mkdir()
    start = time.monotonic()
    receipt = {'argv': [str(arg) for arg in argv], 'cwd': str(cwd),
               'started_utc': datetime.now(timezone.utc).isoformat(),
               'timeout_seconds': timeout, 'automatic_retry': False}
    process = None
    try:
        with (directory / 'stdout.log').open('wb') as stdout, (directory / 'stderr.log').open('wb') as stderr:
            process = subprocess.Popen(argv, cwd=cwd, stdout=stdout, stderr=stderr, start_new_session=True)
            receipt['pid'] = process.pid
            try:
                receipt['actual_child_exit'] = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                receipt['stop_reason'] = 'process_timeout'
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    receipt['actual_child_exit'] = process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    receipt['actual_child_exit'] = process.wait()
        receipt['elapsed_seconds'] = time.monotonic() - start
        receipt['ended_utc'] = datetime.now(timezone.utc).isoformat()
        save(directory / 'EXIT.json', receipt)
        need(receipt['actual_child_exit'] == 0 and not receipt.get('stop_reason'),
             'Process failed or was interrupted; see ' + str(directory))
        return receipt
    except BaseException:
        if process is not None and process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
        raise


def build(output):
    manifest = check_sources()
    output.mkdir()
    tool = shutil.which('verilator')
    need(tool is not None, 'Install Verilator and a C++17 compiler before running')
    version = subprocess.run([tool, '--version'], check=True, text=True, capture_output=True).stdout.strip()
    save(output / 'STARTED.json', {'public_base': manifest['public_base'], 'sources': identity(HERE / 'SOURCE-INPUTS.json'),
         'verilator': version, 'started_utc': datetime.now(timezone.utc).isoformat(),
         'compile_workers': 1, 'simulator_threads': 1, 'downloads': False, 'vendor_or_cloud_jobs': False})
    search = ['-I' + str(DESIGN), '-y', str(DESIGN), '-y', str(HERE / 'rtl'), '+libext+.sv+.v']
    # HardFloat keeps multiple differently named modules in several .v files.
    # A filename-based -y search alone cannot resolve those grouped modules.
    hardfloat = [str(path) for path in sorted(DESIGN.glob('*.v'))]
    for top, source in (('qwen_verified_machine', DESIGN / 'qwen_verified_machine.sv'),
                        ('qwen_protected_machine', HERE / 'rtl/qwen_protected_machine.sv')):
        command([tool, '--lint-only', '--assert', '-Wno-fatal', '--top-module', top,
                 *search, *hardfloat, str(source)], HERE, output / ('elaborate-' + top), 600)
    binaries = {}
    source_copies = {}
    for configuration in CONFIGURATIONS:
        result = output / configuration
        result.mkdir()
        shutil.copyfile(DESIGN / 'rom/softmax-exp2.hex', result / 'softmax-exp2.hex')
        # Verilator's generated make invocation cannot quote a spaced Mdir.
        # Compile in a fresh unspaced scratch directory, retaining its exact copies.
        work = Path(tempfile.mkdtemp(prefix='qwen17-kv-', dir='/tmp'))
        need(not any(char.isspace() for char in str(work)), 'Compiler scratch path must not contain whitespace')
        source = work / 'source'
        source.mkdir()
        copies = {}
        for directory in (DESIGN, HERE / 'rtl', HERE / 'tests'):
            for path in sorted(directory.iterdir()):
                if path.is_file() and path.suffix in ('.sv', '.v', '.vi', '.vh', '.cpp', '.hpp', '.h'):
                    target = source / path.name
                    need(not target.exists(), 'Duplicate selected source name: ' + path.name)
                    shutil.copyfile(path, target)
                    need(identity(target) == identity(path), 'Compiler copy differs: ' + path.name)
                    copies[path.name] = identity(path)
        source_copies[configuration] = {'directory': str(source), 'files': copies}
        local_search = ['-I' + str(source), '-y', str(source), '+libext+.sv+.v']
        flags = '-std=c++17 -O2 -ffp-contract=off -DPROTECTED_BUILD=' + str(int(configuration == 'protected'))
        argv = [tool, '--cc', '--exe', '--build', '--assert', '-Wno-fatal', '-j', '1', '--threads', '1',
                '--output-split', '12000', '--top-module', 'operand_test', *local_search,
                '-Mdir', str(work / 'obj'), '-o', 'operand-test', '-CFLAGS', flags]
        if configuration == 'protected':
            argv.append('+define+KV_PROTECTED')
        argv += [*[str(path) for path in sorted(source.glob('*.v'))], str(source / 'top.sv'), str(source / 'test.cpp')]
        command(argv, work, output / ('build-' + configuration), 1800)
        for name, pin in copies.items():
            need(identity(source / name) == pin, 'Compiled source changed: ' + name)
        shutil.copyfile(work / 'obj/operand-test', result / 'operand-test')
        (result / 'operand-test').chmod(0o755)
        binaries[configuration] = identity(result / 'operand-test')
    for log in output.glob('*/stderr.log'):
        warning = log.read_text()
        need('%Warning-UNOPTFLAT:' not in warning and '%Warning-MODDUP:' not in warning,
             'Feedback or duplicate module warning in ' + str(log))
    check_sources()
    save(output / 'BUILT.json', {'passed': True, 'binaries': binaries, 'source_copies': source_copies,
         'sources': identity(HERE / 'SOURCE-INPUTS.json'), 'both_machine_tops_elaborated': True})


def checked_binary(output, configuration):
    check_sources()
    built = json.loads((output / 'BUILT.json').read_text())
    need(built['passed'] and built['sources'] == identity(HERE / 'SOURCE-INPUTS.json'), 'Build source identity differs')
    binary = output / configuration / 'operand-test'
    need(identity(binary) == built['binaries'][configuration], 'Compiled binary differs')
    need(identity(output / configuration / 'softmax-exp2.hex') == identity(DESIGN / 'rom/softmax-exp2.hex'), 'Runtime ROM differs')
    return binary


def review_logs(plain_log, protected_log):
    results = {}
    for configuration, log in (('plain', plain_log), ('protected', protected_log)):
        lines = log.read_text().splitlines()
        need(lines[-1:] == ['PASS operand_integrity_observation protected=' + str(int(configuration == 'protected'))],
             'Original terminal PASS absent: ' + configuration)
        events = [json.loads(line) for line in lines if line.startswith('{')]
        rows = [row for row in events if row['event'] == 'result']
        need([row['scenario'] for row in rows] == list(range(5)), 'Incomplete or duplicate scenarios')
        for row in rows:
            need(row['protected_build'] == (configuration == 'protected'), 'Wrong compiled configuration')
            scenario = row['scenario']
            need(row['actual_writes'] == (2 if scenario == 4 else 1), 'Actual writer publication coverage')
            need(row['independent_roots'] == (row['actual_writes'] if configuration == 'protected' else 0), 'Root coverage')
            if scenario in (1, 2):
                wanted = 'fault_prevents_target_use' if configuration == 'protected' else 'changed_operand_used'
                need(row['outcome'] == wanted, 'Mutation control did not reach expected boundary')
                fault = [event for event in events if event['scenario'] == scenario and event['event'] == 'fault_edge']
                consumed = [event for event in events if event['scenario'] == scenario and event['event'] == 'operand_handshake']
                role = scenario - 1
                if configuration == 'protected':
                    need(len(fault) == 1 and fault[0]['auth_error'] and fault[0]['key_valid' if role == 0 else 'value_valid'] is False,
                         'Authentication fault did not block the affected valid signal')
                    need(not any(event['role'] == role for event in consumed), 'Affected protected operand was consumed')
                else:
                    need(not fault and any(event['role'] == role and event['changed'] for event in consumed),
                         'Plain mutation did not reach the real attention handshake')
            else:
                need(row['outcome'] == 'original_operand_used' and row['fault_cycle'] == 0
                     and not row['changed_key_used'] and not row['changed_value_used'], 'Honest/captured/recovery mismatch')
            if scenario == 4:
                need(0 < row['clear_cycle'] < row['old_return_cycle'] < row['reopen_cycle']
                     and row['blocked_clear_checks'] > 0, 'Modeled delayed-return drain coverage absent')
        results[configuration] = rows
    return {'passed': True, 'results': results, 'checks': 'actual writer publication, independent SHA roots, actual attention operands',
            'physical_CDC_HBM_or_full_model_qualification': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True, help='New result directory (existing only with --exec or --verify-logs)')
    group = parser.add_mutually_exclusive_group()
    group.add_argument('--build-only', action='store_true')
    group.add_argument('--exec', choices=CONFIGURATIONS, help='Exec one already-built simulator for an external direct-child guard')
    group.add_argument('--verify-logs', type=Path, nargs=2, metavar=('PLAIN', 'PROTECTED'))
    args = parser.parse_args()
    output = args.output.resolve()
    if args.exec:
        binary = checked_binary(output, args.exec)
        os.chdir(output / args.exec)
        os.execv(binary, [str(binary)])
    if args.verify_logs:
        check_sources()
        result = review_logs(*args.verify_logs)
        save(output / 'VERIFIED.json', result)
        print(json.dumps({'passed': True, 'configurations': 2, 'cases_per_configuration': 5}))
        return
    build(output)
    if args.build_only:
        print(json.dumps({'built': True, 'machine_tops': 2, 'component_configurations': 2}))
        return
    logs = []
    for configuration in CONFIGURATIONS:
        binary = checked_binary(output, configuration)
        directory = output / ('run-' + configuration)
        command([str(binary)], output / configuration, directory, 120)
        need(not (directory / 'stderr.log').read_bytes(), 'Simulator stderr was not empty')
        logs.append(directory / 'stdout.log')
    result = review_logs(*logs)
    save(output / 'VERIFIED.json', result)
    print(json.dumps({'passed': True, 'machine_tops': 2, 'configurations': 2, 'cases_per_configuration': 5}))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('FAIL protected-kv-simulation: ' + str(error), file=sys.stderr)
        raise
