"""Check that captured GPU decode reads changing tokens and prompt caches.

This is a GPU-benchmark correctness check, not an FPGA test or a performance
measurement. Runs on exactly one full H100 SXM with the pinned public model.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path

import benchmark as bench
from model_snapshot import verify


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model-dir', type=Path, default=Path('.model'))
    parser.add_argument('--mode', choices=('graph', 'compile-graph'), required=True)
    parser.add_argument('--batch', type=int, default=16)
    parser.add_argument('--context', type=int, default=128)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError(args.output)
    verify(args.model_dir)
    torch, _, _, _ = bench.load_stack()
    torch.set_num_threads(8)
    torch.set_grad_enabled(False)
    torch.backends.cuda.matmul.allow_tf32 = False
    torch.backends.cudnn.allow_tf32 = False
    torch.backends.cuda.matmul.allow_fp16_reduced_precision_reduction = False
    torch.backends.cuda.matmul.allow_bf16_reduced_precision_reduction = False
    if torch.cuda.device_count() != 1:
        raise ValueError('Expose exactly one GPU')
    identity = bench.gpu_identity(torch)
    if 'H100' not in identity['name'] or identity['multiprocessor_count'] != 132:
        raise ValueError('Expected a full H100 SXM')

    def caches(step):
        return list(step.cache.key_cache) + list(step.cache.value_cache)

    def compare_with_full(model, inputs, logits, tokens):
        full = model(input_ids=inputs, use_cache=False,
                     num_logits_to_keep=1).logits[:, -1, :]
        torch.testing.assert_close(logits, full, rtol=0.01, atol=0.15)
        if not torch.equal(tokens, full.argmax(-1)):
            raise ValueError('Greedy result disagrees with uncached inference')
        return bench.logits_comparison(logits, full)

    with torch.inference_mode():
        model = bench.load_model(args.model_dir, 'float16', 'cuda')
        inputs = bench.make_inputs(args.batch, args.context, 20260916, 'cuda')
        step = bench.FixedDecode(model, inputs)
        prefix = [tensor[:, :, :-1].clone() for tensor in caches(step)]
        runner, initial_check = bench.prepare_runner(step, args.mode)
        first_logits, first_tokens = runner()
        first_logits, first_tokens = first_logits.clone(), first_tokens.clone()
        original_input = step.input_ids.clone()
        baseline = compare_with_full(model, inputs, first_logits, first_tokens)
        for _ in range(3):
            repeated_logits, repeated_tokens = runner()
            torch.testing.assert_close(repeated_logits, first_logits, rtol=0, atol=0)
            if not torch.equal(repeated_tokens, first_tokens):
                raise ValueError('Repeated decode changed tokens')
        for before, after in zip(prefix, caches(step)):
            if not torch.equal(before, after[:, :, :-1]):
                raise ValueError('Decode changed cached prefix')

        changed_inputs = inputs.clone()
        changed_inputs[:, -1] = (changed_inputs[:, -1] + 137) % 4019
        step.input_ids.copy_(changed_inputs[:, -1:])
        changed_logits, changed_tokens = runner()
        changed_logits, changed_tokens = changed_logits.clone(), changed_tokens.clone()
        token_change = compare_with_full(model, changed_inputs, changed_logits, changed_tokens)
        if torch.equal(first_logits, changed_logits):
            raise ValueError('Runner ignored changed final tokens')
        for before, after in zip(prefix, caches(step)):
            if not torch.equal(before, after[:, :, :-1]):
                raise ValueError('Changed-token decode changed cached prefix')

        second_inputs = bench.make_inputs(args.batch, args.context, 20260917, 'cuda')
        second_inputs[:, -1:] = original_input
        second_step = bench.FixedDecode(model, second_inputs)
        for destination, source in zip(caches(step), caches(second_step)):
            destination.copy_(source)
        step.input_ids.copy_(original_input)
        second_logits, second_tokens = runner()
        second_logits, second_tokens = second_logits.clone(), second_tokens.clone()
        prompt_change = compare_with_full(model, second_inputs, second_logits, second_tokens)
        if torch.equal(second_logits, first_logits):
            raise ValueError('Runner ignored changed prompt prefix')

        for destination, source in zip(caches(step), prefix):
            destination[:, :, :-1].copy_(source)
        restored_logits, restored_tokens = runner()
        torch.testing.assert_close(restored_logits, first_logits, rtol=0, atol=0)
        if not torch.equal(restored_tokens, first_tokens):
            raise ValueError('Restored prompt did not reproduce baseline')

    result = {
        'status': 'pass', 'time_utc': datetime.now(timezone.utc).isoformat(),
        'mode': args.mode, 'batch': args.batch, 'context': args.context,
        'gpu': identity, 'cuda_visible_devices': os.environ.get('CUDA_VISIBLE_DEVICES'),
        'source_sha256': {name: hashlib.sha256(Path(name).read_bytes()).hexdigest()
                          for name in ('benchmark.py', 'model_snapshot.py', 'check_gpu_replay.py')},
        'checks': {'initial_optimized_vs_eager': initial_check,
                   'baseline_vs_uncached': baseline, 'changed_token_vs_uncached': token_change,
                   'changed_prompt_vs_uncached': prompt_change,
                   'key_and_value_prefix_unchanged': True,
                   'repeated_and_restored_outputs_exact': True},
        'scope': 'GPU replay correctness on changed tokens and two prompts; not a speed measurement or FPGA-bit-exact equivalence.',
    }
    with args.output.open('x') as handle:
        json.dump(result, handle, indent=2)
        handle.write('\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
