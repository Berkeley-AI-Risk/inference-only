# Run the demo on a Tang Mega 138K

This guide installs the **plaintext** model for the baseline and
K/V-protected configurations. For the third image, follow the explicit
[encrypted-memory substitutions](ENCRYPTED-MEMORY.md#install-or-restore);
it requires different flash contents, not only a different SRAM image.

This is the **Apple Silicon macOS, prebuilt-image workflow**. No hardware
compiler is required. Use only a **Tang Mega 138K non-Pro with GW5AST-138C /
PG484A**, FPGA IDCODE `0001081B`, and the tested 16-MiB flash with JEDEC ID
`0B4018`. Do not use these files on a 60K, device B, or 138K Pro board.
See [Sipeed's board guide](https://wiki.sipeed.com/hardware/en/tang/tang-mega-138k/mega-138k.html).
The model starts above 8 MiB, so older 64-Mbit / 8-MiB flash cannot hold this
layout. Sipeed identifies the 128-Mbit version with its October 2025 update;
verify the actual hardware/flash ID rather than relying on a purchase date.
Other operating systems and programmer builds have not been qualified here.

**Installing the model erases the entire flash, including the factory demo.**
Preserve two complete backups before any erase. This experimental design also
retains unresolved vendor-DDR timing paths; proceeding is exploratory use,
not complete timing or electrical signoff. Stop on any mismatch or tool error.
Do not add retries, OTP, eFuse, key, debug, boot-address or flash-mode operations.

The model resides in nonvolatile flash. The inference circuit is loaded into
volatile FPGA SRAM and is lost on power-off. The demonstrated flash layout
contains no persistent FPGA boot configuration. Normal power-on use therefore
requires an SRAM reload, not another model install.

Plan about 1.5 hours for first-time backup, installation and verification:
the three complete serial reads in sections 2 and 4 take about 25 minutes each, in addition to
programming. This is setup time, not token-generation latency. Later sessions
with an unchanged model normally start at section 5.

## 1. Install and identify

Obtain the exact standalone Programmer and verify its hash/configuration as
described in [VENDOR-SETUP.md](VENDOR-SETUP.md). Also install the separately
downloaded **openFPGALoader 1.1.1** used for restoring a complete factory backup
in section 6; check its version before erasing anything. The GOWIN numeric
operations below are for **1.9.12.03 build 2712** only. Install Python 3.12 and
the host dependencies from [host-app/README.md](host-app/README.md).

Connect the board's USB debugging port with a data-capable cable and provide
the board's specified power. Stop the app and other serial/JTAG programs.
Keep the cable/power stable throughout programming and reads.
Set the flash capacity in both required `spi.ini` sections as specified in
[VENDOR-SETUP.md](VENDOR-SETUP.md) before continuing; the tested flash is
128 Mbit, not 64 Mbit.

From the release repository root, first check all supplied files:

```sh
python3.12 -I -S -B tools/verify_release.py
```

Set these shell variables to **your actual paths and device**, not another
owner's USB identifiers. Keep the recovery directory outside the repository.

```sh
FPGA_PROGRAMMER="/absolute/path/to/Programmer/bin/programmer_cli"
FPGA_OPENLOADER="/absolute/path/to/openFPGALoader"
FPGA_PACKAGE="/absolute/path/to/this/repository"
FPGA_RECOVERY="/absolute/path/to/durable-recovery-directory"
"$FPGA_PROGRAMMER" --scan-cables
"$FPGA_OPENLOADER" -V
"$FPGA_OPENLOADER" --scan-usb
```

The scan reports each cable and USB location. Select the connected board's
USB Debugger A cable, using cable index 4 in this tested tool profile:

If the scan identifies that cable under a different index, substitute that
reported index for every `--cable-index 4` below. Do not guess an index or
proceed if the cable type or target is unclear.

```sh
FPGA_USB_LOCATION="YOUR_SCAN_LOCATION"
FPGA_UART="/dev/cu.usbserial-YOUR_BOARD"
FPGA_FTDI_SERIAL="YOUR_BOARD_SERIAL_FROM_SCAN"
mkdir -p "$FPGA_RECOVERY"
"$FPGA_PROGRAMMER" --device GW5AST-138C --cable-index 4 --location "$FPGA_USB_LOCATION" --frequency 0.9MHz --operation_index 0
"$FPGA_PROGRAMMER" --device GW5AST-138C --cable-index 4 --location "$FPGA_USB_LOCATION" --frequency 0.9MHz --operation_index 51
```

Require the intended target, FPGA ID `0x0001081B`, flash ID `0x0B4018` and
terminal `Finished.` with successful tool exit. A generic all-ones response
is not a valid ID. If an ID differs, stop before writing anything. A different
flash ID does not by itself prove insufficient capacity, but that variant is
outside this rehearsed procedure and needs a separate compatibility check.
For the UART, macOS may expose two serial interfaces; the
tested connection used the second interface. Confirm it by a successful
reader header/ID/CRC below, not by assuming a serial suffix is universal.
For openFPGALoader, select that same board's FTDI serial from its USB scan,
not its transient USB bus/device number or the UART interface suffix. USB
locations can change after reconnection; rescan rather than retaining an old
location. The selected openFPGALoader board profile is `tangmega138k`, channel 0.
No flash write is allowed until those checks and the two full reads pass.

## 2. Preserve two full backups

Load the **separate read-only maintenance image** into SRAM:

```sh
"$FPGA_PROGRAMMER" --device GW5AST-138C --cable-index 4 --location "$FPGA_USB_LOCATION" --frequency 0.9MHz --operation_index 2 --fsFile "$FPGA_PACKAGE/prebuilt/flash-reader/readonly_flash_reader.fs"
python3.12 -I -S -B maintenance/flash-reader/host/read_factory_flash.py --device "$FPGA_UART" --output "$FPGA_RECOVERY/read1.bin"
"$FPGA_PROGRAMMER" --device GW5AST-138C --cable-index 4 --location "$FPGA_USB_LOCATION" --frequency 0.9MHz --operation_index 2 --fsFile "$FPGA_PACKAGE/prebuilt/flash-reader/readonly_flash_reader.fs"
python3.12 -I -S -B maintenance/flash-reader/host/read_factory_flash.py --device "$FPGA_UART" --output "$FPGA_RECOVERY/read2.bin"
python3.12 -I -S -B tools/check_flash_layout.py backups "$FPGA_RECOVERY/read1.bin" "$FPGA_RECOVERY/read2.bin"
```

Run each command only after the previous one finishes successfully. Each read
takes about **25 minutes**. The receiver sends only `R`, validates the full
16,777,216-byte packet, identity and CRC32, and records its SHA-256. It rejects
existing output files and retains partial evidence after failure. Stopping
the receiver does not cancel the FPGA's transmission: do not start another
operation on a failed/in-flight read without investigating.

Require two separately initiated reads with identical bytes and hashes.
Copy both `.bin` files and their `.jsonl` receipts to another durable storage
location. A copied file is an extra recovery copy, not a second physical read.
Do not publish your backups or receipts. Review the restoration procedure in
section 6 before accepting the next step.

The backup reader is **not part of the inference image and not a fourth
inference command**. It replaces the development FPGA's SRAM configuration.
See [its implementation and checks](maintenance/flash-reader/README.md).

## 3. Erase and install the fixed model

After the preceding identity, backup and file checks, explicitly accept loss
of the current flash configuration. These two commands select full erase,
then binary erase/program/verify at the fixed model address:

```sh
"$FPGA_PROGRAMMER" --device GW5AST-138C --cable-index 4 --location "$FPGA_USB_LOCATION" --frequency 0.9MHz --operation_index 52
"$FPGA_PROGRAMMER" --device GW5AST-138C --cable-index 4 --location "$FPGA_USB_LOCATION" --frequency 0.9MHz --operation_index 56 --mcuFile "$FPGA_PACKAGE/assets/board1-real-semantic-image2048.bin" --spiaddr 0x801000
```

Require the intended target, operation **exFlash Bulk Erase Arora V** for 52,
then **exFlash C Bin Erase,Program,Verify Arora V** for 56, successful exit
and terminal `Finished.` for each. This is raw binary input via `--mcuFile`,
**not** FPGA bitstream input via `--fsFile`. Never write the model at zero.
Numeric operations or file formats from another tool version are not substitutes.

The complete intended flash layout is:

| Byte interval, end excluded | Contents |
| --- | --- |
| `[0x000000, 0x801000)` | Erased (`FF`) |
| `[0x801000, 0xEEEEC0)` | Exact 7,265,984-byte model image |
| `[0xEEEEC0, 0x1000000)` | Erased (`FF`) |

The boot reader starts directly at `0x801000`; it does not consume an older
metadata header at `0x800000`. Its model/page digests are fixed in the circuit.
Do not concatenate a guessed header or FPGA configuration with the model.

## 4. Independently read back the complete array

Reload the reader and capture a new, complete physical read. The programmer's
own verification is not a substitute for this independent check:

```sh
"$FPGA_PROGRAMMER" --device GW5AST-138C --cable-index 4 --location "$FPGA_USB_LOCATION" --frequency 0.9MHz --operation_index 2 --fsFile "$FPGA_PACKAGE/prebuilt/flash-reader/readonly_flash_reader.fs"
python3.12 -I -S -B maintenance/flash-reader/host/read_factory_flash.py --device "$FPGA_UART" --output "$FPGA_RECOVERY/model-readback.bin"
python3.12 -I -S -B tools/check_flash_layout.py layout --model assets/board1-real-semantic-image2048.bin --readback "$FPGA_RECOVERY/model-readback.bin"
```

This compares **every byte**, including both erased regions. The model SHA-256
must be `cad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0`;
the full-array SHA-256 must be
`b6be312296b01d4eb2f985cd71f90d110a2a632c42ca0b4698dc8c9832765a25`.
These are saved-byte/transport checks, not remote attestation of silicon.

## 5. Load inference and start the app

After the readback passes, load only the selected inference image into SRAM:

```sh
"$FPGA_PROGRAMMER" --device GW5AST-138C --cable-index 4 --location "$FPGA_USB_LOCATION" --frequency 0.9MHz --operation_index 2 --fsFile "$FPGA_PACKAGE/prebuilt/inference/project/impl/pnr/shared_product.fs"
```

The command above loads the **baseline without K/V integrity checks**. To
load the **K/V-protected prototype**, use the same SRAM operation
with `--fsFile "$FPGA_PACKAGE/prebuilt/kv-protected/project/impl/pnr/shared_product.fs"`.
Load only one configuration, then use its matching build receipt for the
known-answer check below. Both remain timing-unqualified exploratory images;
see [the comparison and limitations](KV-PROTECTION.md).

Require the expected target, successful **SRAM Program** and `Finished.`.
Do not run another flash bridge/JTAG operation afterward: it may replace the
loaded circuit. Keep the board powered and allow **at least 60 seconds** for
startup. Waiting alone does not establish a successful boot.

Follow [the host guide](host-app/README.md) to run the seven-command known-answer
test with `prebuilt/inference/BUILD.json` for the baseline or
`prebuilt/kv-protected/BUILD.json` for the protected image, then start the browser app. The
test deliberately clears any current conversation. Requalify after every
power cycle, SRAM reload, board replacement or unexplained fault.
Subsequent power-on sessions repeat this section and qualification; they do
not require erasing/reinstalling the unchanged model.

## 6. Restore the saved factory flash instead

This optional path **replaces the model with your own backup**. Stop the app,
check target identity again, and rerun the two-backup equality check from
section 2. Use only your verified complete 16-MiB raw dump, never a `.fs`
file, partial read, model image or somebody else's factory dump. This uses
**openFPGALoader 1.1.1**, not GOWIN operation 56: that GOWIN operation failed
when given the saved factory array at address zero in our rehearsal.

Recheck the selected board before the destructive command:

```sh
"$FPGA_OPENLOADER" -b tangmega138k --ftdi-serial "$FPGA_FTDI_SERIAL" --ftdi-channel 0 --freq 900000 -v --detect
```

Require FPGA ID `0x0001081B` (the tool may omit leading zeroes), and the intended
FTDI serial/channel. The following command erases/programs the entire array
and verifies it. Its input is **the complete raw 16-MiB dump at offset zero**;
do not trim it or prepend a bitstream/header. Do not enable unprotect, quad,
OTP or security options. If nonzero protection or a protection error is
reported, stop and investigate.

```sh
"$FPGA_OPENLOADER" -b tangmega138k --ftdi-serial "$FPGA_FTDI_SERIAL" --ftdi-channel 0 --freq 900000 -v -f --verify --offset 0 "$FPGA_RECOVERY/read1.bin"
"$FPGA_PROGRAMMER" --device GW5AST-138C --cable-index 4 --location "$FPGA_USB_LOCATION" --frequency 0.9MHz --operation_index 2 --fsFile "$FPGA_PACKAGE/prebuilt/flash-reader/readonly_flash_reader.fs"
python3.12 -I -S -B maintenance/flash-reader/host/read_factory_flash.py --device "$FPGA_UART" --output "$FPGA_RECOVERY/restored-readback.bin"
python3.12 -I -S -B tools/check_flash_layout.py backups "$FPGA_RECOVERY/read1.bin" "$FPGA_RECOVERY/restored-readback.bin"
```

As before, execute one command at a time and require success before continuing.
The openFPGALoader transcript must report the intended FPGA and flash identity,
complete erase/write and successful verification, not merely a successful
device scan. Its GW5AST backend adjusts the flash-access clock internally;
`--freq 900000` is the initial JTAG request, not a guarantee of that speed
throughout the flash operation.
For this flash, version 1.1.1 also reports that the chip is absent from its
database and uses basic protection detection. That message appeared in the
tested recovery path; it does not replace checking the exact ID or verifying
all restored bytes.
The final check must match all 16 MiB of the saved factory array. Power cycling
then permits the original flash boot configuration to run. A byte-exact flash
restoration is distinct from a separately observed factory-demo boot or a
claim that the programmer leaves every internal status register unchanged.
See [the release validation record](VALIDATION.md) for what was actually tested.

Recovery evidence stays outside the public repository. On any failure, retain
logs and power/state information, stop, and investigate; do not automatically
retry, erase again, or assume the factory configuration has been restored.
