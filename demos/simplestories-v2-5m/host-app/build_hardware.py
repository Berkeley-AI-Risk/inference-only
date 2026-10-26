#!/usr/bin/env python3
"""Build the exact selected inputs using separately acquired GOWIN dependencies.

All outputs remain local. This never programs the FPGA or flash, downloads IP,
accepts a vendor agreement, or promotes a timing-unqualified image.
"""
from __future__ import annotations

import argparse
import datetime
import json
import os
from pathlib import Path
import subprocess
import sys
import time

import runtime_profile as profile

GW_SHA256 = '1a2497e6752a4561b64f620e0aa68ae5da599b118f8d723ca70c491f6688678e'
VENDOR_NAMES = {'ddr3_memory_interface.v', 'gowin_pll.v', 'gowin_pll_mod.v', 'pll_init.v'}


def collect(package: Path, vendor: Path, variant: str = 'baseline') -> dict[str, bytes]:
    sources = {}
    selected = profile.variant_settings(variant)
    for name, digest in profile.hardware_inputs(variant).items():
        path = package / selected['hardware_root'] / name
        if name.startswith('project/official/'):
            if Path(name).name not in VENDOR_NAMES: raise ValueError('Unexpected vendor dependency')
            path = vendor / Path(name).name
        data = profile.read_regular(path, 32 * 1024 * 1024)
        if profile.sha(data) != digest: raise ValueError('Selected build input missing or changed: ' + name)
        sources[name] = data
    if len(sources) != selected['input_files']: raise ValueError('Incomplete hardware inventory')
    return sources


def build(package: Path, vendor: Path, ide: Path, output: Path, *,
          acknowledge_terms: bool, preflight_only: bool = False, variant: str = 'baseline') -> dict:
    if not acknowledge_terms:
        raise ValueError('Confirm you are entitled to use the separately acquired GOWIN tool/IP; this script does not accept terms for you.')
    selected = profile.variant_settings(variant)
    sources = collect(Path(package), Path(vendor), variant)
    ide, output = Path(ide).absolute(), Path(output).absolute()
    # This version intentionally pins the exact macOS executable used in the
    # demonstrated build. A Linux/tool-version port needs separate validation.
    if sys.platform != 'darwin': raise RuntimeError('This reproducible build profile currently supports macOS only.')
    executable = ide / 'bin/gw_sh'
    if profile.sha(profile.read_regular(executable, 128 * 1024 * 1024)) != GW_SHA256:
        raise ValueError('This is not the pinned GOWIN executable; do not silently mix tool versions.')
    if any(c.isspace() for c in str(output)):
        raise ValueError('Use a space-free absolute build path to avoid tool path ambiguity.')
    if output.exists(): raise FileExistsError('Build output must be a fresh directory; existing work is preserved.')
    if preflight_only:
        return {'passed': True, 'input_files': len(sources), 'hardware_access': False, 'writes': False,
            'variant': variant, 'hardware_inputs_sha256': selected['inputs_sha256'], 'tool_sha256': GW_SHA256}
    output.mkdir(parents=True, exist_ok=False)
    for name, data in sources.items():
        profile.private_write(output / name, data)
        profile.private_write(output / 'input' / name, data)
    env = os.environ.copy()
    env['DYLD_LIBRARY_PATH'] = str(ide / 'lib')
    env['DYLD_FRAMEWORK_PATH'] = str(ide / 'lib')
    for variable, folder in (('TMPDIR', 'private-tmp'), ('XDG_CACHE_HOME', 'private-xdg/cache'),
                             ('XDG_CONFIG_HOME', 'private-xdg/config'), ('XDG_DATA_HOME', 'private-xdg/data')):
        directory = output / folder
        directory.mkdir(parents=True, exist_ok=False)
        env[variable] = str(directory) + '/'
    argv = [str(executable), str(output / 'run.tcl')]
    started = time.monotonic()
    stdout, stderr = output / 'stdout.log', output / 'stderr.log'
    with stdout.open('xb', buffering=0) as out, stderr.open('xb', buffering=0) as err:
        child = subprocess.Popen(argv, cwd=output, env=env, stdout=out, stderr=err)
        profile.private_write(output / 'STARTED.json', profile.encode({'pid': child.pid, 'argv': argv,
            'hardware_access': False, 'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat()}))
        print('GOWIN offline build started, pid=' + str(child.pid), flush=True)
        keep_awake = subprocess.Popen(['/usr/bin/caffeinate', '-i', '-w', str(child.pid)])
        code = child.wait()
        keep_awake.wait()
    elapsed = time.monotonic() - started
    # Preserve the actual child result even if post-build file validation fails.
    profile.private_write(output / 'TOOL-FINISHED.json', profile.encode({
        'exit': code, 'seconds': elapsed, 'argv': argv, 'tool_sha256': GW_SHA256,
        'hardware_access': False}))
    logs = stdout.read_text(errors='replace') + '\n' + stderr.read_text(errors='replace')
    validation_errors = []
    try:
        unchanged = all(profile.read_regular(output / 'input' / name, 32 * 1024 * 1024) == data
            and (name == 'project/product.gprj' or profile.read_regular(output / name, 32 * 1024 * 1024) == data)
            for name, data in sources.items())
    except (OSError, ValueError) as error:
        unchanged = False
        validation_errors.append('Source validation: ' + str(error))
    image_relative = 'project/impl/pnr/shared_product.fs'
    image = b''
    metadata_sha = None
    try:
        image = profile.read_regular(output / image_relative, profile.MAX_BITSTREAM_BYTES)
    except (OSError, ValueError) as error:
        validation_errors.append('Bitstream validation: ' + str(error))
    try:
        metadata_sha = profile.sha(profile.read_regular(output / 'project/product.gprj'))
    except (OSError, ValueError) as error:
        validation_errors.append('Project metadata validation: ' + str(error))
    completed = (code == 0 and unchanged and bool(image) and not validation_errors
        and logs.count('LOCAL_KV_SYN_COMPLETE hardware_access=0') == 1
        and logs.count('LOCAL_KV_NATIVE_COMPLETE hardware_access=0') == 1)
    record = {'schema': profile.BUILD_SCHEMA, 'variant': variant, 'flow_completed': completed, 'exit': code,
        'seconds': elapsed, 'source_inputs_verified': True,
        'source_inputs_unchanged': unchanged, 'hardware_inputs_sha256': selected['inputs_sha256'],
        'image_relative_path': image_relative, 'image_sha256': profile.sha(image) if image else None,
        'image_bytes': len(image), 'validation_errors': validation_errors,
        'tool_sha256': GW_SHA256, 'argv': argv, 'hardware_access': False,
        'stdout_sha256': profile.sha(stdout.read_bytes()), 'stderr_sha256': profile.sha(stderr.read_bytes()),
        'project_metadata_after_sha256': metadata_sha,
        'timing_qualified': False, 'board_load_allowed': False,
        'scope': 'Exact archived input files and unchanged working RTL/constraints/run script; vendor may rewrite project metadata. Completed flow is not timing/PHY signoff, netlist equivalence, live configuration attestation or programming authorization.'}
    profile.private_write(output / 'BUILD.json', profile.encode(record))
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument('--variant', choices=tuple(profile.VARIANTS), default='baseline',
        help='Explicit source variant; baseline remains the default. This does not program a board.')
    parser.add_argument('--vendor-dir', type=Path, required=True, help='Directory containing the four lawfully acquired, pinned .v dependencies.')
    parser.add_argument('--gowin-ide', type=Path, required=True, help='The GOWIN IDE directory containing bin/gw_sh and lib/.')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--confirm-permitted-vendor-use', action='store_true')
    parser.add_argument('--preflight-only', action='store_true', help='Verify inputs/tool without writing files or starting synthesis.')
    args = parser.parse_args()
    result = build(args.package, args.vendor_dir, args.gowin_ide, args.output,
        acknowledge_terms=args.confirm_permitted_vendor_use, preflight_only=args.preflight_only, variant=args.variant)
    print(json.dumps(result, sort_keys=True), flush=True)
    return 0 if result.get('passed') or result.get('flow_completed') else 1


if __name__ == '__main__': raise SystemExit(main())
