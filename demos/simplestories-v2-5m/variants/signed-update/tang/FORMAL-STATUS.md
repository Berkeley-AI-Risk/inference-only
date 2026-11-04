# Tang S-AWIC formal status

**No new formal proof has been completed for the Tang S-AWIC composition.** Its evidence is executable reference checking, RTL simulation and native compilation, with the exact scope recorded in [VALIDATION.md](VALIDATION.md).

The eventual interface theorem should state that, for every public command stream, the locked machine implements only APPEND, STEP with the admitted fixed-geometry model, and CLEAR, or fails closed. Successful signed admission must precede model lock. Under the cryptographic assumptions, admitted model commitments must be authorized by the required distinct fixed authorities. Reset discards the current admission and requires the same checks again. This theorem includes both authorization and functional behavior; it is not established by testing a permanently disabled machine.

For this target, functional refinement also assumes correct external DDR/K/V behavior. Its unprotected K/V store does not support a theorem that tolerates arbitrary hostile K/V-memory modification. The fixed-circuit and memory-environment assumptions must be part of the formal statement.

| Obligation | Available evidence | Formal status |
| --- | --- | --- |
| Canonical parser and distinct-authority signature policy | Real LMS/SHA positive and negative tests | Open |
| Root hashes exactly the runtime table bytes | Native shared RAM read ports; connected memory regression | Open |
| Synchronous signature/intermediate reads supply the requested bytes before hash consumption | Read-address qualifiers and stalled-signature known-answer tests | Open |
| No image transaction before valid admission and erased slot padding | Pin-level bad-signature test; directed padding test | Open |
| Model lock follows ordered DDR readback and all image/metadata/norm/fixed-function checks | Full-size boot simulations and negative fixtures | Open |
| Table/norm storage cannot change during the locked session | Private boot-only ownership and directed simulations | Open |
| Each runtime page is verified before the consumer can read it | Native bank tests and complete token execution | New composition open |
| Boot-to-runtime ownership and reset/CDC are safe | Existing native boundaries exercised in the integration harness | New composition open |
| All public streams refine APPEND/STEP/CLEAR and the admitted numerical model | Directed complete UART traces against an independent image-derived oracle | Open |
| Chosen signed weights and repeated updates have low residual training capacity | No bound established | Open |
| Native primitives, timing, physical tampering and production keys | Outside these RTL simulation claims | Open |

Inherited SHA, bank and arithmetic results are useful building blocks. They do not transfer a whole-machine certificate to a composition with new trust provenance and private RAM ownership. Further proofs must bind the actual [native project](hardware/project/) and make their environment, cryptographic and implementation assumptions explicit.

No monotonic version, delay or lifetime-cap property is claimed: this signature-only policy implements none of them.
