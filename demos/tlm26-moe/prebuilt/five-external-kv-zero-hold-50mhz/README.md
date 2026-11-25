# Run TLM26 with authenticated external K/V on Tang Mega

This package supplies the exact 50 MHz [FPGA image](tlm26.fs) that
authenticates external DDR K/V in all five layers. It shares the
[3 MiB signed int16 model](../overlap-r2-50mhz/model.bin) and
[SentencePiece tokenizer](../overlap-r2-50mhz/tok512.model) with the
on-chip K/V release. The board measured **10.711110 cached tokens/s**
over two 128-output trials and matched all 255 outputs through capacity.
This image uses the same model and cache design as the earlier 20 ms held control. [Image and model identities](IMAGE.json) · [Earlier board evidence](../../../../evidence/tlm26-tang-five-layer-kv-board/README.md)

## Load the image into SRAM

Use a **Tang Mega 138K Basic (non-Pro), GW5AST-LV138PG484AC1/I0,
device revision C**. The tested host is Apple Silicon macOS with
Python 3.12 and the independently installed GOWIN Programmer. Use your
board's Debugger A cable location and free UART. If the board is shared,
arrange how to restore the prior SRAM configuration before loading this image.
[Sipeed board guide](https://wiki.sipeed.com/hardware/en/tang/tang-mega-138k/mega-138k.html)

From the repository root, verify these assets and identify the target:

```sh
python3.12 -B demos/tlm26-moe/scripts/run_prebuilt.py verify --variant five-external-kv-zero-hold-50mhz
TLM_PROGRAMMER="/absolute/path/to/Programmer/bin/programmer_cli"
"$TLM_PROGRAMMER" --scan-cables
TLM_CABLE_INDEX=4
TLM_USB_LOCATION="YOUR_SCAN_LOCATION"
TLM_FPGA_IMAGE="$PWD/demos/tlm26-moe/prebuilt/five-external-kv-zero-hold-50mhz/tlm26.fs"
"$TLM_PROGRAMMER" --device GW5AST-138C --cable-index "$TLM_CABLE_INDEX" \
  --location "$TLM_USB_LOCATION" --frequency 0.9MHz --operation_index 0
```

Use the cable index your scan reports. Require IDCODE `0x0001081B` and a
successful `Finished.` result before loading. Operation 2 writes
volatile FPGA SRAM and leaves power-on flash untouched.

```sh
"$TLM_PROGRAMMER" --device GW5AST-138C --cable-index "$TLM_CABLE_INDEX" \
  --location "$TLM_USB_LOCATION" --frequency 0.9MHz --operation_index 2 \
  --fsFile "$TLM_FPGA_IMAGE"
```

## Provision the model and verify generation

After a successful **SRAM Program**, select the board's UART. The reader
uses 115200 baud, 8N1. From a fresh SRAM load it checks the loader reply and
all 768 page acknowledgments. Allow roughly five minutes for that upload.

```sh
TLM_UART="/dev/cu.usbserial-YOUR_BOARD"
TLM_SESSION_ROOT="/absolute/path/to/existing-session-directory"
python3.12 -B demos/tlm26-moe/scripts/run_prebuilt.py run \
  --variant five-external-kv-zero-hold-50mhz --uart "$TLM_UART" \
  --out "$TLM_SESSION_ROOT/reader-smoke"
```

The default prompt is `Once upon a time`. It should emit IDs
**432 383 286 261 376 298 315 421 395 317 426 338**. The reader
acknowledges CLEAR before and after the prompt. For a custom prompt on
the same powered and provisioned board, use `--already-provisioned`
with `--ids` or install SentencePiece 0.2.1 and use `--prompt`.
Keep prompt plus new tokens within 256 positions. Power cycling or loading
another image requires a fresh upload.

## Repeat the benchmark

Run the two trials as separate reader invocations. Each begins with CLEAR
and BOS 1, compares the next 128 token IDs to the reference and then clears
the tape. The model remains in DDR across CLEAR.

```sh
for trial in 1 2; do
  python3.12 -B demos/tlm26-moe/scripts/run_prebuilt.py run \
    --variant five-external-kv-zero-hold-50mhz --uart "$TLM_UART" \
    --already-provisioned --benchmark --out "$TLM_SESSION_ROOT/trial-$trial" || break
done
python3.12 -B demos/tlm26-moe/scripts/check_prebuilt_benchmark.py --receipts \
  "$TLM_SESSION_ROOT/trial-1/RESULT.json" "$TLM_SESSION_ROOT/trial-2/RESULT.json"
```

The reader records a host timestamp when all five reply bytes have arrived
and another after checking the reply, CRC and expected token. The rate pools
127 cached intervals per trial. First STEP latency runs from the first STEP
send to the respective timing boundary. Model loading and the first STEP
latency are outside the cached rate. The released image sets the
first-weight-return diagnostic hold to zero.

The physical reader checked 768 loader acknowledgments and all 12 default
prompt IDs. Both standard trials matched all 256 benchmark IDs. After the
capacity run, the signed restoration image returned 108 and 32 and
acknowledged final CLEAR.

| Timing boundary | First STEP, trial 1 | First STEP, trial 2 | Cached tokens/s, 254 intervals |
| --- | ---: | ---: | ---: |
| Complete UART frame | 84.989 ms | 84.926 ms | 10.711105 |
| After reply validation | 85.018 ms | 84.941 ms | 10.711110 |

[Release reader capture](READER-CAPTURE.json)

## Repeat the full-history trial

The reader checks the saved integer reference for BOS and 255 outputs.
Run this after the two trials to include the capacity receipt in the same
recalculation.

```sh
python3.12 -B demos/tlm26-moe/scripts/run_prebuilt.py run \
  --variant five-external-kv-zero-hold-50mhz --uart "$TLM_UART" \
  --already-provisioned --capacity --out "$TLM_SESSION_ROOT/capacity"
python3.12 -B demos/tlm26-moe/scripts/check_prebuilt_benchmark.py --receipts \
  "$TLM_SESSION_ROOT/trial-1/RESULT.json" "$TLM_SESSION_ROOT/trial-2/RESULT.json" \
  --capacity-receipt "$TLM_SESSION_ROOT/capacity/RESULT.json"
```

| Capacity window | Intervals | Complete UART frame | After reply validation |
| --- | ---: | ---: | ---: |
| All 255 outputs | 254 | 9.200737 | 9.200737 |
| Last 32 cached intervals | 32 | 7.353335 | 7.353335 |

Rates are cached tokens/s. To check the bundled runs offline, omit the
receipt arguments.

```sh
python3.12 -B demos/tlm26-moe/scripts/check_prebuilt_benchmark.py
```

## Older held control

The separate held image `7bb2e988` retains the 20 ms first-return delay.
Its matched earlier board session used the same model, clock, UART protocol
and workload. It matched all 256 IDs at **8.904667 validated cached
tokens/s** and **8.904668 complete-frame cached tokens/s**. The older
capacity session measured **7.798575 cached tokens/s** using complete
frame receipt. That archived session also has its own 8.883470
complete-frame paired rate. The control captures are from earlier sessions
on the same board. [Matched held reader capture](HELD-READER-CAPTURE.json) · [Original held and capacity evidence](../../../../evidence/tlm26-tang-five-layer-kv-board/README.md)

## Timing and attribution

Reported 50 MHz inference setup and hold slack are +0.537 ns and +0.183 ns.
Reported 100 MHz application setup and hold slack are +0.555 ns and +0.131 ns.
The route retains **120 setup/recovery and 34 hold/removal violating
endpoints** within vendor DDR. The check covers the reported core and
application clock pairs. The retained path tables do not enumerate the
application-good and application-fault synchronizers individually.
[Image, clock-pair slacks and route scope](IMAGE.json)

The bitstream retains the original GOWIN header. The shared model and
tokenizer retain their MIT provenance. Vendor tools and IP source remain
separate dependencies. [TLM26 notices](../../NOTICES.md) · [License scope](../../../../LICENSE-SCOPE.md)
