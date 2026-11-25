#!/usr/bin/env python3
"""Replay SimpleStories evidence with its original qualified host files."""
from hashlib import file_digest
import argparse
import json
from pathlib import Path
from shutil import copyfile
import subprocess
import sys
import tarfile
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / 'demos/simplestories-v2-5m'
ARCHIVE = (ROOT / 'evidence/simplestories-tang-protected-seeded-board'
           / 'recorded-greedy-release-inputs.tar.gz')
ARCHIVE_SHA256 = '63f4aada873db96b980c5e11534ff255fa0275a14434dfbba1d76ef649748150'


def replay(seeded):
    with ARCHIVE.open('rb') as stream:
        if file_digest(stream, 'sha256').hexdigest() != ARCHIVE_SHA256:
            raise ValueError('The frozen greedy release inputs changed.')
        stream.seek(0)
        with tarfile.open(fileobj=stream, mode='r:gz') as archive:
            entries = archive.getmembers()
            frozen_files = {entry.name: entry for entry in entries}
            if len(frozen_files) != len(entries) or any(not entry.isfile() for entry in entries):
                raise ValueError('Unexpected frozen release member.')
            with archive.extractfile(frozen_files.pop('MANIFEST.json')) as handle:
                historical_manifest = handle.read()
            members = json.loads(historical_manifest)['files']
            if not frozen_files.keys() <= members.keys():
                raise ValueError('The frozen archive includes an undeclared member.')
            with TemporaryDirectory(prefix='simplestories-recorded-greedy-') as directory:
                package = Path(directory)
                (package / 'MANIFEST.json').write_bytes(historical_manifest)
                for name in members:
                    path = package / name
                    path.parent.mkdir(parents=True, exist_ok=True)
                    if name in frozen_files:
                        with archive.extractfile(frozen_files[name]) as handle:
                            path.write_bytes(handle.read())
                    else:
                        # Copies keep verification metadata stable if the
                        # current release is audited while this runs.
                        copyfile(MODEL / name, path)
                if seeded:
                    cmd = [sys.executable, '-I', '-S', '-B',
                           str(package / 'tools/check_current_seeded_recorded_v1.py'),
                           '--package', str(package), '--require-complete']
                else:
                    cmd = [sys.executable, '-I', '-B',
                           str(package / 'tools/check_current_three_greedy_v15_v4.py'),
                           '--package', str(package), '--stage', 'current', '--index',
                           'evidence/current-greedy/INDEX.json']
                subprocess.run(cmd, check=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seeded', action='store_true',
                        help='Check the original recorded d271 seeded sampling evidence.')
    replay(parser.parse_args().seeded)
