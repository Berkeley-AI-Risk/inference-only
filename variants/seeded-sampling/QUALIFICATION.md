# Seeded-sampling qualification roadmap

The seeded image is a **runnable release**: the prebuilt circuit, exact source
inventory, fixed model, browser app and installation instructions are supplied.
Availability does not establish correctness for every allowed workload or
security certification. [VALIDATION.md](../../VALIDATION.md) records completed
tests; this file defines the additional evidence needed to approach the
original baseline's functional and control-proof coverage.
The target is the existing SimpleStories seeded image, SHA-256
`0e6d30b68bd8757657bc1c3b949ac5b9571a0a8d1f8bb1a6e6018b241f733033`.
This roadmap does not call for another model or a replacement hardware design.

Every unchecked item below is **remaining work**. New results must name the
exact image, production sources, model, oracle, host code and test transcripts
they cover. A successful repetition or matching checksum cannot substitute
for a missing reference comparison or proof.

## Completed foundation

- [x] Source-bound routed image, with model authentication, plaintext flash
  layout, clocking and board pins retained from the baseline.
- [x] Finite component and authenticated-model/UART simulations of greedy
  preservation, fixed-point sampling, seeded replay, stalls and fault cases.
  The public records summarize these private campaigns; the public checker
  does not rerun their compiled simulations.
- [x] Physical short fixtures at all four temperatures, changed-seed cases,
  CLEAR replay, settings rejection and STEP/CLEAR recovery.
- [x] Two 128-output runs from prompt token 378 at each temperature, with
  exact full-sequence CLEAR replay and a later independent whole-model
  comparison matching all 1,024 outputs. This completes that short-prompt
  matrix row, not the longer-prompt and full-context rows below.
- [x] Extended local registration: 45 command results and 19 exact tokens.
- [x] Streamlit AppTest using the real FPGA, including displayed seed settings,
  replay, automatic seeds, Stop/CLEAR, resumed generation and USB release.
  This is separate from a browser-driven installation rehearsal.
- [x] Clean manifest-only export with offline app, helper, reference and
  package checks. This is separate from a fresh physical recipient setup.

## Functional and numerical coverage still required

### Reference-check every generated token

- [ ] Produce source-bound integer reference outputs for all board workloads
  below. Temperature 0 must match the original greedy integer model exactly,
  including ties. Positive temperatures must match the implemented integer
  CDF and PRNG rules, rather than a floating-point sampler.
- [ ] Compare **every** generated token in each qualification run with that
  reference. Record the prompt IDs, temperature, complete seed, outputs,
  first-token time, cached-command times and final CLEAR. Repeated matching
  hardware transcripts demonstrate replay; they alone do not establish
  numerical correctness.
- [ ] Exercise additional independent seeds and prompts at positive
  temperatures, including seed zero's documented mapping and all-ones seed.
  Check continuous PRNG streams across many STEPs, not only freshly seeded
  first-token cases. Retain fixed-point boundary/distribution checks; do not
  interpret statistical agreement as proof of independent random draws.

### Match the baseline's context and recovery campaign

The supplied baseline's six board trials include this matrix. Use the same
prompt fixtures for temperature 0 and extend the matrix to every supported
positive temperature with declared reproducible seeds. Retain the unchanged
browser limits; use a separate bounded wire harness for context-limit tests.

| Prompt tokens | Generated tokens | Required evidence |
| ---: | ---: | --- |
| 1 (`[378]`) | 128, repeated | Exact reference comparison and identical seeded replay |
| 128 | 128 | Prompt processing and growing-context generation |
| 512 | 4 | Longer-prompt processing and exact replies |
| 2,047 | 2 | Last input position, final output slot and rejection boundary |
| 2,048 | 1 | Full-input prompt and final output slot |

- [ ] Complete the whole matrix for the actual seeded image, without borrowing
  another image's full-context flag. Report every mismatch or timeout, and
  preserve failed runs alongside successful reruns.
- [ ] Include the baseline campaign's 12-token CLEAR/replay checks per trial
  and its over-limit/invalid-operation rejections. For the new image also
  verify that CLEAR retains temperature/seed and rewinds the sequence, while
  reset restores greedy defaults. Check settings rejection when nonempty or
  busy and exact continuation after rejection.
- [ ] Extend cancellation/recovery cases across prompt upload, computation,
  result delivery and full-context boundaries. Prove ordered drain in the
  digital model and test the observable physical behavior. A host-observed
  Stop or CLEAR does not reveal the exact internal command edge.

Pass criteria are exact outputs and acknowledgements, correct rejection and
replay behavior, no unexplained or stale wire data, and complete image/source
bindings. These finite trials can establish parity with the named baseline
campaign, not correctness for every possible prompt.

## Extended formal specification and proofs still required

The baseline's [formal inventory](../../FORMAL-STATUS.md) is partial and
source-bound. It includes UART/front-end, token-shell and connected-shell
properties, with private computation abstractions and a separately reported
secondary-solver limitation. The new decoder and controller do not inherit
those results merely by reusing the greedy selector.

- [ ] Extend the abstract transition system with bounded temperature/seed
  settings, deterministic PRNG state, accepted-token commit, CLEAR rewind,
  reset and terminal-fault behavior. State explicitly which inference
  function or numerical operation remains abstract.
- [ ] Extend the actual UART/front-end proofs to authorize SETTINGS only from
  complete valid frames and an empty, idle owning shell. Prove that rejected,
  malformed, busy or interrupted settings cannot partially mutate or defer
  configuration, and account for parser timeout/resynchronization semantics.
- [ ] Extend token-shell and connected-control proofs for seed/temperature
  ownership, one draw per accepted token, stable stalled results, CLEAR
  cancellation/drain, no stale replies and persistent faults. Include faulty
  controls that must fail, source/abstraction audits and reproducible solver
  results with every remaining unresolved conclusion disclosed.

Numerical reference comparisons and sampler boundary tests belong to the
functional checks above. A complete mathematical distribution theorem or
whole-model numerical proof would be stronger additional work, not a
prerequisite for matching the baseline's current scoped proof evidence.
Any future distribution theorem must state its randomness assumptions;
deterministic PRNG transcripts are not independent physical entropy.

Passing these scoped proofs would improve control and numerical evidence.
It would not by itself prove whole-machine refinement, mapped-netlist
equivalence, cryptographic security or resistance to physical tampering.

## Recipient and browser validation still required

- [ ] Rehearse the documented setup from a clean recipient package with the
  supported board and host: preserve recovery assets, verify installed model
  bytes, load the intended SRAM image, run the extended registration, and
  launch the ordinary local web server.
- [ ] Drive that listening app in an actual browser, recording text entry,
  all temperatures, chosen/automatic seeds, fixed-seed replay, greedy after
  sampling, Stop after generation starts, recovery and Disconnect. Check the
  displayed and downloaded settings against the real serial transcript.
  Streamlit AppTest with real hardware is useful existing evidence, but does
  not replace this browser path.

The existing baseline also lacks a complete installation on another owner's
setup and cross-platform qualification. Retain those limitations unless
separate recipient/platform trials are performed; do not require them merely
to match the baseline's present evidence or claim untested platforms.

## Timing and security are separate, unfinished obligations

These are **not completed by the other Tang images either**, and are outside
the target of matching the baseline's present functional/proof evidence:

- [ ] Resolve vendor-DDR, reset/CDC and board-I/O timing findings, document
  justified constraints, and complete implementation/timing qualification.
  The seeded image currently retains 145 setup/recovery and ten hold/removal
  violated vendor-DDR endpoints; a positive inference-clock slack is insufficient.
- [ ] Establish the intended complete implementation/specification connection
  under explicit assumptions, beyond the component/control proofs above.
- [ ] Define and evaluate the physical attacker model, external-memory and
  debug/configuration paths, fault/tampering behavior and any claimed bound on
  residual training capacity. This seeded variant has no K/V integrity or
  encryption; neither a restricted interface nor passing output tests closes
  those attack surfaces.
- [ ] Obtain whatever independent assessment is required for a specific
  production/security claim. No result in this repository currently certifies
  a nation-state-resistant whole-device residual training fraction.

The frozen-configuration assumption and research-demo limits remain explicit
throughout. Use precise labels such as “full-context campaign passed” or
“extended control proof passed” when those named tasks are complete, rather
than treating “fully qualified” as an unbounded certification claim.
