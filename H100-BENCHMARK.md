# Single-H100 reference inference benchmark

On one **H100 SXM 80 GB**, the original SimpleStories-V2-5M FP16 checkpoint
achieved approximately **1.02 million cached-decode token evaluations/s in
aggregate at 128 input positions**. A different-prompt repeat reproduced the
result within 0.02%. The batch-one compiled microbenchmark measured about
6,500 evaluations/s. These are different capacity/latency measurements, not
a claim that one chat produces a million tokens each second.

This reference informs the [conditional residual training factor analysis](TRAINING-CAPACITY.md).
It is **not bit-exact FPGA W10/A16/KV16 inference**, an end-to-end chat-service
benchmark, or a certified peak H100 rating. The September 16 GPU experiment
itself changed neither the FPGA nor the host app. Later FPGA and host speed
updates are documented separately in [VALIDATION.md](VALIDATION.md).

## Results

Measured September 16, 2026 Pacific (September 17 UTC), on GPU 0 of a rented
two-H100 instance. `CUDA_VISIBLE_DEVICES=0` exposed only one GPU; the benchmark
also rejected any run with more than one visible device. GPU 1 was not used.

The raw `nvidia-smi` inventory lists both GPUs installed in the server;
it does not describe CUDA visibility for the benchmark process. The
[runner](benchmarks/h100/benchmark.py) checks that `torch.cuda.device_count()`
is exactly one. The separate [replay record](evidence/h100/correctness/replay-compile-graph.json)
also records `cuda_visible_devices = "0"`.

| Implementation | Independent sequences | Aggregate evaluations/s | Acceptance |
| --- | ---: | ---: | --- |
| Compiled CUDA graph | 1 | 6,460 | Strict greedy agreement |
| Compiled CUDA graph, new-prompt repeat | 1 | 6,513 | FP16 reference; no disagreement in this case |
| Uncompiled CUDA graph | 32,768 | 609,285 | Strict greedy agreement |
| Compiled CUDA graph | 8,192 | 996,875 | FP16 reference |
| Compiled CUDA graph | 32,768 | 1,017,925 | FP16 reference |
| Compiled CUDA graph, new-prompt repeat | 32,768 | **1,018,048** | FP16 reference |

The [selected repeat](evidence/h100/h100-compiled-fp16-repeat/ctx128-batch32768-float16-compile-graph.json)
used five approximately three-second trials. Its median rate was
1,018,047.545/s, with trial rates between 1,018,035 and 1,018,145/s. At that
batch size, a step took 32.19 ms: about **31.1 evaluations/s per sequence**.
The [initial large-batch result](evidence/h100/h100-compiled-fp16-reference/ctx128-batch32768-float16-compile-graph.json)
was 1,017,924.918/s. The large-batch compiled rate improved by only about 2.1%
from batch 8,192 to 32,768; that suggests a plateau for this implementation,
not a limit on all possible GPU implementations.

The saved evidence contains **six sweeps, 28 passing cases and two preserved
strict-acceptance failures**. Eager, CUDA-graph and compiled CUDA-graph modes
were tested. A separate eager natural-language test generated a 64-token
story at roughly 350–365 tokens/s after its first token; that slower baseline
is not used as the reference capacity.

## What the timing counts

The model is pinned to revision `c4b3a4bb81297f5316697098e1d4b65c1249daf8`,
with 5,354,496 parameters. All six checkpoint/tokenizer files were verified
against fixed sizes and SHA-256 digests before workers ran. No remote model
code was loaded.

Each batch row has an independently generated 128-token tape and its own
K/V cache, with no prefix sharing or padding. The first 127 positions are
precomputed; every timed invocation evaluates the final input position,
overwrites that cache position, executes all six layers and the vocabulary
head, and performs greedy argmax. The prefix does not advance.

Thus this is **repeated fixed-context decoding**, not different
autoregressively generated tokens or teacher-forced input tokens relabeled
as generated output. Changed-input tests check that replay really uses the
token and prefix buffers rather than returning a fixed result.

Rates use median host-wall duration, including GPU launches and final
synchronization. CUDA event spans are also recorded. Model loading,
prefix construction, compilation, warmup, returning tokens to the host,
text decoding and network handling are outside the timing. These boundaries
do not exactly match the FPGA's host/serial-inclusive step measurement.

## Numerical acceptance

The original sweep required all logits to meet `rtol=0.005, atol=0.05`
relative to same-precision eager inference **and** every greedy token to
match. Compiled batches 256 and 1,024 passed the logit comparison but failed
the exact-token check. Their original failed results and worker records remain
in [the initial sweep](evidence/h100/h100-context128/summary.json).

The [rounding diagnostic](evidence/h100/correctness/compiled-rounding-batch1024.json)
found four different greedy tokens in batch 1,024, all near ties. Eager's
top-two gap was zero on three rows and 0.0078125 on the fourth. Compiled FP16
agreed with uncached FP32 on three of these rows; eager FP16 agreed on one.
This supports ordinary rounding as the explanation and shows why eager FP16
cannot simply be treated as an exact numerical oracle.

That diagnostic used seed `20260916`; the selected batch-32,768 repeat used
seed `20260918`. It does not individually diagnose the repeat's 54 disagreeing
rows. The saved diagnostic script reproduces the separate four-row case,
not a complete analysis of the selected reference run's disagreements.

The **separate FP16-reference sweep** retained the all-logit tolerances and
nonfinite-output rejection, but explicitly allowed and recorded greedy
rounding differences. At batch 32,768, the first run disagreed with eager on
64 rows (99.8047% agreement); the repeat disagreed on 54 rows (99.8352%).
The repeat's maximum absolute logit difference was 0.04296875 and RMS
difference 0.00362087. These checks do not prove identical story continuations
or exact FPGA-model equivalence.

No agreement statistic between this FP16 parent and the FPGA's W10/A16/KV16
integer model is included. The GPU implementation checks and the board's
integer-reference checks answer different questions; neither substitutes
for a cross-format comparison. A closer reference would benchmark the exact
integer model under matched timing boundaries, or quantify and justify an
explicit numerical-equivalence criterion.

The default benchmark policy remains strict. The alternative needs
`--allow-greedy-rounding`, and the JSON records that choice. The original
failures were not overwritten or reclassified. The capacity analysis uses
the faster, explicitly qualified FP16 result rather than selecting the
slower strict implementation for a smaller residual training factor estimate.

Additional batch-16 GPU checks in both modes passed: changed tokens and
changed prompts agreed with uncached inference within tolerance and in
greedy choice; both K and V prefixes remained unchanged during repeated
steps; restoring inputs reproduced the baseline exactly. Source snapshots
also include the initial 13-test and expanded 16-test CPU/model suites.
Their test-run transcripts are not included in this package; the saved GPU
replay records above are separate checks.

## Environment and reproducibility

The GPU was an H100 SXM 80 GB, 132 SMs, compute capability 9.0, 700 W power
limit, with MIG disabled. The timing records identify Linux/Python 3.10.12,
driver 580.105.08, PyTorch 2.10.0+cu126, Transformers 4.48.3, tokenizers
0.21.4, safetensors 0.7.0 and NumPy 1.26.4. TF32 and reduced-precision GEMM
reduction were disabled. Cases ran sequentially in fresh processes, and the
records report eight CPU execution threads.

The [original setup notes](benchmarks/h100/source-versions/fp16-reference/README.txt)
identify Ubuntu 22.04, but the timing records do not save the OS release.
The worker launcher defaults to four compilation threads unless an existing
environment setting overrides it; the effective setting was not recorded
per case. The reproduction commands explicitly request four threads.

Each successful timing JSON records `environment.all_python_packages`, an
installed-distribution version inventory, as well as the main package
versions and GPU identity. A separate literal `pip freeze` file is unnecessary
to inspect that inventory, though it is not an archive of every wheel or
system library. Per-case records do not include the OS release or the
`CUDA_VISIBLE_DEVICES` value; separate replay checks record GPU visibility,
and the runner enforces one visible H100. The `nvidia-smi` clock readings are
snapshots outside the timed window, not clock/power telemetry throughout it.
These are reproducibility limits, not evidence of measured utilization.

[Benchmark instructions and scripts](benchmarks/h100/README.md) are included.
Model weights and GPU software are obtained separately under their own terms;
they are unnecessary for inspecting the recorded data or running the FPGA.

[`evidence/h100/IMPORT.json`](evidence/h100/IMPORT.json) binds the published
files to their original identities. Measurement JSON is unchanged. Worker
logs are included as `.txt` with only machine-local benchmark-directory paths
replaced where present; both original and released digests are recorded.
Exact source versions, including the original strict implementation, are
retained. Credentials, cloud connection details and environment installations
are not included. Historical source README snapshots retain the cloud
provider's name as part of their unchanged, hash-identified source bytes.

Offline verification requires only Python 3.12:

```sh
python3.12 -I -S -B tools/check_h100_reference.py
python3.12 -I -S -B tools/estimate_training_capacity.py --check
```

## Performance headroom

An achieved rate is evidence that this workload can run at least that fast,
not proof of the hardware's absolute maximum. The
[capacity analysis](TRAINING-CAPACITY.md#gpu-performance-headroom-and-sensitivity)
derives an ideal minimum-K/V-traffic bandwidth roof of 8.52 million
evaluations/s, and a looser arithmetic-only roof of 86.08 million/s. Neither
is achieved performance or a prediction of a particular optimized kernel.

Useful-work and minimum-traffic ratios to peak specifications are not
profiled arithmetic/bandwidth utilization. The saved matrix-multiplication
autotune logs likewise do not constitute an end-to-end kernel profile.
Profiling cache expansion/copies and testing a grouped-query-aware fused
decode path would address a plausible inefficiency; no such speedup is
measured here. Further optimization, an exact-quantized-model implementation
and a standardized inference rating remain separate work.
