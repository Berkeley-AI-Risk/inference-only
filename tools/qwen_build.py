"""Checked local Qwen synthesis and checkpoint packaging, not AWS deployment.

The frozen vendor Tcl and source/image inventories are not modified. Success
means tool/collection completion and container integrity, not timing signoff.
"""
import argparse
from contextlib import contextmanager
import fcntl
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
TAGS = {'qwen3-1.7b': 'private_supported_c2_100', 'qwen3-8b': 'private_qwen8b_100'}
CLOCKS = dict(a='A0', b='B0', c='C2', hbm='H1')


class Failed(RuntimeError):
    def __init__(self, message, code=1):
        super().__init__(message)
        self.code = code if 1 <= code <= 255 else 1


def require(value, message):
    if not value:
        raise Failed(message)


@contextmanager
def workspace_lock(build):
    """One cooperative owner per canonical staged CL, including preflight."""
    stage = (build/'cl_qwen').resolve(strict=True)
    require(stage.is_dir(), 'Missing staged CL directory')
    require(hasattr(os, 'O_NOFOLLOW'), 'This client requires the supported POSIX host')
    path = stage/'.qwen-build.lock'
    descriptor = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        details = os.fstat(descriptor)
        require(stat.S_ISREG(details.st_mode) and details.st_nlink == 1, 'Unsafe workspace lock inode')
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise Failed('Staged CL already has another build/package owner: '+str(stage), 75) from error
        lease = dict(kind='POSIX flock LOCK_EX LOCK_NB', canonical_stage=str(stage), path=str(path),
                     device=details.st_dev, inode=details.st_ino, owner_pid=os.getpid(),
                     acquired_utc=datetime.now(timezone.utc).isoformat(), fd=descriptor)
        lock_intact(lease)
        yield lease
    finally:
        # Never unlink or replace the shared inode. Closing releases this owner;
        # a passed child descriptor retains the same lock while that child lives.
        os.close(descriptor)


def lock_intact(lease):
    current = os.stat(lease['path'], follow_symlinks=False)
    require(stat.S_ISREG(current.st_mode) and current.st_nlink == 1
            and (current.st_dev, current.st_ino) == (lease['device'], lease['inode']),
            'Workspace lock inode was removed or replaced')


def identity(path):
    with path.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    return dict(bytes=path.stat().st_size, sha256=digest)


def save(path, value):
    with path.open('x') as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write('\n')


def regular(path):
    require(path.is_file() and not path.is_symlink(), 'Missing or symlinked file: '+str(path))
    return path


def checkpoint(path):
    regular(path)
    require(path.suffix == '.dcp' and '.VIOLATED' not in path.name.upper(), 'Select a non-VIOLATED .dcp checkpoint')
    require(path.stat().st_size > 0, 'Empty checkpoint')
    try:
        with zipfile.ZipFile(path) as archive:
            require(bool(archive.infolist()) and archive.testzip() is None, 'Checkpoint ZIP CRC failure')
    except (OSError, zipfile.BadZipFile, RuntimeError) as error:
        raise Failed('Invalid checkpoint ZIP container: '+str(error)) from error
    return identity(path)


def profile(repository, name):
    root = repository/'demos'/name
    source = root/'tools/prepare_hardware.py'
    spec = importlib.util.spec_from_file_location('qwen_build_prepare', source)
    prepare = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(prepare)
    checked = prepare.verify(root)
    if name == 'qwen3-1.7b':
        inputs, selected = checked
        version = selected['vivado_version']
    else:
        inputs, selected = checked['frozen_hardware_inputs'], checked
        version = selected['tool_version']
    require(selected['clock_recipes'] == CLOCKS, 'Different clock recipe selection')
    inventories = {'SOURCE-INPUTS.json': identity(root/'SOURCE-INPUTS.json')}
    if name == 'qwen3-1.7b':
        inventories['hardware/IMPLEMENTATION-INPUTS.json'] = identity(root/'hardware/IMPLEMENTATION-INPUTS.json')
    return dict(name=name, root=root, inputs=inputs, selected=selected, version=version, prepare=prepare,
                inventories=inventories)


def staged_inputs(data, build):
    require(build.is_dir() and not build.is_symlink(), 'Stage sources into a fresh build directory first')
    cl = build/'cl_qwen'
    require(cl.is_dir() and not cl.is_symlink(), 'Missing staged cl_qwen')
    checked = {}
    for name, expected in data['inputs'].items():
        if name.startswith(('hardware/design/', 'hardware/build/')):
            relative = Path('cl_qwen')/Path(name).relative_to('hardware')
        elif name.startswith('hardware/implementation/'):
            relative = Path(name).relative_to('hardware/implementation')
        else:
            continue
        path = regular(build/relative)
        require(path.resolve().is_relative_to(build.resolve()) and identity(path) == expected,
                'Changed staged frozen input: '+str(relative))
        checked[str(relative)] = expected
    return checked


def version(vivado, expected, output, lock_fd):
    result = subprocess.run([vivado, '-version'], stdout=subprocess.PIPE, stderr=subprocess.PIPE, pass_fds=(lock_fd,))
    (output/'version.stdout.log').write_bytes(result.stdout)
    (output/'version.stderr.log').write_bytes(result.stderr)
    require(result.returncode == 0, 'Vivado version query failed')
    match = re.search(r'\bVivado\s+v([0-9]+(?:\.[0-9]+)+)\b', result.stdout.decode(errors='replace'))
    require(match and match.group(1) == expected, 'Different or unrecognized Vivado version')
    return dict(version=match.group(1), executable=str(Path(vivado).resolve()), executable_identity=identity(Path(vivado)),
                stdout=identity(output/'version.stdout.log'), stderr=identity(output/'version.stderr.log'))


def synthesize(data, build, hdk, vivado, output, lease):
    tag = TAGS[data['name']]
    scripts = build/'cl_qwen/build/scripts'
    artifact = build/'cl_qwen/build/checkpoints'/('cl_qwen.'+tag+'.post_synth.dcp')
    require(not artifact.exists() and not artifact.is_symlink(), 'Refuse an existing synthesis checkpoint; use a fresh build')
    tool = version(vivado, data['version'], output, lease['fd'])
    environment = dict(os.environ, CL='cl_qwen', CL_DIR=str((build/'cl_qwen').resolve()), SHELL_MODE='small_shell',
                       BUILD_FLOW='SynthCL', BUILD_TAG=tag, ENCRYPT='0', AWS_FPGA_REPO_DIR=str(hdk),
                       HDK_DIR=str(hdk/'hdk'), HDK_COMMON_DIR=str(hdk/'hdk/common'),
                       HDK_SHELL_DIR=str(hdk/'hdk/common/shell_stable'),
                       HDK_SHELL_DESIGN_DIR=str(hdk/'hdk/common/shell_stable/design'),
                       HDK_IP_SRC_DIR=str(hdk/'hdk/common/ip/cl_ip/cl_ip.srcs/sources_1/ip'),
                       HDK_BD_SRC_DIR=str(hdk/'hdk/common/ip/cl_ip/cl_ip.srcs/sources_1/bd'),
                       HDK_BD_GEN_DIR=str(hdk/'hdk/common/ip/cl_ip/cl_ip.gen/sources_1/bd'),
                       VIVADO_TOOL_VERSION=tool['version'])
    command = [vivado, '-mode', 'batch', '-source', 'build_all.tcl', '-log', str(output/'vivado.log'),
               '-journal', str(output/'vivado.jou'), '-tclargs', 'SSI_SpreadLogic_high', 'AggressiveExplore',
               'AggressiveExplore', *CLOCKS.values()]
    observed_environment = {key: environment[key] for key in (
        'HDK_DIR', 'HDK_COMMON_DIR', 'HDK_SHELL_DIR', 'HDK_SHELL_DESIGN_DIR',
        'HDK_IP_SRC_DIR', 'HDK_BD_SRC_DIR', 'HDK_BD_GEN_DIR', 'AWS_FPGA_REPO_DIR',
        'CL', 'CL_DIR', 'SHELL_MODE', 'BUILD_FLOW', 'BUILD_TAG', 'ENCRYPT', 'VIVADO_TOOL_VERSION')}
    save(output/'STARTED.json', dict(command=command, cwd=str(scripts), tool=tool, tag=tag, environment=observed_environment,
                                   started_utc=datetime.now(timezone.utc).isoformat()))
    with (output/'stdout.log').open('xb') as stdout, (output/'stderr.log').open('xb') as stderr:
        result = subprocess.run(command, cwd=scripts, env=environment, stdout=stdout, stderr=stderr, pass_fds=(lease['fd'],))
    save(output/'CHILD-EXIT.json', dict(actual_child_exit=result.returncode))
    if result.returncode:
        code = result.returncode if result.returncode > 0 else 128-result.returncode
        raise Failed('Vivado failed with actual exit '+str(result.returncode), code)
    found = checkpoint(artifact)
    return dict(actual_child_exit=0, artifact=str(artifact), artifact_identity=found, checkpoint_ZIP_CRC_checked=True, tool=tool)


def version_field(path, key):
    values = [line.split('=', 1)[1].strip() for line in path.read_text().splitlines()
              if '=' in line and line.split('=', 1)[0].strip() == key]
    require(len(values) == 1 and values[0], 'Missing or ambiguous version field '+key)
    return values[0]


def package(data, build, hdk, vivado, output, routed, expected, tag, lease, probes=None):
    require(re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,95}', tag) is not None, 'Unsafe package tag')
    require(re.fullmatch(r'[0-9a-f]{64}', expected) is not None, 'Supply the routed checkpoint SHA-256')
    found = checkpoint(routed)
    require(found['sha256'] == expected, 'Routed checkpoint SHA-256 mismatch')
    tool = version(vivado, data['version'], output, lease['fd'])
    ids = {}
    for which, high, low in re.findall(r"^\s*`define\s+CL_SH_ID([01])\s+32'h([0-9a-fA-F]{4})_([0-9a-fA-F]{4})\b",
                                      (build/'cl_qwen/design/cl_id_defines.vh').read_text(), re.MULTILINE):
        keys = ('pci_device_id', 'pci_vendor_id') if which == '0' else ('pci_subsystem_id', 'pci_subsystem_vendor_id')
        ids.update(zip(keys, ('0x'+high.lower(), '0x'+low.lower())))
    require(len(ids) == 4, 'Missing fixed PCI identities')
    payload = output/'to_aws'
    payload.mkdir()
    name = tag+'.SH_CL_routed.dcp'
    shutil.copyfile(routed, payload/name)
    require(identity(payload/name) == found == identity(routed), 'Checkpoint changed during packaging')
    manifest = dict(ids, manifest_format_version=2, dcp_hash=expected,
                    shell_version=version_field(hdk/'hdk/common/shell_stable/shell_version.txt', 'small_shell'),
                    hdk_version=version_field(hdk/'release_version.txt', 'RELEASE_VERSION'),
                    tool_version='v'+tool['version'], date=tag, dcp_file_name=name,
                    **{'clock_recipe_'+key: value for key, value in CLOCKS.items()})
    manifest_name = tag+'.manifest.txt'
    (payload/manifest_name).write_text(''.join(f'{key}={value}\n\n' for key, value in manifest.items()))
    members = {name: found, manifest_name: identity(payload/manifest_name)}
    if probes is not None:
        regular(probes)
        shutil.copyfile(probes, payload/(tag+'.debug_probes.ltx'))
        members[tag+'.debug_probes.ltx'] = identity(payload/(tag+'.debug_probes.ltx'))
    archive = output/(tag+'.Developer_CL.tar')
    with tarfile.open(archive, 'x') as stream:
        for member in members:
            stream.add(payload/member, arcname='to_aws/'+member, recursive=False)
    with tarfile.open(archive) as stream:
        require({member.name for member in stream.getmembers()} == {'to_aws/'+n for n in members}, 'Unexpected package members')
        for member in stream.getmembers():
            require(member.isfile(), 'Non-file package member')
            with stream.extractfile(member) as source:
                digest = hashlib.file_digest(source, 'sha256').hexdigest()
            require(dict(bytes=member.size, sha256=digest) == members[member.name.removeprefix('to_aws/')], 'Package member hash mismatch')
    return dict(archive=str(archive), archive_identity=identity(archive), members=members, manifest=manifest,
                checkpoint_ZIP_CRC_checked=True, tool=tool, AFI_created=False)


def argument_parser():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('synth', 'package'))
    parser.add_argument('--profile', choices=tuple(TAGS), required=True)
    parser.add_argument('--build-dir', type=Path, required=True)
    parser.add_argument('--hdk', type=Path, required=True)
    parser.add_argument('--vivado', default='vivado')
    parser.add_argument('--output', type=Path, required=True, help='New receipt/package directory; never overwritten')
    parser.add_argument('--checkpoint', type=Path)
    parser.add_argument('--checkpoint-sha256')
    parser.add_argument('--tag')
    parser.add_argument('--probes', type=Path)
    return parser


def run_owned(args, repository, build, lease):
    output = None
    try:
        if args.action == 'package':
            require(args.checkpoint is not None and args.checkpoint_sha256 is not None and args.tag is not None,
                    'package requires --checkpoint, --checkpoint-sha256 and --tag')
        else:
            require(not any((args.checkpoint, args.checkpoint_sha256, args.tag, args.probes)), 'Packaging options do not apply to synth')
        data = profile(repository, args.profile)
        hdk = args.hdk.resolve()
        selected = staged_inputs(data, build)
        data['prepare'].check_hdk(hdk, data['selected'])
        ip = hdk/'hdk/common/ip'
        actual_ip_root = subprocess.check_output(['git', '-C', str(ip), 'rev-parse', '--show-toplevel'], text=True).strip()
        require(actual_ip_root == str(ip.resolve()), 'IP must be the separately pinned repository')
        executable = shutil.which(args.vivado)
        require(executable is not None, 'Vivado executable not found')
        require(not args.output.exists() and not args.output.is_symlink(), 'Choose a new receipt/package output directory')
        args.output.mkdir(parents=True, exist_ok=False)
        output = args.output.resolve()
        common = dict(profile=args.profile, clock_recipes=CLOCKS, source_inventories=data['inventories'],
                      aws_hdk_revision=data['selected']['aws_hdk_revision'], aws_ip_revision=data['selected']['aws_ip_revision'],
                      shell_checkpoint_sha256=data['selected']['shell_checkpoint_sha256'],
                      action=args.action, source_and_vendor_preflight_passed=True,
                      workspace_ownership={key: value for key, value in lease.items() if key != 'fd'},
                      timing_or_hardware_qualified=False,
                      AWS_accessed=False, FPGA_programmed=False)
        save(output/'WORKSPACE-LOCK.json', common['workspace_ownership'])
        if args.action == 'synth':
            lock_intact(lease)
            result = synthesize(data, build, hdk, executable, output, lease)
        else:
            lock_intact(lease)
            result = package(data, build, hdk, executable, output, args.checkpoint, args.checkpoint_sha256, args.tag, lease, args.probes)
        lock_intact(lease)
        require(staged_inputs(data, build) == selected, 'Frozen inputs changed during the operation')
        result.update(common, passed=True, completed_utc=datetime.now(timezone.utc).isoformat())
        save(output/'FINISHED.json', result)
        print(json.dumps(result, sort_keys=True))
        return 0
    except (Failed, OSError, ValueError, subprocess.SubprocessError) as error:
        return report_failure(error, args.action, output)


def report_failure(error, action, output=None):
    code = error.code if isinstance(error, Failed) else 1
    failure = dict(passed=False, action=action, error=str(error), exit_code=code,
                   timing_or_hardware_qualified=False, AWS_accessed=False, FPGA_programmed=False)
    if output is not None:
        save(output/'FAILED.json', failure)
    print(json.dumps(failure, sort_keys=True), file=sys.stderr)
    return code


def main(argv=None, repository=ROOT):
    args = argument_parser().parse_args(argv)
    try:
        build = args.build_dir.resolve(strict=True)
        with workspace_lock(build) as lease:
            return run_owned(args, repository, build, lease)
    except (Failed, OSError, ValueError, subprocess.SubprocessError) as error:
        return report_failure(error, args.action)


if __name__ == '__main__':
    sys.exit(main())
