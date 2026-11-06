# Tang S-AWIC validation

The selected [source identity](SOURCE-IDENTITY.json) and [SRAM image](prebuilt/README.md) describe the current complete Tang composition. Its inference clock is 25 MHz. Source-level proofs, modeled RTL runs and physical observations retain separate scopes.

| Check | Result and evidence |
| --- | --- |
| Boot page accounting and compressor ownership | Two full-geometry component induction jobs; [scope and records](../formal/page-consistency/README.md) |
| Stream assembly | Five unbounded wrapper-equivalence configurations, launch witness and changed-byte control; [packet](../formal/stream-assembly/README.md) |
| Actual SHA | Three deterministic geometries, including all 1,774 pages and the final zero tail; [unit receipt](../formal/page-consistency/records/unit/RESULT.json) |
| Normalization | Both models' 3,328 rows on both read ports, reset and output masking; [unit](evidence/consistency-verification/normalization-unit/result.json) |
| Complete numerical RTL | Signed base and zero-final-norm model produce `[108,32]` and `[0,0]`, with CLEAR/replay and all norm rows checked; [build](evidence/consistency-verification/BUILD.json), [base](evidence/consistency-verification/case-0-result.json), [changed model](evidence/consistency-verification/case-1-result.json) |
| Native route and timing | Route completes; reported core maximum 25.377 MHz. All five real-clock setup/hold summaries are clean; [review](evidence/repair-native-2026-11-05/REVIEW.json), [raw timing](evidence/repair-native-2026-11-05/swic_product.tr) |
| Physical base model | Prompt `[1]` generates `[108,32]`; [candidate observation](evidence/repair-board-2026-11-05/candidate-base.json) and [image identity](evidence/repair-board-2026-11-05/BOARD-RESULT.json) |
| Common speed | Two one-token `[378]` prompts, each with 128 feedback-dependent greedy outputs; **~10.1 tokens/s**; [capture](evidence/repair-board-2026-11-05/FINISHED.json), [reference](evidence/repair-board-2026-11-05/reference.json), [raw replay](evidence/repair-board-2026-11-05/RAW-REVIEW.json) |
| Recovery | Original S-AWIC restored and UART verified; no flash write; [result](evidence/repair-board-2026-11-05/RESULT.json), [restoration](evidence/repair-board-2026-11-05/RESTORED.json) |

The paired cached intervals are 12.579301666 and 12.562350208 seconds. The pooled rate is `254 / (12.579301666 + 12.562350208)`, approximately 10.1 tokens/s. First-STEP latencies are retained separately. All 262 CLEAR/APPEND/STEP transactions are replayed offline for CRCs, reference IDs, order and monotonic caller timestamps. Host-loop gaps are included.

The [complete-array readback receipt](evidence/repair-board-2026-11-05/readback-record.json) records exact equality with the expected 16 MiB base-model array. Its [reuse provenance](evidence/repair-board-2026-11-05/READBACK-REUSE.json) retains the original capture from the same SRAM-only campaign; intervening recovery uses SRAM/USB/UART operations and no flash write. Raw arrays remain private.

The oracle reconstructs matrices, projection scales, normalization parameters and lookup tables directly from the physical image using [tang_image.py](reference/tang_image.py) and the enclosing independent IntegerLlama reference. Expected outputs are not derived from HDL observations. The changed-norm fixture is synthetic and supplies no fine-tune-quality result.

Complete-model simulations retain actual numerical and LMS/SHA RTL with fast flash, modeled DDR storage and behavioral DSP branches. They do not exercise analog DDR or establish native primitive equivalence. The bounded native negative-path tables retain only vendor-DDR negatives; full timing/PVT/CDC signoff, physical attestation, hostile-memory tolerance, production keys and the whole-machine inference-only theorem remain open.

Additional [component](../evidence/component-snapshot/) and [directed board](evidence/board/RESULT.json) packets retain their own source and bitstream identities. Their observations have those explicit scopes.
