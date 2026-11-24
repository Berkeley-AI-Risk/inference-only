# Measured TLM26 at 50 MHz

The overlapped TLM26 schedule measured **9.077744453 cached tokens/s** on Tang Mega device C. The two independent BOS/128-output trials measured **9.077751280** and **9.077737626**. All 256 IDs match the unchanged integer and FP32 references. The pooled 254 cached intervals span **27.980518875 seconds**; first STEP is reported separately at **102.083292 / 101.986541 ms**.

Keep three measured images separate: the original 12.5 MHz image measured **1.612038177**, the [overlapped 12.5 MHz image](../overlap-r2/README.md) **3.097428715**, and this 50 MHz image **9.077744453**. They use the same checkpoint, int16 model image, arithmetic and page authentication. All retain an included **20 ms** first-return diagnostic hold. These are single-stream host-validated FPGA measurements.

The [portable captures](../../../../benchmarks/fpga-speed/tlm26-overlap-r2-50mhz-v1/CAPTURE.json) retain byte-identical raw trials and the original physical timing boundary. The measured image SHA-256 is `4da8188c7c27af20c4a759085d7cf0ecd8a12078e6ff9518f661db69d1a4a93b`.

## Exact source delta

Apply the prior overlap-r2 overlay to a verified original native stage first, then run this variant's `apply_to_staged.py` on that stage. The helper checks all 28 input hashes before and after, and is idempotent. It changes three native inputs: `top.sv`, `board1_gowin_ddr3_raw_controller_shell.sv` and `product.sdc`. The [review diff](clock-delivery.patch) and [source identities](SOURCE-IDENTITIES.json) identify exact measured bytes. It performs file operations only and never invokes EDA or a programmer.

The core uses the existing PLL's 50 MHz output through a native CLKDIV in divide-by-one/pass-through mode. The actual core constraint also uses `-divide_by 1`. DDR memory stays 400 MHz and its application clock 100 MHz. Runtime and loader UART divisors scale from 109 to **436**, preserving the same actual hardware baud rate. The hold scales from 250,000 to **1,000,000 cycles**, preserving 20 ms. The decoder, on-chip K/V, weight authentication, SHA compressor, transport, model and PLL outputs are unchanged. The exact measured input retains historical source comments; active primitives and constraints define the recorded clock.

Rebuilds may have different implementation hashes. The saved rate applies to the exact recorded image in the [50 MHz runnable package](../../prebuilt/overlap-r2-50mhz/README.md). Its generated bitstream and packed model are ready for SRAM loading and UART provisioning. The documented source rebuild obtains vendor inputs separately.

## Timing and assurance scope

The [native route summary](evidence/route-50mhz.json) reports core setup **+2.861 ns**, hold **+0.163 ns**, incoming reset recovery **+1.749 ns**, removal **+0.960 ns**, and ordinary application setup **+1.078 ns**. Whole-image timing remains open: **158 setup/recovery-side and 34 hold/removal-side failing endpoints** remain in the recorded vendor-DDR scope. The two successful physical trials do not establish DDR/pin/PVT qualification or ASIC readiness.

The [K/V lifecycle review](KV-LIFECYCLE.md) traces the current on-chip cache and reports the first finite clean-versus-reused-history regression. Its exact test source and results are in `tests/`; it is not an unbounded noninterference proof or physical fault certification.

Run `python3 -I -S -B demos/tlm26-moe/variants/overlap-r2-50mhz/verify_measurement.py --package .` from the repository root. This read-only verifier checks the six raw histories, saved restoration and image identities, references, and exact frame/timestamp boundaries. It pins the common benchmark calculator and checks its rates independently. The calculator retains its numerical rules and all earlier result rows; its presentation now uses a separate table for each model. This rate rounds to **9.1** in that table format.

See [NOTICE.md](NOTICE.md) and [PROVENANCE.json](PROVENANCE.json). Historical restoration records contain successful signed-image `[108,32]` checks; they confer no current device custody or programming authorization.
