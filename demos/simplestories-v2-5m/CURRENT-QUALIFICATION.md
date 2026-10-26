# Current optimized seeded image

**Package status: Runnable release.** The image, model, local app and
installation instructions are supplied. The current image passed its complete
seven-suite board sequence, scoped scientific replay and named completion
registration, whole-flash model readback, registered-recipient inference reload
and 45-command/19-token registration, and twelve ordinary Chrome cases on the
supported host and board. These results have the limits stated below; they do
not establish every possible workload, complete timing or physical security.

This is the same **SimpleStories-V2-5M** numerical model, implemented by the
optimized seeded image
`d271626a7fb9ce1debdf7a9cd847125ec7eb4c907fa9d06af9d5f8146cecc725`.
Its complete model run checked 30 cases, 108 heads and 434,052 raw logit rows.
The 91 model-tested and 91 implemented inputs differ only in the reviewed
native Tcl. There are 87 distributable source files; four vendor digests are
provenance only. Native timing screens and finite canonical mapped-ROM checks
retain their own limits, including unresolved complete vendor-DDR signoff.

## Recorded timing

The temperature-1 cached command rate is **9.942238076 tokens/s**, compared
with **8.674484 tokens/s** for the archived seeded image. Both use a one-token
prompt and two 128-output trials. The weighted rate is 254 outputs divided by
the sum of the two 127-STEP durations, excluding each trial's first STEP. It
includes command/reply costs and is not browser streaming throughput.

In the completed context campaign, the temperature-1/seed-A 2,048-token case
measured **352.237119291 seconds** for its first hardware STEP, compared with
**1,331.417028625 seconds** in the named parent trial: **3.779888478×** faster.
Prompt upload, connection setup and earlier probes are excluded. These are
individual source-bound command/reply trials, not averages, guarantees or
browser time to first token. The earlier pilot remains separate provenance.

The ordinary-browser 2,048-token greedy case displayed its first token after
**388.94 seconds**, including connection/setup and prompt upload. That UI
measurement is a separate trial and workload from the temperature-1 hardware
STEP measurement above; it is not the cached command rate or its speedup.

## Completed qualification

- All seven physical suites passed in control-first order, with 49 cases.
- The matched benchmark retained all eight trials: two 128-output
  continuations at each temperature 0, 0.5, 1 and 2 from prompt token 378.
  Every returned main token in those eight trials matched the reference.
- All 16 context cases passed: 128-, 512-, 2,047- and 2,048-token prompts at
  each of the four temperatures.
- Seventy offline host tests passed, including Streamlit rendering and
  synthetic controller fixtures. They are not an actual browser or board test.
- Fresh scientific replay passed the 35/57/63/94 component scopes, all 196
  connected primary assertions, 15 abstract Lean theorems and sensitivity
  controls. The secondary solver passed the base and attempted all 196
  connected conclusions, proving 194. CRC conclusions 38 and 73 remain
  unresolved, not proved.
- The separate current seeded page-bank proof passed 42 assertions with both
  solvers, real 32,768-bit RAM and arbitrary 258-bit SHA replies, plus ten
  directed scenarios and five faulty controls.
- The named current formal completion is registered in the clean recipient's
  [CURRENT-REPLAY.json](../../formal/current-seeded-sampling/CURRENT-REPLAY.json).
  Construction/source-action false flags remain unchanged.
- One fresh read of all 16,777,216 flash bytes passed: the 7,265,984-byte fixed
  model matched exactly, and every other byte was `FF`. The reader used the
  read-only command; it did not write flash or provision a new backup pair.
- The readback retains its original clean-package identity. A separate exact
  comparison joins its 13 required payload members and 87 distributed native
  source roles to the registered recipient. The raw receipt is not relabelled
  with the later manifest.
- After the reader replaced SRAM, the registered recipient reloaded the exact
  inference image, observed at least 120 seconds of startup settling and passed
  the 45-command/19-token registration check.
- Twelve ordinary Chrome cases completed with **100 outputs**, each matched to
  the reference. The two automatic-seed runs had independent integer-oracle
  checks. The original ten-case set was retained, with the 2,048-token greedy
  run and Stop during the first STEP of a 2,047-token prompt added.
- The long Stop drained exactly one first-STEP reply, acknowledged CLEAR and
  issued no second STEP. Automatic release left no UART owner. The shorter
  Stop run produced 71 outputs; a later greedy run resumed successfully.
- Publication checks the assembled final copy with strict inventory/current,
  browser/formal completion and active-release timing checks and the ordinary
  offline CI. Their results belong to that exact final copy.

## Proof and implementation boundaries

The current source association binds seven unchanged modular scopes plus
separate 154 cache-stage assertions and exp-ROM source evidence. Counts overlap
and are not added. Historical cache141 and atomic59/87 results are excluded.
The source-binding action itself ran no solver; its false replay flag stays
with that action. Fresh scientific outcomes use a separate named completion
record. The connected model retains 37 arbitrary private-output cuts. The
15 Lean theorems concern an abstract machine, without an RTL correspondence
theorem. The bank proof identifies production SHA as source provenance but
does not elaborate it; its 258-bit replies remain arbitrary.

No SHA compression arithmetic/private-bank composition, whole-machine
refinement, mapped-image equivalence, K/V cryptographic integrity, complete
timing or physical-security theorem follows. Logical CLEAR safety is not a
physical memory-erasure theorem. Finite model and board tests do not establish
correctness for every possible prompt or independently attest the loaded FPGA.

The encrypted-memory image retains K/V integrity and replay protection and
encrypts weights and K/V with public demonstration keys. This seeded image
authenticates weights but has no K/V cryptographic integrity or encryption.
Its host limits are 2,048 prompt tokens, 128 new tokens and 2,049 combined;
each original greedy profile retains 128 prompt, 128 new and 256 combined.

## Current replay and offline checks

Fresh current replay uses `formal/current-seeded-sampling/` and a single
combined primary/secondary campaign with `--secondary --require-recorded-model`.
The current bank wrapper owns its complete proof/scenario/audit sequence;
neither campaign needs a duplicate primary run. Original induction depths,
per-query limits and unresolved-secondary rules remain unchanged.

The registered `current_control_formal_replay` entry identifies
`formal/current-seeded-sampling/CURRENT-REPLAY.json`, SHA-256
`c89177b13518209f0c8fb3ccde7db8c1d31dd39b875e1ba084650ed666806fcd`.
This named record registers the checked outcomes; it does not rerun solvers or
turn the construction binding's false replay flag into a proof claim. The
normal offline workflow includes:

    python -I -S -B formal/current-seeded-sampling/check_recorded.py --require-complete

The immutable 0e6 archive preserves its original source, images, timings,
ten-case browser records and portable proofs. Legacy replay entrypoints retain
that historical context; no archived PASS or source-action flag substitutes for
fresh current completion. No other-owner installation is claimed.
