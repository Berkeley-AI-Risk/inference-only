# Run the measured 50 MHz TLM26 on Tang Mega

This package provides the exact [FPGA image](tlm26.fs) and [3 MiB int16 model](model.bin) used for the **9.077744453 cached tokens/s** measurement. The image uses on-chip K/V and authenticates weight pages fetched from DDR. The two 128-output benchmark trials matched all 256 reference IDs. The 20 ms diagnostic DDR hold is included. The routed analysis still has **158 setup/recovery-side and 34 hold/removal-side violating endpoints** in vendor DDR. [Measured run](../../variants/overlap-r2-50mhz/README.md) · [Image and model identities](IMAGE.json)

## Load the FPGA SRAM image

Use a **Tang Mega 138K non-Pro, device C, GW5AST-LV138PG484AC1/I0**. The tested command-line setup uses the separate GOWIN Programmer on Apple Silicon macOS and Python 3.12. Use a free UART on the chosen board. For a shared board, arrange the current owner’s SRAM restoration before reconfiguring it. [Board guide](https://wiki.sipeed.com/hardware/en/tang/tang-mega-138k/mega-138k.html) · [Licensing](../../../../LICENSING.md)

From the repository root, check the shipped files and list the attached programmer cables.

```sh
python3.12 -B demos/tlm26-moe/scripts/run_prebuilt.py verify
TLM_PROGRAMMER="/absolute/path/to/Programmer/bin/programmer_cli"
"$TLM_PROGRAMMER" --scan-cables
```

Set the index and location reported for the intended USB Debugger A. The recorded setup used index 4 and a 0.9 MHz JTAG rate. Read IDCODE first and proceed only with `0x0001081B` and a successful `Finished.` result. Operation 2 loads FPGA SRAM. The power-on flash is untouched.

```sh
TLM_CABLE_INDEX=4
TLM_USB_LOCATION="YOUR_SCAN_LOCATION"
TLM_FPGA_IMAGE="$PWD/demos/tlm26-moe/prebuilt/overlap-r2-50mhz/tlm26.fs"
"$TLM_PROGRAMMER" --device GW5AST-138C --cable-index "$TLM_CABLE_INDEX" \
  --location "$TLM_USB_LOCATION" --frequency 0.9MHz --operation_index 0
```

```sh
"$TLM_PROGRAMMER" --device GW5AST-138C --cable-index "$TLM_CABLE_INDEX" \
  --location "$TLM_USB_LOCATION" --frequency 0.9MHz --operation_index 2 \
  --fsFile "$TLM_FPGA_IMAGE"
```

Require a successful SRAM Program result before opening the UART. The measured programmer log identifies the device C; use your own cable location and serial port.

## Provision the model and check a prompt

The client uses 115200 baud, 8N1. It sends `TLM1` to the boot loader and checks all 768 page acknowledgments before issuing token commands. Allow roughly five minutes for the model upload. Choose a new output folder under an existing directory.

```sh
TLM_UART="/dev/cu.usbserial-YOUR_BOARD"
TLM_SESSION="/absolute/path/to/new-tlm26-session"
python3.12 -B demos/tlm26-moe/scripts/run_prebuilt.py run \
  --uart "$TLM_UART" --out "$TLM_SESSION"
```

The default check sends the reference IDs for `Once upon a time`, with BOS, in a fresh tape. The twelve expected replies are `432 383 286 261 376 298 315 421 395 317 426 338`. The session receipt retains the acknowledged pages, UART request and reply frames, measured host round trips and result. [Integer reference](../../evidence/integer-cpu.json)

To run another text prompt on an already provisioned board, install SentencePiece in your Python environment and use the included tokenizer. You can also supply the complete input ID sequence with `--ids` instead of text.

```sh
python -m pip install sentencepiece==0.2.1
python -B demos/tlm26-moe/scripts/run_prebuilt.py run \
  --uart "$TLM_UART" --already-provisioned --prompt "The little cat" \
  --new-tokens 12 --out "/absolute/path/to/new-tlm26-prompt"
```

The input plus generated IDs must fit within 256 positions. Each run starts with CLEAR, so it gets a fresh token history. The model stays in DDR across CLEAR and must be uploaded again after a power cycle or a new SRAM load. Use the shared board’s agreed SRAM restoration procedure when finished.

The [.fs and model provenance](IMAGE.json) and [upstream notices](../../NOTICES.md) identify the exact outputs, preserved Gowin header and MIT model data. The [source reproduction guide](../../REPRODUCE.md) covers rebuilding with separately obtained vendor tools.
