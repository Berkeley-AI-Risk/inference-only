# Protected K/V: scoped, source-bound safety proofs

This replay checks the K/V-protected variant's actual RTL. It does not change
the configuration or use the FPGA. Both Z3 and cvc5 prove every conclusion
in each of these reset-initialized, length-two inductions:

| Model | Assertions, including supporting invariants | What is retained |
| --- | ---: | --- |
| Guard and page-hash history | 221 | Real controllers and all eight full-size guard memories |
| Guard, atomic cache and parent connections | 325 | The preceding 221, the local cache's 59, and 45 connection/history assertions |
| Attention capture and use | 34 | Actual attention controller, capture/prefetch registers, value-row assembly and eight-lane aligner |

Length-two induction proves these safety properties for arbitrarily long
executions of the stated digital models; it is not a two-cycle simulation.
There are no RTL assumption cells. Initial reset is constrained in the base
case; other inputs at each model's declared boundary remain unrestricted.
The counts overlap and must not be added to suggest a whole-machine theorem.
The attention result is **separate** from the 325-assertion composition.
The 59 local-cache assertions come from the existing
[`formal/kv-epoch` controller proof](../kv-epoch/epoch_monitor.inc.sv);
they are re-proved here, not assumed from an earlier receipt.

## Threat model and evidence boundaries

The attacker may change external DDR contents and its response data, timing
and faults, and may issue the legitimate public commands or reset the device.
The selected inference circuit and its on-chip state remain intact. This is
the project's frozen-design interpretation, not a claim that a development
FPGA cannot be reprogrammed. These digital proofs do not model invasive
circuit edits, probing of on-chip state, or voltage, clock and EM glitches.

The intended integrity guarantee is that changing DDR cannot substitute
chosen operands for the cache data the fixed computation stored. Connecting
the proved safety properties to that guarantee also requires correct SHA-256
implementation, cryptographic collision resistance and the unproved circuit
connections identified below. The SHA implementation is tested, not formally
proved here. Expected tags need write protection, not secrecy; external K/V
data remain readable. Neither confidentiality nor useful training capacity
is certified by these checks.

| Data path or obligation | Evidence in this package |
| --- | --- |
| Accepted private writes → partial-page storage and hash input | Guard history proof |
| Hash framing → expected-tag storage → later comparison | Guard/hash proof, with arbitrary compressor results |
| SHA result implements SHA-256 | Independent known-answer simulation; assumed by the security argument |
| Verified staged copy → assembled committed response | Joint guard/cache proof, including vectors and exponent bytes |
| Staged pending row → writes and pending response | Joint proof, including exponents and all 18 write completions |
| Cache response → requested layer, position, head and role | Joint proof under the source-projected parent |
| Attention's outstanding request → accepted reply → operand use | Separate attention proof; reply contents are arbitrary at this boundary |
| Accepted reply → key operand and value-aligner input | Separate proof, including key exponent and shift relative to the controller's alignment-exponent register |
| Aligner input pins → aligner reply | Real RTL retained; the reply's mathematical relation to its latched inputs is not asserted |
| Aligner replies → assembled value operand | Separate attention proof |
| Fixed-model arithmetic → newly staged K/V | Simulation and source inspection, not proved here |
| Other external-memory reads (boot image, model pages) → computation | Digest authentication in the design; no whole-design data/control-flow proof in this replay |
| Parent projection → complete RTL → physical image | Source checks and build records, not equivalence proofs or live attestation |

The guard simulation compares complete RTL tags with an independent software
SHA-256 computation; see [the executable simulation](../../simulation/kv-protected/README.md).
The model's authenticated boot provides additional finite implementation
evidence. Neither substitutes for a compressor-correctness proof.

The standalone replay checks the proof's production hashes against the
[protected hardware input inventory](../../host-app/hardware-inputs-kv-protected.json).
It checks the inventory's canonical hash and the image's actual bytes against the
[build receipt](../../prebuilt/kv-protected/BUILD.json). This binds the audited
sources to the recorded build inputs and output. The completion receipt names
that image and explicitly records `attestation: false`. This does not prove synthesis
equivalence or attest which configuration is currently loaded on a board.

## Guard and cache history

The guard proof follows accepted private writes through partial-page storage,
hash framing, private tag publication and later read comparison. It checks
the page identity and epoch, staging fill-before-use, sealed-copy
reads, fault closure and cancellation. The actual page-hash wrapper is
included: header fields, byte order, word count, padding and reply sequencing
are checked. The **SHA compression arithmetic is abstracted**: its completion
and 256-bit result can change arbitrarily each cycle. This is not a proof of
SHA-256 correctness or collision resistance.

Freshness depends on the guard's on-chip committed prefix and expected tags:
reads are allowed only below that prefix, every append replaces the affected
tags before publishing the new prefix, and reset/CLEAR set the prefix to zero.
The 64-bit epoch in each hash header adds separation between CLEARs. The proof
records CLEAR independently, checks the circuit's previous-CLEAR register
against that history, and checks epoch advancement, stability and terminal
failure at saturation. Reset starts the epoch at zero; this is not a
persistent counter across power cycles. Old RAM bytes alone cannot authorize
a read before the corresponding prefix has been repopulated.

The 325-assertion composition includes the actual atomic K/V controller and
address mappers. A nonfaulting committed-row response requires the matching
guard-admitted pieces for that location and epoch. The pending-row path
retains the controller's internal staging provenance and all 18 required
write completions. Private write vectors and exponent bytes originate in that
staged row, but the values offered to the staging interface are arbitrary: their numerical
provenance from the fixed model is not proved.

The intervening parent model is **source-projected**. It extracts the real
core reset-release/reply gates and shared-wrapper lock/fault registers, and
checks the shell's CLEAR pass-through and actual instance bindings. Other
semantic-control, arithmetic, attention and fault outputs are unrestricted
private inputs, including fault sources that are sticky in the full hardware
but unrestricted in this model. This retains the real connection expressions;
it does not include every register in the full parent circuit. Source extraction
checks that CLEAR reaches the atomic controller or finds it held in reset;
the controller's cancellation behavior is checked by the solver. The guard's own prefix/cache
invalidation and epoch increment are also checked against public CLEAR.
Terminal closure blocks new child work while allowing owned external replies
to drain. A detected guard fault survives CLEAR; reset is required to clear it.

All eight guard memories retain their full geometry: 13,824 partial-page
words, 640 staging words and six 4,096-word tag banks, each 32 bits wide
(1,249,280 bits total). Initial RAM contents are unconstrained. The 64-bit
epoch and 50,000,000-cycle guard timeout are unchanged. Read-only symbolic
observers cover all locations without driving production signals or writes.

## Attention capture and use

The actual attention controller is checked with arbitrary cache replies and
arbitrary outputs from selected arithmetic/memory children. A row copied
into a capture register is not automatically authorized for use: acceptance
also requires the correct owned response, legal values and a live controller.
The proof checks that:

- Key/value data are used only after acceptance of the reply to the controller's
  own outstanding request for that kind, scan position and K/V head. No reset,
  CLEAR or fault has revoked that acceptance. Reply contents are unconstrained
  in this model. The separate 325-assertion theorem checks that a healthy cache
  response carries the requested descriptor; the parent projection source-checks
  the connections from attention's request outputs. The captured vector matches
  the reply; for values, the captured exponent does too.
- The key operand presented to the score lane matches the appropriate
  coordinate of the accepted key vector, through the real prefetch register.
  Its pending score exponent uses the accepted key exponent and the captured
  query exponent, with the fixed scaling adjustment.
- Value alignment requests use the correct 128-bit group of the accepted
  value row and the shift derived from its accepted exponent and the controller's
  `value_align_exponent_q` register (zero for the exponent scan).
  The proof does not establish that this common alignment exponent is the
  correct result of the earlier scan. Read-only taps observe the real input pins.
  All eight groups must be assembled from the real aligner's replies before the value lane uses
  the assembled row; a symbolic coordinate checks that operand selection.
- CLEAR revokes acceptance and partial-row history. An outstanding cache
  reply may drain, but stale capture contents do not authorize new use.
  CLEAR, lock loss and faults suppress live use and new requests/results.

The eight-lane aligner and normalization-candidate stage are retained. Seven
other child module types are replaced at their complete output interfaces:
the multiply lanes, query/output/workspace RAMs, iterative shifter, exponential
lookup and divider. Each retained abstract output has its own unconstrained
driver. No internal attention-controller register is deliberately replaced by
an arbitrary input. Elaboration can nevertheless remove unused registers and
signals whose only consumers were abstracted children; their values are not
thereby proved. This is **not** a numerical theorem
for attention, the shifter, softmax or multiply results. In particular, the
value-row assertion tracks the real aligner's replies, rather than proving
their lane mapping, signs, shift direction or rounding against an independent
mathematical specification.

The parent model source-checks the cache-to-attention pin bindings. That
structural connection plus the separate attention theorem is useful evidence,
but this package does not claim a single joint guard-to-attention induction.

## Reproduce

From the repository root, with Python 3.12 and the recorded Yosys, Z3 and cvc5
versions in [REPRODUCE.md](../../REPRODUCE.md#formal-toolchain-and-replay-results)
on PATH:

```sh
python3.12 -I -S -B tools/check_kv_integrity.py \
  --package . --work ../fresh-kv-integrity --jobs 16 --timeout 300
```

The work directory must be new and outside this repository. Allow several
minutes and roughly 2–3 GB for the generated files; no network or
board access is needed. Up to 16 solver jobs run per positive proof, and
the independent history and attention stages can overlap. A timeout,
`unknown`, unexpected answer, changed source, generated-file identity mismatch
or audit failure is not a pass.
The default worker count is at most half the logical CPUs, capped at 16;
use `--serial-stages` to avoid overlapping stages. On machines with fewer than
16 logical CPUs, start with `--serial-stages --timeout 600`.
Explicit `--yosys`, `--z3` and `--cvc5` executable paths are supported.
The recorded tool-version strings
are checked before any proof starts. Generated-file identity is still checked
afterward. This is an offline, toolchain-pinned replay, not a demonstrated
cross-platform byte-identical build. Python `-O` and `-OO` are rejected.

The replay regenerates all three models, proves them with both solvers,
checks four deliberately faulty formal-only copies, rebuilds each query and
checks it against the solved file and raw answer, re-elaborates the audited
models to byte-identical outputs, and runs 44 core auditor regression tests.
The four reset-reachable faulty controls lose child CLEAR,
bypass a guard payload wire, clear a terminal guard fault, or take a private
write payload from external DDR. Both solvers find reset-reachable failures.
The wire-bypass case detects incorrect wiring before a valid row need be
delivered; it is not a demonstrated payload-injection or training attack.
None of these faulty copies is programmed or included as a runnable image.
The two guard reset-reachable controls fail local invariants before any hash,
tag-publication or verified-read activity; they are not end-to-end integrity
attack demonstrations.

Another 23 targeted controls test 22 distinct faulty source copies. They cover
epoch advancement and CLEAR history, guard CLEAR, digest rejection, tag
publication, sealed-copy return, read-prefix bounds, write-hash provenance,
cache role, hash framing, accumulated-row provenance, attention cancellation,
operand coordinates, aligner inputs and exponents. Both solvers must find a
counterexample to the specified induction conclusion. **These are
induction-sensitivity tests, not reset-reachable attack demonstrations.**
The stored- and pending-key-exponent checks share one faulty copy; these are
not controls for every value-exponent or head-1 path. The accumulated-row test
also omits the direct wire-equality lemma in its faulty copy, so it checks
the new data-history assertion rather than merely detecting a wire mismatch.

Each unchanged target is covered by the positive proof. The controls use all
earlier-state invariants; adding hypotheses to a proved induction step cannot
create a counterexample. The accumulated-row test, which also removes a lemma,
is explicitly a two-change test. A separate artifact audit reconstructs every
faulty source and query, re-elaborates the model, checks both raw solver answers,
and compares target indices and model/query hashes with `expected.json`.
Eight additional regression tests check this audit, including rejection of
changed targets, models, queries, mutations and solver logs. The auditor shares
helpers with the runner; it is not an independently implemented query checker.
Public [simulation fault controls](../../simulation/kv-protected/README.md)
separately exercise digest rejection, role checks and tag publication.

The artifact-dependent auditor tests run automatically in the replay. To
rerun them separately, set `KV_FORMAL_WORK` to that replay's work directory.
Without it, those test classes explicitly skip; that is not a proof pass.
The complete replay rejects skipped tests. The log/constraint tests do not
require generated artifacts.

Audits check non-driving observer fanout, original RAM geometry, source
instrumentation and unrestricted abstraction outputs. They share source-model
generators with the runners and were developed as part of the same work:
they are **not an independent review of the proof methodology**.

[expected.json](expected.json) records production, verification and replay source hashes,
generated-source/query identities and summarized solver results. Large
generated SMT files are reproduced on demand, not bundled. The summaries
are records of completed runs, not substitutes for rerunning the solvers.
For a quick source-binding check only:

```sh
python3.12 -I -S -B tools/check_kv_integrity.py --package . --recorded-only
```

## Remaining boundaries

Not established here: full semantic-prefix composition; fixed-model provenance
of newly produced K/V; end-to-end numerical correctness; SHA compression
correctness; whole-machine refinement; synthesized-netlist equivalence;
electrical timing qualification; liveness; physical-tamper resistance; or a
certified bound on useful training capacity. The models are synchronous,
two-state RTL models, not analog fault models. Trusted on-chip state and
cryptographic collision resistance remain separate security assumptions.
Reset reasoning uses Yosys's `async2sync` digital model, not analog behavior
around a clock edge. Splitting an induction into individual conclusions does
not assume them for the current state: the reset base and every next-state
conclusion must pass, using only earlier-state invariants.

Also not supplied by this replay: a proof that every external-memory influence
passes the intended checks, a mechanically derived/equivalent full parent
projection, or a separately implemented query checker. A structural traversal
that stops at comparisons, addresses or selection signals can help inspect
direct data paths, but does not prove safety of those control influences.
GitHub CI checks recorded bindings and helper tests; it does not run the
toolchain-pinned solvers. Systematic reachability coverage, a cryptographic
collision-reduction theorem and further reset/rollback campaigns remain
additional work, not implicit consequences of the assertion counts.
