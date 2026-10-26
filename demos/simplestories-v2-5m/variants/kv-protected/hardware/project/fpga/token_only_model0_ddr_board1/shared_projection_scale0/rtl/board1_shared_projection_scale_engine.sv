`timescale 1ns/1ps
`default_nettype none

// Private fixed-model projection plus row-scale controller.
//
// One group transaction is deliberately ordered as:
//   fixed descriptor -> all real-row metadata -> fixed-column weight beats
//   -> four 16-row scale chunks -> real-row results.
//
// The only multiplier substrate is board1_asymmetric_unified_dsp64.  Every
// weight beat issues mode 0 on all 64 lanes.  Once the signed-35 dot products
// are complete, the controller issues mode 4 on the lower 16 rich lanes for
// four chunks and two exact phases per chunk:
//
//   raw35 = unsigned(raw[24:0]) + (signed(raw[34:25]) << 25).
//
// layer/job/group and every stream below are private seams owned by the fixed
// six-layer controller.  They are not product operations or user operands.
module board1_shared_projection_scale_engine (
    input  wire                     clk,
    input  wire                     reset_n,
    input  wire                     clear_i,
    input  wire                     model_locked_i,
    input  wire                     upstream_fail_closed_i,

    input  wire                     start_valid_i,
    output logic                    start_ready_o,
    input  wire [2:0]               fixed_layer_i,
    input  wire [3:0]               fixed_job_i,
    input  wire [5:0]               fixed_group_i,
    input  wire signed [7:0]        activation_exponent_i,

    input  wire                     metadata_valid_i,
    output logic                    metadata_ready_o,
    input  wire signed [7:0]        metadata_exponent_i,
    input  wire [15:0]              metadata_multiplier_i,
    input  wire [12:0]              metadata_row_index_i,
    input  wire                     metadata_last_i,

    input  wire                     weight_valid_i,
    output logic                    weight_ready_o,
    input  wire signed [15:0]       activation_i,
    input  wire [64*10-1:0]         weight_data_i,
    input  wire                     weight_last_i,

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
    typedef enum logic [2:0] {
        ST_IDLE       = 3'd0,
        ST_METADATA   = 3'd1,
        ST_WEIGHTS    = 3'd2,
        ST_SCALE_LOW  = 3'd3,
        ST_SCALE_HIGH = 3'd4,
        ST_EMIT       = 3'd5,
        ST_DONE       = 3'd6,
        ST_FAIL       = 3'd7
    } state_t;

    state_t state_q;
    logic [2:0] layer_q;
    logic [3:0] job_q;
    logic [5:0] group_q;
    logic [9:0] columns_q;
    logic [6:0] valid_lanes_q;
    logic signed [7:0] activation_exponent_q;
    logic [6:0] metadata_count_q;
    logic [9:0] column_q;
    logic [1:0] chunk_q;
    logic [6:0] emit_lane_q;
    logic fail_q;

    logic signed [34:0] accumulator_q [0:63];
    logic signed [49:0] result_q [0:63];
    logic signed [47:0] low_product_q [0:15];
    logic [15:0] multiplier_q [0:63];
    logic signed [7:0] source_exponent_q [0:63];

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
            4'd1, 4'd2: groups_for_job = 7'd2;
            4'd4, 4'd5: groups_for_job = 7'd11;
            4'd7: groups_for_job = 7'd63;
            default: groups_for_job = 7'd0;
        endcase
    endfunction

    function automatic [6:0] last_group_lanes(input logic [3:0] job);
        case (job)
            4'd4, 4'd5: last_group_lanes = 7'd42;
            4'd7:       last_group_lanes = 7'd51;
            4'd0, 4'd1, 4'd2, 4'd3, 4'd6:
                         last_group_lanes = 7'd64;
            default:    last_group_lanes = 7'd0;
        endcase
    endfunction

    function automatic signed [25:0] low25_piece(
        input logic [24:0] low
    );
        low25_piece = $signed({1'b0, low});
    endfunction

    function automatic signed [25:0] high10_piece(
        input logic signed [9:0] high
    );
        high10_piece = {{16{high[9]}}, high};
    endfunction

    logic descriptor_valid;
    logic [6:0] descriptor_groups;
    logic [12:0] descriptor_rows;
    logic [9:0] descriptor_columns;
    logic [6:0] descriptor_valid_lanes;
    logic [12:0] group_row_base;
    logic [12:0] expected_metadata_row;
    logic expected_metadata_last;
    logic signed [10:0] metadata_source_exponent_wide;
    logic metadata_protocol_error;
    logic weight_protocol_error;
    logic forbidden_weight;
    logic nonzero_ragged_weight;
    logic accumulator_overflow;
    logic unexpected_input;

    logic array_request_valid;
    logic [2:0] array_private_mode;
    logic [63:0] array_requested_lanes;
    logic [64*16-1:0] array_activations;
    logic [64*10-1:0] array_direct_weights;
    logic [64*4-1:0] array_coarse0;
    logic [64*4-1:0] array_coarse1;
    logic [64*6-1:0] array_residual0;
    logic [64*6-1:0] array_residual1;
    logic [16*16-1:0] array_dynamic;
    logic [16*26-1:0] array_wide;
    logic [16*16-1:0] array_scale;
    wire array_issue_valid;
    wire [63:0] array_issued_lanes;
    wire array_illegal_request;
    wire [64*32-1:0] array_product0;
    wire [64*32-1:0] array_product1;
    wire [16*48-1:0] array_wide_product;
    logic array_schedule_error;
    wire _unused_array_product1 = ^array_product1;

    wire start_transfer = start_valid_i && start_ready_o;
    wire metadata_transfer = metadata_valid_i && metadata_ready_o;
    wire weight_transfer = weight_valid_i && weight_ready_o;
    wire result_transfer = result_valid_o && result_ready_i;
    wire done_transfer = done_valid_o && done_ready_i;

    wire signed [35:0] next_accumulator [0:63];
    genvar lane;
    generate
        for (lane = 0; lane < 64; lane = lane + 1) begin : g_next_sum
            wire signed [31:0] lane_product =
                $signed(array_product0[lane*32 +: 32]);
            wire signed [35:0] product_extended =
                {{4{lane_product[31]}}, lane_product};
            wire signed [35:0] accumulator_extended =
                {accumulator_q[lane][34], accumulator_q[lane]};
            assign next_accumulator[lane] = (column_q == 10'd0) ?
                product_extended : accumulator_extended + product_extended;
        end
    endgenerate

    integer check_lane;
    always @* begin
        descriptor_groups = groups_for_job(fixed_job_i);
        descriptor_rows = rows_for_job(fixed_job_i);
        descriptor_columns = columns_for_job(fixed_job_i);
        descriptor_valid = (descriptor_groups != 7'd0) &&
            ({1'b0, fixed_group_i} < descriptor_groups) &&
            (((fixed_job_i == 4'd7) && (fixed_layer_i == 3'd7)) ||
             ((fixed_job_i < 4'd7) && (fixed_layer_i < 3'd6)));
        descriptor_valid_lanes =
            ({1'b0, fixed_group_i} == descriptor_groups - 7'd1) ?
            last_group_lanes(fixed_job_i) : 7'd64;

        group_row_base = {1'b0, group_q, 6'b000000};
        expected_metadata_row = group_row_base +
                                {{6{1'b0}}, metadata_count_q};
        expected_metadata_last =
            (metadata_count_q == valid_lanes_q - 7'd1);
        metadata_source_exponent_wide =
            $signed({{3{activation_exponent_q[7]}},
                     activation_exponent_q}) +
            $signed({{3{metadata_exponent_i[7]}},
                     metadata_exponent_i}) - 11'sd15;
        metadata_protocol_error =
            (metadata_row_index_i != expected_metadata_row) ||
            (metadata_last_i != expected_metadata_last) ||
            (metadata_multiplier_i == 16'd0) ||
            metadata_multiplier_i[15] ||
            (metadata_source_exponent_wide < -11'sd128) ||
            (metadata_source_exponent_wide > 11'sd127);

        forbidden_weight = 1'b0;
        nonzero_ragged_weight = 1'b0;
        accumulator_overflow = 1'b0;
        for (check_lane = 0; check_lane < 64;
             check_lane = check_lane + 1) begin
            if (weight_data_i[check_lane*10 +: 10] == 10'b1000000000)
                forbidden_weight = 1'b1;
            if ((check_lane >= valid_lanes_q) &&
                (weight_data_i[check_lane*10 +: 10] != 10'd0))
                nonzero_ragged_weight = 1'b1;
            if (next_accumulator[check_lane][35] !=
                next_accumulator[check_lane][34])
                accumulator_overflow = 1'b1;
        end
        weight_protocol_error =
            (activation_i == -16'sd32768) || forbidden_weight ||
            nonzero_ragged_weight ||
            (weight_last_i != (column_q == columns_q - 10'd1)) ||
            accumulator_overflow;

        unexpected_input =
            (start_valid_i && (state_q != ST_IDLE)) ||
            (metadata_valid_i && (state_q != ST_METADATA)) ||
            (weight_valid_i && (state_q != ST_WEIGHTS));
    end

    integer mux_lane;
    always @* begin
        array_request_valid = 1'b0;
        array_private_mode = 3'd0;
        array_requested_lanes = 64'd0;
        array_activations = '0;
        array_direct_weights = '0;
        array_coarse0 = '0;
        array_coarse1 = '0;
        array_residual0 = '0;
        array_residual1 = '0;
        array_dynamic = '0;
        array_wide = '0;
        array_scale = '0;

        if ((state_q == ST_WEIGHTS) && weight_transfer) begin
            array_request_valid = 1'b1;
            array_private_mode = 3'd0;
            array_requested_lanes = 64'hffff_ffff_ffff_ffff;
            array_direct_weights = weight_data_i;
            for (mux_lane = 0; mux_lane < 64;
                 mux_lane = mux_lane + 1)
                array_activations[mux_lane*16 +: 16] = activation_i;
        end else if ((state_q == ST_SCALE_LOW) ||
                     (state_q == ST_SCALE_HIGH)) begin
            array_request_valid = 1'b1;
            array_private_mode = 3'd4;
            array_requested_lanes = 64'h0000_0000_0000_ffff;
            for (mux_lane = 0; mux_lane < 16;
                 mux_lane = mux_lane + 1) begin
                array_wide[mux_lane*26 +: 26] =
                    (state_q == ST_SCALE_LOW) ?
                    low25_piece(
                        accumulator_q[chunk_q * 16 + mux_lane][24:0]) :
                    high10_piece(
                        accumulator_q[chunk_q * 16 + mux_lane][34:25]);
                array_scale[mux_lane*16 +: 16] =
                    multiplier_q[chunk_q * 16 + mux_lane];
            end
        end
    end

    always @* begin
        array_schedule_error = 1'b0;
        if (array_request_valid) begin
            if (!array_issue_valid || array_illegal_request ||
                (array_issued_lanes != array_requested_lanes))
                array_schedule_error = 1'b1;
        end
    end

`ifdef BOARD1_SHARED_SCALE_FORMAL_ABSTRACT_ARRAY
    assign array_issue_valid = array_request_valid;
    assign array_issued_lanes = array_request_valid ?
                                array_requested_lanes : 64'd0;
    assign array_illegal_request = 1'b0;
    assign array_product0 = '0;
    assign array_product1 = '0;
    assign array_wide_product = '0;
`else
    board1_asymmetric_unified_dsp64 u_shared_array (
        .request_valid_i(array_request_valid),
        .private_mode_i(array_private_mode),
        .requested_lanes_i(array_requested_lanes),
        .activation_i(array_activations),
        .direct_weight_i(array_direct_weights),
        .coarse_weight0_i(array_coarse0),
        .coarse_weight1_i(array_coarse1),
        .residual_weight0_i(array_residual0),
        .residual_weight1_i(array_residual1),
        .dynamic_operand_i(array_dynamic),
        .wide_operand_i(array_wide),
        .scale_operand_i(array_scale),
        .issue_valid_o(array_issue_valid),
        .issued_lanes_o(array_issued_lanes),
        .illegal_request_o(array_illegal_request),
        .product0_o(array_product0),
        .product1_o(array_product1),
        .wide_product_o(array_wide_product)
    );
`endif

    always @* begin
        start_ready_o = (state_q == ST_IDLE) && model_locked_i &&
                        !upstream_fail_closed_i && !fail_q && !clear_i;
        metadata_ready_o = (state_q == ST_METADATA) && model_locked_i &&
                           !upstream_fail_closed_i && !fail_q && !clear_i;
        weight_ready_o = (state_q == ST_WEIGHTS) && model_locked_i &&
                         !upstream_fail_closed_i && !fail_q && !clear_i;
        result_valid_o = (state_q == ST_EMIT) && model_locked_i &&
                         !upstream_fail_closed_i && !fail_q && !clear_i;
        result_row_index_o = result_valid_o ?
            group_row_base + {{6{1'b0}}, emit_lane_q} : 13'd0;
        result_scaled_raw_o = result_valid_o ?
            result_q[emit_lane_q[5:0]] : 50'sd0;
        result_source_exponent_o = result_valid_o ?
            source_exponent_q[emit_lane_q[5:0]] : 8'sd0;
        result_last_o = result_valid_o &&
                        (emit_lane_q == valid_lanes_q - 7'd1);
        done_valid_o = (state_q == ST_DONE) && model_locked_i &&
                       !upstream_fail_closed_i && !fail_q && !clear_i;
        busy_o = (state_q != ST_IDLE) && (state_q != ST_FAIL);
        fail_closed_o = fail_q || upstream_fail_closed_i;
    end

`ifndef SYNTHESIS
    logic simulation_x_fault;
    always @* begin
        simulation_x_fault = $isunknown(clear_i) ||
            $isunknown(model_locked_i) ||
            $isunknown(upstream_fail_closed_i) ||
            $isunknown(start_valid_i) ||
            $isunknown(metadata_valid_i) ||
            $isunknown(weight_valid_i);
        if (start_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                $isunknown(fixed_layer_i) || $isunknown(fixed_job_i) ||
                $isunknown(fixed_group_i) ||
                $isunknown(activation_exponent_i);
        if (metadata_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                $isunknown(metadata_exponent_i) ||
                $isunknown(metadata_multiplier_i) ||
                $isunknown(metadata_row_index_i) ||
                $isunknown(metadata_last_i);
        if (weight_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                $isunknown(activation_i) || $isunknown(weight_data_i) ||
                $isunknown(weight_last_i);
        if (result_valid_o === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                                 $isunknown(result_ready_i);
        if (done_valid_o === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                                 $isunknown(done_ready_i);
        if (array_request_valid)
            simulation_x_fault = simulation_x_fault ||
                $isunknown(array_issue_valid) ||
                $isunknown(array_issued_lanes) ||
                $isunknown(array_illegal_request) ||
                ((array_private_mode == 3'd0) &&
                 $isunknown(array_product0)) ||
                ((array_private_mode == 3'd4) &&
                 $isunknown(array_wide_product));
    end
`endif

    integer index;
    wire signed [49:0] recombined_scale [0:15];
    generate
        for (lane = 0; lane < 16; lane = lane + 1) begin : g_recombine
            wire signed [49:0] low_term =
                $signed({2'b00, low_product_q[lane]});
            wire signed [49:0] high_term =
                $signed({{2{array_wide_product[lane*48 + 47]}},
                         array_wide_product[lane*48 +: 48]}) <<< 25;
            assign recombined_scale[lane] = low_term + high_term;
        end
    endgenerate

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state_q <= ST_IDLE;
            layer_q <= 3'd0;
            job_q <= 4'd0;
            group_q <= 6'd0;
            columns_q <= 10'd0;
            valid_lanes_q <= 7'd0;
            activation_exponent_q <= 8'sd0;
            metadata_count_q <= 7'd0;
            column_q <= 10'd0;
            chunk_q <= 2'd0;
            emit_lane_q <= 7'd0;
            fail_q <= 1'b0;
            for (index = 0; index < 64; index = index + 1) begin
                accumulator_q[index] <= 35'sd0;
                result_q[index] <= 50'sd0;
                multiplier_q[index] <= 16'd0;
                source_exponent_q[index] <= 8'sd0;
            end
            for (index = 0; index < 16; index = index + 1)
                low_product_q[index] <= 48'sd0;
        end else if (clear_i === 1'b1) begin
            state_q <= ST_IDLE;
            layer_q <= 3'd0;
            job_q <= 4'd0;
            group_q <= 6'd0;
            columns_q <= 10'd0;
            valid_lanes_q <= 7'd0;
            activation_exponent_q <= 8'sd0;
            metadata_count_q <= 7'd0;
            column_q <= 10'd0;
            chunk_q <= 2'd0;
            emit_lane_q <= 7'd0;
            fail_q <= 1'b0;
            for (index = 0; index < 64; index = index + 1) begin
                accumulator_q[index] <= 35'sd0;
                result_q[index] <= 50'sd0;
                multiplier_q[index] <= 16'd0;
                source_exponent_q[index] <= 8'sd0;
            end
            for (index = 0; index < 16; index = index + 1)
                low_product_q[index] <= 48'sd0;
        end else if (upstream_fail_closed_i ||
                     (((state_q != ST_IDLE) && (state_q != ST_FAIL)) &&
                      !model_locked_i) ||
                     (start_valid_i && !start_ready_o) ||
                     unexpected_input || array_schedule_error) begin
            state_q <= ST_FAIL;
            fail_q <= 1'b1;
            for (index = 0; index < 64; index = index + 1)
                result_q[index] <= 50'sd0;
`ifndef SYNTHESIS
        end else if (simulation_x_fault) begin
            state_q <= ST_FAIL;
            fail_q <= 1'b1;
            for (index = 0; index < 64; index = index + 1)
                result_q[index] <= 50'sd0;
`endif
        end else begin
            case (state_q)
                ST_IDLE: begin
                    if (start_transfer) begin
                        if (!descriptor_valid ||
                            (descriptor_rows == 13'd0) ||
                            (descriptor_columns == 10'd0) ||
                            (descriptor_valid_lanes == 7'd0)) begin
                            state_q <= ST_FAIL;
                            fail_q <= 1'b1;
                        end else begin
                            layer_q <= fixed_layer_i;
                            job_q <= fixed_job_i;
                            group_q <= fixed_group_i;
                            columns_q <= descriptor_columns;
                            valid_lanes_q <= descriptor_valid_lanes;
                            activation_exponent_q <= activation_exponent_i;
                            metadata_count_q <= 7'd0;
                            column_q <= 10'd0;
                            chunk_q <= 2'd0;
                            emit_lane_q <= 7'd0;
                            for (index = 0; index < 64;
                                 index = index + 1) begin
                                accumulator_q[index] <= 35'sd0;
                                result_q[index] <= 50'sd0;
                                multiplier_q[index] <= 16'd0;
                                source_exponent_q[index] <= 8'sd0;
                            end
                            state_q <= ST_METADATA;
                        end
                    end
                end

                ST_METADATA: begin
                    if (metadata_transfer) begin
                        if (metadata_protocol_error) begin
                            state_q <= ST_FAIL;
                            fail_q <= 1'b1;
                        end else begin
                            multiplier_q[metadata_count_q[5:0]] <=
                                metadata_multiplier_i;
                            source_exponent_q[metadata_count_q[5:0]] <=
                                metadata_source_exponent_wide[7:0];
                            if (expected_metadata_last) begin
                                metadata_count_q <= 7'd0;
                                state_q <= ST_WEIGHTS;
                            end else begin
                                metadata_count_q <= metadata_count_q + 7'd1;
                            end
                        end
                    end
                end

                ST_WEIGHTS: begin
                    if (weight_transfer) begin
                        if (weight_protocol_error) begin
                            state_q <= ST_FAIL;
                            fail_q <= 1'b1;
                        end else begin
                            for (index = 0; index < 64;
                                 index = index + 1)
                                accumulator_q[index] <=
                                    next_accumulator[index][34:0];
                            if (column_q == columns_q - 10'd1) begin
                                column_q <= 10'd0;
                                chunk_q <= 2'd0;
                                state_q <= ST_SCALE_LOW;
                            end else begin
                                column_q <= column_q + 10'd1;
                            end
                        end
                    end
                end

                ST_SCALE_LOW: begin
                    for (index = 0; index < 16; index = index + 1)
                        low_product_q[index] <=
                            array_wide_product[index*48 +: 48];
                    state_q <= ST_SCALE_HIGH;
                end

                ST_SCALE_HIGH: begin
                    for (index = 0; index < 16; index = index + 1)
                        result_q[chunk_q * 16 + index] <=
                            recombined_scale[index];
                    if (chunk_q == 2'd3) begin
                        emit_lane_q <= 7'd0;
                        state_q <= ST_EMIT;
                    end else begin
                        chunk_q <= chunk_q + 2'd1;
                        state_q <= ST_SCALE_LOW;
                    end
                end

                ST_EMIT: begin
                    if (result_transfer) begin
                        if (emit_lane_q == valid_lanes_q - 7'd1) begin
                            emit_lane_q <= 7'd0;
                            state_q <= ST_DONE;
                        end else begin
                            emit_lane_q <= emit_lane_q + 7'd1;
                        end
                    end
                end

                ST_DONE: begin
                    if (done_transfer)
                        state_q <= ST_IDLE;
                end

                default: begin
                    state_q <= ST_FAIL;
                    fail_q <= 1'b1;
                    for (index = 0; index < 64; index = index + 1)
                        result_q[index] <= 50'sd0;
                end
            endcase
        end
    end

    // The captured descriptor is intentionally retained only as a private
    // fixed-controller witness; it cannot generate an address or mode port.
    wire _unused_fixed_descriptor =
        ^{layer_q, job_q, _unused_array_product1};

`ifdef FORMAL
    logic formal_past_valid;
    initial formal_past_valid = 1'b0;
    initial assume(!reset_n);
    always_ff @(posedge clk) begin
        formal_past_valid <= 1'b1;
        if (array_request_valid) begin
            assert((array_private_mode == 3'd0) ||
                   (array_private_mode == 3'd4));
            if (array_private_mode == 3'd0)
                assert(array_requested_lanes == 64'hffff_ffff_ffff_ffff);
            if (array_private_mode == 3'd4)
                assert(array_requested_lanes == 64'h0000_0000_0000_ffff);
        end
        if (formal_past_valid && reset_n && $past(reset_n)) begin
            if ($past(clear_i)) begin
                assert(state_q == ST_IDLE);
                assert(!fail_q);
                assert(!result_valid_o);
            end else if (!$past(clear_i)) begin
                if ($past(state_q) == ST_FAIL)
                    assert(state_q == ST_FAIL);
                if ($past(result_valid_o) && !$past(result_ready_i) &&
                    !$past(upstream_fail_closed_i) &&
                    $past(model_locked_i)) begin
                    assert(result_valid_o);
                    assert(result_row_index_o ==
                           $past(result_row_index_o));
                    assert(result_scaled_raw_o ==
                           $past(result_scaled_raw_o));
                    assert(result_source_exponent_o ==
                           $past(result_source_exponent_o));
                end
            end
        end
        if (state_q == ST_FAIL) begin
            assert(fail_closed_o);
            assert(!result_valid_o);
            assert(!done_valid_o);
        end
    end
`endif
endmodule

`default_nettype wire
