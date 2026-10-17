"""Read only the hash-locked fixed model image; no private project paths."""
import hashlib
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from fixed_model_layout import model_layout, unpack_codes

IMAGE_BYTES = 2354380800
IMAGE_SHA256 = '90d82ed9b90c58607f924190be0c15f18b70d849c536a2ccbddd259858979cd1'
ASSETS = {
    'silu': ('reference/tables/silu-bf16.bin', 131072, '859765e19bdbff036092c2348745f589803006506e6ec78d77be3d4d516fd77a'),
    'softmax': ('reference/tables/softmax-exp2.bin', 8192, '7914026720a0167743ba2e68d3aaf0b86255b75d878ad56e5fa1827dad9b77f3'),
    'rope': ('model/rope-cos-sin-bf16.bin', 8388608, 'a75ae922ed520915d07b4f2b01dd26a7c8083fbe96a1419b867403cccb7cf3c5'),
}


def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(4*1024*1024), b''):
            h.update(block)
    return h.hexdigest()


def checked_file(path, size, sha):
    path = Path(path)
    if not path.is_file() or path.stat().st_size != size or digest(path) != sha:
        raise ValueError('Missing or changed fixed numerical input: '+str(path))
    return path


def checked_asset(name):
    relative, size, sha = ASSETS[name]
    return checked_file(ROOT/relative, size, sha)


class FixedImage:
    def __init__(self, path):
        import numpy as np
        if sys.byteorder != 'little':
            raise ValueError('Reference loader requires a little-endian computer')
        path = checked_file(path, IMAGE_BYTES, IMAGE_SHA256)
        layout = model_layout()
        if layout['image_bytes'] != IMAGE_BYTES:
            raise ValueError('Different memory layout')
        self.data = np.memmap(path, mode='r', dtype=np.uint8, shape=(IMAGE_BYTES,))
        self.matrices = {row['name']: row for row in layout['matrices']}
        self.vectors = {row['name']: row for row in layout['vectors']}

    def matrix(self, name):
        import numpy as np
        import torch
        row = self.matrices[name]
        start = row['codes_offset']
        packed = self.data[start:start+row['codes_bytes']].view(np.int8)
        codes = unpack_codes(packed, row['rows'], row['columns']).copy()
        start = row['scales_offset']
        scales = self.data[start:start+row['scales_bytes']].view('<f4').reshape(row['rows'], 1).copy()
        if not np.isfinite(scales).all() or not (scales > 0).all():
            raise ValueError('Invalid row scale')
        return torch.from_numpy(codes), torch.from_numpy(scales)

    def vector(self, name):
        import numpy as np
        import torch
        row = self.vectors[name]
        bits = self.data[row['offset']:row['offset']+row['bytes']].view('<i2').copy()
        value = torch.from_numpy(bits).view(torch.bfloat16)
        if not torch.isfinite(value).all():
            raise ValueError('Invalid normalization coefficient')
        return value
