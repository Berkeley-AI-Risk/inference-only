# Real-model RTL and weight-integrity simulations

This bench runs the actual six-layer integer datapath, token shell, private
model-page service, boot/readback SHA, typed K/V cache and dual-clock DDR
transport. **All 64 production RTL files are read unchanged from `hardware/`.**
No pretrained-model computation is substituted for the RTL output.

The bench supplies a fixed flash-like data source and a behavioral DDR PHY.
It does not simulate physical SPI, the vendor DDR controller/PHY, analog
timing or the UART bit stream. Public operations are exercised at the token
handshake boundary; separate package tests cover the real UART path.
Clocks match the selected core/application/trusted rates. Simulation is
two-state; correct simulated output does not establish physical qualification.

## Run from the package root

First reconstruct the model image using `tools/materialize_image.py`, as
described in [REPRODUCE.md](../../REPRODUCE.md). Then:

```sh
python3.12 -I -S -B tools/check_model_rtl.py \
  --package . \
  --image /absolute/asset-directory/fpga-image/board1-real-semantic-image2048.bin \
  --work /absolute/space-free/path/to/fresh-model-rtl-run
```

Python needs only its standard library; Verilator 5.050 and a C++ toolchain
are required. Source and image hashes are checked before compilation. All
generated files go outside the package in the fresh work directory. The
default compiles with eight build workers and runs four cases concurrently;
`--jobs` and `--build-jobs` control those counts. A case timing out is a failed
test, not evidence of rejection or completion. No vendor tool, board, UART,
network download, server or flash-programming action is invoked.

## Default four cases

- **Normal inference with no imposed DDR stalls**, followed by CLEAR/replay.
- **The same computation with deterministic DDR stalls and backpressure.**
  Each case must return `[200, 15, 103, 157]` after APPEND 378, then return
  200 again after CLEAR and a fresh APPEND 378. Held output, memory ownership,
  K/V census, literal arithmetic/controller shadows and draining are checked.
- **One-bit corruption in boot data.** The real full-image SHA must reject it
  after writing and reading all 227,062 words; the interface must never open.
- **One-bit corruption in the first post-boot model-page return.** Boot must
  succeed first, then the actual page hash must fail before any token is
  exposed. Public commands and new memory work must remain disabled.

Each case redoes the entire boot/readback/SHA; there is no injected lock or
seeded hash state. Model data are reconstructed from the fixed binary into
an exactly checked `$readmemh` representation, not bundled as another model
checkpoint. Corruption cases are finite negative tests, not a proof against
all tampering, hash collisions or a physical attacker.

The bench and its shadow-reference modules are verification fixtures, not
alternative FPGA designs or user-accessible arithmetic units. They are not
listed in the FPGA project and are never synthesized into its bitstream.
Their comparisons observe real DUT signals and use no `force`/`release`.
The default runner retains every bench assertion and checks the recorded
markers exactly, including token IDs and cycle/traffic counts. Expected
outputs are not regenerated from a failing implementation.

The full offline package replay includes these four cases. This is a short
numerical/integrity check, not a new full-context or whole-machine proof.
