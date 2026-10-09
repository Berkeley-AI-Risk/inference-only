# Reproducing the H100 reference

This optional benchmark runs the pinned **original FP16 SimpleStories-V2-5M
checkpoint** on one H100 SXM 80 GB. It does not operate the FPGA or change its
model. Read [the measurement report](../../H100-BENCHMARK.md) before interpreting
its results, particularly the distinction between aggregate capacity, one-user
latency and the FPGA's different numerical rules.

## Isolated setup

Use a full H100 SXM with MIG disabled. The benchmark guards for exactly one
visible GPU, the H100 name and 132 SMs; inspect `nvidia-smi` too. The timing
records identify Linux, Python 3.10.12 and driver 580.105.08. Original setup
notes identify Ubuntu 22.04, but the OS release was not recorded per case.
CPU-only checks were also exercised on Python 3.12. Other GPU types must not
silently substitute for this SXM reference.

Keep environments, model downloads and new results **outside the clean release**.
From the repository root, with a fresh sibling directory:

```sh
mkdir ../h100-work
cp benchmarks/h100/*.py benchmarks/h100/requirements.txt ../h100-work/
cd ../h100-work
python3.10 -m venv .venv
.venv/bin/python -m pip install torch==2.10.0 --index-url https://download.pytorch.org/whl/cu126
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python -m pip check
.venv/bin/python -B model_snapshot.py .model
.venv/bin/python -B test_benchmark.py --model-dir .model -v
nvidia-smi
```

The downloader fetches six public files from the pinned revision and checks
their sizes and hashes. Workers recheck them before loading safetensors with
network access and remote model code disabled. The model's upstream MIT
declaration is included in the release notices. GPU libraries are installed
separately; no vendor binaries or cloud credentials are bundled.

## Run measurements

A dry run needs only Python's standard library and starts no GPU job:

```sh
python3 -B benchmark.py --plan
```

Start with the short, strict-greedy acceptance sweep:

```sh
CUDA_VISIBLE_DEVICES=0 .venv/bin/python -B benchmark.py \
  --batches 1,64 --modes eager,graph --trials 3 --seconds 0.3 \
  --max-runtime 300 --output-dir results/acceptance
```

The original full sweep, also strict, uses the default batches and modes:

```sh
CUDA_VISIBLE_DEVICES=0 TORCHINDUCTOR_COMPILE_THREADS=4 \
  .venv/bin/python -B benchmark.py --output-dir results/strict-sweep
```

The measured default capacity reference was a separate FP16 run allowing
reported near-tie greedy differences, **not exact token equivalence**:

```sh
CUDA_VISIBLE_DEVICES=0 TORCHINDUCTOR_COMPILE_THREADS=4 \
  .venv/bin/python -B benchmark.py \
  --batches 1,32768 --modes compile-graph --allow-greedy-rounding \
  --seed 20260918 --generation-tokens 0 --seconds 3 --trials 5 \
  --max-runtime 300 --output-dir results/fp16-reference-repeat
```

Use a new output directory each time. Per-case logs, JSON, package identities,
source hashes and every timing repetition are saved. Workers run in separate
processes; timeout limits stop worker groups, not cloud billing. The default
individual-case budget is 15 minutes and total worker budget 30 minutes;
compilation speed can vary. Do not run competing GPU jobs during measurements.

The changed-input checks are separate from timing:

```sh
CUDA_VISIBLE_DEVICES=0 TORCHINDUCTOR_COMPILE_THREADS=4 \
  .venv/bin/python -B check_gpu_replay.py --mode graph --output replay-graph.json
CUDA_VISIBLE_DEVICES=0 TORCHINDUCTOR_COMPILE_THREADS=4 \
  .venv/bin/python -B check_gpu_replay.py --mode compile-graph --output replay-compile-graph.json
CUDA_VISIBLE_DEVICES=0 TORCHINDUCTOR_COMPILE_THREADS=4 \
  .venv/bin/python -B inspect_compiled_rounding.py --output compiled-rounding.json
```

Never select a deliberately slow eager or single-sequence rate as if it were
the GPU's aggregate inference capacity. Nor should a numerical failure be
silently treated as a successful exact-equivalence check. Preserve failed
cases and state any changes to the acceptance rule.

**Cloud users:** these scripts do not provision, shut down or terminate an
instance. Copy and verify your results, then terminate the instance through
your provider to stop instance billing.

## Recorded source versions

The scripts here match the recorded FP16-reference run. `source-versions/strict/`
preserves the original stricter version; `source-versions/fp16-reference/`
preserves the final measured version. Their historical preparation/readme
text is retained verbatim as `README.txt` for source-hash reproducibility,
not as current instructions. The saved sweep summaries identify their source
versions. Use [the offline evidence check](../../tools/check_h100_reference.py)
to verify those associations without installing any GPU packages.
