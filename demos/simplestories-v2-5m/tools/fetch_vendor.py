#!/usr/bin/env python3
"""Fetch four exact rebuild inputs from the official Sipeed example.

Not needed to run the prebuilt demo. Does not install tools, accept licenses,
execute downloaded code, or open a board. --check is entirely offline.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import urllib.request

REVISION = '06e7d8b118d345915ab6f257b7c22226f81575cd'
BASE = 'https://raw.githubusercontent.com/sipeed/TangMega-138K-example/' + REVISION + '/ddr_memory/ddr_memory_test_uart/src/'
FILES = {
    'ddr3_memory_interface.v': ('ddr3_memory_interface/ddr3_memory_interface.v', 2238123, 'd7cae5a16467ca35ee3f95411537344ae3702e1dba86a06571530e3dd0180c57'),
    'gowin_pll.v': ('gowin_pll/gowin_pll.v', 992, '982ca6387f42086e88b4c858490eb00954a80a3284e0f07d959311d0975d7536'),
    'gowin_pll_mod.v': ('gowin_pll/gowin_pll_mod.v', 6081, '07398632b56749dbe52f6e5d739a526c7ca5e71c4060c7d062a64dada6e1a953'),
    'pll_init.v': ('pll_init.v', 6458, '502436115e507453e2c139a073f5b56484421311ef57088ce1a16140347957f5'),
}


def validate(data, size, digest):
    if len(data) != size or hashlib.sha256(data).hexdigest() != digest:
        raise ValueError('Unexpected upstream file contents; do not substitute a new hash')


def acquire(directory, check=False, opener=urllib.request.urlopen):
    directory = Path(directory).absolute()
    if any(p.is_symlink() for p in (directory, *directory.parents)):
        raise ValueError('Use a directory without symbolic-link components')
    if not check:
        directory.mkdir(parents=True, exist_ok=True)
    results = {}
    for name, (relative, size, digest) in FILES.items():
        path = directory / name
        if path.is_symlink():
            raise ValueError('Refusing a linked vendor file')
        if path.exists():
            if not path.is_file() or path.stat().st_size != size:
                raise ValueError('Unexpected existing vendor file')
            validate(path.read_bytes(), size, digest)
        elif check:
            raise FileNotFoundError(name)
        else:
            url = BASE + relative
            with opener(url, timeout=90) as response:
                data = response.read(size + 1)
            validate(data, size, digest)
            # Publish only fully checked bytes; never overwrite an existing file.
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, 'O_NOFOLLOW', 0), 0o600)
            with os.fdopen(fd, 'wb') as out:
                out.write(data)
                out.flush()
                os.fsync(out.fileno())
        results[name] = digest
    return {'passed': True, 'revision': REVISION, 'files': results,
            'network_allowed': not check, 'hardware_access': False}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('directory', type=Path)
    ap.add_argument('--check', action='store_true')
    ap.add_argument('--confirm-permitted-vendor-use', action='store_true')
    args = ap.parse_args()
    if not args.check and not args.confirm_permitted_vendor_use:
        ap.error('Read VENDOR-SETUP.md and confirm permitted vendor use before downloading')
    print(json.dumps(acquire(args.directory, args.check), indent=2, sort_keys=True))


if __name__ == '__main__': main()
