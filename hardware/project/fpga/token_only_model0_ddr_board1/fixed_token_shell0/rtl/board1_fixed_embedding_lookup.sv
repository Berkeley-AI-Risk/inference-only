`timescale 1ns/1ps
`default_nettype none

// Fixed input-embedding service for the sealed SimpleStories model.
//
// The requested token selects one lane of one immutable job-7 row group.
// The frozen group reader still fetches the complete authenticated group from
// the sole tied embedding/head payload, but only the selected row is admitted
// to the exact BFP-v5 normalizer.  The row address, group, lane, multiplier,
// exponent, and normalization job are all derived internally.  This module is
// an integration-private service and must never be wired to product pins.
module board1_fixed_embedding_lookup #(
    parameter integer ADDR_W = 25,
    parameter integer METADATA_BASE_WORD = 211920,
    parameter integer MAX_COMPUTE_CYCLES = 4_000_000
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    clear_i,
    input  wire                    model_lock_i,
    input  wire                    upstream_fault_i,

    input  wire                    start_valid_i,
    output logic                   start_ready_o,
    input  wire [11:0]             fixed_token_i,

    output wire                    private_word_req_valid_o,
    input  wire                    private_word_req_ready_i,
    output wire [ADDR_W-1:0]       private_word_req_index_o,
    input  wire                    private_word_rsp_valid_i,
    output wire                    private_word_rsp_ready_o,
    input  wire [255:0]            private_word_rsp_data_i,
    input  wire                    private_word_rsp_fault_i,

    output logic                   result_valid_o,
    input  wire                    result_ready_i,
    output logic [7:0]             result_index_o,
    output logic signed [15:0]     result_mantissa_o,
    output logic signed [7:0]      result_exponent_o,
    output logic                   result_last_o,
    output logic                   done_valid_o,
    input  wire                    done_ready_i,
    output logic                   busy_o,
    output logic                   fail_closed_o
);
    typedef enum logic [3:0] {
        ST_IDLE        = 4'd0,
        ST_GROUP_START = 4'd1,
        ST_HEADER      = 4'd2,
        ST_NORM_START  = 4'd3,
        ST_WEIGHTS     = 4'd4,
        ST_RESULTS     = 4'd5,
        ST_TERMINALS   = 4'd6,
        ST_DONE        = 4'd7,
        ST_DRAIN       = 4'd8,
        ST_FAIL        = 4'd15
    } state_t;

    state_t state_q;
    logic [11:0] token_q;
    logic [7:0] column_q;
    logic signed [7:0] row_exponent_q;
    logic [15:0] row_multiplier_q;
    logic group_done_seen_q;
    logic norm_done_seen_q;
    logic [31:0] compute_cycles_q;
    logic fail_q;

    wire group_start_ready;
    wire group_valid;
    logic group_ready;
    wire [2:0] group_layer;
    wire [3:0] group_job;
    wire [5:0] group_index;
    wire [6:0] group_valid_lanes;
    wire [64*8-1:0] group_row_exponents;
    wire [64*16-1:0] group_row_multipliers;
    wire [639:0] group_weight_data;
    wire group_weight_valid;
    logic group_weight_ready;
    wire group_weight_last;
    wire group_done_valid;
    logic group_done_ready;
    wire group_busy;
    wire group_fault;

    wire norm_start_ready;
    logic norm_input_valid;
    wire norm_input_ready;
    wire norm_result_valid;
    logic norm_result_ready;
    wire [9:0] norm_result_index;
    wire signed [15:0] norm_result_mantissa;
    wire signed [7:0] norm_result_exponent;
    wire norm_result_last;
    wire norm_done_valid;
    logic norm_done_ready;
    wire norm_busy;
    wire norm_fault;

    wire [5:0] token_lane = token_q[5:0];
    wire [5:0] token_group = token_q[11:6];
    logic signed [9:0] selected_coefficient;
    logic signed [25:0] selected_product;
    logic signed [7:0] selected_header_exponent;
    logic [15:0] selected_header_multiplier;
    logic header_legal;

    wire group_start_valid = (state_q == ST_GROUP_START) && !fail_q &&
                             !upstream_fault_i && model_lock_i && !clear_i;
    wire norm_start_valid = (state_q == ST_NORM_START) && !fail_q &&
                            !upstream_fault_i && model_lock_i && !clear_i;
    wire weight_transfer = group_weight_valid && group_weight_ready;
    wire group_terminal_transfer = group_done_valid && group_done_ready;
    wire norm_terminal_transfer = norm_done_valid && norm_done_ready;
    wire all_terminals = (group_done_seen_q || group_terminal_transfer) &&
                         (norm_done_seen_q || norm_terminal_transfer);
    wire active_state = (state_q != ST_IDLE) && (state_q != ST_DRAIN) &&
                        (state_q != ST_FAIL);
    wire aggregate_fault = fail_q || group_fault || norm_fault ||
                           upstream_fault_i ||
                           (active_state && !model_lock_i) ||
                           (compute_cycles_q >= MAX_COMPUTE_CYCLES);

    // A constant job-7/layer-7 descriptor selects the one tied tensor used
    // both here and by the final head projection.
    board1_fixed_group_ddr_stream #(
        .ADDR_W(ADDR_W), .METADATA_BASE_WORD(METADATA_BASE_WORD)
    ) u_tied_group_reader (
        .clk(clk), .reset_n(rst_n), .clear_i(clear_i),
        .model_locked_i(model_lock_i),
        .upstream_fail_closed_i(upstream_fault_i || fail_q),
        .start_valid_i(group_start_valid),
        .start_ready_o(group_start_ready),
        .fixed_layer_i(3'd7), .fixed_job_i(4'd7),
        .fixed_group_i(token_group),
        .private_word_req_valid_o(private_word_req_valid_o),
        .private_word_req_ready_i(private_word_req_ready_i),
        .private_word_req_index_o(private_word_req_index_o),
        .private_word_rsp_valid_i(private_word_rsp_valid_i),
        .private_word_rsp_ready_o(private_word_rsp_ready_o),
        .private_word_rsp_data_i(private_word_rsp_data_i),
        .private_word_rsp_fault_i(private_word_rsp_fault_i),
        .group_valid_o(group_valid), .group_ready_i(group_ready),
        .group_layer_o(group_layer), .group_job_o(group_job),
        .group_index_o(group_index),
        .group_valid_lanes_o(group_valid_lanes),
        .group_row_exponent_o(group_row_exponents),
        .group_row_multiplier_o(group_row_multipliers),
        .weight_data_o(group_weight_data),
        .weight_valid_o(group_weight_valid),
        .weight_ready_i(group_weight_ready),
        .weight_last_o(group_weight_last),
        .done_valid_o(group_done_valid), .done_ready_i(group_done_ready),
        .busy_o(group_busy), .fail_closed_o(group_fault)
    );

    // Job zero is used only as the frozen 256-lane length descriptor.  No
    // projection job is exposed or selected by the caller.
    board1_fixed_vector_normalizer #(
        .MAX_COMPUTE_CYCLES(MAX_COMPUTE_CYCLES)
    ) u_embedding_normalizer (
        .clk(clk), .rst_n(rst_n), .clear_i(clear_i || fail_q),
        .model_lock_i(model_lock_i),
        .upstream_fault_i(upstream_fault_i || fail_q),
        .start_valid_i(norm_start_valid), .start_ready_o(norm_start_ready),
        .fixed_layer_i(3'd0), .fixed_job_i(4'd0),
        .input_valid_i(norm_input_valid), .input_ready_o(norm_input_ready),
        .input_row_index_i({2'd0, column_q}),
        .input_raw_i({{24{selected_product[25]}}, selected_product}),
        .input_source_exponent_i(row_exponent_q - 8'sd15),
        .input_last_i(column_q == 8'd255),
        .result_valid_o(norm_result_valid),
        .result_ready_i(norm_result_ready),
        .result_row_index_o(norm_result_index),
        .result_mantissa_o(norm_result_mantissa),
        .result_exponent_o(norm_result_exponent),
        .result_last_o(norm_result_last),
        .done_valid_o(norm_done_valid), .done_ready_i(norm_done_ready),
        .busy_o(norm_busy), .range_fault_o(norm_fault)
    );

    always_comb begin
        // Variable lane selection is confined to the private tied group.
        selected_coefficient = $signed(
            group_weight_data[token_lane*10 +: 10]);
        selected_product = selected_coefficient *
                           $signed({1'b0, row_multiplier_q});
        selected_header_exponent = $signed(
            group_row_exponents[token_lane*8 +: 8]);
        selected_header_multiplier =
            group_row_multipliers[token_lane*16 +: 16];
        header_legal = (group_layer == 3'd7) && (group_job == 4'd7) &&
            (group_index == token_group) &&
            ({1'b0, token_lane} < group_valid_lanes) &&
            (selected_header_exponent >= -8'sd12) &&
            (selected_header_exponent <= -8'sd10) &&
            (selected_header_multiplier != 16'd0) &&
            !selected_header_multiplier[15];

        start_ready_o = (state_q == ST_IDLE) && model_lock_i &&
                        !upstream_fault_i && !fail_q && !group_fault &&
                        !norm_fault && !clear_i;
        busy_o = (state_q != ST_IDLE) && (state_q != ST_FAIL);
        fail_closed_o = fail_q || group_fault || norm_fault ||
                        upstream_fault_i || (state_q == ST_FAIL);

        group_ready = (state_q == ST_HEADER) && header_legal &&
                      !fail_closed_o && !clear_i;
        norm_input_valid = (state_q == ST_WEIGHTS) && group_weight_valid &&
                           (selected_coefficient != -10'sd512) &&
                           !fail_closed_o && !clear_i;
        group_weight_ready = (state_q == ST_WEIGHTS) && norm_input_ready &&
                             (selected_coefficient != -10'sd512) &&
                             !fail_closed_o && !clear_i;

        result_valid_o = (state_q == ST_RESULTS) && norm_result_valid &&
                         !fail_closed_o && !clear_i;
        result_index_o = norm_result_index[7:0];
        result_mantissa_o = norm_result_mantissa;
        result_exponent_o = norm_result_exponent;
        result_last_o = norm_result_last;
        norm_result_ready = (state_q == ST_RESULTS) && result_ready_i &&
                            !fail_closed_o && !clear_i;

        group_done_ready = (state_q == ST_TERMINALS) &&
                           !group_done_seen_q && !fail_closed_o && !clear_i;
        norm_done_ready = (state_q == ST_TERMINALS) &&
                          !norm_done_seen_q && !fail_closed_o && !clear_i;
        done_valid_o = (state_q == ST_DONE) && !fail_closed_o && !clear_i;
    end

`ifndef SYNTHESIS
    logic simulation_x_fault;
    always_comb begin
        simulation_x_fault = $isunknown(rst_n) || $isunknown(clear_i) ||
            $isunknown(model_lock_i) || $isunknown(upstream_fault_i) ||
            $isunknown(start_valid_i) ||
            $isunknown(private_word_req_ready_i) ||
            $isunknown(private_word_rsp_valid_i) ||
            $isunknown(private_word_rsp_fault_i) ||
            $isunknown(result_ready_i) || $isunknown(done_ready_i) ||
            $isunknown(state_q) || $isunknown(fail_q);
        if (start_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                                 $isunknown(fixed_token_i);
        if (private_word_rsp_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                                 $isunknown(private_word_rsp_data_i);
    end
`endif

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= ST_IDLE;
            token_q <= 12'd0;
            column_q <= 8'd0;
            row_exponent_q <= 8'sd0;
            row_multiplier_q <= 16'd0;
            group_done_seen_q <= 1'b0;
            norm_done_seen_q <= 1'b0;
            compute_cycles_q <= 32'd0;
            fail_q <= 1'b0;
        end else begin
`ifndef SYNTHESIS
            if (simulation_x_fault) begin
                state_q <= ST_FAIL;
                fail_q <= 1'b1;
            end else
`endif
            if (aggregate_fault) begin
                state_q <= ST_FAIL;
                fail_q <= 1'b1;
            end else if ((start_valid_i === 1'b1) &&
                         (state_q != ST_IDLE)) begin
                state_q <= ST_FAIL;
                fail_q <= 1'b1;
            end else if (clear_i) begin
                // The group reader owns every accepted DDR request through
                // terminal drain.  Keep this wrapper busy until it releases
                // that ownership; the normalizer aborts locally.
                state_q <= ST_DRAIN;
                column_q <= 8'd0;
                group_done_seen_q <= 1'b0;
                norm_done_seen_q <= 1'b0;
                compute_cycles_q <= 32'd0;
            end else begin
                if (active_state)
                    compute_cycles_q <= compute_cycles_q + 1'b1;
                else if (state_q == ST_IDLE)
                    compute_cycles_q <= 32'd0;

                case (state_q)
                    ST_IDLE: begin
                        if (start_valid_i && start_ready_o) begin
                            if (fixed_token_i >= 12'd4019) begin
                                state_q <= ST_FAIL;
                                fail_q <= 1'b1;
                            end else begin
                                token_q <= fixed_token_i;
                                column_q <= 8'd0;
                                group_done_seen_q <= 1'b0;
                                norm_done_seen_q <= 1'b0;
                                state_q <= ST_GROUP_START;
                            end
                        end
                    end

                    ST_GROUP_START: begin
                        if (group_start_valid && group_start_ready)
                            state_q <= ST_HEADER;
                    end

                    ST_HEADER: begin
                        if (group_valid) begin
                            if (!header_legal) begin
                                state_q <= ST_FAIL;
                                fail_q <= 1'b1;
                            end else if (group_ready) begin
                                row_exponent_q <= selected_header_exponent;
                                row_multiplier_q <= selected_header_multiplier;
                                column_q <= 8'd0;
                                state_q <= ST_NORM_START;
                            end
                        end
                    end

                    ST_NORM_START: begin
                        if (norm_start_valid && norm_start_ready)
                            state_q <= ST_WEIGHTS;
                    end

                    ST_WEIGHTS: begin
                        if (group_weight_valid &&
                            (selected_coefficient == -10'sd512)) begin
                            state_q <= ST_FAIL;
                            fail_q <= 1'b1;
                        end else if (weight_transfer) begin
                            if (group_weight_last != (column_q == 8'd255)) begin
                                state_q <= ST_FAIL;
                                fail_q <= 1'b1;
                            end else if (column_q == 8'd255) begin
                                column_q <= 8'd0;
                                state_q <= ST_RESULTS;
                            end else begin
                                column_q <= column_q + 1'b1;
                            end
                        end
                    end

                    ST_RESULTS: begin
                        if (norm_result_valid &&
                            ((norm_result_index[9:8] != 2'd0) ||
                             (norm_result_mantissa == -16'sd32768))) begin
                            state_q <= ST_FAIL;
                            fail_q <= 1'b1;
                        end else if (result_valid_o && result_ready_i &&
                                     result_last_o) begin
                            state_q <= ST_TERMINALS;
                        end
                    end

                    ST_TERMINALS: begin
                        if (group_terminal_transfer)
                            group_done_seen_q <= 1'b1;
                        if (norm_terminal_transfer)
                            norm_done_seen_q <= 1'b1;
                        if (all_terminals) begin
                            group_done_seen_q <= 1'b0;
                            norm_done_seen_q <= 1'b0;
                            state_q <= ST_DONE;
                        end
                    end

                    ST_DONE: begin
                        if (done_valid_o && done_ready_i)
                            state_q <= ST_IDLE;
                    end

                    ST_DRAIN: begin
                        if (!group_busy && !norm_busy)
                            state_q <= ST_IDLE;
                    end

                    default: begin
                        state_q <= ST_FAIL;
                        fail_q <= 1'b1;
                    end
                endcase
            end
        end
    end

`ifdef FORMAL
    always_ff @(posedge clk) begin
        if (rst_n && !$past(clear_i)) begin
            if ($past(fail_q)) assert(fail_q);
            if ($past(result_valid_o) && !$past(result_ready_i)) begin
                assert(result_valid_o);
                assert(result_index_o == $past(result_index_o));
                assert(result_mantissa_o == $past(result_mantissa_o));
                assert(result_exponent_o == $past(result_exponent_o));
                assert(result_last_o == $past(result_last_o));
            end
            if (result_valid_o) begin
                assert(result_mantissa_o != -16'sd32768);
                assert(result_last_o == (result_index_o == 8'd255));
            end
        end
    end
`endif
endmodule

`default_nettype wire
