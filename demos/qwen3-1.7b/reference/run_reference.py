"""Regenerate recorded token IDs with the fixed numerical model, on CPU or MPS.

This is a software verification program, never a fallback in the FPGA app.
It contacts no cloud service and reads no private engineering artifacts.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import time

os.environ['PYTORCH_MPS_FAST_MATH'] = '0'
ROOT = Path(__file__).resolve().parents[1]


def select_cases(campaign):
    source = json.loads((ROOT/'measurements.json').read_text())
    if campaign == 'all':
        # Repeated campaigns need not repeat identical deterministic prefixes.
        chosen = {}
        for group in source['campaigns']:
            for case in group['cases']:
                key = tuple(case['prompt_tokens'])
                old = chosen.get(key)
                if old is not None:
                    n = min(len(old['expected_tokens']), len(case['expected_tokens']))
                    if old['expected_tokens'][:n] != case['expected_tokens'][:n]:
                        raise ValueError('Recorded deterministic prefixes disagree')
                if old is None or len(case['expected_tokens']) > len(old['expected_tokens']):
                    chosen[key] = case
        return list(chosen.values())
    matches = [group['cases'] for group in source['campaigns'] if group['name'] == campaign]
    if len(matches) != 1:
        raise ValueError('Unknown or ambiguous campaign')
    return matches[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model-image', type=Path, required=True)
    parser.add_argument('--campaign', default='full-smoke', choices=(
        'first-smoke', 'full-smoke', 'sustained-128-run1', 'sustained-128-run2',
        'prefill-64-256-512', 'all'))
    parser.add_argument('--backend', choices=('cpu', 'mps'), default='cpu')
    parser.add_argument('--threads', type=int, default=8)
    parser.add_argument('--mps-memory-fraction', type=float, default=0.2)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if not 1 <= args.threads <= 32 or not 0 < args.mps_memory_fraction <= 1:
        parser.error('Use 1–32 CPU threads and an MPS memory fraction in (0,1]')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.output.exists():
        parser.error('Output already exists; choose a fresh result path')
    import torch
    import numpy as np
    from fixed_qwen_reference import FixedQwenEngine, TokenMachine
    from model_image import IMAGE_SHA256
    torch.set_num_threads(args.threads)
    torch.set_float32_matmul_precision('highest')
    if args.backend == 'mps':
        if not torch.backends.mps.is_available():
            raise ValueError('MPS is not available; select --backend cpu')
        torch.mps.set_per_process_memory_fraction(args.mps_memory_fraction)
    cases = select_cases(args.campaign)
    started = time.monotonic()
    engine = FixedQwenEngine(args.model_image, device=args.backend, serial_prefill=True,
        norm_arithmetic='ordered-fp32', nonlinear_arithmetic='fixed-tables',
        attention_arithmetic='tree-qk-ordered-av', softmax_arithmetic='fixed-exp2-exact-sum')
    machine = TokenMachine(engine)
    record = dict(schema='qwen-portable-reference-run-v1', passed=False,
        model_image_sha256=IMAGE_SHA256, campaign=args.campaign, backend=args.backend,
        torch=torch.__version__, numpy=np.__version__, threads=args.threads,
        measurements_sha256=hashlib.sha256((ROOT/'measurements.json').read_bytes()).hexdigest(),
        software_reference_only=True, hardware_access=False, cases=[])
    for case in cases:
        machine.clear()
        for token in case['prompt_tokens']:
            machine.append(token)
        tokens = []
        for index, expected in enumerate(case['expected_tokens']):
            token = machine.step()
            tokens.append(token)
            if token != expected:
                raise ValueError(f"{case['name']} token {index}: got {token}, expected {expected}")
        record['cases'].append(dict(name=case['name'], prompt_tokens=case['prompt_tokens'], tokens=tokens))
        print(f"PASS {case['name']}: {len(tokens)} tokens", flush=True)
    machine.clear()
    record.update(passed=True, compared_tokens=sum(len(c['tokens']) for c in record['cases']),
                  elapsed_seconds=time.monotonic()-started)
    with args.output.open('x') as stream:
        json.dump(record, stream, indent=2)
        stream.write('\n')
    print(json.dumps(dict(passed=True, compared_tokens=record['compared_tokens'],
                         elapsed_seconds=record['elapsed_seconds'])), flush=True)


if __name__ == '__main__':
    main()
