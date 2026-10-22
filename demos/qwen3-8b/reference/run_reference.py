"""Run the fixed 8B software oracle, not hardware inference or a GPU benchmark."""
import argparse
import json
from pathlib import Path
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))


def run(model, threads):
    import torch
    from prepare_model import check_image
    from dense_qwen_reference import DenseQwenEngine
    if not 1 <= threads <= 32:
        raise ValueError('Choose 1–32 CPU threads')
    check_image(model)
    torch.set_num_threads(threads)
    torch.set_float32_matmul_precision('highest')
    start = time.monotonic()
    engine = DenseQwenEngine(model, 'cpu')
    machine = engine.token_machine()
    expected = [11, 358, 2776]
    runs = []
    for _ in range(2):
        machine.clear()
        machine.append(9707)
        actual = [machine.step() for _ in expected]
        if actual != expected:
            raise ValueError('Portable software reference disagrees with hardware oracle')
        runs.append(actual)
    return dict(passed=True, prompt_tokens=[9707], expected_tokens=expected,
                clear_replay_outputs=runs, threads=threads,
                elapsed_software_seconds=time.monotonic()-start,
                scope='CPU reference and CLEAR/replay only; not an FPGA measurement.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model', type=Path, required=True, help='Verified exported model directory')
    parser.add_argument('--threads', type=int, default=8)
    parser.add_argument('--record', type=Path)
    args = parser.parse_args()
    result = run(args.model, args.threads)
    if args.record:
        with args.record.open('x') as stream:
            json.dump(result, stream, indent=2, sort_keys=True)
            stream.write('\n')
    print(json.dumps(result, indent=2, sort_keys=True))
