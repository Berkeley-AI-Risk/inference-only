set here [file dirname [file normalize [info script]]]
open_project [file join $here readonly_flash_reader.gprj]
set_option -verilog_std sysv2017
set_option -top_module readonly_flash_reader
set_option -use_mspi_as_gpio 1
set_option -use_cpu_as_gpio 1
set_option -output_base_name readonly_flash_reader
set_option -gen_text_timing_rpt 1
run syn
run pnr
run close
