# Protected seeded SimpleStories on Tang Mega

This package runs SimpleStories-V2-5M with authenticated external K/V in DDR
and seeded temperature sampling. It includes the exact 25 MHz bitstream
`490a58526e6a9593a07e5744779ab6f55d25a8fd4c192df86b34be55c9aee23f`
from the two 128-output trials. [Benchmark and UART records](../../../../evidence/simplestories-tang-protected-seeded-board/README.md#128-output-benchmark) · [Image and model identities](RELEASE.json)

## Install and run

Use a **Tang Mega 138K Basic (non-Pro), GW5AST-138C / PG484A** with the
verified 16-MiB flash, Apple Silicon macOS, Python 3.12 and the separately
installed programmer. Follow the [programming guide](../../PROGRAMMING.md)
for identity and recovery checks. First-time model installation erases flash
and requires two verified backups. Reuse the verified plaintext model at
`0x801000` if it is already installed.

From the SimpleStories demo directory, check the release files:

```sh
python3.12 -I -S -B ../../tools/verify_release.py
```

Use the programmer and variables from the guide to load the exact
protected seeded image into **volatile SRAM**:

```sh
"$FPGA_PROGRAMMER" --device GW5AST-138C --cable-index 4 --location "$FPGA_USB_LOCATION" --frequency 0.9MHz --operation_index 2 --fsFile "$FPGA_PACKAGE/prebuilt/protected-seeded-sampling/project/impl/pnr/shared_product.fs"
```

Use the Debugger A cable index reported for your board. Require the
expected target, **SRAM Program**, a successful exit and `Finished.`.
Wait at least 120 seconds after the load completes. From the demo directory,
set up the existing host app and register the exact loaded image:

```sh
cd host-app
python3.12 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python -B fetch_tokenizer.py
.venv/bin/python -B qualify_board.py \
  --image-receipt ../prebuilt/protected-seeded-sampling/RELEASE.json \
  --device "$FPGA_UART" --confirm-loaded-image --acknowledge-unqualified-timing
.venv/bin/python -B start_local_server.py
```

Use `--replace-profile` if switching from another qualified image. A
successful check verifies 19 exact outputs, including a CLEAR replay, and
registers the **K/V integrity protection + seeded temperature sampling**
profile. Stop on a failed check and retain the serial log. Verify the exact
files and requalify after every SRAM reload.

Open [the local app](http://127.0.0.1:8507), enter `around`, choose **3**
new tokens and **temperature 1**, and set the seed to
`0x99aabbccddeeff001122334455667788`. The run record should show
token IDs **357, 3898, 104**. Disconnect USB in the app or stop the server
before reprogramming. [Host guide and recovery steps](../../host-app/README.md)

## Evidence and attribution

The reader registration passed on Tang hardware with the shipped image and
verified model. All 45 command/reply pairs and 19 expected outputs matched.
The prior signed SRAM image returned its two expected tokens and acknowledged
final CLEAR after restoration. [Reader smoke record](BOARD-SMOKE.json)

This release uses the existing MIT-attributed SimpleStories model and tokenizer.
The device-specific bitstream retains its original GOWIN notice and is
distributed with the project's Apache-2.0 contributions and the applicable
third-party notices. The vendor programmer and source IP are installed
separately. [Model attribution](../../README.md) · [License scope](../../../../LICENSE-SCOPE.md) · [Third-party notices](../../../../THIRD-PARTY-NOTICES.md)

The recorded inference setup and hold slack are +0.409 ns and +0.170 ns.
The vendor DDR report retains 145 setup/recovery and eight hold/removal
endpoints with negative slack. Board evidence covers the clean output,
SETTINGS and CLEAR exchanges for this exact image. A repeated token sequence
is a deployment check. [Timing and observation scope](../../../../evidence/simplestories-tang-protected-seeded-board/README.md#timing-and-observation-scope)
