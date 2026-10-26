# Validation and limits

All four supplied SimpleStories-V2-5M configurations have their own selected
image, source inventory and finite functional qualification. The three greedy
designs share one numerical model and token interface; seeded sampling adds
bounded temperature/seed settings and has no K/V integrity or encryption.
The encrypted-memory design retains K/V integrity and replay checks and
encrypts weights and K/V using public demonstration keys.

## Current greedy designs

[GREEDY-QUALIFICATION.md](GREEDY-QUALIFICATION.md) links the source/model/native,
mapped, CLI and browser records for baseline, K/V-protected and encrypted memory.
Each image passed ten CLI cases with 395 main reference outputs and separate
recovery/race checks. Seven browser cases check 26 outputs, full contexts,
pending-STEP Stop, CLEAR and a new connection. The common speed workload has
two 128-output trials with all 256 IDs matching the numerical reference.

[The common benchmark](../../docs/benchmarks/FPGA-SPEED-BENCHMARK.md) reports
10.04 tokens/s baseline, 7.03 K/V-protected and 6.04 with K/V protection and
encrypted memory. These are cached host rates for a one-token prompt, using
validated-reply timestamps. They are separate from browser streaming rates,
prompt-processing latency and fixed-context capacity calculations.

## Seeded sampling

[CURRENT-QUALIFICATION.md](CURRENT-QUALIFICATION.md) states the seeded image's
source-bound qualification. Seven physical suites include eight matched
128-output trials and 16 context cases. Twelve ordinary Chrome cases checked
100 outputs, including independent verification of automatic public seeds.
The long Stop case drains one active reply and clears without a second STEP.
The common greedy temperature-zero rate is separately recorded in the shared
benchmark; temperature-one measurements retain their named sampling workload.

## Proof and physical boundaries

[FORMAL-STATUS.md](FORMAL-STATUS.md) describes the RTL properties, arbitrary
private-service cuts and unresolved secondary-solver conclusions. A changed
controller does not inherit another image's whole-controller proof. Component
simulation and finite model comparisons do not establish a universal numerical,
whole-machine, SHA/AES or cryptographic-security theorem.

All selected images retain `timing_qualified: false`. Native implementation,
positive reported custom-logic margins and successful board tests do not
provide complete vendor-DDR or external-I/O timing signoff. Build hashes identify
recorded inputs and files; they do not independently attest a loaded FPGA.
The demonstration assumes a frozen, intact circuit and synchronous digital
behavior. It does not certify invasive/side-channel resistance or a residual
training factor. See [the inference-only assessment](INFERENCE-ONLY.md).

For offline integrity and recorded-evidence checks, follow
[REPRODUCE.md](REPRODUCE.md). For guarded board installation and recovery, read
[PROGRAMMING.md](PROGRAMMING.md) and the [host guide](host-app/README.md).
