# Conditional authorization-control statement

For the selected source and production parameters, starting from reset in the
binary clocked model, the joined controller/permit/runtime/UART slice satisfies:

1. A token-response frame starts only while inference permission is live for
   the unchanged admitted model. Permission has a grant witness since reset.
   That witness requires a complete 128-byte request and 1,420-byte grant frame,
   matching header fields, a fresh verifier start and a successful verdict.
2. The signed message is exactly `DOMAIN[16] || DEVICE[16] || NONCE[32] ||
   MODEL-COMMITMENT[32] || GEOMETRY[32]`. All echoed header bytes match it. The
   real registered signature RAM supplies the current frame's bytes. The
   post-admission real verifier join captures the fixed home key and 128-byte
   message length in the current verifier epoch; a prior verdict cannot survive
   that epoch's reset.
   The real boot-admission/shared-owner/home-controller handoff is also checked:
   lease ownership starts with verifier reset asserted and no retained boot
   verdict. Runtime model readiness implies sealed admission through the
   selected source-derived guard chain. It also requires the boot page-checker's
   verification predicate. The separate page-accounting component proves its
   input/page coverage under an explicit SHA-flow contract.
3. A response starts with more than 20,000 remaining lease clocks and reaches
   UART quiet within 10,855 clocks. Without an independent terminal fault or
   reset, enough permission remains throughout that reply and the normal
   authorization transport cannot pause it midway.
4. Without live permission, the token engine and runtime reset remain asserted,
   model/KV request admission and raw runtime request offers are suppressed,
   and the external token-serial path is clamped. Home-protocol transmission is
   a separate mux branch carrying its fixed request protocol.
5. Waiting for renewal consumes the old lease budget. A challenge grants at
   most once; a subsequent grant requires a different captured nonce. Zero and
   an immediate-repeat nonce fail closed. Expiry/failure is sticky until reset;
   late bytes or a retained verifier verdict do not revive permission.

These are authorization-control invariants and a bounded reply-progress
property. They do not establish that every numeric result equals a transformer
specification, nor the complete external-command refinement theorem.

## Contracts required for the security interpretation

- **Admitted model and memory.** The private commitment identifies the weights
  served by authenticated memory, with the stated fixed geometry. Model boot
  admission, two-of-three update-authority checks, authentication and numerical
  consumer correctness have their own obligations. Shared-verifier ownership
  transfer is checked through the real admission controller and mux, with
  shared SHA outputs abstracted. This proves control isolation through boot;
  it does not independently specify or prove the complete payload-validation
  algorithm or physical DDR image semantics.
- **Cryptography.** A successful LMS verdict under the fixed home trust anchor
  means a valid authorization of the specified message. The real verifier's
  control/key/reset connection is checked, but shared SHA results are arbitrary
  in that proof. LMS/SHA algorithm correctness and cryptographic security are
  not discharged by these controller lemmas.
- **Nonce freshness.** The private source supplies unpredictable, fresh nonces
  across renewals and power cycles. The controller's zero/immediate-repeat
  checks do not provide a persistent history of all nonces or reset-resistant
  anti-replay state on their own.
- **Implementation.** Actual hardware conforms to the binary synchronous RTL
  and its clock/reset/memory contracts. The proof uses `async2sync`, not analog
  metastability, clock tampering, physical fault injection or implementation
  equivalence. All private abstract input seams in the joined SAT proof are
  explicitly constrained to binary values; no input-output correctness is
  assumed for numerical clients.

The lease is measured in core clock cycles. The ten-second demonstration
interpretation assumes an intact 25 MHz clock. It is not an unhackable wall
clock, and signing a model update does not itself provide home-base permission
to run that model.

## Proof construction and limits

The main join contains the actual lease controller, selected top-level permit
register and UART mux, selected runtime-reset release, actual backend arbiter,
and actual token UART bridge/TX/RX. Numerical clients and untrusted transport
bytes/results are abstract binary inputs. The unused signature-data output
cone is cut in that join and independently covered by the real-RAM lemma and
the post-admission verifier join. Existing unrelated arbiter count/owner
assertions are excluded from this authorization-specific job; its functional
RTL and request guards are retained.

The verifier join retains the real grant controller/RAM and LMS controller,
with shared-hash results abstracted. The complete handoff job also retains the
actual admission controller, manifest/signature RAM and shared-owner mux.
A separately proved Boolean factorization of its phase-exclusive owner
expression avoids a structural loop introduced by the formal async-reset
conversion; production RTL is unchanged. Observation ports and ghost histories
add no functional control. A 75-connection source correspondence audit and
32 boot/model-lock and page-port connections link these
selected excerpts and interfaces to the published wrapper hierarchy. This is
a composed authorization slice with explicit contracts, not a monolithic proof
of every block or every physical input of the chip.

Induction closure establishes the invariants for arbitrarily long clocked
executions under these contracts. The small induction depths are not the
length of execution covered. Finite witnesses and mutation controls support
non-vacuity and harness checks; they remain separate from unbounded proofs.

The source history retains the preceding committed input inventories. Unchanged
extracted proof designs and their original engine receipts are preserved; the
page-verification model-lock cone has its own fresh Boolean proof. Current source
hashes and regenerated design/port checks establish the stated correspondence.
This rebinding does not convert retained witnesses or mutation controls into
new executions.
