# Protected pretrained TLM26 on Tang Mega

The 50 MHz Tang Mega image authenticated external K/V for layers 0 and 1 of the five-layer pretrained TLM26 model. The two protected trials returned all 256 expected token IDs. The earlier 50 MHz control kept K/V on chip and used the same physical board, model image and workload. [Image, model and source identities](IMAGE-SOURCE.json)

| Configuration | Trial 1 cached tokens/s | Trial 2 cached tokens/s | Pooled cached tokens/s | First STEP, trials 1 and 2 |
| --- | ---: | ---: | ---: | --- |
| Authenticated external K/V in layers 0 and 1 | 9.022967 | 9.022892 | **9.022930** | 101.985 ms, 101.923 ms |
| Earlier on-chip control | 9.077751 | 9.077738 | **9.077744** | 102.083 ms, 101.987 ms |

Each trial appended BOS token 1 after CLEAR and generated 128 greedy outputs. The pooled rate divides 254 cached intervals by the sum of the two first-to-last host-validated reply spans. The protected rate was 0.604% lower in this historical comparison. Both images used a diagnostic first-return hold of 1,000,000 core cycles. The candidate’s 768-page model upload took 282.687 seconds and is outside the generation measurement. [Protected UART capture](UART-TRACE.json) · [Earlier raw control](../../benchmarks/fpga-speed/tlm26-overlap-r2-50mhz-v1/CAPTURE.json)

## Check the recorded measurement

Run the following from the repository checkout on a POSIX host with Python 3.

```sh
python3 -I -S -B evidence/tlm26-tang-protected-kv-board/check_capture.py
```

The checker uses the TLM26 [UART codec](../../demos/tlm26-moe/scripts/uart_replay.py) and the [shared checkpoint and integer references](../../benchmarks/fpga-speed/tlm26-overlap-r2-50mhz-v1/golden.json). It matches the bytes, CRC and order of all 262 command/reply pairs in each arm. It recomputes rates from the recorded host timestamps and checks the two signed-image sentinels. The new capture keeps relative times and exact protocol bytes. The check opens no device.

The protected image was loaded into SRAM. The signed-update image returned 108, 32 and acknowledged CLEAR before the trial and again after SRAM restoration. The source receipt identifies the routed candidate, the native input files and tool, the int16 model, the two SRAM programming logs and the earlier control. The restored image and protected candidate are identified by digest. [Image, model and source identities](IMAGE-SOURCE.json)

## Timing and K/V scope

On the protected routed build, the 50 MHz inference domain had reported setup slack of +0.564 ns and hold slack of +0.199 ns. The 100 MHz application domain’s reported setup slack was +0.004 ns. The whole-image report still lists 200 setup-side and 34 hold-side violating endpoints. DDR and whole-design timing remain open. Stale K/V rejection was observed in RTL simulation. The board capture covers clean inference and restoration. [Routed report identities](IMAGE-SOURCE.json)

See the [TLM26 model and implementation guide](../../demos/tlm26-moe/README.md) and [attribution notices](../../demos/tlm26-moe/NOTICES.md).
