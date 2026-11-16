# TLM26 MoE validation

The [physical receipt](evidence/physical.json) records one Tang Mega 138K image, SHA-256 `87af5148584729fe3ea1a0d97d247fce773ef533e8ad1408acde7f5cc6af6a42`, with the pinned pretrained TLM26 checkpoint.

## Overlapped schedule measurement

The separate [overlapped schedule variant](variants/overlap-r2/README.md)
measured 3.09743 cached tokens/s at the same 12.5 MHz with the same model,
precision, authentication and 20 ms hold. Its own two 128-output trials,
image identity and timing limits remain separate from the original-image
measurements on this page. It retains 143 setup/recovery-side and 34
hold/removal-side failures; it does not close whole-image timing.

## Paired common speed benchmark

Two fresh one-BOS, 128-output greedy trials on this 12.5 MHz instrumented
image matched all 256 IDs against both recorded references. The pooled
cached rate is **1.612038176875 tokens/s** (table: **1.6**), from 254 intervals
over 157.564506625 seconds. First-STEP latencies are 577.896750 and
577.987208 ms. The rate includes the 250,000-cycle / 20 ms diagnostic hold.
[Capture](../../benchmarks/fpga-speed/tlm26-common-v1/CAPTURE.json) ·
[Raw frames and timing review](../../benchmarks/fpga-speed/tlm26-common-v1/REVIEW.json) ·
[Restoration](../../benchmarks/fpga-speed/tlm26-common-v1/RESTORATION.json)

## Earlier functional validation

- Two five-token prompts produced twelve greedy tokens each. All 24 generated IDs matched both CPU references.
- A boot stream with a single changed bit in an external DDR expert weight reached the affected STEP and returned the canonical refusal frame. The same image with healthy weights returned the expected token.
- Adjacent STEP and CLEAR frames exercised an outstanding first DDR return. CLEAR completed after drainage, the host observed 80 ms without stale replies, and a fresh BOS produced token 403.
- The original SRAM configuration passed its 108, 32 token check after restoration. The campaign performed no flash programming.

Median UART STEP round trip was 577.636 ms over the 24 generated tokens. Each token job includes a fixed 20 ms hold of its first actual DDR return. This is a two-prompt latency measurement, separate from the repository's one-input-token, 128-output paired speed benchmark. The board interface returns tokens. Its internal expert routing is not directly observed.

The [integer reference](evidence/integer-cpu.json) and [checkpoint reference](evidence/checkpoint-cpu.json) agree on both histories and all 120 ordered top-two expert selections for the generated tokens. The [serial-boot simulations](evidence/boot3-simulation.json) cover honest memory and the changed expert weight. Their transcripts and all 28 native build inputs were reproduced in the [clean replay](evidence/clean-replay.json). Use [REPRODUCE.md](REPRODUCE.md) for fresh output paths.

The [expert-dispatch replay](evidence/expert-dispatch/README.md) matched **340 ordered W1 launches and 340 first W1 acceptance events**, with all 40 layer-specific experts exercised. The complete trace preserves both CLEAR boundaries and all 36 UART replies. Coverage includes each selected expert's first W1 handshake and address in these two simulated histories. The physical record supplies the matching 24 external output tokens.

## Timing qualification

The [native route](evidence/route-volatile3.json) reports a 12.5 MHz token clock and same-domain Fmax of 43.789 MHz. Full-image analysis reports 127 setup and 34 hold violating endpoints; the bounded negative setup, hold and recovery path tables lie inside the inherited DDR IP. The board trials are finite functional observations with these timing limits. They do not establish full-image timing closure or a whole-chip theorem. See [formal scope](FORMAL-STATUS.md).
