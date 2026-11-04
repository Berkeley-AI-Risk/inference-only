# SimpleStories SWIC prototype

This experimental **Signed-Weight Inference-Only Chip (SWIC)** component accepts compatible, signed SimpleStories-V2-5M model packages. Fixed public verification keys authorize model commitments. A signature is a form of authentication; the term SWIC distinguishes this update policy from the released fixed-digest AWIC designs. It does not assert a separate cryptographic category or establish a residual-training certificate.

**Implemented scope:** a Python package/signature reference and a connected RTL boot-admission, image-readback and verified-page memory subsystem. The RTL performs actual LMS signature verification using the native SimpleStories SHA-256 compressor. It does not take a software-supplied verification-success bit. The runtime page bank is an unmodified copy of the baseline block.

**This is a component prototype, not a runnable Tang image.** The complete UART/token machine, flash loader, DDR controller, clock crossings and four-bank page service are not integrated with this variant. No board programming, place-and-route or whole-model generation is claimed. The released baseline and other variants are unchanged.

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
| [rtl/su_policy.svh](rtl/su_policy.svh) | Fixed domain, geometry and public demo trust anchors. |
| [rtl/su_lms_verify.sv](rtl/su_lms_verify.sv) | RFC 8554 LMS verifier with real SHA computation. |
| [rtl/swic_boot_admission.sv](rtl/swic_boot_admission.sv) | Strict frame parsing, root/signature verification and private sealed digest/metadata RAM. |
| [rtl/su_image_check.sv](rtl/su_image_check.sv) | Ordered full-image DDR readback check against the admitted digest. |
| [rtl/swic_verified_memory.sv](rtl/swic_verified_memory.sv) | Joins admission, image verification and the existing private page bank. |
| [rtl/vendor/](rtl/vendor/) | Frozen native SHA/page-bank sources, identified by [native-sources.json](evidence/native-sources.json). |

The first integration milestone is a qualified complete token-machine simulation with actual approved model packages. A trained fine-tune, a full bitstream, resource/timing qualification and physical assessment remain open. The changed-model fixtures use a synthetic weight change and a matching image/metadata change, not trained fine-tunes.
