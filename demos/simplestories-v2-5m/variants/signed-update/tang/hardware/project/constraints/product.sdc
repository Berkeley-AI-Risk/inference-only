// Diagnostic clock model, NOT a physical-acceptance certificate.
// Exact pinned official PLL: input 50 MHz, output 2 at 400 MHz, phase 0.
// DDR fclkdiv is expected to divide that by four. Check the actual native
// netlist and clock table; an SDC declaration alone does not establish this.
create_clock -name board_clk50 -period 20.000 -waveform {0 10.000} [get_ports {clk_50mhz}]
// The raw shell's preserved reset registers retain its otherwise unused
// trusted divider. Native run0 exposed TA1132 on this exact clock; include
// its real lineage rather than ignoring the warning or cutting those paths.
create_generated_clock -name pll_clkout1_50 -source [get_ports {clk_50mhz}] -master_clock [get_clocks {board_clk50}] -multiply_by 1 -divide_by 1 [get_pins {u_raw_controller/u_board_ddr_pll/u_pll/PLL_inst/CLKOUT1}]
create_generated_clock -name memory_clk400 -source [get_ports {clk_50mhz}] -master_clock [get_clocks {board_clk50}] -multiply_by 8 -divide_by 1 [get_pins {u_raw_controller/u_board_ddr_pll/u_pll/PLL_inst/CLKOUT2}]
create_generated_clock -name app_clk100 -source [get_pins {u_raw_controller/u_board_ddr_pll/u_pll/PLL_inst/CLKOUT2}] -master_clock [get_clocks {memory_clk400}] -divide_by 4 [get_pins {u_raw_controller/u_ddr3/gw3_top/u_ddr_phy_top/fclkdiv/CLKOUT}]
create_generated_clock -name trusted_clk12p5 -source [get_pins {u_raw_controller/u_board_ddr_pll/u_pll/PLL_inst/CLKOUT1}] -master_clock [get_clocks {pll_clkout1_50}] -divide_by 4 [get_pins {u_raw_controller/u_trusted_clkdiv/CLKOUT}]

// Real dedicated inference divide-by-two, not a relaxed constraint on board_clk50.
create_generated_clock -name inference_clk25 -source [get_pins {u_raw_controller/u_board_ddr_pll/u_pll/PLL_inst/CLKOUT1}] -master_clock [get_clocks {pll_clkout1_50}] -divide_by 2 [get_pins {u_raw_controller/u_core_clkdiv/CLKOUT}]

// No false paths, clock groups, multicycle paths, or arbitrary CDC bounds.
// This initial build intentionally exposes vendor-IP and reset paths. DDR
// pin timing, reset synchronization, clock uncertainty/phase and UART baud
// still need separate qualification before hardware programming.
// Bounded diagnostic tables; a 256-row table is NOT exhaustive evidence.
report_timing -setup -max_paths 256 -max_common_paths 1
report_timing -hold -max_paths 256 -max_common_paths 1
report_timing -recovery -max_paths 256 -max_common_paths 1
report_timing -removal -max_paths 256 -max_common_paths 1
report_exceptions -setup -max_paths 256 -max_common_paths 1
report_exceptions -hold -max_paths 256 -max_common_paths 1
report_exceptions -recovery -max_paths 256 -max_common_paths 1
report_exceptions -removal -max_paths 256 -max_common_paths 1
