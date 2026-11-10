# Qwen3 8B protected K/V component simulation

This opt-in simulation checks a protected K/V writer, committed roots, a
same-clock AXI transport and an attention consumer using deterministic test
values. It is separate from the released Qwen3-8B F2 image, which has plain K/V.
It does not produce an FPGA image or execute the complete model.

The original local component passed honest publication/readback at one position
through all 36 layer identities, separate layer-35 K and V corruption cases,
plain consumption controls, and nine typed transport refusals. The source bytes
here are the exact compiled inputs of that accepted component, stored once for
both build modes. `PROVENANCE.json` identifies their original source and review
hashes. The independent Python checker reconstructs all 36 roots with hashlib
and checks actual consumed BF16 operands rather than trusting a terminal PASS.

## Replay

Use Python 3.12, Verilator with C++17 support, a C++ compiler and make. Choose
package and build paths without whitespace. No AWS
SDK, FPGA, model download or third-party RTL installation is needed. Run each
case explicitly into a fresh output outside this directory. Build commands
use one compiler worker and one simulation thread. Each compilation has a
900-second limit and each simulation a 240-second limit; no retry is automatic.
Compiler caching is disabled so a read-only source/image does not require a
writable home-directory cache.
The runner is not an operating-system memory cap. Use an appropriately bounded
local environment and coordinate other large jobs; the test uses sparse
component fixtures rather than an 8.8 GB model image.

```sh
python3.12 -B run.py --case plain --output /absolute/fresh-results/plain
python3.12 -B run.py --case protected --output /absolute/fresh-results/protected
python3.12 -B run.py --case bounds --output /absolute/fresh-results/bounds
python3.12 -B check.py \
  --plain /absolute/fresh-results/plain \
  --protected /absolute/fresh-results/protected \
  --bounds /absolute/fresh-results/bounds \
  --output /absolute/fresh-results/VERIFIED.json
```

The source directory may be read-only and relocated. Build products, binary,
raw stdout/stderr, actual child exits and timing receipts remain in the result
directories. Keep failures or interruptions; a missing `FINISHED.json` or a
timeout is not a pass. `check.py` only reads completed results and writes its
new review; it never invokes a compiler or simulator.

## Acceptance and traffic

The honest protected case checks 36 ordered commits and 9,216 consumed BF16
values through the first attention GQA pair at each layer. It does not cover
all attention heads or a generated token. A key corruption prevents affected
K and V use; a value corruption permits the preceding honest K but blocks the
affected V. The plain builds must actually consume the changed operand.
The transport case checks the final legal digest beat and nine typed refusals,
including the first out-of-range address. Layer identities include 31, 32 and35.

For this first-position workload, protected writes are 2,377,728 bytes versus
147,456 plain bytes: 16.125×. This is initial whole-page publication traffic,
not whole-model overhead, a sustained decode rate or a physical HBM benchmark.

Remaining gates include positions 15/16 and partial-page updates, longer
contexts, complete-model numerical integration, CDC/reset and vendor HBM
behavior, physical fit/timing and an approved board test. Separate later local
experiments do not silently expand this package's acceptance.

## Licenses

See [NOTICES.md](NOTICES.md). Project code is Apache-2.0; included HardFloat and
AWS sources retain their original terms. Unused platform source preserved for
provenance is not a vendor shell or a supported hardware-build entry point.
No credentials, model image, shell checkpoint or simulator binary is supplied.
