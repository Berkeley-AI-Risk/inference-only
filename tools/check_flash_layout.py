#!/usr/bin/env python3
"""Check local flash-readback files; never open a device or modify a file.

This checks bytes only. It does not establish that a file came from a physical
read, that two reads were independent, or that a current board matches it.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import stat

CAPACITY = 16_777_216
BASE = 0x801000
MODEL_BYTES = 7_265_984
MODEL_SHA = 'cad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0'
FLASH_SHA = 'b6be312296b01d4eb2f985cd71f90d110a2a632c42ca0b4698dc8c9832765a25'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read_regular(path, size):
    path = Path(path)
    before = path.lstat()
    if not stat.S_ISREG(before.st_mode) or before.st_size != size:
        raise ValueError('Expected a regular file of exactly ' + str(size) + ' bytes')
    descriptor = os.open(path, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0) | getattr(os, 'O_NONBLOCK', 0))
    with os.fdopen(descriptor, 'rb') as source:
        opened = os.fstat(source.fileno())
        if not stat.S_ISREG(opened.st_mode) or (opened.st_dev, opened.st_ino) != (before.st_dev, before.st_ino):
            raise ValueError('File changed while opening')
        data = source.read(size + 1)
        after = os.fstat(source.fileno())
    if len(data) != size or (opened.st_size, opened.st_mtime_ns, opened.st_ctime_ns) != (
            after.st_size, after.st_mtime_ns, after.st_ctime_ns):
        raise ValueError('File changed while reading')
    return data, (opened.st_dev, opened.st_ino)


def compare_regions(model, readback):
    """Pure byte comparison, including both erased regions; not authentication."""
    if len(model) != MODEL_BYTES or len(readback) != CAPACITY:
        raise ValueError('Incorrect model or full-array length')
    end = BASE + MODEL_BYTES
    if readback[BASE:end] != model:
        raise ValueError('Model region differs')
    if readback[:BASE] != b'\xff' * BASE:
        raise ValueError('Bytes before the model are not erased')
    if readback[end:] != b'\xff' * (CAPACITY - end):
        raise ValueError('Bytes after the model are not erased')


def check_layout(model_path, readback_path):
    model, _ = read_regular(model_path, MODEL_BYTES)
    if sha(model) != MODEL_SHA:
        raise ValueError('Not the selected fixed-model image')
    readback, _ = read_regular(readback_path, CAPACITY)
    compare_regions(model, readback)
    if sha(readback) != FLASH_SHA:
        raise ValueError('Unexpected complete-array identity')
    return {'passed': True, 'kind': 'selected_model_layout', 'bytes': CAPACITY,
        'model_start': BASE, 'model_end_exclusive': BASE + MODEL_BYTES,
        'model_sha256': MODEL_SHA, 'flash_sha256': FLASH_SHA,
        'other_bytes': 'FF', 'hardware_access': False,
        'scope': 'Local file contents only; not physical-read provenance or current-board attestation.'}


def check_backups(first_path, second_path):
    first, first_id = read_regular(first_path, CAPACITY)
    second, second_id = read_regular(second_path, CAPACITY)
    if first_id == second_id:
        raise ValueError('Supply two distinct files, not one path or hard-linked aliases')
    if first != second:
        raise ValueError('Backup files differ')
    return {'passed': True, 'kind': 'equal_backup_files', 'bytes': CAPACITY,
        'sha256': sha(first), 'hardware_access': False,
        'scope': 'Two distinct equal files only. Independence and validity of physical reads require their own transport/identity records.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_subparsers(dest='action', required=True)
    layout = actions.add_parser('layout', help='Check the selected model and all 16 MiB of a readback')
    layout.add_argument('--model', type=Path, required=True)
    layout.add_argument('--readback', type=Path, required=True)
    backups = actions.add_parser('backups', help='Compare two complete backup files without overwriting either')
    backups.add_argument('first', type=Path)
    backups.add_argument('second', type=Path)
    args = parser.parse_args()
    try:
        result = check_layout(args.model, args.readback) if args.action == 'layout' else check_backups(args.first, args.second)
    except (OSError, ValueError) as error:
        parser.exit(1, 'FAIL: ' + str(error) + '\n')
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == '__main__':
    main()
