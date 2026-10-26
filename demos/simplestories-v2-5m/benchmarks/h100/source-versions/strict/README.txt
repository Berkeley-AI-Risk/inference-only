# SimpleStories H100 reference benchmark

A standalone benchmark for the original **SimpleStories-V2-5M** checkpoint,
pinned to `c4b3a4bb81297f5316697098e1d4b65c1249daf8` (5,354,496 parameters).
This directory is separate from the frozen FPGA public-release package.
It does not operate the FPGA, provision cloud resources, or publish anything.

Preparation status (2026-09-16): **13 local tests and six CPU smoke cases
passed**, including the real pinned checkpoint, FP32/FP16 paths, actual greedy
generation, and Dynamo whole-graph tracing with the eager backend. Dependency
consistency also passed. **No H100 run, CUDA code generation test or CUDA graph
replay has been performed yet.** Ready for the short H100 acceptance run below.

**This is floating-point GPU inference, not a bit-exact implementation of the
FPGA's W10/A16/KV16 arithmetic.** Results are an explicitly labeled reference
baseline, not a measured speed for the exact quantized machine and not, by
themselves, a certified hobbling factor.

## What is measured

1. **Fixed-context cached decoding**, initially at 128 input positions: cache
   the first 127 positions, then time evaluating the final input and choosing
   the next token by argmax. Repeat this full decode step on the same tapes.
   Batch sizes 1, 16, 64, 256 and 1,024 distinguish individual latency from
   aggregate throughput. Each batch row has its own deterministic synthetic
   token tape and its own K/V storage, with no prefix sharing or padding.
2. **Actual greedy story generation**, as a separate batch-one eager baseline:
   natural-language prompt, growing K/V cache, 64 generated tokens, first-token
   latency and subsequent generation throughput. EOS does not end the timed
   run early. This is not the optimized fixed-context rating.

The fixed-context test is a microbenchmark, **not a stream of different
autoregressively generated tokens**. Nor is it a teacher-forced prompt pass
whose input tokens are mislabeled as generated output. Every measured step
executes all six layers, the output head and greedy token selection. Prefix
construction, model loading, compilation, warmup, network transfer and text
decoding are outside its timing. GPU-to-host token transfer is also excluded;
both host-wall timing (including launch/synchronization) and CUDA event spans
are recorded. The primary reported rate uses median host-wall duration.

Three execution modes are compared:

- `eager`: ordinary PyTorch calls, including Python dispatch overhead.
- `graph`: CUDA graph replay to reduce dispatch overhead.
- `compile-graph`: whole-graph `torch.compile`, with compiler-owned CUDA graphs
  disabled, followed by explicit CUDA graph capture/replay.

There is no automatic fallback disguised as a successful optimized run.
Compilation/capture/numerical failures get their own failed result and log.
The measured best result is an **achieved rate, not a proved H100 maximum**.
If throughput is still improving at the largest batch, extend the sweep before
using it as the reference for the paper. Do not use the deliberately slower
single-stream/eager number in place of an aggregate-capacity comparison.

## Lambda instance and setup

Use **one full H100 SXM 80 GB**, with **Lambda Stack 24.04** (Python 3.12).
The default GPU guard checks the H100 name and 132 streaming multiprocessors;
inspect the recorded `nvidia-smi` information as well to confirm model, memory,
MIG status, clocks and power limit. `--allow-other-gpu` is for explicitly
labeled exploratory runs only, never silent substitution of a different GPU.

Copy only the files in this directory, excluding `.venv`, `.model`, caches and
results. Do not upload the entire private repository or an SSH private key.
The checkpoint is public and can be fetched directly on the instance.

In this directory on the instance:

```sh
python3 -m venv .venv
.venv/bin/python -m pip install torch==2.10.0 --index-url https://download.pytorch.org/whl/cu126
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python -B model_snapshot.py .model
.venv/bin/python -B test_benchmark.py --model-dir .model -v
nvidia-smi
```

The dedicated environment does not alter the system Lambda Stack installation.
The six model files are size- and SHA-256-checked against the same manifest as
the FPGA project, on download **and again before each benchmark worker**.
Only safetensors weights and built-in Transformers model/tokenizer code are
loaded, with networking and remote model code disabled during benchmark runs.

Check the plan without a GPU, model or third-party Python packages:

```sh
python3 -B benchmark.py --plan
```

Run a short real-GPU acceptance test first:

```sh
CUDA_VISIBLE_DEVICES=0 .venv/bin/python -B benchmark.py \
  --batches 1,64 --modes eager,graph --trials 3 --seconds 0.3 \
  --max-runtime 300 --output-dir results/h100-acceptance
```

Then run the optimized sweep:

```sh
CUDA_VISIBLE_DEVICES=0 .venv/bin/python -B benchmark.py \
  --output-dir results/h100-context128
```

Use a new output-directory name for each invocation. The script refuses to
overwrite an existing result directory. Each case runs in a fresh process to
isolate compilation, cache specialization and GPU memory. Defaults limit each
worker to 15 minutes and the whole worker sweep to 30 minutes; compiler child
processes are terminated as a group on timeout. These are experiment controls,
not a promise that every optimized case will finish within the budget.

**The script does not shut down or terminate the rented instance.** Copy the
results back, then terminate it in Lambda's console to stop instance billing.
Do not leave it running after the benchmark finishes.

## Correctness and evidence

The tests exercise token accounting, argument validation, pinned-file
verification, cached-versus-full inference, prefix-cache stability, changing
inputs, greedy generation, and whole-graph tracing. A local CPU run cannot
validate CUDA code generation, CUDA graph capture or actual H100 performance.

Each GPU worker additionally checks cached versus uncached inference on up to
two sampled rows, compares its dtype with FP32, and checks optimized outputs
against same-precision eager outputs across the full batch. Optimized greedy
predictions must agree; if rounding changes a winning token, the case fails
for investigation instead of silently accepting it. Cross-dtype argmax
differences are recorded, not claimed to match the FPGA or FP32 exactly.

`summary.json` accumulates successes and failures. Per-case JSON contains:

- Model and source identity, exact package versions and GPU identity;
- Context, batch, precision, timing exclusions and execution mode;
- Every timing repetition, aggregate and per-sequence rates;
- Numerical checks, output digest, and the separate generation sample.

The controller stores SHA-256 hashes of its local source/document files in
the summary. Keep the JSON **and logs**, including failed cases. Before using
the results, repeat the best configuration, inspect dtype differences and
GPU utilization, and consider further batch/kernel tuning. Fixed-model GPU
optimization is allowed; comparing the FPGA against a needlessly slow CPU
oracle or Python loop would not establish an H100 reference rating.

Additional contexts or batch sizes can be requested, for example:

```sh
CUDA_VISIBLE_DEVICES=0 .venv/bin/python -B benchmark.py \
  --contexts 128,512 --batches 256,1024,4096 --modes graph,compile-graph \
  --generation-tokens 0 --output-dir results/h100-extended
```

Contexts above 513 occupied FPGA slots are not yet physically qualified on
the FPGA. The GPU's context limit is checked against the original model's
2,048-position configuration. Longer-context GPU results do not qualify the
FPGA or justify extrapolating its measured speed.

## Primary technical references

- [Pinned model](https://huggingface.co/SimpleStories/SimpleStories-V2-5M/tree/c4b3a4bb81297f5316697098e1d4b65c1249daf8)
- [Lambda images](https://docs.lambda.ai/public-cloud/on-demand/)
- [PyTorch installation commands](https://pytorch.org/get-started/previous-versions/)
- [CUDA graph semantics and timing](https://docs.pytorch.org/docs/2.8/notes/cuda.html)
- [Compilation modes](https://docs.pytorch.org/docs/2.8/generated/torch.compile.html)
- [Llama implementation interface](https://huggingface.co/docs/transformers/v4.48.2/en/model_doc/llama)
