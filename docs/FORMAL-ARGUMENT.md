# The inference-only argument and its proof dependencies

We want to verify what a host can make an inference-only chip compute through
its public interface. Suppose the host sends a prompt and asks for the next
token. A successful reply should be the token prescribed by the approved
model for that history and its generation settings. We also want to account
for the work inside the chip. Every multiply and private memory access must
serve the model's inference or a specified supporting operation, such as
authenticating stored data. This restriction must hold even if the host
cancels the request and no token comes back.

A whole-device theorem would establish both guarantees for every sequence of
host inputs on one fixed circuit, under explicit assumptions about the
platform. Component proofs establish parts of this claim. Proving them
together on the same hardware execution remains open.

## The target and its interfaces

The first target is the protected, four-bank SimpleStories-V2-5M circuit with
greedy token selection. We want one top-level theorem that a reviewer can
check by certifying its ACL2 book and its dependencies. An ACL2 book is a file
of definitions and theorems. The hardware books use Centaur's SystemVerilog
semantics to reason about the circuit registers and signals. The numerical
specification states what the fixed model should compute with the chip's
integer arithmetic. [SimpleStories verification objective](../demos/simplestories-v2-5m/FORMAL-STATUS.md#verification-objective)

## How the component proofs fit together

Follow one accepted `STEP` through the chip.

1. **Identify the input.** The controller must associate the request with the
   token history built by accepted commands since the last `CLEAR`.
2. **Compute the model's answer.** Starting with that history, each layer
   must receive the right activations and weights. In attention, the query
   **Q** is compared with keys **K** to determine how to combine values **V**.
   Later layers and the output head must turn that result into the vocabulary
   scores. The greedy selector must choose the prescribed token.
3. **Publish the answer for that request.** The public reply must contain
   the selected token for the same `STEP`. If `CLEAR` cancels the request
   before reply capture, the discarded result must never appear as the answer
   to a later request.

A second obligation applies **throughout** that execution. Each arithmetic
operation and private memory access must have a permitted purpose, operands
and owner, including work that drains after a cancellation. For example, the
model weights must remain fixed during inference, and attention must consume
K/V belonging to the current session. A reported fault must have a cause
allowed by the contract. Those obligations still apply during an execution
that never produces a token.

### Which parts are already checked in ACL2?

| Published result | What it supplies to the larger argument |
| --- | --- |
| **One completed K/V store.** On the reconstructed behavioral RTL, completion entails nine accepted key writes followed by nine value writes. | The addresses and data at the internal memory interface belong to the layer, position and staged values of the same store. The next steps are to establish where those numerical values came from and what attention later reads. [18-write theorem](../evidence/simplestories-kv-record/README.md) |
| **Arithmetic for the first value vector.** On the fixed-point reference, the required range conditions hold for every one of the 4,019 possible first tokens. | This supplies a numerical premise for proving that the RTL produces the reference V vector at layer 0, position 0. [All-token range theorem](../evidence/simplestories-first-v-profile/README.md) |
| **Four RTL value vectors.** Four specified first tokens on the repaired eight-bank behavioral circuit produce the expected 128 V mantissas and shared exponent. | These witnesses connect real signal values to the reference on four executions. The equation for an arbitrary first token and its application to the protected four-bank target remain open. [Four certified witnesses](../evidence/simplestories-first-v-witnesses/README.md) |

There is also a test that follows the **four-bank target** from prompt to
digital UART output. Prompt 378 produced tokens 200, 15, 103 and 157. The
test checks the vocabulary scores as well as the replies, giving a reviewer
a concrete execution of the behavior the theorem must cover for every legal
history. [Four-bank simulation and replay](../evidence/simplestories-protected-prompt378-uart/README.md)

### Where do the earlier RTL proofs enter?

RTL is the hardware description. ACL2, Z3 and cvc5 are tools used to prove
properties about it. The Q operator proof and the detailed implementation results have their own
RTL/SMT replays for the circuits named below. To use one in the top-level ACL2 book, we must identify
the matching circuit signals, state the needed fact in ACL2, and establish its
hypotheses on the same hardware execution as its caller. ACL2 can prove the
obligation directly or invoke Z3 through Smtlink during certification. The
latter route includes the translation and Z3 in the trust assumptions.
[Smtlink documentation](https://acl2.org/doc/index-seo.php?xkey=SMT____SMTLINK)

| Earlier result | Role in the planned ACL2 theorem and the connection still needed |
| --- | --- |
| **Q projection on the baseline circuit.** From the hidden vector present when RMS normalization starts, the proof follows normalization, fixed-weight dot products and the unrotated query through writes and reads of query RAM. | This is part of the model computation in step 2. The caller must show that the starting vector comes from this request's token history. The attention proof must use the resulting query after position-dependent rotation, on the selected circuit. [Q operator](../demos/simplestories-v2-5m/formal/q-operator/THEOREM.md) · [Joined RMSNorm-to-Q proof](../demos/simplestories-v2-5m/formal/rms-q-segment/THEOREM.md) |
| **Boot, reset, queues and memory writes.** The checked SimpleStories paths exclude writes to the model region after runtime lock, including writes queued during boot. Authentication and read-path proofs track checked words to named consumers. | These facts restrict which operands a host can cause the chip to use. The top-level proof must carry the model identity, address and request ownership through to the actual arithmetic. [Detailed implementation proof results](../demos/simplestories-v2-5m/FORMAL-STATUS.md#detailed-implementation-proof-results) · [Authentication and access](../demos/simplestories-v2-5m/formal/authentication-access/README.md) |
| **K/V use after CLEAR.** Protected variants track session epochs, checked cache rows and selected attention inputs. | The target proof must connect an authorized writer to the matching attention input across a later read, cancellation or stall. Computing a digest correctly and consuming the right session's value are separate obligations. [Session and CLEAR results](../demos/simplestories-v2-5m/FORMAL-STATUS.md#working-memory-ownership-and-clear) |
| **STEP and reply ownership on the baseline circuit.** An accepted request owns its candidate commit and reply capture. The proof allows any candidate token at the numerical core's output. | This supplies the control side of step 3. The numerical proof must establish that the candidate came from the vocabulary scores of that very request. [Control theorem](../demos/simplestories-v2-5m/formal/public-control-ownership/THEOREM.md) |

For example, a correct Q projection of the **wrong token history** would still
satisfy a local theorem about the vector presented to the Q operator. Likewise,
the controller could deliver the **wrong candidate** to the right request and
satisfy its ownership theorem. The top-level book must rule out both cases by
connecting the actual values and their owners from acceptance to publication.

## Which results concern other designs?

Seeded SimpleStories adds temperature, a public seed and a sampler. Signed-update
and renewable-authorization variants add conditions on which model may run and
for how long. Those policies need their own theorems. The first greedy proof
can share a component result where the implementations and hypotheses match.
[Seeded sampling](../demos/simplestories-v2-5m/STOCHASTIC-GENERATION.md) ·
[Signed updates](../demos/simplestories-v2-5m/variants/signed-update/tang/FORMAL-STATUS.md) ·
[Renewable authorization](../demos/simplestories-v2-5m/variants/home-authorization/FORMAL-STATUS.md)

Qwen3-1.7B has a separate objective and reported proofs of its authenticated
read and control paths. The release gives their statements and source
identities. Qwen3-8B and the HWIC checkpoint provide engineering evidence on
other implementations. Their proof obligations belong to those designs.
[Qwen3-1.7B](../demos/qwen3-1.7b/FORMAL-STATUS.md) · [Qwen3-8B](../demos/qwen3-8b/FORMAL-STATUS.md) ·
[HWIC checkpoint](../research/hwic/simplestories-2026-10-27/README.md)

## Trust boundary and a reproducible starting point

The digital theorem assumes a fixed circuit, trusted on-chip state and the
clock, reset and external-memory behavior stated for that circuit. The baseline
model-read proof, for example, assumes vendor storage semantics, the correct
model image at runtime entry and the matching metadata ROM. Physical access,
FPGA reconfiguration, implementation timing and equivalence to a programmed
bitstream need separate evidence. Hash resistance remains a cryptographic
assumption even when SHA arithmetic has been proved. [Model-read contracts](../demos/simplestories-v2-5m/formal/upstream-model-values/THEOREM.md)

A claim about which operations may occur also leaves separate questions about
eventual completion, observable fault and timing behavior, and how much
training a person with the chip could perform. The residual training analysis
states its own access assumptions and rating. [Residual training methodology](analysis/RESIDUAL-TRAINING-METHODOLOGY.md)

To try an ACL2 proof, certify the first-value range theorem from the published
model image. To try an earlier RTL proof, replay the protected K/V CLEAR-epoch
example, which recompiles three models and exercises 26 Z3/cvc5 queries.
[ACL2 replay](../evidence/simplestories-first-v-profile/README.md#reproduce-the-proof) ·
[RTL solver replay](../demos/simplestories-v2-5m/formal/kv-clear-epoch/REPLAY-EXAMPLE.md)
