# Qwen3-1.7B: validation and limits

[Guide](README.md) · [Reproduction](REPRODUCE.md) · [Formal scope](FORMAL-STATUS.md)

This page identifies the evidence for the released, authenticated-weight
Qwen3-1.7B implementation. Its numerical function uses the fixed quantization,
arithmetic and rounding rules described in the [guide](README.md); the comparison
reference implements those rules rather than upstream floating-point Qwen.
The released circuit does not authenticate K/V or encrypt weights.

## Evidence

| Boundary | Records | What they establish |
| --- | --- | --- |
| Common generation workload | [Capture](evidence/common-speed-2026-10-26/capture.json), [source bindings](evidence/common-speed-2026-10-26/source-review.json), [reference record](evidence/common-speed-2026-10-26/reference.json) | Two one-input-token, 128-output greedy trials, with all 256 output IDs matching the fixed-model reference. |
| Additional hardware workloads | [Measurements](measurements.json), [workloads and limits](README.md#additional-validation-workloads) | Finite token comparisons, CLEAR/replay checks and workload-specific host timings. |
| Numerical reference | [Runnable reference](reference/README.md), [recorded checks](evidence/reference/CHECKS.json) | Independent software checks for the stated fixed numerical model and selected cases. |
| Source and implementation | [Source inputs](SOURCE-INPUTS.json), [implementation inputs](hardware/IMPLEMENTATION-INPUTS.json) and [implementation reports](evidence/implementation/REPORTS.json), [hardware guide](HARDWARE.md) | Identities of the measured build and preserved timing, routing and implementation evidence under its declared constraints. |
| Formal development status | [Scoped results and open obligations](FORMAL-STATUS.md), [source-bound summary](evidence/formal/STATUS.json) | Component RTL proof status for the identified sources. Whole-machine refinement remains incomplete; the complete solver/evidence bundle is not included in this release. |
| Installation | [Deployment](deployment.json), [rehearsal](evidence/installation.json), [installation guide](INSTALL.md) | Recorded public-image availability and a finite installation/replay test in the image owner's existing SDK environment. |

The [common benchmark](../../docs/benchmarks/FPGA-SPEED-BENCHMARK.md) defines
reply timing and recomputes the selected rates. Additional workloads have their
own prompt lengths and output counts; their timings describe those cases.

## Limits

The longest hardware-tested tape described in the guide has 512 prompt tokens
followed by 16 outputs. The 32,768-token tape capacity is not a hardware-qualified
full-context claim. The installation rehearsal is not a second-account or fresh
operating-system test. Recorded public-image permission can change.

Finite output agreement and implementation reports do not establish all-prompt
numerical correctness, whole-machine formal refinement or resistance to physical
modification. Source hashes identify recorded files; they do not independently
attest the FPGA currently loaded in another machine. The
[formal-status page](FORMAL-STATUS.md) states the verification boundary.

[REPRODUCE.md](REPRODUCE.md) separates offline record checks, fresh numerical
reference execution, hardware tests and source rebuilding.
