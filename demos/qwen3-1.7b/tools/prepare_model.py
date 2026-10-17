"""Reconstruct the one accepted model-memory image from pinned Qwen data."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys

HERE = Path(__file__).resolve().parents[1]
IMAGE_BYTES = 2354380800
IMAGE_SHA256 = '90d82ed9b90c58607f924190be0c15f18b70d849c536a2ccbddd259858979cd1'
ROPE_SHA256 = 'a75ae922ed520915d07b4f2b01dd26a7c8083fbe96a1419b867403cccb7cf3c5'


def digest(path, git=False):
    h = hashlib.sha1() if git else hashlib.sha256()
    if git:
        h.update(('blob ' + str(path.stat().st_size) + '\0').encode())
    with path.open('rb') as f:
        for block in iter(lambda: f.read(4 * 1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def verify_sources(source):
    lock = json.loads((HERE / 'model/source-lock.json').read_text())
    for name, expected in lock['files'].items():
        path = source / name
        key = 'sha256' if 'sha256' in expected else 'git_blob_sha1'
        if not path.is_file() or path.stat().st_size != expected['bytes'] or digest(path, key == 'git_blob_sha1') != expected[key]:
            raise ValueError('Missing or changed upstream data: ' + name)
    return lock


def download(source):
    os.environ['HF_HUB_DISABLE_IMPLICIT_TOKEN'] = '1'
    os.environ['HF_HUB_DISABLE_TELEMETRY'] = '1'
    from huggingface_hub import snapshot_download
    lock = json.loads((HERE / 'model/source-lock.json').read_text())
    snapshot_download(repo_id=lock['model_id'], revision=lock['revision'],
                      local_dir=source, allow_patterns=list(lock['files']),
                      token=False, max_workers=4)


def build(source, output, threads=8):
    import numpy as np
    import torch
    from safetensors import safe_open
    from fixed_model_layout import model_layout, pack_codes, embedding_bits
    verify_sources(source)
    if sys.byteorder != 'little':
        raise ValueError('This exporter requires a little-endian machine')
    if not 1 <= threads <= 32:
        raise ValueError('Choose 1–32 CPU threads')
    torch.set_num_threads(threads)
    layout = model_layout()
    assert layout['image_bytes'] == IMAGE_BYTES
    rope = HERE / 'model/rope-cos-sin-bf16.bin'
    if rope.stat().st_size != layout['rotary']['bytes'] or digest(rope) != ROPE_SHA256:
        raise ValueError('Changed fixed rotary table')
    index = json.loads((source / 'model.safetensors.index.json').read_text())['weight_map']
    matrices = {x['name']: x for x in layout['matrices']}
    vectors = {x['name']: x for x in layout['vectors']}
    if set(index) != set(matrices) | set(vectors) | {'lm_head.weight'}:
        raise ValueError('Unexpected tensor set')
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists() or output.is_symlink():
        raise ValueError('Output already exists; choose a new output path')
    if shutil.disk_usage(output.parent).free < IMAGE_BYTES + 1024**3:
        raise ValueError('Need image size plus 1 GiB free space')
    partial = output.with_name(output.name + '.partial')
    with partial.open('xb') as f:
        f.truncate(IMAGE_BYTES)
    image = np.memmap(partial, dtype=np.uint8, mode='r+', shape=(IMAGE_BYTES,))
    def write(offset, data):
        raw = np.frombuffer(data, dtype=np.uint8)
        image[offset:offset + len(raw)] = raw
    seen = set()
    for shard in sorted(set(index.values())):
        with safe_open(source / shard, framework='pt', device='cpu') as tensors:
            for name in tensors.keys():
                if name == 'lm_head.weight':
                    continue
                t = tensors.get_tensor(name)
                if t.dtype != torch.bfloat16 or not torch.isfinite(t).all():
                    raise ValueError('Unexpected tensor type/nonfinite value: ' + name)
                seen.add(name)
                if name in vectors:
                    v = vectors[name]
                    if list(t.shape) != [v['elements']]:
                        raise ValueError('Vector shape mismatch')
                    write(v['offset'], t.view(torch.uint16).numpy().tobytes())
                    continue
                m = matrices[name]
                if list(t.shape) != [m['rows'], m['columns']]:
                    raise ValueError('Matrix shape mismatch')
                for start in range(0, m['rows'], 256):
                    value = t[start:start+256].float()
                    scale = value.abs().amax(dim=1, keepdim=True) / 127.0
                    scale = torch.where(scale == 0, torch.ones_like(scale), scale)
                    codes = torch.round(value / scale).clamp(-127, 127).to(torch.int8).numpy()
                    scales = scale.numpy()
                    write(m['codes_offset'] + start*m['columns'], pack_codes(codes).tobytes())
                    write(m['scales_offset'] + start*4, scales.astype('<f4').tobytes())
                    if name == 'model.embed_tokens.weight':
                        write(layout['embedding']['offset'] + start*4096, embedding_bits(codes, scales).tobytes())
                print('Packed ' + name, flush=True)
    if seen != set(matrices) | set(vectors):
        raise ValueError('Missing or extra source tensor')
    # Independently verify the tied upstream output head, not just its config flag.
    with safe_open(source/index['lm_head.weight'], framework='pt', device='cpu') as a, safe_open(source/index['model.embed_tokens.weight'], framework='pt', device='cpu') as b:
        head, embedding = a.get_tensor('lm_head.weight'), b.get_tensor('model.embed_tokens.weight')
        if not torch.equal(head, embedding):
            raise ValueError('Upstream tied head/embedding disagree')
    write(layout['rotary']['offset'], rope.read_bytes())
    image.flush()
    del image
    actual = digest(partial)
    if actual != IMAGE_SHA256:
        raise ValueError('Reconstructed image is NOT the accepted fixed image: ' + actual)
    # Do not overwrite another writer's completed output.
    os.link(partial, output)
    partial.unlink()
    return dict(passed=True, image_bytes=IMAGE_BYTES, image_sha256=actual,
                source_revision='70d244cc86ccca08cf5af4e1e306ecf908b1ad5e',
                torch=torch.__version__, numpy=np.__version__, threads=threads)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source', type=Path, required=True)
    p.add_argument('--output', type=Path)
    p.add_argument('--download', action='store_true', help='Explicitly fetch pinned upstream data (~4.1 GB)')
    p.add_argument('--verify-only', action='store_true')
    p.add_argument('--threads', type=int, default=8)
    args = p.parse_args()
    if args.download:
        download(args.source)
    if args.verify_only:
        verify_sources(args.source)
        print(json.dumps(dict(source_verified=True)))
    else:
        if args.output is None:
            p.error('--output is required unless --verify-only')
        print(json.dumps(build(args.source, args.output, args.threads), sort_keys=True))


if __name__ == '__main__':
    main()
