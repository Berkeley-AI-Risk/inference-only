"""Local deployment checks, not a security root or attestation of running silicon.

This replaces the original author's private load/test receipts with a locally
reproducible build record and an explicitly requested seven-command board test.
The hardware, not this editable host software, restricts the command surface.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import stat

APP = Path(__file__).resolve().parent
PROFILE = APP / 'local/board-profile.json'
HARDWARE_INPUTS_SHA256 = '8955cde51f78b582612ca4ee61d146b6128a85a535b3d492d325a4168f77e334'
VARIANTS = {
    'encrypted-memory': {
        'label': 'Encrypted external memory (public test keys)',
        'inventory': 'hardware-inputs-encrypted-memory.json',
        'hardware_root': 'variants/encrypted-memory/hardware',
        'inputs_sha256': '840c12ce7d1a5886966aca73e7c44eb3e42b9ee07ab33adcb2de3d273125e262', 'input_files': 100,
    },
    'baseline': {
        'label': 'Without K/V integrity checks',
        'inventory': 'hardware-inputs.json', 'hardware_root': 'hardware',
        'inputs_sha256': HARDWARE_INPUTS_SHA256, 'input_files': 90,
    },
    'kv-protected': {
        'label': 'K/V integrity protection',
        'inventory': 'hardware-inputs-kv-protected.json',
        'hardware_root': 'variants/kv-protected/hardware',
        'inputs_sha256': 'cfff67c4559b290287ea0c024f4782154fc0c27aa62bb3b264b2e5bf472ed7b2',
        'input_files': 93,
    },
}
PROFILE_SCHEMA = 'fixed-fpga-host-profile-v1'
BUILD_SCHEMA = 'fixed-fpga-local-build-v1'
EXPECTED_TOKENS = [200, 15, 103, 157]
# Both selected GOWIN text-format .fs files fit below this bound.
# This is a bounded host-file guard, not flash capacity or a model-size limit.
MAX_BITSTREAM_BYTES = 64 * 1024 * 1024


def sha(data: bytes) -> str: return hashlib.sha256(data).hexdigest()


def encode(value) -> bytes:
    return (json.dumps(value, sort_keys=True, indent=2) + '\n').encode()


def read_regular(path: Path, limit: int = 2 * 1024 * 1024) -> bytes:
    path = Path(path)
    fd = os.open(path, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0))
    with os.fdopen(fd, 'rb') as source:
        info = os.fstat(source.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_size > limit:
            raise ValueError('Expected a bounded regular file: ' + str(path))
        data = source.read(limit + 1)
        if len(data) > limit: raise ValueError('File grew past its limit: ' + str(path))
        return data


def variant_settings(variant: str = 'baseline') -> dict:
    if not isinstance(variant, str) or variant not in VARIANTS:
        raise ValueError('Unknown hardware variant; choose baseline, kv-protected or encrypted-memory.')
    return VARIANTS[variant]


def hardware_inputs(variant: str = 'baseline') -> dict[str, str]:
    selected = variant_settings(variant)
    files = json.loads(read_regular(APP / selected['inventory']))
    canonical = (json.dumps(files, sort_keys=True, separators=(',', ':')) + '\n').encode()
    if sha(canonical) != selected['inputs_sha256'] or len(files) != selected['input_files']:
        raise ValueError('The selected hardware input inventory changed.')
    return files


def private_write(path: Path, data: bytes):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, 'O_NOFOLLOW', 0), 0o600)
    with os.fdopen(fd, 'wb') as out:
        out.write(data); out.flush(); os.fsync(out.fileno())


def check_device(device: str, expected: dict | None = None) -> dict:
    if not isinstance(device, str) or not device.startswith('/dev/') or '\x00' in device:
        raise ValueError('Choose an explicit /dev/ serial device; automatic discovery is not used.')
    info = os.stat(device)
    if not stat.S_ISCHR(info.st_mode): raise OSError('The selected UART is not a character device.')
    identity = {'path': device, 'rdev': info.st_rdev, 'stat_dev': info.st_dev, 'inode': info.st_ino}
    if expected is not None and identity != expected:
        raise OSError('The USB device identity changed; stop the app and requalify the board.')
    return identity


def check_open_device(fd: int, expected: dict):
    info = os.fstat(fd)
    actual = {'path': expected['path'], 'rdev': info.st_rdev, 'stat_dev': info.st_dev, 'inode': info.st_ino}
    if not stat.S_ISCHR(info.st_mode) or actual != expected:
        raise OSError('The opened UART does not match the checked device.')


def check_build(receipt_path: Path) -> dict:
    receipt_path = Path(receipt_path).absolute()
    data = read_regular(receipt_path)
    record = json.loads(data)
    # Original v1 receipts have no variant field and identify the baseline.
    variant = record.get('variant', 'baseline')
    selected = variant_settings(variant)
    hardware_inputs(variant)
    if (record.get('schema') != BUILD_SCHEMA or record.get('flow_completed') is not True
            or record.get('source_inputs_verified') is not True
            or record.get('source_inputs_unchanged') is not True
            or record.get('hardware_inputs_sha256') != selected['inputs_sha256']):
        raise ValueError('The build record does not identify a completed build of the selected sources.')
    relative = PurePosixPath(record['image_relative_path'])
    if relative.is_absolute() or '..' in relative.parts or str(relative) != 'project/impl/pnr/shared_product.fs':
        raise ValueError('Unexpected build image location.')
    image_path = receipt_path.parent / relative
    image = read_regular(image_path, MAX_BITSTREAM_BYTES)
    if not image or sha(image) != record['image_sha256']:
        raise ValueError('The local bitstream changed after its build.')
    return {'build_receipt_path': str(receipt_path), 'build_receipt_sha256': sha(data),
        'image_path': str(image_path), 'image_sha256': sha(image),
        'variant': variant, 'hardware_inputs_sha256': selected['inputs_sha256'],
        'timing_qualified': record.get('timing_qualified') is True}


def configured_port() -> str | None:
    """Read only the small profile for an idle caption; never open a UART."""
    try:
        data = json.loads(read_regular(PROFILE))
        port = data['device']['path']
        return port if data.get('schema') == PROFILE_SCHEMA and isinstance(port, str) and port.startswith('/dev/') else None
    except (OSError, ValueError, KeyError, TypeError): return None


def configured_variant() -> str | None:
    """Idle UI label from the local profile, not a readback of FPGA state."""
    try:
        record = json.loads(read_regular(PROFILE))
        variant = record.get('variant', 'baseline')
        selected = variant_settings(variant)
        if (record.get('schema') == PROFILE_SCHEMA and record.get('passed') is True
                and record.get('hardware_inputs_sha256') == selected['inputs_sha256']):
            return selected['label']
    except (OSError, ValueError, KeyError, TypeError): pass
    return None


def load_checked() -> dict:
    profile = json.loads(read_regular(PROFILE))
    variant = profile.get('variant', 'baseline')
    selected = variant_settings(variant)
    if (profile.get('schema') != PROFILE_SCHEMA or profile.get('passed') is not True
            or profile.get('operator_confirmed_loaded_build') is not True
            or profile.get('hardware_configuration_not_independently_attested') is not True
            or profile.get('hardware_inputs_sha256') != selected['inputs_sha256']):
        raise ValueError('Missing or invalid local qualification profile. See README.md.')
    build = check_build(Path(profile['build_receipt_path']))
    if build['variant'] != variant:
        raise ValueError('Local hardware variant changed; stop and requalify the board.')
    for key in ('build_receipt_sha256', 'image_sha256', 'image_path'):
        if build[key] != profile[key]: raise ValueError('Local build association changed: ' + key)
    if not build['timing_qualified'] and profile.get('operator_acknowledged_unqualified_timing') is not True:
        raise ValueError('This build still needs an explicit exploratory timing acknowledgement.')
    if profile.get('known_answer') != {'prompt_tokens': [378], 'generated_tokens': EXPECTED_TOKENS,
            'initial_clear_acknowledged': True, 'final_clear_acknowledged': True}:
        raise ValueError('No matching completed local known-answer test.')
    raw = read_regular(Path(profile['qualification_log_path']))
    if sha(raw) != profile['qualification_log_sha256']:
        raise ValueError('The local qualification log changed.')
    rows = [json.loads(line) for line in raw.splitlines()]
    commands = [(row['operation'], row['operand'], row['token']) for row in rows if row.get('event') == 'qualification_result']
    expected = [('clear', 0, None), ('append', 378, None)] + [('step', 0, t) for t in EXPECTED_TOKENS] + [('clear', 0, None)]
    if commands != expected or not rows or rows[-1].get('event') != 'qualification_complete':
        raise ValueError('The recorded qualification sequence is incomplete or changed.')
    check_device(profile['device']['path'], profile['device'])
    return profile
