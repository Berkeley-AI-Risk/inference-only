# Run the reset-guarded four-bank greedy image

This Tang Mega 138K F-AWIC uses the same plaintext model and UART token client
as the original protected release. The [release record](RELEASE.json) identifies
the exact bitstream, model, client and clock domains. The [board capture](../../../../evidence/simplestories-tang-reset-guard/README.md)
contains 18 dependent tokens across three functional trials. The separate
[speed benchmark](../../../../evidence/simplestories-tang-reset-guard/README.md#cached-generation)
matched all 256 outputs on the same image.

Follow the [programming guide](../../PROGRAMMING.md) for board identification,
the supported programmer, flash recovery and initial model installation. It
covers the non-Pro GW5AST-138C with the tested 16-MiB flash. A board with the
verified `cad8d015…` plaintext model at `0x801000` reuses that model. The
new inference circuit goes into volatile FPGA SRAM.

From the SimpleStories demo directory, verify the package. Use the guide's
programmer variables and the cable index reported for that board (4 in the
tested profile). In section 5, select the guarded image.

```sh
python3.12 -I -S -B ../../tools/verify_release.py
"$FPGA_PROGRAMMER" --device GW5AST-138C --cable-index 4 --location "$FPGA_USB_LOCATION" --frequency 0.9MHz --operation_index 2 --fsFile "$FPGA_PACKAGE/prebuilt/kv-protected-reset-guarded/project/impl/pnr/shared_product.fs"
```

After successful SRAM programming, allow at least 120 seconds for startup.
From the same directory, run the short token-ID trial with the selected UART.
It clears the current conversation, appends token 27, requests two dependent
tokens and clears the tape again. Expect STEP replies **85, 393** and an
acknowledgment for each CLEAR. The original image also produces these tokens.
Identify the programmed configuration by checking the bitstream bytes before
loading and retaining the programming receipt.

```sh
python3.12 -I -S -B host-app/token_machine_uart.py --device "$FPGA_UART" batch clear append:27 step step clear
```

## Register the guarded image for the browser

Use the [host guide](../../host-app/README.md) to install the browser dependencies
and tokenizer. With the app stopped and the guarded image loaded, run from the
host-app directory. The qualification checks the receipt and image hashes, then
issues CLEAR, APPEND 378, four STEPs and a final CLEAR. The expected tokens
are **200, 15, 103, 157**. If switching a previously qualified board, add
`--replace-profile` to archive its prior local record.

```sh
.venv/bin/python -B qualify_board.py \
  --image-receipt ../prebuilt/kv-protected-reset-guarded/RELEASE.json \
  --device "$FPGA_UART" --confirm-loaded-image --acknowledge-unqualified-timing
.venv/bin/python -B start_local_server.py
```

The browser should display **K/V integrity protection, reset-guarded greedy**.
The release checks verified this profile with a simulated UART. A dedicated
UART collector exercised the corresponding tokens on the physical board.
Enter `around` and request four new tokens to compare with the qualification
sequence. The configured context limit is 2,048 input positions. The short
board capture here covers the recorded prompts.

The existing [historical release](https://github.com/Berkeley-AI-Risk/inference-only/tree/5f4d209a4452fb40a78dde5d3f845dfbec15e773/demos/simplestories-v2-5m/prebuilt/kv-protected) and its [speed record](https://github.com/Berkeley-AI-Risk/inference-only/blob/5f4d209a4452fb40a78dde5d3f845dfbec15e773/demos/simplestories-v2-5m/benchmarks/fpga-speed/captures/protected-common-speed-20261026-r1/FINISHED.json) identify the original unguarded `90ac6815…` image.
