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
The common benchmark records seeded sampling at temperature 1: **9.928 cached
host tokens/s**, or **9.942 command-only tokens/s** over the same two trials.
It does not contain a separate seeded temperature-zero rate. Temperature-zero
functional qualification is separate from the published common speed row.

## Recorded negative timing slack

All four selected images have **known negative slack in vendor-DDR paths**;
they are not fully timing-closed. The following counts are distinct failing
endpoints within each check category, with the worst reported negative slack
in nanoseconds. They are recorded implementation results, not new timing runs.

| Image | Setup: count (worst ns) | Hold: count (worst ns) | Recovery: count (worst ns) |
| --- | ---: | ---: | ---: |
| Authenticated weights | 36 (−6.847) | 2 (−1.056) | 109 (−9.095) |
| K/V-protected | 36 (−5.699) | 10 (−1.096) | 154 (−9.192) |
| K/V protection + encrypted memory | 36 (−6.305) | 10 (−1.112) | 109 (−8.451) |
| Seeded sampling | 36 (−5.838) | 10 (−1.112) | 109 (−8.739) |

No negative removal endpoint is listed in these censuses. The listed negative
paths lie within `u_raw_controller/u_ddr3/`, including controller/PHY
initialization, calibration and reset paths between the reported board, app
and memory clocks. The recorded nonvendor/custom-logic screen is clear; that
does not waive the vendor failures or establish complete external-I/O signoff.
The vendor report's global “setup” union also includes recovery endpoints, so
these category counts must not be added as disjoint physical endpoints.

[The generated timing disclosure](evidence/timing-disclosure.json) pins the four
selected image identities and source censuses, including the
[seeded native summary](evidence/seeded-sampling/current-native-summary-v8-baseline-selected-native.json).
Reconstruct the disclosure without a compiler, solver or board:

```sh
python3.12 -I -S -B tools/check_timing_disclosure.py
```

The raw greedy evidence capsules retain `release_qualified: false`,
`semantic_closure_replay_pending: true`, `final_release_index: false` and their
captured construction-phase labels. Those flags are not rewritten into later
success claims. The [current role index](evidence/current-greedy/INDEX.json),
[functional qualification](GREEDY-QUALIFICATION.md) and offline source/evidence
checker identify the named completed scopes. “Runnable release” describes the
supplied image/model/application/instructions and finite demonstrated behavior;
it does not assert blanket release, timing or physical-security qualification.
All selected build records retain `timing_qualified: false`.

## Proof and physical boundaries

[FORMAL-STATUS.md](FORMAL-STATUS.md) describes the RTL properties, arbitrary
private-service cuts and unresolved secondary-solver conclusions. A changed
controller does not inherit another image's whole-controller proof. Component
simulation and finite model comparisons do not establish a universal numerical,
whole-machine, SHA/AES or cryptographic-security theorem.

Native implementation, positive reported custom-logic margins and successful
board tests do not close the negative vendor-DDR paths listed above or provide
complete external-I/O timing signoff. Build hashes identify
recorded inputs and files; they do not independently attest a loaded FPGA.
The demonstration assumes a frozen, intact circuit and synchronous digital
behavior. It does not certify invasive/side-channel resistance or a residual
training factor. See [the inference-only assessment](INFERENCE-ONLY.md).

For offline integrity and recorded-evidence checks, follow
[REPRODUCE.md](REPRODUCE.md). For guarded board installation and recovery, read
[PROGRAMMING.md](PROGRAMMING.md) and the [host guide](host-app/README.md).

The [normal K/V return proof](formal/kv-return/README.md) has separate source,
27-query and full native operating/corruption replay. It connects current
committed plaintext to the accepted request at the normal guard response.
The formal-status guide distinguishes functional correctness from inference-only
restrictions and states the remaining whole-design obligations.
