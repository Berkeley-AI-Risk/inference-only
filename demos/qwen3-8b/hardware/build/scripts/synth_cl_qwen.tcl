# Candidate supported-HDK synthesis entry, not a qualified implementation.
source ${HDK_SHELL_DIR}/build/scripts/synth_cl_header.tcl
source ${CL_DIR}/build/scripts/qwen_sources.tcl
set_property include_dirs [list $src_post_enc_dir ${HDK_SHELL_DESIGN_DIR}/interfaces] [current_fileset]
foreach name $qwen_sv_sources {read_verilog -sv [file join $src_post_enc_dir $name]}
foreach name $qwen_v_sources {read_verilog [file join $src_post_enc_dir $name]}
foreach name {silu-bf16.hex softmax-exp2.hex model-page-roots-bank-0.hex model-page-roots-bank-1.hex model-page-roots-bank-2.hex model-page-roots-bank-3.hex model-page-roots-bank-4.hex model-page-roots-bank-5.hex model-page-roots-bank-6.hex model-page-roots-bank-7.hex model-page-roots-bank-8.hex model-page-roots-bank-9.hex model-page-roots-bank-10.hex model-page-roots-bank-11.hex model-page-roots-bank-12.hex model-page-roots-bank-13.hex model-page-roots-bank-14.hex model-page-roots-bank-15.hex model-page-roots-bank-16.hex model-page-roots-bank-17.hex model-page-roots-bank-18.hex model-page-roots-bank-19.hex model-page-roots-bank-20.hex model-page-roots-bank-21.hex model-page-roots-bank-22.hex model-page-roots-bank-23.hex model-page-roots-bank-24.hex model-page-roots-bank-25.hex model-page-roots-bank-26.hex model-page-roots-bank-27.hex model-page-roots-bank-28.hex model-page-roots-bank-29.hex model-page-roots-bank-30.hex model-page-roots-bank-31.hex model-page-roots-bank-32.hex} {
    add_files -norecurse [file join $scripts_dir $name]
}
# Minimal active IP plus the DDR dependencies of the mandatory disabled SH_DDR.
# No software clock crossbar, debug bridge, ILA, host DMA or generic accelerator.
foreach name {cl_ddr4_32g cl_ddr4_32g_ap cl_ddr4 cl_ddr4_64g_ap cl_hbm
              clk_mmcm_a clk_mmcm_b clk_mmcm_c clk_mmcm_hbm cl_clk_axil_xbar
              cl_axi_register_slice_light cl_axi_clock_converter_light} {
    read_ip [file join $HDK_IP_SRC_DIR $name ${name}.xci]
}
update_compile_order -fileset sources_1
# Preserve FIFO hierarchy for explicit endpoint matching in the first build.
# Any later flattening change must rerun the constraint coverage checks.
synth_design -mode out_of_context -top ${CL} -part ${DEVICE_TYPE} \
    -verilog_define XSDB_SLV_DIS -keep_equivalent_registers -flatten_hierarchy none
# Preserve synthesis if a subsequent constraint/report check fails. This raw
# checkpoint is not the post_synth input accepted by the implementation flow.
write_checkpoint -force ${checkpoints_dir}/${CL}.${TAG}.pre_custom_constraints.dcp
source ${CL_DIR}/build/scripts/qwen_cdc_constraints.tcl
qwen_apply_cdc_constraints
report_utilization -hierarchical -file ${reports_dir}/${CL}.${TAG}.qwen_utilization.rpt
report_cdc -details -file ${reports_dir}/${CL}.${TAG}.qwen_cdc.rpt
report_clock_interaction -file ${reports_dir}/${CL}.${TAG}.qwen_clock_interaction.rpt
report_exceptions -coverage -file ${reports_dir}/${CL}.${TAG}.qwen_exceptions.rpt
report_methodology -file ${reports_dir}/${CL}.${TAG}.qwen_methodology.rpt
source ${HDK_SHELL_DIR}/build/scripts/synth_cl_footer.tcl
