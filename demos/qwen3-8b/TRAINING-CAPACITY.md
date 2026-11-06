# Conditional residual training capacity of Qwen3 8B

The released Qwen3-8B design has a reproducible arithmetic inventory and conditional capacity calculator. Its 8B GPU reference rate `R8B`, actual residual training factor and certified factor remain unassigned. The calculations below are alternative access assumptions, not demonstrated attacks or a completed whole-device assessment. The [shared methodology](../../docs/analysis/RESIDUAL-TRAINING-METHODOLOGY.md) defines the rating procedure; the measured references for [Qwen3-1.7B](../qwen3-1.7b/TRAINING-CAPACITY.md) and SimpleStories do not transfer to 8B.

## Released circuit and arithmetic inventory

This analysis concerns the [released hardware](HARDWARE.md), not a later private speed candidate. The parent is `Qwen/Qwen3-8B`, revision `b968826d9c46dd6066d109eabc6255188de91218`, with 8,190,735,360 unique parameters. The routed checkpoint SHA-256 is `c16119f03177c4975be4bcc54e93cf54c290bb98079f2f8ddb2cc10bb4d07a9c`; the fixed-model image SHA-256 is `a1e8a91912dfa79fb602601e256a4a07da64c57dda146529c08886532d42f833`.

The [hierarchical report](evidence/implementation/utilization-hierarchical.rpt) contains 1,000 DSP blocks, reconciled without summing overlapping parent and child rows:

| Arithmetic | Functional instances or sites | DSP blocks |
| --- | ---: | ---: |
| 64 dot8 units with eight W8 by A16 products each | 512 products | 512 |
| Two integer adder DSPs per dot8 | 128 adders | 128 |
| FP32 multiplication stages | 175 | 350 |
| BF16 elementwise multiplication units | 5 | 10 |
| Total | 692 multiplier instances or sites | 1,000 |

Only one 256-product projection bank is selected for useful input on an accepted beat. DSP blocks are not independent MACs, and the two banks do not provide 512 useful products per accepted beat.

The report hierarchy identifies 32 QK and 128 AV product instances. Seven more named runtime or square sites are two softmax probability scalers, one RMS square stage, one RMS normalization stage, two second projection rescalers and one feed-forward gate multiplier: 167 in all. This classification follows the packaged [RMS](hardware/design/qwen_rms_norm.sv), [attention](hardware/design/qwen_attention_pair.sv), [softmax](hardware/design/qwen_softmax.sv), [projection scale](hardware/design/qwen_projection_scale.sv) and [core](hardware/design/qwen_fixed_core.sv) sources. Runtime operands are not necessarily independently chosen; squares, fixed consumers, source restrictions and scheduling constrain them.

## Logical decode work

Let `n` include the current input. Geometry is 36 layers, width 4,096, feed-forward width 12,288, 32 query heads, eight K/V heads, head width 128 and vocabulary 151,936. Projection and output-head work is:

```text
P = 36*(2*4096*4096 + 2*4096*1024 + 3*4096*12288)
    + 151936*4096
  = 7,568,097,280 MACs per decode

C_attention(n) = 4*36*32*128*n = 589,824*n operations
C_matrix(n)    = 15,136,194,560 + 589,824*n operations
```

Attention uses every query head; GQA reduces K/V projection work and storage. The separate input embedding is a lookup, not another decode matrix product. The [layout](model/layout.json) reconciles `P`, 308,224 unique RMS parameters and 622,329,856 separate embedding parameters to the [source lock](model/source-lock.json) total.

The broader named-work allowance adds 442,368 gate products, two runtime products or squares for each of 483,328 RMS elements, one activation-scale rescaling for each of 1,552,768 projection output rows, and `1,152*n` probability scalings. Crediting each as a full MAC gives:

```text
C_named(n) = 592,128*n + 5,923,584 MAC-equivalent operations
```

These are logical useful-work counts, not a bound over cancellation, partial execution, stalls or replay. Division, nonlinearities, padding and duplicated implementation work require separate treatment. Crediting W8 products, standalone products or squares as dense 16-bit training MACs is a conditional usefulness allowance.

| Input context | Attention operations | Matrix operations | Named MAC-equivalent operations |
| ---: | ---: | ---: | ---: |
| 128 | 75,497,472 | 15,211,692,032 | 81,715,968 |
| 512 | 301,989,888 | 15,438,184,448 | 309,093,120 |
| 2,048 | 1,207,959,552 | 16,344,154,112 | 1,218,601,728 |
| 8,192 | 4,831,838,208 | 19,968,032,768 | 4,856,636,160 |
| 32,768 | 19,327,352,832 | 34,463,547,392 | 19,408,773,888 |

Long-context rows are model arithmetic, not hardware qualification. The retained hardware suite reaches a 512-token prompt followed by 16 outputs; full 32,768-position execution is not qualified.

## Measured timings and conditional coefficients

The primary [saved suite](measurements.json) has the following cached continuation intervals. Output zero includes prefill and is excluded from these rates.

| Case | Cached input contexts | Intervals | Cached tokens per second | Mean named operations per token |
| --- | ---: | ---: | ---: | ---: |
| Single token and 128 outputs | 2 through 128 | 127 | 1.12233504 | 44,411,904 |
| FPGA chat | 24 through 75 | 52 | 1.12396228 | 35,233,920 |
| 512 token prefill | 513 through 527 | 15 | 1.07660811 | 313,830,144 |

The single-token case also contains one STEP at exactly 128 input positions, output index 127. Its `step_ns=896424626` gives `F128=1.1155427584/s`. This is one host-timed call, not a sustained peak. Its timing boundary differs from continuation delivery intervals.

Let `R128` be a matching single-H100 8B reference rate at 128 positions, and use the shared dense-operation normalizer `H=989e12`. No such 8B reference has been supplied. For the following alternative allowances, `phi_proxy = coefficient * R128`:

| Conditional access and schedule | Coefficient per reference evaluation per second |
| --- | ---: |
| Useful MAC every clock from all 160 attention multipliers | `2.90046391e-5` |
| Useful MAC every clock from all 167 named runtime or square sites | `3.02735920e-5` |
| Useful MAC every clock from all 692 functional multiplier sites | `1.25445064e-4` |
| Exactly named useful work on the matching 128-position decode schedule | `8.26248413e-8` |
| All counted matrix work useful on that matching schedule | `1.53808817e-5` |

Every-cycle rows assume useful operand control, accumulation, readout and continuous operation despite fixed dataflow and source restrictions. The matrix row additionally assumes useful access to accepted projection weights. Neither capability has been demonstrated. These rows overlap and must not be added.

For named work on each continuation's **own matching inference schedule**, coefficients are `4.49058686e-8`, `3.56258038e-8` and `3.17320671e-7`, respectively. Each multiplies that continuation's own GPU reference, not `R128`. Cancellation of device speed in `T*R/(H*F)` is valid only under the matching-schedule assumption `T=C*F`.

If a hypothetical attacker instead obtains the counted named work on another retained schedule, keep the fixed `F128` denominator. Those three coefficients per `R128` are `4.51792900e-8`, `3.58946885e-8` and `3.06245551e-7`. The largest is the 512-token case, corresponding to 337.872 million conditional useful operations/s. It is a maximum over three modeled scenarios, not an achieved attack rate or an upper bound over all possible schedules.

## Access questions and remaining assessment

The packaged application supports APPEND, STEP and CLEAR, not arbitrary tensor arithmetic. Its [management display](README.md#management-display) carries lifecycle, clock, readiness and fault fields according to source; correspondence to the routed display remains unverified. The released [plain K/V store](hardware/design/qwen_kv_plain_store.sv) has no cryptographic integrity check. Whether external-memory access supplies useful operand control and observable results in this 8B design remains unassessed; a 1.7B hypothesis is not an 8B result.

A completed assessment needs a workload-matched 8B GPU reference with an explicit numerical-equivalence policy, a defensible inference rating, and evidence about useful access and execution limits. This arithmetic calculator does not establish token-only observation, K/V security, physical security or a certified residual-training bound. It also does not qualify a newer FPGA design or an ASIC.

## Reproduce offline

From the public package root, with standard-library Python 3:

```sh
python3 tools/estimate_qwen8b_training_capacity.py
python3 -m unittest discover -s tools -p 'test_qwen8b_training_capacity.py'
```

The calculator verifies hashes of the saved measurements, hierarchical report, source-input manifest, layout and source lock, then verifies all 135 frozen hardware input files. It reads no model weights and performs no model execution, synthesis, solver, network or cloud operation. Default output leaves the measured reference and actual/certified factors `null`.

For sensitivity only, `--assumed-reference-tps 1000` assigns an illustrative rate to each matching workload. It does not create a measurement and does not populate the actual or certified factor. Re-run the calculator to obtain full precision rather than copying rounded table entries.
