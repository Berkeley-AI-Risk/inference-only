"""Verify frozen inputs and optionally stage a fresh source-build directory.

Does not run Vivado, install vendor tools, access AWS or program an FPGA.
"""
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


def checked_path(root, name):
    relative = PurePosixPath(name)
    if relative.is_absolute() or '..' in relative.parts or not relative.parts or '\\' in name:
        raise ValueError('Unsafe input name')
    target = root.joinpath(*relative.parts)
    if target.is_symlink() or not target.is_file() or not target.resolve().is_relative_to(root.resolve()):
        raise ValueError('Missing or escaping source input: '+name)
    return target


def verify(root=ROOT):
    selected = json.loads((root/'SOURCE-INPUTS.json').read_text())
    implementation = json.loads((root/'hardware/IMPLEMENTATION-INPUTS.json').read_text())
    if (selected['source_bundle_manifest_sha256'] != implementation['source_bundle_manifest_sha256']
            or implementation['clock_recipes'] != dict(a='A0', b='B0', c='C0', hbm='H1')):
        raise ValueError('Mismatching measured source/clock selection')
    inputs = dict(selected['source_files'])
    inputs.update({'hardware/implementation/'+name: row for name, row in implementation['files'].items()})
    for name, row in inputs.items():
        path = checked_path(root, name)
        if path.stat().st_size != row['bytes'] or digest(path) != row['sha256']:
            raise ValueError('Changed frozen input: '+name)
    return inputs, implementation


def check_hdk(hdk, expected):
    def git(directory, *args):
        return subprocess.check_output(['git', '-C', str(directory), *args], text=True).strip()
    hdk = hdk.resolve()
    ip = hdk/'hdk/common/ip'
    if (git(hdk, 'rev-parse', 'HEAD') != expected['aws_hdk_revision']
            or git(ip, 'rev-parse', '--show-toplevel') != str(ip.resolve())
            or git(ip, 'rev-parse', 'HEAD') != expected['aws_ip_revision']):
        raise ValueError('Different HDK or version-specific IP revision')
    for directory in (hdk, ip):
        subprocess.run(['git', '-C', str(directory), 'diff', '--quiet', 'HEAD', '--'], check=True)
    shell = hdk/'hdk/common/shell_stable/build/checkpoints/from_aws/cl_bb_routed.small_shell.dcp'
    if digest(shell) != expected['shell_checkpoint_sha256']:
        raise ValueError('Different or unpopulated AWS shell checkpoint')


def prepare(output, root=ROOT):
    inputs, implementation = verify(root)
    output = output.resolve()
    if output.exists() or any(character.isspace() for character in str(output)):
        raise ValueError('Choose a new build directory with no whitespace')
    output.mkdir(parents=True, exist_ok=False)
    for name in sorted(inputs):
        if name.startswith(('hardware/design/', 'hardware/build/')):
            relative = Path('cl_qwen')/Path(name).relative_to('hardware')
        elif name.startswith('hardware/implementation/'):
            relative = Path(name).relative_to('hardware/implementation')
        else:
            continue
        target = output/relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(root/name, target)
        if digest(target) != inputs[name]['sha256']:
            raise ValueError('Source changed while staging')
    return dict(passed=True, inputs_verified=len(inputs), build_directory=str(output),
                clock_recipes=implementation['clock_recipes'], vendor_build_run=False,
                cloud_actions=False, hardware_access=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--hdk', type=Path, help='Also verify the separately installed HDK/IP/shell')
    args = parser.parse_args()
    inputs, implementation = verify()
    if args.hdk is not None:
        check_hdk(args.hdk, implementation)
    result = prepare(args.output) if args.output is not None else dict(
        passed=True, inputs_verified=len(inputs), hardware_access=False, cloud_actions=False)
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
