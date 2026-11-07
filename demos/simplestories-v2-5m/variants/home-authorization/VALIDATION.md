# Periodic-reauthorization validation

## Selected image, generation and renewal

The [selected source identity](SOURCE-IDENTITY.json) and [SRAM image](prebuilt/README.md) run at 25 MHz. The [physical campaign](evidence/repair-board-2026-11-05/EVIDENCE-AUDIT.json) uses SRAM programming and restores the known-good plain S-AWIC afterward, without flash writes.

| Check | Result |
| --- | --- |
| Initial approval and context | Base prompt generates `[108,32]` across a valid renewal |
| Home authorization | Ten distinct request nonces; eight valid LMS grants, two policy denials and eight distinct signing leaves |
| Revocation | Withholding approval stops token publication by expiry |
| Reconfiguration and replay | Fresh challenge differs; an old valid grant cannot reopen inference |
| Token checking | 267 CRC-checked reply frames; 258 reference-matched STEP results |
| Common speed | One-token `[378]` prompt and 128 greedy outputs twice; 254 cached outputs / 33.250101333 seconds = **~7.6 tokens/s**, including renewal and host gaps |
| Complete-model RTL | Four source-bound scenarios: valid renewal/context preservation, wrong-model rejection, expiry during inference and corrupt renewal rejection |
| Recovery | Original S-AWIC restored and verified with `[108,32]` and CLEAR; no flash write |

The routed image runs at 25 MHz. The whole-design timing summary reports 121 setup and 55 hold violating endpoints. The 256 listed removal paths show no slack below zero at the printed precision, and the startup-reset review records no reset-entry exceptions. The reset assessment traces a reported hold violation in the entropy control logic. Timing closure across operating corners, clock-domain crossings, entropy quality and physical security remain open. [Routed report](evidence/repair-native-2026-11-05/home_product.tr) · [Reset assessment](RESET-REVIEW.md) · [Timing review](evidence/repair-native-2026-11-05/TIMING-REVIEW.json) · [Mapping review](evidence/repair-native-2026-11-05/REVIEW.json) · [Simulation binding](evidence/repair-native-2026-11-05/SIMULATION-QUALIFICATION.json)

The [raw benchmark](evidence/repair-board-2026-11-05/COMMON-SPEED.json), reference, collector, nonce/grant journal and independent evidence audit accompany the campaign. Each trial has 128 feedback-dependent outputs; the first STEP is excluded from the paired cached metric. All outputs match the independent integer reference.

RTL simulations use actual admission, numerical, UART and LMS/SHA logic with fast flash, modeled DDR, deterministic raw entropy and accelerated timers. They establish functional observations under those models. Current source/proof scopes are in [FORMAL-STATUS.md](FORMAL-STATUS.md).

## Physical model replacement

The [replacement campaign](evidence/model-replacement-v2/RESULT.json) uses its recorded 25 MHz image, SHA-256 `cb0f7d60bbedca7ec504973d26f5093445049a4dbac3435df591231c2ae1922e`. Model A is the base model; model B is a signed synthetic replacement with 320 changed final-normalization bytes. Both have valid signatures from two distinct update authorities and retain the fixed architecture and arithmetic tables.

| Physical check | Result |
| --- | --- |
| A approved | 34 STEP outputs match A's independent integer reference |
| A withdrawn, only B allowlisted | A's renewal is denied and inference output stops |
| B installed | Two 64 KiB model/admission blocks programmed; complete 16 MiB readback matches the candidate, preserving all other bytes |
| B not yet approved | No inference output; a valid A approval carrying B's exact fresh nonce/device cannot authorize B |
| B approved | 34 STEP outputs match B's independent reference, including generation across renewal |
| Revoked A reinstalled | A remains denied after two fresh FPGA configurations while only B is allowlisted; its captured valid approval cannot reopen inference |
| Recovery | Complete starting flash array restored byte for byte; original development S-AWIC image verified with `[108,32]` and CLEAR |

The [local evidence audit](evidence/model-replacement-v2/EVIDENCE-AUDIT.json) checks 68 numerical outputs, 78 CRC-checked reply frames, 90 transmitted command frames, five transmitted grants and seven distinct nonces. Its [six controls](evidence/model-replacement-v2/AUDIT-NEGATIVE-CONTROLS.json) reject changed signatures, wire bytes, numerical claims, replay nonces and a hidden outside-region array change. Four fresh signing leaves are used; the captured replay deliberately resends an earlier grant.

The [public offline checker](tools/check_model_replacement.py) reconstructs and verifies both signed models and both programmed blocks from public assets, then rechecks the raw trace and installation receipts. Complete flash arrays, recovery backups and live signer state remain private. The public replay compares their recorded receipts/hashes; `--private-workspace` additionally compares the complete original array captures. [Reproduction](REPRODUCE.md#model-replacement-evidence) gives the commands and physical sequence. [PUBLIC-COPIES.json](evidence/model-replacement-v2/PUBLIC-COPIES.json) records the redacted copy identities.

B is a controlled synthetic fixture, not a trained fine-tune. Its constant-zero outputs show generation across renewal but cannot independently distinguish preserved context from a context reset; the separate base-model campaign supplies the observable context-preservation check. The two final restarts are SRAM reconfigurations, not electrical power cycles. Revocation is tested with the fixed periodic-reauthorization image; restoring a separate development image is outside that policy boundary. The speed table retains the paired base-model benchmark above.

## Qualification scope and provenance

Physical unpredictability, entropy quantity, hostile clock/power manipulation, electrical power-cycle freshness, universal command-stream behavior, whole-machine refinement and a residual-training bound are not established. The key, device ID and authorization service are public demonstration fixtures. A service outage stops inference by the configured deadline.

[PUBLIC-COPIES.json](evidence/PUBLIC-COPIES.json) maps original capture hashes to path-redacted public copies. Captured source and result identities remain separate from relocated reproduction tools. [REPRODUCE.md](REPRODUCE.md) gives offline checks without hardware access.


