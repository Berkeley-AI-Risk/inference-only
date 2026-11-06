# Startup reset and timing review

The selected image uses a falling-edge qualification stage followed by three rising-edge core-reset release stages. Resets assert asynchronously. The flash loader retains separate three-stage release chains for core and trusted domains, with a distinct mapped core-clear buffer path.

The [source/mapping review](evidence/repair-native-2026-11-05/REVIEW.json) checks the actual selected structure. The [timing review](evidence/repair-native-2026-11-05/TIMING-REVIEW.json) and [raw report](evidence/repair-native-2026-11-05/home_product.tr) show zero real-clock setup/hold violating endpoints and no additional functional negative paths in the bounded setup/hold/recovery/removal tables. No reset-synchronizer entry exception or minimum-delay substitution is used.

The clock is **25 MHz**, with a reported maximum of **25.002 MHz** and very little setup margin. The bounded negative paths remain within vendor DDR or physical entropy circuitry. Those paths, analog metastability/MTBF, process/voltage/temperature coverage, entropy and physical tamper resistance need separate assessment.

Source-bound phase/count checks and component induction support reset sequencing; the selected-image [board campaign](VALIDATION.md) checks initial startup and fresh-challenge replay rejection after SRAM reconfiguration. Electrical power-cycle freshness is outside that campaign. These are scoped prototype checks, not a production certificate.
