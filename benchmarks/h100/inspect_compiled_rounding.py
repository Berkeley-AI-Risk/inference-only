"""Diagnose compiled FP16 disagreement without changing benchmark acceptance.

This records logits and FP32 comparisons for disagreeing rows. It does not
report a speed or turn a failed strict-greedy benchmark into a passed case.
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
    parser.add_argument('--batch', type=int, default=1024)
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
    with torch.inference_mode():
        model = bench.load_model(args.model_dir, 'float16', 'cuda')
        inputs = bench.make_inputs(args.batch, args.context, 20260916, 'cuda')
        step = bench.FixedDecode(model, inputs)
        eager, eager_tokens = step()
        eager, eager_tokens = eager.clone(), eager_tokens.clone()
        compiled = torch.compile(step, fullgraph=True, dynamic=False,
                                 mode='max-autotune-no-cudagraphs')
        stream = torch.cuda.Stream()
        stream.wait_stream(torch.cuda.current_stream())
        with torch.cuda.stream(stream):
            for _ in range(5):
                compiled()
        torch.cuda.current_stream().wait_stream(stream)
        torch.cuda.synchronize()
        graph = torch.cuda.CUDAGraph()
        with torch.cuda.graph(graph):
            actual, actual_tokens = compiled()
        graph.replay()
        torch.cuda.synchronize()
        comparison = bench.logits_comparison(actual, eager)
        torch.testing.assert_close(actual, eager, rtol=0.005, atol=0.05)
        mismatch = (actual_tokens != eager_tokens).nonzero().flatten()
        records = []
        fp32_comparison = None
        if mismatch.numel():
            selected = mismatch[:64]
            full32 = bench.load_model(args.model_dir, 'float32', 'cuda')
            logits32 = full32(input_ids=inputs[selected], use_cache=False,
                              num_logits_to_keep=1).logits[:, -1, :]
            fp32_comparison = {
                'sampled_rows': selected.numel(),
                'eager_fp16_vs_uncached_fp32': bench.logits_comparison(eager[selected], logits32),
                'compiled_fp16_vs_uncached_fp32': bench.logits_comparison(actual[selected], logits32),
            }
            for local, row in enumerate(selected.cpu().tolist()):
                a, b = eager_tokens[row].item(), actual_tokens[row].item()
                candidates = sorted(set([a, b] + logits32[local].topk(3).indices.cpu().tolist()))
                records.append({
                    'batch_row': row, 'eager_token': a, 'compiled_token': b,
                    'fp32_token': logits32[local].argmax().item(),
                    'eager_top2_gap': (eager[row].topk(2).values.float().diff().abs()).item(),
                    'compiled_top2_gap': (actual[row].topk(2).values.float().diff().abs()).item(),
                    'row_max_absolute_logit_error': (actual[row].float()-eager[row].float()).abs().max().item(),
                    'candidate_logits': [
                        {'token': token, 'eager_fp16': eager[row, token].item(),
                         'compiled_fp16': actual[row, token].item(),
                         'uncached_fp32': logits32[local, token].item()}
                        for token in candidates],
                })
    result = {
        'status': 'diagnostic_only', 'time_utc': datetime.now(timezone.utc).isoformat(),
        'batch': args.batch, 'context': args.context, 'seed': 20260916,
        'gpu': identity, 'cuda_visible_devices': os.environ.get('CUDA_VISIBLE_DEVICES'),
        'source_sha256': {name: hashlib.sha256(Path(name).read_bytes()).hexdigest()
                          for name in ('benchmark.py', 'model_snapshot.py', 'inspect_compiled_rounding.py')},
        'compiled_vs_eager': comparison, 'original_logit_tolerance_passed': True,
        'greedy_mismatch_count': mismatch.numel(),
        'mismatching_rows_fp32_comparison': fp32_comparison, 'mismatching_rows': records,
        'scope': 'Numerical diagnosis only; original strict-greedy benchmark failures remain failures.',
    }
    with args.output.open('x') as handle:
        json.dump(result, handle, indent=2)
        handle.write('\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
