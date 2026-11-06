# SimpleStories Tang S-AWIC

This Signed-Update Authenticated-Weight Inference-Only Chip design combines real LMS verification, fixed read-only SPI boot, DDR loading/readback, private authenticated tables and the APPEND/STEP/CLEAR token machine. It targets Tang Mega 138K Basic / non-Pro, GW5AST-138C / PG484A. Compatible model weights require signatures from at least two of the three fixed demonstration authorities.

The selected image runs at **25 MHz**. Its two common 128-output greedy trials measure **~10.1 tokens/s**, with all outputs matching the independent image-derived reference. Boot checks the image, fixed lookup tables and every signed page digest against one ordered DDR readback before runtime ownership is released.

| Document | Purpose |
| --- | --- |
| [Hardware](HARDWARE.md) | Admission, page binding, fixed architecture, clocks and storage |
| [Validation](VALIDATION.md) | Source-bound simulations, timing and physical observations |
| [Reproduction](REPRODUCE.md) | Build, offline evidence and board commands |
| [Formal status](FORMAL-STATUS.md) | Component proofs and the open whole-machine theorem |
| [Prebuilt image](prebuilt/README.md) | Selected SRAM configuration and exact hash |

The prototype uses public demonstration signing material and unprotected K/V memory. No deliberate update delay, lifetime cap or independent rollback prevention is implemented. Production key management, physical security, complete timing signoff and a residual-training certificate remain open.
