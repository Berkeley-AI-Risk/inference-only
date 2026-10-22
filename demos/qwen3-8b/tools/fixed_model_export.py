"""Build a fixed dense-Qwen image offline; this is not a deployed model loader.

Reuse the released byte packing and arithmetic. The untied 8B model has its
own quantized output head and retains the source BF16 embedding table. Image
hashes produced here are candidates until numerical and RTL qualification.
"""
import argparse
from dataclasses import asdict
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import time

from model_geometry import Geometry, expected_tensor_shapes, model_layout

AWS = Path(__file__).resolve().parents[1]
RELEASE = AWS
sys.path.insert(0, str(RELEASE / 'tools'))
from fixed_model_layout import pack_codes, embedding_bits

ROPE_SHA256 = 'a75ae922ed520915d07b4f2b01dd26a7c8083fbe96a1419b867403cccb7cf3c5'


def digest(path, git=False):
    h = hashlib.sha1() if git else hashlib.sha256()
    if git:
        h.update(('blob ' + str(path.stat().st_size) + '\0').encode())
    with path.open('rb') as stream:
        for data in iter(lambda: stream.read(4 * 1024 * 1024), b''):
            h.update(data)
    return h.hexdigest()


def verify_sources(source, lock):
    for name, expected in lock['files'].items():
        if Path(name).name != name:
            raise ValueError('Source lock must contain plain filenames')
        path = source / name
        key = 'sha256' if 'sha256' in expected else 'git_blob_sha1'
        if (path.is_symlink() or not path.is_file()
                or path.stat().st_size != expected['bytes']
                or digest(path, key == 'git_blob_sha1') != expected[key]):
            raise ValueError('Missing or changed locked source: ' + name)


def build(source, lock_path, output, threads=8, positions=32768):
    import numpy as np
    import torch
    from safetensors import safe_open

    started = time.monotonic()
    source, lock_path, output = map(Path, (source, lock_path, output))
    lock = json.loads(lock_path.read_text())
    verify_sources(source, lock)
    if sys.byteorder != 'little' or not 1 <= threads <= 32:
        raise ValueError('Little-endian machine and 1–32 CPU threads required')
    torch.set_num_threads(threads)
    g = Geometry.from_config(json.loads((source / 'config.json').read_text()), positions)
    layout, shapes = model_layout(g), expected_tensor_shapes(g)
    index = json.loads((source / 'model.safetensors.index.json').read_text())['weight_map']
    if set(index) != set(shapes):
        raise ValueError('Unexpected source tensor set')
    if any(name not in lock['files'] or Path(name).name != name for name in index.values()):
        raise ValueError('Unpinned tensor shard')
    rope = RELEASE / 'model/rope-cos-sin-bf16.bin'
    if digest(rope) != ROPE_SHA256 or rope.stat().st_size < layout['rotary']['bytes']:
        raise ValueError('Changed or insufficient fixed rotary table')
    if output.exists() or output.is_symlink():
        raise ValueError('Choose a fresh output directory')
    output.parent.mkdir(parents=True, exist_ok=True)
    if shutil.disk_usage(output.parent).free < layout['image_bytes'] + 4 * 1024**3:
        raise ValueError('Need model image plus 4 GiB free disk')
    output.mkdir()
    source_files = [Path(__file__), AWS / 'tools/model_geometry.py',
                    RELEASE / 'tools/fixed_model_layout.py']
    record = dict(schema='fixed-qwen-export-v1', passed=False,
                  model_id=lock['model_id'], source_revision=lock['revision'],
                  source_lock_sha256=digest(lock_path), geometry=asdict(g),
                  source_sha256={p.name: digest(p) for p in source_files},
                  numerical_contract=dict(projection_weights='signed int8, per-row FP32 absmax/127 scale, RNE',
                      embedding='derived quantized-head BF16' if g.tied_embeddings else 'source BF16 (untied)',
                      normalization_weights='source BF16', rotary_sha256=ROPE_SHA256),
                  torch=torch.__version__, numpy=np.__version__, threads=threads,
                  qualification='Image export only; not a hardware result or numerical quality qualification')
    for p in source_files:
        shutil.copy2(p, output / p.name)
    shutil.copy2(lock_path, output / 'source-lock.json')
    (output / 'layout.json').write_text(json.dumps(layout, indent=2, sort_keys=True) + '\n')
    (output / 'STARTED.json').write_text(json.dumps(record, indent=2, sort_keys=True) + '\n')
    partial = output / 'model.bin.partial'
    with partial.open('xb') as stream:
        stream.truncate(layout['image_bytes'])
    image = np.memmap(partial, dtype=np.uint8, mode='r+', shape=(layout['image_bytes'],))
    matrices = {m['name']: m for m in layout['matrices']}
    vectors = {v['name']: v for v in layout['vectors']}
    seen = set()

    def write(offset, data):
        raw = np.frombuffer(data, dtype=np.uint8)
        if not 0 <= offset <= layout['image_bytes'] - len(raw):
            raise ValueError('Image write overflow')
        image[offset:offset+len(raw)] = raw

    try:
        if g.tied_embeddings:
            with safe_open(source/index['lm_head.weight'], framework='pt', device='cpu') as a, \
                    safe_open(source/index['model.embed_tokens.weight'], framework='pt', device='cpu') as b:
                if not torch.equal(a.get_tensor('lm_head.weight'), b.get_tensor('model.embed_tokens.weight')):
                    raise ValueError('Tied head differs from embedding')
        for shard in sorted(set(index.values())):
            with safe_open(source/shard, framework='pt', device='cpu') as tensors:
                for name in tensors.keys():
                    if name not in shapes or index[name] != shard or name in seen:
                        raise ValueError('Unexpected or duplicate shard tensor: ' + name)
                    tensor = tensors.get_tensor(name)
                    if (list(tensor.shape) != shapes[name] or tensor.dtype != torch.bfloat16
                            or not torch.isfinite(tensor).all()):
                        raise ValueError('Invalid source tensor: ' + name)
                    seen.add(name)
                    if g.tied_embeddings and name == 'lm_head.weight':
                        continue
                    if name in vectors:
                        write(vectors[name]['offset'], tensor.view(torch.uint16).numpy().tobytes())
                        continue
                    if not g.tied_embeddings and name == 'model.embed_tokens.weight':
                        for start in range(0, g.vocab, 256):
                            write(layout['embedding']['offset'] + start*g.width*2,
                                  tensor[start:start+256].view(torch.uint16).numpy().tobytes())
                        print('Packed native BF16 embedding', flush=True)
                        continue
                    m = matrices[name]
                    for start in range(0, m['rows'], 256):
                        value = tensor[start:start+256].float()
                        scale = value.abs().amax(dim=1, keepdim=True) / 127.0
                        scale = torch.where(scale == 0, torch.ones_like(scale), scale)
                        codes = torch.round(value/scale).clamp(-127, 127).to(torch.int8).numpy()
                        scales = scale.numpy()
                        if not np.isfinite(scales).all() or (scales <= 0).any():
                            raise ValueError('Invalid quantized scale')
                        write(m['codes_offset'] + start*m['columns'], pack_codes(codes).tobytes())
                        write(m['scales_offset'] + start*4, scales.astype('<f4').tobytes())
                        if g.tied_embeddings and name == 'model.embed_tokens.weight':
                            write(layout['embedding']['offset'] + start*g.width*2,
                                  embedding_bits(codes, scales).tobytes())
                    print('Packed ' + name, flush=True)
        if seen != set(shapes):
            raise ValueError('Missing source tensor')
        write(layout['rotary']['offset'], rope.read_bytes()[:layout['rotary']['bytes']])
        image.flush()
        del image
        actual = digest(partial)
        os.link(partial, output/'model.bin')
        partial.unlink()
        record.update(passed=True, image_bytes=layout['image_bytes'], image_sha256=actual,
                      tensor_count=len(seen), elapsed_seconds=time.monotonic()-started,
                      completed_utc=datetime.now(timezone.utc).isoformat())
        (output/'FINISHED.json').write_text(json.dumps(record, indent=2, sort_keys=True)+'\n')
        print(json.dumps(record, indent=2, sort_keys=True), flush=True)
        return record
    except BaseException as error:
        record.update(error=str(error), exception=type(error).__name__,
                      elapsed_seconds=time.monotonic()-started,
                      failed_utc=datetime.now(timezone.utc).isoformat())
        (output/'FAILED.json').write_text(json.dumps(record, indent=2, sort_keys=True)+'\n')
        raise


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--source-lock', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--threads', type=int, default=8)
    parser.add_argument('--positions', type=int, default=32768)
    args = parser.parse_args()
    build(args.source, args.source_lock, args.output, args.threads, args.positions)
