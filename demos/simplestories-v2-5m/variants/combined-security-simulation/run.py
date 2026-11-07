#!/usr/bin/env python3
"""Replay the separately selected combined SimpleStories simulation."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--demo', type=Path, default=HERE.parents[1])
    parser.add_argument('--phase', choices=('all', 'prepare', 'build', 'case', 'summarize'), default='all',
                        help='Separate phases preserve finite compiler/simulator ownership; all is the full replay')
    parser.add_argument('--case', type=int, choices=range(11))
    parser.add_argument('--build-jobs',type=int,default=1)
    args = parser.parse_args()
    if not 1<=args.build_jobs<=64:
        raise ValueError('Choose 1 through 64 compiler workers')
    output = args.output.resolve()
    demo = args.demo.resolve()
    repository = demo.parents[1]
    if output.is_relative_to(repository):
        raise ValueError('Choose an output directory outside the repository')
    driver = output / 'driver'
    if args.phase in ('all', 'prepare'):
        output.mkdir(parents=True, exist_ok=False)
        driver.mkdir()
        for path in sorted((HERE / 'scripts').glob('*.py')):
            shutil.copyfile(path, driver / path.name)
        for name in ('rtl', 'tests', 'reference'):
            shutil.copytree(HERE / name, driver / name)
        shutil.copyfile(HERE / 'SOURCE-INPUTS.json', driver / 'SOURCE-INPUTS.json')
        (driver / 'CONFIG.json').write_text(json.dumps({'repository': str(repository), 'demo': str(demo)}, indent=2) + '\n')
        seal = {str(p.relative_to(driver)): sha(p) for p in sorted(driver.rglob('*')) if p.is_file()}
        (output / 'DRIVER-SEAL.json').write_text(json.dumps(seal, indent=2, sort_keys=True) + '\n')
    if not driver.is_dir():
        raise ValueError('Run the prepare phase into a new output directory first')
    for name, expected in json.loads((output / 'DRIVER-SEAL.json').read_text()).items():
        if sha(driver / name) != expected:
            raise ValueError('Replay driver changed: ' + name)
    command = [sys.executable, '-I', '-B', str(driver / 'replay.py'), '--phase', args.phase,'--build-jobs',str(args.build_jobs)]
    if args.case is not None:
        command += ['--case', str(args.case)]
    return subprocess.call(command)


if __name__ == '__main__':
    raise SystemExit(main())
