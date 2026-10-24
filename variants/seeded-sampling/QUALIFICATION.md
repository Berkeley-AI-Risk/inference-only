> **Archived seeded 0e6 roadmap.** The completed counts and reports below retain
> their original image/source context. For the optimized seeded image's actual
> current status, see [CURRENT-QUALIFICATION.md](../../CURRENT-QUALIFICATION.md).
> No old qualification flag or PASS is inherited.

# Seeded-sampling qualification roadmap

The seeded image is a **runnable release**: the prebuilt circuit, exact source
inventory, fixed model, browser app and installation instructions are supplied.
Availability does not establish correctness for every allowed workload or
security certification. [VALIDATION.md](../../VALIDATION.md) records completed
tests; this file records completed coverage matching the original baseline's
finite functional and scoped control-proof campaigns. A clean recipient/browser
rehearsal also passed on the same supported host and board. Timing and security
obligations remain separate.
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
  comparison matching all 1,024 outputs. These benchmark receipts remain
  separate from the baseline-style context/control campaign below; the
  original 64-output trial remains historical evidence.
- [x] Extended local registration: 45 command results and 19 exact tokens.
- [x] Streamlit AppTest using the real FPGA, including displayed seed settings,
  replay, automatic seeds, Stop/CLEAR, resumed generation and USB release.
  This is separate from a browser-driven installation rehearsal.
- [x] Clean manifest-only export with offline app, helper, reference and
  package checks. This is separate from a fresh physical recipient setup.

## Completed functional and numerical coverage

### Reference-check every generated token

- [x] Produce source-bound integer reference outputs for all board workloads
  below. Temperature 0 must match the original greedy integer model exactly,
  including ties. Positive temperatures must match the implemented integer
  CDF and PRNG rules, rather than a floating-point sampler.
  The [portable exact reference](../../reference/seeded-sampling/README.md)
  provides 48 complete fixtures plus six zero/all-ones seed fixtures. Fresh
  native replay checks all 2,328 outputs and head/K/V/PRNG digests; a separate
  scalar replay checks the full 128-output temperature-1 fixture. The
  [source-bound validation record](../../evidence/seeded-sampling/numerical-reference.json)
  distinguishes actual model replays from archived receipt checks.
- [x] Compare **every** generated token in each qualification run with that
  reference. Record the prompt IDs, temperature, complete seed, outputs,
  first-token time, cached-command times and final CLEAR. Repeated matching
  hardware transcripts demonstrate replay; they alone do not establish
  numerical correctness.
- [x] Exercise additional independent seeds and prompts at positive
  temperatures, including seed zero's documented mapping and all-ones seed.
  Check continuous PRNG streams across many STEPs, not only freshly seeded
  first-token cases. Retain fixed-point boundary/distribution checks; do not
  interpret statistical agreement as proof of independent random draws.

The [full-context record](../../evidence/seeded-sampling/full-context.json) and
[around-control record](../../evidence/seeded-sampling/around-control.json)
check every output in 24 baseline-style trials: 1,564 main outputs and 288
per-trial CLEAR/replay outputs. The separate
[seed-domain campaign](../../evidence/seeded-sampling/seed-domain.json) passed
12 cases with 960 continuous outputs, 96 replay outputs and three final greedy
restoration outputs. It covers a second chosen seed on short and 128-token
prompts, and zero/all-ones seeds at every positive temperature. The public
record checkers validate archived wire/reference comparisons; they do not
rerun the model or access the board.

### Baseline-style context and recovery campaign passed

The supplied baseline's six board trials include this matrix. The seeded image
passed the same prompt fixtures at temperature 0 and every supported positive
temperature with declared reproducible seeds: six trials per temperature,
24 total. Context-limit tests use a separate bounded wire harness; the browser
limits remain unchanged.

| Prompt tokens | Generated tokens | Required evidence |
| ---: | ---: | --- |
| 1 (`[378]`) | 128, repeated | Exact reference comparison and identical seeded replay |
| 128 | 128 | Prompt processing and growing-context generation |
| 512 | 4 | Longer-prompt processing and exact replies |
| 2,047 | 2 | Last input position, final output slot and rejection boundary |
| 2,048 | 1 | Full-input prompt and final output slot |

- [x] Complete the whole matrix for the actual seeded image, without borrowing
  another image's full-context flag. Report every mismatch or timeout, and
  preserve failed runs alongside successful reruns.
- [x] Include the baseline campaign's 12-token CLEAR/replay checks per trial
  and its over-limit/invalid-operation rejections. For the new image also
  verify that CLEAR retains temperature/seed and rewinds the sequence, while
  reset restores greedy defaults. Check settings rejection when nonempty or
  busy and exact continuation after rejection.
- [x] Extend cancellation/recovery cases across prompt upload, computation,
  result delivery and full-context boundaries. Prove ordered drain in the
  digital model and test the observable physical behavior. A host-observed
  Stop or CLEAR does not reveal the exact internal command edge.

The 16 longer-prompt context trials and eight one-token-prompt control trials
each include 12 replay outputs. The original failed partial output capture is
preserved in the context continuation provenance and receives no completion
credit. Physical CLEAR/rejection checks accompany the RTL simulations and
proofs of reset defaults and ordered drain. The separate
[recovery campaign](../../evidence/seeded-sampling/recovery.json) passed partial
prompt upload and early CLEAR during 128- and 2,048-token prompt processing,
with 48 exact recovery outputs and three final greedy restoration outputs.
These extend the existing application Stop/result-delivery tests; host timing
does not independently locate the internal in-flight command edge.

Pass criteria are exact outputs and acknowledgements, correct rejection and
replay behavior, no unexplained or stale wire data, and complete image/source
bindings. These finite trials can establish parity with the named baseline
campaign, not correctness for every possible prompt.

## Extended scoped formal specification and proofs completed

The baseline's [formal inventory](../../FORMAL-STATUS.md) is partial and
source-bound. It includes UART/front-end, token-shell and connected-shell
properties, with private computation abstractions and a separately reported
secondary-solver limitation. The new decoder and controller do not inherit
those results merely by reusing the greedy selector.

- [x] Extend the atomic abstract transition system with bounded temperature/seed
  settings, deterministic random-state transitions, accepted-token commit and
  CLEAR rewind. Fifteen Lean 4.33.1 theorems pass; fixed greedy/sample/random-step
  functions remain abstract. Busy, reset circuitry and terminal faults are
  separate actual RTL obligations, not asynchronous Lean transactions.
- [x] Extend the actual UART/front-end and connected proofs to authorize SETTINGS from
  complete valid frames and an empty, idle owning shell. Prove that rejected,
  malformed, busy or interrupted settings cannot partially mutate or defer
  configuration, and account for parser timeout/resynchronization semantics.
- [x] Extend token-shell and connected-control proofs for seed/temperature
  ownership, one draw per accepted token, stable stalled results, CLEAR
  cancellation/drain, no stale replies and persistent faults. Include faulty
  controls that must fail, source/abstraction audits and reproducible solver
  results with every remaining unresolved conclusion disclosed.

The [public formal replay](../../formal/seeded-sampling/README.md) binds the
87 distributed inputs and exact image, retains the full 4,019-row sampler and
actual memories, and audits observers, source transformations and the original
37 unrestricted private-service cuts. Component results are 35 selector,
57 buffer ownership, 63 UART/frontend and 94 shell assertions; these overlap.
The connected Z3 result passes all 196 assertions. cvc5 checks its base and
194/196 conclusions; request/reply CRC 38/73 remain `unknown`, not passes.
Nine reset-reachable formal fault controls and five serial simulation faults
are detected. Four omitted vendor-file digests remain historical provenance;
the public replay does not verify their bytes or prove vendor logic.

Numerical reference comparisons and sampler boundary tests belong to the
functional checks above. A complete mathematical distribution theorem or
whole-model numerical proof would be stronger additional work, not a
prerequisite for matching the baseline's current scoped proof evidence.
Any future distribution theorem must state its randomness assumptions;
deterministic PRNG transcripts are not independent physical entropy.

These completed scoped proofs establish their control/ownership obligations.
They do not prove numerical CDF equivalence, whole-machine refinement, mapped-netlist
equivalence, cryptographic security or resistance to physical tampering.

## Recipient and browser validation completed

- [x] Rehearse the documented setup from a clean recipient package with the
  supported board and host: preserve recovery assets, verify installed model
  bytes, load the intended SRAM image, run the extended registration, and
  launch the ordinary local web server.
- [x] Drive that listening app in an actual browser, recording text entry,
  all temperatures, chosen/automatic seeds, fixed-seed replay, greedy after
  sampling, Stop after generation starts, recovery and Disconnect. Check the
  displayed and downloaded settings against the real serial transcript.
  Streamlit AppTest with real hardware is useful existing evidence, but does
  not replace this browser path.

The [actual Chrome record](../../evidence/seeded-sampling/browser.json) binds a
clean 1,316-file recipient package on the same supported macOS host and board.
A fresh read of all 16 MiB of flash matched every installed model byte and
the `FF` bytes outside its region. Existing recovery assets were preserved;
the model was not reinstalled. The exact same seeded SRAM image named above
was reloaded, and its extended registration passed all 45 commands and 19
expected outputs before the ordinary listening app was launched.

Ten Chrome cases covered all temperatures, fixed-seed replay, a changed seed,
two distinct automatic seeds, greedy after sampling, Stop after visible
generation, resumed greedy generation and Disconnect. All 104 generated
outputs matched the integer reference; both automatic-seed runs had independent
scalar model replays. Displayed and downloaded settings were checked against
144 wire commands. Stop was clicked with 75 outputs visible and finished with
77 of 128 requested outputs, followed by acknowledged CLEAR and USB release.
Greedy generation resumed successfully, and Disconnect released USB ownership.
The UI observations and raw wire/reference checks are separate evidence;
neither independently attests the physical configuration or the internal
command edge at the Stop click.

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
