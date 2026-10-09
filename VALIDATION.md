# Validation and known limits

This release contains three runnable configurations: baseline, K/V-protected
and encrypted-memory. They share the same model, numerical contract and
three-operation interface, but have separate implementation and validation
evidence. This is a **research demonstration**, not a production or security
certification.

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
not a recorded end-to-end human browser-click rehearsal of all three supplied
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
