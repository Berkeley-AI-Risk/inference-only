#!/usr/bin/env python3
if not __debug__:
    raise SystemExit('Optimized Python is unsupported; run without -O or -OO')
"""Opt-in real-model K/V substitution replay; no board or default CI action."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--repository', type=Path)
    parser.add_argument('--phase', choices=('all','prepare','build','run','check'), default='all')
    parser.add_argument('--build-jobs', type=int, default=1)
    parser.add_argument('--jobs', type=int, default=1)
    args = parser.parse_args()
    if not 1 <= args.build_jobs <= 64 or not 1 <= args.jobs <= 6:
        raise ValueError('Choose 1..64 compiler workers and 1..6 native workers')
    output = args.output.resolve()
    repository = (args.repository if args.repository is not None else HERE.parents[3]).resolve()
    if output.is_relative_to(repository):
        raise ValueError('Output must be outside the repository')
    driver = output / 'driver'
    if args.phase in ('all','prepare'):
        output.mkdir(parents=True, exist_ok=False)
        shutil.copyfile(HERE/'run.py',output/'ENTRY-SNAPSHOT.py')
        driver.mkdir()
        for folder in ('scripts','fixtures','reference'):
            shutil.copytree(HERE / folder, driver / folder)
        shutil.copyfile(HERE / 'SOURCE-INPUTS.json', driver / 'SOURCE-INPUTS.json')
        pins = {str(p.relative_to(driver)): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in sorted(driver.rglob('*')) if p.is_file()}
        (output / 'DRIVER-SEAL.json').write_text(json.dumps(pins,indent=2,sort_keys=True)+'\n')
    if (HERE/'run.py').read_bytes() != (output/'ENTRY-SNAPSHOT.py').read_bytes():
        raise ValueError('Entry point changed')
    for name, digest in json.loads((output / 'DRIVER-SEAL.json').read_text()).items():
        if hashlib.sha256((driver / name).read_bytes()).hexdigest() != digest:
            raise ValueError('Driver changed: ' + name)
    return subprocess.call([sys.executable,'-I','-B',str(driver/'scripts/replay.py'),
        '--repository',str(repository),'--output',str(output),'--phase',args.phase,
        '--build-jobs',str(args.build_jobs),'--jobs',str(args.jobs)])


if __name__ == '__main__':
    raise SystemExit(main())
