# Startup reset and timing review

The selected image uses a falling-edge qualification stage followed by three rising-edge core-reset release stages. Resets assert asynchronously. The flash loader retains separate three-stage release chains for core and trusted domains, with a distinct mapped core-clear buffer path.

The mapped design uses no reset-synchronizer entry exception or minimum-delay substitution. The selected core runs at **25 MHz**. Gowin reports a maximum of **25.002 MHz** for that clock. [Source and mapping review](evidence/repair-native-2026-11-05/REVIEW.json) · [Timing review](evidence/repair-native-2026-11-05/TIMING-REVIEW.json)

The whole-design timing summary reports **121 setup and 55 hold violating endpoints**. For each of 27 clocks, the total-negative-slack table lists zero endpoints for both setup and hold. Each detailed path table is limited to 256 paths with `-max_common_paths 1`. Resolving this discrepancy requires targeted reports that identify the matched registers, launch and capture edges, and delay model. [Routed timing report, sections 2 and 3](evidence/repair-native-2026-11-05/home_product.tr)

**Hold path 1 (−1.115 ns).** In entropy cell 2, `sreg_3_s0` and
`sreg_4_s0` both use the 25 MHz core clock. The preceding register's Q feeds
the next register's D and a ring latch's gate. The tool starts the reported
launch path at that Q, names its enable signal as a separate 100 MHz base
clock, and captures on `inference_clk25`. The clock-propagation model and the
complete same-core-clock register path need review.
[Pin/clock inventory](evidence/timing-path-inspection-2026-11-07/INVENTORY.json) ·
[Report sections 2.2 and 3.3.2, path 1](evidence/repair-native-2026-11-05/home_product.tr)

**DDR setup path 1 (−2.261 ns).** This path captures the DDR DLL's calibration
code: `u_dll/CLKIN → STEP[0] → dll_step_base_0_s0/D`, with a calibration-dependent
capture enable. The product timing model uses a 400 MHz rising launch edge at
7.500 ns and a 100 MHz rising capture edge at 10.000 ns. Its printed arrivals
reproduce the slack: `13.373 − 15.634 = −2.261 ns`.
[Pins, enable and clock relationship](evidence/timing-path-inspection-2026-11-07/INVENTORY.json) ·
[Report section 3.3.1, path 1](evidence/repair-native-2026-11-05/home_product.tr)

The [original upstream constraint file](https://github.com/sipeed/TangMega-138K-example/blob/06e7d8b118d345915ab6f257b7c22226f81575cd/ddr_memory/ddr_memory_test_uart/src/ddr3_1v4_hs.sdc)
excludes analysis between its memory and application clocks. That does not
establish a calibration exception for this design: stable, coherent
`STEP[7:0]` at the enabled sampling edge is **unverified**. The
[inventory's source identities and open obligations](evidence/timing-path-inspection-2026-11-07/INVENTORY.json)
keep that requirement separate from the reported clock relationship. These
examples do not establish corrected timing; both paths remain open.

Analog metastability/MTBF, process/voltage/temperature coverage, entropy and physical tamper resistance need separate assessment.

Source-bound phase/count checks and component induction support reset sequencing; the selected-image [board campaign](VALIDATION.md) checks initial startup and fresh-challenge replay rejection after SRAM reconfiguration. Electrical power-cycle freshness is outside that campaign. These are scoped prototype checks, not a production certificate.
