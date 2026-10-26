"""Rebuild and replay the source-bound real-model RTL and corruption checks."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import time

assert sys.flags.isolated and sys.flags.no_site and sys.flags.dont_write_bytecode
assert not sys.flags.optimize
MARKERS = ('BOOT_AUTHENTICATED ', 'SEMANTIC_STEP ', 'CLEAR_TRACE ', 'SEMANTIC_RNE ',
    'PROFILE_WORKLOAD ', 'PASS ', 'QUERY_CAPTURE_MONITOR ', 'ELEMENTWISE_MODEL_MONITOR ',
    'NORMALIZER_MODEL_MONITOR ', 'FCP_MODEL_MONITOR ', 'SHP_MODEL_MONITOR ',
    'HDP_MODEL_MONITOR ', 'THIN_TRANSPORT_MONITOR ', 'THIN_APP_MODEL_CLOCK ')
FATAL = r'%Error|%Fatal|%Warning-MULTIDRIVEN|Assertion failed|Aborting|GLOBAL_TIMEOUT'
CASES = {'zero': ['+ZERO_STALL'], 'stalled': [],
         'corrupt-boot': ['+ZERO_STALL', '+CORRUPT_BOOT'],
         'corrupt-runtime': ['+ZERO_STALL', '+CORRUPT_RUNTIME']}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def put(path, value):
    with path.open('x') as out:
        json.dump(value, out, indent=2, sort_keys=True)
        out.write('\n')


def check_case_log(text, code, expected_markers):
    """Require every recorded observation; silence/timeouts cannot pass."""
    markers = [line for line in text.splitlines() if line.startswith(MARKERS)]
    return (code == 0 and not re.search(FATAL, text)
        and any(line.startswith('PASS ') for line in expected_markers)
        and markers == expected_markers)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', type=Path, required=True)
    parser.add_argument('--image', type=Path, required=True)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--verilator', default='verilator')
    parser.add_argument('--jobs', type=int, default=4)
    parser.add_argument('--build-jobs', type=int, default=8)
    parser.add_argument('--timeout-seconds', type=int, default=1800)
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    if not args.image.is_file():
        parser.error('--image must name the binary file, not its directory: '
                     'fpga-image/board1-real-semantic-image2048.bin '
                     '(or the included assets/board1-real-semantic-image2048.bin)')
    assert 1 <= args.jobs <= 4 and 1 <= args.build_jobs <= 32 and args.timeout_seconds >= 60
    package, work = args.package.resolve(strict=True), args.work.absolute()
    assert not work.resolve().is_relative_to(package)
    assert not any(c.isspace() for c in str(work)), 'Use a whitespace-free work path or alias.'
    source = package / 'simulation/model'
    manifest = json.loads((package / 'MANIFEST.json').read_text())
    files = {}
    def read_pinned(path, digest, size=None):
        assert path.is_file() and not path.is_symlink(), path
        data = path.read_bytes()
        assert sha(data) == digest, path
        if size is not None:
            assert len(data) == size, path
        return data
    row = manifest['files']['simulation/model/MANIFEST.json']
    helper_manifest = json.loads(read_pinned(source / 'MANIFEST.json', row['sha256'], row['bytes']))
    row = helper_manifest['files']['expected.json']
    expected = json.loads(read_pinned(source / 'expected.json', row['sha256'], row['bytes']))
    assert expected['historical_image_sha256'] == manifest['image_sha256']
    assert all(not p.is_symlink() for p in source.rglob('*'))
    assert {p.relative_to(source).as_posix() for p in source.rglob('*') if p.is_file()} == set(helper_manifest['files']) | {'MANIFEST.json'}
    for name, row in helper_manifest['files'].items():
        assert not PurePosixPath(name).is_absolute() and '..' not in PurePosixPath(name).parts
        relative = 'simulation/model/' + name
        assert manifest['files'][relative] == row
        data = read_pinned(source / name, row['sha256'], row['bytes'])
        if name in expected['test_source_sha256']:
            assert sha(data) == expected['test_source_sha256'][name]
            files[name] = data
    assert set(files) == set(expected['test_source_sha256'])
    for name, digest in expected['production_source_sha256'].items():
        assert not PurePosixPath(name).is_absolute() and '..' not in PurePosixPath(name).parts
        relative = 'hardware/project/' + name
        assert manifest['files'][relative]['sha256'] == digest
        files[name] = read_pinned(package / relative, digest, manifest['files'][relative]['bytes'])
    assert len(set(expected['production_compile_order'])) == len(expected['production_compile_order']) == 64
    assert set(expected['production_source_sha256']) == set(expected['production_compile_order']) | set(expected['rom_files'])
    assert len(expected['rom_files']) == 4 and len(expected['reference_sources']) == 5
    assert expected['production_compile_order'] == files['production_sources.f'].decode().splitlines()
    assert set(expected['expected_markers']) == set(CASES)
    image = read_pinned(args.image, expected['image_sha256'], expected['image_bytes'])
    assert len(image) == 7_265_984 and len(image) % 32 == 0
    image_memh = b''.join(image[i:i+32][::-1].hex().encode() + b'\n' for i in range(0, len(image), 32))
    assert sha(image_memh) == expected['image_memh_sha256']
    # Independently undo serialization before any simulator sees the data.
    assert b''.join(bytes.fromhex(line.decode())[::-1] for line in image_memh.splitlines()) == image
    files['image.memh'] = image_memh
    files['replayer.py'] = Path(__file__).read_bytes()
    pins = {name: {'sha256': sha(data), 'bytes': len(data)} for name, data in files.items()}
    binding = {'package_manifest_sha256': sha((package / 'MANIFEST.json').read_bytes()),
        'test_manifest_sha256': sha((source / 'MANIFEST.json').read_bytes()),
        'expected_sha256': sha((source / 'expected.json').read_bytes()),
        'files': pins, 'production_compile_order': expected['production_compile_order'],
        'hardware_access': False, 'network_access': False}

    def audit_record(record):
        assert record['passed'] and record['input_sha256'] == sha((work / 'INPUTS.json').read_bytes())
        assert json.loads((work / 'INPUTS.json').read_text()) == binding
        for name, row in pins.items():
            read_pinned(work / name, row['sha256'], row['bytes'])
        assert set(record['cases']) == set(CASES)
        for name, row in [('compile', record['build'])] + list(record['cases'].items()):
            text = read_pinned(work / (name + '.log'), row['log_sha256']).decode()
            assert row['exit'] == 0 and not re.search(FATAL, text), name
            execution = json.loads((work / (name + '-EXECUTION.json')).read_text())
            assert execution == {k: v for k, v in row.items() if k != 'passed'}
            assert json.loads((work / (name + '-STARTED.json')).read_text())['argv'] == row['argv']
            if name != 'compile':
                assert row['argv'] == [str(work / 'obj/Vtb_board1_booted_shared_semantic'), '+IMAGE_MEMH=image.memh', '+PROFILE_CASE=0'] + CASES[name]
                assert check_case_log(text, row['exit'], expected['expected_markers'][name]), name
                markers = [line for line in text.splitlines() if line.startswith(MARKERS)]
                assert markers == row['markers'] and row['passed']
        assert sha((work / 'obj/Vtb_board1_booted_shared_semantic').read_bytes()) == record['executable_sha256']

    if args.verify_only:
        audit_record(json.loads((work / 'FINISHED.json').read_text()))
        print('MODEL_RTL_REPLAY_VERIFY passed=True cases=4 hardware_access=0', flush=True)
        return 0
    work.mkdir(parents=True, exist_ok=False)
    for name, data in files.items():
        target = work / name
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open('xb') as out:
            out.write(data)
    put(work / 'INPUTS.json', binding)

    def execute(name, argv, timeout):
        start = time.monotonic()
        with (work / (name + '.log')).open('xb') as log:
            child = subprocess.Popen(argv, cwd=work, stdout=log, stderr=subprocess.STDOUT)
            put(work / (name + '-STARTED.json'), {'pid': child.pid, 'argv': argv, 'hardware_access': False})
            try:
                code = child.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                child.terminate()
                try:
                    child.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()
                code = 124
        text = (work / (name + '.log')).read_text()
        row = {'exit': code, 'seconds': time.monotonic() - start, 'argv': argv,
            'log_sha256': sha((work / (name + '.log')).read_bytes()),
            'fatal_lines': [line for line in text.splitlines() if re.search(FATAL, line)],
            'markers': [line for line in text.splitlines() if line.startswith(MARKERS)]}
        put(work / (name + '-EXECUTION.json'), row)
        return row

    verilator = shutil.which(args.verilator)
    assert verilator is not None
    flags = ['--binary', '--timing', '--build-jobs', str(args.build_jobs), '-MAKEFLAGS',
        'CURDIR=' + str(work / 'obj') + ' OPT_FAST=-O3 OPT_SLOW=-O3', '-Wall', '-Wno-fatal',
        '-Wno-DECLFILENAME', '-Wno-TIMESCALEMOD', '-Wno-WIDTHEXPAND', '-Wno-WIDTHTRUNC',
        '-Wno-UNUSEDSIGNAL', '-Wno-UNUSEDPARAM', '-Wno-SYNCASYNCNET', '-Wno-BLKSEQ',
        '-Wno-VARHIDDEN', '-Wno-PINCONNECTEMPTY', '-Wno-PROCASSINIT', '-DSYNTHESIS',
        '-GAUTH_BANKS=4', '--top-module', 'tb_board1_booted_shared_semantic',
        '--Mdir', str(work / 'obj'), '-f', 'production_sources.f']
    argv = [verilator] + flags + expected['reference_sources'] + ['tb.sv', '-CFLAGS', '-O3']
    print('MODEL_RTL_REPLAY_STARTED production_sources=64 cases=4 hardware_access=0', flush=True)
    built = execute('compile', argv, args.timeout_seconds)
    print('MODEL_RTL_COMPILE exit=' + str(built['exit']), flush=True)
    results = {}
    executable = work / 'obj/Vtb_board1_booted_shared_semantic'
    if built['exit'] == 0 and not built['fatal_lines']:
        def test(name):
            row = execute(name, [str(executable), '+IMAGE_MEMH=image.memh', '+PROFILE_CASE=0'] + CASES[name], args.timeout_seconds)
            row['passed'] = check_case_log((work / (name + '.log')).read_text(), row['exit'], expected['expected_markers'][name])
            put(work / (name + '-CHECKED.json'), row)
            print('MODEL_RTL_CASE ' + name + ' passed=' + str(row['passed']), flush=True)
            return name, row
        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            results = dict(pool.map(test, CASES))
    unchanged = all((work / name).read_bytes() == data for name, data in files.items())
    passed = built['exit'] == 0 and not built['fatal_lines'] and set(results) == set(CASES) and all(r['passed'] for r in results.values()) and unchanged
    record = {'passed': passed, 'build': built, 'cases': results, 'source_files_unchanged': unchanged,
        'input_sha256': sha((work / 'INPUTS.json').read_bytes()),
        'executable_sha256': sha(executable.read_bytes()) if executable.is_file() else None,
        'production_rtl_byte_identical': 64, 'production_rtl_changes': 0,
        'positive_exact_tokens': {name: len(re.findall(r'^SEMANTIC_STEP .* token=\d+ ', '\n'.join(row['markers']), re.M))
            for name, row in results.items() if name in ('zero', 'stalled') and row['passed']},
        'weight_corruption_rejections': sum(results.get(name, {}).get('passed', False) for name in ('corrupt-boot', 'corrupt-runtime')),
        'hardware_access': False, 'network_access': False, 'whole_machine_refinement': False,
        'scope': expected['scope']}
    if passed:
        audit_record(record)
    put(work / 'FINISHED.json', record)
    print('MODEL_RTL_REPLAY_FINISHED passed=' + str(passed), flush=True)
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
