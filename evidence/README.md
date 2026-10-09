# Evidence guide

For an overview of what has been checked and what remains unproved, read
[VALIDATION.md](../VALIDATION.md). This directory supplies the corresponding
image identities, source bindings, measurements and replay summaries.

## Supplied baseline

The `baseline-current/` records describe the supplied baseline:

- `board.json`: six physical trials with 391 main outputs and 72 CLEAR/replay
  outputs, including a repeated 128-output continuation, the full context
  boundary and a separate 2,048-token prompt. Relative reply timestamps allow
  streaming-rate calculations without exposing local device identifiers.
- `metrics.json`: the individual durations used in the capacity analysis.
- `native.json` and `implementation.json`: build inputs, resource counts and
  unresolved DDR timing.
- `replay.json`: packaged-model simulations and token-shell, page-bank and
  connected-shell proof runs. The connected proof has 134 primary-solver
  conclusions; the secondary solver confirms 133, with checksum conclusion 39
  unresolved. The primary connected proof was rerun; the secondary results
  apply to byte-identical formulas. The page-bank proof has 42 assertions.

Run `tools/check_baseline_speed.py` for offline consistency checks. It does
not rerun solvers or the private UART transcripts.

## Supplied protected and encrypted images

The `speed-2026-10-02/` records describe these two images:

- `board.json`: 391 protected and 522 encrypted main-case outputs, plus 12
  CLEAR/replay outputs per trial. Both images were checked through the
  full context window. Per-STEP timings
  distinguish short tests from 128-output continuations.
- `native.json`: build identities, post-route resources and timing summaries.
  Both images retain unresolved vendor-DDR timing.
- `replay.json`: the protected guard/hash, guard/cache/parent and attention
  proofs, plus full-geometry guard simulation. These do not extend the formal
  claims to the encrypted image.

The physical summaries were checked against private UART logs. Public
checkers validate the sanitized records, reference tokens, timing arithmetic
and image associations—not the withheld raw transcripts or the currently
connected chip.

The `read-window/` records bind the baseline and protected images to their
current native builds and physical trials. `references.json` includes the
independently calculated integer outputs for the separate 2,048-token prompt;
overlapping reference cases match the established reference set exactly.

## Other supporting evidence

- `leaf-speed/qualification.json` summarizes exact-arithmetic equivalence,
  caller-bound checks and numerical tests. It includes receipt hashes, not
  the private proof/model harnesses or raw logs. The public full-model replay
  runs four cases and does not prove arithmetic bounds for every possible input.
- `leaf-speed/host-timing.json` records the observed approximately 17 ms
  host reply-delivery pattern; it does not establish its cause.
- `installation.json` records backup restoration, model installation,
  full-array readback and app/controller/UART checks. Its image and source
  identities define the rehearsal's scope.
- `training-capacity-estimates.json` contains reproducible conditional
  calculations, not physical training measurements. See
  [TRAINING-CAPACITY.md](../TRAINING-CAPACITY.md).
- `h100/` contains single-GPU timing sweeps, numerical checks, failed cases
  and source provenance. See [H100-BENCHMARK.md](../H100-BENCHMARK.md) for the
  numerical acceptance rules and the comparison's limits.

## Reading source-bound records

Each test record applies to the source and image hashes it names. Some
supporting records and comparison trials concern other revisions; their
timings and test coverage must not be attributed to the supplied images.
Flags about host qualification in those records describe that particular
test, not the status of the current app.

Records and exact reversible source edits are retained where offline
consistency checks depend on them. This preserves reproducibility without
treating a documentation update as a new test. The supplied sources, images
and inventories are checked directly by `tools/verify_release.py`.

Vendor timing summaries include report hashes, not the complete private
reports. A route-complete marker or clean inference-clock summary is not
whole-product timing signoff. Hashes identify supplied bytes; they are neither
certification signatures nor attestation of a board's current configuration.
