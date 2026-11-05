# What the RTL proofs establish

This page covers the four current SimpleStories-V2-5M configurations. Qwen has
separate implementation and test evidence; no Qwen theorem is claimed here.

## Verification objective

As in the [Qwen3-1.7B formal program](../qwen3-1.7b/FORMAL-STATUS.md),
the intended whole-design result combines two claims:

1. **Functional correctness:** permitted operations behave as specified.
   `APPEND(token)` extends the logical tape; `STEP` computes, appends and returns
   the fixed model's next token using the configuration's numerical and sampling
   rules; `CLEAR` resets the logical context. Arithmetic, data preservation,
   sequencing, backpressure, reset and clock crossings belong to this claim.
2. **Inference-only restrictions:** arbitrary application command sequences
   remain within the permitted interface. Inputs cannot replace the accepted
   model, bypass authentication, choose another execution program or obtain a
   general private tensor/operand port. Ownership and lifecycle rules must also
   prevent discarded workspace from influencing later inference after CLEAR.

The seeded design additionally permits bounded temperature and public-seed
settings while its tape is empty and idle. Restricted boot/provisioning, status
and diagnostic facilities have their own stated interfaces. Invalid or busy
commands, cancellation and faults need specified behavior as well as legal
inference. The circuit configuration and stated external-service contracts are
assumed fixed.

**The joint whole-design theorem is an objective, not an achieved result.**
Universal whole-model numerical correctness and complete session isolation
through subsequent token output remain open. A restricted interface alone does
not establish correct token computation; correct examples alone do not establish
the restrictions for arbitrary command sequences.

| Proof layer | Functional-correctness role | Inference-only role |
| --- | --- | --- |
| Arithmetic, storage and transport | Establish the specified numerical functions and preserve requested data and ordering. | Supply trustworthy component contracts for restricted computation. |
| Authentication and checked copies | Compute the checked digest and preserve the accepted bytes through use. | Bind computation to the permitted fixed model and protected current data. |
| LOCK, controllers and private access paths | Establish operation/lifecycle and request/reply behavior. | Exclude model writes and unauthorized programs, operands or addresses at the checked boundaries. |
| Working-memory ownership and CLEAR | Establish fresh/current data before consumption and specified cancellation. | Constrain mutable storage to authorized inference state; full post-CLEAR isolation still needs composition. |
| Source-bound composition and implementation mapping | Join contracts at actual ports, parameters and state. | Connect restrictions to the actual circuit; vendor, physical and mapped-image boundaries remain explicit. |

The following sections state the established scopes and the remaining boundaries.

**The source proofs establish restricted model writes, authentication through
use, and fixed private access paths.** The [authentication/access package](formal/authentication-access/README.md)
connects the actual SHA engines, checked model RAM, fixed six-layer schedule,
operand/address routing and protected K/V capture/use. These are source-bound
component compositions, with explicit cryptographic and physical assumptions.

**After runtime LOCK, the custom RTL
cannot issue a write to the model region through the vendor DDR application
interface until the common hard reset. Writes must stay in the permitted runtime
K/V region, including its protection metadata where present.** This includes
model writes that were previously queued in the custom transport during boot.

Z3 establishes this safety property by bounded base checks and unbounded
induction: it holds for arbitrarily long executions of the checked digital
model, under its reset conditions. cvc5 passes the transport's bounded base
checks; its unbounded transport proof remains incomplete. This is a proved
restriction on issued commands, not a proof of the contents or physical behavior
of DRAM.

## Native numerical and model-word value results

The baseline now has a [composed model-read value proof](formal/upstream-model-values/README.md)
through the actual custom DDR transport, runtime wrappers, shared model/K/V
routing, model CDC and production four-bank cache. Successful cache words are
the fixed model words at their accepted request addresses. The cache's correct
raw-reply premise is discharged through those custom RTL modules.

| Result | What is established | Remaining boundary |
| --- | --- | --- |
| [RMSNorm invocation](formal/native-component-values/README.md) | Every successful result agrees with the native finite-width operator on the current accepted role, exponent and complete vector. Retained workspace, stalls and CLEAR cannot substitute another invocation's values. | Caller operand provenance and the full graph remain open; configured stateless DSP correspondence is a platform premise. |
| [Model reads through the memory path and cache](formal/upstream-model-values/THEOREM.md) | Requested model word, ownership and order are preserved through the actual custom transport and wrappers, including held cache returns and replacement. The native preceding-write/read-snapshot proof accounts for queued boot commands. | Vendor DDR storage semantics, the trusted model image at runtime entry and its static metadata-ROM binding remain explicit. Other arithmetic consumers and the whole-device composition remain open. |
| [Q projection operand provenance](formal/q-operand-provenance/THEOREM.md) | Fixed-model coefficients and matching current accepted activations reach all 64 actual Q MAC input pins; current row metadata reaches tile storage, synchronous reads and both postscale coefficient pins. All six layers, four groups and 256 columns are covered. | Baseline operand layer. The complete Q value result is stated in the next row; caller RMSNorm, other consumers and the whole graph remain open. |

| [Q projection and normalization](formal/q-operator/THEOREM.md) | Exact fixed-model Q dot products/scaling, ordered raw rows, the independent normalization algorithm, actual Q write admissions/exponent, full stage completion and current-invocation value ownership. Common-reset, bootstrap and regular trace composition are checked. | Named interruptions may truncate a correct prefix. Caller RMSNorm/whole graph, retained query-RAM reads, timed fault authorization, other configurations and physical implementation equivalence remain open. |

```mermaid
flowchart LR
  V[Vendor storage contract] --> T[Native transport and runtime wrappers]
  I[Trusted model image at runtime entry] --> T
  T --> S[Shared model/KV routing and model CDC]
  S --> C[Production four-bank cache]
  M[Metadata-ROM/model binding] --> C
  C --> Q[Q reader, packer and all native MAC coefficient inputs]
  A[Current accepted activation vector] --> Q
  C --> R[Q row metadata through tile RAM and postscale inputs]
```

The [readable theorem and contract map](formal/upstream-model-values/THEOREM.md)
explain each discharged interface and external boundary. The proof retains the
native FIFO payloads, RAMs, ownership rings, watchdogs and independent physical
clock crossing. It uses no correct-private-reply promise and makes no
queue-empty assumption at LOCK. Its combined fresh reproduction recompiles
eight native models and passes all 1,411 exact queries: 1,404 UNSAT proofs and
seven expected SAT witnesses or countermodels. Native operating and actual-only
defect controls supplement the unbounded proof.

The [Q operand-provenance package](formal/q-operand-provenance/README.md)
connects those model words to the actual Q consumer. It retains the native
projection subtree, queues, saved request owners, packer, tile operand registers
and metadata memories. Every one of the 640 beat bits is covered by constant
coefficient slices and a checked join. The main [SMT-LIB statement](formal/q-operand-provenance/THEOREM.smt2)
names four constituent guarantees; the [readable theorem and diagram](formal/q-operand-provenance/THEOREM.md)
state their meaning and assumptions. Its portable replay checks 449 exact
obligations (438 UNSAT and eleven expected SAT contexts), source reconstruction,
eight native operating/defect cases and logical refusal controls. The 19 other
numerical leaves in its parent control model remain unrestricted. The proof
establishes operand provenance, without claiming arithmetic-result correctness.

The [complete Q operator package](formal/q-operator/README.md) joins that operand
layer to the numerical implementation and actual Q effects. Its 326 UNSAT
implications and three SAT controls have an executable common-trace composition.
The portable qualification recompiles seven numerical models identically and
reruns 17 selected solver queries; all 329 canonical/actual new engine inputs and
the existing dependencies are reconstructed. [The readable theorem and diagram](formal/q-operator/THEOREM.md)
explain the fixed-model dot/scale, normalization, write, exponent and completion
chain. Finite cases cover all layers/lanes, large signed values, cancellation,
zero/impulse inputs, stalls and seven source-only defects. This establishes
interruptible value/prefix/completion behavior, without a termination or timed
fault-authorization claim. The actual normalizer is bound in this composition;
18 unrelated numerical leaves remain unrestricted.

These numerical/value results apply to the named baseline sources. They do not
automatically qualify the other configurations. The main theorem still needs
actual command-to-graph connections, remaining caller/consumer contracts,
arithmetic correctness and attention/K/V value contracts.

## How this supports the inference-only claim

An inference-only machine serves a fixed permitted model while allowing the
temporary state needed for inference to change. Training normally changes learned
parameters; inference changes the token tape, activations and K/V cache. This
result supports the **fixed-model requirement**: after LOCK, the checked RTL
cannot issue writes that update stored model weights through this interface,
while permitting the K/V state needed for inference to evolve. Checking the
underlying write path establishes hardware enforcement of that restriction.
The model-read value proof closes the complementary operand gap: a word claimed
to come from that fixed model really arrives as its requested model word,
rather than K/V contents, a different read's word or an assumed private reply.
The Q operand proof now connects those words to the actual Q MAC and
postscale coefficient inputs, with matching current accepted activations.
The Q operator proof additionally establishes the specified numerical result and
its current-invocation writes. Connecting the remaining consumers and the permitted
command-to-graph schedule belongs to the whole-device proof.

The authentication/access proofs supply further parts of that argument: they
check the actual SHA engines and accepted byte streams, preserve the checked
model copy through consumption, restrict arithmetic to fixed private scheduling
and operand/address paths, and join protected K/V verification to attention use.
They remove ordinary mechanisms for changing model parameters or directly
programming internal tensor computation through the token interface.

These facts do not establish that every token-only algorithm has negligible
training utility. Cryptographic resistance and trusted on-chip state remain
explicit assumptions, and physical enforcement needs separate evidence. See the
[inference-only assessment](INFERENCE-ONLY.md) and
[training-capacity assessment](TRAINING-CAPACITY.md) for those limits.

## Scope of the memory-write theorem

The diagram adapts the request paths in the actual top-level RTL. The green
region marks the composed memory-write proof. The controller has a separate
control proof; the amber boxes identify behavior that remains abstracted or
only partly verified. The gray box is outside the proof.

```mermaid
flowchart TB
    HOST["Public token commands<br/>APPEND, STEP, CLEAR; optional settings"]
    CTRL["UART and token controller<br/>separate control proof"]
    COMPUTE["Private inference and memory services<br/>numerical behavior not fully proved"]
    QSPI["Fixed model image<br/>QSPI reader"]
    AUTH["Image authenticator<br/>four outputs unrestricted in this proof"]

    subgraph WRITE_PROOF["Write-exclusion proof"]
        BOOT["Boot loader and readback sequencing"]
        RUN["Runtime request adapter"]
        OWNER["One-way boot/runtime handoff<br/>LOCK selects runtime ownership"]
        FIFO["Ordered command and return FIFOs<br/>core/application clock crossing"]
        PORT["Vendor DDR application interface<br/>WRITE EXCLUSION PROVED HERE"]
        BOOT <--> OWNER
        RUN <--> OWNER
        OWNER <--> FIFO
        FIFO <--> PORT
    end

    DDR["Vendor DDR controller, PHY and DRAM<br/>outside this proof"]
    HOST <--> CTRL
    CTRL <--> COMPUTE
    COMPUTE <--> RUN
    QSPI --> BOOT
    AUTH -.-> BOOT
    PORT <--> DDR

    classDef control fill:#eaf1fb,stroke:#42658b,color:#172b4d
    classDef checked fill:#e8f5e9,stroke:#2e7d32,color:#172b1a
    classDef abstract fill:#fff4d6,stroke:#9a6700,color:#3d3100
    classDef outside fill:#f3f4f6,stroke:#6b7280,color:#24292f
    class HOST,CTRL,QSPI control
    class BOOT,RUN,OWNER,FIFO,PORT checked
    class COMPUTE,AUTH abstract
    class DDR outside
    style WRITE_PROOF fill:#f5fbf6,stroke:#2e7d32,color:#172b1a
```

Arrows summarize connections and request/reply paths; they do not imply one
numerical-correctness theorem across every box. The memory-write proof permits
arbitrary runtime requests and arbitrary authenticator output flags. Its
write restriction therefore does not depend on those producers behaving
correctly. The actual top-level connections are checked separately.

The proof ends at the custom RTL's **issued command**. It includes the custom
command and return FIFOs, but does not establish when the vendor controller
finishes a write it has already accepted, or what it retains across reset.
Runtime reads of model weights remain allowed, as inference requires them.

## Why queued boot writes cannot bypass LOCK

The composed argument has three steps:

1. **Boot model writes precede readback.** The actual source path proves that,
   once a source READ has been emitted, every later WRITE targets the permitted
   runtime K/V region.
2. **Runtime LOCK requires an earlier READ and reply.** The source path proves
   this even with the four authenticator outputs left unrestricted. It does not
   prove that the digest was computed correctly.
3. **The transport preserves order and reply ownership.** A returned reply
   requires an earlier READ issued at the vendor interface. Model writes queued
   before that READ have already left the custom command FIFO; later writes are
   restricted by step 1.

The reset proof establishes that these histories describe the same reset epoch
across the actual clock domains. All 52 imported FIFO invariants and both source
contracts are independently proved before use; the argument has no circular
dependencies or unproved client protocol promises. It does not simply assume
that the command queue is empty when LOCK arrives.

## Authentication and access through the actual implementation

| Checked boundary | Established result | Main limit |
| --- | --- | --- |
| Authentication to runtime LOCK | 45 assertions per image, both solvers; native ordered byte stream, padding and one BEGIN per hard reset | No formal full native-size successful-boot reachability witness. |
| Native SHA and sealed model RAM through consumption | SHA compression/chaining, fixed digest/metadata selection, complete fill/hash/seal and current service/consumer ownership are source-bound and composed | SHA resistance is assumed. That package leaves private decryption replies unrestricted; the normal K/V return proof below has a separate scope. |
| Fixed schedule and arithmetic/state access | Six-layer sequence: 22 assertions; actual datapath: 53; group/metadata addresses: 23; lookup: 9. Both solvers complete bases, induction and covers | Numerical-child outputs remain arbitrary in the datapath scope; no whole-transformer numerical theorem. |
| Protected K/V through attention use | Both protected designs: 221-assertion history, 357-assertion current guard/cache, 43-assertion actual hash framing/chaining and separate 34-assertion attention scopes; both solvers | Component scopes overlap. The integrity interpretation assumes SHA resistance and trusted on-chip tags/state; confidentiality and physical tampering are separate. |

The [current authentication/access evidence and reproduction guide](formal/authentication-access/README.md)
states the actual source/image joins, proof boundaries, semantic fault controls
and incomplete secondary results. Actual port, reset, CLEAR, fault, identity and
data connections join these universal component facts. The baseline and seeded
designs do not gain integrity against an external K/V-memory attacker.

## Working-memory ownership and CLEAR

The [working-memory evidence and reproduction guide](formal/session-isolation/README.md)
adds completed current-writer histories and ownership checks for native RAMs,
transient state and K/V staging. The baseline/seeded committed cache requires all
nine current data/metadata returns before validity; its actual typed-write
payloads have current stage-writer provenance. These facts constrain mutable
storage to initialized inference workspace at the checked boundaries.

Connected protocol proofs also retain accepted requests through busy CLEAR.
Both shell classes have a complete model-read core barrier. Separate connected
semantic/model/K/V proofs restore all thirty native cache outputs and show that
healthy active semantic idle owes or presents no model or typed K/V work. The
four current images are source-bound to their applicable native classes.

These are component results with explicit initial tracking, numerical-service
and RAM-history boundaries. **Full device session isolation through subsequent
token publication is not yet established.** The common core/outer transport
epoch join, numerical/reply composition and complete mutable-state signoff
remain open. Logical CLEAR revokes ownership; it does not erase raw payload bits.
The packet retains 82 selected component records and thirteen real corruption
controls, including premature drain release and a skipped K/V RAM writer.
Counts overlap and are not a coverage score.

## Normal returned K/V data

The encrypted-memory design has a separate [normal K/V return proof and portable
replay](formal/kv-return/README.md). At the integrity guard's normal live read
response, the complete 256-bit word equals the current committed plaintext word
named by the **actual accepted request**, under the stated digital-memory and
native-function/primitive contracts. The argument follows the actual
seal/store/open producer, capture register, staging RAM, cache, synchronous read
pipeline and output assembly. It does not assume a desired matching decrypted
reply or stable upper input wires while busy.

This is functional storage/data-path correctness. It also supports the
inference-only argument by connecting consumed mutable data to current
authorized writers. It is a component of session isolation; public CLEAR/drain
entry, complete hash/tag/fault correspondence, token publication and physical
DDR refinement remain separate obligations. It does not establish standard-AES
conformance, confidentiality or a whole-model numerical theorem.

Fresh standalone replay regenerates the exact source graph and checks all 27
new point/lifting queries. Concrete native execution checks 72 writes and 72
normal reads across two sessions, 56 cache hits and an in-flight read canceled
by CLEAR. Two actual staging-read defects are detected, including a wrong
normal response with `fault=0`. These finite examples qualify applicability;
the universal component results come from their recorded source-bound proofs.
Imported earlier proof records are supplied and checked for integrity, but
their entire solver campaign is not rerun by this selected replay.

## Public control and important limits

The separate public-controller proofs check which commands are admitted and
how they own state and replies: `APPEND(token)` records an accepted token,
`STEP` owns a generated result that is stored and returned consistently, and
`CLEAR` cancels the relevant ownership and invalidates the logical tape. The
seeded configuration also checks settings and seed ownership at an empty, idle
tape. These are control guarantees; private numerical services remain
unrestricted at their declared proof boundaries. Logical CLEAR does not promise
physical erasure of every memory cell.

The following stronger claims **are not established by these formal proofs**:

| Stronger claim | Current evidence boundary |
| --- | --- |
| Runtime LOCK is formally reachable after a full native-size boot | Board and simulation campaigns exercise completed boot. No formal native-size full-boot LOCK reachability witness is supplied; transport covers use the separately contracted LOCK input. |
| Hash resistance and unconditional physical image equality | Actual SHA arithmetic, fixed-digest admission and checked-copy use are verified separately. Collision/second-preimage resistance, trusted on-chip state and vendor memory behavior remain assumptions; source proofs do not attest persistent physical DRAM bytes. |
| Every STEP computes exactly the fixed model's numerical next-token function | Controller proofs leave private numerical outputs unrestricted. Numerical comparisons and board tests cover particular executions. |
| The programmed FPGA and external memory satisfy the RTL theorem physically | Source and image hashes record provenance. RTL-to-mapped-image equivalence, vendor DDR behavior, physical CDC/reset timing and FPGA power-on behavior remain outside the proof. |
| Every possible use of the machine is incapable of learning | These scoped proofs supply no certified residual training-capacity bound. See [INFERENCE-ONLY.md](INFERENCE-ONLY.md) and [TRAINING-CAPACITY.md](TRAINING-CAPACITY.md). |

The current [implementation-assurance package](formal/implementation-assurance/README.md)
provides the exact models, source bindings, proof receipts, known limitations,
and commands for checking recorded evidence or running fresh solver phases.
The detailed inventories below state which component claims are established
by which solver; assertion counts overlap and are not a coverage score.

## Detailed implementation proof results

| Checked boundary | Current result | Main limit |
| --- | --- | --- |
| Complete boot/memory source path | 113 overlapping assertions pass Z3 and cvc5 for each distinct path; all 227,062 native words remain | Four scalar authenticator outputs are unrestricted; no SHA arithmetic theorem. |
| Native reset correspondence and wiring | 11 reset assertions pass both solvers; 63 top-level connections are checked per image | Digital reset/wiring only; vendor reset generation and physical CDC remain outside. |
| QSPI model reader | 24 assertions pass both solvers; fixed READ03 command and range | Vendor I/O and physical flash protection are outside the theorem. |
| Full-size command and return FIFOs | 28 assertions per channel pass Z3; four of six distinct configurations also pass cvc5 induction | Two encrypted secondary inductions remain unresolved. |
| Source-to-vendor command write epoch | 105 transport assertions pass Z3 for each distinct transport; cvc5 base checks pass | Secondary induction/coverage remains incomplete, including two retained coverage tool errors. Vendor persistence/read ordering is not proved. |
| Connected greedy UART/core/shell | 134 assertions pass Z3 per greedy design | 37 private semantic-layer outputs remain arbitrary; secondary induction is incomplete. Seeded control has its separate result below. |

The 59 selected positive and mutation runs retain their original outcomes,
queries, replies, semantic controls and source audits. Counts overlap and are not
additive. A portable recorded check uses no vendor/compiler/solver tools;
separate commands perform exact source/query reproduction or fresh solver work.
Hardware images, model, host and benchmark records are unchanged. This command-
trace result strengthens the inference-only argument without establishing
whole-machine numerical, cryptographic, physical DDR or RTL-to-bitstream claims.

## Current seeded RTL replay

The seeded-sampling image is
`d271626a7fb9ce1debdf7a9cd847125ec7eb4c907fa9d06af9d5f8146cecc725`.
Its [current replay](formal/current-seeded-sampling/README.md) and named
[completion record](formal/current-seeded-sampling/CURRENT-REPLAY.json) identify
the exact checked models, queries, tools and outcomes. The completion uses
schema `current-seeded-rtl-formal-replay-completion-v2` and records the actual
fresh RTL-only campaign; registering it does not execute a solver again.

| Checked model | Recorded result | Boundary |
| --- | --- | --- |
| Selector lifecycle | **35 assertions**, complete primary and secondary checks | Real fixed-dimension sampler and greedy child; settings admission, seed/PRNG commitment, result ownership, stalls, CLEAR rewind and sticky faults. Not numerical CDF equivalence. |
| Selector buffer ownership | **57 assertions**, complete primary and secondary checks, including the selector's 35 | All three sampler memories retained; complete 4,019-row acceptance, selected-slot current logits/mass and captured-payload ownership. Read-only observers do not drive production. This component is separate from the connected model. |
| UART/frontend | **63 assertions**, complete primary and secondary checks | Real RX/TX at 217 clocks per bit, bridge and adapter; independent admitted-byte/CRC history. Downstream readiness, model and settings replies remain arbitrary. |
| Seeded token shell | **94 assertions**, complete primary and secondary checks | Original 48 controller/tape statements, 11 settings statements and 35 selector statements; actual shell/arithmetic/sampler and 20 memories. Private model/layer/head services remain arbitrary inputs. |
| Connected UART/core/seeded shell | **196 assertions** pass primary Z3 base and induction. Secondary cvc5 passes the base and **194 of 196 conclusions**. | Same whole external boundary and **37 unrestricted private semantic-layer output cuts**. Actual queues, gates, shell, sampler and 20 memories remain. Request CRC conclusion **38** and reply CRC conclusion **73** remain `unknown` for cvc5. |

The connected primary result covers all 196 assertions. Its two unresolved
secondary conclusions are not counterexamples and are not counted as proved by
that solver. Each secondary conclusion uses the same joint prior invariants.
These counts overlap and must not be added. The 57-assertion component is not
inserted into the connected theorem. The connected model has no RTL assumption
cells; reset initializes its base states and is not imposed during induction.

The replay also records seven reset-reachable selector mutants, two buffer
mutants, five serial mutants and 284 actual serial scenarios. These sensitivity
and scenario checks have their stated finite scope; they are not additional
whole-machine assertions.

### Sealed weight-page bank

The separate current seeded bank proof passes **42 assertions with both
solvers**. It retains the real **32,768-bit RAM**, checks fill-before-read,
sealed-copy admission after a completed matching digest comparison, owned
replies, hash-input correspondence, prefetch sequencing and sticky faults.
Ten directed scenarios and five faulty controls accompany that proof.

The bank's **258-bit SHA replies remain arbitrary**. Production SHA is identified
as source provenance but is not elaborated in the bank theorem. The result does
not prove SHA compression arithmetic, the parent service's digest selection,
private bank/SHA composition or cryptographic security by itself. The
[authentication/access proofs](formal/authentication-access/README.md) separately
retain the native SHA and full bank RAM, check parent digest selection and join
the checked copy through the private service to its consumers. Counts remain
nonadditive.

### Source binding and retained support

The current provider verifies **87 distributed native source files and the
selected seeded image**. The full 91-input inventory additionally records four
omitted vendor digests; those digests are provenance, not verified vendor bytes
or elaborated vendor logic. Source audits check reversal of instrumentation,
local elaboration, initialized ROM words, original ports/cuts and read-only
observer cones. The separate finite model campaign checked 30 cases, 108 heads
and 434,052 raw logit rows with the implemented SHA engine; it does not turn
those executions into a universal arithmetic theorem.

The source association retains seven unchanged modular scopes, separate
154-assertion cache-stage evidence and exp-ROM source evidence. The source-binding
action ran no solver and retains its false replay flag. Its recorded primary
cache-stage evidence does not establish full cache equivalence, unconditional
terminal-failure write drain or physical erasure. The named fresh
completion above records the actual controller and bank replay separately.

The replay audits its [98-member support-source inventory](reference/baseline-formal-354/REFERENCE-SOURCES.json), including the monitor support and boundary derivation inputs. Source regeneration checks 128 model/source members and their complete source/binding map byte for byte. These source checks run no solver and grant no additional proof scope.

## Greedy design scope

The baseline, K/V-protected and encrypted designs have their own exact
source/model/native/mapped and physical qualification records in
[GREEDY-QUALIFICATION.md](GREEDY-QUALIFICATION.md). A changed design does not
inherit an older controller, cache, bank or SHA proof merely because it uses
the same numerical model or public command names. Source associations state
which byte-identical components retain evidence and which changed boundaries
remain outside it. Physical timing and resource observations add no assertions.

The selected greedy-source records retain these scoped results:

| Design | Checked source scope | Boundary |
| --- | --- | --- |
| Baseline | 34 attention-controller assertions; 72 recorded query checks | Child arithmetic and memory replies remain unrestricted at the listed outputs. No numerical-attention or concrete-memory composition theorem. |
| K/V-protected | Current joint guard/cache proof: 357 assertions; actual hash and separate 34-assertion attention use composed through checked source connections | Cryptographic resistance and trusted on-chip state are assumptions. No whole-machine numerical refinement. |
| K/V protection and encrypted memory | Native encrypted guard/current cache: 357 assertions; actual hash and separate 34-assertion attention use composed | That authentication/access scope abstracts decryption. The separate normal-return proof below checks K/V data values; confidentiality and numerical attention remain outside it. |

Counts are nonadditive. The [qualification guide](GREEDY-QUALIFICATION.md)
identifies the exact source associations and recorded solver/audit results.
These byte/query rechecks run no fresh solver and supply no physical attestation.

The encrypted design retains K/V integrity and replay checks, but encryption
and the supplied public demonstration keys do not imply a cryptographic theorem.

## Limits

The monitors prove command authorization, operand preservation, STEP/result
ownership, live-tape correspondence and logical cancellation at their stated
boundaries. Private numerical and memory services remain unrestricted at the
listed cuts. They do not establish eventual completion when readiness stalls
forever, the correctness of every generated token, physical RAM erasure,
whole-machine numerical refinement, source-to-mapped-image equivalence,
complete vendor-DDR timing or physical security. Actual SHA arithmetic and the
named model/K/V checked-copy compositions have their separate verified scopes
in the authentication/access package. A successful model or board test does not attest another loaded FPGA.

The assessment assumes a frozen circuit and synchronous digital behavior.
[INFERENCE-ONLY.md](INFERENCE-ONLY.md) and
[TRAINING-CAPACITY.md](TRAINING-CAPACITY.md) state the separate architectural
and conditional capacity assumptions; these proofs supply no certified residual
training factor.

