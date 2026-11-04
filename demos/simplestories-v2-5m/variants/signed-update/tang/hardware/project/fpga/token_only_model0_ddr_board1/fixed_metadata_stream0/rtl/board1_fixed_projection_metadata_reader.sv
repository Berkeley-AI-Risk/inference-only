`timescale 1ns/1ps
`default_nettype none

// Private fixed-address reader for real_semantic_image1's projection metadata.
//
// The descriptor inputs are driven only by the immutable six-layer controller
// below the product boundary.  No descriptor, address, metadata, or raw result
// signal is a user operation.  Each accepted descriptor reads exactly eight
// consecutive 256-bit words and emits one record for every real row in the
// selected 64-row group.  Ragged records are consumed internally and must be
// all zero.
module board1_fixed_projection_metadata_reader #(
    parameter integer ADDR_W = 25,
    parameter integer METADATA_BASE_WORD = 211920
) (
    input  wire                   clk,
    input  wire                   reset_n,
    input  wire                   clear_i,
    input  wire                   model_locked_i,
    input  wire                   upstream_fail_closed_i,

    input  wire                   start_valid_i,
    output logic                  start_ready_o,
    input  wire [2:0]             fixed_layer_i,
    input  wire [3:0]             fixed_job_i,
    input  wire [5:0]             fixed_group_i,

    output logic                  private_word_req_valid_o,
    input  wire                   private_word_req_ready_i,
    output logic [ADDR_W-1:0]     private_word_req_index_o,
    input  wire                   private_word_rsp_valid_i,
    output logic                  private_word_rsp_ready_o,
    input  wire [255:0]           private_word_rsp_data_i,
    input  wire                   private_word_rsp_fault_i,

    output logic                  metadata_valid_o,
    input  wire                   metadata_ready_i,
    output logic signed [7:0]     metadata_exponent_o,
    output logic [15:0]           metadata_multiplier_o,
    output logic [12:0]           metadata_row_index_o,
    output logic                  metadata_last_o,

    output logic                  done_valid_o,
    input  wire                   done_ready_i,
    output logic                  busy_o,
    output logic                  fail_closed_o
);
    localparam logic [2:0] ST_IDLE    = 3'd0;
    localparam logic [2:0] ST_REQUEST = 3'd1;
    localparam logic [2:0] ST_WAIT    = 3'd2;
    localparam logic [2:0] ST_EMIT    = 3'd3;
    localparam logic [2:0] ST_DONE    = 3'd4;
    localparam logic [2:0] ST_DRAIN   = 3'd5;
    localparam logic [2:0] ST_FAIL    = 3'd7;

    logic [2:0] state_q;
    logic [ADDR_W-1:0] group_base_word_q;
    logic [2:0] word_in_group_q;
    logic [2:0] record_in_word_q;
    logic [6:0] valid_lanes_q;
    logic [5:0] group_q;
    logic [3:0] job_q;
    logic [2:0] layer_q;
    logic [255:0] response_word_q;
    logic request_outstanding_q;
    logic fail_closed_q;

    logic descriptor_valid;
    logic [6:0] descriptor_groups;
    logic [6:0] descriptor_valid_lanes;
    logic [ADDR_W-1:0] descriptor_base_word;
    logic [10:0] job_word_offset;

    logic [31:0] current_record;
    logic [5:0] current_lane;
    logic current_lane_is_real;
    logic current_real_record_is_legal;
    logic current_ragged_record_is_legal;
    logic response_transfer;
    logic request_transfer;
    logic metadata_transfer;
    logic done_transfer;

`ifndef SYNTHESIS
    logic simulation_x_fault;
`endif

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

    function automatic [10:0] word_offset_for_job(input logic [3:0] job);
        case (job)
            4'd0: word_offset_for_job = 11'd0;
            4'd1: word_offset_for_job = 11'd32;
            4'd2: word_offset_for_job = 11'd48;
            4'd3: word_offset_for_job = 11'd64;
            4'd4: word_offset_for_job = 11'd96;
            4'd5: word_offset_for_job = 11'd184;
            4'd6: word_offset_for_job = 11'd272;
            4'd7: word_offset_for_job = 11'd1824;
            default: word_offset_for_job = 11'd0;
        endcase
    endfunction

    always @* begin
        descriptor_groups = groups_for_job(fixed_job_i);
        job_word_offset = word_offset_for_job(fixed_job_i);
        descriptor_valid = (descriptor_groups != 7'd0) &&
            ({1'b0, fixed_group_i} < descriptor_groups) &&
            (((fixed_job_i == 4'd7) && (fixed_layer_i == 3'd7)) ||
             ((fixed_job_i < 4'd7) && (fixed_layer_i < 3'd6)));
        descriptor_valid_lanes =
            ({1'b0, fixed_group_i} == (descriptor_groups - 7'd1)) ?
            last_group_lanes(fixed_job_i) : 7'd64;
        if (fixed_job_i == 4'd7) begin
            descriptor_base_word = ADDR_W'(METADATA_BASE_WORD) +
                                   ADDR_W'(11'd1824) +
                                   ADDR_W'({fixed_group_i, 3'b000});
        end else begin
            descriptor_base_word = ADDR_W'(METADATA_BASE_WORD) +
                                   ADDR_W'(fixed_layer_i * 12'd304) +
                                   ADDR_W'(job_word_offset) +
                                   ADDR_W'({fixed_group_i, 3'b000});
        end
    end

    always @* begin
        current_lane = {word_in_group_q, record_in_word_q};
        current_record =
            response_word_q[record_in_word_q * 32 +: 32];
        current_lane_is_real = ({1'b0, current_lane} < valid_lanes_q);
        current_real_record_is_legal =
            (current_record[31:24] == 8'd0) &&
            (current_record[23:8] != 16'd0) &&
            !current_record[23];
        current_ragged_record_is_legal = (current_record == 32'd0);

        start_ready_o = (state_q == ST_IDLE) && model_locked_i &&
                        !upstream_fail_closed_i && !fail_closed_q &&
                        !clear_i;
        private_word_req_valid_o = (state_q == ST_REQUEST) &&
                                   model_locked_i &&
                                   !upstream_fail_closed_i &&
                                   !fail_closed_q && !clear_i;
        private_word_req_index_o = group_base_word_q +
                                   ADDR_W'(word_in_group_q);
        private_word_rsp_ready_o = request_outstanding_q &&
            ((state_q == ST_WAIT) || (state_q == ST_DRAIN) ||
             (state_q == ST_FAIL));

        metadata_valid_o = (state_q == ST_EMIT) &&
                           current_lane_is_real &&
                           current_real_record_is_legal &&
                           !upstream_fail_closed_i && !fail_closed_q &&
                           model_locked_i && !clear_i;
        metadata_exponent_o = metadata_valid_o ?
                              $signed(current_record[7:0]) : 8'sd0;
        metadata_multiplier_o = metadata_valid_o ?
                                current_record[23:8] : 16'd0;
        metadata_row_index_o = metadata_valid_o ?
            ({7'd0, group_q} << 6) + {7'd0, current_lane} : 13'd0;
        metadata_last_o = metadata_valid_o &&
                          ({1'b0, current_lane} ==
                           (valid_lanes_q - 7'd1));

        done_valid_o = (state_q == ST_DONE) && !fail_closed_q &&
                       !upstream_fail_closed_i && model_locked_i &&
                       !clear_i;
        busy_o = (state_q != ST_IDLE) && (state_q != ST_FAIL);
        fail_closed_o = fail_closed_q || upstream_fail_closed_i;

        request_transfer = private_word_req_valid_o &&
                           private_word_req_ready_i;
        response_transfer = private_word_rsp_valid_i &&
                            private_word_rsp_ready_o;
        metadata_transfer = metadata_valid_o && metadata_ready_i;
        done_transfer = done_valid_o && done_ready_i;
    end

`ifndef SYNTHESIS
    always @* begin
        simulation_x_fault = $isunknown(clear_i) ||
            $isunknown(model_locked_i) ||
            $isunknown(upstream_fail_closed_i) ||
            $isunknown(start_valid_i) ||
            $isunknown(private_word_req_ready_i) ||
            $isunknown(private_word_rsp_valid_i) ||
            $isunknown(private_word_rsp_fault_i);
        if (start_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                $isunknown(fixed_layer_i) || $isunknown(fixed_job_i) ||
                $isunknown(fixed_group_i);
        if (private_word_rsp_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                                 $isunknown(private_word_rsp_data_i);
        if (metadata_valid_o === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                                 $isunknown(metadata_ready_i);
        if (done_valid_o === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                                 $isunknown(done_ready_i);
    end
`endif

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state_q <= ST_IDLE;
            group_base_word_q <= '0;
            word_in_group_q <= 3'd0;
            record_in_word_q <= 3'd0;
            valid_lanes_q <= 7'd0;
            group_q <= 6'd0;
            job_q <= 4'd0;
            layer_q <= 3'd0;
            response_word_q <= 256'd0;
            request_outstanding_q <= 1'b0;
            fail_closed_q <= 1'b0;
        end else if (upstream_fail_closed_i ||
                     ((state_q != ST_IDLE) &&
                      (state_q != ST_FAIL) && !model_locked_i) ||
                     (private_word_rsp_valid_i &&
                      !request_outstanding_q) ||
                     (private_word_rsp_fault_i && response_transfer) ||
                     (start_valid_i && !start_ready_o && !clear_i)) begin
            state_q <= ST_FAIL;
            if (response_transfer)
                request_outstanding_q <= 1'b0;
            fail_closed_q <= 1'b1;
`ifndef SYNTHESIS
        end else if (simulation_x_fault) begin
            state_q <= ST_FAIL;
            fail_closed_q <= 1'b1;
`endif
        end else if (clear_i) begin
            if (request_outstanding_q && !response_transfer)
                state_q <= ST_DRAIN;
            else
                state_q <= ST_IDLE;
            if (response_transfer)
                request_outstanding_q <= 1'b0;
            word_in_group_q <= 3'd0;
            record_in_word_q <= 3'd0;
            response_word_q <= 256'd0;
        end else begin
            case (state_q)
                ST_IDLE: begin
                    if (start_valid_i && start_ready_o) begin
                        if (!descriptor_valid ||
                            (descriptor_valid_lanes == 7'd0)) begin
                            state_q <= ST_FAIL;
                            fail_closed_q <= 1'b1;
                        end else begin
                            group_base_word_q <= descriptor_base_word;
                            valid_lanes_q <= descriptor_valid_lanes;
                            group_q <= fixed_group_i;
                            job_q <= fixed_job_i;
                            layer_q <= fixed_layer_i;
                            word_in_group_q <= 3'd0;
                            record_in_word_q <= 3'd0;
                            state_q <= ST_REQUEST;
                        end
                    end
                end

                ST_REQUEST: begin
                    if (request_transfer) begin
                        request_outstanding_q <= 1'b1;
                        state_q <= ST_WAIT;
                    end
                end

                ST_WAIT: begin
                    if (response_transfer) begin
                        request_outstanding_q <= 1'b0;
                        response_word_q <= private_word_rsp_data_i;
                        record_in_word_q <= 3'd0;
                        state_q <= ST_EMIT;
                    end
                end

                ST_EMIT: begin
                    if (current_lane_is_real) begin
                        if (!current_real_record_is_legal) begin
                            state_q <= ST_FAIL;
                            fail_closed_q <= 1'b1;
                        end else if (metadata_transfer) begin
                            if (record_in_word_q == 3'd7) begin
                                record_in_word_q <= 3'd0;
                                if (word_in_group_q == 3'd7) begin
                                    state_q <= ST_DONE;
                                end else begin
                                    word_in_group_q <=
                                        word_in_group_q + 3'd1;
                                    state_q <= ST_REQUEST;
                                end
                            end else begin
                                record_in_word_q <=
                                    record_in_word_q + 3'd1;
                            end
                        end
                    end else begin
                        if (!current_ragged_record_is_legal) begin
                            state_q <= ST_FAIL;
                            fail_closed_q <= 1'b1;
                        end else if (record_in_word_q == 3'd7) begin
                            record_in_word_q <= 3'd0;
                            if (word_in_group_q == 3'd7) begin
                                state_q <= ST_DONE;
                            end else begin
                                word_in_group_q <= word_in_group_q + 3'd1;
                                state_q <= ST_REQUEST;
                            end
                        end else begin
                            record_in_word_q <= record_in_word_q + 3'd1;
                        end
                    end
                end

                ST_DONE: begin
                    if (done_transfer)
                        state_q <= ST_IDLE;
                end

                ST_DRAIN: begin
                    if (response_transfer) begin
                        request_outstanding_q <= 1'b0;
                        state_q <= ST_IDLE;
                    end
                end

                default: begin
                    if (response_transfer)
                        request_outstanding_q <= 1'b0;
                    state_q <= ST_FAIL;
                    fail_closed_q <= 1'b1;
                end
            endcase
        end
    end

    // These registers are retained as explicit fixed-controller witnesses.
    // They are intentionally not outputs and cannot select any new address.
    wire _unused_descriptor_witness = ^{job_q, layer_q};

`ifdef FORMAL
    logic formal_past_valid_q;
    always_ff @(posedge clk) begin
        formal_past_valid_q <= 1'b1;
        if (formal_past_valid_q && reset_n) begin
            if (private_word_req_valid_o) begin
                assert(state_q == ST_REQUEST);
                assert(model_locked_i && !fail_closed_o && !clear_i);
                assert(private_word_req_index_o >=
                       ADDR_W'(METADATA_BASE_WORD));
                assert(private_word_req_index_o <
                       ADDR_W'(METADATA_BASE_WORD + 2328));
            end
            if (metadata_valid_o) begin
                assert(state_q == ST_EMIT);
                assert(current_lane_is_real);
                assert(current_real_record_is_legal);
            end
            if (state_q == ST_DRAIN)
                assert(!private_word_req_valid_o);
            if (state_q == ST_DONE)
                assert(!request_outstanding_q);
            if ($past(fail_closed_q))
                assert(fail_closed_q);
            if ($past(state_q == ST_DRAIN && !response_transfer &&
                      !clear_i))
                assert(state_q == ST_DRAIN || fail_closed_q);
        end
    end
`endif
endmodule

`default_nettype wire
