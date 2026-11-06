# Startup reset and timing review

The selected image uses a falling-edge qualification stage followed by three rising-edge core-reset release stages. Resets assert asynchronously. The flash loader retains separate three-stage release chains for core and trusted domains, with a distinct mapped core-clear buffer path.

The [source/mapping review](evidence/repair-native-2026-11-05/REVIEW.json) checks the actual selected structure. The [timing review](evidence/repair-native-2026-11-05/TIMING-REVIEW.json) records zero setup/hold violating endpoints in five named real-clock summaries. The same [raw report](evidence/repair-native-2026-11-05/home_product.tr) contains interclock negative paths, so those summaries do not establish complete functional timing. No reset-synchronizer entry exception or minimum-delay substitution is used.

The clock is **25 MHz**, with a reported maximum of **25.002 MHz** and very little reported setup margin.

The entropy-hierarchy hold negatives include clocked enable-shift and debias-control registers as well as an oscillator-latch path. The register paths are functional logic, not intentional oscillator loops; the report uses enable-chain nets as launch clocks. The archived review's broad entropy classification does not resolve their timing. Targeted analysis must establish the correct launch/capture clock relationships, edges, corners and path coverage before deciding whether these negatives reflect clock modeling, physical violations or both. Zero per-clock summaries and successful tokens do not settle that question. Vendor-DDR timing and its functional interface boundaries also remain unresolved.

Analog metastability/MTBF, process/voltage/temperature coverage, entropy and physical tamper resistance need separate assessment.

Source-bound phase/count checks and component induction support reset sequencing; the selected-image [board campaign](VALIDATION.md) checks initial startup and fresh-challenge replay rejection after SRAM reconfiguration. Electrical power-cycle freshness is outside that campaign. These are scoped prototype checks, not a production certificate.
