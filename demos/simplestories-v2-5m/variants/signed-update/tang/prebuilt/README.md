# Experimental Tang S-AWIC SRAM image

[`swic_product.fs`](swic_product.fs) is the routed image used for the three directed [physical board cases](../evidence/board/RESULT.json).

- Target: Tang Mega 138K non-Pro, GW5AST-138C / PG484A.
- Bytes: 42197772.
- SHA-256: `4545bd0b0c4076eaea8358d547b19ff0176952417daa0e0f07d1c346aee5fee2`.
- Complete vendor-DDR timing signoff: **open**.

The [native input inventory](../evidence/native-build/INPUTS.json), [build receipt](../evidence/native-build/RESULT.json) and [timing review](../evidence/native-build/REVIEW.json) identify the source and implementation. Proprietary vendor source is acquired separately; it is not bundled.

Use SRAM programming operation 2 after verifying the board and cable as described in [REPRODUCE.md](../REPRODUCE.md). The file is an FPGA configuration, not a model/admission flash data file. It requires the matching fixed flash layout. Do not use it as a complete raw flash array.

This is an experimental demonstration with public signing material, no deliberate delay, no update cap and no antirollback. It carries no new formal certificate or physical tamper-resistance claim.
