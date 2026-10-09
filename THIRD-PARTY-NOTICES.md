# Third-party attribution and asset provenance

## SimpleStories model and tokenizer

The selected model is `SimpleStories/SimpleStories-V2-5M`, revision
`c4b3a4bb81297f5316697098e1d4b65c1249daf8`. Its
[pinned model card](https://huggingface.co/SimpleStories/SimpleStories-V2-5M/blob/c4b3a4bb81297f5316697098e1d4b65c1249daf8/README.md)
declares `license: mit`. The declaration is preserved verbatim in
[LICENSES/SimpleStories-MODEL-CARD.md](LICENSES/SimpleStories-MODEL-CARD.md),
alongside [MIT terms](LICENSES/SimpleStories-MIT.txt).
The selected upstream snapshot supplies no separate copyright line; we do
not invent a copyright holder or substitute a training-code repository's
license for the model declaration.

`reference/upstream/manifest.json` records the six upstream assets and their
hashes. The release bundles the exact tokenizer and a quantized model image;
the original floating-point checkpoint can be fetched for reproduction.

| Asset | Provenance |
| --- | --- |
| `assets/board1-real-semantic-image2048.bin` | Fixed quantized/serialized representation of the trained model. |
| `host-app/assets/tokenizer.json` | Unmodified tokenizer from the pinned model snapshot. |
| `hardware/project/fpga/token_only_model0_ddr_board1/fixed_vector_rmsnorm0/recorded/norm_rom34.memh` | Quantized trained normalization coefficients and fixed exponent/scaling encoding. |
| `hardware/project/metadata192.memh` | Projection-row exponents and multipliers derived from model quantization. |
| `hardware/project/digests32.memh` | SHA-256 integrity values computed from the serialized model, including specified page padding; not an additional copy of its weight tensors. |
| `hardware/project/model_rtl_evidence/attention_sublayer/exp_neg_q30.memh` | Numerical exponential lookup generated from the project's fixed-point formula, not learned weights. |

`tools/materialize_image.py` regenerates the image and all four tables.
Their identities are in `MANIFEST.json`. Model derivation does not become
wholly original project authorship merely because a file is small or generated.

## Tang Mega board constraints

`hardware/project/constraints/board1_fixed_product.cst` adapts
`ddr_memory/ddr_memory_test_uart/src/ddr3_1v4_hs.cst` from Sipeed's
`TangMega-138K-example`, revision `06e7d8b118d345915ab6f257b7c22226f81575cd`.
The original GOWIN notice is reproduced unchanged:

```text
Copyright (C)2014-2026 Gowin Semiconductor Corporation.
All rights reserved.
```

The [repository's root license](https://github.com/sipeed/TangMega-138K-example/blob/06e7d8b118d345915ab6f257b7c22226f81575cd/LICENSE)
is preserved in [LICENSES/Sipeed-Apache-2.0.txt](LICENSES/Sipeed-Apache-2.0.txt),
including its notice with the brackets as supplied upstream:

```text
Copyright [2024] [Shenzhen Sipeed Technology Co,Ltd.]
```

Our adaptation renames clock/reset signals and the PLL instance path and
adds UART/flash interface constraints. It is not an unmodified Sipeed example.
An adjacent `.NOTICE` preserves this attribution without changing the tested
constraint bytes or the source-bound hardware identity.

## AES S-box circuit

The encrypted-memory variant's `tang_private_aes256.sv` and
`tang_private_aes256_fixed2.sv` adapt the Boolean S-box in BearSSL's
`br_aes_ct_bitslice_Sbox` to one-bit SystemVerilog signals. The source is
[`src/symcipher/aes_ct.c` at revision `5f045c759957fdff8c85716e6af99e10901fdac0`](https://www.bearssl.org/gitweb/?p=BearSSL;a=blob;f=src/symcipher/aes_ct.c;hb=5f045c759957fdff8c85716e6af99e10901fdac0).
BearSSL credits the underlying Boolean circuit to Boyar and Peralta.
The adaptation retains Thomas Pornin's copyright and full MIT permission
notice in both RTL files and in [LICENSES/BearSSL-MIT.txt](LICENSES/BearSSL-MIT.txt).
The project did not originate this S-box circuit. Adapting it to hardware
does not establish resistance to power or electromagnetic side channels.

## Vendor outputs, source inputs and tools

The included FPGA configurations are GOWIN-device-specific implementation
outputs. All three inference configurations incorporate the selected DDR/clock functions;
the separate reader contains no vendor DDR controller. GOWIN and Sipeed
retain their respective third-party rights. See [LICENSING.md](LICENSING.md)
for the output-distribution judgment and its scope.

GOWIN software, vendor libraries, encrypted source IP and flattened netlists
are not bundled. [VENDOR-DEPENDENCIES.json](VENDOR-DEPENDENCIES.json) identifies
the four separately fetched source files. Their original notices must be
retained when obtaining them. The downloader checks identity, not permission.
Python packages, numerical libraries and verification tools are likewise
installed separately under their own terms.
The openFPGALoader utility used for restoring a complete factory backup is
also installed separately; no copy of its executable or libraries is bundled.

## AI and photographic attribution

The README credits GPT 5.6 Sol and GPT 6 Astra for the custom implementation,
with review feedback from Fable 5.1 and Opus 5.5. Those credits do not cover
the pretrained model, FPGA silicon, Sipeed board, vendor IP or tools.
The owner-supplied board photograph is included in the project's Apache-2.0
grant; its removal of metadata is not an ownership claim about its subjects.
