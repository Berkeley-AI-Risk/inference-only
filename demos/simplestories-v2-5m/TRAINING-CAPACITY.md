# Residual training capacity of SimpleStories-V2-5M

Our primary case is the board-tested **K/V-protected F-AWIC**. The question
is how much useful training computation someone with the chip can obtain per
unit of inference service. The answer depends on what they can control and
what results they can recover. The chip's physical-owner residual training
factor remains open. The [plain-cache baseline](#plain-cache-baseline) is a
separate worked comparison.

## K/V-protected greedy design

The 25 MHz Tang Mega image `90ac6815…` authenticates its weights and keeps
trusted on-chip digests for the attention keys and values it writes to
external memory. When a historical row is read back, the guard checks its
contents and context before releasing the checked copy. Under the fixed-circuit,
trusted-state and hash-resistance assumptions, changing the external bytes
alone cannot supply an arbitrarily chosen row through that path. The cache
is plaintext on this image. The component proofs and corruption tests state
which paths have been checked. A full proof from the original writer to the
matching attention operation remains open. [Board image](prebuilt/kv-protected/BUILD.json) ·
[K/V protection](KV-PROTECTION.md) · [Guard replay](simulation/kv-protected/README.md) ·
[Formal scope](formal/authentication-access/README.md)

### The measured inference comparison

At **128 occupied positions**, the last STEP in two protected-board trials
took **0.169531958 s** and **0.169748334 s**. Both returned the expected token
85. Pooling the two request/reply intervals gives **5.89483 evaluations/s**.
The board's **7.03 cached tokens/s** headline averages generation across
growing contexts and answers a different performance question.
[Trial 1](benchmarks/fpga-speed/captures/protected-common-speed-20261026-r1/trial-1.json) ·
[Trial 2](benchmarks/fpga-speed/captures/protected-common-speed-20261026-r1/trial-2.json) ·
[Benchmark definitions](GREEDY-QUALIFICATION.md#common-speed-workload)

The published H100 comparison is **2,951,332.87 evaluations/s** for the FP16
parent model at context 128, in a batch of 32,768. The FPGA runs integer
arithmetic on a single feedback-dependent tape. The GPU uses different
histories and a different timing boundary. Its acceptance policy permits
logit differences and recorded 61 greedy-token disagreements with eager
FP16 in 32,768 comparisons. We use the rate ratio as an illustrative
denominator. The licensed inference rating has yet to be established.
[H100 benchmark](../../docs/benchmarks/H100-BENCHMARK.md) · [Reference data](../../evidence/qwen-h100-2026-10-25/computed-results.json)

Under the published convention of 989 trillion dense operations/s per H100,
the comparison implies the following budget for **φ below 0.001**. Here
`T` means useful training operations per second obtainable from the device.

```text
F = 2 / (0.169531958 + 0.169748334) = 5.89483 evaluations/s
R = 2,951,332.87 evaluations/s
φ_proxy = T / (989e12 × F/R)
φ_proxy < 0.001 requires T < 1,975,374.57 useful operations/s (rounded)
```

**1.98 million operations/s is the threshold to beat under this comparison.**
The two measured inference rates set that threshold. How much useful training
work a person with the chip can actually obtain remains unknown. Certifying a
physical-owner bound requires an upper bound on that work across all access
paths and a justified inference rating.
[Rating methodology](../../docs/analysis/RESIDUAL-TRAINING-METHODOLOGY.md)

### What changes with access?

| Assumption | Consequence for the protected image |
| --- | --- |
| **Only ordinary tokens, with both dense input matrices and their product explicitly represented on one tape.** | The completed-command wire limit gives at most about **40,145 useful ops/s** for this method, or **0.0000204** as a rounded-up proxy ceiling. This grants correct products and omits inference time. Other computations expressed through prompts need their own analysis. |
| **The operator can read or alter external K/V memory while the circuit remains fixed.** | An altered or stale record must pass the guard's integrity and freshness checks before use. The contents of authentic plaintext records can still be observed. The evidence gives no aggregate training rate for this access assumption. |
| **Every counted dynamic operation in a normal context-128 decode is useful for training.** | Crediting 801,272 operations per decode at the protected board rate gives **4.72 million ops/s**, or **0.00239**. This assumes useful operands and results throughout and a restriction to this schedule. The observed decode rate does not establish those assumptions. |
| **The operator can obtain one useful multiply–accumulate internally every 25 core clocks.** | Crediting two operations per MAC gives **2.00 million ops/s**, or **0.001012**. This illustrates how much sustained access would matter. The chip measurements have not demonstrated such access. |

The token calculation grants one 16-bit entry per token. With 2,049 tape
slots the explicit square-matrix method gets at most
`(2/3) × sqrt(2049/3)` operations per entry. Each successful input or output
command needs a reply on the same transmitter. At 25 MHz, 217 clocks per bit,
ten serial bits per byte and five bytes per frame, at most 2,304.15 such
replies fit in a second. The dynamic-operation case uses the published model
work count. The rows describe alternative assumptions and must not be added.
[Token interface and UART](HARDWARE.md) · [Protected UART source](variants/kv-protected/hardware/project/uart_core.sv) ·
[Model work counts](../../docs/analysis/ARCHITECTURE-DEPENDENT-CAPACITY.md)

The assessment assumes the FPGA configuration is frozen. A stock FPGA can
be reprogrammed. Rating a fixed die requires evidence about its production
interfaces and physical access. The **0.88745** registered-arithmetic result
belongs to the plain-cache image and its mapped arithmetic paths. It bounds the credits assigned to register updates on those paths under
the baseline comparison. Useful training throughput requires separate evidence. [Baseline registered-credit calculation](analysis/registered-credits/README.md)

## Plain-cache baseline

The following comparison applies to the SimpleStories-V2-5M baseline with authenticated
weights and without K/V integrity protection, image
`01b040cb830cd4c5343f0666568213d433442c6937e711751a79847d492b4a57`.
Its [implementation](HARDWARE.md), [qualification](GREEDY-QUALIFICATION.md),
[mapped census](evidence/current-greedy/baseline/analysis/mapped-census.json)
and [timings](evidence/current-greedy/baseline/analysis/metrics.json)
bind the inputs. Other hardware configurations require their own assessment.

The question is how much useful training arithmetic an adversary could obtain
per unit of inference service. The calculations below grant explicit,
hypothetical capabilities. **No general training interface or attack is
demonstrated, and no whole-device residual training factor is certified.**
The [shared methodology](../../docs/analysis/RESIDUAL-TRAINING-METHODOLOGY.md)
separates software token access, memory tampering, internal-circuit access,
weight-enforcement compromise and changes to the hardware.

### Baseline implementation and workload

The selected mapped circuit contains **87 `MULTALU27X18` and three `MULT12X12`
instances**, reported by the vendor as **88.5 DSP blocks**. These are different
counting conventions. The census classifies **19 instances with two runtime
operands in named scheduled roles**: eight attention-score, eight
attention-value, one feed-forward elementwise and two RMSNorm instances.
An instance can serve fixed-operand roles in other phases. Runtime operands
are values produced during inference; they are not independently programmable
attacker inputs. These observations establish neither a useful simultaneous
rate nor synthesis correctness or attacker access.

The nominal inference clock is **25 MHz**. The capacity comparison uses one
output evaluated at **128 input positions**, including 127 cached positions.
The two matching trial intervals are **0.101706167 s** and **0.101874708 s**;
pooling them gives **9.82410553 outputs/s** at this fixed context. The
[common headline benchmark](../../docs/benchmarks/FPGA-SPEED-BENCHMARK.md)
measures cached generation across growing contexts using the complete 128-output
sequences. Each quantity retains its workload and timing boundary.

<!-- capacity-reference:start -->
The selected GPU reference is the FP16 parent model with Transformers **5.17.0**,
at about **2.95 million evaluations/s**, batch **32,768**,
at the same 128-position geometry. Its stated all-logit tolerance policy
passes with **61/32,768 greedy disagreements** against eager FP16;
this is not exact-token agreement. The selected case, source snapshots and
all 897 archived payload files are checked by the shared reference reader.

The older Transformers **4.48.3** campaign measured about
**1.02 million evaluations/s**. Its measured result and the corresponding
conditional scenarios are retained as a reference-performance sensitivity
in [the calculation record](evidence/training-capacity-estimates.json), not
as the current reference. Neither GPU implementation evaluates the FPGA's
integer function bit for bit. The [H100 report](../../docs/benchmarks/H100-BENCHMARK.md)
states both campaigns' numerical acceptance and timing boundaries.
<!-- capacity-reference:end -->

## Access assumptions and arithmetic

For this plain-cache baseline, with an assumed useful training operation rate `T`, reference inference rate
`R` and FPGA inference comparison rate `F`, the illustrative proxy is:

```text
φ_proxy = (T / 989e12) × (R / F)
```

The 989e12 reference is a dense arithmetic specification, not a measurement of
training throughput. Counting an FPGA integer multiplication as a full useful
multiply–accumulate credits two operations even when the source role supplies
only a product or square. This favors the hypothetical attacker and does not
establish equivalent numerical precision or usefulness for training.

The scenarios overlap and must not be added:

<!-- capacity-scenarios:start -->
| Scenario | Assumed operation rate `T` | Calculated `φ_proxy` | `φ_proxy / 0.01` | `φ_proxy / 0.001` | `φ_proxy / 0.0001` |
| --- | ---: | ---: | ---: | ---: | ---: |
| Explicit matrix I/O through tokens | 100,362/s | 3e-05 | 0.003 | 0.03 | 0.3 |
| Full useful access to 19 scheduled runtime-operand units | 950,000,000/s | 0.29 | 29 | 2.9e+02 | 2.9e+03 |
| Full useful access to all 90 mapped multipliers | 4,500,000,000/s | 1.4 | 1.4e+02 | 1.4e+03 | 1.4e+04 |
| Named dynamic work on the fixed 128-position decode schedule | 7,871,781/s | 0.0024 | 0.24 | 2.4 | 24 |
| Chosen accepted weights, same decode schedule | 112,866,869/s | 0.034 | 3.4 | 34 | 3.4e+02 |
<!-- capacity-scenarios:end -->

Displayed proxies are rounded; the calculation record retains
full precision. The comparison targets 0.01, 0.001 and 0.0001 are illustrative paper values,
not certification thresholds. The source and all computed quantities are in
[the calculation record](evidence/training-capacity-estimates.json).

### Explicit matrix arithmetic through tokens

Assume the model can multiply matrices represented in its token tape, and
charge only communication time. This capability has not been demonstrated.
For tape capacity `L`, with one two-byte matrix entry credited per token,
explicit dense matrix I/O gives:

```text
T_token <= (2/3) × sqrt(L/3) × r
L =2,049
r <=2 ×25,000,000 / (217 ×8 ×5) =5,760.37 tokens/s
T_token <=100,362 operations/s
```

The tape count includes the final output slot. The UART uses 217 clocks per
bit and five bytes per token frame. The rate credits both directions at once,
counts only eight data bits per byte, and omits framing, acknowledgements and
model computation. The vocabulary carries less than 12 bits per token, while
this allowance grants 16. This is a loose communication allowance for this
particular explicit-matrix method; it does not bound every computation
obtainable from legitimate prompts.

### Useful access to internal multipliers

The 19-unit scenario grants complete useful input/output access and one MAC
per unit per clock, giving `2 ×19 ×25e6 =950e6` credited operations/s.
The 90-unit scenario extends that grant to every mapped multiplier, giving
`2 ×90 ×25e6 =4.5e9` operations/s. Both grant control and throughput that
have not been demonstrated.

Changing external K/V can affect attention inputs and expose transformed
results through later stored activations. It does not by itself expose
independently chosen queries, attention coefficients or raw products, or make
the elementwise and normalization units callable. Weight projections use fixed,
authenticated coefficients. Physical circuit editing would additionally need
usable input/output connections, accumulation, scheduling and data movement
at the assumed rate. We have not established a feasible modification achieving
these grants. These scenarios also omit other possible uses of logic outside
the counted multiplier instances, so they are not whole-chip tamper bounds.

An optional [registered-route worked example](analysis/registered-credits/README.md)
uses the frozen 25 MHz source and mapped inventory to account for registered
numerical and address sinks. The example bounds how many arithmetic operations
these register updates can credit. A whole-device bound would also have to
account for other ways to compute. The example supplies separate recorded
and full regeneration commands and keeps its frozen source inputs explicit.

### Fixed-schedule allowances

One 128-position decode has **801,272 credited dynamic operations** in the
model work count. Crediting that work at the measured fixed-context rate gives
about **7.872 million operations/s**. This scenario assumes useful attacker
access and a complete, immutable execution restriction that prevents more
work, faster execution or alternative workload advantages. **That restriction
has not been proved.** The [architecture analysis](../../docs/analysis/ARCHITECTURE-DEPENDENT-CAPACITY.md#different-workloads-do-not-generally-cancel)
shows why different context lengths and prefill workloads require separate
accounting.

The weight-compromise scenario grants chosen accepted weights and credits
**11,488,768 dominant matrix operations** per decode at the unchanged rate,
about **112.867 million operations/s**. It assumes defeat of hardware weight
acceptance and useful result recovery, while ignoring replacement/restart
costs. No such enforcement failure or usable general-model service is
established. It is not an application command in the released interface.

When the same counted work determines both the assumed training allowance and
inference rate, `F` cancels algebraically from the proxy. A speedup alone then
leaves that matched-workload ratio unchanged. Other workloads can have
different work mixes and relative speeds; the maximum requires additional
analysis and a justified execution restriction.

## Limits and reproduction

These calculations assume a frozen circuit. They do not certify resistance
to FPGA reprogramming, physical replacement, probing or fault injection.
The [formal-status guide](FORMAL-STATUS.md) identifies the separately scoped
RTL properties and their private-service boundaries. Those proofs do not
establish the execution, access, numerical or physical premises assumed here.
A faster GPU reference increases the proxy; the measurements do not establish
a maximum reference rate. Ideal arithmetic/bandwidth roofs in the calculation
record are sensitivity models, not achieved performance or forecasts.

From the SimpleStories demo directory (`demos/simplestories-v2-5m/`), without hardware or network access:

```sh
python3 -I -S -B tools/estimate_training_capacity.py --check
python3 -I -S -B ../../tools/architecture_work_counts.py --check
```
