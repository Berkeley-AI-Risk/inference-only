# Startup reset and timing review

The selected image uses a falling-edge qualification stage followed by three rising-edge core-reset release stages. Resets assert asynchronously. The flash loader retains separate three-stage release chains for core and trusted domains, with a distinct mapped core-clear buffer path.

The mapped design uses no reset-synchronizer entry exception or minimum-delay substitution. The selected core runs at **25 MHz**. Gowin reports a maximum of **25.002 MHz** for that clock. [Source and mapping review](evidence/repair-native-2026-11-05/REVIEW.json) · [Timing review](evidence/repair-native-2026-11-05/TIMING-REVIEW.json)

The whole-design timing summary reports **121 setup and 55 hold violating endpoints**. For each of 27 clocks, the total-negative-slack table lists zero endpoints for both setup and hold. Each detailed path table is limited to 256 paths with `-max_common_paths 1`. Resolving this discrepancy requires targeted reports that identify the matched registers, launch and capture edges, and delay model. [Routed timing report, sections 2 and 3](evidence/repair-native-2026-11-05/home_product.tr)

Hold path 1 shows why the clock relationship matters. The tool reports **−1.115 ns** for a shift register in entropy cell 2. It uses the preceding enable-chain signal as the launch clock and `inference_clk25` as the capture clock. The register is clocked control logic within the entropy source. Its timing and the timing of the vendor DDR interface remain open.

Analog metastability/MTBF, process/voltage/temperature coverage, entropy and physical tamper resistance need separate assessment.

Source-bound phase/count checks and component induction support reset sequencing; the selected-image [board campaign](VALIDATION.md) checks initial startup and fresh-challenge replay rejection after SRAM reconfiguration. Electrical power-cycle freshness is outside that campaign. These are scoped prototype checks, not a production certificate.
