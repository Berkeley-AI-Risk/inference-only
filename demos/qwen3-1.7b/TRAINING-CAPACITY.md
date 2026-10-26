# Residual training capacity of Qwen3 1.7B on AWS F2

The released 100 MHz Qwen3-1.7B circuit supplies about 9 cached tokens/s in the measured short-prompt continuations. The [October 25 H100 campaign](../../docs/benchmarks/H100-BENCHMARK.md) now supplies an achieved FP16 parent-model reference: 61,655.709 fixed-context evaluations/s at 128 input positions. Its residual training factor remains unassigned because useful adversarial access has not been demonstrated or bounded for the whole system, and the parent differs from the FPGA numerical function. The calculations below are conditional engineering proxies.

Use the [shared methodology](../../docs/analysis/RESIDUAL-TRAINING-METHODOLOGY.md) for the definition, rating procedure and evidence requirements. [SimpleStories estimates](../simplestories-v2-5m/TRAINING-CAPACITY.md) use different hardware, arithmetic and measurements; its H100 rate and scoped formal proofs do not transfer to Qwen.

## Evaluated circuit and access

The pinned parent is `Qwen/Qwen3-1.7B`, revision `70d244cc86ccca08cf5af4e1e306ecf908b1ad5e`, with 1,720,574,976 unique parameters. The [hardware guide](HARDWARE.md) identifies the tested numerical model, source and implementation. The routed checkpoint SHA-256 is `e8a1143e44bdc65fd1da76d7faeac236e59c49ccd4d5ce004a3b962ce6b5c98d`; the [model source lock](model/source-lock.json) identifies the upstream data.

The assessment concerns this frozen inference circuit or an eventual fixed ASIC. AWS reconfiguration and the general-purpose host lie outside that boundary. Consumed weight pages are authenticated; K/V integrity and weight encryption are absent from this baseline.

| Access assumption | Relevant paths and remaining question |
| --- | --- |
| Host software control | APPEND, STEP and CLEAR; constrained model upload, status and lifecycle controls. No application command supplies arbitrary tensor operands or returns products. Token arithmetic and unproved command/reset behaviors still need assessment. |
| Physical access to external memory | Unauthenticated K/V can potentially be changed and later K/V writes observed. Q and softmax operands remain circuit-derived; downstream observations transform products. Whether these paths enable useful general arithmetic is unresolved. |
| Internal faults or physical changes | May defeat ownership, checks or schedule restrictions. Every-cycle allowances below assume the required useful access succeeds; they do not establish a feasible modification or success rate. |

Diagnostic exposure also needs reconciliation. The README describes a 16-bit attention-control diagnostic; the [packaged top-level source](hardware/design/cl_qwen.sv) instead assigns its 16-bit management display from lifecycle, clock, HBM and error flags. Source inspection alone does not resolve a possible checkpoint overlay. Carry this as an audit item rather than assuming either a token-only observation boundary or a tensor readout.

## Arithmetic inventory

The [mapped hierarchical report](evidence/implementation/utilization-hierarchical.rpt) and [diagram inventory](../../diagrams/qwen-hardware-architecture.inventory.json) reconcile 1,000 DSP48E2 blocks as follows:

| Functional arithmetic | Instances or product sites | DSP blocks |
| --- | ---: | ---: |
| 64 dot8 units, each with eight W8 by A16 products | 512 products | 512 |
| Two additional integer adder DSPs per dot8 | 128 adders | 128 |
| FP32 multiplication stages | 175 | 350 |
| BF16 elementwise multiplication units | 5 | 10 |
| Total | 692 functional multiplier instances/sites | 1,000 |

Only one of the two 256-product projection banks is selected for useful input on an accepted beat. Giving all 512 sites simultaneous useful work assumes away that restriction. The DSP total is not a count of independent MACs.

The primary attention paths have 32 QK and 128 AV multiplier instances. Seven more named runtime/square units comprise two softmax probability scalers, two RMS services, two second projection rescalers and the feed-forward gate multiplier: 167 in all. “Runtime” does not mean independently attacker-chosen. Squares have equal operands, rescalers have constrained producers, and all results have fixed consumers.

## Logical operation counts

Let `n` include the current decode input. With 28 layers, hidden width 2,048, feed-forward width 6,144, 16 query heads, eight K/V heads, head width 128 and vocabulary 151,936:

```text
P = 28*(2*2048*2048 + 2*2048*1024 + 3*2048*6144)
    + 151936*2048
  = 1,720,451,072 fixed projection/head MACs per decode

C_attention(n) = 4*28*16*128*n = 229,376*n
C_matrix(n)    = 2*P + C_attention(n)
               = 3,440,902,144 + 229,376*n
```

The input embedding is a lookup; the tied head is one matrix multiplication. GQA reduces K/V storage and projection work, while every query head performs attention.

For a broader named-product allowance, also count 172,032 feed-forward gate products, two runtime products/squares for each of 202,752 RMS elements (including Q/K head normalization), one activation-scale rescaling for each of 725,376 projection output rows, and `448*n` softmax probability scalings. Crediting each product or square as a full MAC gives:

```text
C_named(n) = 230,272*n + 2,605,824 MAC-equivalent operations/decode
```

This is logical useful work, not a complete count of accepted hardware operations or a bound over cancellation, partial execution and replay. Nonlinearities, division, padding and duplicated implementation work require separate treatment. W8 products and standalone/square operations are not automatically equivalent to dense 16-bit training MACs.

| Decode context | Attention operations | Matrix operations | Attention share of matrix work |
| ---: | ---: | ---: | ---: |
| 128 | 29,360,128 | 3,470,262,272 | 0.85% |
| 512 | 117,440,512 | 3,558,342,656 | 3.3% |
| 2,048 | 469,762,048 | 3,910,664,192 | 12% |
| 8,192 | 1,879,048,192 | 5,319,950,336 | 35% |
| 32,768 | 7,516,192,768 | 10,957,094,912 | 69% |

The longer-context rows are model arithmetic, not hardware qualification. The released tests reach a 512-token prompt followed by 16 outputs.

## Measurements and conditional ratios

The [saved measurements](measurements.json), campaign `sustained-128-run2`, give the story continuation 9.0011962044 cached tokens/s over 127 intervals at input contexts 5 through 131. Its average `C_named` is 18,264,320 operations per cached token. This workload requires its own GPU continuation reference `R_story`.

The same tape contains one STEP at exactly 128 input positions, output index 124. Its `step_ns=112895146` gives `F128=8.8577767551/s`. It is a single host-timed call, not a sustained peak rating. Its timing boundary also differs from delivery-to-delivery continuation intervals. Retain it as an explicitly identified fixed-context comparison pending a repeated rating measurement.

Let `R128` be aggregate single-H100 reference evaluations/s at context 128, and `H=989e12`. The measured selected repeat supplies `R128=61,655.70936002969` under the explicit compiled FP16 logit-tolerance policy; it is not a token-exact equivalence claim or a proved peak. The following are **alternative conditional allowances**, not additive channels, observed attacks or bounds on the actual factor:

| Credited access and scheduling | Credited operation rate or work | Conditional `phi_proxy` |
| --- | ---: | ---: |
| All 160 attention multipliers supply a useful MAC every clock | 32.0 billion operations/s | `3.65283e-6 * R128` |
| All 167 named runtime/square units supply a useful MAC every clock | 33.4 billion operations/s | `3.81264e-6 * R128` |
| All 692 functional multipliers supply a useful MAC every clock | 138.4 billion operations/s | `1.57985e-5 * R128` |
| Exactly the named useful work in the same 128-position decode | 32,080,640 operations/decode | `3.24375e-8 * R128` |
| Chosen accepted weights make all counted matrix work useful on that same schedule | 3,470,262,272 operations/decode | `3.50886e-6 * R128` |
| Exactly the named work in the measured story continuation | 18,264,320 operations/cached token on average | `1.84675e-8 * R_story` |

Every-cycle rows assume useful operand control, accumulation, readout and continuous operation despite the actual dataflow, precision and scheduling. The weight-replacement row assumes all necessary authentication and metadata restrictions are overcome, with no extra replacement cost. None of these capabilities has been demonstrated. The schedule rows assume useful access to the counted work without extra or faster executions; that execution restriction is also unproved.

Under the matched schedule assumption `T=C*F`, device speed cancels from `T*R/(H*F)`. If the attacker selects a different workload, maximize its operation rate separately and retain the fixed inference rating denominator. A larger attention work fraction at long context is a reason to test those workloads, not a measured increase in training capacity.

For explicit matrix entries encoded through tokens, the paper's conditional communication model gives `(2/3)*sqrt(L/3)*r` operations/s for a combined token-processing rate `r` and tape budget `L`. Qwen has PCIe register commands, not Tang's UART. PCIe bandwidth and APPEND acknowledgements do not establish a model-processing rate; no numerical token-channel training bound is assigned here. Other encodings and indirect computations also require assessment.

## Measured H100 reference and comparison

The [complete report](../../docs/benchmarks/H100-BENCHMARK.md) retains source snapshots, all trials, failures, diagnostics and reproduction instructions. One whole 132-SM H100 SXM 80 GB was used, with MIG disabled and no other process on that GPU. Qwen and SimpleStories were measured on the same GPU, software stack and cache/timing core. Selected configurations were repeated in fresh processes with a second seed.

| Alternative access assumption at context 128 | Qwen `phi_proxy` | SimpleStories `phi_proxy`, shared-method calibration |
| --- | ---: | ---: |
| Named useful work on the same decode schedule | 0.00199995 | 0.00239112 |
| Useful MAC every cycle from all named runtime/square units | 0.235071 | 0.114092 |
| Useful MAC every cycle from all functional multipliers | 0.974066 | 1.73419 |
| Chosen accepted weights make all counted matrix work useful | 0.216341 | 0.0342843 |

These are overlapping hypothetical allowances, not an observed attack or a range for the actual factor. The new SimpleStories reference is 2,951,332.875 evaluations/s at context 128, about 2.90 times its historical reference. Retaining the old slower GPU implementation only for SimpleStories would distort the comparison. Its historical FPGA step and the Qwen step above supply the explicitly scoped device rates; neither is a repeated peak rating.

The primary Qwen generation workload now uses **one input token `[9707]` and 128 feedback-dependent outputs**, consistent with the other demonstrations. Its 127 timed cached intervals span input contexts 2 through 128. The repeated graph score is 219.743 tokens/s at batch one and 62,538.360/s in aggregate at batch 2,048, with independent K/V storage. These continuation scores are separate from `R128` above. A matching 128-output FPGA campaign is still pending; the old three-prompt measurement has not been relabeled. The primary mean `C_named` is 17,573,504 operations/cached token, giving the conditional matched-schedule identity 0.00111124 with that aggregate GPU score, without supplying the missing FPGA measurement.

Native BF16 failed the prepared cached/full tolerance. FP32 diagnostics and FP16 cached/full checks passed, so the reported suite explicitly uses FP16. Graph-only and continuation cases retain exact optimized/eager greedy agreement. The selected compiled fixed-context policy retains all-logit `rtol=0.005, atol=0.05` and nonfinite rejection, while recording greedy disagreements: 1/512 on the Qwen repeat and 61/32,768 on the SimpleStories repeat. Strict graph-only fixed-context scores are 55,851.987/s for Qwen and 2,258,270.700/s for SimpleStories. No failed case contributes an accepted speed.

Changed-input/prefix, replay, K/V stability and full-trajectory checks passed under each case's stated policy. Profiles show native GQA without software-level full-cache head expansion. Separate GPU context panels at 512, 2,048 and 8,192 passed; they do not extend FPGA qualification. Achieved plateaus do not establish hardware maxima or licensed ratings.

The three older Qwen prompt continuations also pass full eager/graph trajectory comparisons. Their upstream FP16 parent diverges from the quantized FPGA at outputs 4, 34 and 32 respectively. After divergence, their generated inputs differ; positionwise matches are not teacher-forced accuracy rates. GPU cached timing includes layers, final norm/head, argmax, host launches and synchronization, but excludes CPU token delivery; FPGA calls include host communication. These numerical-function and timing differences remain qualifications on every proxy.

## Reproduce the offline analysis

From the repository root, using only Python's standard library:

```sh
python3 -I -S -B tools/estimate_qwen_training_capacity.py
python3 -I -S -B tools/qwen_h100_results.py --check
python3 -I -S -B -m unittest discover -s tools -p 'test_qwen_training_capacity.py' -v
```

The calculator verifies the saved measurement and mapped-report hashes, recomputes the exact context interval and continuation work, and reports workload-specific coefficients. The separate `qwen_h100_results.py` verifies all 897 archived evidence files, recomputes the selected measured rates, and applies the fixed-context coefficients; it keeps the older story-continuation reference unassigned. `--assumed-reference-tps` produces an explicitly labeled sensitivity calculation.

The remaining evidence needed for a whole-system bound includes an execution monitor/proof for the exact Qwen schedule, consumed-weight ownership and command/reset behavior, source-to-checkpoint diagnostic reconciliation, and external-memory/test/debug/physical assessment. Tang's formal assertion count does not establish these Qwen properties.
