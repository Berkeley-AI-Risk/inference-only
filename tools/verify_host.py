#!/usr/bin/env python3
"""Replay packaged host tests in a fresh copy using an already installed app environment.

No network, listening server, physical UART/JTAG, vendor build or software
inference is used. Test fixtures are explicitly synthetic, not FPGA results.
"""
import argparse
import ast
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

if not sys.flags.isolated or not sys.flags.dont_write_bytecode or sys.flags.optimize:
    raise SystemExit('Run with Python -I -B, without -O.')
TOKENIZER_SHA = '01b6553da99789d461cec48eed624684a803f259a5177616a67f7391700acf51'


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--app-python', type=Path, required=True)
    parser.add_argument('--tokenizer', type=Path, required=True)
    parser.add_argument('--work', type=Path, required=True)
    args = parser.parse_args()
    package = args.package.absolute()
    manifest = json.loads((package / 'MANIFEST.json').read_text())
    files = {name.removeprefix('host-app/'): row for name, row in manifest['files'].items() if name.startswith('host-app/')}
    if not files: raise ValueError('No host app in this package')
    for name, row in files.items():
        path = package / 'host-app' / name
        if path.is_symlink() or sha(path) != row['sha256'] or path.stat().st_size != row['bytes']:
            raise ValueError('Changed packaged host file: ' + name)
    tokenizer = args.tokenizer.absolute()
    if tokenizer.is_symlink() or tokenizer.stat().st_size != 86463 or sha(tokenizer) != TOKENIZER_SHA:
        raise ValueError('Expected the pinned tokenizer file')
    work = args.work.absolute()
    if work == package or work.is_relative_to(package): raise ValueError('Use a fresh work directory outside the package')
    work.mkdir(parents=False, exist_ok=False)
    host = work / 'host-app'; host.mkdir()
    for name in files:
        target = host / name; target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(package / 'host-app' / name, target)
    (host / 'assets').mkdir(exist_ok=True)
    bundled = host / 'assets/tokenizer.json'
    if bundled.exists():
        if sha(bundled) != TOKENIZER_SHA: raise ValueError('Changed bundled tokenizer')
    else:
        shutil.copyfile(tokenizer, bundled)
    tests = []
    for path in sorted(host.glob('test_*.py')):
        module = ast.parse(path.read_text())
        tests.extend(node.name for cls in module.body if isinstance(cls, ast.ClassDef)
            for node in cls.body if isinstance(node, ast.FunctionDef) and node.name.startswith('test_'))
    if len(tests) < 41: raise ValueError('The expected regression suite is incomplete')
    argv = [str(args.app_python.absolute()), '-I', '-B', '-m', 'unittest', 'discover', '-v']
    started = time.monotonic()
    with (work / 'tests.log').open('xb') as log:
        child = subprocess.Popen(argv, cwd=host, stdout=log, stderr=subprocess.STDOUT)
        with (work / 'STARTED.json').open('x') as out:
            json.dump({'pid': child.pid, 'argv': argv, 'hardware_access': False}, out, indent=2); out.write('\n')
        code = child.wait()
    log = (work / 'tests.log').read_text(errors='replace')
    counts = re.findall(r'^Ran (\d+) tests? in ', log, re.MULTILINE)
    passed = code == 0 and counts == [str(len(tests))] and re.search(r'^OK$', log, re.MULTILINE) is not None
    unchanged = all(sha(host / name) == row['sha256'] and sha(package / 'host-app' / name) == row['sha256'] for name, row in files.items())
    result = {'passed': passed and unchanged, 'exit': code, 'seconds': time.monotonic() - started,
        'tests_expected': len(tests), 'test_methods': tests, 'tests_reported': counts,
        'source_files': {name: row['sha256'] for name, row in files.items()},
        'source_files_unchanged': unchanged, 'log_sha256': sha(work / 'tests.log'),
        'package_manifest_sha256': sha(package / 'MANIFEST.json'),
        'hardware_access': False, 'network_access': False, 'server_started': False,
        'scope': 'Offline real host/UI code plus explicit synthetic protocol/deployment/build fixtures. Not a physical qualification of the portable host or any rebuilt bitstream.'}
    with (work / 'FINISHED.json').open('x') as out: json.dump(result, out, indent=2, sort_keys=True); out.write('\n')
    print('HOST_REPLAY_FINISHED passed=' + str(result['passed']) + ' tests=' + str(len(tests)), flush=True)
    return 0 if result['passed'] else 1


if __name__ == '__main__': raise SystemExit(main())
