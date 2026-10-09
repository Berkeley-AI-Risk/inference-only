#!/usr/bin/env python3
"""Replay one curated prompt using only the packaged integer model."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

if not sys.flags.isolated or not sys.flags.dont_write_bytecode or sys.flags.optimize:
    raise SystemExit('Use the pinned reference environment Python -I -B, without -O.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference-root', required=True, type=Path)
    parser.add_argument('--rom', required=True, type=Path)
    parser.add_argument('--cases', required=True, type=Path)
    parser.add_argument('--case', required=True)
    options = parser.parse_args()
    reference = options.reference_root.resolve(strict=True)
    code = (reference / 'quantization/oracle.py').read_bytes()
    if hashlib.sha256(code).hexdigest() != '9b048a8e8b82faba3d21fd6b259aa1c23d91f04662fe2734fc109602777b4a74':
        raise SystemExit('FAIL: reference source identity differs')
    sys.path.insert(0, str(reference))
    import numpy as np
    from quantization.oracle import IntegerLlama, QuantizedModel
    if np.__version__ != '1.26.4': raise SystemExit('FAIL: reference NumPy version differs')
    case = json.loads(options.cases.read_text())[options.case]
    expected = case['generated_tokens']
    model = IntegerLlama(QuantizedModel.load(options.rom))
    actual = model.generate(case['prompt_tokens'], len(expected), stop_at_eos=True)
    if actual != expected:
        raise SystemExit('FAIL: token sequence differs for ' + options.case)
    print('PASS_REFERENCE ' + json.dumps({'case': options.case,
        'prompt_tokens': len(case['prompt_tokens']), 'generated_tokens': actual,
        'reference_sha256': hashlib.sha256(code).hexdigest(), 'hardware_access': False}, sort_keys=True), flush=True)


if __name__ == '__main__': main()
