# Startup reset and timing review

The selected image uses a falling-edge qualification stage followed by three rising-edge core-reset release stages. All source resets assert asynchronously. The flash loader retains separate three-stage release chains for its core and trusted clock domains; its core-clear path has a distinct mapped AND gate followed by an inverter.

The [mapped realization](evidence/native-v132/RESET-REALIZATION.json) records the actual circuit. The source's identity-LUT requests are absorbed by synthesis; the review does not assume two retained LUT1 instances. The mapped assertion cones are Boolean-equivalent for all four input assignments. Physical delay is established by the routed timing report.

**The selected 25 MHz image uses no reset-synchronizer timing exceptions.** Its raw report has no negative functional setup, hold, recovery or removal paths in the bounded tables. The five real named clock domains report zero setup/hold violating endpoints. The reported core maximum is **25.005 MHz**, so the setup margin is small. The main phase-qualifier removal slack is **+0.325 ns**; all three flash-core release CLEAR inputs have **+0.494 ns** removal slack.

The [timing review](evidence/native-v132/TIMING-REVIEW.json), [raw report](evidence/native-v132/native-report.tr) and [structural review](evidence/native-v132/REVIEW.json) bind these results to the exact prebuilt image. The clock/timing SDC is unchanged from the source experiment, with no false-path, multicycle, clock-group, disabled-timing or minimum-delay substitution used to obtain the result.

The digital checks include 2,240 main-reset release phases, 160 starts using the unmodified vendor divider model, 1,200 flash-reset phase/combinations, stopped-clock assertion/restart, and inductive release-count specifications. Four full-design scenarios and eight complete volatile board startups pass. The checks are described in [VALIDATION.md](VALIDATION.md).

Remaining bounded negative paths concern vendor DDR or entropy circuitry. Complete vendor-DDR timing, analog metastability/MTBF, entropy qualification, ASIC process/voltage/temperature signoff and physical-tamper resistance remain separate obligations. This is a functional FPGA demonstration, not a production certificate.
