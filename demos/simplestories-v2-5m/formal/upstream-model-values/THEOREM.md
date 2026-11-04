# Baseline model-read value theorem

For the named baseline sources, successful model reads through the custom
memory path preserve the accepted request's address, ownership, order and
fixed-model word value. This discharges the exact `upstream-word` premise of
the production four-bank cache proof.

Let `M[u]` denote word `u` of the fixed model image, for `0 <= u < 227062`.
Under the boundaries below, every non-error model word published by the
production cache is `M[u]` for its corresponding accepted request address `u`.
The statement covers held responses and replacement. It does not require
completion: a watchdog, error or other terminal condition may fail closed.
Already buffered successful words retain their meaning after a later
application fault; ignored failed-port fields are unrestricted.

The proof operates within the actual common hard-reset epochs. The transport
uses its raw reset inputs only in their conjunction, `common_reset_n`;
both-low base states represent assertion of that common reset. Retained memory
words start arbitrarily in each epoch, with no erasure promise. Public CLEAR
resets neither the custom DDR transport nor the model CDC; the cache caller
also does not cancel accepted model reads on CLEAR.

## Exact external boundaries

1. **Physical vendor storage.** On the sampled healthy physical application
   interface, a return has a previously issued read owner, is a complete beat,
   and supplies the selected word's value at that read, according to preceding
   physically accepted writes. Faulted physical fields carry no desired-value
   promise. The vendor controller, DRAM, analog behavior and physical CDC
   implementation are outside this digital custom-RTL proof.
2. **Trusted model image at runtime entry.** On the parent's one-way transition
   into runtime, the accepted-command write fold at model word `u` equals
   `M[u]`. That fold starts with the arbitrary retained word at the common
   reset and updates only on actual accepted writes to `u`. This is an image
   identity/loading boundary, not a promise about any private reply. The
   original boot module's outputs are unrestricted in the parent model;
   successful boot authentication/loading is not proved in this packet.
3. **Static metadata-ROM binding.** The cache's fixed metadata words are the
   corresponding projection of `M`. This is the same explicit configuration
   condition used by the cache component theorem. The current named image
   and table bindings are recorded in the adjacent
   [component-value package](../native-component-values/README.md).
4. **Digital RTL semantics and actual connections.** The source pins,
   production dimensions, clock/reset connections and two-state formal
   configuration are those supplied with this packet. There is no assumption
   that the host follows a friendly command protocol or that clocks have a
   particular frequency ratio. This component theorem does not yet compose
   the public command parser with the complete forward graph.

No assumption says that a private normalized reply, shared model reply, CDC
reply or cache raw reply already contains the correct model value. Those are
proved interfaces in the composition. No queue-empty assumption is made at
LOCK or runtime entry.

## Why the value is the model word

The native thin transport first proves a stronger correspondence than a
model-range check. A successful core return carries the preceding-write
snapshot captured for its actual accepted core read. The proof keeps the
32-command and 64-return FIFO memories, their native payload values and
independent clocks. It connects accepted-core write histories to physically
issued read snapshots under the vendor storage contract. It also proves that
bad physical captures cannot emerge as successful core returns.

The parent uses the same core clock, reset epoch and accepted lower commands.
Native history joins identify its lower read record with that accepted-core
snapshot. The immediate controller/fault qualification marks a bad first-edge
return before the registered parent fault. The exact sampled parent owner,
end and data predicates therefore follow from the native transport.

The shared routing's owner premise is then closed from parent read/return
counts **before** assuming any shared ownership invariant. Its separate
ownership induction uses no desired model values. That avoids a circular
argument between "this reply is owned" and "this reply is correct."

The actual typed runtime source permits writes only in the K/V region. Its
native invariants, the parent and the startup boundary establish that model
word folds and runtime read snapshots remain `M[u]`. Command FIFO ordering
accounts for queued boot commands; it is not silently replaced with an empty
transport at handoff. The parent/shared record mapping closes the shared
module's exact sampled lower M-word predicate, including otherwise ignored
shared-fault cycles.

Shared accepted-model address histories match the CDC's actual app-read
history. Their response ordinals also agree until the internal sticky app
fault; an immediate fault closes new captures. Complete coverage of the
shared model-response pipeline connects every published word to its raw owner
slot. The shared value theorem therefore supplies the CDC's exact lower
M-word predicate for every target address. The full native CDC induction
preserves those values through its request, response and credit FIFOs.

Finally, the cache's page-fill read and return offsets match the CDC's core
accepted-address history, including wrap. This proves the cache component's
literal predicate:

```text
upstream-word(a, r, M) :=
  ddr_response_fire(a) ->
    ddr_response_data(a) = M[concat(r.page, low7(r.returned))]
```

The existing cache induction then establishes the requested fixed-model word
at its private cache-service response. Static metadata bypasses use the explicit
metadata-ROM/model binding above.

## Arbitrary selectors and the core-history projection

Several native proofs watch an arbitrary fixed address or slot. They are not
bounded tests of a selected slot. Source erasure checks that the added
observations do not drive the circuit. Thus every actual trace admits an
observer extension for every choice of those constants, under the global
vendor storage contract and startup image condition.

The proof makes coverage explicit. The native shared pipeline captures its
actual response-origin slot independently of the watched slot. The parent
similarly captures its ordinal base at the actual sample edge. The respective
seam lemmas need only a final-state selector equality, not a restriction on
all earlier epochs. The SMT selector rules instantiate the arbitrary choice
at that actual origin. Separate slot-independent owner/end lemmas cover
returns outside the parent data observer's selected slot.

At the final cache seam, a small projection copies the CDC's **readonly core
history block byte-for-byte**. It has the same actual core request/return
handshakes, common core edge and hard reset. A native SMT lemma checks its
counter and RAM recurrence. Identical observer updates give the same accepted
address history; the complete functional CDC is still present in its own
native value proof. The projection supplies history coordinates, not data or
an arithmetic producer. It introduces no correct-reply promise.

[CONTRACTS.json](CONTRACTS.json) gives the premise-discharge order, and
[PROOF.json](PROOF.json) gives every native and logical proof rule. The proof
combines native induction with source erasure/instantiation, the common-event
history projection and explicit universal selector elimination. It does not
claim one monolithic solver model of the complete chip.

## Contribution to inference-only confinement

Model immutability rules out changing the model through runtime memory
writes. This result closes a complementary gap: operands claimed to come
from that model really arrive as its requested words, rather than as K/V
contents, a different read's word, stale ownership or an unproved private
reply. Together, those guarantees support fixed-weight inference.

They do not yet prove that every public command sequence invokes only the
intended forward computations. Remaining work includes caller descriptors,
packed coefficient consumption, other arithmetic and attention/K/V value
contracts, and their composition with the command controller. The complete whole-device inference-only theorem remains open.
