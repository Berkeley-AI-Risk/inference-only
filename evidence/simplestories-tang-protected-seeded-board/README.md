# Protected seeded SimpleStories on Tang Mega

The protected seeded image `490a58526e6a9593a07e5744779ab6f55d25a8fd4c192df86b34be55c9aee23f` ran on a Tang Mega 138K Basic. The source retains the verified external K/V guard and adds the seeded token selector. The separate signed-update image supplied the entry and restoration checks. [Image and source identities](IMAGE-SOURCE.json)

| Exercise | Recorded UART result |
| --- | --- |
| Protected greedy control and seeded image default | For prompt 378, both returned 200, 15, 103, then 200 after CLEAR and re-append. |
| Temperature 1 and the public seed | SETTINGS acknowledged with `0x83/2`. The three sampled tokens were 357, 3898, 104. |
| SETTINGS on a nonempty tape | The second 20-byte SETTINGS request returned `0xc3/0`. |
| Replay after CLEAR | The same prompt yielded 357, 3898, 104 again with the retained settings. Final CLEAR acknowledged. |
| Signed image before and after | Prompt 1 gave 108, 32 and CLEAR acknowledged on both checks. All three configuration operations used SRAM. |

## 128-output benchmark

The same 25 MHz protected seeded image averaged **7.03152 cached tokens/s** over two 128-output trials. Both used prompt token 378, temperature 1, and public seed 0x99aabbccddeeff001122334455667788. Every output matched the independent scalar reference. Trial 2 replayed the sequence after CLEAR with the retained settings.

| Trial | Matched outputs | First STEP | Cached reply intervals | Cached tokens/s |
| --- | ---: | ---: | ---: | ---: |
| Fresh SETTINGS | 128 | 102.004 ms | 127 | 7.02820 |
| CLEAR replay | 128 | 102.040 ms | 127 | 7.03485 |

The pooled rate counts 254 intervals over 36.123035209 seconds between validated replies. The restored signed image returned 108, 32 and acknowledged final CLEAR. [Timed UART capture](COMMON-SPEED.json) · [Common benchmark results](../../benchmarks/fpga-speed/results.json)

## Check the captured exchanges

Run the following from the repository checkout with Python 3.12 or newer.

```sh
python3 -I -S -B evidence/simplestories-tang-protected-seeded-board/check_capture.py
```

The checker uses the [public SETTINGS codec and sample fixture](../../demos/simplestories-v2-5m/host-app/sampling_protocol.py). It checks the raw bytes, order and CRCs of all 40 request/reply pairs, including the two 20-byte SETTINGS requests. The raw capture contains the exact token and SETTINGS traffic. The source receipt identifies the 94 native inputs, the protected control and model already in the repository, the routed candidate and the signed restoration image. [Raw capture](UART-TRACE.json) · [Checksums](SHA256SUMS)

## Timing and observation scope

The reported inference setup and hold slack were +0.409 ns and +0.170 ns. The vendor DDR timing report still lists 145 setup or recovery and eight hold or removal endpoints with negative slack. The board observation covers clean token generation, SETTINGS, CLEAR and restoration. The K/V guard is documented by the source and native reports. Fault injection and internal tag comparisons were outside this UART observation. [Timing and source identities](IMAGE-SOURCE.json)

See the [seeded-generation guide](../../demos/simplestories-v2-5m/STOCHASTIC-GENERATION.md) and [SimpleStories model attribution](../../demos/simplestories-v2-5m/README.md).
