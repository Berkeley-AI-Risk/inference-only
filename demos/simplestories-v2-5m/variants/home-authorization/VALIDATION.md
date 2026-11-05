# Validation

## Generation, renewal and timing

The generation and renewal benchmark campaign is [board-25mhz-v9](evidence/board-25mhz-v9/EVIDENCE-AUDIT.json), using the exact prebuilt image at 25 MHz. Its tests program volatile SRAM; the original signed-update image is restored and verified afterward. No flash writes occur in this campaign.

| Check | Result |
| --- | --- |
| Startup | Eight volatile configurations each produce reference tokens `[108,32]` after fresh approval |
| Home authorization | 20 distinct request nonces, 18 valid LMS approvals, two policy denials; unique signing leaves within the campaign |
| Renewal | Passive renewal with zero application commands; valid renewal preserves the exact inference context |
| Revocation and replay | Withheld approval stops token publication; an old valid grant fails against the fresh reconfiguration challenge |
| Token checking | 307 CRC-checked reply frames and 274 reference-matched STEP results |
| Common speed | `[378]`, 128 greedy outputs twice; 256 exact outputs, 254 cached outputs / 34.406163083 s = **~7.4 tokens/s** |
| Full-design simulation | Four source-bound scenarios: valid renewal/context preservation, wrong-model grant rejection, expiry during inference and corrupt renewal signature rejection |
| Reset review | Phase-qualified main release and distinct flash-core reset path; positive removal margins and no reset-entry exceptions |
| Recovery | Original S-AWIC generates `[108,32]`, followed by CLEAR; no flash write |

The [raw timing report](evidence/native-v132/native-report.tr), [source and mapping review](evidence/native-v132/REVIEW.json), [simulation binding](evidence/native-v132/SIMULATION-QUALIFICATION.json) and [reset assessment](RESET-REVIEW.md) state their scope. Core Fmax is 25.005 MHz, with a small margin. This supports the demonstrated functional prototype, not complete vendor-DDR, entropy, production-security or metastability signoff.

The home gate's standalone tests use supplied verified roots and deterministic nonces. Complete simulations retain actual model admission, signatures, arithmetic, UART and nonce conditioning, with modeled external DDR/flash and deterministic raw entropy. Physical replacement under home policy is covered by the campaign below. The software demonstration exercises revoking one signed model and authorizing a second signed model.

## Physical model replacement

The [replacement campaign](evidence/model-replacement-v2/RESULT.json) uses the same published 25 MHz image. Model A is the base model; model B is a signed synthetic replacement with 320 changed final-normalization bytes. Both have valid signatures from two distinct update authorities and retain the fixed architecture and arithmetic tables.

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


The [clean-reset recipient rehearsal](evidence/recipient-rehearsal-clean-reset/RESULT.json) passes all four complete-design scenarios and the 1,200-case flash-reset sweep/count proof from the packaged source. The compiled simulator source snapshot matches the physically qualified configuration byte for byte.
