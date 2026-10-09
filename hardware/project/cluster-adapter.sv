`timescale 1ns/1ps
`default_nettype none

// Private adapter from the fixed_group_ddr_stream1 packed group header to the
// scalar metadata seam of board1_shared_projection_scale_engine.
//
// The packed header is deliberately *not* copied into a second 64-row store.
// The adapter withholds group_ready_o while it presents one real row per
// cycle to the engine.  The ordinary ready/valid contract therefore requires
// the producer to hold the entire immutable header until the final scalar
// metadata transfer.  Weight traffic is then passed through unchanged.
// This keeps the composition to one shared 64-DSP array and adds no RAM.
module board1_shared_projection_scale_group_adapter (
    input  wire                     clk,
    input  wire                     reset_n,
    input  wire                     clear_i,
    input  wire                     model_locked_i,
    input  wire                     upstream_fail_closed_i,

    input  wire                     group_valid_i,
    output logic                    group_ready_o,
    input  wire [2:0]               group_layer_i,
    input  wire [3:0]               group_job_i,
    input  wire [5:0]               group_index_i,
    input  wire [6:0]               group_valid_lanes_i,
    input  wire [64*8-1:0]          group_row_exponent_i,
    input  wire [64*16-1:0]         group_row_multiplier_i,
    input  wire signed [7:0]        activation_exponent_i,

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
        AD_IDLE    = 3'd0,
        AD_META    = 3'd1,
        AD_WEIGHTS = 3'd2,
        AD_WAIT    = 3'd3,
        AD_FAIL    = 3'd4
    } adapter_state_t;

    adapter_state_t state_q;
    logic [2:0] layer_q;
    logic [3:0] job_q;
    logic [5:0] group_q;
    logic [6:0] valid_lanes_q;
    logic signed [7:0] activation_exponent_q;
    logic [5:0] metadata_lane_q;
    logic fail_q;

    function automatic [6:0] groups_for_job(input logic [3:0] job);
        case (job)
            4'd0, 4'd3, 4'd6: groups_for_job = 7'd4;
            4'd1, 4'd2:       groups_for_job = 7'd2;
            4'd4, 4'd5:       groups_for_job = 7'd11;
            4'd7:             groups_for_job = 7'd63;
            default:          groups_for_job = 7'd0;
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

    function automatic source_exponent_valid(
        input logic signed [7:0] activation_exponent,
        input logic [7:0] row_exponent
    );
        logic signed [10:0] sum;
        begin
            sum = $signed({{3{activation_exponent[7]}},
                           activation_exponent}) +
                  $signed({{3{row_exponent[7]}}, row_exponent}) -
                  11'sd15;
            source_exponent_valid = (sum >= -11'sd128) &&
                                    (sum <= 11'sd127);
        end
    endfunction

    logic [6:0] descriptor_groups;
    logic [6:0] descriptor_valid_lanes;
    logic descriptor_valid;
    logic header_protocol_error;
    integer check_lane;
    always @* begin
        descriptor_groups = groups_for_job(group_job_i);
        descriptor_valid_lanes =
            ({1'b0, group_index_i} == descriptor_groups - 7'd1) ?
            last_group_lanes(group_job_i) : 7'd64;
        descriptor_valid = (descriptor_groups != 7'd0) &&
            ({1'b0, group_index_i} < descriptor_groups) &&
            (((group_job_i == 4'd7) && (group_layer_i == 3'd7)) ||
             ((group_job_i < 4'd7) && (group_layer_i < 3'd6)));
        header_protocol_error = !descriptor_valid ||
            (group_valid_lanes_i != descriptor_valid_lanes);
        for (check_lane = 0; check_lane < 64;
             check_lane = check_lane + 1) begin
            if (check_lane < descriptor_valid_lanes) begin
                if ((group_row_multiplier_i[check_lane*16 +: 16] ==
                     16'd0) ||
                    group_row_multiplier_i[check_lane*16 + 15] ||
                    !source_exponent_valid(
                        activation_exponent_i,
                        group_row_exponent_i[check_lane*8 +: 8]))
                    header_protocol_error = 1'b1;
            end else if ((group_row_exponent_i[check_lane*8 +: 8] !=
                          8'd0) ||
                         (group_row_multiplier_i[
                              check_lane*16 +: 16] != 16'd0)) begin
                header_protocol_error = 1'b1;
            end
        end
    end

    logic engine_start_valid;
    wire engine_start_ready;
    logic engine_metadata_valid;
    wire engine_metadata_ready;
    logic engine_weight_valid;
    wire engine_weight_ready;
    wire engine_result_valid;
    wire [12:0] engine_result_row;
    wire signed [49:0] engine_result_scaled;
    wire signed [7:0] engine_result_exponent;
    wire engine_result_last;
    wire engine_done_valid;
    wire engine_busy;
    wire engine_fail;

    wire engine_start_transfer = engine_start_valid && engine_start_ready;
    wire engine_metadata_transfer = engine_metadata_valid &&
                                    engine_metadata_ready;
    wire weight_transfer = weight_valid_i && weight_ready_o;
    wire done_transfer = done_valid_o && done_ready_i;
    wire metadata_is_last =
        ({1'b0, metadata_lane_q} == valid_lanes_q - 7'd1);
    wire [12:0] metadata_row =
        {1'b0, group_q, 6'b000000} +
        {{7{1'b0}}, metadata_lane_q};
    wire signed [7:0] selected_metadata_exponent =
        group_row_exponent_i[metadata_lane_q*8 +: 8];

    always @* begin
        engine_start_valid = (state_q == AD_IDLE) && group_valid_i &&
                             !header_protocol_error &&
                             model_locked_i &&
                             !upstream_fail_closed_i && !fail_q &&
                             !clear_i;
        engine_metadata_valid = (state_q == AD_META) && group_valid_i &&
                                model_locked_i &&
                                !upstream_fail_closed_i && !fail_q &&
                                !clear_i;
        engine_weight_valid = (state_q == AD_WEIGHTS) && weight_valid_i &&
                              model_locked_i &&
                              !upstream_fail_closed_i && !fail_q &&
                              !clear_i;

        // The packed header is accepted on the same edge as its final scalar
        // metadata row.  Until then the producer must hold it immutable.
        group_ready_o = engine_metadata_valid && engine_metadata_ready &&
                        metadata_is_last;
        weight_ready_o = (state_q == AD_WEIGHTS) ? engine_weight_ready :
                         1'b0;

        result_valid_o = engine_result_valid;
        result_row_index_o = engine_result_row;
        result_scaled_raw_o = engine_result_scaled;
        result_source_exponent_o = engine_result_exponent;
        result_last_o = engine_result_last;
        done_valid_o = engine_done_valid;
        busy_o = ((state_q != AD_IDLE) && (state_q != AD_FAIL)) ||
                 engine_busy;
        fail_closed_o = fail_q || engine_fail ||
                        upstream_fail_closed_i;
    end

`ifndef SYNTHESIS
    logic simulation_x_fault;
    always @* begin
        simulation_x_fault = $isunknown(clear_i) ||
            $isunknown(model_locked_i) ||
            $isunknown(upstream_fail_closed_i) ||
            $isunknown(group_valid_i) || $isunknown(weight_valid_i);
        if (group_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                $isunknown(group_layer_i) || $isunknown(group_job_i) ||
                $isunknown(group_index_i) ||
                $isunknown(group_valid_lanes_i) ||
                $isunknown(group_row_exponent_i) ||
                $isunknown(group_row_multiplier_i) ||
                $isunknown(activation_exponent_i);
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
    end
`endif

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state_q <= AD_IDLE;
            layer_q <= 3'd0;
            job_q <= 4'd0;
            group_q <= 6'd0;
            valid_lanes_q <= 7'd0;
            activation_exponent_q <= 8'sd0;
            metadata_lane_q <= 6'd0;
            fail_q <= 1'b0;
        end else if (clear_i === 1'b1) begin
            state_q <= AD_IDLE;
            layer_q <= 3'd0;
            job_q <= 4'd0;
            group_q <= 6'd0;
            valid_lanes_q <= 7'd0;
            activation_exponent_q <= 8'sd0;
            metadata_lane_q <= 6'd0;
            fail_q <= 1'b0;
        end else if (upstream_fail_closed_i || engine_fail ||
                     (((state_q != AD_IDLE) && (state_q != AD_FAIL)) &&
                      !model_locked_i) ||
                     ((state_q == AD_IDLE) && group_valid_i &&
                      header_protocol_error) ||
                     ((state_q == AD_META) &&
                      (!group_valid_i ||
                       (group_layer_i != layer_q) ||
                       (group_job_i != job_q) ||
                       (group_index_i != group_q) ||
                       (group_valid_lanes_i != valid_lanes_q) ||
                       (activation_exponent_i != activation_exponent_q) ||
                       header_protocol_error)) ||
                     ((state_q != AD_META) &&
                      (state_q != AD_IDLE) && group_valid_i) ||
                     ((state_q != AD_WEIGHTS) && weight_valid_i)) begin
            state_q <= AD_FAIL;
            fail_q <= 1'b1;
`ifndef SYNTHESIS
        end else if (simulation_x_fault) begin
            state_q <= AD_FAIL;
            fail_q <= 1'b1;
`endif
        end else begin
            case (state_q)
                AD_IDLE: begin
                    if (engine_start_transfer) begin
                        layer_q <= group_layer_i;
                        job_q <= group_job_i;
                        group_q <= group_index_i;
                        valid_lanes_q <= group_valid_lanes_i;
                        activation_exponent_q <= activation_exponent_i;
                        metadata_lane_q <= 6'd0;
                        state_q <= AD_META;
                    end
                end

                AD_META: begin
                    if (engine_metadata_transfer) begin
                        if (metadata_is_last) begin
                            metadata_lane_q <= 6'd0;
                            state_q <= AD_WEIGHTS;
                        end else begin
                            metadata_lane_q <= metadata_lane_q + 6'd1;
                        end
                    end
                end

                AD_WEIGHTS: begin
                    if (weight_transfer && weight_last_i)
                        state_q <= AD_WAIT;
                end

                AD_WAIT: begin
                    if (done_transfer)
                        state_q <= AD_IDLE;
                end

                default: begin
                    state_q <= AD_FAIL;
                    fail_q <= 1'b1;
                end
            endcase
        end
    end

    board1_clustered_projection_scale2 u_engine (
        .clk(clk), .reset_n(reset_n), .clear_i(clear_i),
        .model_locked_i(model_locked_i),
        .upstream_fail_closed_i(upstream_fail_closed_i || fail_q),
        .start_valid_i(engine_start_valid),
        .start_ready_o(engine_start_ready),
        .fixed_layer_i((state_q == AD_IDLE) ? group_layer_i : layer_q),
        .fixed_job_i((state_q == AD_IDLE) ? group_job_i : job_q),
        .fixed_group_i((state_q == AD_IDLE) ? group_index_i : group_q),
        .activation_exponent_i((state_q == AD_IDLE) ?
            activation_exponent_i : activation_exponent_q),
        .metadata_valid_i(engine_metadata_valid),
        .metadata_ready_o(engine_metadata_ready),
        .metadata_exponent_i(selected_metadata_exponent),
        .metadata_multiplier_i(group_row_multiplier_i[
            metadata_lane_q*16 +: 16]),
        .metadata_row_index_i(metadata_row),
        .metadata_last_i(metadata_is_last),
        .weight_valid_i(engine_weight_valid),
        .weight_ready_o(engine_weight_ready),
        .activation_i(activation_i), .weight_data_i(weight_data_i),
        .weight_last_i(weight_last_i),
        .result_valid_o(engine_result_valid),
        .result_ready_i(result_ready_i),
        .result_row_index_o(engine_result_row),
        .result_scaled_raw_o(engine_result_scaled),
        .result_source_exponent_o(engine_result_exponent),
        .result_last_o(engine_result_last),
        .done_valid_o(engine_done_valid), .done_ready_i(done_ready_i),
        .busy_o(engine_busy), .fail_closed_o(engine_fail)
    );

`ifdef FORMAL
    logic formal_past_valid;
    initial formal_past_valid = 1'b0;
    always_ff @(posedge clk) begin
        formal_past_valid <= 1'b1;
        assert(!(group_ready_o && weight_ready_o));
        if (group_ready_o)
            assert(metadata_is_last && (state_q == AD_META));
        if (state_q == AD_META)
            assert({1'b0, metadata_lane_q} < valid_lanes_q);
        if (formal_past_valid && reset_n && $past(reset_n)) begin
            if ($past(clear_i)) begin
                assert(state_q == AD_IDLE);
                assert(!fail_q);
            end
            if ($past(fail_q) && !$past(clear_i))
                assert(fail_q);
        end
    end
`endif
endmodule

`default_nettype wire
