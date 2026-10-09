# Architecture, arithmetic mix and conditional training capacity

This note explains how the scheduled-operation calculation in
[TRAINING-CAPACITY.md](TRAINING-CAPACITY.md) depends on model architecture and
workload. It separates three quantities: the model's arithmetic mix, the
implementation's use of its arithmetic units, and the reference GPU's throughput.

In brief:

- At the measured 128-position workload, the scheduled estimate is about
  **7% credited dynamic work × 1.18% reference arithmetic efficiency = 0.000825**.
  Both factors matter; this is not an architecture-only result.
- The roughly 48-fold gap to the every-clock estimate is a different comparison:
  the counted operations use **2.10% of the five multipliers' cycle capacity**.
- Context and workload matter. FPGA speed cancels only for a matched workload
  or a uniform speedup across workloads. For Llama 405B, attention's share of
  matrix work rises from 0.131% at 128 positions to 25.10% at 32,768.

The formulas and Llama examples below are **derived work counts, not measured
training rates or certified residual training factors**. Assuming that an attacker can
obtain useful inputs and results from internal operations does not establish
that such access is possible. The frozen-design interpretation and access
assumptions in the main capacity document remain unchanged.

Following the paper, φ denotes the residual training factor. The expressions
`φ_schedule` and `φ_every_clock` below are conditional proxies for it, not
certified ratings.

Here, a **dynamic multiplication** has two runtime-computed operands, rather
than a runtime activation and a fixed model coefficient. **Cached decode**
processes one new position using previously computed keys and values (K/V).
**Prefill** processes a prompt or a new chunk of it. A multiply–accumulate
(MAC) is a multiplication followed by an addition, counted as two operations.

## Why scheduled work and every-clock capacity differ

The two scenarios grant different capabilities:

- **Scheduled operations:** useful arithmetic only when the unchanged model
  schedule performs the counted dynamic operations.
- **Every-clock operation:** useful arithmetic from all five counted multiplier
  instances on every clock, including times when inference normally uses them
  for other roles or leaves them idle. This assumes that scheduling and data
  movement no longer prevent their continuous use.

At 128 input positions, the FPGA calculation credits 801,272 MAC-equivalent
operations per decode. Five continuously productive multipliers would provide
38,232,406.25 operations over the measured 0.152929625-second decode. The former
is 2.10% of the latter, explaining the approximately 48-fold difference.
This is not the dynamic fraction of the model's arithmetic, nor a measured
utilization trace. It compares counted work with available multiplier-cycle
capacity. The remaining time includes fixed-coefficient work, other stages,
waits and host overhead.

The difference is not an established security advantage. The scheduled scenario
requires a justified limit on the work an attacker could trigger, including
prefill, partial execution and cancellation. We have not proved that limit.

## When FPGA speed cancels

Let `C_dynamic` be credited dynamic operations per workload unit, `F` the
inference-only system's workload units per second, `R` the reference system's
corresponding rate, and `P_ref` its rated training-arithmetic throughput. For a
multi-GPU reference, use the whole reference cluster's rate and arithmetic
rating, not its aggregate rate divided by one GPU's rating.

A workload unit can be one cached decode or one whole prompt block. If both
sides use the **same workload**, and the assumed schedule restricts useful
training arithmetic to `C_dynamic * F`,

```text
φ_schedule = (C_dynamic * F / P_ref) / (F / R)
           = C_dynamic * R / P_ref
```

Making FPGA inference twice as fast also makes the counted operations available
twice as fast: **slow FPGA inference does not make this matched-workload ratio
smaller**. This also assumes the execution restriction; we have not established
that an attacker must respect it.

### Different workloads do not generally cancel

The paper defines the numerator using peak training throughput, while rating
inference at a standardized context. Suppose `w0` is the inference-rating
workload and `w` ranges over workloads an attacker could run. Under the same
hypothetical access assumption, the schedule-based expression becomes

```text
φ_schedule_peak = max_w [C_dynamic(w) * F(w)] * R(w0) / (P_ref * F(w0))
```

A uniform speedup across workloads still cancels. A change in their relative
speeds does not. Establishing the maximum would require a justified execution
bound, including prefill, partial execution, cancellation, replay and the
costs of preparing and repeating workloads.

The following examples keep the inference comparison fixed at the packaged
128-position decode and H100 reference. The counts come from the formulas
below; elapsed times come from the saved
[selected baseline measurements](evidence/baseline-current/metrics.json).

<!-- architecture-workload-table:start -->
| Recorded workload | Credited dynamic operations | Time (s) | Credited rate (million/s) | Proxy using the 128-position inference comparison |
| --- | ---: | ---: | ---: | ---: |
| `around128`, last STEP: 128-position decode | 801,272 | 0.1529 | 5.239 | 0.000825 |
| `prefix128`, last STEP: 255-position decode | 1,581,560 | 0.2205 | 7.172 | 0.001129 |
| `prefix512`, first STEP: 512-token prefill | 814,215,680 | 106.0744 | 7.676 | 0.001208 |
| `prefix128`, first STEP: 128-token prefill | 52,559,360 | 12.3586 | 4.253 | 0.000669 |
<!-- architecture-workload-table:end -->

These are single host-timed intervals, not sustained peak measurements. The
prefill counts credit the named operations across the prompt, with final
normalization counted only for the final logits. They do not establish useful
attacker access, the overhead of repeating an attack, or a peak training rate.
The two longer-workload examples exceed the paper's illustrative 0.001 under
these assumptions; that is **not evidence of an attack achieving that factor**.
Nor does the 128-position estimate of 0.000825 establish a limit for other
workloads. We do not extrapolate these rates to full context. The
[full-window measurements](KV-PROTECTION.md#measured-performance) are separate
observations and do not turn the fixed-context estimates into universal limits.

## Reference performance does not cancel

For the matched-workload calculation and any consistent total-work count
`C_total`,

```text
rho = C_dynamic / C_total
eta_ref = C_total * R / P_ref
φ_schedule = rho * eta_ref
```

`rho` describes the arithmetic mix. `eta_ref` describes counted useful model
work per second relative to the reference's arithmetic rating; it is not a
profiler measurement of occupied GPU units. It depends on the workload,
implementation, precision, batch size and memory traffic.

To recover the released FPGA's scheduled row, count its credited gate products
and RMSNorm squares in both numerator and denominator:

```text
C_dynamic  = 801,272
C_total    = 11,488,768 matrix operations + 14,840 other credited operations
           = 11,503,608
rho        = 0.06965397
eta_ref    = 0.01184148
φ_schedule = 0.000824806
```

These use the packaged H100 rate, 1,018,047.545 evaluations/s, and the recorded
989e12 operations/s reference rating. The main document's matrix-only efficiency
figure is 1.1826%; including the 14,840 credited operations makes it 1.1841%.
The bookkeeping difference changes neither the measurement nor `φ_schedule`.
The square/product credits are allowances, not measured useful training work.

Thus the small proxy combines roughly **7% credited dynamic work with 1.18%
effective reference arithmetic throughput**. It is not an architecture-only
number. A faster reference increases it. The GPU/FPGA numerical differences and
other comparison limitations in [TRAINING-CAPACITY.md](TRAINING-CAPACITY.md)
still apply.

For comparison, write `T_peak` for the five units' credited every-clock rate
and `u_dynamic = C_dynamic * F / T_peak`. Then
`φ_every_clock = φ_schedule / u_dynamic` for this same workload.
Here `u_dynamic` is approximately 0.02096. This is a separate
implementation-dependent quantity, not `rho` or `eta_ref`.

### Relation to the paper

*The Feasibility of a Hardwired Pause of Frontier AI Training* distinguishes
having dynamic attention arithmetic from letting an attacker supply chosen
operands and recover useful results. Its discussion of GEMM laundering asks
whether fixed internal routing can prevent that access, including indirect
paths through other operations. Our scheduled scenario assumes useful access;
the arithmetic counts do not show how to obtain it.

The paper also discusses how much inference arithmetic could become training
capacity if attention were commandeered. The `rho_attn` below quantifies
attention's share of **counted matrix work**, not every operation performed by
the hardware. That share depends on architecture and workload: for Llama 405B,
the paper's “tens of percent” description applies at long contexts, not all
contexts. Turning the share into a residual training factor estimate also requires reference
performance and justified access and execution assumptions.

The weight-replacement scenario in [TRAINING-CAPACITY.md](TRAINING-CAPACITY.md)
credits all counted matrix work under its separate, unproved assumptions. In
that matrix-only bookkeeping, `rho = 1`, so its matched-workload estimate
equals the matrix-only `eta_ref`, approximately 0.0118. This identity does not
establish that replacing weights makes every counted operation useful for
training.

## General useful-work counts

The following derivation covers ordinary causal, full-context grouped-query
attention (GQA) and gated SwiGLU feed-forward layers. All layers are assumed
to have the same geometry. It is not a formula for every possible transformer,
linear-attention model or hardware implementation.

| Symbol | Meaning |
| --- | --- |
| `d_model`, `d_ff`, `d_head` | Model width, feed-forward intermediate width per expert, head dimension |
| `H_q`, `H_kv` | Query-head and K/V-head counts |
| `n_layers`, `n_vocab` | Layer count and vocabulary size |
| `B` | Number of equal-length independent sequences in the batch |
| `n_new`, `n_cached` | Newly processed positions per sequence and preceding cached positions |
| `n_logit` | New positions for which vocabulary logits and final RMSNorm are evaluated |
| `E_total`, `E_active` | Total routed experts and active experts per token; dense layers use `E_total = 0`, `E_active = 1` and no router |

Count one matrix MAC as two operations. Input embedding is a lookup, not a
second vocabulary matrix multiplication. The output head is counted even when
its weights are tied to the input embedding.

Each new position attends to the cached prefix and itself and its earlier new
positions. The useful query-key position pairs per sequence are

```text
pairs = n_new*n_cached + n_new*(n_new+1)/2
n_att = pairs/n_new = n_cached + (n_new+1)/2
```

The fixed-weight projection MACs per layer and new position are

```text
W = 2*d_model*(H_q + H_kv)*d_head + 3*E_active*d_model*d_ff + router_MACs
router_MACs = d_model*E_total for a standard linear MoE router, otherwise 0
```

The first term counts Q/K/V and output projections; the second counts the three
SwiGLU projections in each active expert. The total useful matrix-operation
counts for the batch are

```text
C_attn  = 4*B*n_layers*H_q*d_head*pairs       # Q*K^T and A_softmax*V
C_fixed = 2*B*(n_new*n_layers*W + n_logit*d_model*n_vocab)
C_matrix = C_attn + C_fixed

head_MACs_per_layer_position = n_logit*d_model*n_vocab / (n_layers*n_new)
rho_attn = C_attn / C_matrix
         = 2*H_q*d_head*n_att / (W + 2*H_q*d_head*n_att + head_MACs_per_layer_position)
```

Here `rho_attn` is specifically the **attention share of matrix arithmetic**.
`n_att` is the average number of attended positions per newly processed position.

- **Cached decode:** `n_new = n_logit = 1`, `n_cached = n - 1`, so `n_att = n`,
  including the current position in the attended context.
- **Fresh causal prefill:** `n_cached = 0`. When only the next-token prediction is
  needed, use `n_logit = 1`; use `n_logit = n_new` if all positions' logits are
  evaluated.
- **Chunked prefill:** retain both `n_cached` and `n_new`. The formula includes
  attention to the cached prefix and within the new chunk. A non-final chunk
  that needs no logits uses `n_logit = 0`.
- **Batch size:** `B` cancels from the work fraction, but can strongly change
  `eta_ref`. For unequal lengths or layer geometries, sum the applicable work
  counts before taking the ratio; do not average percentages unweighted.
- **Depth and head geometry:** `n_layers` cancels between the transformer-layer
  terms, but not the final head; that head matters more in the tiny model.
  At fixed `H_q*d_head = d_model`, changing the query-head count alone does not
  change the attention MAC count. Reducing K/V heads reduces projections and
  cache storage, not attention's count by a factor `H_kv/H_q`: every query head
  still attends.

### Mixture of experts and other runtime arithmetic

Total experts `E_total` and active experts `E_active` are distinct. With fixed
expert widths and fixed `E_active`, increasing `E_total` primarily increases
stored weights rather than the main per-token feed-forward work; the router
still scales with `E_total`. A standard top-k MoE also combines expert outputs
using runtime router weights.
That combination is additional dynamic arithmetic. This is the routing pattern
described in [Mixtral of Experts, Section 2.1](https://arxiv.org/html/2401.04088v1).

For the named gate and square channels counted in the FPGA document, an
additional MAC-equivalent allowance is

```text
C_gate_norm = 2*B*(n_layers*n_new*E_active*d_ff
                  + (2*n_layers*n_new + n_logit)*d_model)
C_mix = 2*B*n_layers*n_new*E_active*d_model  # weighted MoE output combination only
```

This counts each scalar gate product or square as a full MAC, as the main
capacity document does. Add these allowances to both numerator and denominator
if reporting their share of the combined counted work. They are **not a complete
count of every runtime operation**: softmax, activation functions, normalization
scaling and their implementation details require separate treatment. The `n_logit`
term assumes final normalization only where logits are needed. An implementation
that normalizes every position executes more work.

Shared experts, partially MoE layer stacks, alternative routing, sliding windows
and other architectures need their own counts. Nor does having `E_total` experts
imply `E_total` physical compute engines: the every-clock scenario requires the
actual hardware inventory and scheduling, not just the model configuration.

## Llama 3.1 405B example

Use the dense, eight-K/V-head configuration: `n_layers = 126`, `d_model = 16,384`,
`d_ff = 53,248`, `H_q = 128`, `H_kv = 8`, `d_head = 128`, and `n_vocab = 128,256`.
The layer dimensions come from [Meta's Table 3](https://arxiv.org/html/2407.21783v3);
the exact vocabulary and configuration are recorded in
[Meta's configuration definitions](https://github.com/meta-llama/llama-models/blob/0e0b8c519242d5833d8c11bffc1232b77ad7f301/models/sku_list.py).
This calculation does not use the 16-K/V-head model-parallel configuration.

The table is our derivation, **not a Llama GPU benchmark or a residual training factor
rating**. It counts useful attention and fixed-weight matrix work, including
the output head. Prefill is a fresh causal prompt with only its final logits
evaluated; decode attends to the stated number of positions, including itself.

<!-- architecture-work-table:start -->
| Context/prompt length | Decode attention share | Causal prefill attention share |
| ---: | ---: | ---: |
| 128 | 0.131% | 0.066% |
| 2,048 | 2.05% | 1.04% |
| 8,192 | 7.73% | 4.04% |
| 32,768 | 25.10% | 14.41% |
| 131,072 | 57.27% | 40.25% |
<!-- architecture-work-table:end -->

At 8,192 positions, for example, a decode has 67,645,734,912 attention operations
and 807,495,794,688 fixed-weight matrix operations: a 7.73% attention share.
For this attention channel, `φ_schedule = 0.0773 * eta_ref`, approximately.
Computing an actual proxy requires a suitable reference's measured or rated
throughput for the specified workload and precision. We have not benchmarked
Llama 405B here. Setting `eta_ref = 1` is an arithmetic-only normalization, not
a measured performance claim. For example, at this context, reaching a
conditional estimate of 0.01 would require `eta_ref` of about 12.9%; reaching
0.001 would require about 1.29%, still assuming useful access to the counted
attention work. Neither is a claim about measured Llama inference performance.

Fresh causal prefill averages `(n + 1)/2` attended positions, whereas decode
at context `n` attends to all `n`. This explains its lower share of useful
attention work, but not necessarily a lower residual training factor estimate: prefill and
decode can have very different reference efficiencies, especially at different
batch sizes. A training-utilization figure is not a substitute for an inference
measurement at the relevant workload.

For comparison, the tiny model's attention share is 6.85% at 128 positions
and 54.04% at 2,048. At the same 128-position context, its share is **larger**
than Llama 405B's 0.131%, not unusually small. Its small scheduled estimate
combines this arithmetic mix with the measured reference's low efficiency;
that efficiency must not be transferred to Llama 405B. The 2,048-position
figure is an architecture count, not physical qualification at that context.
A short-context result is not a bound for long-context operation.

## What these counts do not establish

These are mathematical useful-work counts. A security analysis must count
**actually executable** work, including padded products, masked-out attention
products, extra passes or duplicated computations. A prefill implementation
that evaluates a whole masked rectangle has more products than the useful
causal triangle counted above.

The hardware inventory, memory bandwidth, attainable clocks and attainable
attacker I/O remain separate questions. A fraction of arithmetic is not a
fraction of chip area or power. None of these equations establishes useful
attacker access or a limit on all software commands, physical modifications,
workloads, partial operations or replay patterns. The every-clock and
schedule-restricted scenarios must remain separate assumptions.

The formulas also do not make integer/block-floating-point and FP16/BF16
operations equally useful for training. A certified comparison would require
justified numerical and workload equivalence, an appropriate reference rating,
and a verified attack-model bound. For prefill, use the same workload unit on
both systems—input positions or whole prompt blocks—not an input-token rate on
one side and a decode-token rate on the other.

## Reproduce the arithmetic

The [offline calculator](tools/architecture_work_counts.py) reproduces both
tables and exposes the general count function for Python callers. It needs only
Python's standard library and does not download weights, run inference or
access hardware.

```sh
python3.12 -I -S -B tools/architecture_work_counts.py
python3.12 -I -S -B tools/architecture_work_counts.py --check
python3.12 -I -S -B -m unittest discover -s tools -p 'test_architecture_work_counts.py' -v
```

Tests compare the tiny-model counts with the existing capacity calculator,
check batched MoE, nonstandard head geometry and chunked-prefill accounting,
and check that both tables match the computed values and packaged measurements.
They also test the command-line checks and malformed inputs. They verify
arithmetic and evidence consistency, not training access.
