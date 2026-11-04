# SimpleStories S-AWIC — Tang integration

This is the complete Tang Mega 138K composition of the experimental **Signed-Update Authenticated-Weight Inference-Only Chip (S-AWIC)**. It connects real LMS signature verification to flash boot, DDR loading and readback, private runtime authentication tables, the four-bank verified-page service, and the APPEND/STEP/CLEAR token machine. The target is the non-Pro GW5AST-138C / PG484A board.

The target uses the baseline greedy token machine, with unprotected external K/V storage. The K/V integrity, encrypted-memory and seeded-sampling variants have separate implementations and evidence.

Compatible full model weights, projection scales and all RMSNorm parameters come from the admitted package. The architecture, arithmetic lookup functions, geometry, UART operations and public verification keys remain fixed. A package cannot supply instructions or change the hardware. Both fixed-commitment F-AWICs and signed-update S-AWICs are AWICs: signatures are a form of authentication. F-AWICs fix the accepted model commitment in hardware; S-AWICs authorize new commitments through signatures.

**This is an experimental integration, not a certified inference-only product.** See [VALIDATION.md](VALIDATION.md) for exact completed tests and build status. No new formal theorem, physical tamper resistance, production key-management assurance or residual-training bound is established. The fixtures use public demonstration signing material. The policy has no deliberate delay, update cap or rollback prevention.

Physical board qualification covers invalid-signature rejection, the base model generating `[108, 32]`, and a signed changed-norm model generating `[0, 0]`, with CLEAR/replay checks and the same inference bitstream. The [experimental SRAM image](prebuilt/README.md) and source-bound [board results](evidence/board/RESULT.json) accompany the source. Complete vendor-DDR timing signoff remains open.

The signed base model measures **~10.1 tokens/s** under the repository's common speed protocol: input `[378]`, 128 greedy outputs, two repetitions, and validated-return host timing including inter-reply gaps. All 256 outputs match the independently reconstructed integer model. See the [speed capture](evidence/common-speed-20261103/FINISHED.json), [raw-evidence review](evidence/common-speed-20261103/RAW-REVIEW.json) and [reproduction instructions](REPRODUCE.md#common-speed-benchmark).

The complete native project is [hardware/project/](hardware/project/), with top `board1_fixed_swic_product_top`. The separate component fixture in the parent variant's `rtl/` directory is not the full board target. Other released images and experiment directories are separate.

| Document | Purpose |
| --- | --- |
| [HARDWARE.md](HARDWARE.md) | Boot ownership, flash layout, active model-dependent paths and clock domains |
| [VALIDATION.md](VALIDATION.md) | Evidence, numerical fixtures and exact limits |
| [REPRODUCE.md](REPRODUCE.md) | Simulation, native build and offline flash-preparation commands |
| [FORMAL-STATUS.md](FORMAL-STATUS.md) | Open proof obligations for the complete composition |
| [Parent signed-update protocol](../SIGNED-UPDATE.md) | Canonical manifest, commitment and LMS policy |

An update is an offline replacement of the fixed flash data followed by reset. The inference UART has only APPEND, STEP and CLEAR. There is no UART updater, runtime model-selection mode or private-key input. Losing the signing threshold permits arbitrary compatible models and repeated boot-time replacement; signed authorization alone does not prevent training through updates.
