#!/usr/bin/env python3
"""Offline release-file check. Never opens a device, network or vendor tool.

Checksums detect changed files relative to this package, not a maliciously
replaced repository, a publisher signature or the current FPGA configuration.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import stat

ASSETS = {
    'prebuilt/encrypted-memory/project/impl/pnr/shared_product.fs': (42303596, '865e74e692d5978815fe921f11e4fa1b8e2c080401a8be05508dd9775823aecc'),
    'assets/board1-encrypted-model2048.bin': (7265984, '88da38f3eb64bacc21aa472666b0cc8ea1e516cb04c80e0678f768425e6390eb'),
    'prebuilt/inference/project/impl/pnr/shared_product.fs': (41074783, '6ba3caa4f88ac58dd30336c3ff4478f836779db0d04309ff457ca065ec1f7f09'),
    'prebuilt/kv-protected/project/impl/pnr/shared_product.fs': (42198463, '72d5a54e06ed2017e653122f3daecf073f239a917b79f24d1e7b886d68a21a2f'),
    'prebuilt/flash-reader/readonly_flash_reader.fs': (34668952, '5c0736fff07d5550dc2b563df009bc9f8922a100b38cbb93db5cf2a7eb7824c9'),
    'assets/board1-real-semantic-image2048.bin': (7265984, 'cad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0'),
    'host-app/assets/tokenizer.json': (86463, '01b6553da99789d461cec48eed624684a803f259a5177616a67f7391700acf51'),
}
VARIANTS = {
    'encrypted-memory': ('prebuilt/encrypted-memory', 'variants/encrypted-memory/hardware',
        'hardware-inputs-encrypted-memory.json', 100, '840c12ce7d1a5886966aca73e7c44eb3e42b9ee07ab33adcb2de3d273125e262'),
    'baseline': ('prebuilt/inference', 'hardware', 'hardware-inputs.json', 90,
        '8955cde51f78b582612ca4ee61d146b6128a85a535b3d492d325a4168f77e334'),
    'kv-protected': ('prebuilt/kv-protected', 'variants/kv-protected/hardware',
        'hardware-inputs-kv-protected.json', 93,
        'cfff67c4559b290287ea0c024f4782154fc0c27aa62bb3b264b2e5bf472ed7b2'),
}


def file_identity(path):
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_size > 64 * 1024 * 1024:
        raise ValueError('Expected a bounded regular release file')
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(chunk)
    after = path.lstat()
    if (after.st_dev, after.st_ino, after.st_mode, after.st_size, after.st_mtime_ns, after.st_ctime_ns) != (
            info.st_dev, info.st_ino, info.st_mode, info.st_size, info.st_mtime_ns, info.st_ctime_ns):
        raise ValueError('File changed during verification')
    return {'bytes': info.st_size, 'sha256': digest.hexdigest()}


def checked_path(package, name):
    relative = PurePosixPath(name)
    if not name or relative.is_absolute() or '..' in relative.parts or str(relative) != name or '\\' in name:
        raise ValueError('Unsafe manifest path')
    path = package / relative
    if any(p.is_symlink() for p in (path, *path.parents) if p != package and p.is_relative_to(package)):
        raise ValueError('Linked release path')
    return path


def inventory(package, strict=False):
    package = Path(package).resolve(strict=True)
    manifest_path = checked_path(package, 'MANIFEST.json')
    file_identity(manifest_path)
    manifest = json.loads(manifest_path.read_text())
    for name, expected in manifest['files'].items():
        if file_identity(checked_path(package, name)) != expected:
            raise ValueError('Changed release file: ' + name)
    if strict:
        found = {p.relative_to(package).as_posix() for p in package.rglob('*')
                 if not p.is_dir() and '.git' not in p.relative_to(package).parts}
        if found != set(manifest['files']) | {'MANIFEST.json'}:
            raise ValueError('Unlisted or missing files in clean release directory')
    return manifest


def verify(package, strict=False):
    package = Path(package).resolve(strict=True)
    manifest = inventory(package, strict)
    for name, (size, digest) in ASSETS.items():
        if manifest['files'].get(name) != {'bytes': size, 'sha256': digest}:
            raise ValueError('Missing or unexpected selected asset: ' + name)
    counts = {}
    vendor = json.loads((package / 'VENDOR-DEPENDENCIES.json').read_text())['not_included']
    for variant, (prebuilt, hardware, inventory_name, count, inventory_sha) in VARIANTS.items():
        receipt = json.loads((package / prebuilt / 'BUILD.json').read_text())
        if not all(receipt.get(k) is True for k in ('flow_completed', 'source_inputs_verified', 'source_inputs_unchanged')):
            raise ValueError('Unsuccessful prebuilt build receipt: ' + variant)
        expected = ASSETS[prebuilt + '/project/impl/pnr/shared_product.fs']
        if (receipt['schema'] != 'fixed-fpga-local-build-v1' or receipt['image_sha256'] != expected[1]
                or receipt.get('variant', 'baseline') != variant
                or receipt.get('timing_qualified') is not False
                or receipt['image_relative_path'] != 'project/impl/pnr/shared_product.fs'):
            raise ValueError('Incorrect prebuilt image association: ' + variant)
        inputs = json.loads((package / 'host-app' / inventory_name).read_text())
        canonical = (json.dumps(inputs, sort_keys=True, separators=(',', ':')) + '\n').encode()
        if (hashlib.sha256(canonical).hexdigest() != inventory_sha
                or receipt['hardware_inputs_sha256'] != inventory_sha or len(inputs) != count):
            raise ValueError('Hardware source identity mismatch: ' + variant)
        external = {}
        for name, digest in inputs.items():
            if name.startswith('project/official/'):
                external[name.removeprefix('project/')] = digest
            elif manifest['files'][hardware + '/' + name]['sha256'] != digest:
                raise ValueError('Selected hardware source changed: ' + variant)
        if external != vendor:
            raise ValueError('Unexpected vendor inputs: ' + variant)
        counts[variant] = len(inputs)
    return {'passed': True, 'files': len(manifest['files']) + 1, 'selected_assets': len(ASSETS),
        'hardware_inputs': counts, 'manifest_sha256': file_identity(package / 'MANIFEST.json')['sha256'],
        'hardware_access': False, 'network_access': False, 'timing_qualified': False,
        'scope': 'Local release-file integrity and selected build/source association, not physical attestation or whole-chip certification.'}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--package', type=Path, default=Path(__file__).resolve().parents[1])
    ap.add_argument('--strict', action='store_true', help='Reject unlisted files in a clean export (except .git)')
    args = ap.parse_args()
    print(json.dumps(verify(args.package, args.strict), indent=2, sort_keys=True))


if __name__ == '__main__': main()
