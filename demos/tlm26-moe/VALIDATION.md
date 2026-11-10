# TLM26 MoE validation

The [physical receipt](evidence/physical.json) records one Tang Mega 138K image, SHA-256 `87af5148584729fe3ea1a0d97d247fce773ef533e8ad1408acde7f5cc6af6a42`, with the pinned pretrained TLM26 checkpoint.

- Two five-token prompts produced twelve greedy tokens each. All 24 generated IDs matched both CPU references.
- A boot stream with a single changed bit in an external DDR expert weight reached the affected STEP and returned the canonical refusal frame. The same image with healthy weights returned the expected token.
- Adjacent STEP and CLEAR frames exercised an outstanding first DDR return. CLEAR completed after drainage, the host observed 80 ms without stale replies, and a fresh BOS produced token 403.
- The original SRAM configuration passed its 108, 32 token check after restoration. The campaign performed no flash programming.

Median UART STEP round trip was 577.636 ms over the 24 generated tokens. Each token job includes a fixed 20 ms hold of its first actual DDR return. This is a two-prompt latency measurement, separate from the repository's one-input-token, 128-output paired speed benchmark. Routing decisions in the per-layer traces are CPU observations; the board interface returns tokens.

The [integer reference](evidence/integer-cpu.json) and [checkpoint reference](evidence/checkpoint-cpu.json) agree on both histories and all 120 ordered top-two expert selections for the generated tokens. The [serial-boot simulations](evidence/boot3-simulation.json) cover honest memory and the changed expert weight. Their transcripts and all 28 native build inputs were reproduced in the [clean replay](evidence/clean-replay.json). Use [REPRODUCE.md](REPRODUCE.md) for fresh output paths.

The [native route](evidence/route-volatile3.json) reports a 12.5 MHz token clock and same-domain Fmax of 43.789 MHz. Full-image analysis reports 127 setup and 34 hold violating endpoints; the bounded negative setup, hold and recovery path tables lie inside the inherited DDR IP. The board trials are finite functional observations with these timing limits. They do not establish full-image timing closure or a whole-chip theorem. See [formal scope](FORMAL-STATUS.md).
