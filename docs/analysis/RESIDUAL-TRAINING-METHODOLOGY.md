# Method for residual training factor analysis

A residual training assessment needs two kinds of evidence: how an adversary could obtain useful training arithmetic, and how much inference service the same hardware supplies. An arithmetic inventory answers only part of the first question. GPU benchmarking supplies the inference reference; it does not demonstrate or exclude a training attack.

Use this method for each released circuit and numerical model separately. The [Qwen3 1.7B assessment](../../demos/qwen3-1.7b/TRAINING-CAPACITY.md) applies it to AWS F2. The [SimpleStories calculations](../../demos/simplestories-v2-5m/TRAINING-CAPACITY.md) retain their historical measurements and assumptions. The [October 25 shared-method H100 campaign](../benchmarks/H100-BENCHMARK.md) applies this procedure to both models and preserves its numerical acceptance failures.

## Define the quantity and rating workload

The [pause paper](https://hardwired-pause.ai/paper), sections 3.2.1 and 4.1, defines the residual training factor as a bound on peak training arithmetic in H100 equivalents divided by the licensed inference rating in inference H100 equivalents. It distinguishes runtime arithmetic from arithmetic an adversary can repurpose, and requires considering physical possession of the system.

For a single H100 reference, write:

```text
H = 989e12 dense 16-bit arithmetic operations/s, with 32-bit accumulation
T = useful training operation rate credited to a specified access scenario
F = device inference tokens/s for rating workload w0
R = single-H100 inference tokens/s for that same workload

phi_proxy = (T/H) / (F/R) = T*R/(H*F)
```

Use `phi_proxy` for conditional engineering comparisons. A certificate additionally needs a justified bound on every relevant training channel and the prescribed licensed rating procedure. The paper's illustrative `1e-4` fleet value is not a certification threshold for these prototypes.

Specify the inference task before measuring it: checkpoint, numerical operations, precision, context including the current input, batch policy, independent cache storage, output selection, timing boundary and reference hardware. A reference cluster of `N` H100 equivalents changes the denominator to `N*F/R`.

## Freeze the evaluated system

Bind the assessment to model and source hashes, hardware image/checkpoint, mapped reports, clocks, reset assumptions and measurements. List the included processors, external memory and communication paths. Account for host CPU training separately if the licensed boundary excludes it.

For these FPGA demonstrations, the assessment assumes a frozen configuration or an eventual fixed ASIC. The actual cloud platform can reconfigure the FPGA. An ASIC needs a new assessment of its layout, scan/test ports and physical exposure; FPGA resource counts do not automatically describe it.

List weight authentication, K/V integrity, encryption and freshness independently. Encryption does not establish integrity, and restricting host commands does not establish physical secrecy of external memory.

## Classify access before assigning throughput

For each proposed channel, identify both operands, their owners, possible injection points, result observations, transformations, precision, scheduling, transport cost and evidence. Use the following evidence classes explicitly:

| Evidence | What it supports |
| --- | --- |
| Demonstrated useful computation | An achieved attack rate under the tested access conditions |
| Proved execution or information bound | An upper bound within its stated system and threat assumptions |
| Arithmetic or bandwidth allowance | A conditional calculation granting access or utilization not established by the evidence |
| Unresolved channel | Further analysis; absence of a demonstrated attack is not zero capacity |

Evaluate host software control, external-memory access, internal faults/changes and reconfiguration as distinct assumptions. For each dynamic operation, follow its inputs upstream and its outputs downstream. A nonlinear or quantized observation can still leak useful information; it also need not expose a general matrix product. Treat diagnostic/status paths as observable until their exact source-to-image correspondence is resolved.

Hypothetical “all multipliers available every clock” rows are stress allowances. They do not show that the assumed access can be obtained, or bound all possible physical changes. Reconcile mapped DSP blocks with functional arithmetic: multi-block floating multipliers and DSP adders must not be counted as independent MACs.

## Count work across allowed executions

Maintain separate counts for mathematical model work, actual accepted arithmetic events and recovered useful training work. State when a square, standalone product or narrow integer operation is credited as a full dense 16-bit MAC. Count one MAC as two operations consistently.

For grouped-query attention with `l` layers, `hq` query heads and head width `d`, one cached decode at `n` occupied input positions has:

```text
C_attention(n) = 4*l*hq*d*n
```

K/V head count changes projections and cache storage; it does not replace query-head count in this attention formula. Count the vocabulary head once when logits are produced. An embedding lookup is not a second vocabulary matrix multiplication.

For `B` independent sequences, `u` new positions after `c` cached positions, a causal mathematical count uses `u*c + u*(u+1)/2` attention pairs. Projection work scales with `B*u`; vocabulary work depends on which positions need logits. A masked rectangular implementation can execute additional work. Instrument the real schedule to resolve padding, stalls, duplicated work and implementation overhead.

A peak training numerator must cover prefill, long and short contexts, cancellation, partial executions, resets and replay. For each access scenario `a`, the schedule-limited candidate is:

```text
T_a = sup over permitted workloads and command traces of
      useful credited operations / elapsed time
```

Prove an execution limit or retain this as an unresolved maximum. A normal-decode test is insufficient. Sum rates only for independent channels that can operate simultaneously; overlapping scenarios for the same units are alternatives.

## Measure the reference without changing the task

Benchmark aggregate independent-sequence service as well as batch-one latency. Sweep batch sizes until throughput plateaus or memory limits intervene; a memory limit alone does not establish peak throughput. Use an optimized attention backend with native GQA and inspect cache-copy traffic. Avoid selecting a slow reference implementation because it yields a smaller ratio.

Measure three panels separately: actual feedback-dependent generation matching the hardware campaign, fixed-context decode for the chosen rating workload, and prefill/time to first output. A repeated fixed-context step is not a stream of distinct generated tokens. A growing-context average is not a fixed-context rate.

Validate cached versus full forward, changed input, changed prefix, K and V prefix stability, replay and optimized versus eager output. Closed-loop tests must check the complete output sequence. Preserve failures and near-tie disagreements with their acceptance policy. If a separately labeled logit-tolerance reference permits greedy disagreements, retain their counts and margins and do not claim exact token equivalence. Keep continuation trajectory acceptance explicit. Test a second prompt seed and repeat selected best cases in fresh processes.

Record host-wall and device-event times, every repetition, dtype/backend, memory, GPU identity and competing processes. Include all layers, final normalization, head and selection in the timed decode. State exclusions such as compilation, warmup, prefix construction and host token delivery. Report a service-inclusive comparison separately when device and GPU timing boundaries differ.

A floating-point parent and the quantized FPGA function are different numerical models. Report prompt-level agreement as a diagnostic. A certified comparison requires the agreed numerical-function equivalence standard or a benchmark of the exact function; selected token agreement cannot prove all-input equivalence.

## Interpret the ratio and uncertainty

If credited useful work for exactly the rating workload is `T=C*F`, then `phi_proxy=C*R/H`: device speed cancels. This does not apply when an adversary can select a different workload or remove schedule restrictions. With rating workload `w0`, use `max_w T(w)*R(w0)/(H*F(w0))` instead.

A faster GPU reference increases the ratio. A faster device lowers it when `T` is fixed, but leaves it unchanged under the matched `C*F` assumption. These are different scenarios, not contradictory effects.

An achieved reference rate is evidence of achievable performance. Two measured rates and an assumed numerator do not establish a one-sided bound. If certification treats peak reference throughput as unknown, an upper bound would require consistent `T_upper`, `R_upper` and `F_lower`, giving `T_upper*R_upper/(H*F_lower)`. Alternatively, the licensed procedure can define a fixed reproducible reference score; record that convention and revision explicitly. Statistical timing uncertainty does not account for unresolved access assumptions or numerical-model differences.

Keep fleet utilization and political discounts separate from the device factor. Publish a channel table, raw evidence and source identities, reproducible counts, measured rates and acceptance policies, and a list of remaining claims requiring proof or physical audit. Reassess when the model, image, interface, clock, diagnostic exposure or measurement procedure changes.
