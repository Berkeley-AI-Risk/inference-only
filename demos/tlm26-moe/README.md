# TLM26 pretrained MoE on the Tang Mega 138K

This **F-AWIC** runs the released eight-expert TLM26 TinyStories checkpoint. Its model architecture and weight-page digests are fixed in the FPGA configuration. Each of its five transformer layers has a 64-wide residual stream, eight attention heads, four KV heads and eight 192-wide SwiGLU experts. The trained router selects two experts per layer per token. Vocabulary size is 512 and the hardware supports 256 positions per history. The host tokenizes text and sends token IDs. Attention, expert selection, both experts, their mixture and greedy output selection run in the circuit. [Author model card](https://huggingface.co/h1matthew/tlm26/tree/804c2137003ede3820fc57608221deb620c2d6d7)

[Validation](VALIDATION.md) · [Reproduction](REPRODUCE.md) · [Formal scope](FORMAL-STATUS.md) · [Dependency notices](NOTICES.md)

The weights-only checkpoint has **1,572,032 unique parameters**, with tied input and output weights. Its 6,340,671-byte file has SHA-256 `c12f73ec224a8ee9de02ff81402eb5777c1658e7151ff31998cb0accc358e2a0`. The matching SentencePiece model is `tinylm/data/tok512.model`, SHA-256 `d7f2c1b4c964f0b4a5e136557059e2e4071a3738441d1d104f70d0a36b999cf8`. Evaluation starts with one BOS token. The author's MoE evaluation selects the custom vocabulary dataset, and the data utility selects `tok512.model` for that vocabulary size. The model card declares MIT. The training and inference source carries the included upstream MIT notice. [Pinned evaluation code](https://github.com/ANRGUSC/tlm26/blob/967a9270ff81220421e062393ae56babe6152888/tinylm/eval_moe.py) · [Tokenizer selection](https://github.com/ANRGUSC/tlm26/blob/967a9270ff81220421e062393ae56babe6152888/tinylm/tinystories.py) · [Upstream license](https://github.com/ANRGUSC/tlm26/blob/967a9270ff81220421e062393ae56babe6152888/tinylm/LICENSE)

## Measured on the Tang

The board produced the following continuations with one FPGA image, SHA-256 `87af5148584729fe3ea1a0d97d247fce773ef533e8ad1408acde7f5cc6af6a42`. Both five-token prompts include BOS. Each continuation has twelve generated tokens. All 24 tokens matched both CPU references.

| Prompt | Generated continuation |
| --- | --- |
| `Once upon a time` | `, there was a little girl named Lily. She` |
| `The little cat` | ` was walking in the park. He` |

Median host-observed UART STEP round trip was **577.636 ms** over the 24 generated tokens, with a range of 577.561–577.731 ms. The circuit holds each job’s first actual DDR return for 250,000 semantic-clock cycles (20 ms) to make the outstanding-response test reproducible. The test sends adjacent STEP and CLEAR frames in one host write. The board acknowledged CLEAR after 33.752 ms, emitted no stale bytes during the following 80 ms, then generated token 403 after a fresh BOS. Median idle CLEAR round trip was 16.606 ms.

On the same FPGA image, a second boot stream flipped bit zero of byte 94,208 in layer 0, expert 0’s first SwiGLU projection. The five prompt APPENDs completed with the changed byte already in on-board DDR. The affected STEP returned the canonical refusal frame `5ac1000086` in 84.756 ms. Its healthy control produced token 432. The product exposes token replies. Layer-by-layer routing comparisons in the numerical traces come from the CPU references. The original SRAM configuration passed its 108, 32 baseline token check after restoration. The campaign used no flash programming operations. [Measured UART frames and latency](evidence/physical.json)

## Numerical and RTL replay

The model uses signed 16-bit matrix and embedding weights with 15 fractional bits. RMSNorm weights have 12 fractional bits. Activations have 16 fractional bits and dot products use signed 64-bit accumulation. The integer reference uses incremental KV caching, integer square root and fixed nonlinear lookup tables. The packed model occupies exactly 3 MiB including padding, SHA-256 `221d412a48f1809d6b9cc46ab9f8d572c37af226d07ec710c82bd0d530b49ce1`. The authenticated cache uses Fable’s SHA-256 compressor from the frozen MoE RTL. The FPGA verifies each 4 KiB DDR weight page against its private on-chip SHA-256 digest before releasing weights to the datapath.

The [reproduction guide](REPRODUCE.md) stages a fresh external copy, then fetches the pinned model, regenerates the CPU references and model image, compiles the serial-boot RTL replay, and verifies the recorded board frames. It also reconstructs the exact native inputs for a separately installed GOWIN compiler. This source release includes compact receipts; it does not include a prebuilt FPGA configuration.

The float and integer references agree on all 24 generated IDs and all 120 ordered top-two decisions for the two 12-token continuations in this package. The RTL replay sends all 3,145,728 model bytes through an 8N1 serial receiver, verifies all 768 flow-control acknowledgments, and checks the replies at the serial output. The model of external DDR serves 256-bit reads. Two boot images exercise honest memory and one corrupted expert weight. [FP32 reference](evidence/checkpoint-cpu.json) · [Independent integer comparison](evidence/integer-cpu.json) · [RTL transcripts](evidence/boot3-simulation.json)

## Tang build and provisioning

The selected target is **GW5AST-LV138PG484AC1/I0**. The device-C package shell and vendor source pins come from the existing Tang platform. With the separately installed GOWIN V1.9.12.04-1 toolchain, run `gw_sh build.tcl` in the staged project. On macOS, configure the vendor installation's dynamic-library and framework paths for that process. The native input manifest identifies the exact inputs used in the archived run. Rebuilding on another tool installation can produce different image bytes. [Board input pins](metadata/pins.json) · [GOWIN and Sipeed dependency guidance](https://github.com/Berkeley-AI-Risk/inference-only/blob/ca99e9f022a05e6116b7c5e55c525e48f9b862f5/demos/simplestories-v2-5m/VENDOR-SETUP.md)

After loading the circuit into FPGA SRAM, a boot-only UART receiver accepts the four ASCII bytes `TLM1` and replies `42` hex when DDR is ready. It consumes 768 sequential blocks of exactly 4,096 bytes, acknowledges each completed block with `79` hex, then relinquishes the UART. Addresses and image length are fixed internally. The operational API accepts APPEND, STEP and CLEAR frames. The build has no external flash pins. A bitstream reload restarts provisioning. Runtime reads assume that an accepted DDR request eventually returns. CLEAR discards pending numerical work and acknowledges after an outstanding return drains. Hard reset reinitializes both controller domains and requires the model to be staged again.

For a reserved and recoverable device, use the hardware owner's established SRAM programming and restoration procedure. After provisioning prerequisites are in place, these host commands perform the token and fault checks. Reload the identical FPGA SRAM image between the two commands to enter the boot phase again. The default UART convention is 115200 baud, 8N1.

```sh
python scripts/uart_replay.py --uart "$FPGA_UART" --case honest --out board-honest
# Reload the same FPGA SRAM image.
python scripts/uart_replay.py --uart "$FPGA_UART" --case corrupt --out board-corrupt
```

The routed candidate produced the following timing results. The 12.5 MHz token clock has reported same-domain Fmax of 43.789 MHz. The full-image analysis has 127 setup and 34 hold violating endpoints. In its bounded timing tables the negative setup, hold and recovery paths start and end inside the inherited DDR IP. The design uses 15,127 logic units, 10,760 registers, 248 of 340 block RAMs and 5 of 298 DSPs. [Post-route summary](evidence/route-volatile3.json)
