# H100 reference benchmark campaigns

This report describes single-H100 inference references for Qwen3-1.7B and SimpleStories-V2-5M. The shared benchmark uses Transformers 5.17.0 for both models. A SimpleStories benchmark using Transformers 4.48.3 has a different cache implementation and is reported separately.

- [October 25 shared-method campaign](#october-25-shared-method-campaign)
- [SimpleStories with Transformers 4.48.3](#historical-simplestories-campaign)

## October 25 shared-method campaign

On one H100 SXM 80 GB, the selected repeated FP16 reference scores are **61,656 fixed-context evaluations/s for Qwen3-1.7B** and **2,951,333/s for SimpleStories-V2-5M**, both at 128 input positions. The standardized Qwen one-token, 128-output continuation achieves **62,538 generated tokens/s in aggregate across 2,048 independent sequences**, or **219.7 tokens/s at batch one**.

The conditional comparison has no single ordering. With the shared benchmark method, Qwen's named scheduled-work proxy is about 16% lower; its hypothetical full-use-of-runtime-units proxy is about twice as high. Neither is a measured training capability or a certified residual training factor. The GPU parents and FPGA numerical functions differ.

Measured October 25, 2026 Pacific (October 25–26 UTC). The evidence archive contains **897 files**, verified against its SHA-256 inventory, with **32 passing and five failed benchmark cases** and the associated numerical diagnostics.

### Reference scores and workload

| Model | Context | Independent batch | Mode | Initial score | Fresh-process repeat used in calculations |
| --- | ---: | ---: | --- | ---: | ---: |
| Qwen3-1.7B | 128 | 512 | Compiled CUDA graph, FP16 reference policy | 61,634.506/s | 61,655.709/s |
| SimpleStories-V2-5M | 128 | 32,768 | Compiled CUDA graph, FP16 reference policy | 2,955,826.731/s | 2,951,332.875/s |

The Qwen repeat differs by 0.034%; the SimpleStories repeat differs by -0.152%. Each score is counted evaluations divided by the median of five host-wall samples. The configuration was selected from the initial sweep, then repeated in a fresh process with seed 20261026. The repeat supplies the reference score even when it is lower than the initial run.

Each fixed-context evaluation executes every layer, final normalization, the vocabulary head and greedy selection, using independently stored K/V for every sequence. It repeats the last input at position 127 with 127 cached predecessors. It is not a stream of distinct generated tokens. Loading, prefix construction, compilation, warmup, CPU token copying, text decoding and networking are outside cached timing. Host launches and synchronization are included; CUDA event spans are also retained.

The same shared cache/timing core, package stack and GPU were used for both models. The Llama-based SimpleStories adapter supplies its model geometry and loader, and translates the precomputed causal-mask API for the benchmark-owned cache. Independent uncached full forwards retain the original Llama mask factory. The adapter preserves all model layers and operations. Full-forward, changed-input, prefix-stability and captured-input replay checks pass. Profiled decode calls use native query/K/V head counts: Qwen 16/8 and SimpleStories 4/2, without software-level expansion of the whole K/V cache.

The [Transformers 4.48.3 SimpleStories benchmark](H100-BENCHMARK.md#historical-simplestories-campaign) measures 1,018,048 evaluations/s with a different cache implementation. Rates from the two implementations are reported with their software versions and numerical policies; bit-exact agreement between the backends is not established.

Strict-greedy graph-only references also pass: Qwen's repeated batch-2,048 score is 55,851.987/s; SimpleStories' batch-32,768 graph score is 2,258,270.700/s. Qwen graph throughput levels off at batch 2,816 (55,841.353/s). SimpleStories' larger batch 57,344 gives 2,235,059.323/s in graph mode and 2,928,107.987/s compiled, below its selected batch-32,768 scores. These are achieved scores and observed plateaus for these implementations, not proved hardware maxima or licensed ratings.

### Standardized generation

Qwen's primary continuation starts with the single token `[9707]` and produces all 128 outputs, including any outputs after an end marker. The 127 timed cached intervals consume input contexts 2 through 128. Each invocation uses true feedback from each newly selected token.

| Independent batch | Initial cached generated tokens/s | Fresh-process repeat |
| ---: | ---: | ---: |
| 1 | 219.682 | 219.743 |
| 2,048 | 62,531.214 | 62,538.360 |

At batch 2,048, the repeat supplies 30.536 tokens/s per sequence. Row zero uses `[9707]`; the other rows have independently generated one-token prompts and disjoint caches. All 262,144 primary output-token comparisons against eager execution agree in the aggregate repeat; the separate changed-prefix trajectory check also passes. The batch-one GPU first-output median is 19.8 ms and the full 128-output median is 0.597 s, with preloaded weights and no CPU token delivery.

The three recorded FPGA prompts pass full GPU eager/graph trajectory comparisons at about 219 tokens/s each. The [common FPGA benchmark](../../demos/qwen3-1.7b/evidence/common-speed-2026-10-26/capture.json) uses one token `[9707]`, 128 outputs and two complete trials. Its pooled host-loop cached rate is **9.00995 tokens/s**, with all 256 outputs matching the independent CPU reference for the FPGA numerical function. The common protocol aligns workload geometry; the FPGA fixed numerical function and host timing boundary differ from the FP16 GPU reference and its timing boundary.

Longer-context graph panels pass separately: 24,676.920 evaluations/s at context 512/batch 512; 7,301.526/s at 2,048/batch 128; and 1,893.382/s at 8,192/batch 32. These GPU panels do not extend FPGA hardware qualification or establish a maximum over attacker workloads.

<a id="numerical-acceptance-and-retained-failures"></a>

### Numerical acceptance and diagnostics

The reference suite uses FP16. Cached/full diagnostics on two seeds show FP32 agreement within 0.000015, including changed-input/prefix checks, and FP16 maximum absolute logit difference 0.015625. The BF16 maximum difference is 0.1875 and exceeds the benchmark's logit tolerance.

Graph-only and continuation runs require exact greedy agreement. A separately selected compiled fixed-context FP16 policy retains all-logit `rtol=0.005, atol=0.05` and nonfinite rejection but reports greedy disagreements. In the selected repeated rating tapes, Qwen differs on **1/512** greedy choices and SimpleStories on **61/32,768**. Mutation-check disagreements and margins are retained too. These results are floating-point reference scores, not exact-token equivalence claims.

The compiled diagnostic reproduced a top-two FP16 tie on a Qwen changed-prefix row: eager scores 12.328125 and 12.3203125 became equal at 12.3203125 in the compiled result, changing argmax. FP32 preferred the eager winner on that inspected row. This explains that row; it is not a claim that every other disagreement has been individually explained. Cases that fail their stated acceptance policy contribute no accepted rate. Compiled Qwen batches 1,024 and 2,048 exceed the all-logit tolerance.

The evidence archive includes every benchmark outcome and setup diagnostic. The parent configuration permits 40,960 positions; the FPGA tape and benchmark admission limit are 32,768 positions.

The GPU parent and quantized FPGA do not produce identical continuations. For the three recorded 128-output prompts, first divergence occurs at outputs 4 (story), 34 (geography) and 32 (chat), counting from one. Positionwise matches are respectively 3/128, 51/128 and 31/128. After divergence the models receive different generated histories, so these are not teacher-forced per-step accuracy rates or model-quality scores. They establish why the inference denominator remains a parent-model proxy; an exact quantized-function comparison or an agreed equivalence standard is still needed.

### Conditional capacity comparison

For the [Qwen analysis](../../demos/qwen3-1.7b/TRAINING-CAPACITY.md), use `phi_proxy = T*R/(989e12*F)`. The device rates use identified fixed-context STEP intervals: Qwen `F=1/0.112895146`; SimpleStories pools two matching 128-position intervals, giving `F=2/(0.101706167+0.101874708)`. Neither is a sustained peak rating. They are distinct from the headline growing-context averages.

The following alternatives use the shared-method repeated H100 references above. Rows overlap and must not be added. Every-cycle rows grant useful operand control, readout and continuous utilization that have not been demonstrated. Narrow products, squares and standalone multiplication are generously credited as full MACs.

| Hypothetical access and schedule | Qwen phi_proxy | SimpleStories phi_proxy | Qwen / SimpleStories |
| --- | ---: | ---: | ---: |
| Named dynamic work on the same decode schedule | 0.00199995 | 0.00239112 | 0.836 |
| Useful MAC every cycle from all named runtime/square units | 0.235071 | 0.288571 | 0.815 |
| Useful MAC every cycle from all functional multipliers | 0.974066 | 1.36691 | 0.713 |
| Chosen accepted weights make all counted matrix work useful | 0.216341 | 0.0342843 | 6.31 |

The counts in the named scheduled-work row are 32,080,640 and 801,272 operations/decode. Under that row's matched-workload assumption, `T=C*F` and device speed cancels. The every-cycle runtime row grants 33.4 billion operations/s for Qwen's 167 named units and 950 million/s for SimpleStories' 19 scheduled runtime-operand instances. Its inferred ratio depends on both the FPGA rate and GPU reference. A value near 0.24 describes credited training arithmetic per unit of inference service; it does not say one FPGA supplies 24% of an H100's raw training arithmetic.

Qwen's smaller attention-work share is therefore an architectural advantage, but it does not establish a smaller whole-system residual training factor. The outcome depends on accessible arithmetic, its schedule, the reference implementation, workload and numerical-function standard. The one-token continuation's conditional named-work identity is separately 0.00111124, using 17,573,504 average operations per cached token; the matching FPGA measurement does not establish the assumed arithmetic access or a device-wide bound.

### Evidence and reproduction

Use Python 3.11 or later from the repository root:

```sh
python3 -I -S -B tools/qwen_h100_results.py --check
python3 -I -S -B tools/qwen_h100_results.py
```

The checker verifies the complete archive against its independently recorded remote SHA-256 and checks every payload against the remote inventory. It binds the selected cases to their source snapshots and recomputes rates from the retained token counts and wall times before deriving the table. It performs no model execution, network or hardware access.

[Selected cases](../../evidence/qwen-h100-2026-10-25/SELECTED-REFERENCES.json), [computed results](../../evidence/qwen-h100-2026-10-25/computed-results.json), [verified raw archive](../../evidence/qwen-h100-2026-10-25/raw-evidence.tar.gz), [backup verification](../../evidence/qwen-h100-2026-10-25/BACKUP-VERIFIED.json), [precision diagnostic](../../evidence/qwen-h100-2026-10-25/cache-precision-diagnostic.json), and [compiled rounding diagnostic](../../evidence/qwen-h100-2026-10-25/compiled-rounding-diagnostic.json) retain successes and failures.

The archive excludes models, environments and compiler caches. It includes the pinned acquisition helpers, benchmark source snapshots for every case, setup/controller logs, wheel-install reports, GPU identity and profiler traces. To reproduce a selected case, extract its archived source snapshot, install the recorded stack in an isolated environment, acquire its pinned public safetensors, expose one whole H100, and use the case's recorded workload arguments with a fresh output directory. The H100 was 132-SM/80-GB/700-W, MIG disabled, driver 580.105.08; the stack used Python 3.10.12, torch 2.10.0+cu126 and Transformers 5.17.0.

A whole-system residual training bound additionally requires bounds across useful training channels and permitted executions, comparable licensed ratings, and physical/test/debug assessment, as described in the [methodology](../analysis/RESIDUAL-TRAINING-METHODOLOGY.md). The GPU measurements do not establish a training attack or a security certificate.

<a id="historical-simplestories-campaign"></a>

## SimpleStories with Transformers 4.48.3

On one **H100 SXM 80 GB**, the SimpleStories-V2-5M FP16 parent checkpoint
achieved approximately **1.02 million cached-decode token evaluations/s in
aggregate at 128 input positions**. A different-prompt repeat reproduced the
result within 0.02%. The batch-one compiled microbenchmark measured about
6,500 evaluations/s. These are different capacity/latency measurements, not
a claim that one chat produces a million tokens each second.

This reference informs the [conditional residual training factor analysis](../../demos/simplestories-v2-5m/TRAINING-CAPACITY.md).
It is **not bit-exact FPGA W10/A16/KV16 inference**, an end-to-end chat-service
benchmark, or a certified peak H100 rating. FPGA and host measurements are
documented in [VALIDATION.md](../../demos/simplestories-v2-5m/VALIDATION.md).

### Results

Measured September 16, 2026 Pacific (September 17 UTC), on GPU 0 of a rented
two-H100 instance. `CUDA_VISIBLE_DEVICES=0` exposed only one GPU; the benchmark
also rejected any run with more than one visible device. GPU 1 was not used.

The raw `nvidia-smi` inventory lists both GPUs installed in the server;
it does not describe CUDA visibility for the benchmark process. The
[runner](../../demos/simplestories-v2-5m/benchmarks/h100/benchmark.py) checks that `torch.cuda.device_count()`
is exactly one. The separate [replay record](../../demos/simplestories-v2-5m/evidence/h100/correctness/replay-compile-graph.json)
also records `cuda_visible_devices = "0"`.

| Implementation | Independent sequences | Aggregate evaluations/s | Acceptance |
| --- | ---: | ---: | --- |
| Compiled CUDA graph | 1 | 6,460 | Strict greedy agreement |
| Compiled CUDA graph, independent-prompt repeat | 1 | 6,513 | FP16 reference; no disagreement in this case |
| Uncompiled CUDA graph | 32,768 | 609,285 | Strict greedy agreement |
| Compiled CUDA graph | 8,192 | 996,875 | FP16 reference |
| Compiled CUDA graph | 32,768 | 1,017,925 | FP16 reference |
| Compiled CUDA graph, new-prompt repeat | 32,768 | **1,018,048** | FP16 reference |

The [selected repeat](../../demos/simplestories-v2-5m/evidence/h100/h100-compiled-fp16-repeat/ctx128-batch32768-float16-compile-graph.json)
used five approximately three-second trials. Its median rate was
1,018,047.545/s, with trial rates between 1,018,035 and 1,018,145/s. At that
batch size, a step took 32.19 ms: about **31.1 evaluations/s per sequence**.
The [initial large-batch result](../../demos/simplestories-v2-5m/evidence/h100/h100-compiled-fp16-reference/ctx128-batch32768-float16-compile-graph.json)
was 1,017,924.918/s. The large-batch compiled rate improved by only about 2.1%
from batch 8,192 to 32,768; that suggests a plateau for this implementation,
not a limit on all possible GPU implementations.

The saved evidence contains **six sweeps, 28 passing cases and two preserved
strict-acceptance failures**. Eager, CUDA-graph and compiled CUDA-graph modes
were tested. A separate eager natural-language test generated a 64-token
story at roughly 350–365 tokens/s after its first token; that slower baseline
is not used as the reference capacity.

### What the timing counts

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

### Numerical acceptance

The strict acceptance policy requires all logits to meet `rtol=0.005, atol=0.05`
relative to same-precision eager inference **and** every greedy token to
match. Compiled batches 256 and 1,024 passed the logit comparison but failed
the exact-token check. Their failed results and worker records are
in [the strict sweep](../../demos/simplestories-v2-5m/evidence/h100/h100-context128/summary.json).

The [rounding diagnostic](../../demos/simplestories-v2-5m/evidence/h100/correctness/compiled-rounding-batch1024.json)
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

### Environment and reproducibility

The GPU was an H100 SXM 80 GB, 132 SMs, compute capability 9.0, 700 W power
limit, with MIG disabled. The timing records identify Linux/Python 3.10.12,
driver 580.105.08, PyTorch 2.10.0+cu126, Transformers 4.48.3, tokenizers
0.21.4, safetensors 0.7.0 and NumPy 1.26.4. TF32 and reduced-precision GEMM
reduction were disabled. Cases ran sequentially in fresh processes, and the
records report eight CPU execution threads.

The [original setup notes](../../demos/simplestories-v2-5m/benchmarks/h100/source-versions/fp16-reference/README.txt)
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

[Benchmark instructions and scripts](../../demos/simplestories-v2-5m/benchmarks/h100/README.md) are included.
Model weights and GPU software are obtained separately under their own terms;
they are unnecessary for inspecting the recorded data or running the FPGA.

[`evidence/h100/IMPORT.json`](../../demos/simplestories-v2-5m/evidence/h100/IMPORT.json) binds the published
files to their original identities. Measurement JSON is unchanged. Worker
logs are included as `.txt` with only machine-local benchmark-directory paths
replaced where present; both original and released digests are recorded.
Exact source versions, including the original strict implementation, are
retained. Credentials, cloud connection details and environment installations
are not included. 
Offline verification requires only Python 3.12:

```sh
python3.12 -I -S -B demos/simplestories-v2-5m/tools/check_h100_reference.py
python3.12 -I -S -B demos/simplestories-v2-5m/tools/estimate_training_capacity.py --check
```

### Performance headroom

An achieved rate is evidence that this workload can run at least that fast,
not proof of the hardware's absolute maximum. The
[capacity analysis](../../demos/simplestories-v2-5m/TRAINING-CAPACITY.md#gpu-performance-headroom-and-sensitivity)
derives an ideal minimum-K/V-traffic bandwidth roof of 8.52 million
evaluations/s, and a looser arithmetic-only roof of 86.08 million/s. Neither
is achieved performance or a prediction of a particular optimized kernel.

Useful-work and minimum-traffic ratios to peak specifications are not
profiled arithmetic/bandwidth utilization. The saved matrix-multiplication
autotune logs likewise do not constitute an end-to-end kernel profile.
These measurements do not establish the performance of other cache or
decode implementations, the exact quantized FPGA function, or a licensed
inference rating.
