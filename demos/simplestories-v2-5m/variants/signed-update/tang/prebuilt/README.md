# Tang S-AWIC SRAM image

`swic_product.fs` is the selected, board-tested Tang Mega 138K Basic / GW5AST-138C configuration at 25 MHz.

SHA-256: `8472e592c68a4b2425be4ecb8f57bde855d3be5df140f96bbe417226d1dca370`.

The [source identity](../SOURCE-IDENTITY.json), [native review](../evidence/repair-native-2026-11-05/REVIEW.json) and [board validation](../VALIDATION.md) bind its source, timing and physical observations. Separately licensed vendor source is not bundled. Use SRAM programming operation 2 with a freshly discovered cable location and the matching model/admission flash data; [reproduction](../REPRODUCE.md) gives the commands.

The image uses public demonstration keys. It implements no deliberate update delay, lifetime cap or independent antirollback policy. Whole-machine certification, production timing and physical security remain open.
