`timescale 1ns/1ps
`default_nettype none

// Product4 application-clock boundary. The authenticated boot owner and the
// sealed typed runtime owner share one normalized request FIFO and the fixed
// official Gowin DDR adapter. The 19-bit endpoint remains entirely private.
// Product4 exports the frozen adapter's already-combinational response fault
// so the enclosing composition can suppress a concurrent physical request on
// the exact malformed/unexpected-response edge.
module board1_context2048_ddr_preboard_locked_boundary (
    input  wire         app_clk_i,
    input  wire         app_reset_n_i,
    input  wire         private_upstream_fault_i,
    input  wire         private_fixed_source_done_i,
    input  wire         private_fixed_source_ok_i,
    input  wire [255:0] private_loader_data_i,
    input  wire         private_loader_valid_i,
    output wire         private_loader_ready_o,
    output wire [255:0] private_readback_word_data_o,
    output wire         private_readback_word_valid_o,
    output wire         private_readback_word_last_o,
    input  wire         private_readback_word_ready_i,
    input  wire         private_readback_digest_done_i,
    input  wire         private_readback_digest_ok_i,

    input  wire         private_runtime_req_valid_i,
    output wire         private_runtime_req_ready_o,
    input  wire [18:0]  private_runtime_req_word_address_i,
    input  wire         private_runtime_req_write_i,
    input  wire [255:0] private_runtime_req_write_data_i,
    output wire [255:0] private_runtime_rsp_data_o,
    output wire         private_runtime_rsp_valid_o,
    input  wire         private_runtime_rsp_ready_i,
    output wire         private_runtime_rsp_error_o,

    input  wire         controller_pll_lock_i,
    input  wire         controller_init_calib_complete_i,
    input  wire         app_cmd_ready_i,
    output wire [2:0]   app_cmd_o,
    output wire         app_cmd_en_o,
    output wire [28:0]  app_addr_o,
    input  wire         app_wr_data_ready_i,
    output wire [255:0] app_wr_data_o,
    output wire         app_wr_data_en_o,
    output wire         app_wr_data_end_o,
    output wire [31:0]  app_wr_data_mask_o,
    input  wire [255:0] app_rd_data_i,
    input  wire         app_rd_data_valid_i,
    input  wire         app_rd_data_end_i,
    output wire         app_burst_o,
    output wire         app_self_refresh_req_o,
    output wire         app_refresh_req_o,
    output wire         model_locked_o,
    output wire         fail_closed_o,
    output wire         raw_response_protocol_fault_now_o
);
    wire bridge_req_valid;
    wire bridge_req_ready;
    wire bridge_req_write;
    wire [18:0] bridge_req_addr;
    wire [255:0] bridge_req_data;
    wire adapter_req_valid;
    wire adapter_req_ready;
    wire adapter_req_write;
    wire [18:0] adapter_req_addr;
    wire [255:0] adapter_req_data;
    wire phy_rsp_valid;
    wire [255:0] phy_rsp_data;
    wire phy_rsp_error;
    wire calib_done;
    wire calib_error;
    wire adapter_protocol_fault;
    wire adapter_app_cmd_en;
    wire adapter_app_wr_data_en;
    wire adapter_app_wr_data_end;
    wire adapter_app_burst;
    wire adapter_app_self_refresh_req;
    wire adapter_app_refresh_req;
    // In the frozen adapter phy_rsp_error is the exact current response fault:
    // valid with bad end, no outstanding read, a bad controller, or a prior
    // sticky adapter fault. Keep this current-cycle predicate at the final
    // physical action points, not in the FIFO's input-ready/loader contract
    // cone. Its registered adapter fault aborts the FIFO on the next edge.
    wire adapter_response_protocol_fault_now = phy_rsp_error;
    wire bridge_fail_closed;
    logic boundary_fault_q;
    // In Product4 this input is the registered app-domain aggregate.  Use it
    // combinationally only to suppress/abort the lower private seam; the
    // sticky copy remains the sole sequential terminal state owned here.
    wire upstream_fault_now =
        private_upstream_fault_i === 1'b1;

`ifndef SYNTHESIS
    always_ff @(posedge app_clk_i or negedge app_reset_n_i) begin
        if (!app_reset_n_i)
            boundary_fault_q <= 1'b0;
        else if ($isunknown(private_upstream_fault_i) ||
                 (private_upstream_fault_i === 1'b1) ||
                 $isunknown(private_fixed_source_done_i) ||
                 $isunknown(private_fixed_source_ok_i) ||
                 $isunknown(private_loader_valid_i) ||
                 $isunknown(private_readback_word_ready_i) ||
                 $isunknown(private_readback_digest_done_i) ||
                 $isunknown(private_readback_digest_ok_i) ||
                 $isunknown(private_runtime_req_valid_i) ||
                 $isunknown(private_runtime_rsp_ready_i) ||
                 ((private_loader_valid_i === 1'b1) &&
                  $isunknown(private_loader_data_i)) ||
                 ((private_runtime_req_valid_i === 1'b1) &&
                  ($isunknown(private_runtime_req_word_address_i) ||
                   $isunknown(private_runtime_req_write_i) ||
                   ((private_runtime_req_write_i === 1'b1) &&
                    $isunknown(private_runtime_req_write_data_i)))))
            boundary_fault_q <= 1'b1;
    end
`else
    always_ff @(posedge app_clk_i or negedge app_reset_n_i) begin
        if (!app_reset_n_i)
            boundary_fault_q <= 1'b0;
        else if (private_upstream_fault_i === 1'b1)
            boundary_fault_q <= 1'b1;
    end
`endif

    board1_context2048_private_ddr_lock_bridge #(
        .ADDR_W(19), .MODEL_BASE_WORD(0), .MODEL_WORDS(227062),
        .SCRATCH_BASE_WORD(227072), .SCRATCH_WORDS(221184)
    ) u_fixed_boot_lock (
        .clk(app_clk_i), .reset_n(app_reset_n_i),
        .calib_done(calib_done),
        .calib_error(calib_error || boundary_fault_q ||
                     upstream_fault_now),
        .fixed_source_done(private_fixed_source_done_i),
        .fixed_source_ok(private_fixed_source_ok_i),
        .loader_data(private_loader_data_i),
        .loader_valid(private_loader_valid_i),
        .loader_ready(private_loader_ready_o),
        .readback_word_data(private_readback_word_data_o),
        .readback_word_valid(private_readback_word_valid_o),
        .readback_word_last(private_readback_word_last_o),
        .readback_word_ready(private_readback_word_ready_i),
        .readback_digest_done(private_readback_digest_done_i),
        .readback_digest_ok(private_readback_digest_ok_i),
        .runtime_req_valid(private_runtime_req_valid_i),
        .runtime_req_ready(private_runtime_req_ready_o),
        .runtime_req_word_address(private_runtime_req_word_address_i),
        .runtime_req_write(private_runtime_req_write_i),
        .runtime_req_write_data(private_runtime_req_write_data_i),
        .runtime_rsp_data(private_runtime_rsp_data_o),
        .runtime_rsp_valid(private_runtime_rsp_valid_o),
        .runtime_rsp_ready(private_runtime_rsp_ready_i),
        .runtime_rsp_error(private_runtime_rsp_error_o),
        .phy_req_valid(bridge_req_valid),
        .phy_req_ready(bridge_req_ready),
        .phy_req_write(bridge_req_write),
        .phy_req_word_addr(bridge_req_addr),
        .phy_req_wdata(bridge_req_data),
        .phy_rsp_valid(phy_rsp_valid), .phy_rsp_data(phy_rsp_data),
        .phy_rsp_error(phy_rsp_error),
        .model_locked(model_locked_o), .fail_closed(bridge_fail_closed)
    );

    board1_ddr_request_fifo2 #(.ADDR_W(19)) u_request_fifo (
        .clk(app_clk_i), .reset_n(app_reset_n_i),
        .abort_i(upstream_fault_now || boundary_fault_q ||
                 bridge_fail_closed || adapter_protocol_fault),
        .in_valid_i(bridge_req_valid), .in_ready_o(bridge_req_ready),
        .in_write_i(bridge_req_write), .in_addr_i(bridge_req_addr),
        .in_data_i(bridge_req_data), .out_valid_o(adapter_req_valid),
        .out_ready_i(adapter_req_ready), .out_write_o(adapter_req_write),
        .out_addr_o(adapter_req_addr), .out_data_o(adapter_req_data)
    );

    board1_gowin_ddr3_app_adapter #(
        .ADDR_W(19), .MAX_OUTSTANDING_READS(1)
    ) u_official_app_adapter (
        .clk(app_clk_i), .reset_n(app_reset_n_i),
        .phy_req_valid_i(adapter_req_valid),
        .phy_req_ready_o(adapter_req_ready),
        .phy_req_write_i(adapter_req_write),
        .phy_req_word_addr_i(adapter_req_addr),
        .phy_req_wdata_i(adapter_req_data),
        .phy_rsp_valid_o(phy_rsp_valid), .phy_rsp_data_o(phy_rsp_data),
        .phy_rsp_error_o(phy_rsp_error),
        .controller_pll_lock_i(controller_pll_lock_i),
        .controller_init_calib_complete_i(
            controller_init_calib_complete_i),
        .calib_done_o(calib_done), .calib_error_o(calib_error),
        .protocol_fault_o(adapter_protocol_fault),
        .app_cmd_ready_i(app_cmd_ready_i), .app_cmd_o(app_cmd_o),
        .app_cmd_en_o(adapter_app_cmd_en), .app_addr_o(app_addr_o),
        .app_wr_data_ready_i(app_wr_data_ready_i),
        .app_wr_data_o(app_wr_data_o),
        .app_wr_data_en_o(adapter_app_wr_data_en),
        .app_wr_data_end_o(adapter_app_wr_data_end),
        .app_wr_data_mask_o(app_wr_data_mask_o),
        .app_rd_data_i(app_rd_data_i),
        .app_rd_data_valid_i(app_rd_data_valid_i),
        .app_rd_data_end_i(app_rd_data_end_i),
        .app_burst_o(adapter_app_burst),
        .app_self_refresh_req_o(adapter_app_self_refresh_req),
        .app_refresh_req_o(adapter_app_refresh_req)
    );

    // On a malformed/controller-bad response edge, a private descriptor may
    // be accepted into (or popped from) the doomed FIFO, but no command/data
    // may reach DDR. The adapter captures its terminal protocol fault at that
    // edge; the next cycle aborts the FIFO and poisons/drains owned responses.
    // This is not a deferred physical fault gate or a retry of dropped work.
    assign app_cmd_en_o = adapter_app_cmd_en &&
                          !adapter_response_protocol_fault_now;
    assign app_wr_data_en_o = adapter_app_wr_data_en &&
                              !adapter_response_protocol_fault_now;
    assign app_wr_data_end_o = adapter_app_wr_data_end &&
                               !adapter_response_protocol_fault_now;
    assign app_burst_o = adapter_app_burst &&
                         !adapter_response_protocol_fault_now;
    assign app_self_refresh_req_o = adapter_app_self_refresh_req &&
                                    !adapter_response_protocol_fault_now;
    assign app_refresh_req_o = adapter_app_refresh_req &&
                               !adapter_response_protocol_fault_now;

    assign fail_closed_o = upstream_fault_now || bridge_fail_closed ||
                           adapter_protocol_fault || boundary_fault_q ||
                           adapter_response_protocol_fault_now;
    assign raw_response_protocol_fault_now_o =
        adapter_response_protocol_fault_now;

`ifdef FORMAL
    always_ff @(posedge app_clk_i) begin
        if (app_reset_n_i && app_wr_data_en_o) begin
            assert (app_cmd_en_o && app_cmd_o == 3'b000);
            assert (app_addr_o[2:0] == 3'b000);
            if (model_locked_o)
                assert (app_addr_o >= 29'h01bb800 &&
                        app_addr_o < 29'h036b800);
            else
                assert (app_addr_o < 29'h01bb7b0);
        end
        if (app_reset_n_i && adapter_response_protocol_fault_now) begin
            assert (!app_cmd_en_o);
            assert (!app_wr_data_en_o);
            assert (!app_wr_data_end_o);
        end
    end
`endif
endmodule

`default_nettype wire
