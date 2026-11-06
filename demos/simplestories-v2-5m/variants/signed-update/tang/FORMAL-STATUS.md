# Tang S-AWIC formal status

The main inference-only goal is a whole-machine theorem: every public command stream refines APPEND, STEP with the authorized model and CLEAR, or fails closed. Complete numerical refinement, signature authorization, private-memory provenance, cancellation and consumer joins remain separate obligations. The complete theorem is open.

| Source-bound result | Established scope | Limits |
| --- | --- | --- |
| [Boot page consistency](../formal/page-consistency/README.md) | Two base/induction jobs cover exact 7,265,984-byte / 1,774-page accounting, padding, reset/fault closure and exclusive shared-compressor ownership | Hash-child flow is abstract; no SHA correctness, DDR behavior or liveness theorem |
| [Stream assembly](../formal/stream-assembly/README.md) | Five unbounded configurations relate the fixed-wiring wrapper to the indexed-byte snapshot; control/padding/chaining agree and every compression launch has the same complete block | Common arbitrary compressor responses and common initial reset; no native mapping or whole-machine theorem |

The same stream packet supplies a reset-rooted compression-launch witness and a changed-byte sensitivity control. Independent actual-SHA unit fixtures cover two 64-byte pages, a three-page 4 KiB case and the complete model geometry. Directed complete-model simulations and board observations are in [VALIDATION.md](VALIDATION.md).

The ordinary fixed-circuit, cryptographic and memory-environment assumptions must be explicit. This variant uses unprotected external K/V memory; its numerical-refinement claim does not tolerate arbitrary hostile K/V changes. No training attack rate or residual-training bound is established. Physical timing/entropy, production keys and FPGA configuration trust are outside the RTL theorems.
