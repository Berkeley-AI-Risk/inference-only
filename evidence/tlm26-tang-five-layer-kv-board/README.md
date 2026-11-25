# Five-layer authenticated external K/V on Tang Mega

The 50 MHz pretrained TLM26 image authenticated external K/V for all five layers. The earlier control authenticated layers 0 and 1. Both used the same Tang Mega 138K device revision C, 3 MiB int16 model image, UART protocol and diagnostic first-return hold. Gowin reports 84 of 340 BSRAMs used for the five-layer image, down from 208. [Image, model and native source hashes](IMAGE-SOURCE.json)

| Measured host-validated rate | Five layers | Two layers | Intervals per arm |
| --- | ---: | ---: | ---: |
| Two clean 128-output trials, pooled | **8.883470 tokens/s** | **9.022930 tokens/s** | 254 |
| First 128 outputs of the capacity trial | 8.894084 tokens/s | 9.012066 tokens/s | 127 |
| Capacity trial, first through 255th generated reply | 7.798575 tokens/s | 7.990386 tokens/s | 254 |
| Capacity trial, last 32 cached intervals | 6.536339 tokens/s | 6.536395 tokens/s | 32 |

Each trial began with CLEAR and BOS token 1. The five-layer capture contains all 527 exchanges from its two 128-output trials and its full-context trial. All 256 short-trial IDs, all 255 full-context STEP IDs and the first five STEP replies after CLEAR matched the reference. BOS and 255 accepted STEPs filled the 256 context positions. Both full-context sessions restored the signed-update image and repeated the sentinel tokens 108 and 32 followed by CLEAR. Programming used SRAM. The rate divides the number of intervals by the elapsed time between receipt of the first and last replies in the selected window. Model loading and the first STEP latency are outside the cached rate. [Recorded exchanges](UART-TRACE.json) · [Earlier two-layer board benchmark](../tlm26-tang-protected-kv-board/README.md)

## Recheck the wire results

From a repository checkout with Python 3, run

```sh
python3 -I -S -B evidence/tlm26-tang-five-layer-kv-board/check_capture.py
```

The checker verifies the exact commands, reply bytes, CRCs and timing order. It recomputes the rates from relative host timestamps. The recorded 255-ID integer reference extends the public 128-ID prefix, which agrees with the checkpoint reference. It compares both board captures against that reference and opens no device. [Recorded reference](REFERENCE.json) · [Public 128-ID reference](../../benchmarks/fpga-speed/tlm26-overlap-r2-50mhz-v1/golden.json)

## Routed timing and scope

| Domain or crossing | Setup slack | Hold slack |
| --- | ---: | ---: |
| 50 MHz inference | +0.768 ns | +0.182 ns |
| 100 MHz DDR application | +0.328 ns | +0.127 ns |
| Inference to application | +8.332 ns | +0.301 ns |
| Application to inference | +8.055 ns | +0.298 ns |

The retained report contains 36 directed clock pairs per timing check. The native review identified all 131 setup or recovery violations and 34 hold or removal violations in the vendor DDR hierarchy. The bounded crossing tables include command and return pointers and reset release. They do not identify the application-good and application-fault synchronizers individually. DDR and whole-image timing remain open.

The clean board trials checked generation through capacity and after CLEAR. The matched native simulation separately checked all 81,920 committed K/V words at capacity and 5,240 five-layer tag comparisons including replay. Bitstream, native tool and report hashes bind the measured build. The wire checker verifies the archived exchanges and rates. Rebuilding the routed image requires the original production board inputs and Gowin DDR IP. [Timing and simulation identities](IMAGE-SOURCE.json) · [TLM26 implementation](../../demos/tlm26-moe/README.md) · [Attribution](../../demos/tlm26-moe/NOTICES.md)
