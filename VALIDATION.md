# Validation and known limits

This release contains three greedy configurations: baseline, K/V-protected
and encrypted-memory. They share the same model, numerical contract and
three-operation interface, but have separate implementation and validation
evidence. An optional seeded-sampling configuration has browser controls and
bounded board evidence below. This is a **research demonstration**, not a
production or security certification.

## Current baseline image

The supplied baseline passed six physical-board trials with **391 main outputs
plus 72 CLEAR/replay outputs**, all matching the integer reference. These include
a repeated 128-output continuation and separate 2,047- and 2,048-token prompts,
with boundary rejection. See [the board evidence](evidence/read-window/board.json).

The full packaged-model RTL replay passed all four cases: ordinary and stalled
inference with ten exact STEP results in total, and two corrupted-weight
rejections. Token-shell and page-bank proofs passed 48 and 42 assertions with
both solvers. The connected-shell proof passed all 134 assertions with the
primary solver, plus 13 serial scenarios, five negative controls and
source/abstraction-boundary audits. The secondary solver confirmed 133
conclusions; checksum conclusion 39 remains unresolved.
The [replay summary](evidence/baseline-current/replay.json)
binds these results to the exact sources.

Inference-clock setup/hold slacks are +0.018/+0.144 ns at 25 MHz: the reported
setup margin is very small. The route still has 145 setup/recovery and
ten hold/removal violated endpoints within
vendor DDR. Successful board tests do **not** establish complete timing signoff.
See [the native summary](evidence/baseline-current/native.json).

## Current protected and encrypted images

[Physical evidence](evidence/speed-2026-10-02/board.json) records:

| Supplied image | Physical cases | Main outputs checked | CLEAR/replay outputs checked | Longest prompt tested |
| --- | ---: | ---: | ---: | ---: |
| K/V-protected | 6 | 391 | 72 | 2,048 tokens |
| Encrypted-memory | 8 | 522 | 96 | 2,047 tokens |

All outputs matched the integer reference. The encrypted image's boundary
case reaches the full 2,048-input limit and final output slot. The supplied
protected image also passed the full-window boundary tests, including a
separate 2,048-token prompt.

The [native summaries](evidence/speed-2026-10-02/native.json) bind the images
to their exact build inputs and remaining timing violations. Neither has
complete DDR timing or physical-security qualification. Protected inference-clock
setup/hold margins are +0.228/+0.116 ns; the report retains 152 setup/recovery
and ten hold/removal violated endpoints within vendor DDR, including seven
DLL hold violations from −0.010 to −0.075 ns. Encrypted inference-clock margins
are +0.084/+0.144 ns, with 161 setup/recovery and two hold/removal violated
endpoints within vendor DDR.

For a one-token prompt and 128-output continuation, measured cached command
rates are 5.22–5.23 tokens/s for K/V-protected and 4.27 for encrypted-memory.
Short six-STEP rates of 9.83 and 7.68 tokens/s are not sustained-generation
rates. See [K/V performance](KV-PROTECTION.md#measured-performance) and
[encrypted-memory measurements](ENCRYPTED-MEMORY.md#evidence-and-limits)
for workloads and measurement boundaries.

<a id="experimental-seeded-sampling-image"></a>

## Seeded-sampling image

The seeded image is available as a runnable release with the browser app.
Its [qualification roadmap](variants/seeded-sampling/QUALIFICATION.md)
records completed functional, scoped control-proof and same-host recipient/
browser coverage, and the timing and security obligations that
also remain for the other Tang images.

The repeated performance campaign ran **128 outputs from prompt token 378
twice at each temperature**, with 1,024 returned outputs and exact full
sequence replay at all four temperatures. Temperature 1 measured **8.66723
and 8.68175 cached command tokens/s**, excluding the first STEP. The complete
eight-run table, including the slower first temperature-2 run, is in
[the seeded guide](STOCHASTIC-GENERATION.md#repeated-128-output-workloads).
A subsequent independent whole-model comparison matched **all 1,024
outputs**, including all 768 positive-temperature outputs. This later
comparison is separate from the original capture receipt, whose narrower
at-capture reference flags remain unchanged.
The [complete archive](evidence/seeded-sampling/matched128.json) and
[offline checker](tools/check_seeded_matched128.py) preserve and verify those
outputs, wire events, timings and source/image bindings without rerunning hardware.

The same image subsequently passed **all 16 context-matrix cases**, covering
128-, 512-, 2,047- and 2,048-token prompts at all four temperatures. All **540
main outputs and 192 CLEAR/replay outputs** matched the complete integer
reference, including final-slot and over-limit checks. Three completed
original cases were retained after independent re-audit; 13 new cases completed
the continuation. An earlier host output-pipe failure and its incomplete case
are preserved and are not credited. The [full context record](evidence/seeded-sampling/full-context.json)
binds every frame, reference, timing and source identity. Its 38 runtime pins
are distinct from the native build's 91-input inventory. Commands used a
3,600-second deadline; deadline parity with the baseline is not claimed.

Eight further [around-control trials](evidence/seeded-sampling/around-control.json)
passed with 1,024 main and 96 known-answer replay outputs, plus three final
greedy restoration outputs. Combined with the context matrix, **24
baseline-style trials check 1,564 main and 288 per-trial replay outputs**.
This matches the baseline's prompt fixtures and replay method at all four
temperatures. The eight earlier matched128 performance runs remain separate.

The [additional seed campaign](evidence/seeded-sampling/seed-domain.json)
passed 12 cases and **1,059 exact outputs**: 960 continuous-stream outputs,
96 CLEAR replays and three final greedy outputs. It covers a second fixed
seed at one- and 128-token prompts and zero/all-ones seeds at each positive
temperature. The [early-CLEAR campaign](evidence/seeded-sampling/recovery.json)
passed partial upload and early cancellation of 128- and 2,048-token prompt
computations, then checked **48 recovery/replay outputs and three final
greedy outputs**. No token preceded CLEAR in either canceled STEP case.
Internal command/read edges were not physically observed.

The [clean-recipient browser rehearsal](evidence/seeded-sampling/browser.json)
also passed. Its 1,316-file package was verified before runtime artifacts;
a fresh full 16-MiB read matched every model and erased-region byte, then the
same image was reloaded and passed fresh 45-command/19-token registration.
The ordinary listening app passed ten Chrome cases with **104 exact generated
outputs and 144 wire commands**, including all temperatures, replay, changed
and automatic seeds, Stop and recovery. Both automatic seeds received fresh
scalar-reference checks. Stop was observed at 75 outputs and completed at 77;
subsequent greedy generation and Disconnect passed. No UART owner remained.
Browser observations are operator/Cua records checked against actual downloads
and wire bytes; they do not independently attest the browser actions or silicon.
No second-owner or new-platform installation is claimed.

In the earlier 2026-10-23 UTC trial, the supplied seeded image passed a bounded physical UART
campaign with **46 exact token checks**: three greedy outputs before any
SETTINGS after a fresh SRAM load, 40 seeded/greedy/replay checks, and the first
three outputs of a 64-output temperature-1 run. The campaign returned 107
outputs in total; the remaining 61 performance outputs were recorded and
checked for valid token encoding, without a full reference comparison.
See [the evidence guide](evidence/seeded-sampling/README.md) and
[source/image-bound receipt](evidence/seeded-sampling/receipt.json).

The checks cover all four temperatures, fixed-seed replay after CLEAR without
resending settings, selected changed-seed fixtures, greedy seed independence,
bad CRC/invalid-temperature/nonempty-settings rejection, settings sent behind
STEP, and STEP/CLEAR followed by replay. The physical trace observed the
STEP canceled by CLEAR and no deferred settings reply; it cannot observe the
internal busy edge or outstanding private reads. It is not a physical fault
injection test or full-context campaign. This trial used the UART acceptance
harness; it is separate from the application checks below.

The extended local registration check then passed **45 command results and
19 exact tokens** on the same FPGA. A separate Streamlit AppTest run drove
the rendered app's controls through the real FPGA backend, with **19 expected
UI outputs checked**. It exercised all temperatures, fixed-seed replay,
greedy after positive temperature, a changed seed, two distinct automatic
seeds, early Stop/CLEAR, subsequent greedy generation, and Disconnect releasing
USB ownership. That first Stop case occurred before prompt upload.
A supplemental run requested 64 tokens at temperature 1, requested Stop after
one output was observed while generating, and finished with 13 outputs,
acknowledged CLEAR and a released connection. A subsequent greedy run returned
`[200, 15, 103]`. Its first three stopped outputs and three resumed outputs
add **six exact checks**, separately from the original 19 UI checks.
These observations do not establish the internal STEP edge at the click or
instantaneous stopping. No mocked UART or software inference supplied the outputs.
This was a framework-driven UI test: no listening web server or browser
automation was used. See [the source-bound app record](evidence/seeded-sampling/app.json).
A clean manifest-only recipient export passed strict inventory verification,
all 22 offline package checks and 70 host-app tests, including the seeded
controls and registration fixtures. These checks do not establish a second
owner's complete installation; the later ordinary-browser evidence is
recorded separately above.

That historical 64-output run measured 63 cached commands in 6.09747 seconds,
**10.33 tokens/s**, with an 85.38 ms first STEP. Command timings include
host/UART and evidence recording, and exclude connection and prompt upload.
It remains in the original receipt; the repeated 128-output measurements now
supply the advertised rate.

The [native summary](evidence/seeded-sampling/native.json) reports
inference-clock setup/hold margins +0.092/+0.144 ns at 25 MHz, with 145
setup/recovery and ten hold/removal violated endpoints in vendor DDR.
The image has separate [extended scoped control proofs](FORMAL-STATUS.md#separate-seeded-sampling-proof-inventory)
and portable numerical references. Its full-context matrix passed; recipient
and actual-browser checks also passed on the same host and board. Complete
timing signoff remains absent. The historical app checks have
the bounded scope stated above. See
[the seeded-generation guide](STOCHASTIC-GENERATION.md).

## K/V integrity checks

The protected proof package was replayed against the supplied source set:
221 guard/hash-history assertions, 325 guard/cache/parent assertions and
34 attention assertions, with both solvers completing each result. The
325-assertion result includes the guard's 221 properties; these are overlapping
scoped results, not independent totals or a whole-machine theorem.

The replay includes source/query audits, four reset-reachable faulty controls
and 23 induction-sensitivity checks on 22 distinct faulty source copies.
The induction checks are not claimed as reset-reachable attacks. The
full-geometry guard simulation passed 275,913 commands.
See the [replay summary](evidence/speed-2026-10-02/replay.json),
[formal package](formal/kv-integrity/README.md) and
[portable guard tests](simulation/kv-protected/README.md).

The simulations exercise altered data, wrong locations, stale data, sealed
reads and CLEAR. **Deliberate corruption was tested in simulation, not by
physically modifying the board's DDR or bus.** The board trials tested normal
inference.

The proofs establish safety properties for their stated RTL models. SHA
compression and specified private computation boundaries are abstracted.
Attention's result is separate from the joint guard/cache induction.
These are not proofs of full numerical correctness, the whole machine or
physical tamper resistance. They do not extend the formal claims to the
encrypted-memory image.

## Host and installation checks

The local app has offline UI/controller tests. The physical-image tests above
exercise the host/UART path. The selected encrypted image was tested with the
UART test client, not the browser or the app's qualification API. These are
not a recorded end-to-end human browser-click rehearsal of all three greedy
images on a second owner's Mac and board.

The backup, flash installation, independent read-back and recovery workflow
has a [byte-level rehearsal record](evidence/installation.json). Its source
and image identities define what that record covers; it is not a new inference
test or live attestation of any connected board. Follow
[PROGRAMMING.md](PROGRAMMING.md) and [the host guide](host-app/README.md),
including the known-answer check for your loaded configuration.

## Not established

- Complete vendor-DDR and board-I/O timing signoff. The endpoint summaries
  come from private vendor reports; the release includes report hashes,
  not those complete reports.
- Correct output for every permitted prompt. Physical and full-model
  simulation tests cover finite cases.
- Whole-machine refinement or equivalence between all implemented hardware
  and the proved RTL models.
- Resistance to invasive circuit modification, side channels or other
  physical attacks.
- A certified whole-device bound on residual training capacity. The
  [conditional estimates](TRAINING-CAPACITY.md) state assumptions, not a
  physical-security certification.
- Validation on other operating systems, board revisions or a second
  owner's complete installation.

Read [FORMAL-STATUS.md](FORMAL-STATUS.md) for exact proof boundaries and
[INFERENCE-ONLY.md](INFERENCE-ONLY.md) for the frozen-configuration argument.
Checksums and editable local deployment profiles are not remote attestation.
