open_project product.gprj
set_option -verilog_std sysv2017
set_option -top_module tlm26_tang_top
set_option -use_cpu_as_gpio 1
set_option -use_mspi_as_gpio 0
set_option -convert_sdp32_36_to_sdp16_18 0
set_option -output_base_name tlm26
set_option -correct_hold_violation 1
if {[catch {run syn} result]} {puts stderr $result; exit 1}
if {[catch {run pnr} result]} {puts stderr $result; exit 1}
run close
exit 0
