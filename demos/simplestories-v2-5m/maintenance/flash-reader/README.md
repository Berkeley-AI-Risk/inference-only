# Auxiliary read-only flash backup tool

This is a **separate maintenance configuration**, not part of the inference
image and not an additional command exposed by the frozen inference-only
machine. It temporarily replaces the FPGA's SRAM configuration so a developer
can preserve and verify flash during bring-up. It must never be described
as a feature of the final three-operation interface.

The fixed top targets GW5AST-138C/PG484A and has no selectable parameters.
One idle UART byte `R` requests a complete 16-MiB read from address zero.
Only SPI opcodes `9F` (identify) and `03` (read) are implemented. A flash ID
other than `0B4018` produces a rejected header without issuing the data read.
There are no host-specified addresses, lengths, writes, erase or mode commands.
No DDR, PLL, model engine or vendor IP payload is used by this helper.

## Offline checks

Using Python 3.12 and Verilator 5.050, from this directory:

```sh
python3.12 -I -S -B replay.py --work /absolute/space-free/path/to/fresh-reader-check
```

This runs ten synthetic receiver tests (including a complete 16-MiB packet
and pseudo-terminal transport) and three RTL simulations. Two simulations
use the production 115,200-baud UART divider and 1-MHz SPI setting, shortening
only the payload to 1 or 257 bytes. The real top's startup/reset pins are
also exercised. Flash-opcode/address checks, an independent UART decoder and
independent CRC computation reject incorrect behavior. These tests are not
an end-to-end 16-MiB RTL proof or electrical qualification.

All logs and build products go in the fresh work directory. No physical UART,
JTAG or vendor tool is opened by this command. The staged source files must
remain unchanged.

## Build and load boundary

`build.tcl` and `readonly_flash_reader.gprj` contain the exact source build
recipe. With the separately acquired GOWIN Education V1.9.11.03 macOS tool:

```sh
python3.12 -I -S -B build.py \
  --gowin-ide /absolute/path/to/Gowin_EDA/IDE \
  --output /absolute/space-free/path/to/fresh-reader-build \
  --confirm-permitted-vendor-use --preflight-only
```

Preflight checks the source inventory and pinned compiler without writing or
running it. Remove `--preflight-only` to build an isolated copy. The wrapper
records the tool exit, checks unchanged source copies, checks the setup/hold
report, and requires the resulting image to match the historical reader
byte-for-byte except for its single creation-time comment. Other differences
fail the check; hashes are not silently updated. Build success is not board
attestation, external I/O timing signoff or permission to load an image.
No programmer, UART, network download or inference app is invoked. Retain
local rebuild products privately. The selected prebuilt reader is supplied
at `prebuilt/flash-reader/readonly_flash_reader.fs` in the repository root.
For the normal backup workflow no compiler is needed; see
[PROGRAMMING.md](../../PROGRAMMING.md).

The historical source build was used to obtain two matching physical factory
reads and, later, a complete model-layout readback. Those historical results
do not attest a newly built image or another board. Source identities and the
historical image hash are in `MANIFEST.json`. The prebuilt reader is the
native rebuild with identical bytes apart from its creation-time comment.
See [VALIDATION.md](../../VALIDATION.md) for its physical rehearsal status.

Load a separately reviewed build into SRAM only, with explicit target and
ownership checks. This stops the inference circuit. A power cycle restores
the factory demo **only if its flash configuration has actually been kept**;
the model-only flash layout does not retain it.

## Read after an approved SRAM load

Only with this reader—not the inference circuit—already loaded, and the
actual board UART identified and exclusively available:

```sh
python3.12 -I -S -B host/read_factory_flash.py \
  --device /dev/cu.usbserial-YOUR_READER \
  --output /absolute/recovery-directory/new-read1.bin
```

This command accesses hardware and creates private local evidence. It sends
exactly one `R`, validates the `TFD1` header, fixed ID/length and CRC32, and
records a SHA-256 digest. It never overwrites an existing output, partial file
or receipt. An error preserves the partial evidence and is not automatically
retried. Receipt paths and USB device identifiers are private; do not publish
them or the factory flash contents.

A read takes approximately 24–27 minutes at this deliberately slow baud rate.
Keep receiving: stopping the host does not cancel the FPGA's in-flight read.
Wait for terminal completion before a separately initiated second read.
Compare the two files with the package's `tools/check_flash_layout.py backups`.
Then perform the separately reviewed SRAM load needed for the inference demo.
No erase, factory restoration or inference-image load is performed by this
receiver.
