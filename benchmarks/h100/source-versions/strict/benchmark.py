"""Pinned SimpleStories GPU benchmark; results are not FPGA-bit-exact results.

Each batch/context/mode runs in a fresh process. The main comparison repeatedly
evaluates one real decode step at a fixed context, including the greedy argmax.
It does NOT count a parallel teacher-forced prompt pass as generated tokens.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.metadata
import json
import math
import os
from pathlib import Path
import platform
import signal
import statistics
import subprocess
import sys
import time

from model_snapshot import REPOSITORY, REVISION, verify

HERE = Path(__file__).resolve().parent


def positive_int(text):
    value = int(text)
    if value <= 0:
        raise argparse.ArgumentTypeError("must be positive")
    return value


def number_list(text):
    try:
        values = [positive_int(item) for item in text.split(",")]
    except (ValueError, argparse.ArgumentTypeError) as error:
        raise argparse.ArgumentTypeError("use comma-separated positive integers") from error
    if len(set(values)) != len(values):
        raise argparse.ArgumentTypeError("duplicate values are not allowed")
    return values


def summarize_samples(samples, batch, iterations):
    wall = [sample["wall_seconds"] for sample in samples]
    if not wall or any(not math.isfinite(t) or t <= 0 for t in wall):
        raise ValueError("timing samples must be finite and positive")
    count = batch * iterations
    median = statistics.median(wall)
    return {
        "aggregate_tokens_per_second": count / median,
        "tokens_per_second_per_sequence": iterations / median,
        "milliseconds_per_decode_step": 1000 * median / iterations,
        "aggregate_tps_min": count / max(wall),
        "aggregate_tps_max": count / min(wall),
        "tokens_counted_per_trial": count,
        "samples": samples,
    }


def run_bounded(command, environment, log, timeout):
    """Stop the entire worker/compilation process group on timeout or Ctrl-C."""
    process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT,
                               env=environment, start_new_session=True)
    try:
        return process.wait(timeout=timeout)
    except BaseException:
        try:
            os.killpg(process.pid, signal.SIGTERM)
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        except ProcessLookupError:
            pass
        raise


def load_stack():
    # --help, --plan and controller argument checking need only the stdlib.
    import torch
    from transformers import AutoTokenizer, LlamaForCausalLM, StaticCache
    return torch, AutoTokenizer, LlamaForCausalLM, StaticCache


def load_model(directory, dtype, device):
    torch, _, LlamaForCausalLM, _ = load_stack()
    model = LlamaForCausalLM.from_pretrained(
        str(directory), local_files_only=True, trust_remote_code=False,
        use_safetensors=True, torch_dtype=getattr(torch, dtype),
        attn_implementation="sdpa",
    ).eval().to(device)
    if sum(parameter.numel() for parameter in model.parameters()) != 5_354_496:
        raise ValueError("wrong model parameter count")
    model.requires_grad_(False)
    return model


def make_inputs(batch, context, seed, device):
    torch, _, _, _ = load_stack()
    generator = torch.Generator(device="cpu").manual_seed(seed)
    # Distinct, deterministic synthetic token tapes; no padding or shared KV.
    # EOS IDs are data here, not a reason to terminate a benchmark early.
    return torch.randint(0, 4019, (batch, context), generator=generator).to(device)


class FixedDecode:
    """Static KV cache with exactly context-1 precomputed positions.

    Every invocation overwrites only the final position and computes its logits.
    The prefix stays fixed: this is a fixed-context microbenchmark, not a story.
    """

    def __init__(self, model, input_ids):
        torch, _, _, StaticCache = load_stack()
        self.model = model
        self.batch, self.context = input_ids.shape
        device = input_ids.device
        self.input_ids = input_ids[:, -1:].contiguous()
        self.position = torch.tensor([self.context - 1], device=device)
        self.position_ids = self.position.view(1, 1)
        self.mask = torch.ones((self.batch, self.context), dtype=torch.long, device=device)
        self.cache = StaticCache(
            config=model.config, max_batch_size=self.batch,
            max_cache_len=self.context, device=device, dtype=model.dtype,
        )
        if self.context > 1:
            positions = torch.arange(self.context - 1, device=device)
            model(
                input_ids=input_ids[:, :-1], attention_mask=self.mask[:, :-1],
                position_ids=positions.unsqueeze(0), cache_position=positions,
                past_key_values=self.cache, use_cache=True, num_logits_to_keep=1,
            )

    def __call__(self):
        logits = self.model(
            input_ids=self.input_ids, attention_mask=self.mask,
            position_ids=self.position_ids, cache_position=self.position,
            past_key_values=self.cache, use_cache=True, num_logits_to_keep=1,
        ).logits[:, -1, :]
        return logits, logits.argmax(dim=-1)


def logits_comparison(actual, expected):
    torch, _, _, _ = load_stack()
    actual, expected = actual.float(), expected.float()
    if not torch.isfinite(actual).all() or not torch.isfinite(expected).all():
        raise ValueError("nonfinite model output")
    delta = actual - expected
    return {
        "max_absolute_logit_error": delta.abs().max().item(),
        "rms_logit_error": delta.square().mean().sqrt().item(),
        "argmax_agreement_fraction": (actual.argmax(-1) == expected.argmax(-1)).float().mean().item(),
    }


def check_cached_against_full(model, input_ids):
    torch, _, _, _ = load_stack()
    cached, _ = FixedDecode(model, input_ids)()
    full = model(input_ids=input_ids, use_cache=False, num_logits_to_keep=1).logits[:, -1, :]
    result = logits_comparison(cached, full)
    # Different matrix shapes can produce small floating-point differences.
    tolerance = 0.002 if model.dtype == torch.float32 else 0.15
    torch.testing.assert_close(cached, full, rtol=0.01, atol=tolerance)
    return result


def prepare_runner(step, mode):
    torch, _, _, _ = load_stack()
    expected_logits, expected_tokens = step()
    expected_logits, expected_tokens = expected_logits.clone(), expected_tokens.clone()
    if mode == "eager":
        return step, {"mode": mode, "comparison": logits_comparison(expected_logits, expected_logits)}
    function = step
    if mode == "compile-graph":
        # External CUDA graph below owns capture; do not nest compiler graphs.
        function = torch.compile(
            step, fullgraph=True, dynamic=False, mode="max-autotune-no-cudagraphs",
        )
    stream = torch.cuda.Stream()
    stream.wait_stream(torch.cuda.current_stream())
    with torch.cuda.stream(stream):
        for _ in range(5):
            function()
    torch.cuda.current_stream().wait_stream(stream)
    torch.cuda.synchronize()
    graph = torch.cuda.CUDAGraph()
    with torch.cuda.graph(graph):
        static_logits, static_tokens = function()
    graph.replay()
    torch.cuda.synchronize()
    comparison = logits_comparison(static_logits, expected_logits)
    torch.testing.assert_close(static_logits, expected_logits, rtol=0.005, atol=0.05)
    if not torch.equal(static_tokens, expected_tokens):
        raise ValueError("optimized runner changed greedy predictions; investigate before reporting")

    def replay():
        graph.replay()
        return static_logits, static_tokens

    return replay, {"mode": mode, "comparison": comparison}


def time_calls(function, iterations, device):
    torch, _, _, _ = load_stack()
    if device == "cuda":
        torch.cuda.synchronize()
        start, end = torch.cuda.Event(enable_timing=True), torch.cuda.Event(enable_timing=True)
        start.record()
    wall_start = time.perf_counter()
    for _ in range(iterations):
        output = function()
    if device == "cuda":
        end.record()
        end.synchronize()
    elapsed = time.perf_counter() - wall_start
    # The event span can include host-launch gaps; it is not pure kernel busy time.
    return {"wall_seconds": elapsed, "cuda_event_seconds": start.elapsed_time(end) / 1000 if device == "cuda" else None}


def gpu_identity(torch):
    props = torch.cuda.get_device_properties(0)
    command = ["nvidia-smi", "--query-gpu=name,driver_version,memory.total,power.limit,clocks.current.sm,clocks.current.memory,mig.mode.current", "--format=csv"]
    try:
        smi = subprocess.run(command, capture_output=True, text=True, timeout=15)
        smi_text = smi.stdout.strip() if smi.returncode == 0 else smi.stderr.strip()
    except (OSError, subprocess.TimeoutExpired) as error:
        smi_text = str(error)
    return {"name": props.name, "total_memory_bytes": props.total_memory,
            "compute_capability": [props.major, props.minor],
            "multiprocessor_count": props.multi_processor_count, "nvidia_smi": smi_text}


def actual_generation(model, directory, device, new_tokens, trials):
    """True batch-one autoregressive continuation, with host launches included.

    This deliberately separate eager baseline has a growing context. Its rate
    must not be substituted for the optimized fixed-context aggregate rate.
    """
    torch, AutoTokenizer, _, _ = load_stack()
    tokenizer = AutoTokenizer.from_pretrained(str(directory), local_files_only=True, trust_remote_code=False)
    prompt = "Once upon a time, there was a little girl who found a"
    ids = tokenizer(prompt, return_tensors="pt", add_special_tokens=False).input_ids.to(device)

    def run():
        if device == "cuda":
            torch.cuda.synchronize()
        started = time.perf_counter()
        result = model(input_ids=ids, use_cache=True, num_logits_to_keep=1)
        token = result.logits[:, -1, :].argmax(-1, keepdim=True)
        if device == "cuda":
            torch.cuda.synchronize()
        first_seconds = time.perf_counter() - started
        decode_start = time.perf_counter()
        outputs = [token]
        cache = result.past_key_values
        for _ in range(new_tokens - 1):
            result = model(input_ids=token, past_key_values=cache, use_cache=True, num_logits_to_keep=1)
            token = result.logits[:, -1, :].argmax(-1, keepdim=True)
            cache = result.past_key_values
            outputs.append(token)
        if device == "cuda":
            torch.cuda.synchronize()
        decode_seconds = time.perf_counter() - decode_start
        generated = torch.cat(outputs, dim=1)[0].cpu().tolist()
        return {"first_token_seconds": first_seconds, "subsequent_decode_seconds": decode_seconds,
                "subsequent_tokens_per_second": (new_tokens - 1) / decode_seconds,
                "total_tokens_per_second_including_prefill": new_tokens / (first_seconds + decode_seconds),
                "token_ids": generated}

    run()  # warmup excluded
    records = [run() for _ in range(trials)]
    if any(record["token_ids"] != records[0]["token_ids"] for record in records):
        raise ValueError("greedy generation differed between repetitions")
    return {"label": "eager_batch_one_growing_context_not_peak_rating", "prompt": prompt,
            "prompt_tokens": ids.shape[1], "new_tokens": new_tokens, "stop_at_eos": False,
            "host_token_transfer_and_text_decoding_in_timing": False,
            "generated_text": tokenizer.decode(records[0]["token_ids"]), "trials": records}


def worker(args):
    hashes = verify(args.model_dir)
    torch, _, _, _ = load_stack()
    torch.set_num_threads(min(8, os.cpu_count() or 1))
    torch.set_grad_enabled(False)
    torch.manual_seed(args.seed)
    torch.backends.cuda.matmul.allow_tf32 = False
    torch.backends.cudnn.allow_tf32 = False
    torch.backends.cuda.matmul.allow_fp16_reduced_precision_reduction = False
    torch.backends.cuda.matmul.allow_bf16_reduced_precision_reduction = False
    identity = None
    if args.device == "cuda":
        if not torch.cuda.is_available():
            raise RuntimeError("CUDA GPU unavailable; CPU timing cannot substitute for H100 timing")
        if torch.cuda.device_count() != 1:
            raise RuntimeError("expose exactly one GPU with CUDA_VISIBLE_DEVICES")
        identity = gpu_identity(torch)
        if not args.allow_other_gpu and ("H100" not in identity["name"] or identity["multiprocessor_count"] != 132):
            raise RuntimeError("expected a full H100 SXM (132 SMs), not PCIe/H200/MIG; inspect GPU identity")
    elif args.mode != "eager":
        raise ValueError("CPU smoke tests only support eager mode")
    with torch.inference_mode():
        model = load_model(args.model_dir, args.dtype, args.device)
        inputs = make_inputs(args.batch, args.context, args.seed, args.device)
        validation_inputs = inputs[:min(args.batch, 2)]
        cached_check = check_cached_against_full(model, validation_inputs)
        fp32_model = load_model(args.model_dir, "float32", args.device)
        fp32_logits = fp32_model(input_ids=validation_inputs, use_cache=False, num_logits_to_keep=1).logits[:, -1, :]
        candidate_logits = model(input_ids=validation_inputs, use_cache=False, num_logits_to_keep=1).logits[:, -1, :]
        precision_check = logits_comparison(candidate_logits, fp32_logits)
        del fp32_model, fp32_logits, candidate_logits
        step = FixedDecode(model, inputs)
        runner, optimization_check = prepare_runner(step, args.mode)
        for _ in range(args.warmup):
            runner()
        calibration = time_calls(runner, 10, args.device)
        iterations = max(10, min(20000, math.ceil(args.seconds * 10 / calibration["wall_seconds"])))
        samples = [time_calls(runner, iterations, args.device) for _ in range(args.trials)]
        final_logits, final_tokens = runner()
        if not torch.isfinite(final_logits).all():
            raise ValueError("nonfinite timed result")
        token_digest = hashlib.sha256(final_tokens.cpu().numpy().tobytes()).hexdigest()
        generation = actual_generation(model, args.model_dir, args.device, args.generation_tokens, args.trials) if args.generation_tokens else None
    packages = {name: importlib.metadata.version(name) for name in ("torch", "transformers", "tokenizers", "safetensors", "numpy")}
    return {
        "status": "pass", "schema_version": 1, "time_utc": datetime.now(timezone.utc).isoformat(),
        "model": {"repository": REPOSITORY, "revision": REVISION, "file_sha256": hashes,
                  "dtype": args.dtype, "fpga_bit_exact": False, "parameters": 5_354_496},
        "environment": {"python": platform.python_version(), "system": platform.system(),
                        "packages": packages, "cuda_runtime": torch.version.cuda, "gpu": identity,
                        "all_python_packages": {dist.metadata["Name"]: dist.version for dist in importlib.metadata.distributions()},
                        "torch_num_threads": torch.get_num_threads(), "tf32": False,
                        "reduced_precision_gemm_reduction": False},
        "workload": {"kind": "fixed_context_cached_decode", "batch": args.batch,
                     "context_including_current_input": args.context, "cached_prefix_positions": args.context - 1,
                     "seed": args.seed, "input_distribution": "independent_uniform_token_ids",
                     "iterations_per_trial": iterations, "mode": args.mode,
                     "includes_argmax": True, "includes_host_launch_and_sync": True,
                     "includes_prefill": False, "includes_host_token_transfer": False,
                     "repeated_fixed_tapes_not_autoregressive_stream": True},
        "checks": {"cached_vs_full": cached_check, "dtype_vs_fp32": precision_check,
                   "optimized_vs_eager": optimization_check, "final_token_sha256": token_digest},
        "timing": summarize_samples(samples, args.batch, iterations),
        "actual_generation": generation,
        "limitations": ["An achieved implementation rate, not a proved hardware peak.",
                        "Original floating-point checkpoint, not the FPGA W10/A16/KV16 model.",
                        "CPU runs are correctness smoke tests, not H100 measurements."],
    }


def build_plan(args):
    modes = args.modes.split(",")
    if not modes or len(set(modes)) != len(modes) or any(mode not in ("eager", "graph", "compile-graph") for mode in modes):
        raise ValueError("modes must be distinct choices from eager,graph,compile-graph")
    return [{"context": context, "batch": batch, "mode": mode}
            for context in args.contexts for batch in args.batches for mode in modes]


def controller(args):
    plan = build_plan(args)
    if args.plan:
        print(json.dumps({"model": REPOSITORY, "revision": REVISION, "cases": plan,
                          "case_timeout_seconds": args.case_timeout,
                          "overall_worker_budget_seconds": args.max_runtime,
                          "note": "No downloads or GPU jobs started."}, indent=2))
        return 0
    verify(args.model_dir)
    args.output_dir.mkdir(parents=True, exist_ok=False)
    sources = {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
               for path in sorted(HERE.iterdir()) if path.is_file() and path.suffix in (".py", ".txt", ".md")}
    summary = {"schema_version": 1, "status": "running", "source_sha256": sources,
               "model_revision": REVISION, "device": args.device, "cases": []}
    summary_path = args.output_dir / "summary.json"
    summary_path.write_text(json.dumps(summary, indent=2) + "\n")
    deadline = time.monotonic() + args.max_runtime
    for case in plan:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            summary["cases"].append({**case, "status": "not_run", "error": "overall worker time budget exhausted"})
            continue
        name = f"ctx{case['context']}-batch{case['batch']}-{args.dtype}-{case['mode']}"
        target = args.output_dir / (name + ".json")
        command = [sys.executable, "-B", str(HERE / "benchmark.py"), "--worker",
                   "--model-dir", str(args.model_dir.resolve()), "--output", str(target.resolve()),
                   "--device", args.device, "--dtype", args.dtype,
                   "--context", str(case["context"]), "--batch", str(case["batch"]), "--mode", case["mode"],
                   "--trials", str(args.trials), "--seconds", str(args.seconds),
                   "--warmup", str(args.warmup), "--seed", str(args.seed)]
        if args.allow_other_gpu:
            command.append("--allow-other-gpu")
        if case == plan[0] and args.generation_tokens:
            command += ["--generation-tokens", str(args.generation_tokens)]
        else:
            command += ["--generation-tokens", "0"]
        environment = os.environ.copy()
        environment.setdefault("TOKENIZERS_PARALLELISM", "false")
        environment.setdefault("TORCHINDUCTOR_COMPILE_THREADS", "4")
        environment.setdefault("HF_HUB_OFFLINE", "1")
        environment.setdefault("TRANSFORMERS_OFFLINE", "1")
        print(f"Starting {name}", flush=True)
        try:
            with (args.output_dir / (name + ".log")).open("x") as log:
                returncode = run_bounded(command, environment, log, min(args.case_timeout, remaining))
            if returncode:
                raise RuntimeError(f"worker exit {returncode}; see {name}.log")
            result = json.loads(target.read_text())
            summary["cases"].append({**case, "status": "pass", "result": target.name, "timing": result["timing"]})
            print(f"  {result['timing']['aggregate_tokens_per_second']:,.1f} aggregate tokens/s", flush=True)
        except (subprocess.TimeoutExpired, RuntimeError, OSError, ValueError) as error:
            summary["cases"].append({**case, "status": "failed", "error": str(error)})
            print(f"  FAILED: {error}", flush=True)
        summary_path.write_text(json.dumps(summary, indent=2) + "\n")
    summary["status"] = "pass" if all(case["status"] == "pass" for case in summary["cases"]) else "partial_or_failed"
    summary_path.write_text(json.dumps(summary, indent=2) + "\n")
    return 0 if summary["status"] == "pass" else 1


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-dir", type=Path, default=HERE / ".model")
    parser.add_argument("--output-dir", type=Path, default=HERE / "results" / datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ"))
    parser.add_argument("--contexts", type=number_list, default=[128])
    parser.add_argument("--batches", type=number_list, default=[1, 16, 64, 256, 1024])
    parser.add_argument("--modes", default="eager,graph,compile-graph")
    parser.add_argument("--dtype", choices=("float16", "bfloat16", "float32"), default="float16")
    parser.add_argument("--device", choices=("cuda", "cpu"), default="cuda")
    parser.add_argument("--trials", type=positive_int, default=5)
    parser.add_argument("--seconds", type=float, default=1.0, help="target seconds per timing trial")
    parser.add_argument("--warmup", type=positive_int, default=20)
    parser.add_argument("--case-timeout", type=positive_int, default=900)
    parser.add_argument("--max-runtime", type=positive_int, default=1800, help="overall worker time budget; does NOT terminate the cloud instance")
    parser.add_argument("--seed", type=int, default=20260916)
    parser.add_argument("--generation-tokens", type=int, default=64)
    parser.add_argument("--allow-other-gpu", action="store_true", help="label an exploratory non-H100-SXM run; never substitute its rate")
    parser.add_argument("--plan", action="store_true", help="stdlib-only dry run; no model or GPU needed")
    parser.add_argument("--worker", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--output", type=Path, help=argparse.SUPPRESS)
    parser.add_argument("--context", type=positive_int, default=128, help=argparse.SUPPRESS)
    parser.add_argument("--batch", type=positive_int, default=1, help=argparse.SUPPRESS)
    parser.add_argument("--mode", choices=("eager", "graph", "compile-graph"), default="eager", help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    if not math.isfinite(args.seconds) or not 0 < args.seconds <= 60:
        parser.error("--seconds must be finite and in (0, 60]")
    if max(args.contexts + [args.context]) > 2048:
        parser.error("context must not exceed the model's 2048 positions")
    if args.generation_tokens != 0 and not 2 <= args.generation_tokens <= 512:
        parser.error("--generation-tokens must be 0 or between 2 and 512")
    if args.worker and args.output is None:
        parser.error("worker requires --output")
    return args


def main():
    args = parse_args()
    if args.worker:
        if args.output.exists():
            raise FileExistsError(args.output)
        result = worker(args)
        with args.output.open("x") as handle:
            json.dump(result, handle, indent=2)
            handle.write("\n")
        return 0
    return controller(args)


if __name__ == "__main__":
    raise SystemExit(main())
