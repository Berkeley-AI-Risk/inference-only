#!/usr/bin/env python3
"""Isolated offline build of the auxiliary reader; never open a programmer/UART."""
import argparse
import datetime
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

if not (sys.flags.isolated and sys.flags.no_site and sys.flags.dont_write_bytecode) or sys.flags.optimize:
    raise SystemExit('Use Python -I -S -B, without -O.')

GW_SHA = '1a2497e6752a4561b64f620e0aa68ae5da599b118f8d723ca70c491f6688678e'
BUILD_FILES = (
    'rtl/fixed_uart_rx.sv', 'rtl/fixed_uart_tx.sv', 'rtl/readonly_flash_reader.sv',
    'constraints/readonly_flash_reader.cst', 'constraints/readonly_flash_reader.sdc',
    'readonly_flash_reader.gprj', 'build.tcl',
)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def regular(path, limit=64 * 1024 * 1024):
    if path.is_symlink() or not path.is_file() or path.stat().st_size > limit:
        raise ValueError('Missing, symbolic, non-regular or oversized file: ' + str(path))
    with path.open('rb') as stream:
        data = stream.read(limit + 1)
    if len(data) > limit:
        raise ValueError('File grew beyond the size limit')
    return data


def normalized_image(data):
    result, count = re.subn(rb'^//Created Time: [^\r\n]+\n', b'//Created Time: <omitted>\n', data, flags=re.M)
    if count != 1:
        raise ValueError('Expected exactly one bitstream creation-time comment')
    return result


def put(path, value):
    with path.open('x') as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write('\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path(__file__).absolute().parent)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--gowin-ide', type=Path, required=True)
    parser.add_argument('--confirm-permitted-vendor-use', action='store_true')
    parser.add_argument('--preflight-only', action='store_true')
    args = parser.parse_args()
    if not args.confirm_permitted_vendor_use:
        raise ValueError('Confirm your existing entitlement to use the separately acquired tool; this does not accept terms.')
    source, output, ide = args.source.absolute(), args.output.absolute(), args.gowin_ide.absolute()
    if sys.platform != 'darwin':
        raise ValueError('This exact tool profile supports macOS only')
    spec = importlib.util.spec_from_file_location('reader_replay', source / 'replay.py')
    replay = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(replay)
    manifest = replay.inventory(source)
    executable = ide / 'bin/gw_sh'
    if digest(regular(executable, 128 * 1024 * 1024)) != GW_SHA:
        raise ValueError('The GOWIN executable differs from the tested version')
    if output.exists() or output.is_symlink():
        raise FileExistsError('Use a fresh output directory; existing work is preserved')
    if any(c.isspace() for c in str(output)) or output.resolve().is_relative_to(source.resolve()):
        raise ValueError('Use a space-free output path outside the source tree')
    inputs = {name: regular(source / name) for name in BUILD_FILES}
    if any(digest(data) != manifest['unchanged_original_source_files'][name] for name, data in inputs.items()):
        raise ValueError('Build inputs differ from the original reader')
    if args.preflight_only:
        print(json.dumps({'passed': True, 'input_files': len(inputs), 'tool_sha256': GW_SHA,
            'writes': False, 'hardware_access': False}), flush=True)
        return 0
    output.mkdir(parents=False, exist_ok=False)
    (output / 'runner.py').write_bytes(Path(__file__).read_bytes())
    (output / 'source-manifest.json').write_bytes(regular(source / 'MANIFEST.json'))
    for name, data in inputs.items():
        for tree in ('project', 'input'):
            target = output / tree / name
            target.parent.mkdir(parents=True, exist_ok=True)
            with target.open('xb') as stream:
                stream.write(data)
    env = os.environ.copy()
    env['DYLD_LIBRARY_PATH'] = str(ide / 'lib')
    env['DYLD_FRAMEWORK_PATH'] = str(ide / 'lib')
    for variable, name in (('TMPDIR', 'tmp'), ('XDG_CACHE_HOME', 'xdg/cache'),
                           ('XDG_CONFIG_HOME', 'xdg/config'), ('XDG_DATA_HOME', 'xdg/data')):
        directory = output / name
        directory.mkdir(parents=True, exist_ok=False)
        env[variable] = str(directory) + '/'
    argv = [str(executable), str(output / 'project/build.tcl')]
    start = time.monotonic()
    with (output / 'tool.log').open('xb') as log:
        child = subprocess.Popen(argv, cwd=output / 'project', env=env, stdout=log, stderr=subprocess.STDOUT)
        put(output / 'STARTED.json', {'pid': child.pid, 'argv': argv, 'tool_sha256': GW_SHA,
            'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'hardware_access': False})
        print('FLASH_READER_BUILD_STARTED pid=' + str(child.pid), flush=True)
        awake = subprocess.Popen(['/usr/bin/caffeinate', '-i', '-w', str(child.pid)])
        code = child.wait()
        awake.wait()
    put(output / 'TOOL-FINISHED.json', {'exit': code, 'seconds': time.monotonic() - start,
        'log_sha256': digest(regular(output / 'tool.log')), 'hardware_access': False})
    errors, artifacts = [], {}
    try:
        unchanged = replay.inventory(source) == manifest and all(
            regular(output / 'input' / name) == data and
            (name == 'readonly_flash_reader.gprj' or regular(output / 'project' / name) == data)
            for name, data in inputs.items())
        pnr = output / 'project/impl/pnr'
        for suffix in ('fs', 'tr', 'rpt.txt', 'log'):
            data = regular(pnr / ('readonly_flash_reader.' + suffix))
            artifacts[suffix] = {'sha256': digest(data), 'bytes': len(data)}
        image = regular(pnr / 'readonly_flash_reader.fs')
        canonical = digest(normalized_image(image))
        same_image = canonical == manifest['historical_image_timestamp_normalized_sha256']
        timing = regular(pnr / 'readonly_flash_reader.tr').decode()
        violations = {kind: re.findall(r'<Numbers of ' + kind + r' Violated Endpoints>:(\d+)', timing)
                      for kind in ('Setup', 'Hold')}
        internal_timing_clear = violations == {'Setup': ['0'], 'Hold': ['0']}
        pnr_log = regular(pnr / 'readonly_flash_reader.log').decode()
        flow = code == 0 and 'Placement and routing completed' in pnr_log and 'Bitstream generation completed' in pnr_log
    except (OSError, ValueError, KeyError) as error:
        errors.append(str(error))
        unchanged = same_image = internal_timing_clear = flow = False
        canonical, violations = None, {}
    result = {'passed': flow and unchanged and same_image and internal_timing_clear and not errors,
        'flow_completed': flow, 'source_unchanged': unchanged,
        'image_equal_except_creation_time': same_image, 'timestamp_normalized_image_sha256': canonical,
        'setup_hold_report_clear': internal_timing_clear, 'violation_counts': violations,
        'artifacts': artifacts, 'errors': errors, 'tool_sha256': GW_SHA,
        'source_manifest_sha256': digest(regular(source / 'MANIFEST.json')),
        'hardware_access': False, 'board_load_allowed': False, 'electrical_qualification': False,
        'scope': 'Exact-source native reproduction and saved-file comparison with the historical reader; not board attestation or complete external I/O timing signoff.'}
    put(output / 'FINISHED.json', result)
    print('FLASH_READER_BUILD_FINISHED passed=' + str(result['passed']), flush=True)
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
