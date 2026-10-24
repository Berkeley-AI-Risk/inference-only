# Current optimized seeded evidence

Current records below describe the optimized **SimpleStories-V2-5M** seeded
image; older reports after the history heading keep their 0e6 source context.
No historical timing, browser census or PASS is transferred to the current image.

- [Current CLI evidence](current-candidate-cli.json): all seven source-bound
  board suites in control-first order, including eight matched 128-output
  trials and the 16-case context matrix.
- [Current model evidence](current-model-v4.json): 30 cases, 108 heads and
  434,052 raw logit rows for the actual model-tested circuit.
- [Current scoped source evidence](current-scoped-proofs-v4.json): seven
  retained modular scopes, separate cache-stage154 and exp-ROM source results,
  plus the independently scoped finite canonical mapped-ROM association.
- [Recorded timing](current-timing-v8-baseline-selected-native.json) and
  [native summary](current-native-summary-v8-baseline-selected-native.json):
  9.942238076 cached command tokens/s at temperature1 and the named 2,048-token
  first STEP of 352.237119291seconds, 3.779888478× faster than its parent trial.
  These are source-bound command/reply timings, not browser timing or guarantees.
- [Current formal replay](../../formal/current-seeded-sampling/README.md):
  registered fresh 196-primary connected outcomes; all 196 secondary
  conclusions were attempted and 194 were proved, with CRC 38/73 unresolved.
  Component scopes and the separate 42-assertion bank proof retain their limits.
  [CURRENT-REPLAY.json](../../formal/current-seeded-sampling/CURRENT-REPLAY.json)
  is the named completion; construction/source-action flags stay unchanged.
- A fresh whole-flash readback compared all 16,777,216 bytes: the fixed model
  matched and every other byte was `FF`. Its raw summary retains the original
  clean-package manifest; a separate 13-payload/87-source comparison joins it
  to the registered recipient. It is not a new backup pair, flash write or
  inference-image attestation. The registered recipient then reloaded the
  inference image, settled and passed 45-command/19-token registration.
- [Current browser status](current-browser.json): twelve ordinary Chrome cases
  completed with all 100 outputs exact, including both independent
  automatic-seed checks, the full 2,048-token greedy case and the 2,047-token
  first-STEP Stop. The long Stop drained one reply, acknowledged CLEAR and
  released UART without a second STEP.

See [CURRENT-QUALIFICATION.md](../../CURRENT-QUALIFICATION.md) for the exact
workloads, timing and qualification limits. Stable source/build/candidate records
retain their original action flags; later package status is separate.

## Historical seeded 0e6 reports

# Seeded-sampling evidence

The Tang Mega 138K non-Pro Dock passed bounded UART and application trials on
October 23, 2026 UTC (October 22 in California), using the frozen optional
`seeded-sampling` image. See [the generation guide](../../STOCHASTIC-GENERATION.md).

- [receipt.json](receipt.json) records artifact identities, loading scope, tested
  fixtures, counts, observations, and host command/reply measurements.
- [uart.jsonl](uart.jsonl) preserves all 164 transmitted frames and 162 received
  frames, plus operation durations and four bounded quiet intervals. It has 493
  records. Raw bytes and operation order are retained; times are rebased to the
  first send. Device paths, USB identifiers, absolute paths, and unrelated logs
  are omitted.
- [native.json](native.json) summarizes the frozen native build and pins its
  original receipt and report hashes. Vendor reports are not distributed.
- [historical-tests.json](historical-tests.json) summarizes earlier private
  component and model/UART simulations. Its checksums preserve provenance; the
  public evidence checker does not rerun those compiled campaigns.
- [app.json](app.json) records a separate 45-operation, 19-token host qualifier
  and the rendered Streamlit form driving the actual FPGA backend through
  AppTest. It pins the seven tested host source files and settings codec, and
  retains sanitized command/reply frames and literal output IDs.
- [app-stop.jsonl](app-stop.jsonl) retains 48 raw frames from a later AppTest
  Stop after generation had begun, followed by a greedy restart. Its separate
  summary is the `stopped_after_generation` block in `app.json`.
- [matched128.json](matched128.json) retains eight later 128-output runs, two
  at each temperature, their complete sanitized command/reply events and
  timings, and independently computed reference outputs for all 1,024 tokens.

- [full-context.json](full-context.json) records the 16 completed context
  cases, all 540 main and 192 replay outputs, capacity rejections, and the
  independently audited three-retained/13-new continuation. The earlier
  host output-pipe failure is preserved without crediting its incomplete case.

- [seed-domain.json](seed-domain.json) retains 12 additional-seed cases:
  960 main outputs, 96 replays and three final greedy outputs, all exact.
- [recovery.json](recovery.json) retains partial upload and early-CLEAR cases
  at 128- and 2,048-token prompts, with 48 exact recovery/replay outputs and
  three final greedy outputs. Internal cancellation edges were not observed.

- [around-control.json](around-control.json) records eight separate 128-output
  control trials, each with 12 baseline-style known-answer replay outputs.
  All 1,024 main, 96 probe and three final greedy outputs match the reference.
  Its timings do not replace the separate matched128 benchmark.

- [browser.json](browser.json) records the later ordinary Chrome rehearsal
  from a clean 1,316-file recipient package, following fresh exact 16-MiB model/
  erased-region readback, the same SRAM reload and 45/19 registration. Ten cases
  checked 104 outputs and 144 wire commands; both automatic seeds have fresh
  scalar replays. Stop was observed at 75 outputs and finished at 77, then
  greedy restart and Disconnect passed. Displayed observations are operator/Cua
  records checked against downloads and raw frames, not independent attestation.
- [numerical-reference.json](numerical-reference.json) records fresh exact
  model replays from the [portable reference](../../reference/seeded-sampling/README.md),
  separately from archive-only output/binding checks.
- [The scoped formal capsule](../../formal/seeded-sampling/README.md) supplies
  source-bound replay materials and recorded results. Its recorded checker
  verifies those records; it does not rerun solvers or prove vendor logic.

## Repeated 128-output campaign

Each temperature (`0`, `0.5`, `1`, `2`) was run twice from prompt `[378]` and
seed `0x99aabbccddeeff001122334455667788`. The second run used CLEAR without
resending SETTINGS. All 1,024 returned tokens matched the later independent
whole-model reference, including 768 positive-temperature outputs, and each
complete seeded sequence replayed exactly.

The two temperature-1 cached command rates were **8.66723 and 8.68175
tokens/s**, measured from 127 STEP/reply durations after the first STEP.
Host/UART and evidence-recording costs are included. All eight runs, including
the slower first temperature-2 run at 7.73359 tokens/s, are retained; see
[the full table](../../STOCHASTIC-GENERATION.md#repeated-128-output-workloads).
The original capture receipt keeps its narrower at-capture reference flags;
the later comparison is recorded separately. The public checker validates the
archived reference outputs and bindings rather than executing the model again.

## Initial short trial

There were 107 returned tokens: three startup tokens, 40 acceptance tokens, and
64 tokens in the performance fixture. Exactly 46 were compared with model
known answers: the three startup tokens, all 40 acceptance tokens, and the
first three performance tokens. The remaining 61 performance tokens are recorded
observations. The checker pins their transcript bytes without promoting them
to independently checked model references.

Acceptance includes greedy behavior with zero and all-ones seeds, three-token
fixtures at all four temperatures, replay after CLEAR without SETTINGS,
selected changed-seed outputs, malformed CRC/invalid temperature/nonempty
SETTINGS rejection, and preserved continuation afterward. Sending SETTINGS
immediately after STEP produced no deferred settings reply and preserved the
continuation. Sending CLEAR immediately after STEP produced a CLEAR reply,
then the seeded fixture replayed. These are host/wire observations; internal
busy transitions and owned memory reads were not observed physically.

At temperature `1`, the historical 64-output fixture had a first STEP of 85.382 ms and
63 subsequent STEP command/reply durations totaling 6.097466498 seconds:
10.332160090 tokens/s. Durations include host evidence recording. The repeated
128-output campaign now supplies the advertised rate. Neither establishes
full-context throughput or worst-case latency.

The local image was SHA-256 checked and the SRAM programmer reported successful
loading. Flash was not modified. This is not independent attestation of the
loaded FPGA configuration. Reset defaults were observed after that load,
before SETTINGS; the harness did not perform a separate logic reset test.

Native routing reports inference setup/hold slack of +0.092/+0.144 ns at 25 MHz,
with 145 setup/recovery and ten hold/removal violated endpoints in vendor DDR.
Complete timing qualification remains open. The original wire campaign supplies
no full-context, browser, formal proof, physical fault injection, or security
qualification. Positive-temperature selection uses a finite fixed-point CDF
and deterministic seeded PRNG, rather than independent physical randomness or
an exact floating-point softmax distribution.

## Application checks

The separate app rehearsal checked 19 expected outputs across all temperatures,
repeat with the same seed, greedy after sampling, a changed seed, and a greedy
restart after Stop. Two additional blank-seed runs displayed distinct automatic
seeds and returned two observed tokens; those two outputs were not compared
with model known answers. Stop occurred before prompt upload, returned a final
CLEAR acknowledgement, and released the connection. A new run then reproduced
`[200, 15, 103]`; Disconnect released the retained connection. The rehearsal
used Streamlit AppTest and the real
backend/UART, with no mocked UART or software inference. It did not start a
listening server or automate a real browser. Its 19 output checks and the
qualifier's separate 19 checks are additional to the original 46 wire checks.

A later supplement waited until an output was observed while the app reported
`generating`, then clicked Stop. The request uploaded its one prompt token and
returned 13 of the requested 64 outputs before stopping, acknowledging final
CLEAR and releasing the connection. Its first three outputs were the pinned
`[357, 3898, 104]` fixture; the other ten are recorded observations. A new run
explicitly selected greedy settings and returned `[200, 15, 103]`, then
Disconnect released the connection. These six expected-output checks are
separate from the earlier app/qualifier counts. The internal command edge at
the Stop click was not observed, so this does not establish an in-flight STEP
or memory-read cancellation test.

Run from the repository root, offline:

```sh
python -I -S -B tools/check_seeded_sampling.py
python -I -S -B tools/test_seeded_sampling.py
python -I -S -B tools/check_seeded_matched128.py
python -I -S -B tools/test_seeded_matched128.py
python -I -S -B tools/check_seeded_context.py
python -I -S -B tools/test_seeded_context.py
python -I -S -B tools/check_seeded_domain.py
python -I -S -B tools/test_seeded_domain.py
python -I -S -B tools/check_seeded_recovery.py
python -I -S -B tools/test_seeded_recovery.py
python -I -S -B tools/check_seeded_around.py
python -I -S -B tools/test_seeded_around.py
python -I -S -B tools/check_seeded_browser.py
python -I -S -B tools/test_seeded_browser.py
python -I -S -B tools/check_seeded_numerical_reference.py
python -I -S -B formal/seeded-sampling/check_recorded.py
```

The checker independently verifies frame CRCs, exact SETTINGS seed/temperature
bytes, operation sequence, fixed token fixtures, replay and rejection outcomes,
duration arithmetic, all 87 distributed native inputs, the canonical 91-input
inventory, the original build identity, and the exact prebuilt image. The four
vendor inputs may be absent; if present, their hashes are checked. Mutation
tests exercise wrong tokens with valid CRCs, changed seeds/temperatures,
rejections, replay/order changes, truncated frames, timing changes, unsupported
claims, and altered image/source/build/evidence hashes. These checks validate
the published record and its artifact bindings; they do not run hardware.
The matched128 checker additionally validates all eight full output sequences,
the independent reference identities, complete frame/CRC and CLEAR replay
order, timing arithmetic and completion-time brackets. Its mutation tests
reject altered outputs/references, settings, frames, repetitions, rates and
unsupported qualification claims. No checker independently attests the live
FPGA configuration or establishes timing or security qualification. The
separate context checker validates the recorded full-context campaign; it
does not execute the FPGA or integer model again.

The later context, domain, recovery, around-control and browser checkers verify
the complete archived finite campaigns and their current source/image bindings.
They do not run hardware, drive Chrome, execute the numerical model or rerun
solvers. The browser archive includes fresh setup and model-readback evidence;
it retains the same-host/board, timing, physical-security and attestation limits.
A long first-download wait occurred after that run had completed; its original
observations and interruption record were preserved privately, and no extra generation
or improved throughput result is inferred from the download timing.
