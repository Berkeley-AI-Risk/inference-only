`timescale 1ns/1ps
`default_nettype none

// Private composition, not a host interface. The pinned whole-image boot
// checker owns DDR until its fixed SHA-256 readback succeeds and all accepted
// reads drain. The one-way handoff then selects a separate 32-read runtime
// adapter; the old serial boot adapter is never in the streaming data path.
// All external inputs here terminate inside the eventual package wrapper.
module tang_confidential_booted_shared_ddr (
    input wire trusted_clk_i,trusted_reset_n_i,app_clk_i,app_reset_n_i,
    input wire private_fixed_source_ready_i,private_boot_progress_i,
    input wire private_loader_done_i,private_loader_valid_i,
    input wire [255:0] private_loader_data_i,
    output wire private_loader_ready_o,
    input wire private_source_fault_i,private_runtime_app_fault_i,
    input wire private_req_valid_i,private_req_write_i,
    input wire [18:0] private_req_word_i,
    input wire [255:0] private_req_data_i,
    output wire private_req_ready_o,private_rsp_valid_o,private_rsp_error_o,
    output wire [255:0] private_rsp_data_o,
    output wire private_model_locked_o,private_fail_closed_o,
    input wire controller_pll_lock_i,controller_init_calib_complete_i,
    input wire app_cmd_ready_i,app_wr_data_ready_i,
    output wire [2:0] app_cmd_o,
    output wire app_cmd_en_o,
    output wire [28:0] app_addr_o,
    output wire [255:0] app_wr_data_o,
    output wire app_wr_data_en_o,app_wr_data_end_o,
    output wire [31:0] app_wr_data_mask_o,
    input wire [255:0] app_rd_data_i,
    input wire app_rd_data_valid_i,app_rd_data_end_i,
    output wire app_burst_o,app_self_refresh_req_o,app_refresh_req_o
);
    wire common_async_reset_n=trusted_reset_n_i && app_reset_n_i;
    (* async_reg="true",syn_preserve=1 *) logic [2:0] app_release_q;
    always_ff @(posedge app_clk_i or negedge common_async_reset_n) begin
        if(!common_async_reset_n) app_release_q<=0;
        else app_release_q<={app_release_q[1:0],1'b1};
    end
    // Matches the boot composition's own app release, avoiding a startup
    // false fault from its intentionally closed output during hard reset.
    wire app_domain_reset_n=app_release_q[2];
    logic fault_q;
    wire boot_locked,boot_fault,boot_watchdog,handoff_locked,handoff_fault;
    wire runtime_adapter_fault,runtime_adapter_error,runtime_adapter_ready;
    wire runtime_req_ready,runtime_rsp_error;
    wire [2:0] boot_cmd,runtime_cmd;
    wire boot_cmd_en,runtime_cmd_en,boot_cmd_ready,runtime_cmd_ready;
    wire [28:0] boot_addr,runtime_addr;
    wire [255:0] boot_data,runtime_data;
    wire boot_data_en,runtime_data_en,boot_data_end,runtime_data_end;
    wire boot_data_ready,runtime_data_ready,boot_read_valid,runtime_read_valid;
    wire [31:0] boot_mask,runtime_mask;
    wire [255:0] selected_read_data;
    wire selected_read_end;
    wire boot_burst,boot_self_refresh,boot_refresh;
    wire runtime_burst,runtime_self_refresh,runtime_refresh;
    wire controller_good=controller_pll_lock_i && controller_init_calib_complete_i;
    wire unexpected_control=boot_burst || boot_self_refresh || boot_refresh ||
        runtime_burst || runtime_self_refresh || runtime_refresh;
    always_ff @(posedge app_clk_i or negedge app_domain_reset_n) begin
        if(!app_domain_reset_n) fault_q<=0;
        else if(private_source_fault_i || private_runtime_app_fault_i || boot_fault ||
                handoff_fault || runtime_adapter_fault || unexpected_control) fault_q<=1;
    end
    assign private_fail_closed_o=fault_q || handoff_fault;
    assign private_model_locked_o=handoff_locked && !fault_q;
    assign private_req_ready_o=runtime_req_ready && private_model_locked_o;
    assign private_rsp_error_o=runtime_rsp_error ||
        (private_rsp_valid_o && private_fail_closed_o);
    // The selected adapters never request manual refresh or a special burst;
    // the actual controller remains responsible for its normal auto-refresh.
    assign app_burst_o=1'b0;
    assign app_self_refresh_req_o=1'b0;
    assign app_refresh_req_o=1'b0;

    board1_context2048_ddr_locked_auth_watchdog_cdc_quarantined_payload u_boot (
        .trusted_clk_i(trusted_clk_i),.trusted_reset_n_i(trusted_reset_n_i),
        .app_clk_i(app_clk_i),.app_reset_n_i(app_reset_n_i),
        .private_fixed_source_ready_i(private_fixed_source_ready_i),
        .private_boot_progress_i(private_boot_progress_i),
        .private_loader_done_i(private_loader_done_i),.private_loader_data_i(private_loader_data_i),
        .private_loader_valid_i(private_loader_valid_i),.private_loader_ready_o(private_loader_ready_o),
        .private_runtime_req_valid_i(1'b0),.private_runtime_req_ready_o(),
        .private_runtime_req_word_address_i(19'd0),.private_runtime_req_write_i(1'b0),
        .private_runtime_req_write_data_i(256'd0),.private_runtime_rsp_data_o(),
        .private_runtime_rsp_valid_o(),.private_runtime_rsp_ready_i(1'b1),.private_runtime_rsp_error_o(),
        .private_runtime_endpoint_fail_closed_i(fault_q),
        .controller_pll_lock_i(controller_pll_lock_i),
        .controller_init_calib_complete_i(controller_init_calib_complete_i),
        .app_cmd_ready_i(boot_cmd_ready),.app_cmd_o(boot_cmd),.app_cmd_en_o(boot_cmd_en),.app_addr_o(boot_addr),
        .app_wr_data_ready_i(boot_data_ready),.app_wr_data_o(boot_data),.app_wr_data_en_o(boot_data_en),
        .app_wr_data_end_o(boot_data_end),.app_wr_data_mask_o(boot_mask),
        .app_rd_data_i(selected_read_data),.app_rd_data_valid_i(boot_read_valid),.app_rd_data_end_i(selected_read_end),
        .app_burst_o(boot_burst),.app_self_refresh_req_o(boot_self_refresh),.app_refresh_req_o(boot_refresh),
        .model_locked_o(boot_locked),.fail_closed_o(boot_fault),.watchdog_fault_o(boot_watchdog));

    board1_gowin_ddr3_app_adapter #(.ADDR_W(19),.MAX_OUTSTANDING_READS(32)) u_runtime_adapter (
        .clk(app_clk_i),.reset_n(app_domain_reset_n),
        .phy_req_valid_i(private_req_valid_i && private_model_locked_o),.phy_req_ready_o(runtime_req_ready),
        .phy_req_write_i(private_req_write_i),.phy_req_word_addr_i(private_req_word_i),.phy_req_wdata_i(private_req_data_i),
        .phy_rsp_valid_o(private_rsp_valid_o),.phy_rsp_data_o(private_rsp_data_o),.phy_rsp_error_o(runtime_rsp_error),
        .controller_pll_lock_i(controller_pll_lock_i),.controller_init_calib_complete_i(controller_init_calib_complete_i),
        .calib_done_o(runtime_adapter_ready),.calib_error_o(runtime_adapter_error),.protocol_fault_o(runtime_adapter_fault),
        .app_cmd_ready_i(runtime_cmd_ready),.app_cmd_o(runtime_cmd),.app_cmd_en_o(runtime_cmd_en),.app_addr_o(runtime_addr),
        .app_wr_data_ready_i(runtime_data_ready),.app_wr_data_o(runtime_data),.app_wr_data_en_o(runtime_data_en),
        .app_wr_data_end_o(runtime_data_end),.app_wr_data_mask_o(runtime_mask),
        .app_rd_data_i(selected_read_data),.app_rd_data_valid_i(runtime_read_valid),.app_rd_data_end_i(selected_read_end),
        .app_burst_o(runtime_burst),.app_self_refresh_req_o(runtime_self_refresh),.app_refresh_req_o(runtime_refresh));

    board1_private_ddr_boot_handoff u_handoff (
        .clk(app_clk_i),.reset_n(app_domain_reset_n),.controller_good_i(controller_good),
        .boot_locked_i(boot_locked),.boot_fault_i(boot_fault || private_source_fault_i || unexpected_control),
        .runtime_fault_i(fault_q || runtime_adapter_fault || private_runtime_app_fault_i),
        .boot_cmd_i(boot_cmd),.runtime_cmd_i(runtime_cmd),.boot_cmd_en_i(boot_cmd_en),.runtime_cmd_en_i(runtime_cmd_en),
        .boot_addr_i(boot_addr),.runtime_addr_i(runtime_addr),.boot_data_i(boot_data),.runtime_data_i(runtime_data),
        .boot_data_en_i(boot_data_en),.runtime_data_en_i(runtime_data_en),.boot_data_end_i(boot_data_end),
        .runtime_data_end_i(runtime_data_end),.boot_mask_i(boot_mask),.runtime_mask_i(runtime_mask),
        .boot_cmd_ready_o(boot_cmd_ready),.runtime_cmd_ready_o(runtime_cmd_ready),
        .boot_data_ready_o(boot_data_ready),.runtime_data_ready_o(runtime_data_ready),
        .boot_read_valid_o(boot_read_valid),.runtime_read_valid_o(runtime_read_valid),
        .read_data_o(selected_read_data),.read_end_o(selected_read_end),
        .app_cmd_ready_i(app_cmd_ready_i),.app_data_ready_i(app_wr_data_ready_i),
        .app_cmd_o(app_cmd_o),.app_cmd_en_o(app_cmd_en_o),.app_addr_o(app_addr_o),.app_data_o(app_wr_data_o),
        .app_data_en_o(app_wr_data_en_o),.app_data_end_o(app_wr_data_end_o),.app_mask_o(app_wr_data_mask_o),
        .app_read_valid_i(app_rd_data_valid_i),.app_read_end_i(app_rd_data_end_i),.app_read_data_i(app_rd_data_i),
        .runtime_locked_o(handoff_locked),.fault_o(handoff_fault));

    wire _unused_status=boot_watchdog || runtime_adapter_ready || runtime_adapter_error;
endmodule
`default_nettype wire
