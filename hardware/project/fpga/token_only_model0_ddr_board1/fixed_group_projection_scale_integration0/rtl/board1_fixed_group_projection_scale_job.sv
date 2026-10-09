`timescale 1ns/1ps
`default_nettype none

// Private job-level composition of the frozen group DDR reader and the
// shared projection/postscale engine.
//
// A fixed controller supplies one legal tensor descriptor and exactly 256 or
// 682 A16 values with one shared BFP exponent.  The values are written through
// a sequential, address-free stream into one synchronous 1R1W activation
// memory.  Thereafter this controller alone enumerates every fixed row group,
// connects the authenticated group header and W10 beats to the shared 64-DSP
// engine, and emits rows in strict order.  There is no programmable address,
// matrix shape, arithmetic mode, multiplier operand, or runtime model write.
module board1_fixed_group_projection_scale_job #(
    parameter integer ADDR_W = 25,
    parameter integer METADATA_BASE_WORD = 211920
) (
    input  wire                     clk,
    input  wire                     reset_n,
    input  wire                     clear_i,
    input  wire                     model_locked_i,
    input  wire                     upstream_fail_closed_i,

    input  wire                     start_valid_i,
    output logic                    start_ready_o,
    input  wire [2:0]               fixed_layer_i,
    input  wire [3:0]               fixed_job_i,
    input  wire signed [7:0]        activation_exponent_i,

    input  wire                     activation_valid_i,
    output logic                    activation_ready_o,
    input  wire signed [15:0]       activation_i,
    input  wire                     activation_last_i,

    output wire                     private_word_req_valid_o,
    input  wire                     private_word_req_ready_i,
    output wire [ADDR_W-1:0]        private_word_req_index_o,
    input  wire                     private_word_rsp_valid_i,
    output wire                     private_word_rsp_ready_o,
    input  wire [255:0]             private_word_rsp_data_i,
    input  wire                     private_word_rsp_fault_i,

    output logic                    result_valid_o,
    input  wire                     result_ready_i,
    output logic [12:0]             result_row_index_o,
    output logic signed [49:0]      result_scaled_raw_o,
    output logic signed [7:0]       result_source_exponent_o,
    output logic                    result_last_o,

    output logic                    done_valid_o,
    input  wire                     done_ready_i,
    output logic                    busy_o,
    output logic                    fail_closed_o
);
    localparam integer MAX_COLUMNS = 682;

    typedef enum logic [2:0] {
        JOB_IDLE        = 3'd0,
        JOB_LOAD        = 3'd1,
        JOB_GROUP_START = 3'd2,
        JOB_GROUP_RUN   = 3'd3,
        JOB_DONE        = 3'd4,
        JOB_DRAIN       = 3'd5,
        JOB_FAIL        = 3'd7
    } job_state_t;

    job_state_t state_q;
    logic [2:0] layer_q;
    logic [3:0] job_q;
    logic signed [7:0] activation_exponent_q;
    logic [12:0] rows_q;
    logic [9:0] columns_q;
    logic [6:0] groups_q;
    logic [9:0] activation_count_q;
    logic [5:0] group_q;
    logic [9:0] column_q;
    logic [12:0] expected_row_q;
    logic stream_done_seen_q;
    logic engine_done_seen_q;
    logic fail_q;
    logic signed [15:0] activation_q;

    // Canonical synchronous 1R1W memory.  The write port is reachable only
    // while loading the fixed-length private activation stream.  The read
    // address is generated solely by the hardwired projection column counter.
    (* ram_style = "block" *) logic signed [15:0]
        activation_memory_q [0:MAX_COLUMNS-1];

    function automatic [12:0] rows_for_job(input logic [3:0] job);
        case (job)
            4'd0: rows_for_job = 13'd256;
            4'd1: rows_for_job = 13'd128;
            4'd2: rows_for_job = 13'd128;
            4'd3: rows_for_job = 13'd256;
            4'd4: rows_for_job = 13'd682;
            4'd5: rows_for_job = 13'd682;
            4'd6: rows_for_job = 13'd256;
            4'd7: rows_for_job = 13'd4019;
            default: rows_for_job = 13'd0;
        endcase
    endfunction

    function automatic [9:0] columns_for_job(input logic [3:0] job);
        case (job)
            4'd6: columns_for_job = 10'd682;
            4'd0, 4'd1, 4'd2, 4'd3, 4'd4, 4'd5, 4'd7:
                columns_for_job = 10'd256;
            default: columns_for_job = 10'd0;
        endcase
    endfunction

    function automatic [6:0] groups_for_job(input logic [3:0] job);
        case (job)
            4'd0, 4'd3, 4'd6: groups_for_job = 7'd4;
            4'd1, 4'd2:       groups_for_job = 7'd2;
            4'd4, 4'd5:       groups_for_job = 7'd11;
            4'd7:             groups_for_job = 7'd63;
            default:          groups_for_job = 7'd0;
        endcase
    endfunction

    logic [12:0] incoming_rows;
    logic [9:0] incoming_columns;
    logic [6:0] incoming_groups;
    logic incoming_descriptor_valid;
    always @* begin
        incoming_rows = rows_for_job(fixed_job_i);
        incoming_columns = columns_for_job(fixed_job_i);
        incoming_groups = groups_for_job(fixed_job_i);
        incoming_descriptor_valid = (incoming_rows != 13'd0) &&
            (incoming_columns != 10'd0) && (incoming_groups != 7'd0) &&
            (((fixed_job_i == 4'd7) && (fixed_layer_i == 3'd7)) ||
             ((fixed_job_i < 4'd7) && (fixed_layer_i < 3'd6)));
    end

    wire activation_expected_last =
        (activation_count_q == columns_q - 10'd1);
    wire start_transfer = start_valid_i && start_ready_o;
    wire activation_transfer = activation_valid_i && activation_ready_o;
    wire activation_protocol_error = activation_transfer &&
        ((activation_last_i != activation_expected_last) ||
         (activation_i == -16'sd32768));

    // Fixed-group DDR stream wires.
    logic stream_start_valid;
    wire stream_start_ready;
    wire stream_group_valid;
    wire stream_group_ready;
    wire [2:0] stream_group_layer;
    wire [3:0] stream_group_job;
    wire [5:0] stream_group_index;
    wire [6:0] stream_group_valid_lanes;
    wire [64*8-1:0] stream_group_row_exponent;
    wire [64*16-1:0] stream_group_row_multiplier;
    wire [639:0] stream_weight_data;
    wire stream_weight_valid;
    wire stream_weight_ready;
    wire stream_weight_last;
    wire stream_done_valid;
    logic stream_done_ready;
    wire stream_busy;
    wire stream_fail;

    // Shared engine adapter wires.
    wire engine_result_valid;
    logic engine_result_ready;
    wire [12:0] engine_result_row;
    wire signed [49:0] engine_result_scaled;
    wire signed [7:0] engine_result_exponent;
    wire engine_result_group_last;
    wire engine_done_valid;
    logic engine_done_ready;
    wire engine_busy;
    wire engine_fail;

    wire child_upstream_fail = upstream_fail_closed_i || fail_q;
    wire integrated_fail = fail_q || stream_fail || engine_fail ||
                           upstream_fail_closed_i;
    wire stream_start_transfer = stream_start_valid && stream_start_ready;
    wire weight_transfer = stream_weight_valid && stream_weight_ready;
    wire stream_done_transfer = stream_done_valid && stream_done_ready;
    wire engine_done_transfer = engine_done_valid && engine_done_ready;

    wire [12:0] group_row_base = {1'b0, group_q, 6'b000000};
    wire [13:0] full_group_end_plus_one =
        {1'b0, group_row_base} + 14'd64;
    wire [12:0] group_end_plus_one =
        (full_group_end_plus_one >= {1'b0, rows_q}) ?
        rows_q : full_group_end_plus_one[12:0];
    wire [12:0] group_last_row = group_end_plus_one - 13'd1;
    wire expected_engine_group_last =
        (engine_result_row == group_last_row);

    wire result_protocol_error = engine_result_valid &&
        ((state_q != JOB_GROUP_RUN) ||
         (engine_result_row != expected_row_q) ||
         (engine_result_row >= rows_q) ||
         (engine_result_group_last != expected_engine_group_last));
    wire weight_protocol_error = weight_transfer &&
        (stream_weight_last != (column_q == columns_q - 10'd1));
    wire group_retiring =
        (stream_done_seen_q || stream_done_transfer) &&
        (engine_done_seen_q || engine_done_transfer);
    wire group_retire_protocol_error = group_retiring &&
        ((expected_row_q != group_end_plus_one) ||
         (column_q != 10'd0));

    // One memory read is primed on the last activation write.  Each accepted
    // W10 beat then advances the synchronous read address.  Holding either
    // side of the weight ready/valid seam also holds activation_q, so the
    // scalar activation and all 64 weights cannot become misaligned.
    wire activation_store_write = activation_transfer &&
                                   !activation_protocol_error;
    wire activation_store_read =
        (activation_store_write && activation_expected_last) ||
        (weight_transfer && !weight_protocol_error &&
         ((column_q != columns_q - 10'd1) ||
          ({1'b0, group_q} != groups_q - 7'd1)));
    wire [9:0] activation_store_read_address =
        (weight_transfer && (column_q != columns_q - 10'd1)) ?
        (column_q + 10'd1) : 10'd0;

    always_ff @(posedge clk) begin
        if (activation_store_write)
            activation_memory_q[activation_count_q] <= activation_i;
        if (activation_store_read)
            activation_q <=
                activation_memory_q[activation_store_read_address];
    end

    always @* begin
        start_ready_o = (state_q == JOB_IDLE) && model_locked_i &&
                        !upstream_fail_closed_i && !integrated_fail &&
                        !clear_i;
        activation_ready_o = (state_q == JOB_LOAD) && model_locked_i &&
                             !upstream_fail_closed_i && !integrated_fail &&
                             !clear_i;
        busy_o = (state_q != JOB_IDLE) && (state_q != JOB_FAIL);
        fail_closed_o = integrated_fail;

        stream_start_valid = (state_q == JOB_GROUP_START) &&
                             !integrated_fail && !clear_i;
        stream_done_ready = (state_q == JOB_GROUP_RUN) &&
                            !stream_done_seen_q && !integrated_fail &&
                            !clear_i;
        engine_done_ready = (state_q == JOB_GROUP_RUN) &&
                            !engine_done_seen_q && !integrated_fail &&
                            !clear_i;

        engine_result_ready = result_ready_i &&
                              (state_q == JOB_GROUP_RUN) &&
                              !result_protocol_error &&
                              !integrated_fail && !clear_i;
        result_valid_o = engine_result_valid &&
                         (state_q == JOB_GROUP_RUN) &&
                         !result_protocol_error &&
                         !integrated_fail && !clear_i;
        // Private invalid metadata is not a public output. Consumers
        // must qualify it with VALID; all fault gates remain intact.
        result_row_index_o = engine_result_row;
        result_scaled_raw_o = result_valid_o ?
                              engine_result_scaled : 50'sd0;
        result_source_exponent_o = result_valid_o ?
                                   engine_result_exponent : 8'sd0;
        result_last_o = (engine_result_row == rows_q - 13'd1);
        done_valid_o = (state_q == JOB_DONE) && !integrated_fail && !clear_i;
    end

`ifndef SYNTHESIS
    logic simulation_x_fault;
    always @* begin
        simulation_x_fault = $isunknown(clear_i) ||
            $isunknown(model_locked_i) ||
            $isunknown(upstream_fail_closed_i) ||
            $isunknown(start_valid_i) ||
            $isunknown(activation_valid_i) ||
            $isunknown(private_word_req_ready_i) ||
            $isunknown(private_word_rsp_valid_i) ||
            $isunknown(private_word_rsp_fault_i);
        if (start_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                $isunknown(fixed_layer_i) || $isunknown(fixed_job_i) ||
                $isunknown(activation_exponent_i);
        if (activation_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                $isunknown(activation_i) || $isunknown(activation_last_i);
        if (private_word_rsp_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                $isunknown(private_word_rsp_data_i);
        if (result_valid_o === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                                 $isunknown(result_ready_i);
        if (done_valid_o === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                                 $isunknown(done_ready_i);
    end
`endif

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state_q <= JOB_IDLE;
            layer_q <= 3'd0;
            job_q <= 4'd0;
            activation_exponent_q <= 8'sd0;
            rows_q <= 13'd0;
            columns_q <= 10'd0;
            groups_q <= 7'd0;
            activation_count_q <= 10'd0;
            group_q <= 6'd0;
            column_q <= 10'd0;
            expected_row_q <= 13'd0;
            stream_done_seen_q <= 1'b0;
            engine_done_seen_q <= 1'b0;
            fail_q <= 1'b0;
        end else if (upstream_fail_closed_i || fail_q || stream_fail ||
                     engine_fail) begin
            state_q <= JOB_FAIL;
            fail_q <= 1'b1;
        end else if (clear_i === 1'b1) begin
            state_q <= JOB_DRAIN;
            activation_count_q <= 10'd0;
            group_q <= 6'd0;
            column_q <= 10'd0;
            expected_row_q <= 13'd0;
            stream_done_seen_q <= 1'b0;
            engine_done_seen_q <= 1'b0;
`ifndef SYNTHESIS
        end else if (simulation_x_fault) begin
            state_q <= JOB_FAIL;
            fail_q <= 1'b1;
`endif
        end else if (((state_q != JOB_IDLE) && start_valid_i) ||
                     ((state_q != JOB_LOAD) && activation_valid_i) ||
                     (((state_q != JOB_IDLE) &&
                       (state_q != JOB_DRAIN) &&
                       (state_q != JOB_FAIL)) && !model_locked_i) ||
                     activation_protocol_error || weight_protocol_error ||
                     result_protocol_error ||
                     group_retire_protocol_error ||
                     ((state_q != JOB_GROUP_RUN) &&
                      (stream_done_valid || engine_done_valid))) begin
            state_q <= JOB_FAIL;
            fail_q <= 1'b1;
        end else begin
            case (state_q)
                JOB_IDLE: begin
                    if (start_transfer) begin
                        if (!incoming_descriptor_valid) begin
                            state_q <= JOB_FAIL;
                            fail_q <= 1'b1;
                        end else begin
                            layer_q <= fixed_layer_i;
                            job_q <= fixed_job_i;
                            activation_exponent_q <= activation_exponent_i;
                            rows_q <= incoming_rows;
                            columns_q <= incoming_columns;
                            groups_q <= incoming_groups;
                            activation_count_q <= 10'd0;
                            group_q <= 6'd0;
                            column_q <= 10'd0;
                            expected_row_q <= 13'd0;
                            stream_done_seen_q <= 1'b0;
                            engine_done_seen_q <= 1'b0;
                            state_q <= JOB_LOAD;
                        end
                    end
                end

                JOB_LOAD: begin
                    if (activation_transfer) begin
                        if (activation_expected_last) begin
                            activation_count_q <= 10'd0;
                            group_q <= 6'd0;
                            column_q <= 10'd0;
                            expected_row_q <= 13'd0;
                            stream_done_seen_q <= 1'b0;
                            engine_done_seen_q <= 1'b0;
                            state_q <= JOB_GROUP_START;
                        end else begin
                            activation_count_q <= activation_count_q + 10'd1;
                        end
                    end
                end

                JOB_GROUP_START: begin
                    if (stream_start_transfer) begin
                        column_q <= 10'd0;
                        stream_done_seen_q <= 1'b0;
                        engine_done_seen_q <= 1'b0;
                        state_q <= JOB_GROUP_RUN;
                    end
                end

                JOB_GROUP_RUN: begin
                    if (weight_transfer) begin
                        if (column_q == columns_q - 10'd1)
                            column_q <= 10'd0;
                        else
                            column_q <= column_q + 10'd1;
                    end
                    if (result_valid_o && result_ready_i)
                        expected_row_q <= expected_row_q + 13'd1;
                    if (stream_done_transfer)
                        stream_done_seen_q <= 1'b1;
                    if (engine_done_transfer)
                        engine_done_seen_q <= 1'b1;
                    if (group_retiring) begin
                        stream_done_seen_q <= 1'b0;
                        engine_done_seen_q <= 1'b0;
                        if ({1'b0, group_q} == groups_q - 7'd1) begin
                            state_q <= JOB_DONE;
                        end else begin
                            group_q <= group_q + 6'd1;
                            state_q <= JOB_GROUP_START;
                        end
                    end
                end

                JOB_DONE: begin
                    if (done_valid_o && done_ready_i) begin
                        activation_count_q <= 10'd0;
                        group_q <= 6'd0;
                        column_q <= 10'd0;
                        expected_row_q <= 13'd0;
                        state_q <= JOB_IDLE;
                    end
                end

                JOB_DRAIN: begin
                    if (!stream_busy && !engine_busy &&
                        !stream_fail && !engine_fail)
                        state_q <= JOB_IDLE;
                end

                default: begin
                    state_q <= JOB_FAIL;
                    fail_q <= 1'b1;
                end
            endcase
        end
    end

    board1_fixed_group_ddr_stream #(
        .ADDR_W(ADDR_W), .METADATA_BASE_WORD(METADATA_BASE_WORD)
    ) u_group_stream (
        .clk(clk), .reset_n(reset_n), .clear_i(clear_i),
        .model_locked_i(model_locked_i),
        .upstream_fail_closed_i(child_upstream_fail),
        .start_valid_i(stream_start_valid),
        .start_ready_o(stream_start_ready),
        .fixed_layer_i(layer_q), .fixed_job_i(job_q),
        .fixed_group_i(group_q),
        .private_word_req_valid_o(private_word_req_valid_o),
        .private_word_req_ready_i(private_word_req_ready_i),
        .private_word_req_index_o(private_word_req_index_o),
        .private_word_rsp_valid_i(private_word_rsp_valid_i),
        .private_word_rsp_ready_o(private_word_rsp_ready_o),
        .private_word_rsp_data_i(private_word_rsp_data_i),
        .private_word_rsp_fault_i(private_word_rsp_fault_i),
        .group_valid_o(stream_group_valid),
        .group_ready_i(stream_group_ready),
        .group_layer_o(stream_group_layer),
        .group_job_o(stream_group_job),
        .group_index_o(stream_group_index),
        .group_valid_lanes_o(stream_group_valid_lanes),
        .group_row_exponent_o(stream_group_row_exponent),
        .group_row_multiplier_o(stream_group_row_multiplier),
        .weight_data_o(stream_weight_data),
        .weight_valid_o(stream_weight_valid),
        .weight_ready_i(stream_weight_ready),
        .weight_last_o(stream_weight_last),
        .done_valid_o(stream_done_valid),
        .done_ready_i(stream_done_ready),
        .busy_o(stream_busy), .fail_closed_o(stream_fail)
    );

    board1_shared_projection_scale_group_adapter u_shared_engine (
        .clk(clk), .reset_n(reset_n), .clear_i(clear_i),
        .model_locked_i(model_locked_i),
        .upstream_fail_closed_i(child_upstream_fail),
        .group_valid_i(stream_group_valid),
        .group_ready_o(stream_group_ready),
        .group_layer_i(stream_group_layer),
        .group_job_i(stream_group_job),
        .group_index_i(stream_group_index),
        .group_valid_lanes_i(stream_group_valid_lanes),
        .group_row_exponent_i(stream_group_row_exponent),
        .group_row_multiplier_i(stream_group_row_multiplier),
        .activation_exponent_i(activation_exponent_q),
        .weight_valid_i(stream_weight_valid),
        .weight_ready_o(stream_weight_ready),
        .activation_i(activation_q),
        .weight_data_i(stream_weight_data),
        .weight_last_i(stream_weight_last),
        .result_valid_o(engine_result_valid),
        .result_ready_i(engine_result_ready),
        .result_row_index_o(engine_result_row),
        .result_scaled_raw_o(engine_result_scaled),
        .result_source_exponent_o(engine_result_exponent),
        .result_last_o(engine_result_group_last),
        .done_valid_o(engine_done_valid),
        .done_ready_i(engine_done_ready),
        .busy_o(engine_busy), .fail_closed_o(engine_fail)
    );

`ifdef FORMAL
    logic formal_past_valid;
    initial formal_past_valid = 1'b0;
    always_ff @(posedge clk) begin
        formal_past_valid <= 1'b1;
        if (reset_n) begin
            assert(group_q < 6'd63);
            assert(column_q < 10'd682);
            assert(expected_row_q <= rows_q);
            if (stream_start_valid)
                assert(state_q == JOB_GROUP_START && group_q < groups_q);
            if (weight_transfer)
                assert(state_q == JOB_GROUP_RUN);
            if (result_valid_o)
                assert(result_row_index_o == expected_row_q);
            if (done_valid_o)
                assert(expected_row_q == rows_q);
            if (state_q == JOB_FAIL) begin
                assert(fail_closed_o);
                assert(!result_valid_o && !done_valid_o);
            end
            if (formal_past_valid && $past(reset_n)) begin
                if ($past(result_valid_o) && !$past(result_ready_i) &&
                    !$past(clear_i)) begin
                    assert(result_valid_o);
                    assert(result_row_index_o ==
                           $past(result_row_index_o));
                    assert(result_scaled_raw_o ==
                           $past(result_scaled_raw_o));
                    assert(result_source_exponent_o ==
                           $past(result_source_exponent_o));
                end
                if ($past(fail_q))
                    assert(fail_q);
            end
        end
    end
`endif
endmodule

`default_nettype wire
