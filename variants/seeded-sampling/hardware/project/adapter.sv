`timescale 1ns/1ps
`default_nettype none

// Private adapter from Board1's normalized one-request/one-response DDR seam
// to the application interface of Sipeed's official Gowin DDR3 IP 6.0
// project for the Tang Mega 138K device-C board.
//
// This block is below the authenticated model lock.  Its normalized request
// input is not public and it adds no address, write, burst, or matrix command
// to the product boundary.  A normalized 256-bit word index maps to the Gowin
// controller's 29-bit address as {zero padding, word_index, 3'b000}: the
// official x32/BL8 controller transfers 32 bytes and its own test advances
// consecutive application addresses by eight column units.
module board1_gowin_ddr3_app_adapter #(
    parameter integer ADDR_W = 25,
    parameter integer MAX_OUTSTANDING_READS = 16
) (
    input  wire                   clk,
    input  wire                   reset_n,

    // Private normalized seam from board1_private_ddr_lock_bridge.
    input  wire                   phy_req_valid_i,
    output logic                  phy_req_ready_o,
    input  wire                   phy_req_write_i,
    input  wire [ADDR_W-1:0]      phy_req_word_addr_i,
    input  wire [255:0]           phy_req_wdata_i,
    output logic                  phy_rsp_valid_o,
    output logic [255:0]          phy_rsp_data_o,
    output logic                  phy_rsp_error_o,

    // Status returned to the authenticated bridge.
    input  wire                   controller_pll_lock_i,
    input  wire                   controller_init_calib_complete_i,
    output logic                  calib_done_o,
    output logic                  calib_error_o,
    output logic                  protocol_fault_o,

    // Exact application seam of the official Gowin DDR3 IP.
    input  wire                   app_cmd_ready_i,
    output logic [2:0]            app_cmd_o,
    output logic                  app_cmd_en_o,
    output logic [28:0]           app_addr_o,
    input  wire                   app_wr_data_ready_i,
    output logic [255:0]          app_wr_data_o,
    output logic                  app_wr_data_en_o,
    output logic                  app_wr_data_end_o,
    output logic [31:0]           app_wr_data_mask_o,
    input  wire [255:0]           app_rd_data_i,
    input  wire                   app_rd_data_valid_i,
    input  wire                   app_rd_data_end_i,
    output logic                  app_burst_o,
    output logic                  app_self_refresh_req_o,
    output logic                  app_refresh_req_o
);
    localparam integer APP_ADDR_W = 29;
    localparam integer COLUMN_ZERO_BITS = 3;
    localparam integer TOP_ZERO_BITS =
        APP_ADDR_W - ADDR_W - COLUMN_ZERO_BITS;
    localparam integer OUTSTANDING_W =
        $clog2(MAX_OUTSTANDING_READS + 1);

    // The official example assigns command 000 to writes and 001 to reads.
    localparam logic [2:0] GOWIN_CMD_WRITE = 3'b000;
    localparam logic [2:0] GOWIN_CMD_READ  = 3'b001;

    logic calibration_seen_q;
    logic [OUTSTANDING_W-1:0] outstanding_reads_q;

    wire controller_known_good =
        (controller_pll_lock_i === 1'b1) &&
        (controller_init_calib_complete_i === 1'b1);
    wire request_accept = phy_req_valid_i && phy_req_ready_o;
    wire read_issue = request_accept && !phy_req_write_i;
    wire read_response_legal =
        (app_rd_data_valid_i === 1'b1) &&
        (app_rd_data_end_i === 1'b1) &&
        (outstanding_reads_q != 0) && controller_known_good;

    initial begin
        if (ADDR_W <= 0 || TOP_ZERO_BITS < 0)
            $fatal(1, "normalized word address does not fit Gowin app address");
        if (MAX_OUTSTANDING_READS <= 0 ||
            MAX_OUTSTANDING_READS >= (1 << OUTSTANDING_W))
            $fatal(1, "invalid maximum outstanding-read count");
    end

    always_comb begin
        phy_req_ready_o = 1'b0;
        phy_rsp_valid_o = (app_rd_data_valid_i === 1'b1);
        // Data buses need no idle-value mux: their valid/enables remain the
        // sole consumers' qualification and every seam here is private.
        phy_rsp_data_o = app_rd_data_i;
        phy_rsp_error_o = phy_rsp_valid_o &&
            ((app_rd_data_end_i !== 1'b1) ||
             (outstanding_reads_q == 0) || !controller_known_good ||
             protocol_fault_o);

        calib_done_o = calibration_seen_q && controller_known_good &&
                       !protocol_fault_o;
        calib_error_o = protocol_fault_o;

        app_cmd_o = GOWIN_CMD_READ;
        app_cmd_en_o = 1'b0;
        app_addr_o = {{TOP_ZERO_BITS{1'b0}},
                      phy_req_word_addr_i, 3'b000};
        app_wr_data_o = phy_req_wdata_i;
        app_wr_data_en_o = 1'b0;
        app_wr_data_end_o = 1'b0;
        app_wr_data_mask_o = 32'b0;
        app_burst_o = 1'b0;
        app_self_refresh_req_o = 1'b0;
        app_refresh_req_o = 1'b0;

        // Readiness is local capacity, not an acknowledgement of VALID.
        // Keep X/Z VALID closed in four-state simulation. For binary hardware
        // this known-value guard is constant true and creates no VALID path.
        // Command/data enables below STILL require the original known VALID.
        if (calib_done_o && ((phy_req_valid_i === 1'b0) ||
                            (phy_req_valid_i === 1'b1))) begin
            if ((phy_req_write_i === 1'b1) &&
                (app_cmd_ready_i === 1'b1) &&
                (app_wr_data_ready_i === 1'b1))
                phy_req_ready_o = 1'b1;
            else if ((phy_req_write_i === 1'b0) &&
                     (app_cmd_ready_i === 1'b1) &&
                     (outstanding_reads_q <
                      OUTSTANDING_W'(MAX_OUTSTANDING_READS)))
                phy_req_ready_o = 1'b1;
        end

        // Exact-equality guards make an X/Z request fail closed in
        // four-state simulation instead of emitting a controller command.
        if ((phy_req_valid_i === 1'b1) && calib_done_o) begin
            if ((phy_req_write_i === 1'b1) &&
                (app_cmd_ready_i === 1'b1) &&
                (app_wr_data_ready_i === 1'b1)) begin
                app_cmd_o = GOWIN_CMD_WRITE;
                app_cmd_en_o = 1'b1;
                app_wr_data_en_o = 1'b1;
                app_wr_data_end_o = 1'b1;
            end else if ((phy_req_write_i === 1'b0) &&
                         (app_cmd_ready_i === 1'b1) &&
                         (outstanding_reads_q <
                          OUTSTANDING_W'(MAX_OUTSTANDING_READS))) begin
                app_cmd_o = GOWIN_CMD_READ;
                app_cmd_en_o = 1'b1;
            end
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            calibration_seen_q <= 1'b0;
            outstanding_reads_q <= '0;
            protocol_fault_o <= 1'b0;
        end else begin
            if (controller_known_good)
                calibration_seen_q <= 1'b1;

            if (calibration_seen_q && !controller_known_good)
                protocol_fault_o <= 1'b1;

            if ((app_rd_data_valid_i === 1'b1) &&
                ((app_rd_data_end_i !== 1'b1) ||
                 (outstanding_reads_q == 0) || !controller_known_good))
                protocol_fault_o <= 1'b1;

`ifndef SYNTHESIS
            if ($isunknown(controller_pll_lock_i) ||
                $isunknown(controller_init_calib_complete_i) ||
                $isunknown(phy_req_valid_i) ||
                ((phy_req_valid_i === 1'b1) &&
                 ($isunknown(phy_req_write_i) ||
                  $isunknown(phy_req_word_addr_i) ||
                  $isunknown(app_cmd_ready_i) ||
                  ((phy_req_write_i === 1'b1) &&
                   ($isunknown(phy_req_wdata_i) ||
                    $isunknown(app_wr_data_ready_i))))) ||
                $isunknown(app_rd_data_valid_i) ||
                ((app_rd_data_valid_i === 1'b1) &&
                 ($isunknown(app_rd_data_end_i) ||
                  $isunknown(app_rd_data_i))))
                protocol_fault_o <= 1'b1;
`endif

            if (!protocol_fault_o) begin
                case ({read_issue, read_response_legal})
                    2'b10: outstanding_reads_q <=
                        outstanding_reads_q + 1'b1;
                    2'b01: outstanding_reads_q <=
                        outstanding_reads_q - 1'b1;
                    default: begin
                    end
                endcase
            end
        end
    end

`ifdef FORMAL
    logic formal_past_valid;
    always_ff @(posedge clk) begin
        formal_past_valid <= 1'b1;
        if (reset_n && app_cmd_en_o) begin
            assert (phy_req_valid_i && phy_req_ready_o);
            assert (app_addr_o[2:0] == 3'b000);
            assert (app_cmd_o == (phy_req_write_i ?
                                  GOWIN_CMD_WRITE : GOWIN_CMD_READ));
        end
        if (reset_n && app_wr_data_en_o) begin
            assert (app_cmd_en_o && app_cmd_o == GOWIN_CMD_WRITE);
            assert (app_wr_data_end_o && app_wr_data_mask_o == 0);
        end
        if (reset_n && app_cmd_en_o && app_cmd_o == GOWIN_CMD_READ)
            assert (!app_wr_data_en_o);
        if (formal_past_valid && reset_n && $past(reset_n) &&
            $past(protocol_fault_o))
            assert (protocol_fault_o);
    end
`endif
endmodule

`default_nettype wire
