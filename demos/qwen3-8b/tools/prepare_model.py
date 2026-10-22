"""Reconstruct and verify the only model image accepted by this 8B circuit.

Offline unless --download is explicit. This program does not contact AWS,
configure an FPGA, or offer a runtime model-update operation.
"""
import argparse
import json
import os
from pathlib import Path

from fixed_model_export import build, digest, verify_sources

ROOT = Path(__file__).resolve().parents[1]
IMAGE_BYTES = 8828026880
IMAGE_SHA256 = 'a1e8a91912dfa79fb602601e256a4a07da64c57dda146529c08886532d42f833'
MODEL_ID = 'Qwen/Qwen3-8B'
REVISION = 'b968826d9c46dd6066d109eabc6255188de91218'


def check_image(directory):
    image = directory / 'model.bin'
    if image.is_symlink() or image.stat().st_size != IMAGE_BYTES or digest(image) != IMAGE_SHA256:
        raise ValueError('Not the fixed image accepted by this FPGA')
    receipt = json.loads((directory / 'FINISHED.json').read_text())
    if not receipt['passed'] or receipt['image_sha256'] != IMAGE_SHA256:
        raise ValueError('Different export receipt')
    return dict(passed=True, image_bytes=IMAGE_BYTES, image_sha256=IMAGE_SHA256,
                scope='Full image hash equality with the measured hardware model; not a new hardware test.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--download', action='store_true')
    parser.add_argument('--verify-only', action='store_true')
    parser.add_argument('--threads', type=int, default=8)
    args = parser.parse_args()
    lock_path = ROOT / 'model/source-lock.json'
    lock = json.loads(lock_path.read_text())
    if lock['model_id'] != MODEL_ID or lock['revision'] != REVISION:
        raise ValueError('Different source model')
    if args.download:
        os.environ['HF_HUB_DISABLE_IMPLICIT_TOKEN'] = '1'
        os.environ['HF_HUB_DISABLE_TELEMETRY'] = '1'
        from huggingface_hub import snapshot_download
        snapshot_download(repo_id=MODEL_ID, revision=REVISION, local_dir=args.source,
                          allow_patterns=list(lock['files']), token=False, max_workers=4)
    if args.verify_only:
        verify_sources(args.source, lock)
        print(json.dumps(dict(source_verified=True)))
        return
    if args.output is None:
        parser.error('--output must name a fresh directory')
    build(args.source, lock_path, args.output, threads=args.threads, positions=32768)
    result = check_image(args.output)
    with (args.output / 'CONTENT-VERIFIED.json').open('x') as stream:
        json.dump(result, stream, indent=2, sort_keys=True)
        stream.write('\n')
    print(json.dumps(result, sort_keys=True))


if __name__ == '__main__':
    main()
