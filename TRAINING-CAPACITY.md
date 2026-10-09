# Estimates of residual training capacity

The measured rates and conditional factors below use the faster baseline.
They have not been recomputed for the third
[encrypted-memory version](ENCRYPTED-MEMORY.md). Encryption alone does not
establish a smaller training-capacity bound.

**Version scope:** the numerical estimates in this document use the supplied
baseline **without K/V integrity checks** and its recorded inference rates.
The repository also supplies a [K/V-protected prototype](KV-PROTECTION.md).
That variant rejects inconsistent external cache data before use under its
stated assumptions; its cache remains unencrypted. A scenario that supplies
chosen K/V through DDR would also have to defeat that protection. We have
not demonstrated such a method, and do not assign the baseline's numerical
ratios to the protected version. Neither version has a certified residual training factor.

This document asks how much useful training computation an attacker could get from the released design. We assess the circuit as if its FPGA configuration were permanently frozen, or it were built as a fixed ASIC. Reprogramming the FPGA is outside this assessment. Some scenarios assume that other forms of physical tampering have succeeded; we have not established the feasibility or cost of obtaining that access. This is not a physical-security assessment of the reprogrammable demo board. See [INFERENCE-ONLY.md](INFERENCE-ONLY.md).

**We have not demonstrated any way to train with this chip. For the scenarios that assume access to its internal multipliers, we do not know a practical way for an attacker to supply chosen inputs and recover useful results. The calculations assume that access; they do not show how to obtain it or that it is possible.**

*The Feasibility of a Hardwired Pause of Frontier AI Training* defines the **residual training factor**, φ, as a bound on peak arithmetic throughput for training, in H100-equivalents, divided by the peak licensed inference rating, in inference-H100-equivalents. In plain terms, a smaller factor means less training capacity for the same amount of inference service. Our calculations are not licensed ratings: they combine assumed training capabilities with measured FPGA and GPU speeds. We call the resulting ratios `φ_proxy`, not certified residual training factors.

## Access assumptions: software versus hardware

We consider three kinds of access:

- **Control of the host software.** The attacker can send prompts and arbitrary UART command sequences. The implemented interface has no command for choosing intermediate memory addresses, supplying inputs to a multiplier, reading its results or replacing accepted model weights. We calculate a limit for one possible use: sending matrices as tokens and asking the model to return their product. That calculation does not cover every possible use of prompts or every implementation bug.
- **Physical access to external DDR memory or its wiring.** The attacker could try to read or change the cached K/V values used by attention, without modifying the silicon. Those values are not cryptographically authenticated. But the chip still checks model weights and controls the other attention inputs and where results go. Later layers' K/V values are written to the same memory and could be read by the attacker; they provide a nonlinear, quantized observation of earlier attention results. We ask whether this memory access could be turned into useful multiplication. **We have not shown how to do that.** Changing or reading K/V alone does not give direct control of both multiplication inputs or direct access to the product itself.
- **Physical changes or faults inside the circuit.** An attacker could try to defeat weight checks or alter the connections and controls around arithmetic units. Some calculations below assume such attempts have succeeded. We have not worked out a feasible way to give an attacker the assumed access, estimated its cost, or measured its success rate. The calculations also keep the stated clock and execution rate; they do not cover arbitrary overclocking or every possible modification.

Here, **direct access** means supplying an operand itself or reading the product itself, rather than influencing or observing values transformed by other model operations. An indirect channel might still be useful; this distinction does not rule that out.

The [formal proofs](FORMAL-STATUS.md) restrict what software can make the verified RTL do. For arbitrary serial input sequences, they show that commands come from valid requests, `APPEND` preserves its token, token replies belong to an accepted `STEP`, and tape updates obey the proved rules. The connected UART/core/token-shell proof establishes 134 assertions, including supporting invariants; a second solver confirms 133 of the 134 conclusions. These results apply under the proof's reset and synchronous digital assumptions; they are not just tests of selected prompts. They do not yet prove the complete inference/memory system or its correspondence to the loaded FPGA implementation.

A software-triggered bug could still break a rule we have not proved. We therefore distinguish the access each calculation assumes from the question of whether an attacker could obtain it. **Neither control of the host app nor access to DDR automatically makes the internal multipliers available for general computation.**

## The scenarios we calculate

Each row asks a different question. The rows are not additive and do not give a range for the chip's actual training capacity.

| Scenario | Assumed operation rate `T` | What we assume |
| --- | ---: | --- |
| Matrix arithmetic through tokens | 100,362/s | The model can multiply matrices supplied as tokens; only communication time limits it. Neither ability nor speed has been demonstrated. |
| Full use of five dynamic multipliers | 250 million/s | The attacker can use all five on every clock cycle and recover useful results. We do not know how to obtain that access. |
| Full use of all 76 mapped multipliers | 3.8 billion/s | The attacker can choose both inputs, obtain results and keep every unit busy. We do not know how to obtain that access. |
| Dynamic operations only when the model runs them | 5.24 million/s | The attacker can use those operations for training, but cannot run more of them or run them faster than the assumed schedule. Neither premise has been proved. |
| Replace accepted weights, keeping the same schedule | 75.1 million/s | The attacker can repeatedly replace the weights and use the resulting forward passes, without slowing inference. We have not demonstrated this. |

The internal-arithmetic rows count one multiply–accumulate (MAC: a multiplication followed by an addition) as two operations. They sometimes count a multiplication or square as if it also supplied a useful addition. These assumptions favor the attacker. The FPGA's integer/block-floating-point operations are not the H100's FP16/BF16 operations; counting them this way does not establish equivalent precision or usefulness for training.

The two schedule-based rates use one cached decode at 128 input positions, not a maximum over workloads. Longer-context decode and prompt processing can expose different amounts of counted arithmetic per second, even with the model schedule unchanged. The [architecture-dependent analysis](ARCHITECTURE-DEPENDENT-CAPACITY.md#different-workloads-do-not-generally-cancel) calculates examples from the saved timings.

The first row concerns the token interface. The others assume access beyond the public commands. Even a small arithmetic rate compared with an H100 can give a substantial residual training factor estimate, because this prototype also performs inference much more slowly than an H100.

## 1. Matrix arithmetic through the token interface

The paper's “Quantifying training capability” section considers sending matrix entries and receiving their product through tokens, assuming each token carries one two-byte matrix entry. Multiplying an `n × k` matrix by a `k × m` matrix takes `nk + km + nm` input and output tokens for `2nkm` arithmetic operations. If all these tokens fit on a tape of length `L`, square matrices maximize operations per token and give:

```text
T_token <= (2/3) × sqrt(L/3) × r
```

Here `r` counts input and output tokens together. We use **L = 2,049**, including the final output slot beyond the model's 2,048-input limit. The supplied baseline reached that limit on the board; see [the full-window results](README.md#the-demonstrated-design-and-measurements).

We then assume tokens can move at the serial link's maximum data rate and ignore the time needed to run the model. The [UART wrapper](hardware/project/uart_core.sv) fixes 217 core cycles per bit; the [protocol](hardware/project/fpga/token_only_model0_mac_uart0/rtl/token_only_model0_uart_bridge.sv) uses five bytes per token-bearing frame. We count eight data bits per byte, omit start/stop bits and acknowledgements, and let both directions run continuously; that last assumption supplies the factor of two below. At the nominal 25 MHz clock:

```text
r <= 2 × 25,000,000 / (217 × 8 × 5) = 5,760.37 tokens/s
T_token <= (2/3) × sqrt(2,049/3) × 5,760.37 = 100,362 FLOP/s
```

The vocabulary actually carries less than 12 bits per token, not 16. Giving it 16 bits also favors the attacker. **The result is a deliberately loose upper limit for this particular way of sending matrix arithmetic through tokens, not a speed the story model has achieved. We have not shown that the model can multiply arbitrary matrices at all.**

A tighter limit would include prompt processing and the time taken by `STEP`, which is the only command that returns a model result. But measured story-generation speeds are not proven maximum speeds for every possible workload. A calculation that charges different costs for inputs and outputs must also reconsider the matrix shapes; the square-matrix result above assumes a combined token rate.

This calculation assumes the unchanged protocol and nominal clock. It does not bound every possible encoded computation, timing channel or physical attack. A limit on one way of using the chip is not a limit on all ways of using it.

## 2. Internal arithmetic scenarios

### Suppose an attacker could use all five dynamic multipliers

The design has five multiplier instances that, in at least one scheduled role, take runtime-computed values on both inputs: the two attention lanes, the shared elementwise lane used for the feed-forward gate product, and one multiplier in each of the two RMSNorm services. The elementwise lane also applies fixed rotary tables. Each RMSNorm multiplier squares runtime values in one phase and multiplies runtime values by fixed normalization weights and row scales in others. Here, “dynamic” distinguishes two runtime-data operands from a runtime activation multiplied by a fixed model coefficient; it does not mean independently chosen operands. See the [arithmetic inventory](ARCHITECTURE.md#other-runtime-arithmetic).

**We do not know a practical way for an attacker to use all five as general arithmetic units.** For this calculation, we simply assume the attacker can make each one perform a useful multiply–accumulate on every clock cycle and obtain the results:

```text
5 × 25,000,000 = 125,000,000 multiplications/s
2 × 125,000,000 = 250,000,000 MAC-equivalent operations/s
```

The calculation ignores the fixed schedule, periods when units are idle, memory waits, how inputs would arrive, and how useful results would leave. It also treats each RMSNorm multiplier as available for arbitrary two-input multiplication, even though its inputs are the same value in its squaring phase and one is a fixed coefficient in its other multiplication phases.

An attacker who changed external K/V could affect one input of each attention multiplication. That would not by itself provide an injection point for arbitrary `Q` or `A`, or a readout of the untransformed product. The attacker could nevertheless read later layers' K/V values written back to the same unauthenticated DDR, giving an indirect, transformed observation of earlier attention results. We have not established whether useful products could be recovered through this channel. Nor does DDR access make the shared elementwise and normalization multipliers independently callable. **The 250 million figure therefore assumes much more than access to DDR provides.** It is not a demonstrated attack rate, and it does not prove that every possible training use of the chip must go through these five units.

For the fixed-hardware interpretation—a future ASIC or a hypothetical non-reprogrammable version of this design—focused-ion-beam (FIB) circuit editing is one possible means of cutting and creating internal connections. But that capability alone does not establish that these five units could be converted into a useful training accelerator. To obtain the assumed full use through physical tampering, an attacker would need to control the inputs, accumulate and retrieve useful results, and change the scheduling and data movement enough to keep all five units working simultaneously on every clock cycle. For the normalization multipliers, the missing capability is attacker control of both operands, not the physical ability to multiply two different values. **We have not identified a feasible set of physical modifications that would achieve this.**

This scenario assumes control over fewer units than the 76-multiplier scenario below. That does not by itself show that the required changes are small or practical. The rate assumes those obstacles have been overcome; it is not evidence that they can be overcome. Conversely, our lack of an identified method is not proof that such access is impossible.

This scenario keeps the accepted model weights fixed. The chip checks weights during inference, not just at startup: it copies each model page into on-chip RAM, prevents that copy from changing, and checks it against a compiled digest before using it. K/V data do not have the same protection. See [model storage and K/V memory](ARCHITECTURE.md#model-storage-authentication-and-kv-memory).

### Suppose an attacker could use all 76 mapped multipliers

The [selected implementation census](evidence/leaf-speed/implementation.json) lists 73 `MULTALU27X18` and three `MULT12X12` primitives, reported as 74.5 DSP blocks. “Mapped” means used to implement this particular circuit, not every arithmetic resource elsewhere in the FPGA. These 76 units include weight-projection and fixed-scaling arithmetic, not just the five dynamic multipliers above. See the [datapath description](ARCHITECTURE.md#arithmetic-microarchitecture).

**These units are not user-callable, and we do not know a feasible way to make them all available to an attacker.** The calculation asks what they could supply if we assumed away their input, output and scheduling restrictions. Specifically, we assume the attacker can:

- Choose both inputs, including inputs normally fixed by authenticated weights or compiled constants;
- Accumulate products and recover results useful for training;
- Keep every counted unit performing a useful multiply–accumulate on every 25 MHz clock cycle, simultaneously and without memory stalls.

Those assumptions give:

```text
2 × (73 + 3) × 25,000,000 = 3,800,000,000 MAC-equivalent operations/s
```

This is a **what-if calculation, not evidence that such an attack is feasible or likely**. Changing K/V would not provide this access. Even defeating weight verification would not automatically let an attacker select both inputs, recover products or keep every unit busy: the fixed controllers and internal connections would still matter.

Under the same fixed-hardware interpretation, having FIB circuit-editing equipment does not establish a way around those restrictions. We have not identified physical changes that would expose useful inputs and outputs for all 76 units while sustaining the assumed simultaneous rate. For example, the 64 projection lanes normally share a broadcast activation and fixed sequencing, and their results leave through a staged output path. Shared circuitry also means that a modification could affect several lanes; we do not assume that an attacker would need 76 separate modifications. **The calculation assumes full access and throughput; it does not demonstrate a physical way to obtain them.** We have not performed a die-level tamper assessment, and a future ASIC layout would need its own assessment.

The calculation also treats the 12-bit units as full 16-bit MACs without accounting for any extra work that would require. On the other hand, it counts only these 76 units at the nominal clock. It is not a proved limit for arbitrary rewiring, overclocking or reuse of other logic. We have not estimated the cost or probability of obtaining the assumed access.

### Suppose the attacker could use dynamic operations only when the model runs them

Both preceding multiplier scenarios let the attacker use the counted units on every clock cycle. Here we instead suppose they can use the model's dynamic operations for training, but **cannot change how often or how fast those operations run**. We have not shown how to obtain useful training results this way, or proved that the assumed execution count and rate would limit an attacker.

The [pinned model](reference/reference/model.py) has six layers, four query heads, **two K/V heads**, 64 coordinates per head, hidden width 256, feed-forward width 682 and a vocabulary of 4,019 tokens. For one cached decode at `n` input positions, the named dynamic operations are:

```text
attention products = 2 × 6 × 4 × 64 × n = 3,072n
gate products      = 6 × 682             = 4,092
RMSNorm squares    = (2 × 6 + 1) × 256    = 3,328
C_dynamic          = 2 × (3,072n + 7,420) MAC-equivalent operations/decode
```

At `n = 128`, this counts **801,272 operations per decode**, or **5,239,482/s** at the measured `F = 6.5390/s`. As above, counting a square or standalone product as a full MAC favors the attacker.

To turn this into a training-capacity bound, we would need to check the complete relevant execution count and prove that the attacker could not run extra operations or run them faster. The proof would need to cover prompt processing, partial work and cancellation as well as normal decoding. One measured decode is not a universal speed limit. The calculation also does not cover every indirect use of the fixed network or other physical attack.

The gap from 250 million/s to 5.24 million/s comes from counting only the named dynamic work, rather than granting useful work from all five multipliers on every cycle. Over the measured 0.152929625-second decode, the every-cycle budget is approximately **38,232,406 MAC-equivalent operations**. The counted 801,272 operations use about **2.10% of that budget**. This is a work fraction derived from the model count and elapsed time, not a measured hardware-utilization trace: the shared lanes also perform fixed-coefficient work, and the elapsed time includes other stages, waits and host overhead.

Separately, under the stated access and execution assumptions, `T = C_dynamic × F`, so `φ_proxy = C_dynamic × R / 989e12`. **FPGA speed cancels when both sides use the same workload:** running that workload twice as fast also runs its counted operations twice as fast. The paper instead compares peak training throughput with inference rated at a standardized context. If an attacker chooses a different workload, its operation rate need not scale with the inference-rating workload. A uniform speedup across workloads still cancels; different relative speeds do not.

**GPU reference performance does not cancel.** Let `C_total` count the 11,488,768 matrix operations derived in the next subsection plus the 14,840 gate-product and square operations credited above: 11,503,608 in all. For the matched 128-position workload, `φ_proxy = (C_dynamic / C_total) × (C_total × R / 989e12)`: roughly 7% credited dynamic work times 1.18% effective reference arithmetic throughput gives 0.000825. The latter is counted useful work divided by the GPU's arithmetic rating, not a profiler measurement. Including the extra products gives 1.1841%; matrix work alone gives 1.1826%. A faster GPU reference makes the ratio larger. The 2.10% multiplier-cycle fraction above is a different quantity, not the model's dynamic-arithmetic share.

The saved longer-workload intervals give conditional estimates of about **0.00113 for a 255-position decode and 0.00121 for a 512-token prefill**, keeping the inference comparison at 128 positions. Those are counts divided by single host-timed intervals, not sustained peak rates or demonstrated training capabilities. They illustrate why 0.000825 is not a workload-independent bound. Neither the access assumption nor a complete execution-rate limit has been proved.

[Architecture-dependent capacity](ARCHITECTURE-DEPENDENT-CAPACITY.md) reproduces these workload examples, derives the work fractions, compares Llama 3.1 405B, and explains context, prefill versus decode, batching and mixture of experts. It uses saved FPGA timings and analytic work counts, not new board measurements or certified ratings.

### Suppose an attacker could replace the accepted weights

Here we suppose an attacker has defeated all necessary weight checks and can repeatedly run the fixed architecture with chosen, changeable weights. We also assume those forward passes would be usable for training and run at the measured inference speed. **We have not demonstrated this or worked out a practical way to do it.** Altering DDR alone is not enough: pages are checked before use, and the compiled scaling metadata, numerical format and controllers still constrain what the chip runs.

The projections in all six layers plus the tied vocabulary head require:

```text
projection/head MACs = 6 × (2 × 256 × 256 + 2 × 256 × 128 + 3 × 256 × 682)
                       + 4,019 × 256
                     = 5,351,168
```

The `128` in the projection formula is the K/V width: two heads of 64 coordinates, not the context length. The input embedding is a lookup, not a second vocabulary multiplication. Adding attention gives:

```text
C_matrix = 2 × (5,351,168 + 3,072n)
         = 11,488,768 operations/decode at n = 128
T_matrix = C_matrix × F = 75,124,542 operations/s
```

We do not subtract time for replacing weights, restarting the chip, transferring results or doing training work on an external computer. The count includes the main matrix operations, not nonlinear operations or every implementation detail. It is therefore a calculation under the stated assumptions, not a complete upper bound or measured training speed.

**If an attacker could supply useful, changeable weights, the absence of a backward-pass engine would not by itself make that harmless.** That is why this scenario is worth considering. But it is different from the previous assumption of direct access to all 76 multipliers; replacing weights would not automatically provide that access.

Here `T = C_matrix × F`, so FPGA speed cancels under the same matched-workload condition as in the dynamic-operation calculation. Crediting all counted matrix work makes this the `rho = 1` case in the architecture note's matrix-only bookkeeping: its proxy equals the reference's counted matrix-work efficiency, approximately 0.0118. This identity depends on the stated assumptions; it does not establish useful training access.

## 3. Residual training factor estimates with a measured reference

The paper's definition uses **peak training throughput and a peak licensed inference rating**. For a given model, its inference-H100-equivalent rating divides peak token throughput at a standardized context by that of a standardized general-purpose accelerator cluster, then multiplies by that cluster's H100-equivalent capacity. Using one H100 as the reference cluster makes that last multiplier one.

We do not have those ratings. Instead, `T` is the assumed operation rate for each scenario, `F` is a measured FPGA inference rate, and `R` is a measured GPU reference rate. Using one H100-equivalent of 989 TFLOP/s gives:

```text
φ_proxy = (T / 989,000,000,000,000) / (F / R)
        = T × R / (989,000,000,000,000 × F)
```

NVIDIA's [H100 specifications](https://www.nvidia.com/en-us/data-center/h100/) give the sparse FP16/BF16 rate; the paper halves it, rounded, for dense arithmetic.

For `F`, the final `STEP` of `around128` in the [selected baseline measurements](evidence/baseline-current/metrics.json) took **0.152929625 s** at 128 input positions, or **6.5390 tokens/s**. This is one measured step including host overhead, not a sustained maximum. Using it avoids comparing an average over a growing context with a fixed-context GPU test. The release includes a repeat of the continuation, but these calculations use the identified first run, not an estimate of peak fixed-context throughput.

The host timing also reflects the approximately 17 ms reply-delivery pattern
described in the [measurement notes](KV-PROTECTION.md#measured-performance).
Small differences between individual STEP measurements need not track the
compute improvement. We retain the observed value rather than subtracting
an assumed delay. If the underlying FPGA rate is higher, `φ_proxy` is lower
with `T` and `R` held fixed; this does not resolve the other rating uncertainties.

Neither measured inference rate proves a maximum or establishes a licensed rating. Both implementations might run faster. A faster GPU reference increases `φ_proxy`; a faster FPGA decreases it when `T` is fixed. **Using measured speeds on both sides does not make `φ_proxy` a known upper or lower bound on the paper's residual training factor.** The assumed training access and the numerical/timing differences below also remain unresolved.

### The measured GPU reference

One **H100 SXM 80 GB** achieved **1,017,925 cached-decode evaluations/s in aggregate**. A fresh-process repeat with different prompts measured **1,018,048/s**; the calculator uses its unrounded `R = 1,018,047.5450472439`. Both used FP16, 128 input positions and 32,768 independent sequences in a compiled CUDA graph. Only one GPU was available to the benchmark's CUDA process. The saved `nvidia-smi` inventory lists both GPUs installed in the server, not the number available to that process. See the [benchmark report](H100-BENCHMARK.md) and [selected raw measurement](evidence/h100/h100-compiled-fp16-repeat/ctx128-batch32768-float16-compile-graph.json).

The benchmark repeatedly evaluates a full decode step on fixed tapes; it does not generate a million successive tokens in one chat. Each step runs all six layers, the vocabulary head and greedy selection. At the large batch, each sequence gets about 31 evaluations/s. A separate single-sequence test reached roughly 6,500/s; that is not the `R` used here.

The timing includes host launches and synchronization but excludes prefix construction, compilation, warmup, returning tokens to the host, text decoding and network handling. The FPGA measurement includes host/serial costs that the GPU test omits.

The compiled FP16 runner met the stated logit tolerances, but chose a different greedy token from eager FP16 on 54 of 32,768 repeat-run rows: **99.8352% agreement**. A separate test of four disagreements in a different batch and seed found near ties. It did not individually explain the selected run's 54 disagreements. The original strict-greedy failures remain in the evidence. An **uncompiled CUDA-graph** run with exact eager-greedy agreement reached **609,285/s**; we use the faster, explicitly qualified result rather than the slower rate that would give a smaller ratio.

**This GPU runs the FP16 parent, not the exact W10/A16/KV16 integer model on the FPGA.** The package has no agreement statistic between those two numerical models. GPU eager/compiled comparisons and FPGA/integer-reference comparisons are separate tests. These differences, the timing differences and the single FPGA step prevent treating the result as a certified comparison.

### Conditional results

The paper uses **0.01, 0.001 and 0.0001 (10⁻⁴)** as illustrative fleet-average residual training factors. Its 10⁻⁴ example considers how a large inference-only fleet could provide inference service while limiting overt-breakout exposure. These are useful comparison points, not established certification thresholds for this prototype. The last three columns divide each calculated ratio by the comparison value: a result below one is below that value, and a result above one is above it.

*Conditional calculations under the stated access assumptions—not measured training rates or certified residual training factors.*

| Scenario | Assumed operation rate `T` | Calculated `φ_proxy` | `φ_proxy / 0.01` | `φ_proxy / 0.001` | `φ_proxy / 0.0001` |
| --- | ---: | ---: | ---: | ---: | ---: |
| Matrix arithmetic through tokens | 100,362/s | 0.0000158 | 0.00158 | 0.0158 | 0.158 |
| Full use of five dynamic multipliers | 250,000,000/s | 0.0394 | 3.94 | 39.4 | 394 |
| Full use of all 76 mapped multipliers | 3,800,000,000/s | 0.598 | 59.8 | 598 | 5,980 |
| Dynamic operations in the 128-position decode schedule | 5,239,482/s | 0.000825 | 0.0825 | 0.825 | 8.25 |
| Replace accepted weights, keeping the 128-position decode schedule | 75,124,542/s | 0.0118 | 1.18 | 11.8 | 118 |

The token-interface figure is about **633× below 0.01, 63.3× below 0.001, and 6.33× below 0.0001**, for the particular matrix-encoding method it bounds. This does not certify a whole-chip factor below 10⁻⁴. The five-multiplier and 76-multiplier figures assume access we do not know how to obtain. The dynamic-work schedule figure, 0.000825, assumes both useful access and a limit on execution that we have not proved. The weight-replacement figure, 0.0118, is above 0.01 and assumes successful defeat of weight checks plus useful forward passes at the unchanged rate; neither capability has been demonstrated.

These numbers compare assumed training capacity **for the same amount of inference service**. A ratio of 0.0394 does not mean one board has 3.94% of an H100's arithmetic throughput. Nor does a row above a target show an attacker can exceed it: the row may assume capabilities the attacker cannot obtain. A low result for one scenario likewise does not prove a limit on all attacks.

### GPU performance headroom and sensitivity

The measured **1.018 million/s** shows that this GPU workload can run at least that fast, not that it cannot run faster. Increasing the compiled batch from 8,192 to 32,768 improved throughput by only about 2.1%. Larger batches stopped helping much in this implementation; that does not show the hardware has reached its limit.

The calculator includes two idealized limits for independent FP16 caches at 128 positions:

- **Arithmetic alone:** `989e12 / 11,488,768 = 86.08 million evaluations/s`, ignoring memory and every cost outside the counted matrix operations.
- **K/V memory traffic alone:** reading each K and V element once takes `2 × 6 × 2 × 64 × 128 × 2 = 393,216 bytes` per sequence-step: K and V, six layers, two K/V heads, 64 coordinates per head, 128 positions, and two bytes per element. At NVIDIA's peak 3.35 TB/s, that gives `3.35e12 / 393,216 = 8.52 million evaluations/s`, ignoring extra copies, writes, weights and other traffic.

| GPU reference | Evaluations/s | Multiple of measured rate | Five-multiplier `φ_proxy` | 76-multiplier `φ_proxy` |
| --- | ---: | ---: | ---: | ---: |
| Measured FP16 performance | 1.018 million | 1.00× | 0.0394 | 0.598 |
| Ideal K/V-bandwidth limit | 8.52 million | 8.37× | 0.329 | 5.01 |
| Arithmetic-only limit, ignoring memory | 86.08 million | 84.56× | 3.33 | 50.6 |

**The idealized rows are not measurements or predictions.** When both limits apply, the smaller one—8.52 million/s—is the tighter limit. The arithmetic-only 86.08 million/s cannot also satisfy that bandwidth assumption. Adding the arithmetic and memory times would make the further assumption that they cannot overlap. These models also assume no cache sharing between sequences or cache compression.

At the measured speed, the counted matrix work amounts to **1.18% of peak arithmetic**, and the minimum K/V traffic to **11.95% of peak bandwidth**. These are not measurements of how busy the GPU was. Actual work includes other operations, and actual memory traffic may include extra cache copies. The saved autotuning logs time individual matrix-multiplication candidates, not the whole program. Avoiding K/V expansion for grouped-query attention might help, but we have not measured its cost or the speedup from removing it.

If a new GPU implementation were 3× or 6× faster, the five-multiplier ratios would be **0.118 or 0.236**, and the 76-multiplier ratios **1.79 or 3.59**. We are not predicting those speedups. The 76-multiplier ratio reaches 1 at `R = 1,701,849/s`, **67.2% above our measurement**. These comparisons show that the estimates depend strongly on GPU performance; they still do not establish that anyone can use the multipliers as assumed.

A faster FPGA lowers the ratios when we hold the assumed training-operation rate fixed. In the two schedule-based scenarios, FPGA speed cancels for a matched workload or a uniform speedup across workloads; it does not generally cancel when the numerator and inference rating use different workloads. The [JSON results](evidence/training-capacity-estimates.json) reproduce the 128-position calculations while keeping the measured GPU rate as the default. The architecture calculator separately reproduces the longer-workload examples above.

## What remains to establish

To give the chip a defensible residual training factor rating, we would need comparable peak inference ratings and a justified limit on useful training computation under a clearly stated attack model. That work must account for precision, execution timing, memory access and any computation required on another machine. Counting internal multiplications is not enough: an attacker would also have to control the needed inputs and recover useful results.

The paper's certified factor `φ` governs exposure in an overt breakout, when attackers need not hide their actions. Its separate covert-evasion factor `φ_E` could be smaller if the most effective GEMM-laundering channels required physical tampering that would be evident to inspectors. We assign neither a certified `φ` nor a separate `φ_E`. Our [formal checks](FORMAL-STATUS.md) prove specific digital interface/controller properties; they do not prove resistance to physical tampering or that an inspector would detect modifications.

The separately supplied protected prototype checks K/V integrity and freshness before use, as described in [KV-PROTECTION.md](KV-PROTECTION.md). This protection is absent from the baseline analyzed numerically here. Neither of those two versions encrypts K/V; the separate [encrypted-memory version](ENCRYPTED-MEMORY.md) adds that mechanism using public demonstration keys. Cache integrity alone does not prove that the token interface is the only remaining way to misuse the chip.

The present result is a working restricted inference circuit, some machine-checked properties, and reproducible calculations about explicitly assumed attacks—not a demonstrated training attack or a certified whole-chip training limit.

## Reproduce the calculations

From the package root (the directory containing this file), using Python 3.12 and no extra dependencies:

```sh
python3.12 -I -S -B tools/estimate_training_capacity.py --check
python3.12 -I -S -B tools/architecture_work_counts.py --check
python3.12 -I -S -B tools/check_h100_reference.py
python3.12 -I -S -B tools/estimate_training_capacity.py --reference-tps 1000000 10000000
python3.12 -I -S -B -m unittest discover -s tools -p test_training_capacity.py -v
python3.12 -I -S -B -m unittest discover -s tools -p test_architecture_work_counts.py -v
```

The JSON records source hashes, inputs, assumptions, the selected GPU measurement and unrounded results. `--reference-tps` lets a reader try other GPU speeds; it does not label them as measurements. These tests check the arithmetic and saved evidence, not physical security. They do not start a GPU job.
