# Conditional training-capacity assessment

This assessment applies to the SimpleStories-V2-5M baseline with authenticated
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

## Selected implementation and workload

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

For an assumed useful training operation rate `T`, reference inference rate
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
full precision. The comparison targets 0.01,0.001 and0.0001 are illustrative paper values,
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
