"""Verify measured sources and optionally stage a new build, without building."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def verify(root=ROOT):
    record = json.loads((root / 'SOURCE-INPUTS.json').read_text())
    for name, expected in record['frozen_hardware_inputs'].items():
        rel = PurePosixPath(name)
        path = root / rel
        if (rel.is_absolute() or '..' in rel.parts or '\\' in name
                or not path.resolve().is_relative_to(root.resolve())
                or path.is_symlink() or not path.is_file()
                or path.stat().st_size != expected['bytes'] or digest(path) != expected['sha256']):
            raise ValueError('Changed or missing frozen source: ' + name)
    return record


def check_hdk(path, selected):
    def git(folder, *args):
        return subprocess.check_output(['git', '-C', str(folder), *args], text=True).strip()
    path = path.resolve()
    ip = path / 'hdk/common/ip'
    for folder, key in ((path, 'aws_hdk_revision'), (ip, 'aws_ip_revision')):
        if git(folder, 'rev-parse', 'HEAD') != selected[key]:
            raise ValueError('Different vendor revision')
        subprocess.run(['git', '-C', str(folder), 'diff', '--quiet', 'HEAD', '--'], check=True)
    shell = path / 'hdk/common/shell_stable/build/checkpoints/from_aws/cl_bb_routed.small_shell.dcp'
    if digest(shell) != selected['shell_checkpoint_sha256']:
        raise ValueError('Missing or different vendor shell')


def stage(output, root=ROOT):
    record = verify(root)
    output = output.resolve()
    if output.exists() or any(c.isspace() for c in str(output)):
        raise ValueError('Choose a fresh build directory without whitespace')
    output.mkdir(parents=True)
    for name, expected in record['frozen_hardware_inputs'].items():
        if not name.startswith('hardware/'):
            continue
        target = output / 'cl_qwen' / Path(name).relative_to('hardware')
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(root / name, target)
        if digest(target) != expected['sha256']:
            raise ValueError('Input changed while staging')
    return output


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--hdk', type=Path)
    args = parser.parse_args()
    record = verify()
    if args.hdk:
        check_hdk(args.hdk, record)
    if args.output:
        stage(args.output)
    print(json.dumps(dict(passed=True, frozen_inputs=len(record['frozen_hardware_inputs']),
                         cloud_actions=False, vendor_build_run=False, hardware_access=False)))
