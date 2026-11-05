#!/usr/bin/env python3
"""Regenerate the owned Tang overlay from its hash-pinned public baseline."""
import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    baseline = json.loads((ROOT / 'integration/BASELINE.json').read_text())
    source = (ROOT / baseline['source_root']).resolve()
    work = Path(tempfile.mkdtemp(prefix='home-overlay-reproduction-'))
    for folder in ['rtl', 'reference']:
        shutil.copytree(ROOT / folder, work / folder,
                        ignore=shutil.ignore_patterns('__pycache__'))
    (work / 'integration').mkdir()
    for name in ['BASELINE.json', 'prepare.py', 'final-integration.patch']:
        shutil.copyfile(ROOT / 'integration' / name, work / 'integration' / name)
    for name, sha in baseline['files'].items():
        if not name.startswith('project/'):
            continue
        assert digest(source / name) == sha, name
        target = work / 'integration' / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source / name, target)
    command = [sys.executable, '-I', '-B', str(work / 'integration/prepare.py')]
    with (out / 'run.log').open('w') as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
    assert result.returncode == 0, 'Overlay preparation failed; see run.log'
    hashes = {}
    for path in (ROOT / 'integration/project').rglob('*'):
        if not path.is_file():
            continue
        name = str(path.relative_to(ROOT / 'integration/project'))
        hashes[name] = digest(path)
        assert digest(work / 'integration/project' / name) == hashes[name], name
    generated = {str(x.relative_to(work / 'integration/project'))
                 for x in (work / 'integration/project').rglob('*') if x.is_file()}
    assert generated == set(hashes), 'Generated source file set differs'
    record = {'result': 'PASS', 'directory': str(work),
              'matched_project_files': len(hashes), 'project_sha256': hashes,
              'baseline_manifest_sha256': digest(ROOT / 'integration/BASELINE.json'),
              'prepare_sha256': digest(ROOT / 'integration/prepare.py'),
              'patch_sha256': digest(ROOT / 'integration/final-integration.patch')}
    (out / 'RESULT.json').write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps({'result': 'PASS', 'matched_project_files': len(hashes)}))


if __name__ == '__main__':
    main()
