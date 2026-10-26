create_clock -name board50 -period 20.000 [get_ports {clk_50mhz}]
# No false-path or multicycle exceptions. UART RX is sampled by its existing
# two-flop synchronizer; SPI MISO has 500ns settling time before each sample.
# Board electrical timing still requires independent review/physical testing.
