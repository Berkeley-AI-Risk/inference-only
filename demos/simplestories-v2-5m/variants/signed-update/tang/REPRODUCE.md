# Reproduce the Tang S-AWIC integration

Run these commands from this directory. `DEMO` is the absolute path to the enclosing `demos/simplestories-v2-5m` directory. The public native image and the demo's integer reference are required. Use Python 3.10+, Verilator with timing support and a C++ compiler; the case runner uses macOS `caffeinate`. `make_fixtures.py` and `make_weight_fixture.py` additionally require NumPy. The staging, signature checks and fixture-identity checker use the standard library. Compilers use one build job. Independent cases can run concurrently with one simulation thread per case.

Set `WORK` to a new directory outside the checkout. Stage only the offline source/reference hierarchy and the two published RFC/LMS vector inputs; all campaign output is generated there. The enclosing `DEMO` assets and oracle are read in place. The source checkout and its archived evidence stay unchanged. The commands use `-B` so oracle imports do not add bytecode caches to `DEMO`.

```sh
TANG="$PWD"
python3 -B "$TANG/tests/prepare_replay.py" --output "$WORK"
REPLAY="$WORK/tang"
```

An existing `WORK` is refused, including an empty directory. Keep each completed or partial replay and choose another fresh path for a new campaign. The copy inventory is `$WORK/STAGED-INPUTS.json`.

## Independent numerical fixtures

```sh
python3 -B "$REPLAY/tests/reference_cases.py" "$DEMO"
python3 -B "$REPLAY/tests/make_fixtures.py" "$DEMO" --output "$REPLAY/evidence/fixtures"
python3 -B "$REPLAY/tests/make_weight_fixture.py" "$DEMO"
python3 -B "$REPLAY/tests/check_fixture_identity.py"
```

Use a Python environment with NumPy for `make_fixtures.py` and `make_weight_fixture.py`. They reconstruct the model's integer tensors and lookup tables directly from the physical image, then invoke the existing independent IntegerLlama oracle. They sign the base, synthetic changed-norm and synthetic zero-matrix models with public demo authorities, write their flash-slot stimuli and record expected output tokens. They refuse to overwrite existing fixtures. Compare the regenerated `fixtures.json` and the payload hashes in `INPUTS.json` with the [recorded fixtures](evidence/fixtures/fixtures.json) and [identity receipt](evidence/fixtures/INPUTS.json); the identity checker's own source hash is an execution binding, not a model-input digest.

## RTL campaigns

```sh
python3 -B "$REPLAY/tests/run_crypto_kats.py"
python3 -B "$REPLAY/tests/run_admission_memory.py" "$DEMO"
python3 -B "$REPLAY/tests/run_norm_store.py"
python3 -B "$REPLAY/tests/build_tang_sim.py" --fast
python3 -B "$REPLAY/tests/run_tang_sim.py" --fast --case 0
python3 -B "$REPLAY/tests/run_tang_sim.py" --fast --case 1
python3 -B "$REPLAY/tests/run_tang_sim.py" --fast --case 2
python3 -B "$REPLAY/tests/run_tang_sim.py" --fast --case 3
python3 -B "$REPLAY/tests/run_boot_faults.py"
python3 -B "$REPLAY/tests/run_host_tools.py"
python3 -B "$REPLAY/tests/build_tang_sim.py"
python3 -B "$REPLAY/tests/run_tang_sim.py" --case 0
python3 -B "$REPLAY/tests/run_tang_sim.py" --case 1
python3 -B "$REPLAY/tests/run_tang_sim.py" --case 2
python3 -B "$REPLAY/tests/audit_build_inputs.py"
```

The admission-memory command exercises the staged Tang memory, including per-page boot checking. Its new receipt binds the staged source hashes. The distributed `evidence/rtl-memory/result.json` records an earlier selection of the component sources; it is not evidence for the selected repaired RTL.

The fast campaign supplies the identical tagged flash bytes directly at core speed. Admission, signatures, hashes, DDR writes/readback, normalization, page authentication, token arithmetic and UART remain real RTL. It is useful for functional debugging; it does not exercise the SPI source or its asynchronous FIFO.

The full campaign drives the real SPI pins and retains that FIFO and the native clock ratios. Each accepted case clocks every bit of the complete 7.27 MB model and can take tens of minutes on one simulation thread. There is no five-minute wall-clock cutoff. Bounds in the harness count simulated cycles and check completion/progress. All campaigns use the explicit vendor-PHY abstraction described in [HARDWARE.md](HARDWARE.md).

Large image/hex stimuli, generated packages and compilation directories are omitted from the compact evidence. The external replay tree supplies fresh paths for scripts with fixed relative output directories; do not move or delete the distributed evidence to make room. The LMS runner uses the captured public [lms-vectors.json](tests/lms-vectors.json) input. The original component campaign and its four-state checks remain in the parent directory.

## Native Tang build

The selected macOS Standard compiler is pinned by `tools/build_native.py`: `gw_sh` SHA-256 `76b24d18ec9785be73de6e9e98866bbd7bec330aff67d1fa8462f71f79b5f72c`. Supply an existing authorized installation. The compiler may contact its configured license server; the script does not accept licenses or download software.

```sh
python3.12 -B tools/build_native.py --ide "$GOWIN_IDE" --vendor-dir "$VENDOR_INPUTS" \
  --dependency-manifest "$DEMO/VENDOR-DEPENDENCIES.json" --output "$WORK/native"
```

Use a new output directory outside the demo. The builder checks the tool, every selected source/constraint/memory input and all four separately acquired vendor files. It copies the exact reproduction Tcl and writes new native receipts without replacing recorded evidence or accessing hardware. Source and bitstream identities are in [SOURCE-IDENTITY.json](SOURCE-IDENTITY.json). Fresh routing and timing require a new review; full vendor-DDR/physical signoff is separate.

## Offline flash data and board qualification

```sh
python3 -B reference/signed_update.py pack-demo IMAGE.bin METADATA192.memh OUTPUT.swic \
  --version 3 --signer-state demo-signer-state.json
python3 -B tools/prepare_flash.py --package OUTPUT.swic --output prepared-update
python3 -B tools/check_flash.py --plan prepared-update/FLASH-PLAN.json --readback FULL-16MIB.bin
```

The package CLI is demo-only; its signer-state file must persist to avoid one-time-leaf reuse. Preparation verifies signatures, fixed-function tables, matching projection metadata and legal norm data. The resulting two files are flash data at the addresses in [HARDWARE.md](HARDWARE.md), not FPGA configuration files.

The enclosing demo's [PROGRAMMING.md](../../../PROGRAMMING.md) supplies the pinned programmer, target identity checks, independent complete backups, read-only maintenance reader and recovery procedure. Before an erase, preserve two independently initiated matching complete 16 MiB backups and an additional durable recovery copy. Do not publish backups or private receipts. Programming this variant also requires the signed slot at `0xf00000` and an independent complete-array readback of both regions. A programmer verify result alone does not establish the final array contents. No programming or erase is performed by the scripts above.

To preserve every other captured flash byte, prepare a complete raw candidate from one of the matching backups:

```sh
python3 -B tools/prepare_preserving_flash.py --plan prepared-update/FLASH-PLAN.json \
  --backup "$RECOVERY/read1.bin" --output "$RECOVERY/swic-candidate.bin"
python3 -B tools/check_flash.py --plan prepared-update/FLASH-PLAN.json \
  --baseline "$RECOVERY/read1.bin" --readback "$RECOVERY/post-install-readback.bin"
```

The first command only constructs and validates data. The complete candidate is the expected final array. Program only changed, complete 64 KiB blocks, preserving captured bytes within each block:

```sh
python3 -B tools/prepare_flash_blocks.py --before "$RECOVERY/latest-readback.bin" \
  --candidate "$RECOVERY/swic-candidate.bin" --output "$RECOVERY/blocks"
```

The offline planner rejects changes outside the model and admission regions, records each block's offset and hash, and checks that replaying the blocks reconstructs the entire candidate. For each write in its `BLOCK-PLAN.json`, use the qualified openFPGALoader 1.1.1 binary with the exact board, FTDI serial/channel and file:

```sh
"$OPENLOADER" -b tangmega138k --ftdi-serial "$SERIAL" --ftdi-channel 0 \
  --freq 900000 -v -f --verify --offset "$BLOCK_ADDRESS" "$BLOCK_FILE"
```

Use ordinary unprotected flash status. Do not add unprotect, bulk-erase, quad-mode or security options. After every installation, independently read the complete 16 MiB array and require equality with the complete candidate. Qualify this read transport against both independent maintenance-reader backups before its first use:

```sh
python3 -B tools/read_flash_jtag.py --openloader "$OPENLOADER" \
  --tool-sha256 "$OPENLOADER_SHA256" --serial "$SERIAL" \
  --output "$RECOVERY/post-install-readback.bin" \
  --expected-array "$RECOVERY/swic-candidate.bin"
```

This read resets volatile FPGA configuration. Reload the S-AWIC bitstream into SRAM afterward. The helper checks full size, FPGA/flash IDs, tool output and complete byte equality; exit status alone is insufficient. The pinned tool's [Gowin implementation](https://github.com/trabucayre/openFPGALoader/blob/v1.1.1/src/gowin.cpp) and [SPI implementation](https://github.com/trabucayre/openFPGALoader/blob/v1.1.1/src/spiFlash.cpp) define the read and programming paths. Keep raw captures and recovery receipts private.

The derived candidate is an S-AWIC installation, not an assertion that the original array has been restored. Preserve the original backups. Do not send a complete raw array to GOWIN operation 56 or send flash data to the SRAM bitstream loader.

The [prebuilt image](prebuilt/README.md) has the source and finite board-test association recorded in the validation document. Check its hash and the target identity first. Load it only into SRAM, with the pinned programmer and cable/location selected using the enclosing programming guide:

```sh
"$PROGRAMMER" --device GW5AST-138C --cable-index "$CABLE_INDEX" \
  --location "$LOCATION" --frequency 0.9MHz --operation_index 2 \
  --fsFile prebuilt/swic_product.fs
```

The physical campaign waits 45 seconds after programming for autonomous boot before sending UART commands. This is test setup, not an enforced update delay. After boot completes:

```sh
python3 -B tools/uart_check.py --device "$UART" --prompt 1 --expected 108,32 \
  --output board-base-result.json
```

The expected IDs above apply only to the matching base fixture. The synthetic zero-final-norm fixture expects `0,0`. Use the matching oracle for other compatible models. The UART tool exclusively opens the selected character device, checks CRC/status/payloads, sends only CLEAR/APPEND/STEP, and preserves partial evidence without automatic retries.

For the documented deliberately corrupted-signature fixture, use `tests/check_board_rejection.py --device "$UART" --output board-bad-signature.json`. It requires an explicit CLEAR acknowledgement and explicit APPEND/STEP rejection; a timeout is not a pass. Preserve that fixture separately from valid signed packages.

## Common speed benchmark

Use the signed base image and the same S-AWIC bitstream. Finish any other board experiment first. The collector opens the UART exclusively and sends only CLEAR, APPEND and STEP; it does not program flash or load a configuration. `WORK` must be a fresh evidence directory. NumPy is needed for the numerical reference, while collection and offline checks use the standard library.

```sh
python3 -B tools/common_speed_reference.py --demo "$DEMO" \
  --image "$DEMO/assets/board1-real-semantic-image2048.bin" \
  --output "$WORK/reference.json"
python3 -B tools/collect_common_speed.py --device "$UART" \
  --reference "$WORK/reference.json" --bitstream prebuilt/swic_product.fs \
  --load-record "$SRAM_LOAD_RECORD" --flash-readback "$FLASH_READBACK" \
  --flash-record "$FLASH_READBACK_RECORD" --board-result evidence/repair-board-2026-11-05/BOARD-RESULT.json \
  --output "$WORK/capture"
cp "$WORK/reference.json" "$WORK/capture/reference.json"
cp evidence/repair-board-2026-11-05/BOARD-RESULT.json "$WORK/capture/BOARD-RESULT.json"
python3 -B tools/check_common_speed.py --capture "$WORK/capture"
```

The load record is the successful SRAM programmer receipt: `command` (including `--operation_index 2` and `--fsFile`), `exit_code`, `started_utc` and `completed_utc`. The readback record is the JSON receipt from `read_flash_jtag.py`. Its complete-array capture must precede that SRAM load. The collector checks the corresponding configuration file, full-array hash, signed model package and independent reference. These host records do not independently attest physical configuration.

Each repetition uses `[378]` and 128 greedy outputs, continuing through end markers. Returned tokens are validated before sampling the monotonic caller clock. The primary rate is 254 divided by the sum of the two first-to-last validated-return intervals; it includes host-loop gaps. Per-STEP durations and first-STEP latency are retained separately. Raw observations are buffered in memory during each measured run, then saved. Failures remain in their own record; there is no automatic retry.

## Selected repair evidence

From the repository root, `python3.12 -I -S -B tools/check_repaired_sawic.py --output /tmp/sawic-recorded-check` checks both selected source/artifact identities, timing records, physical frames/grants and the recorded component proofs. Use a new output directory; no hardware, compiler or solver is launched. The stream packet offers a separate fresh compile/replay mode.

For board access, discover the current cable location with `programmer_cli --scan-cables F`. A cached location can become stale after USB changes. Require the actual `ID Code is: 0x0001081B` line, `Finished` and no error text; the command header and a zero exit code alone are insufficient.
