# Validation

The current physical campaign is [board-25mhz-v9](evidence/board-25mhz-v9/EVIDENCE-AUDIT.json), using the exact prebuilt image at 25 MHz. All tests program volatile SRAM; the original signed-update image is restored and verified afterward. No flash writes occur in this campaign.

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

The home gate's standalone tests use supplied verified roots and deterministic nonces. Complete simulations retain actual model admission, signatures, arithmetic, UART and nonce conditioning, with modeled external DDR/flash and deterministic raw entropy. The base signed-update design separately tests compatible changed model weights; this home-authorization board campaign tests one base model and does not claim a physical replacement-model test under home policy. The software demonstration exercises revoking one signed model and authorizing a second signed model.

Physical unpredictability, entropy quantity, hostile clock/power manipulation, electrical power-cycle freshness, universal command-stream behavior, whole-machine refinement and a residual-training bound are not established. The key, device ID and authorization service are public demonstration fixtures. A service outage stops inference by the configured deadline.

[PUBLIC-COPIES.json](evidence/PUBLIC-COPIES.json) maps original capture hashes to path-redacted public copies. Captured source and result identities remain separate from relocated reproduction tools. [REPRODUCE.md](REPRODUCE.md) gives offline checks without hardware access.


The [clean-reset recipient rehearsal](evidence/recipient-rehearsal-clean-reset/RESULT.json) passes all four complete-design scenarios and the 1,200-case flash-reset sweep/count proof from the packaged source. The compiled simulator source snapshot matches the physically qualified configuration byte for byte.
