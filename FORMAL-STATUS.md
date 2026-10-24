# What has—and has not—been formally proved

## What the formalization is meant to establish

The aim is to show that the implemented circuit obeys a precise inference-only
specification: software can use one fixed model through its allowed commands,
rather than select arbitrary internal operations or replace its accepted
weights. For the [fixed numerical SimpleStories model](INFERENCE-ONLY.md#the-idealized-machine-and-the-implemented-interface)
described here, the baseline ideal machine has a token tape and three commands:

- `APPEND(token)` adds an input token to the tape, when there is room in the
  2,048-token input context.
- `STEP` applies the fixed model to a nonempty tape of at most 2,048 tokens,
  appends its next token and returns that token. An extra tape slot holds the
  result at the context boundary.
- `CLEAR` empties the logical tape so a new sequence can begin. In the circuit,
  cancellation and invalidation must also prevent old private work from becoming
  a later public result; logical clearing need not zero every physical cell.

The larger proof objective is to connect the circuit's accepted commands and
completed replies to this ideal machine, including its private state,
authenticated model data and fixed inference computation. This connection is
often called *refinement*: the implementation's public transactions must agree
with the specification. Establishing it requires joining the component
guarantees, not merely checking the parser or the numerical output separately.
That end-to-end theorem is **not yet proved**.

Finite prompt tests check particular executions. A completed induction proof
instead establishes its stated safety properties for arbitrarily long
executions of the checked digital model, with its declared input boundaries
and reset conditions. This can rule out entire classes of unauthorized
commands, stale-state use or mismatched replies within that scope. It does
not establish eventual completion or properties omitted from the model.

## What is checked now, and what it implies

There are two complementary kinds of formal work here. **Lean checks the
abstract transaction specification**, including command effects, tape bounds
and reply counts. Its `nextToken` parameter is an arbitrary function held
fixed throughout an execution; no model weights or numerical inference
algorithm are defined there. Lean does **not** prove that the RTL computes
that function or implements the specification. The
[Lean reading guide](formal/abstract/README.md) maps the definitions and theorems
to these claims.

**Yosys and SMT solvers check selected hardware components and connections**
against assertions about their actual RTL. These include request authorization,
STEP ownership of returned tokens, live tape contents, logical CLEAR behavior,
and scoped weight/K/V memory checks. Some private computation and hash-result
interfaces remain arbitrary inputs. These are hardware safety proofs, not
Lean proofs of the fixed model's numerical next-token computation.

Under the frozen-circuit, reset and synchronous digital-model assumptions,
changing host software or command sequences cannot violate the proved
interface/control properties at those boundaries. This supports the intended
software-facing restriction: token commands must not authorize arbitrary
tensor operations, weight replacement or intermediate-memory access. The
current results do not establish that full restriction end to end, nor do they
bound every computation obtainable through legitimate prompts. They do not
certify resistance to physical modification, probing or fault injection, or
provide a numerical residual-training-capacity bound; see the separate
[inference-only assessment](INFERENCE-ONLY.md) and
[conditional capacity analysis](TRAINING-CAPACITY.md).

The current result is **partial machine-checked verification**, not a complete
proof that the whole FPGA refines the ideal inference-only machine.

## Detailed proof inventory and source scope

The proof receipts below identify the exact sources checked. These results
concern the SimpleStories baseline and the separately identified K/V-protected
components; they do not automatically cover any Qwen design. They do
not certify the [encrypted-memory configuration](ENCRYPTED-MEMORY.md).
The seeded configuration's separate inventory follows below; the original
receipts do not automatically cover that changed controller, even at temperature 0.

**Version scope:** the 48-assertion token-shell and 134-assertion connected
proofs have been replayed against the supplied baseline,
with its current source bindings. The page-bank proof was also replayed;
its SHA outputs are abstracted, so it does not prove the
SHA engine's compression arithmetic. The four-case model simulation
uses that real engine. See the [current baseline replay](evidence/baseline-current/replay.json).
The K/V-protected sources have
separate guard/hash-history, guard/cache/parent and attention capture/use
proofs, replayed with the supplied protected source bindings. The proof's
read-only observation tracks the packed value buffer. Elaboration maps its eight small rows to
explicit registers; the actual capture, aligner and row-write logic remain.
The wrong-coordinate fault control selects an adjacent value
from that packed representation. See the
[current protected replay](evidence/speed-2026-10-02/replay.json).
These results do not establish complete cryptographic integrity or
whole-machine refinement. The protected variant's
[simulation and physical evidence](KV-PROTECTION.md#evidence-and-limits) is
separate from its formal evidence.

| Layer | Checked result | Important boundary |
| --- | --- | --- |
| [Abstract machine](formal/abstract/README.md) | Lean checks the three-command specification, tape bounds, command effects and reply counts. | Its fixed next-token function is abstract; this is not an RTL correspondence proof. |
| Actual UART bridge | Yosys proves 46 assertions by induction covering domain/CLEAR rules, request history, authorization and replies. | This covers the bridge's admitted input bytes, command interface and reply-byte handoff, not the inference engine. |
| UART plus three-operation adapter | 60 joint properties: the 46 bridge properties plus 14 for real operation wires, operand preservation, CLEAR and token-return connections. Two SMT solvers check the complete induction. | Uses the actual front-end instance wiring; the machine backend is excluded and its ready/token inputs are arbitrary. |
| Token-shell controller and tape | 48 assertions covering control, live tape contents, tape overwrite-before-read after CLEAR/reset, and stored/published-token agreement. Both SMT solvers check the complete induction. | Real local arithmetic and memories remain; external private services are arbitrary component inputs. This is not K/V/scratch erasure or the fixed model's numerical next-token theorem. |
| Local typed K/V controller | 59 assertions cover staging data, ordered persistence/commit, owned replies, requested row-piece assembly and logical CLEAR validity. Two SMT solvers check the base and every induction conclusion. | External typed DDR data/completions remain arbitrary inputs. This is not external-memory epoch integrity, scratch erasure or composition with the token shell. |
| Connected UART/core/token shell | 134 joint properties proved by Z3; cvc5 separately confirms 133 conclusions and the base. One checksum conclusion remains unresolved by cvc5. | Retains real core gates, queues, token shell and 17 memories; the six-layer/head service has 37 explicitly unrestricted output ports. Not whole-machine refinement. |
| Verified weight-page bank | 42 assertions, with both solvers checking the complete induction: fill-before-read, sealed RAM, digest-comparison admission, hash-input correspondence and prefetch sequencing, owned replies and sticky faults. | Real 128-by-256-bit RAM is retained; SHA replies and the expected-digest input remain arbitrary. Not SHA correctness or parent-ROM composition. |
| Protected K/V guard/hash history | 221 assertions, both solvers: private write/tag history, independent CLEAR history, epoch advancement, staged reads and hash framing. | All eight guard RAMs retained; SHA compression outputs remain arbitrary. Not cryptographic security. |
| Protected guard/cache/parent connections | 325 joint assertions, both solvers, including the guard's 221, the local cache's 59 and 45 connection/history checks. Includes accumulated data, request identity, exponents and guard-side CLEAR. | Real guard and atomic cache with source-projected parent reset/reply gates; private schedule and arithmetic boundaries remain arbitrary. |
| Protected attention capture/use | 34 assertions, both solvers: request-bound acceptance, key prefetch/exponent, value-aligner input/shift, row assembly and CLEAR cancellation. | Cache reply contents and selected arithmetic/memory children are arbitrary. Real eight-lane aligner retained, without a mathematical input-to-reply theorem. Separate from the 325-assertion theorem. |
| Whole implementation | Exact integer-reference simulations and physical FPGA comparisons provide finite evidence. | Private-memory/computation composition and mapped-implementation correspondence remain open. |

The arithmetic shortcuts have separate equivalence and caller-bound checks
summarized in [the qualification record](evidence/leaf-speed/qualification.json).
Those proof harnesses and logs are not bundled; only their receipt hashes
and summary are included. The public full-model RTL simulations exercise the
supplied arithmetic but do not prove its bounds for every input. The controller
proofs above must not be read as arithmetic-equivalence proofs.

The portable controller replay retains actual memories and both solvers,
including five bounded tape-fault negatives and two reset/CLEAR reuse witnesses.
The 60-property front end includes the 46 UART assertions; these are not
106 separate properties. The front end, 48-property controller/tape and
59-property local K/V results do not yet compose into a whole-chip proof.
The protected composition re-proves those 59 local-cache assertions against
the byte-identical controller inside its 325-assertion model; it does not
assume a separate proof receipt as a theorem.

## Separate seeded-sampling proof inventory

The optional [seeded-sampling configuration](STOCHASTIC-GENERATION.md) now has
[separate source-bound proofs and public replay](formal/seeded-sampling/README.md)
for SETTINGS, sampler/seed ownership and CLEAR/replay. Its connected Z3 proof
passes 196 assertions; cvc5 checks the base and 194 conclusions, with two CRC
conclusions unresolved by that second solver. These new results are separate
from the original three-command receipts and retain scoped component/private
computation boundaries. No whole-machine or numerical-distribution theorem is
claimed.

The [portable seeded replay](formal/seeded-sampling/README.md) checks the exact
distributed RTL and fixed tables associated with image SHA-256
`0e6d30b68bd8757657bc1c3b949ac5b9571a0a8d1f8bb1a6e6018b241f733033`.
Its [recorded receipts](formal/seeded-sampling/recorded/RESULTS.json) and fresh
replay reports preserve the source/model/solver bindings and all unresolved
second-solver conclusions.

| Layer | Seeded checked result | Important boundary |
| --- | --- | --- |
| Abstract four-command machine | 15 Lean 4.33.1 theorems for bounded settings/seed state, transaction effects, CLEAR replay, tape bounds and replies. | Greedy/sample/random-step functions remain abstract and fixed throughout a run. Busy, reset circuitry and faults are separate RTL obligations; no RTL correspondence theorem. |
| Selector lifecycle | 35 assertions, both solvers: atomic empty-boundary settings, accepted-start winner ownership, PRNG commit only on accepted positive-mode results, greedy state preservation, stalls, CLEAR rewind and sticky faults. | Complete fixed-dimension selector and original greedy child remain. Not numerical CDF equivalence. |
| Selector buffer ownership | 57 assertions including those 35, both solvers: complete 4,019-row acceptance and current per-slot logits/mass ownership and captured payload before healthy use. | All three real sampler memories retained; arbitrary read-only slot and child row-count observations have no production feedback. Separate from the connected model. |
| Actual UART/frontend | 63 joint assertions. Z3 checks the complete induction; cvc5 checks the base and all conclusions with identical joint priors. | Actual RX/TX at 217 clocks/bit, bridge and adapter retained. Independent admitted-byte/CRC history; downstream readiness/model/settings replies remain arbitrary. |
| Actual seeded token shell | 94 joint assertions: original 48 controller/tape, 11 settings and 35 selector. Both solvers check base and complete induction. | Real shell/arithmetic/sampler and 20 memories; private model/layer/head services remain arbitrary component inputs. |
| Connected UART/core/seeded shell | 196 joint assertions pass Z3 base and induction; cvc5 passes base and 194/196 conclusions. Request CRC 38 and reply CRC 73 remain `unknown` after bounded supplements. | Exactly the original baseline's whole external boundary and 37 unrestricted semantic-layer outputs; actual queues/gates/shell/sampler and 20 memories. Not whole-machine or mapped equivalence. |

These counts overlap and must not be added. The connected proof keeps 88
baseline statements unchanged and replaces the original 46 UART statements
with 47 extended statements for the new valid frame states/indices. The
57-assertion buffer component proof is not inserted into that composition.
Induction retains every preceding joint assertion; separate cvc5 conclusions
change only the final goal. Solver `unknown` results remain unresolved.

Public replay verifies 87 distributed source inputs plus the packaged image.
The historical 91-input inventory includes four omitted vendor digests; these
are provenance, not vendor bytes verified or logic proved by this replay.
Source reversal, exact local elaboration, all initialized ROM words, original
cuts/ports and read-only observer cones are audited. Nine reset-reachable
formal faulty controls and five directed UART simulation faults are detected.
Mutable payload is not assumed zero, and logical CLEAR does not imply physical
erasure. No new application weight/tensor-write command is added; that scoped
command/control result is not a whole-memory information-flow theorem.

## UART request and reply proof

A verification-only monitor records bytes admitted by the real parser and
independently folds their checksum. It records authorization for a canonical
APPEND, STEP or CLEAR request, an outstanding accepted STEP, and the expected
reply. These records are compared with the actual RTL. No production logic
is replaced or changed; all monitor invariants are proved, not assumed.

The checked properties establish that offered commands have the appropriate
validated request provenance and operand; CLEAR has a validated CLEAR request;
the bridge accepts a model output only while it owns an accepted STEP; and
reply bytes, checksums and non-token zero operands follow the corresponding
response event. Recovery CLEAR retains its authorization while stalled. The
reply monitor also prevents spontaneous or duplicated byte-frame emission.

The proof uses the actual receiver and transmitter at **217 clocks per bit**,
without cutting their internal signals or restricting serial data or downstream
inputs. Yosys checks a reset-initialized base case and closes the joint induction
at length two. The proof has **46 assertion cells and no assumption cells**;
the script's environmental constraint initializes reset at its first two steps.
This is synchronous, two-state RTL reasoning, not an analog or metastability
proof. Proving a reply-byte handoff does not separately prove the transmitter's
complete serial-bit waveform contract.

Five intentionally faulty controls are caught using directed serial simulation:
CRC bypass, altered APPEND operand, nonzero acknowledgement payload, incorrect
reply checksum, and duplicate reply. The unchanged design passes 12 scenarios,
including busy-command rejection/ignoring and stalled recovery CLEAR. These
are **simulation counterexamples for sensitivity**, not bounded SAT proofs or
an exhaustive UART test.

## Scope details that matter

- The frame history is the stream of **admitted** bytes. The current parser can
  retain a partial request over an interval when replies are being transmitted.
  This proof must not be restated as requiring five contiguous physical-wire
  bytes with no ignored bytes between them.
- Model output is an arbitrary 12-bit primary input to the bridge. The proof
  does not establish that this value is the correct next token, or even that
  a faulty model engine always produces an in-vocabulary value.
- These are safety properties. They do not establish eventual completion when
  the model faults or downstream readiness stalls forever.
- A validated CLEAR can start cancellation before a reply acknowledgement.
  This proof does not identify acknowledgement with erasure of every private
  register, FIFO, cached value, or pending memory transaction.
- Checksums protect frame integrity, not adversarial authentication. The
  model-memory SHA-256 mechanism is a different proof obligation.

## What the UART/adapter composition adds

The proof wrapper retains the actual receiver, transmitter, bridge and
three-operation adapter, connected using the instance text from the selected
`uart_core.sv`. Its nine bindings to the backend operation boundary are
checked against that source. The backend itself is not included: readiness,
token-valid and token-value remain arbitrary primary inputs.

The 14 additional assertions carry the bridge's admitted-request authorization
through the real adapter: operation exclusivity and decode, APPEND operand
preservation/range, accepted-command correspondence, registered CLEAR alignment,
and token/ready return mapping. All 60 assertions are proved jointly, with no
assumption cells or internal RX/TX cuts. Yosys and Z3 close the reset-initialized
base and length-two induction. cvc5 checks the base and each of the 60
conclusions under the same joint prior invariant, using eager bit-blasting
with function elimination. This changes the solver strategy, not the theorem.

Ten reachable serial scenarios pass; five deliberately faulty implementations
are detected in simulation: changed APPEND operand, APPEND misrouted as STEP,
dropped CLEAR, changed return token and dropped token readiness. The portable
replay checks source bindings and both solvers, including a raw-result recheck.
These simulation controls are not bounded SAT proofs. This component does not
prove the backend token's vocabulary/numerical correctness or compose the
controller, caches, clock/reset machinery or mapped physical implementation.

## What the controller proof adds

The controller proof tracks accepted-STEP ownership and result commitment,
checks the 2,048-input/2,049-slot bounds, and proves exact next-cycle logical
count updates. Public token output requires an outstanding STEP and an
in-vocabulary result. At most one result can be committed and consumed per
STEP; **eventual completion is not proved**. A held result register remains
stable under backpressure, with explicit reset/CLEAR/fault cancellation.
CLEAR empties the logical tape/prefix and retained-output state and keeps
that state empty through draining, without reopening a terminal failure.

This uses the actual embedding, normalization and argmax children and their
memories—no internal value/handshake stubs. The model-memory and six-layer/head
service ports remain arbitrary inputs to the selected component, so this is
not a proof of the model's numerical output or of those services.
There are no RTL assumption cells; reset initializes the base only. All
phase invariants are proved together by induction, with 48 assertions. Both Z3 and
cvc5 check the complete induction, with cvc5 checking the identical joint
conclusion as 48 separate obligations. The portable replay includes five tape
mutations that produce reset-reachable bounded counterexamples. A separate internal source
audit reproduces the elaboration and checks every normalization ROM word.

The tape monitor watches one arbitrary, constant slot; proving the
property for that unconstrained choice covers every slot. It records which
APPEND or generated-result commitment wrote the slot since reset/CLEAR, then
compares that history with the **actual** RAM and embedding input register.
The symbolic index never drives production logic or replaces a value path;
the replay checks its complete forward dependency cone. Mutable RAM is not
assumed zero. Two reachable examples explicitly retain token 17 across CLEAR
or reset, then overwrite it with token 29 before the new embedding request.
These examples check reachability; they are not assumptions of the safety proof.

For each live slot, the RAM equals its recorded current-epoch token. A token
presented to the user equals the token stored in the new last slot. This is
transaction/data-path agreement, **not proof that the token is the model's
mathematically correct prediction**. It does not establish that every compute
phase or full-context output is reachable; the broader cover obligations remain.

The proof preserves synthesis-mode production logic. Unqualified
`ifdef FORMAL` checks are not enabled or silently counted as proved. As with
the UART proof, this is synchronous two-state reasoning, not physical signoff.

## What the local K/V proof adds

An arbitrary read-only coordinate observer checks the actual staging registers
against accepted values. A healthy persisted pending row requires all 18 typed
write completions, and commit changes exactly the matching logical prefix.
The row-assembly observer requires all requested pieces before a healthy
committed-row reply. Pending replies use fully staged data; unrequested halves
and fault payloads are masked. Reply ownership and CLEAR/reset validity are
checked without claiming that logical CLEAR physically zeros the storage.

The unchanged production controller and both real address mappers are retained.
Z3 and cvc5 pass the reset-initialized base and k=2 induction, checking each of
the 59 conclusions against the same joint invariant. There are no assumption
cells or internal value cuts. A fanout audit verifies that the seven-bit
coordinate selector cannot drive production paths. All 6,160 bits of staging
and assembled-row storage retain unconstrained initial contents. Five faulty
implementations are detected in reset-reachable BMC, and two witnesses show
old staging data retained while invalid and overwritten on reset/CLEAR reuse.

Typed DDR data and completions are still component inputs, not a trusted-memory
model. The result proves local assembly/visibility rules, not the provenance
or physical integrity of external DDR contents. In particular, it is not a
cryptographic integrity proof for cached activations.

## Connected public-command and real-token-shell proof

`formal/composed-shell` joins the actual UART/adapter to the real core gates,
four model request/reply queues, private owner arbiter, token shell, tape,
embedding, normalization and argmax. It jointly proves 108
front-end/controller properties and 26 connection/gating properties. Monitors
do not change production behavior: the replay checks instrumentation reversal,
37 declared service-output cuts, all 17 actual memories, 3,328 ROM words and
the symbolic tape observer's complete no-production-fanout dependency cone.

Z3 proves reset feasibility, the reset-initialized safety base and joint
length-two induction for **all 134 assertions**. There are no RTL assumption
cells; initial reset is explicit in the proof script. External model/KV
responses, model lock, faults and six-layer/head service outputs are unrestricted.
The private computation boundary remains a real limitation: this does not
prove transformer numerics, page SHA correctness, or private-DDR provenance.

A separately audited cvc5 check proves the base and **133 of 134** induction
conclusions using the same joint prior invariant. The remaining conclusion,
number 39, equates the UART parser's running checksum with its admitted-byte
history. It remains unresolved by that solver. The source/query auditor checks
the same induction formulas throughout. An `unknown` is neither a
counterexample nor a passing second-solver result. The packaged
replay can reproduce the full secondary check; it never counts an unknown as
proved. The primary proof of all 134 properties remains a distinct result.

Thirteen directed real-serial scenarios pass. Five intentionally faulty
connection/tape variants are caught by independent testbench checks. These
are finite simulations, not an unbounded serial-waveform theorem. The source
and query identities in `expected.json` bind the portable proof to the audited
result, not to an assumed correspondence with a synthesized bitstream.

The standalone replay's default success means primary induction, exact query
correspondence, serial tests and structural audits passed. It does **not** mean
the optional secondary solver completed, or the entire chip was verified.

## Remaining machine-level proof

The remaining work is to compose the public controller, private K/V paths,
scratch overwrite and fixed inference computation in one machine-level
statement. The protected guard/cache proof advances external K/V generation
and transaction ownership, but its private semantic controls remain abstract
and the attention theorem is separate. In particular, interrupted
operations and CLEAR must not let old internal work become a later public result,
and public requests must not select private tensor/memory operations. Those
facts need to compose with authenticated model memory and the fixed inference
computation, under explicit reset and memory assumptions.
An implementation correspondence argument must then relate verified RTL to
what synthesis and mapping actually put on the FPGA. Physical tampering and
timing/side-channel claims require separate treatment.

Frozen FPGA configuration, or an equivalent fixed ASIC, remains the intended
assessment boundary. None of these proof results certifies resistance to an
invasive physical attacker.

## Sealed weight-page bank

The actual weight-bank RTL has a 42-property component proof,
including its full RAM. Both solvers check the complete reset-initialized
induction. The checks establish that inference uses the sealed copy only
after a matching completed digest comparison, and that read cancellation
cannot clear an integrity fault. Ten directed scenarios and five deliberately
faulty variants accompany the proof; a separate source/query/observer audit
checks the replay. The assertion count includes supporting invariants for
prefetching the next hash-input block while the compressor works on its
previously captured block. The bank supplies the correct sealed bytes when
launching each compression; its input register need not remain unchanged
after the compressor has captured them.

The SHA compressor replies are unrestricted inputs to this theorem. It does
not prove SHA correctness, the parent service's fixed-ROM selection, external
K/V authenticity or whole-machine refinement. See the
[precise boundary and reproduction instructions](formal/page-bank/README.md).

## Protected K/V guard, cache and attention

The 221-assertion guard proof traces accepted private writes through the
full partial-page RAM, write hashing, private expected-tag RAM and later read
comparison. It also traces read data through the staged, verified copy to
the returned word. Identity includes layer, page, head, role, position count
and epoch (the CLEAR counter). Prefix invalidation and tag replacement are
the freshness mechanism; the epoch provides additional separation. Its
increment, stability and saturation-fault behavior are checked, along with the
circuit's previous-CLEAR register against independently recorded CLEAR history.
CLEAR revokes ownership without clearing a terminal integrity fault.
The actual page-hash wrapper's header, byte order,
length and sequencing are included; its SHA compressor is not.

The 325-assertion joint result connects that guard to the actual atomic K/V
controller and address mappers. Real core reset/reply gates and shared-wrapper
lock/fault registers are extracted from the parent sources; the actual
intermediate instance bindings and shell CLEAR pass-through are checked.
This is source-projected composition, not a proof of every parent register.
Surrounding semantic control, arithmetic and attention requests remain
unrestricted private inputs. Every required piece of a healthy committed-row
response has matching guard-admitted history. A separate accumulated-row
observer checks the returned vectors and exponents against the guard's data.
The response matches the requested layer, position, head and role. The
pending-row path retains its internal staging provenance and all 18 required
write completions, including the exponent bytes in writes and pending replies.
Public CLEAR is checked on both the atomic-controller and guard sides.

A separate 34-assertion theorem checks the real attention controller's
capture, key prefetch, value-row assembly and cancellation. Live use requires
acceptance of the reply to its own outstanding request for that kind, position
and head. This theorem leaves reply contents arbitrary; the separate joint
cache theorem checks response descriptors, and source checks connect the
request pins. Key operands match
the captured row, and the pending score exponent uses the accepted key and
captured query exponents. The real value-aligner input uses the correct group
and the shift derived from the accepted exponent and the controller's common
alignment-exponent register. The scan that computes that common exponent is
not proved numerically correct. Value operands come from a completely assembled
set of real eight-lane aligner replies. Selected other arithmetic/memory children
have unrestricted outputs. This does not prove attention's numerical result
or the aligner's input-to-reply arithmetic against an independent specification.

Both solvers complete reset-initialized induction for all three results.
There are no assumption cells, reduced guard memories or shortened timeouts.
Source/query audits check non-driving observers, retained geometry and direct,
distinct unrestricted abstraction outputs. Four deliberately faulty formal
copies have reset-reachable counterexamples. Another 23 targeted checks use
22 distinct faulty source copies, including digest comparison, tag publication,
sealed-copy return, hash framing and CLEAR history. Their counterexamples are
to induction, not demonstrated reset-reachable attacks. The replay reconstructs
their models and queries, checks raw answers, and checks the recorded target
indices and hashes. There are 44 core auditor tests and eight additional
fault-evidence tests. None of the faulty copies was programmed. The audits
share model generators with the runners and are not independent review.

These checks strengthen the evidence at specific boundaries. They do not
prove that every accepted private write is the fixed model's mathematical
output, join attention into the guard/cache induction, or establish SHA
correctness, mapped-circuit equivalence, physical timing or tamper resistance.
The standalone replay binds its sources to the recorded protected-build inputs
and names the associated image; that is not a synthesis-equivalence proof or
attestation of a connected FPGA. A whole-design check covering every data and
control path from external memory is not part of this replay.
See [the detailed scope and replay](formal/kv-integrity/README.md).
