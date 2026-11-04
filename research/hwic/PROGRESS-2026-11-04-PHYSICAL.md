# Experimental HWIC progress — November 4, 2026

The SimpleStories study now has a matched physical comparison between grouped
fixed-weight arithmetic and a banked-ROM implementation of the complete 256×256
layer-0 query projection. Precision remains W10/A16 with the original BFP-v5
arithmetic; this introduces no model quantization change.

Both actual gate-level simulations passed 47 inference input vectors, all
12,032 result rows and exponents, packet ordering and expected cycle counts.
Physical correspondence checks cover cells and connected signal/clock pins.
Every reportable pin has measured activity, and every loaded driver has RC
coverage. Independent review accepted the completed captures and diagnostic
power results.

| Component result | Grouped | ROM16 |
|---|---:|---:|
| Cell area, mm² | 3.260 | 2.188 |
| Sequential cycles per projection | 55 | 107 |
| Estimated average power, W | 2.104 | 1.630 |
| Estimated energy per projection, nJ | 231.4 | 348.9 |
| Worst setup slack, ns | −0.76251 | −0.98901 |
| Worst hold slack, ns | −0.08917 | −0.03950 |

These use predictive Nangate45/FreePDK45 research views, a nominal 2 ns clock,
1.10 V and 25°C, zero-delay inference activity and global-route RC reconstructed
from saved guides. Both layouts retain routing congestion and negative
setup/hold. They are diagnostic points, with no accepted legal detailed route,
extracted sign-off RC, implemented 500 MHz clock or qualified ASIC. The reported
power and energy exclude the rest of the model, KV memory and the package.

ROM16 uses about 33% less cell area and 23% less average power, while taking
almost twice as many cycles. Its energy per projection is about 51% higher.
Grouped/spatial remains the primary candidate for routing and timing closure
because it is faster and uses less energy per projection in this comparison.
ROM16 remains a comparison for area and routing tradeoffs. The next physical milestone is legal global routing
and setup/hold closure on a complete query block under the unchanged clock target,
starting with the driver/buffer and placement issues exposed by the real paths.

The full-model memory organization has also been audited. Qualified large
ROM/SRAM implementations, whole-chip area and floorplanning, detailed routing,
extraction, corner timing, physical verification and manufacturing sign-off
remain future work. Reuse of verified AWIC/HWIC arithmetic, interfaces and test
infrastructure remains a main goal. SimpleStories remains first; Qwen 8B and
optional FPGA component tests remain deferred.

The design study draws on the [HNLPU paper](https://arxiv.org/abs/2508.16151v2).
It uses generated RTL and standard-cell implementations; HNLPU's custom physical
weight-routing layout has not been reproduced.
