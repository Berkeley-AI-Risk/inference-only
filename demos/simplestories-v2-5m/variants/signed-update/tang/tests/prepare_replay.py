#!/usr/bin/env python3
"""Stage a fresh offline Tang replay without changing distributed evidence."""
import argparse
import hashlib
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEST_INPUTS = (
    'reference_cases.py', 'make_fixtures.py', 'make_weight_fixture.py',
    'check_fixture_identity.py', 'run_crypto_kats.py', 'run_admission_memory.py',
    'run_norm_store.py', 'build_tang_sim.py', 'run_tang_sim.py',
    'run_boot_faults.py', 'run_host_tools.py', 'audit_build_inputs.py',
    'tb_tang.sv', 'phy_model.sv', 'fast_flash_body.sv', 'tb_memory.sv',
    'tb_norm_store.sv', 'rfc8554-case1.json', 'lms-vectors.json',
)
TOOL_INPUTS = (
    'prepare_flash.py', 'prepare_preserving_flash.py', 'prepare_flash_blocks.py',
    'check_flash.py', 'uart_check.py',
)


def stage(source, output):
    source = Path(source).resolve()
    requested = Path(output).expanduser()
    if requested.exists() or requested.is_symlink():
        raise FileExistsError('Use a new work directory; preserve existing replay output')
    output = requested.resolve()
    release = next((p for p in source.parents
                    if (p / 'MANIFEST.json').is_file()
                    and (p / 'tools/verify_release.py').is_file()), source)
    if output == release or output.is_relative_to(release):
        raise ValueError('Replay output must be outside the source release')
    names = {'reference/signed_update.py', 'reference/tang_image.py'}
    names.update('tests/' + n for n in TEST_INPUTS)
    names.update('tools/' + n for n in TOOL_INPUTS)
    project = source / 'hardware/project'
    if project.is_symlink() or not project.is_dir():
        raise ValueError('Expected a regular hardware/project source directory')
    for folder, directories, files in os.walk(project, followlinks=False):
        for name in directories + files:
            p = Path(folder) / name
            if p.is_symlink():
                raise ValueError('Do not stage source symlinks: ' + str(p.relative_to(source)))
        names.update((Path(folder) / n).relative_to(source).as_posix() for n in files)
    for name in names:
        p = source / name
        if p.is_symlink() or not p.is_file() or not p.resolve().is_relative_to(source):
            raise ValueError('Expected a regular replay input: ' + name)
    # The scripts read their RFC/LMS vectors from tests/, and generate all
    # evidence/ inputs in the work tree. No archived campaign is copied.
    output.mkdir(parents=True, exist_ok=False)
    replay = output / 'tang'
    rows = {}
    for name in sorted(names):
        p = source / name
        raw = p.read_bytes()
        target = replay / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)
        os.chmod(target, p.stat().st_mode & 0o777)
        rows[name] = {'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()}
    (replay / 'evidence').mkdir()
    record = {
        'source': str(source), 'replay': str(replay), 'files': rows,
        'stager_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'input_vectors': ['tests/rfc8554-case1.json', 'tests/lms-vectors.json'],
        'archived_evidence_copied': False, 'evidence_initially_empty': True,
        'demo_inputs': 'Read the separately supplied DEMO image, metadata, digests and integer reference in place',
        'scope': 'Offline staging only; no generation, compilation, signing service, device or cloud action',
    }
    (output / 'STAGED-INPUTS.json').write_text(json.dumps(record, indent=2, sort_keys=True) + '\n')
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path,
                        help='new directory outside the source release')
    args = parser.parse_args()
    record = stage(ROOT, args.output)
    print(json.dumps({'replay': record['replay'], 'source_files': len(record['files']),
                      'archived_evidence_copied': False}))


if __name__ == '__main__':
    main()
