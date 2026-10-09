#!/usr/bin/env python3
"""Check a complete ciphertext flash-readback FILE; no hardware or writes.

The independent plaintext-layout checker stays unchanged. Neither checker
establishes physical-read provenance or the configuration of a connected FPGA.
"""
import argparse
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('plain_flash_check',ROOT/'tools/check_flash_layout.py')
plain = importlib.util.module_from_spec(spec); spec.loader.exec_module(plain)
MODEL_SHA = '88da38f3eb64bacc21aa472666b0cc8ea1e516cb04c80e0678f768425e6390eb'
FLASH_SHA = '779fc1a8a0158ce66e7dc52ac4662259f5618f01303d3299eb990b2f361d2ef1'


def check_layout(model_path,readback_path):
    model,_ = plain.read_regular(model_path,plain.MODEL_BYTES)
    if plain.sha(model) != MODEL_SHA: raise ValueError('Not the selected ciphertext image')
    readback,_ = plain.read_regular(readback_path,plain.CAPACITY)
    plain.compare_regions(model,readback)
    if plain.sha(readback) != FLASH_SHA: raise ValueError('Wrong complete ciphertext flash image')
    return dict(passed=True,kind='encrypted_model_layout',bytes=plain.CAPACITY,
        model_start=plain.BASE,model_end_exclusive=plain.BASE+plain.MODEL_BYTES,
        model_sha256=MODEL_SHA,flash_sha256=FLASH_SHA,other_bytes='FF',hardware_access=False,
        scope='Local file contents only; not physical-read provenance or current-board attestation.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model',type=Path,default=ROOT/'assets/board1-encrypted-model2048.bin')
    parser.add_argument('--readback',type=Path,required=True)
    args = parser.parse_args()
    print(json.dumps(check_layout(args.model,args.readback),indent=2))


if __name__ == '__main__': main()
