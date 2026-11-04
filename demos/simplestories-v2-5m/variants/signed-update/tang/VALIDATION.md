# Tang S-AWIC validation

The evidence concerns the complete native Tang source composition. It is not a new formal certificate, a physical security assessment or a residual-training bound. Source and input identities accompany the campaigns.

| Campaign | Result and scope | Evidence |
| --- | --- | --- |
| Native-copy LMS verifier | 17 positive/negative cases pass, including published RFC 8554 vectors; real native SHA throughout | [Result](evidence/rtl-lms/result.json), [log](evidence/rtl-lms/run.log) |
| Native-copy admission and page memory | 26 cases pass with private shared RAM ports; real full-image readbacks and native page verification | [Result](evidence/rtl-memory/result.json), [log](evidence/rtl-memory/run.log) |
| Image-derived normalization storage | Both models' 3,328 rows pass on both synchronous ports; reset/masking and illegal coefficient/scale rejection checked | [Result](evidence/norm-store/result.json) |
| Fast complete-token integration | Three signed images boot and produce exact expected UART tokens; invalid signature rejected before model loading | [Base](evidence/tang-fast-simulation/case-0-result.json), [changed norm](evidence/tang-fast-simulation/case-1-result.json), [zero matrices](evidence/tang-fast-simulation/case-3-result.json), [bad signature](evidence/tang-fast-simulation/case-2-result.json) |
| Complete-boot faults | Five cases pass: unsigned image mutation, signed fixed-LUT mutation, signed metadata/image mismatch, signed zero norm multiplier and non-erased slot padding; no model lock | [Result and source hashes](evidence/boot-faults/result.json) |
| Full pin-level SPI integration | Base and changed-norm models pass complete flash transactions, native FIFO/clock ratios, DDR readback and exact UART generation/replay; invalid signature rejected before model loading | [Base](evidence/tang-simulation/case-0-result.json), [changed norm](evidence/tang-simulation/case-1-result.json), [bad signature](evidence/tang-simulation/case-2-result.json), [build](evidence/tang-simulation/BUILD.json) |
| Flash/UART host tooling | Seventeen offline flash-preparation/readback cases, including full-array preservation and aligned block planning, and seven UART framing/status cases pass; no hardware access | [Result](evidence/host-tools/result.json) |
| Evidence overwrite guards | Compile and run wrappers refuse existing campaign outputs; saved receipts/logs remain byte-identical | [Result](evidence/runner-guards.json) |
| Native GOWIN synthesis | Pass: 98,268 / 138,240 logic resources (72%), 55,877 registers and 246 / 340 BSRAM blocks (73%) | [Synthesis report](evidence/native-build/swic_product_syn.rpt.html), [build status](evidence/native-build/STATUS.json) |
| Common speed benchmark | Two runs of input `[378]` and 128 feedback-dependent greedy outputs pass; all 256 IDs match the independent reference; pooled host-observed rate **~10.1 tokens/s** | [Capture](evidence/common-speed-20261103/FINISHED.json), [reference](evidence/common-speed-20261103/reference.json), [raw review](evidence/common-speed-20261103/RAW-REVIEW.json) |

Native routing has completed successfully. The 25 MHz inference clock has a reported Fmax of 25.227 MHz. The timing summary reports 148 setup and 10 hold violated endpoints. Every negative path shown in the bounded setup, hold and recovery tables has both endpoints within the vendor DDR hierarchy; those tables do not exhaust all paths. Generic routing of `clk_50mhz_d` also produces warning PR1014. Complete timing signoff remains open. See the [review](evidence/native-build/REVIEW.json) and [timing report](evidence/native-build/swic_product.tr). Physical board results are recorded separately after their completion checks pass.

## Physical board qualification

All three cases use the same routed bitstream on the Tang Mega 138K non-Pro. The [campaign summary](evidence/board/RESULT.json) binds its hash, model/slot hashes and UART observations.

| Flash fixture | Observed behavior | Evidence |
| --- | --- | --- |
| Base image with one deliberately corrupted signature byte | CLEAR acknowledged; valid APPEND and STEP explicitly rejected with valid CRCs | [UART](evidence/board/bad-signature-uart.json) |
| Valid signed zero-final-norm image | Prompt `[1]` produces `[0, 0]`; CLEAR/replay produces first token `0` | [Generation](evidence/board/changed-norm-uart.json), [replay](evidence/board/changed-norm-replay.json) |
| Valid signed base image | Prompt `[1]` produces `[108, 32]`; CLEAR/replay produces first token `108` | [Generation](evidence/board/base-uart.json), [replay](evidence/board/base-replay.json) |

Before writing flash, two independently initiated complete 16 MiB maintenance-reader captures matched, with another verified durable recovery copy. A faster JTAG read transport was qualified byte-for-byte against both captures. Every installed fixture has an independent complete-array readback matching its expected candidate. All readbacks preserve every byte outside the model and admission regions. Raw flash captures and recovery records remain private. The final running fixture is the signed base model.

These are finite directed hardware observations. They do not establish behavior for every compatible model or command stream, physical attestation, production-key security or complete timing signoff. The inference configuration is in volatile SRAM; the flash updates contain model data and the admission slot.

## Numerical acceptance

The common speed benchmark uses the signed base image. Its two cached intervals are 12.579277084 and 12.545297166 seconds, each spanning validated returns 1 through 128. The headline rate is `254 / (12.579277084 + 12.545297166) = 10.109624...` tokens/s. First-STEP latencies are about 85 ms and are excluded from that rate. The retained raw frames cover all 262 CLEAR, APPEND and STEP transactions; the offline checker verifies their CRCs, tokens, order and caller timestamps. The benchmark does not change the FPGA configuration or flash.

The oracle reconstructs every matrix tensor, projection scale, normalization parameter and arithmetic lookup table directly from the physical image, using [tang_image.py](reference/tang_image.py), then runs the enclosing demo's independent IntegerLlama reference. It does not derive expected tokens from the HDL or simulator observations.

| Signed fixture | Prompt | Two feedback-dependent greedy outputs | Meaning |
| --- | --- | --- | --- |
| Released base image | `[1]` | `[108, 32]` | Native numerical model |
| Synthetic image with the final RMSNorm coefficient vector zeroed | `[1]` | `[0, 0]` | A signed model-parameter change reaches actual token generation |
| Synthetic image with all matrix weights zeroed, retaining base norm parameters | `[1]` | `[0, 0]` | Distinct matrix-weight acceptance fixture |

The changed fixtures are not trained fine-tunes and do not establish model quality. The changed-norm case specifically distinguishes a working dynamic norm path from accidentally retaining the base model's compiled norm ROM. The zero-matrix case changes the other principal model-parameter path while keeping the base norms. Simulated positive cases also CLEAR and replay the prompt, checking the first expected output again. The independent fixtures are described in [fixtures.json](evidence/fixtures/fixtures.json).

## Scope of simulation

The fast campaign supplies tagged flash bytes at core speed, while the full campaign uses the actual SPI pin-level read source and native asynchronous FIFO. Both execute real signature verification, DDR load/readback authentication, fixed-LUT checking, dynamic norm extraction, the native four runtime page banks and complete UART/token arithmetic.

Both replace the raw vendor PHY with the explicit [DDR simulation model](tests/phy_model.sv). That model supplies native clock ratios, calibration, storage, ordered responses and periodic backpressure. The native arithmetic wrappers use their existing integer-equivalent behavioral branches. No analog PHY, native DSP primitive equivalence, timing closure, physical fault resistance or exhaustive command-stream property follows from these traces.

The complete elaboration has 26 width warnings (`WIDTHTRUNC` and `WIDTHEXPAND`); it is not warning-free lint. The separate component's four-state results remain available in the parent [validation document](../VALIDATION.md) and do not become complete-machine unknown/fault-injection proofs.

The [fixture identity check](evidence/fixtures/INPUTS.json) binds the simulator's complete hex stimuli to the signed binary packages and exact norm rows. Additional source audits compare the retained compiled copies, including the fast flash replacement, against the concrete source snapshot: [fast](evidence/tang-fast-simulation/SOURCE-AUDIT.json), [full SPI](evidence/tang-simulation/SOURCE-AUDIT.json). These provenance checks supplement the per-campaign receipts; they do not enlarge their functional scope.

Public evidence copies replace local filesystem paths with descriptive placeholders. Cross-file hashes identify those public copies; [PUBLIC-COPIES.json](evidence/PUBLIC-COPIES.json) records their original capture hashes. The complete original captures remain preserved locally. This formatting does not turn file checksums into a publisher signature or physical attestation.
