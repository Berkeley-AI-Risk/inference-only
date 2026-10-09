open_project [file join [pwd] project product.gprj]
set_option -verilog_std sysv2017
set_option -top_module board1_fixed_shared_product_top
set_option -use_cpu_as_gpio 1
set_option -use_mspi_as_gpio 1
set_option -convert_sdp32_36_to_sdp16_18 0
set_option -output_base_name shared_product
set_option -gen_text_timing_rpt 1
if {[catch {run syn} result options]} {puts stderr $result; exit 1}
puts "LOCAL_KV_SYN_COMPLETE hardware_access=0"
flush stdout
set_option -place_option 4
set_option -route_option 0
set_option -clock_route_order 0
set_option -route_maxfan 23
set_option -replicate_resources 0
set_option -correct_hold_violation 1
set_option -gen_verilog_sim_netlist 1
set_option -gen_sdf 1
if {[catch {run pnr} result options]} {puts stderr $result; exit 1}
puts "LOCAL_KV_NATIVE_COMPLETE hardware_access=0"
flush stdout
run close
exit 0
