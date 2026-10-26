# Seeded SimpleStories generation on Tang Mega

The **seeded-sampling** image generates varied continuations from the
same fixed SimpleStories-V2-5M model. Choose temperature **0, 0.5, 1 or 2** and
a public 128-bit seed. Repeating a prompt with the same settings reproduces
the tokens; temperature 0 keeps the exact greedy rule.

Use the local browser app to enter text and choose generation settings.
The seeded-sampling image uses the fixed model and authenticated weights;
it has no K/V cryptographic integrity or memory encryption. The baseline,
K/V-protected and encrypted-memory versions remain separate available images.
Current package status is **Runnable release**. See the
[qualification record](CURRENT-QUALIFICATION.md) for current validation and
[timing details](CURRENT-QUALIFICATION.md#recorded-timing), then follow the
installation and generation instructions below.

## Load and check the seeded image

Use the same supported Tang Mega 138K non-Pro/device-C board and 16-MiB flash
as the [standard installation](PROGRAMMING.md). For a first installation,
complete that guide's identity, backup, plaintext-model installation and full
readback checks. Its model-installation step erases flash. If the plaintext
model is already installed and verified, switching from the baseline to this
image requires only an SRAM load; it does not require a flash write.
An encrypted-memory installation has different flash contents; follow
[its restoration guide](ENCRYPTED-MEMORY.md#install-or-restore) before using a
plaintext image.

From the SimpleStories demo directory (`demos/simplestories-v2-5m/`), verify the package:

```sh
python3.12 -I -S -B ../../tools/verify_release.py
```

Stop the browser app and every other serial/JTAG user. Retain the exact
known-good SRAM image you intend to reload when returning to your previous
version. Use the current cable index and USB location from the programming
guide's fresh scan. For its tested cable index 4:

```sh
"$FPGA_PROGRAMMER" --device GW5AST-138C --cable-index 4 --location "$FPGA_USB_LOCATION" --frequency 0.9MHz --operation_index 2 --fsFile "$FPGA_PACKAGE/prebuilt/seeded-sampling/project/impl/pnr/shared_product.fs"
```

Require the intended target, successful **SRAM Program**, successful tool exit
and `Finished.`. Keep the board powered and wait at least 120 seconds after actual
SRAM load completes. The FPGA configuration is volatile; reload it after power loss.
Its SHA-256 is
`d271626a7fb9ce1debdf7a9cd847125ec7eb4c907fa9d06af9d5f8146cecc725`;
[BUILD.json](prebuilt/seeded-sampling/BUILD.json) binds it to the selected
sources. Its scope field records the qualification status at native-build
time; later board, browser and proof results are recorded separately in
[VALIDATION.md](VALIDATION.md) and the
[qualification record](variants/seeded-sampling/QUALIFICATION.md). These
identities do not independently attest a connected FPGA.

Install the host app dependencies as described in
[host-app/README.md](host-app/README.md), then register the loaded seeded image
from the `host-app` directory:

```sh
.venv/bin/python -B qualify_board.py \
  --build-receipt ../prebuilt/seeded-sampling/BUILD.json \
  --device /dev/cu.usbserial-YOUR_BOARD \
  --confirm-loaded-source-build --acknowledge-unqualified-timing
```

Use your actual serial device. Add `--replace-profile` when a profile already
exists. The extended check requires 19 exact tokens across greedy generation,
all three positive temperatures, CLEAR replay and changed-seed fixtures,
with 45 command results. It finishes with greedy settings and CLEAR. A legacy
seven-command result cannot qualify the seeded profile. Success saves the
local profile and evidence; failure leaves generation disabled.
No reset, reflash or automatic retry follows a fault. The check discards any
current conversation and acknowledges exploratory timing, not timing signoff.

Start the app from that same directory:

```sh
.venv/bin/python -B start_local_server.py
```

Open **http://127.0.0.1:8507**. The page shows sampling controls only for a
qualified seeded profile. A successful wait or local file hash alone cannot
enable generation or establish a successful boot.

To switch back to another hardware version, stop the app, reload that version's
known-good SRAM image and rerun its matching qualification. The browser does
not switch hardware images or change flash. Choosing temperature 0 in the
seeded app itself needs no reprogramming.

## Choose settings and generate

Enter a story prompt in the browser and choose a temperature. **0** is the
default and reproduces the original greedy rule. The positive choices are
**0.5, 1 and 2**. Leave the seed automatic for a fresh continuation or supply
a 128-bit seed to reproduce an earlier run. The last-run display and
downloadable run record show the actual temperature and seed used.

Each Generate clears the tape, applies the chosen settings, uploads the
tokenized prompt and streams the continuation. Completion and Stop finish
with CLEAR. Repeating the same prompt, temperature and seed reproduces the
continuation. The tokenizer and conservative browser limits are unchanged:
at most 2,048 prompt tokens, 128 new tokens and 2,049 combined tokens for seeded sampling. The three greedy profiles have the same limits. These limits do not
constitute a full-context test of the seeded image.

CLEAR retains temperature and seed and restarts the generator from that seed.
Reset restores temperature 0. A different seed can produce a different
continuation, but need not change every token. The generator is deterministic
and noncryptographic; a seed is a public reproducibility setting, not a key
or a source of independent physical randomness.

## Optional token-ID diagnostics

The CLI is for direct wire tests and diagnostics. Stop or disconnect the
browser app before using the same serial device. From the SimpleStories demo directory (`demos/simplestories-v2-5m/`),
prepare a known-answer request without opening a device:

```sh
python3.12 -B variants/seeded-sampling/tools/generate.py --temperature 1 --seed 0x99aabbccddeeff001122334455667788 --tokens 378 --steps 3
```

Add `--execute` and your actual device to run it, optionally using a new
private log file:

```sh
python3.12 -B variants/seeded-sampling/tools/generate.py --temperature 1 --seed 0x99aabbccddeeff001122334455667788 --tokens 378 --steps 3 --execute --device "$FPGA_UART" --record "$FPGA_RECOVERY/seeded-check.jsonl"
```

The returned token IDs must be **357, 3898, 104**. A second invocation with the
same settings must reproduce them. The CLI prints JSON lines and accepts
token IDs rather than text. Temperature defaults to 0; a positive temperature
without `--seed` chooses and displays a fresh seed before opening the device.
It is a dry run until `--execute` is present and never programs the board.
Stop on rejection, timeout, malformed response or mismatch; uncertain commands
are not automatically retried.

For prompt token 378 and seed `0x99aabbccddeeff001122334455667788`, the
board-checked first three outputs are:

| Temperature | Token IDs |
| --- | --- |
| 0 | 200, 15, 103 |
| 0.5 | 247, 130, 32 |
| 1 | 357, 3898, 104 |
| 2 | 3436, 4007, 141 |

## Board evidence and limits

The seeded-sampling image measured **9.94 cached tokens/s at temperature 1**
with a one-token prompt and two 128-output trials. The rate divides the 254
cached outputs by the sum of their command/reply durations, excluding each
trial's first STEP, connection setup and prompt upload. It includes host/UART
and evidence-recording costs.

The matched benchmark runs two 128-output trials at each supported temperature
and compares every output with the integer reference. The fixed-work benchmark
continues through end-of-story tokens; ordinary browser generation stops at an
end-of-story token.

Qualification covers the four temperatures, chosen-seed replay, seed-boundary
cases, SETTINGS rejection and CLEAR/recovery. Context tests use 128-, 512-,
2,047- and 2,048-token prompts. Twelve ordinary Chrome cases checked 100 outputs,
including long-prompt generation, Stop and subsequent generation.

The [qualification record](CURRENT-QUALIFICATION.md) provides the image and
source identities, exact test coverage, timings and offline checking commands.
The [formal scope](FORMAL-STATUS.md) describes the separately checked RTL
properties and their boundaries. These finite model, board and browser results
do not establish correctness for every prompt, a numerical-distribution
theorem, complete timing signoff or physical-security certification.

## Fixed sampling and protocol contract

The model and authenticated logits are unchanged. Temperature 0 bypasses
sampling and PRNG state and retains the original greedy tie behavior.
For positive temperatures, the circuit buffers the logits, subtracts their
maximum, obtains fixed Q30 masses from its immutable exponential table, and
selects through an integer cumulative distribution. This is a finite-precision
distribution rather than exact floating-point softmax. All sampling arithmetic
and state are private; the host cannot supply logits or probability tables.

The generator is xoroshiro128++; seed zero maps to the nonzero initial state
`(1, 0)`. APPEND, prefill, idle cycles and stalls do not advance it. A draw
commits when its selected token is accepted; CLEAR discards uncommitted work
and rewinds to the configured seed. Faults remain terminal through CLEAR.

The seeded image accepts `SETTINGS` (opcode 03) alongside five-byte
APPEND/STEP/CLEAR frames. Its 20-byte request contains magic `A5`, opcode,
temperature code (0=greedy, 1=0.5, 2=1, 3=2), the 16-byte little-endian seed
and CRC8. Acceptance replies with kind `83` and the temperature code;
rejection uses `C3`; recognized malformed SETTINGS or bad CRC uses `CF`.
CRC is error detection.
Settings apply atomically only when the tape is empty and idle. They cannot
overtake an active STEP or modify in-flight inference. Send one complete
request and wait for its response; there is no exactly-once retransmission
guarantee. A partial SETTINGS frame times out after 40 UART bit-times without
another byte (about 347 microseconds at 115200 baud). It cannot partially
apply settings; after timeout and reply drain, a later valid legacy frame can
be parsed as a new request. Do not continue an abandoned frame or interleave
requests. The CLI implements this framing and stops on faults.

The source is in [variants/seeded-sampling/hardware](variants/seeded-sampling/hardware).
The pinned 91-input inventory is
[hardware-inputs-seeded-sampling.json](host-app/hardware-inputs-seeded-sampling.json);
four vendor files must be acquired separately under
[VENDOR-SETUP.md](VENDOR-SETUP.md). Its settings and sampler controller have their own scoped RTL results. Separate [seeded formal proofs and public replay](formal/seeded-sampling/README.md)
check SETTINGS, sampler/seed ownership and CLEAR/replay with the stated
private-service boundaries. The connected Z3 proof passes 196 assertions;
cvc5 passes its base and 194 conclusions, with two CRC conclusions unresolved.
The public replay verifies 87 distributed source files and image bytes; it does
not verify or prove the four omitted vendor files, whole-machine refinement,
numerical CDF equivalence or mapped/timing correctness.
