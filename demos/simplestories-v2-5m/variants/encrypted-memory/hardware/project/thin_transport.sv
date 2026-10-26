`timescale 1ns/1ps
`default_nettype none

// Private ordered transport, never a host endpoint. Policy and boot/runtime
// ownership are upstream in the core domain. This block holds accepted work
// across public CLEAR (no CLEAR port); core_stop prevents NEW admission only.
// Controller failure requires common hard reset, not fabricated completions.
module board1_thin_ddr_app_transport (
    input wire core_clk_i, core_reset_n_i, app_clk_i, app_reset_n_i,
    input wire core_stop_i,
    output wire core_fault_o, core_controller_good_o,
    input wire [2:0] core_cmd_i,
    input wire core_cmd_en_i,
    input wire [28:0] core_addr_i,
    input wire [255:0] core_wr_data_i,
    input wire core_wr_en_i, core_wr_end_i,
    input wire [31:0] core_wr_mask_i,
    input wire core_burst_i, core_self_refresh_i, core_refresh_i,
    output wire core_cmd_ready_o, core_wr_ready_o,
    output wire [255:0] core_rd_data_o,
    output wire core_rd_valid_o, core_rd_end_o,
    input wire controller_pll_lock_i, controller_calibrated_i,
    input wire app_cmd_ready_i, app_wr_ready_i,
    output wire [2:0] app_cmd_o,
    output wire app_cmd_en_o,
    output wire [28:0] app_addr_o,
    output wire [255:0] app_wr_data_o,
    output wire app_wr_en_o, app_wr_end_o,
    output wire [31:0] app_wr_mask_o,
    input wire [255:0] app_rd_data_i,
    input wire app_rd_valid_i, app_rd_end_i,
    output wire app_burst_o, app_self_refresh_o, app_refresh_o
);
    localparam integer MAX_READS = 32;
    localparam integer COMMAND_W = 276; // write + 19-bit word + 256-bit data
    wire common_reset_n = core_reset_n_i && app_reset_n_i;
    (* async_reg="true", syn_preserve=1 *) logic [2:0] core_release_q, app_release_q;
    always_ff @(posedge core_clk_i or negedge common_reset_n) begin
        if (!common_reset_n) core_release_q <= 0;
        else core_release_q <= {core_release_q[1:0],1'b1};
    end
    always_ff @(posedge app_clk_i or negedge common_reset_n) begin
        if (!common_reset_n) app_release_q <= 0;
        else app_release_q <= {app_release_q[1:0],1'b1};
    end
    wire core_reset_n = core_release_q[2];
    wire app_reset_n = app_release_q[2];

    logic core_fault_q, app_fault_q, app_good_q, app_seen_q;
    (* async_reg="true", syn_preserve=1 *) logic [1:0] good_core_q, fault_core_q;
    logic [5:0] reserved_q, physical_reads_q;
    wire controller_good = controller_pll_lock_i && controller_calibrated_i;
    wire request_s_ready, request_s_fault, request_m_fault, request_m_valid, physical_ready;
    wire [COMMAND_W-1:0] request_m_data;
    wire response_s_ready, response_s_fault, response_m_fault, response_m_valid;
    wire [256:0] response_m_data;

    assign core_fault_o = core_fault_q || fault_core_q[1];
    assign core_controller_good_o = core_reset_n && good_core_q[1] && !core_fault_o;
    // Reserve a response slot BEFORE admission. Writes share the conservative
    // cap, so no combinational command/VALID dependence enters READY.
    wire core_ready = core_controller_good_o && !core_stop_i &&
                      request_s_ready && (reserved_q < 6'(MAX_READS));
    assign core_cmd_ready_o = core_ready;
    assign core_wr_ready_o = core_ready;
    wire core_write = core_cmd_i == 3'd0;
    wire core_read = core_cmd_i == 3'd1;
    wire core_bad = core_burst_i || core_self_refresh_i || core_refresh_i ||
        (core_cmd_en_i && (!core_ready || (!core_write && !core_read) ||
            core_addr_i[28:22] != 0 || core_addr_i[2:0] != 0 ||
            core_addr_i[21:3] >= 19'd472832 ||
            (core_write && (!core_wr_en_i || !core_wr_end_i || core_wr_mask_i != 0)) ||
            (core_read && (core_wr_en_i || core_wr_end_i)))) ||
        (core_wr_en_i && (!core_cmd_en_i || !core_write));
    wire enqueue = core_cmd_en_i && core_ready && !core_bad;

    board1_async_fifo_gray_block #(.WIDTH(COMMAND_W), .ADDR_BITS(5),
        .RAM_STYLE("block"), .DESTINATION_LOOKAHEAD(0)) u_commands (
        .s_clk_i(core_clk_i), .s_reset_n_i(core_reset_n),
        .s_valid_i(enqueue), .s_ready_o(request_s_ready),
        .s_data_i({core_write,core_addr_i[21:3],core_wr_data_i}), .s_abort_i(1'b0),
        .s_full_o(), .s_empty_o(), .s_protocol_fault_o(request_s_fault),
        .m_clk_i(app_clk_i), .m_reset_n_i(app_reset_n),
        .m_valid_o(request_m_valid), .m_ready_i(physical_ready),
        .m_data_o(request_m_data), .m_empty_o(), .m_protocol_fault_o(request_m_fault));

    wire physical_write = request_m_data[275];
    assign physical_ready = app_reset_n && app_good_q && controller_good &&
        !app_fault_q && app_cmd_ready_i && (!physical_write || app_wr_ready_i);
    wire issue = request_m_valid && physical_ready;
    wire issue_read = issue && !physical_write;
    // All payloads originate in the destination FIFO register; no upstream
    // address-policy/owner/reset reduction is in the physical command cone.
    assign app_cmd_o = physical_write ? 3'd0 : 3'd1;
    assign app_addr_o = {7'd0,request_m_data[274:256],3'b000};
    assign app_wr_data_o = request_m_data[255:0];
    assign app_cmd_en_o = issue;
    assign app_wr_en_o = issue && physical_write;
    assign app_wr_end_o = app_wr_en_o;
    assign app_wr_mask_o = 32'd0;
    assign app_burst_o = 1'b0;
    assign app_self_refresh_o = 1'b0;
    assign app_refresh_o = 1'b0;

    wire owned_return = app_rd_valid_i && physical_reads_q != 0;
    wire capture_return = app_reset_n && owned_return && response_s_ready;
    board1_async_fifo_gray_block #(.WIDTH(257), .ADDR_BITS(6),
        .RAM_STYLE("block")) u_returns (
        .s_clk_i(app_clk_i), .s_reset_n_i(app_reset_n),
        .s_valid_i(capture_return), .s_ready_o(response_s_ready),
        .s_data_i({app_rd_end_i,app_rd_data_i}), .s_abort_i(1'b0),
        .s_full_o(), .s_empty_o(), .s_protocol_fault_o(response_s_fault),
        .m_clk_i(core_clk_i), .m_reset_n_i(core_reset_n),
        .m_valid_o(response_m_valid), .m_ready_i(1'b1),
        .m_data_o(response_m_data), .m_empty_o(), .m_protocol_fault_o(response_m_fault));
    assign core_rd_valid_o = core_reset_n && response_m_valid;
    assign core_rd_data_o = response_m_data[255:0];
    assign core_rd_end_o = response_m_data[256];

    always_ff @(posedge core_clk_i or negedge core_reset_n) begin
        if (!core_reset_n) begin
            good_core_q <= 0; fault_core_q <= 0;
            core_fault_q <= 0; reserved_q <= 0;
        end else begin
            good_core_q <= {good_core_q[0],app_good_q};
            fault_core_q <= {fault_core_q[0],app_fault_q};
            if (core_bad || request_s_fault || response_m_fault ||
                (core_rd_valid_o && reserved_q == 0)) core_fault_q <= 1;
            case ({enqueue && core_read,core_rd_valid_o})
                2'b10: reserved_q <= reserved_q + 6'd1;
                2'b01: if (reserved_q != 0) reserved_q <= reserved_q - 6'd1;
                default: ;
            endcase
        end
    end
    always_ff @(posedge app_clk_i or negedge app_reset_n) begin
        if (!app_reset_n) begin
            app_good_q <= 0; app_seen_q <= 0; app_fault_q <= 0;
            physical_reads_q <= 0;
        end else begin
            app_good_q <= controller_good;
            if (controller_good) app_seen_q <= 1;
            if ((app_seen_q && !controller_good) || request_m_fault || response_s_fault ||
                (app_rd_valid_i && (!owned_return || !response_s_ready ||
                    !app_rd_end_i || !controller_good)) ||
                (issue_read && physical_reads_q == 6'(MAX_READS) && !owned_return))
                app_fault_q <= 1;
            case ({issue_read,owned_return})
                2'b10: physical_reads_q <= physical_reads_q + 6'd1;
                2'b01: physical_reads_q <= physical_reads_q - 6'd1;
                default: ;
            endcase
        end
    end
`ifdef FORMAL
    always_ff @(posedge core_clk_i) if (core_reset_n) begin
        assert (reserved_q <= MAX_READS);
        assert (!core_stop_i || !enqueue);
        if (core_rd_valid_o) assert (reserved_q != 0);
    end
    always_ff @(posedge app_clk_i) if (app_reset_n) begin
        assert (physical_reads_q <= MAX_READS);
        if (app_cmd_en_o) assert (app_cmd_ready_i);
        if (app_wr_en_o) assert (app_cmd_en_o && app_wr_ready_i && app_wr_end_o);
    end
`endif
endmodule
`default_nettype wire
