# TLM26 overlapped matrix schedule, measured at 12.5 MHz

This variant measured **3.09743 cached tokens/s**, versus **1.61204** for the preserved original image. Both use the same real pretrained checkpoint, fixed-point precision, page authentication, 12.5 MHz core and **20 ms diagnostic hold on every token job**. Each measurement contains two BOS/128-output trials; all 256 returned IDs match the unchanged integer and FP32 reference. Rates use 254 first-to-last validated-reply intervals, with first-STEP latency reported separately.

| Measured quantity | Original | Overlapped schedule |
| --- | ---: | ---: |
| Pooled cached tokens/s | 1.612038 | 3.097429 |
| First STEP, trial 1 / trial 2 | 577.897 / 577.987 ms | 271.965 / 271.942 ms |
| Core clock | 12.5 MHz | 12.5 MHz |
| Included diagnostic hold | 20 ms | 20 ms |

The one-file RTL change overlaps the next synchronous scratch read and authenticated weight request with the current registered multiply and accumulation. Ordinary matrix hits run at three cycles per term after row startup, versus eleven in the original schedule. The multiplier count, signed widths, accumulation order, row rounding and private verified-weight port are unchanged. A page miss still waits for the full page digest check.

The measured image is `aeccf667a14cbc31cf88a223b643ec37e6dd82df87a4613c4191078972e82e64`; the original is `87af5148584729fe3ea1a0d97d247fce773ef533e8ad1408acde7f5cc6af6a42`. [Source identities](SOURCE-IDENTITIES.json) bind all 28 native inputs. Only the decoder changes behavior; the SDC addition asks for more reports and changes no clock, timing exception or pin constraint.

## Rebuild the source variant

Use the existing demo's [reproduction procedure](../../REPRODUCE.md) to create a fresh, verified original native staging directory with its separately obtained model and vendor dependencies. Apply this file-only overlay **after** that original stage has passed all baseline hashes:

```sh
python3 demos/tlm26-moe/variants/overlap-r2/apply_to_staged.py /path/to/fresh-native-stage
```

The helper checks all 28 original inputs before replacing `tlm_decoder.sv` and appending the report-only SDC queries. It then checks every resulting input against the measured set. It performs no download, EDA run or device operation. `decoder.patch` provides the one-file review diff; `rtl/tlm_decoder.sv` supplies the exact replacement. Running the original decoder generator again regenerates the baseline, so apply this overlay after staging.

Use the original `build.tcl` in the resulting stage with the separately licensed tool. A rebuild may produce a different implementation/image hash; the recorded performance belongs to the exact measured image, not to every rebuild. No model weights, vendor source, netlist, tool or FPGA configuration is supplied by this variant.

## Recheck the saved measurement

From the repository root:

```sh
python3 demos/tlm26-moe/variants/overlap-r2/verify_measurement.py
python3 tools/fpga_speed_benchmark.py --check
```

The variant verifier checks both original and optimized captures against raw UART frames, CRCs, the unchanged references, custody digests, route/image identities and interval boundaries. It also calls the hash-pinned common benchmark parser. Neither command accesses hardware or re-runs model inference.

## Timing qualification

The measured variant retains **143 setup/recovery-side and 34 hold/removal-side failing endpoints**, versus 127 and 34 on the original image. Same-core setup/hold is +58.169/+0.162 ns, but an ordinary 100 MHz transport path has only +0.008 ns setup margin. Whole-image DDR/reset, external pin timing and broader PVT qualification remain open. A successful board experiment does not close those gaps. [Recorded native summary](evidence/route-12p5.json).

This package records only the physically measured 12.5 MHz comparison. The original benchmark row and captures remain separate. Both physical sessions restored the previous signed-update image and verified 108,32 without flash writes. See [notices and provenance](NOTICE.md).
