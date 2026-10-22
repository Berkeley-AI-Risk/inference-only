# =============================================================================
# Amazon FPGA Hardware Development Kit
#
# Copyright 2024 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Amazon Software License (the "License"). You may not use
# this file except in compliance with the License. A copy of the License is
# located at
#
#    http://aws.amazon.com/asl/
#
# or in the "license" file accompanying this file. This file is distributed on
# an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, express or
# implied. See the License for the specific language governing permissions and
# limitations under the License.
# =============================================================================


# Common CL Implementation Tcl Script


# AWS shell DCP location
set AWS_DCP_DIR "${HDK_SHELL_DIR}/build/checkpoints/from_aws/"


###############################################################################
print "Start linking customer design ${CL}"
###############################################################################
add_files ${AWS_DCP_DIR}/cl_bb_routed.${SHELL_MODE}.dcp
add_files ${checkpoints_dir}/${CL}.${TAG}.post_synth.dcp

set_property SCOPED_TO_CELLS {WRAPPER/CL} \
             [get_files ${checkpoints_dir}/${CL}.${TAG}.post_synth.dcp]

link_design -mode default \
            -reconfig_partitions {WRAPPER/CL} \
            -top top

print "Writing post-link design checkpoint"
write_checkpoint -force ${checkpoints_dir}/${CL}.${TAG}.post_link.dcp

#######################################
#
# MMCM Clock recipe constraints
#
#######################################
source $HDK_SHELL_DIR/build/scripts/aws_clock_properties.tcl

# Qwen adaptation: re-resolve exact CDC endpoints in the linked hierarchy.
source ${CL_DIR}/build/scripts/qwen_cdc_constraints.tcl
qwen_apply_cdc_constraints

#######################################
# Floorplan Constraints
#######################################
# Dynamic region floorplan (CL)
read_xdc ${HDK_SHELL_DIR}/build/constraints/${SHELL_MODE}_level_1_fp_cl.xdc

# User defined floorplan (use SLR0/SLR1/SLR2 from main floorplan)
read_xdc ${constraints_dir}/${SHELL_MODE}_cl_pnr_user.xdc

# Optional, MIG placement training
source ${HDK_SHELL_DIR}/build/scripts/ddr_io_train.tcl

# # MMCM cascade placement constraint
# read_xdc ${HDK_SHELL_DESIGN_DIR}/../build/constraints/mmcm_cascade.xdc

###############################################################################
print "Start optimizing customer design ${CL}"
###############################################################################
opt_design

# Work Around 2025.1 HBM DONT TOUCH issue
# https://adaptivesupport.amd.com/s/article/000038502?language=en_US&t=1754923887312
if {[llength [get_cells -quiet WRAPPER/CL/HBM/HBM_CORE_I/inst]] > 0} {
    puts "INFO: HBM found, setting DONT_TOUCH to 0"
    set_property DONT_TOUCH 0 [get_cells WRAPPER/CL/HBM/HBM_CORE_I/inst]
}

print "Writing post-opt design checkpoint and report"
write_checkpoint -force ${checkpoints_dir}/${CL}.${TAG}.post_opt.dcp

report_timing -delay_type max \
              -path_type full_clock_expanded \
              -max_paths 10 \
              -nworst 1 \
              -input_pins \
              -slice_pins \
              -sort_by group \
              -significant_digits 3 \
              -file ${reports_dir}/${CL}.${TAG}.post_opt_timing.rpt


###############################################################################

# Exact existing reset-release policy, collected again on this new netlist.
set helpers [file dirname [info script]]
set output [file join [file dirname $CL_DIR] output]
if {[file exists $output]} {error "Placement output already exists"}
file mkdir $output
source $helpers/parallel_core_reset_contract.tcl
foreach {name period} {clk_out2_clk_mmcm_c 10.0 clk_out1_clk_mmcm_hbm 8.0 clk_main_a0 4.0} {
    set clock [pcr_one [get_clocks -quiet $name] "actual clock $name"]
    if {[get_property PERIOD $clock] != $period} {error "Wrong actual clock $name"}
}
set payload_cells {}
foreach cell [get_cells -quiet -hier -filter {REF_NAME =~ URAM288*}] {
    set name [get_property NAME $cell]
    if {[regexp {^WRAPPER/CL/.*/workers\[([0-3])\]\.verifier/banks\[([0-3])\]\.payload_ram/memory_reg_uram_([0-7])$} $name]} {
        lappend payload_cells $name
    }
}
if {[llength [lsort -unique $payload_cells]] != 128} {error "Incomplete private payload UltraRAM mapping"}
set stream [open $output/payload-uram-cells.txt {WRONLY CREAT EXCL}]
puts $stream [join [lsort $payload_cells] "\n"];close $stream
puts "PAYLOAD_FULL_MAPPING_PASSED blocks=128"

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

# Informational full-netlist mapping: inspect survivors, do not infer timing.
set stream [open $output/projection-av-stage-cells.tsv {WRONLY CREAT EXCL}]
puts $stream "cell\tprimitive\tkind"
set observed 0
foreach cell [get_cells -quiet -hier -filter {REF_NAME =~ FD* || REF_NAME =~ RAMB*}] {
    set name [get_property NAME $cell]
    set kind ""
    if {[regexp {activation_banks\[[0-7]\]\.(even_codes|odd_codes)_reg} $name]} {set kind projection_parity_ram}
    if {[regexp {(^|[/.])(probability_rec_q|value_rec_q)_reg} $name]} {set kind av_recoded_operand}
    if {$kind ne ""} {
        puts $stream [join [list $name [get_property REF_NAME $cell] $kind] "\t"]
        incr observed
    }
}
close $stream
puts "PROJECTION_AV_STAGE_MAPPING_OBSERVED cells=$observed timing_qualified=0"
report_utilization -file $output/post-opt-utilization.rpt
set contract [pcr_collect $helpers/parallel-reset-chains.tsv $helpers/reset_chain_045_lib.tcl $output WRAPPER/CL/]
pcr_apply $contract
report_exceptions -coverage -file $output/pre-place-exceptions.rpt
write_checkpoint $output/payload.reset-contract.post_opt.dcp
place_design -directive SSI_SpreadLogic_high -no_bufg_opt
write_checkpoint $output/payload.reset-contract.post_place.dcp
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -max_paths 20 -file $output/post-place-timing.rpt
phys_opt_design -directive Default
write_checkpoint $output/payload.reset-contract.post_phys_opt.dcp
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -max_paths 20 -file $output/post-phys-opt-timing.rpt
report_exceptions -coverage -file $output/exceptions.rpt
report_utilization -file $output/utilization.rpt
report_clocks -file $output/clocks.rpt
pcr_retained_timing $contract $output 0
close_design
puts "PAYLOAD_PLACEMENT_FINISHED recipe=C2/H1 routing_attempted=0 timing_qualified=0 fpga_programmed=0"
