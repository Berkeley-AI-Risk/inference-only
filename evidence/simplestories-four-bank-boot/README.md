# From flash samples to the SimpleStories boot loader

These ACL2 books check how the protected four-bank Tang Mega design receives model data at boot. Two theorems describe the same four-entry, 256-bit FIFO in the board project at [b12eadc](https://github.com/Berkeley-AI-Risk/inference-only/tree/b12eadcffd05a6052d648ec23869bc369c4cd16a/demos/simplestories-v2-5m/variants/kv-protected/hardware/project).

1. **Which bits reach a FIFO word?** At each actual store, the word contains the 32 accepted reader bytes in order. Each byte consists of eight selected DQ1 pin samples, most significant bit first. The first byte occupies bits 7–0. A repeated bit pattern still counts as a new store. [Flash-to-storage theorem](pin-reset-history.lisp)
2. **Which words reach the loader?** For every finite digital history after common reset, the sequence of words the application-side loader accepts is a prefix of the sequence written to the FIFO. This accounts for equal words, pointer wrap, backpressure, and the loader’s one-word holding register. If a clock stops or the loader stalls permanently, some words may remain undelivered. [Storage-to-loader theorem](order-reset.lisp)

The two statements meet at the actual FIFO storage write. The first follows the flash reader’s sampled input to that write. The second follows the FIFO’s write data and strobe through its dual-clock storage, read prefetch and application handshake. It checks the write transition against the write-side source equations. [Write-side correspondence](order-source-model.lisp)

## Assumptions and scope

The flash contents can be arbitrary. The flash theorem samples binary signals at trusted clock edges. Interpreting a DQ1 sample as the external chip’s value requires stable data at sampling. The loader theorem starts with both domain resets asserted and released together when neither clock rises. Thereafter the clocks can rise separately or together. A later common reset begins another epoch. Physical metastability, unilateral resets across epochs, off-chip DDR persistence, model authentication and eventual boot completion have separate obligations. These proofs describe RTL in the released board project. They add no new physical board measurement.

## Reproduce

Run from the public repository root. Python 3 and Icarus Verilog with SystemVerilog support suffice for the pin and order simulations. The driver checks the released RTL byte identities and its membership in both production source lists.

```sh
python3 -IB evidence/simplestories-four-bank-boot/replay.py
```

The tests exercise two clock schedules, full and stalled queues, repeated data, pointer wrap and reset with queued words. Changing one sampled bit in the test observer must trigger a pin mismatch. Changing the expected delivery order must trigger a loader mismatch at word six.

For the proofs use ACL2 8.7 and certified Community Books with the [corrected SystemVerilog translator](../simplestories-kv-record/translator/README.md). Set `ACL2` to the saved executable and `ACL2_SYSTEM_BOOKS` to that books directory. Use paths without spaces and a new scratch directory. The driver copies the original proof books there, checks the translator, and certifies both top books. The two fresh ACL2 sessions then print the theorem statements and run nine flash and eight loader assertions.

```sh
ACL2_CUSTOMIZATION=NONE python3 -IB evidence/simplestories-four-bank-boot/replay.py \
  --certify /tmp/simplestories-boot-proof
```
