"""Reconstruct a digest-pinned source package offline in a fresh directory.

Source paths are relative to this repository; destination paths are relative to
the reconstructed package. No compiler, simulator, network or hardware is used.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import stat

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = 'digest-checked-relocatable-source-map-v1'
MAX_FILE_BYTES = 64 * 1024 * 1024


def relative_name(name):
    if not isinstance(name, str) or not name or any(c in name for c in ('\\', '\x00', '\n', '\r')):
        raise ValueError('Expected a relative POSIX file name')
    relative = PurePosixPath(name)
    if relative.is_absolute() or '..' in relative.parts or relative.as_posix() != name or name == '.':
        raise ValueError('Unsafe relative file name: ' + name)
    return relative


def regular_input(root, name):
    relative = relative_name(name)
    path = root.joinpath(*relative.parts)
    for p in (path, *path.parents):
        if p == root:
            break
        if p.is_symlink():
            raise ValueError('Symlink source input: ' + name)
    try:
        info = path.stat()
    except FileNotFoundError as error:
        raise ValueError('Missing source input: ' + name) from error
    if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_FILE_BYTES:
        raise ValueError('Expected a bounded regular source input: ' + name)
    return path


def checked_bytes(root, row):
    path = regular_input(root, row['source'])
    with path.open('rb') as stream:
        raw = stream.read(row['bytes'] + 1)
    if len(raw) != row['bytes'] or hashlib.sha256(raw).hexdigest() != row['sha256']:
        raise ValueError('Changed source input: ' + row['source'])
    return raw


def unique_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('Duplicate source-map key: ' + key)
        result[key] = value
    return result


def stage(root, source_map, output):
    root = Path(root).resolve(strict=True)
    requested = Path(output).expanduser()
    if requested.exists() or requested.is_symlink():
        raise FileExistsError('Choose a fresh output directory; preserve existing results')
    output = requested.resolve()
    if output == root or output.is_relative_to(root):
        raise ValueError('Output must be outside the source repository')
    map_path = regular_input(root, source_map)
    raw_map = map_path.read_bytes()
    selected = json.loads(raw_map, object_pairs_hook=unique_keys)
    if not isinstance(selected, dict) or selected.get('schema') != SCHEMA:
        raise ValueError('Unsupported source-map schema')
    files = selected.get('files')
    if not isinstance(files, dict) or not files or type(selected.get('expected_files')) is not int or selected['expected_files'] != len(files):
        raise ValueError('Incomplete source-map inventory')
    for name, row in files.items():
        relative = relative_name(name)
        if any(parent.as_posix() in files for parent in relative.parents):
            raise ValueError('Colliding destination file/directory: ' + name)
        if not isinstance(row, dict) or set(row) != {'source', 'bytes', 'sha256', 'kind'}:
            raise ValueError('Invalid source-map entry: ' + name)
        relative_name(row['source'])
        if type(row['bytes']) is not int or not 0 <= row['bytes'] <= MAX_FILE_BYTES:
            raise ValueError('Invalid source byte count: ' + name)
        if not isinstance(row['sha256'], str) or re.fullmatch('[0-9a-f]{64}', row['sha256']) is None:
            raise ValueError('Invalid source digest: ' + name)
        if row['kind'] not in ('shared', 'retained'):
            raise ValueError('Invalid source kind: ' + name)
        # All inputs pass before the output directory is created.
        checked_bytes(root, row)
    output.mkdir(parents=True, exist_ok=False)
    for name, row in sorted(files.items()):
        # Recheck copied bytes so an input changed since preflight cannot pass.
        raw = checked_bytes(root, row)
        destination = output.joinpath(*relative_name(name).parts)
        destination.parent.mkdir(parents=True, exist_ok=True)
        with destination.open('xb') as stream:
            stream.write(raw)
    return {'passed': True, 'output': str(output), 'files': len(files),
            'shared_sources': sum(row['kind'] == 'shared' for row in files.values()),
            'source_map_sha256': hashlib.sha256(raw_map).hexdigest(),
            'native_execution': False, 'network_access': False, 'hardware_access': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--map', required=True, help='source map relative to the repository root')
    parser.add_argument('--output', required=True, type=Path, help='new directory outside this repository')
    args = parser.parse_args()
    try:
        result = stage(ROOT, args.map, args.output)
    except (ValueError, OSError) as error:
        parser.exit(2, 'error: ' + str(error) + '\n')
    print(json.dumps(result, sort_keys=True))


if __name__ == '__main__':
    main()
