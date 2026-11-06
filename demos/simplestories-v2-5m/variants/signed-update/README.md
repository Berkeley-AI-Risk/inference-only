# SimpleStories S-AWIC prototype

This **Signed-Update Authenticated-Weight Inference-Only Chip (S-AWIC)** accepts compatible, signed SimpleStories-V2-5M model packages. Fixed public verification keys authorize new model commitments. S-AWICs and Fixed-Commitment AWICs (F-AWICs) are subtypes of Authenticated-Weight Inference-Only Chips (AWICs). F-AWICs fix the accepted model commitment in hardware; S-AWICs permit new commitments authorized by signatures. This prototype does not establish a residual-training certificate.

**Implemented scope:** a Python package/signature reference, the connected RTL component, and the complete isolated [Tang integration target](tang/README.md). The full target joins real LMS verification, read-only SPI boot, DDR loading/readback, private digest/metadata/norm storage, the four verified runtime page banks and the UART token machine. It accepts compatible full model parameters with the fixed SimpleStories architecture.

Boot binds every signed page digest to the same ordered readback used for the whole-image and fixed-function-table checks. Runtime pages authenticate against that sealed table; [hardware](tang/HARDWARE.md#boot-to-runtime-page-binding) describes the binding and its assumptions.

The Tang target's [validation](tang/VALIDATION.md) separates numerical simulation, source-bound component proofs, native timing and board observations. The whole-machine inference-only theorem and a residual-training certificate remain open.

## Update policy

- Any two of three distinct fixed demo authorities must sign the canonical manifest. All provided signatures must verify; signer IDs are sorted and unique.
- An update supplies the full fixed-geometry model image, its page-digest table and projection metadata. The architecture and package interpretation remain fixed.
- Admission happens only after reset. There is no runtime model-update operation.
- **No deliberate delay, lifetime update cap or antirollback counter is implemented.** The signed version is informational. A valid older signed package is allowed after reset.
- The device holds public keys. Private signing keys are used by the packager, not sent to the device. All keys in this prototype are public demonstration material.

Key compromise allows arbitrary compatible signed weights. This prototype supplies an unrestricted signed-update comparison for a possible delayed variant. It does not claim to prevent training through repeated updates or to retain the fixed-digest design's residual training factor.

See [SIGNED-UPDATE.md](SIGNED-UPDATE.md) for the format and trust boundaries, [VALIDATION.md](VALIDATION.md) for evidence, [FORMAL-STATUS.md](FORMAL-STATUS.md) for proof scope and [REPRODUCE.md](REPRODUCE.md) for commands.

## Source layout

| Path | Purpose |
| --- | --- |
| [reference/signed_update.py](reference/signed_update.py) | Independent byte-level package, LMS signing and verification reference; demo-only CLI. |
| [tang/hardware/project/](tang/hardware/project/) | Complete native Tang target; top `board1_fixed_swic_product_top`. |
| [rtl/su_policy.svh](rtl/su_policy.svh) | Fixed domain, geometry and public demo trust anchors. |
| [rtl/su_lms_verify.sv](rtl/su_lms_verify.sv) | RFC 8554 LMS verifier with real SHA computation. |
| [rtl/swic_boot_admission.sv](rtl/swic_boot_admission.sv) | Strict frame parsing, root/signature verification and private sealed digest/metadata RAM. |
| [rtl/su_image_check.sv](rtl/su_image_check.sv) | Ordered full-image DDR readback check against the admitted digest. |
| [rtl/swic_verified_memory.sv](rtl/swic_verified_memory.sv) | Joins admission, image verification and the existing private page bank. |
| [rtl/vendor/](rtl/vendor/) | Frozen native SHA/page-bank sources, identified by [native-sources.json](evidence/native-sources.json). |

The `rtl/` tree and its component evidence are separate from the complete Tang project. Use [tang/REPRODUCE.md](tang/REPRODUCE.md) for complete-machine commands and [tang/HARDWARE.md](tang/HARDWARE.md) for flash layout and ownership. Changed-model fixtures are synthetic; they do not establish fine-tune quality. Production timing, physical assessment, key management and formal certification remain open.
