# Experimental HWIC progress — November 4, 2026

The SimpleStories study now has a matched physical comparison between grouped
fixed-weight arithmetic and a banked-ROM implementation of the complete 256×256
layer-0 query projection. Precision remains W10/A16 with the original BFP-v5
arithmetic; this introduces no model quantization change. The table below
records the November 4 physical points. The [physical result summary](evidence/physical-query-2026-11-05/results.json)
binds those observations to their comparison and power-review record hashes.
Raw physical implementation artifacts remain private; the summary is not a
standalone reproduction package.

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
In these November 4 points, grouped/spatial is faster and uses less energy per
projection, while ROM16 uses less area and average power. These measurements
motivate the comparison; they do not qualify either implementation for silicon.

## Subsequent ROM16 result — November 5

A separate ROM16 point completed signal detailed routing with zero reported
native routing violations and empty router and fresh native DRC reports.
Actual wire-based predictive extraction and a separate fresh SPEF readback both
report setup slack +0.03048 ns, hold slack +0.03960 ns and zero setup TNS at the
unchanged 2 ns target. Native slew, capacitance and fanout violation counts are
all zero. Explicit coverage checks pass for all 1,541,937 load-bearing nets,
including exact terminals, resistor reachability, capacitance totals and mirrored
coupling records. The [result summary](evidence/physical-query-2026-11-05/results.json)
identifies the detailed-route, extraction and coverage review records.

This is a single-query research-flow result. All-terminal geometric wire/pin/via
connectivity, foundry DRC/LVS, broader timing corners and complete-chip
qualification remain open. No new power or energy result has been established
for this point; the November 4 power table above applies to its original points.
The later grouped local-tag candidate takes 57 cycles. Its bounded repair
attempt reached the six-hour wall limit during the first electrical-repair pass
on November 5, before producing a completed repaired point. Its original-tool
replay and no-edit checks passed; the guard stopped and drained the owned
processes, and native CPU accounting was retained. No final repaired timing or
power result is inferred from that incomplete attempt or from the older 55-cycle
grouped comparison.

There is no automatic retry or repair extension. Authentication-cost comparison
and process/security feasibility are the next priorities before another
physical optimization campaign. The November 4 power comparison, November 5
ROM16 extraction point and capped grouped attempt remain separate observations.

The full-model memory organization has also been audited. Qualified large
ROM/SRAM implementations, whole-chip area and floorplanning, detailed routing,
extraction, corner timing, physical verification and manufacturing sign-off
remain future work. Reuse of verified AWIC/HWIC arithmetic, interfaces and test
infrastructure remains a main goal. SimpleStories remains first; Qwen 8B and
optional FPGA component tests remain deferred.

The design study draws on the [HNLPU paper](https://arxiv.org/abs/2508.16151v2).
It uses generated RTL and standard-cell implementations; HNLPU's custom physical
weight-routing layout has not been reproduced.
