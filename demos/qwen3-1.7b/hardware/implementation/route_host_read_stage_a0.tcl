# Route the new A0 placement with the previously completed internal-parameter policy.
# No new timing exceptions, RTL/clock changes, image creation or device load.
if {$argc != 3} {error "Expected completed post-phys-opt checkpoint, SHA-256 and fresh output"}
lassign $argv input digest output
proc input_sha {path} {return [lindex [exec sha256sum $path] 0]}
if {[version -short] ne "2025.2" || ![regexp {^[0-9a-f]{64}$} $digest] ||
    [input_sha $input] ne $digest || [file exists $output]} {error "Wrong diagnostic input"}
file mkdir $output
set_param general.maxThreads 8
if {[get_param general.maxThreads] != 8} {error "Thread limit was not applied"}
open_checkpoint $input
if {[get_property PART [current_design]] ne "xcvu47p-fsvh2892-2-e"} {error "Wrong device"}
foreach {name period} {clk_out1_clk_mmcm_a 16.0 clk_out1_clk_mmcm_hbm 8.0 clk_main_a0 4.0} {
    set clock [get_clocks -quiet $name]
    if {[llength $clock] != 1 || [get_property PERIOD $clock] != $period} {error "Wrong clock $name"}
}

# Verify this particular fix survived full-design synthesis/optimization.
set ingress_banks {}
foreach cell [get_cells -quiet -hier -filter {REF_NAME =~ RAMB*}] {
    set name [get_property NAME $cell]
    if {[regexp {^WRAPPER/CL/fixed_machine/machine/startup/ingress/blocks_reg_([0-7])$} $name -> bank]} {
        if {[dict exists $ingress_banks $bank]} {error "Duplicate startup BRAM bank"}
        dict set ingress_banks $bank $cell
    }
}
if {[lsort -integer [dict keys $ingress_banks]] ne {0 1 2 3 4 5 6 7}} {error "Incomplete startup BRAM mapping"}
set stream [open $output/startup-block-ram-properties.tsv {WRONLY CREAT EXCL}]
puts $stream "cell\tprimitive\tDOA_REG\tDOB_REG\tREAD_WIDTH_A\tREAD_WIDTH_B\tWRITE_WIDTH_A\tWRITE_WIDTH_B"
foreach bank {0 1 2 3 4 5 6 7} {
    set cell [dict get $ingress_banks $bank]
    set primitive [get_property REF_NAME $cell]
    set width [expr {$bank == 7 ? 36 : 72}]
    set dob [expr {$bank == 7 ? 0 : 1}]
    set expected [expr {$bank == 7 ? "RAMB18E2" : "RAMB36E2"}]
    if {$primitive ne $expected || [get_property DOA_REG $cell] != 1 ||
        [get_property DOB_REG $cell] != $dob || [get_property READ_WIDTH_A $cell] != $width ||
        [get_property READ_WIDTH_B $cell] != 0 || [get_property WRITE_WIDTH_A $cell] != 0 ||
        [get_property WRITE_WIDTH_B $cell] != $width} {error "Startup BRAM geometry/output register changed: $cell"}
    set row [list [get_property NAME $cell] $primitive]
    foreach property {DOA_REG DOB_REG READ_WIDTH_A READ_WIDTH_B WRITE_WIDTH_A WRITE_WIDTH_B} {
        lappend row [get_property $property $cell]
    }
    puts $stream [join $row "\t"]
}
close $stream
puts "HOST_READ_STAGE_FULL_MAPPING_PASSED banks=8"

report_exceptions -coverage -file $output/input-exceptions.rpt
if {[get_param route.optimizeLeafClkProgDlys] != 1} {error "Unexpected leaf optimization default"}
if {[get_param route.disableLeafClockModeling] != 0} {error "Clock modeling is disabled"}
set_param route.optimizeLeafClkProgDlys false
if {[get_param route.optimizeLeafClkProgDlys] != 0 || [get_param route.disableLeafClockModeling] != 0} {
    error "Leaf diagnostic parameter or clock modeling mismatch"
}
puts "LEAF_CLOCK_PROBE_PARAMETER route.optimizeLeafClkProgDlys=0 clock_modeling_disabled=0"
puts "HOST_READ_STAGE_A0_ROUTE_BEGIN threads=8 timing_driven=1 timing_exceptions_added=0"
route_design -directive AggressiveExplore -tns_cleanup
write_checkpoint $output/host-read-stage-a0.post_route.dcp
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -max_paths 20 -file $output/timing-summary.rpt
report_route_status -file $output/route-status.rpt
report_drc -file $output/drc.rpt
report_cdc -details -file $output/cdc.rpt
report_bus_skew -file $output/bus-skew.rpt
report_clock_interaction -file $output/clock-interaction.rpt
report_exceptions -coverage -file $output/exceptions.rpt
report_clocks -file $output/clocks.rpt
close_design
if {[input_sha $input] ne $digest} {error "Source checkpoint changed"}
puts "HOST_READ_STAGE_A0_ROUTE_FINISHED source=$digest timing_qualified=0 fpga_programmed=0"
