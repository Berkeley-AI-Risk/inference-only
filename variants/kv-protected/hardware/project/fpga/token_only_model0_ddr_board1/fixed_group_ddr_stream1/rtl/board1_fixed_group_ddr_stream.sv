`timescale 1ns/1ps
`default_nettype none

// Fixed-model, one-group-at-a-time DDR stream for Board1.
//
// Each private descriptor is one legal row group of one of the eight frozen
// SimpleStories-V2-5M projections.  The block first reads the group's eight
// projection-metadata words, emits the resulting immutable header, and only
// then reads the exact contiguous weight words for that group.  Consequently
// metadata and weight reads never coexist: the single DDR response channel
// needs no programmable address arbiter or response tag RAM.
//
// fixed_layer_i/fixed_job_i/fixed_group_i are below the sealed transformer
// controller.  They are not public operations.  All word addresses and
// tensor geometries are derived here from the fixed model; there is no write,
// arbitrary address, matrix shape, or arithmetic-mode interface.
module board1_fixed_group_ddr_stream #(
    parameter integer ADDR_W = 25,
    parameter integer METADATA_BASE_WORD = 211920
) (
    input  wire                    clk,
    input  wire                    reset_n,
    input  wire                    clear_i,
    input  wire                    model_locked_i,
    input  wire                    upstream_fail_closed_i,

    input  wire                    start_valid_i,
    output logic                   start_ready_o,
    input  wire [2:0]              fixed_layer_i,
    input  wire [3:0]              fixed_job_i,
    input  wire [5:0]              fixed_group_i,

    output logic                   private_word_req_valid_o,
    input  wire                    private_word_req_ready_i,
    output logic [ADDR_W-1:0]      private_word_req_index_o,
    input  wire                    private_word_rsp_valid_i,
    output logic                   private_word_rsp_ready_o,
    input  wire [255:0]            private_word_rsp_data_i,
    input  wire                    private_word_rsp_fault_i,

    // One immutable header precedes every group's weight stream.
    output logic                   group_valid_o,
    input  wire                    group_ready_i,
    output logic [2:0]             group_layer_o,
    output logic [3:0]             group_job_o,
    output logic [5:0]             group_index_o,
    output logic [6:0]             group_valid_lanes_o,
    output wire [64*8-1:0]         group_row_exponent_o,
    output wire [64*16-1:0]        group_row_multiplier_o,

    output wire [639:0]            weight_data_o,
    output logic                   weight_valid_o,
    input  wire                    weight_ready_i,
    output logic                   weight_last_o,

    output logic                   done_valid_o,
    input  wire                    done_ready_i,
    output logic                   busy_o,
    output logic                   fail_closed_o
);
    localparam logic [2:0] ST_IDLE       = 3'd0;
    localparam logic [2:0] ST_META_START = 3'd1;
    localparam logic [2:0] ST_META_RUN   = 3'd2;
    localparam logic [2:0] ST_HEADER     = 3'd3;
    localparam logic [2:0] ST_WEIGHT     = 3'd4;
    localparam logic [2:0] ST_DONE       = 3'd5;
    localparam logic [2:0] ST_DRAIN      = 3'd6;
    localparam logic [2:0] ST_FAIL       = 3'd7;

    localparam logic [1:0] OWNER_NONE   = 2'd0;
    localparam logic [1:0] OWNER_META   = 2'd1;
    localparam logic [1:0] OWNER_WEIGHT = 2'd2;

    logic [2:0] state_q;
    logic [1:0] owner_q;
    logic [2:0] layer_q;
    logic [3:0] job_q;
    logic [5:0] group_q;
    logic [6:0] valid_lanes_q;
    logic [9:0] group_beats_q;
    logic [10:0] group_words_q;
    logic [ADDR_W-1:0] weight_base_word_q;
    logic [10:0] issued_words_q;
    logic [10:0] consumed_words_q;
    logic [11:0] outstanding_words_q;
    logic [9:0] accepted_beats_q;
    logic [6:0] metadata_count_q;
    logic fail_closed_q;

    logic signed [7:0] row_exponent_q [0:63];
    logic [15:0] row_multiplier_q [0:63];

    logic descriptor_valid;
    logic [6:0] descriptor_groups;
    logic [6:0] descriptor_valid_lanes;
    logic [9:0] descriptor_columns;
    logic [17:0] descriptor_beat_base;
    logic [17:0] descriptor_half_beat_base;
    logic [20:0] descriptor_word_base_wide;

    logic meta_start_valid;
    logic meta_start_ready;
    logic meta_req_valid;
    logic meta_req_ready;
    logic [ADDR_W-1:0] meta_req_index;
    logic meta_rsp_valid;
    logic meta_rsp_ready;
    logic meta_metadata_valid;
    logic meta_metadata_ready;
    logic signed [7:0] meta_exponent;
    logic [15:0] meta_multiplier;
    logic [12:0] meta_row_index;
    logic meta_last;
    logic meta_done_valid;
    logic meta_done_ready;
    logic meta_busy;
    logic meta_fail;

    logic adapter_word_ready;
    logic adapter_weight_valid;
    wire beat_buffer_ready;
    wire beat_buffer_valid;
    wire [639:0] beat_buffer_data;
    logic [639:0] adapter_weight_data;
    logic adapter_pair_boundary;
    wire adapter_reset_n = reset_n && !clear_i &&
                           (state_q == ST_WEIGHT);

    logic weight_request_accept;
    logic weight_response_accept;
    logic weight_accept;
    wire [11:0] outstanding_after_weight_transfers;
    wire outstanding_after_weight_empty;
    board1_private_outstanding_delta u_outstanding_delta (
        .count_i(outstanding_words_q),
        .request_i(weight_request_accept),
        .response_i(weight_response_accept),
        .next_o(outstanding_after_weight_transfers),
        .empty_o(outstanding_after_weight_empty)
    );
    logic metadata_transfer;
    logic meta_done_transfer;
    logic descriptor_transfer;
    logic header_transfer;
    logic done_transfer;

    function automatic [6:0] groups_for_job(input logic [3:0] job);
        case (job)
            4'd0, 4'd3, 4'd6: groups_for_job = 7'd4;
            4'd1, 4'd2:       groups_for_job = 7'd2;
            4'd4, 4'd5:       groups_for_job = 7'd11;
            4'd7:             groups_for_job = 7'd63;
            default:          groups_for_job = 7'd0;
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

    function automatic [6:0] last_group_lanes(input logic [3:0] job);
        case (job)
            4'd4, 4'd5: last_group_lanes = 7'd42;
            4'd7:       last_group_lanes = 7'd51;
            4'd0, 4'd1, 4'd2, 4'd3, 4'd6:
                         last_group_lanes = 7'd64;
            default:    last_group_lanes = 7'd0;
        endcase
    endfunction

    function automatic [13:0] job_beat_offset(input logic [3:0] job);
        case (job)
            4'd0: job_beat_offset = 14'd0;
            4'd1: job_beat_offset = 14'd1024;
            4'd2: job_beat_offset = 14'd1536;
            4'd3: job_beat_offset = 14'd2048;
            4'd4: job_beat_offset = 14'd3072;
            4'd5: job_beat_offset = 14'd5888;
            4'd6: job_beat_offset = 14'd8704;
            default: job_beat_offset = 14'd0;
        endcase
    endfunction

    always_comb begin
        descriptor_groups = groups_for_job(fixed_job_i);
        descriptor_columns = columns_for_job(fixed_job_i);
        descriptor_valid = (descriptor_groups != 7'd0) &&
            ({1'b0, fixed_group_i} < descriptor_groups) &&
            (((fixed_job_i == 4'd7) && (fixed_layer_i == 3'd7)) ||
             ((fixed_job_i < 4'd7) && (fixed_layer_i < 3'd6)));
        descriptor_valid_lanes =
            ({1'b0, fixed_group_i} == (descriptor_groups - 7'd1)) ?
            last_group_lanes(fixed_job_i) : 7'd64;

        if (fixed_job_i == 4'd7) begin
            descriptor_beat_base = 18'd68592 +
                ({12'd0, fixed_group_i} << 8);
        end else begin
            descriptor_beat_base =
                ({15'd0, fixed_layer_i} * 18'd11432) +
                {4'd0, job_beat_offset(fixed_job_i)} +
                ({12'd0, fixed_group_i} *
                 {8'd0, descriptor_columns});
        end
        descriptor_half_beat_base = descriptor_beat_base >> 1;
        descriptor_word_base_wide =
            {3'd0, descriptor_half_beat_base} +
            ({3'd0, descriptor_half_beat_base} << 2);
    end

    genvar lane;
    generate
        for (lane = 0; lane < 64; lane = lane + 1) begin : g_metadata
            assign group_row_exponent_o[lane*8 +: 8] =
                (group_valid_o && (7'(lane) < valid_lanes_q)) ? row_exponent_q[lane] : 8'd0;
            assign group_row_multiplier_o[lane*16 +: 16] =
                (group_valid_o && (7'(lane) < valid_lanes_q)) ? row_multiplier_q[lane] : 16'd0;
        end
    endgenerate

    board1_fixed_projection_metadata_reader #(
        .ADDR_W(ADDR_W),
        .METADATA_BASE_WORD(METADATA_BASE_WORD)
    ) u_metadata_reader (
        .clk(clk), .reset_n(reset_n), .clear_i(clear_i),
        .model_locked_i(model_locked_i),
        .upstream_fail_closed_i(upstream_fail_closed_i || fail_closed_q),
        .start_valid_i(meta_start_valid), .start_ready_o(meta_start_ready),
        .fixed_layer_i(layer_q), .fixed_job_i(job_q),
        .fixed_group_i(group_q),
        .private_word_req_valid_o(meta_req_valid),
        .private_word_req_ready_i(meta_req_ready),
        .private_word_req_index_o(meta_req_index),
        .private_word_rsp_valid_i(meta_rsp_valid),
        .private_word_rsp_ready_o(meta_rsp_ready),
        .private_word_rsp_data_i(private_word_rsp_data_i),
        .private_word_rsp_fault_i(private_word_rsp_fault_i),
        .metadata_valid_o(meta_metadata_valid),
        .metadata_ready_i(meta_metadata_ready),
        .metadata_exponent_o(meta_exponent),
        .metadata_multiplier_o(meta_multiplier),
        .metadata_row_index_o(meta_row_index),
        .metadata_last_o(meta_last),
        .done_valid_o(meta_done_valid), .done_ready_i(meta_done_ready),
        .busy_o(meta_busy), .fail_closed_o(meta_fail)
    );

    board1_private_ddr256_to_w640 u_width_adapter (
        .clk(clk), .reset_n(adapter_reset_n),
        .ddr_word_valid(private_word_rsp_valid_i &&
                        (owner_q == OWNER_WEIGHT) &&
                        (state_q == ST_WEIGHT) && !fail_closed_q &&
                        !upstream_fail_closed_i && !clear_i &&
                        !private_word_rsp_fault_i),
        .ddr_word_ready(adapter_word_ready),
        .ddr_word_data(private_word_rsp_data_i),
        .weight_valid(adapter_weight_valid),
        .weight_ready(beat_buffer_ready && (state_q == ST_WEIGHT) &&
                      !fail_closed_q && !upstream_fail_closed_i),
        .weight_data(adapter_weight_data),
        .pair_boundary(adapter_pair_boundary)
    );

    board1_private_weight_beat_register u_weight_beat_register (
        .clk(clk), .reset_n(adapter_reset_n),
        .in_valid_i(adapter_weight_valid && (state_q == ST_WEIGHT) &&
                    !fail_closed_o && !clear_i),
        .in_ready_o(beat_buffer_ready), .in_data_i(adapter_weight_data),
        .out_valid_o(beat_buffer_valid), .out_ready_i(weight_accept),
        .out_data_o(beat_buffer_data)
    );
    assign weight_data_o = weight_valid_o ? beat_buffer_data : 640'd0;

    always_comb begin
        start_ready_o = (state_q == ST_IDLE) && model_locked_i &&
                        !upstream_fail_closed_i && !fail_closed_q &&
                        !meta_fail && !clear_i;
        busy_o = (state_q != ST_IDLE) && (state_q != ST_FAIL);
        fail_closed_o = fail_closed_q || meta_fail ||
                        upstream_fail_closed_i;

        meta_start_valid = (state_q == ST_META_START) &&
                           (owner_q == OWNER_META) && !fail_closed_o &&
                           !clear_i;
        meta_metadata_ready = (state_q == ST_META_RUN) &&
                              (owner_q == OWNER_META) && !fail_closed_o &&
                              !clear_i;
        meta_done_ready = (state_q == ST_META_RUN) &&
                          (metadata_count_q == valid_lanes_q) &&
                          !fail_closed_o && !clear_i;

        private_word_req_valid_o = 1'b0;
        private_word_req_index_o = {ADDR_W{1'b0}};
        meta_req_ready = 1'b0;
        if ((owner_q == OWNER_META) &&
            ((state_q == ST_META_START) || (state_q == ST_META_RUN))) begin
            private_word_req_valid_o = meta_req_valid;
            private_word_req_index_o = meta_req_index;
            meta_req_ready = private_word_req_ready_i;
        end else if ((owner_q == OWNER_WEIGHT) &&
                     (state_q == ST_WEIGHT) &&
                     (issued_words_q < group_words_q) &&
                     !fail_closed_o && !clear_i) begin
            private_word_req_valid_o = 1'b1;
            private_word_req_index_o = weight_base_word_q +
                                       ADDR_W'(issued_words_q);
        end

        meta_rsp_valid = private_word_rsp_valid_i &&
                         (owner_q == OWNER_META);
        private_word_rsp_ready_o = 1'b0;
        if (owner_q == OWNER_META) begin
            private_word_rsp_ready_o = meta_rsp_ready;
        end else if (owner_q == OWNER_WEIGHT) begin
            if (clear_i || (state_q == ST_DRAIN) ||
                (state_q == ST_FAIL) || private_word_rsp_fault_i)
                private_word_rsp_ready_o = 1'b1;
            else if (state_q == ST_WEIGHT)
                private_word_rsp_ready_o = adapter_word_ready;
        end

        group_valid_o = (state_q == ST_HEADER) && !fail_closed_o &&
                        !clear_i;
        group_layer_o = group_valid_o ? layer_q : 3'd0;
        group_job_o = group_valid_o ? job_q : 4'd0;
        group_index_o = group_valid_o ? group_q : 6'd0;
        group_valid_lanes_o = group_valid_o ? valid_lanes_q : 7'd0;

        weight_valid_o = (state_q == ST_WEIGHT) &&
                         beat_buffer_valid && !fail_closed_o && !clear_i;
        weight_last_o = weight_valid_o &&
                        (accepted_beats_q == (group_beats_q - 10'd1));
        done_valid_o = (state_q == ST_DONE) && !fail_closed_o && !clear_i;

        descriptor_transfer = start_valid_i && start_ready_o;
        metadata_transfer = meta_metadata_valid && meta_metadata_ready;
        meta_done_transfer = meta_done_valid && meta_done_ready;
        header_transfer = group_valid_o && group_ready_i;
        weight_request_accept = private_word_req_valid_o &&
                                private_word_req_ready_i &&
                                (owner_q == OWNER_WEIGHT);
        weight_response_accept = private_word_rsp_valid_i &&
                                 private_word_rsp_ready_o &&
                                 (owner_q == OWNER_WEIGHT);
        weight_accept = weight_valid_o && weight_ready_i;
        done_transfer = done_valid_o && done_ready_i;
    end

`ifndef SYNTHESIS
    logic simulation_x_fault;
    always_comb begin
        simulation_x_fault = $isunknown(clear_i) ||
            $isunknown(model_locked_i) ||
            $isunknown(upstream_fail_closed_i) ||
            $isunknown(start_valid_i) ||
            $isunknown(private_word_req_ready_i) ||
            $isunknown(private_word_rsp_valid_i) ||
            $isunknown(private_word_rsp_fault_i) ||
            $isunknown(group_ready_i) || $isunknown(weight_ready_i) ||
            $isunknown(done_ready_i);
        if (start_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                $isunknown(fixed_layer_i) || $isunknown(fixed_job_i) ||
                $isunknown(fixed_group_i);
        if (private_word_rsp_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                                 $isunknown(private_word_rsp_data_i);
    end
`endif

    // Resetless unpublished metadata. The control/count/validation
    // state still resets and clears exactly as before. Writes on a
    // subsequently rejected record cannot publish a header.
    always_ff @(posedge clk) begin
        if (reset_n && metadata_transfer) begin
            row_exponent_q[metadata_count_q[5:0]] <= meta_exponent;
            row_multiplier_q[metadata_count_q[5:0]] <= meta_multiplier;
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state_q <= ST_IDLE;
            owner_q <= OWNER_NONE;
            layer_q <= 3'd0;
            job_q <= 4'd0;
            group_q <= 6'd0;
            valid_lanes_q <= 7'd0;
            group_beats_q <= 10'd0;
            group_words_q <= 11'd0;
            weight_base_word_q <= {ADDR_W{1'b0}};
            issued_words_q <= 11'd0;
            consumed_words_q <= 11'd0;
            outstanding_words_q <= 12'd0;
            accepted_beats_q <= 10'd0;
            metadata_count_q <= 7'd0;
            fail_closed_q <= 1'b0;
        end else begin
`ifndef SYNTHESIS
            if (simulation_x_fault) begin
                state_q <= ST_FAIL;
                fail_closed_q <= 1'b1;
            end else
`endif
            if ((state_q == ST_FAIL) || fail_closed_q || meta_fail ||
                upstream_fail_closed_i) begin
                state_q <= ST_FAIL;
                fail_closed_q <= 1'b1;
                if ((owner_q == OWNER_WEIGHT) && weight_response_accept)
                    outstanding_words_q <=
                        outstanding_words_q - 12'd1;
            end else if ((private_word_rsp_valid_i &&
                          (owner_q == OWNER_NONE)) ||
                         ((owner_q == OWNER_WEIGHT) &&
                          private_word_rsp_valid_i &&
                          (outstanding_words_q == 12'd0)) ||
                         (weight_response_accept &&
                          private_word_rsp_fault_i)) begin
                state_q <= ST_FAIL;
                fail_closed_q <= 1'b1;
            end else if (clear_i) begin
                issued_words_q <= 11'd0;
                consumed_words_q <= 11'd0;
                accepted_beats_q <= 10'd0;
                metadata_count_q <= 7'd0;
                if ((owner_q == OWNER_WEIGHT) &&
                    !outstanding_after_weight_empty) begin
                    outstanding_words_q <=
                        outstanding_after_weight_transfers;
                    state_q <= ST_DRAIN;
                end else if ((owner_q == OWNER_META) && meta_busy) begin
                    outstanding_words_q <= 12'd0;
                    state_q <= ST_DRAIN;
                end else begin
                    outstanding_words_q <= 12'd0;
                    owner_q <= OWNER_NONE;
                    state_q <= ST_IDLE;
                end
            end else begin
                case (state_q)
                    ST_IDLE: begin
                        owner_q <= OWNER_NONE;
                        issued_words_q <= 11'd0;
                        consumed_words_q <= 11'd0;
                        outstanding_words_q <= 12'd0;
                        accepted_beats_q <= 10'd0;
                        metadata_count_q <= 7'd0;
                        if (descriptor_transfer) begin
                            if (!descriptor_valid ||
                                descriptor_beat_base[0] ||
                                (descriptor_word_base_wide >= 21'd211800) ||
                                ((fixed_job_i == 4'd6) &&
                                 (descriptor_columns != 10'd682)) ||
                                ((fixed_job_i != 4'd6) &&
                                 (descriptor_columns != 10'd256))) begin
                                state_q <= ST_FAIL;
                                fail_closed_q <= 1'b1;
                            end else begin
                                layer_q <= fixed_layer_i;
                                job_q <= fixed_job_i;
                                group_q <= fixed_group_i;
                                valid_lanes_q <= descriptor_valid_lanes;
                                group_beats_q <= descriptor_columns;
                                group_words_q <=
                                    (descriptor_columns == 10'd682) ?
                                    11'd1705 : 11'd640;
                                weight_base_word_q <=
                                    ADDR_W'(descriptor_word_base_wide);
                                owner_q <= OWNER_META;
                                state_q <= ST_META_START;
                            end
                        end
                    end

                    ST_META_START: begin
                        if (meta_start_valid && meta_start_ready)
                            state_q <= ST_META_RUN;
                    end

                    ST_META_RUN: begin
                        if (metadata_transfer) begin
                            if ((metadata_count_q >= valid_lanes_q) ||
                                (meta_row_index !=
                                 (({7'd0, group_q} << 6) +
                                  {6'd0, metadata_count_q})) ||
                                (meta_last !=
                                 (metadata_count_q ==
                                  (valid_lanes_q - 7'd1))) ||
                                (meta_multiplier == 16'd0) ||
                                meta_multiplier[15]) begin
                                state_q <= ST_FAIL;
                                fail_closed_q <= 1'b1;
                            end else begin
                                metadata_count_q <= metadata_count_q + 7'd1;
                            end
                        end
                        if (meta_done_transfer) begin
                            if (metadata_count_q != valid_lanes_q) begin
                                state_q <= ST_FAIL;
                                fail_closed_q <= 1'b1;
                            end else begin
                                owner_q <= OWNER_NONE;
                                state_q <= ST_HEADER;
                            end
                        end
                    end

                    ST_HEADER: begin
                        if (header_transfer) begin
                            issued_words_q <= 11'd0;
                            consumed_words_q <= 11'd0;
                            outstanding_words_q <= 12'd0;
                            accepted_beats_q <= 10'd0;
                            owner_q <= OWNER_WEIGHT;
                            state_q <= ST_WEIGHT;
                        end
                    end

                    ST_WEIGHT: begin
                        outstanding_words_q <=
                            outstanding_after_weight_transfers;
                        if (weight_request_accept)
                            issued_words_q <= issued_words_q + 11'd1;
                        if (weight_response_accept)
                            consumed_words_q <= consumed_words_q + 11'd1;
                        if (weight_accept) begin
                            if (accepted_beats_q ==
                                (group_beats_q - 10'd1)) begin
                                if (!weight_last_o ||
                                    (issued_words_q != group_words_q) ||
                                    // The last external word was accepted
                                    // before this registered beat appears.
                                    (consumed_words_q != group_words_q) ||
                                    weight_response_accept ||
                                    !outstanding_after_weight_empty) begin
                                    state_q <= ST_FAIL;
                                    fail_closed_q <= 1'b1;
                                end else begin
                                    accepted_beats_q <=
                                        accepted_beats_q + 10'd1;
                                    owner_q <= OWNER_NONE;
                                    state_q <= ST_DONE;
                                end
                            end else begin
                                accepted_beats_q <=
                                    accepted_beats_q + 10'd1;
                            end
                        end
                    end

                    ST_DONE: begin
                        if ((accepted_beats_q != group_beats_q) ||
                            (issued_words_q != group_words_q) ||
                            (consumed_words_q != group_words_q) ||
                            (outstanding_words_q != 12'd0) ||
                            !adapter_pair_boundary) begin
                            state_q <= ST_FAIL;
                            fail_closed_q <= 1'b1;
                        end else if (done_transfer) begin
                            metadata_count_q <= 7'd0;
                            state_q <= ST_IDLE;
                        end
                    end

                    ST_DRAIN: begin
                        if (owner_q == OWNER_WEIGHT) begin
                            outstanding_words_q <=
                                outstanding_after_weight_transfers;
                            if (weight_response_accept &&
                                outstanding_after_weight_empty) begin
                                owner_q <= OWNER_NONE;
                                state_q <= ST_IDLE;
                            end
                        end else if ((owner_q == OWNER_META) &&
                                     !meta_busy && meta_start_ready) begin
                            owner_q <= OWNER_NONE;
                            state_q <= ST_IDLE;
                        end else if (owner_q == OWNER_NONE) begin
                            state_q <= ST_IDLE;
                        end
                    end

                    default: begin
                        state_q <= ST_FAIL;
                        fail_closed_q <= 1'b1;
                    end
                endcase
            end
        end
    end

`ifdef FORMAL
    logic formal_past_valid;
    initial formal_past_valid = 1'b0;
    always_ff @(posedge clk) begin
        formal_past_valid <= 1'b1;
        if (reset_n) begin
            if (private_word_req_valid_o) begin
                assert(model_locked_i && !fail_closed_o && !clear_i);
                assert((private_word_req_index_o < ADDR_W'(211800)) ||
                       ((private_word_req_index_o >=
                         ADDR_W'(METADATA_BASE_WORD)) &&
                        (private_word_req_index_o <
                         ADDR_W'(METADATA_BASE_WORD + 2328))));
            end
            assert(!(group_valid_o && weight_valid_o));
            if (weight_valid_o)
                assert(owner_q == OWNER_WEIGHT && state_q == ST_WEIGHT);
            if (group_valid_o)
                assert(metadata_count_q == valid_lanes_q);
            if (state_q == ST_DRAIN)
                assert(!private_word_req_valid_o);
            if (formal_past_valid && $past(fail_closed_q))
                assert(fail_closed_q);
        end
    end
`endif
endmodule

`default_nettype wire

`timescale 1ns/1ps
`default_nettype none

// Private bookkeeping, not an additional machine operation. Both arithmetic
// candidates depend only on the old registered count. Late transfer controls
// select between them; they do not enter a carry chain. The zero decision is
// also selected from old-count predicates rather than recomputed from next.
module board1_private_outstanding_delta (
    input wire [11:0] count_i,
    input wire request_i,
    input wire response_i,
    output logic [11:0] next_o,
    output logic empty_o
);
    (* syn_keep = 1 *) wire [11:0] incremented = count_i + 12'd1;
    (* syn_keep = 1 *) wire [11:0] decremented = count_i - 12'd1;
    wire was_zero = count_i == 12'd0;
    wire was_one = count_i == 12'd1;
    wire was_maximum = count_i == 12'hfff;

    always_comb begin
        case ({request_i, response_i})
            2'b00, 2'b11: begin
                next_o = count_i;
                empty_o = was_zero;
            end
            2'b10: begin
                next_o = incremented;
                empty_o = was_maximum;
            end
            2'b01: begin
                next_o = decremented;
                empty_o = was_one;
            end
            default: begin
                next_o = 12'bx;
                empty_o = 1'bx;
            end
        endcase
        // Preserve the original four-state arithmetic semantics even for a
        // partially unknown old count. This applies in both ordinary and
        // -DSYNTHESIS simulation; it is not a physical unknown-bit detector.
        // synthesis translate_off
        if ($isunknown(count_i) || $isunknown(request_i) ||
            $isunknown(response_i)) begin
            next_o = count_i + {11'd0, request_i} - {11'd0, response_i};
            empty_o = next_o == 12'd0;
        end
        // synthesis translate_on
    end
endmodule

`default_nettype wire

`timescale 1ns/1ps
`default_nettype none

// One integration-private 640-bit beat. Deliberately no fall-through or
// combinational downstream READY -> upstream READY path. The 256-to-640
// converter cannot emit consecutive beats, so one beat per two clocks is
// sufficient at its maximum sustained input rate. CLEAR may revoke this
// already-received payload; outstanding external responses remain owned by
// the parent reader and are drained there.
module board1_private_weight_beat_register (
    input wire clk,
    input wire reset_n,
    input wire in_valid_i,
    output wire in_ready_o,
    input wire [639:0] in_data_i,
    output wire out_valid_o,
    input wire out_ready_i,
    output wire [639:0] out_data_o
);
    logic valid_q;
    logic [639:0] data_q;
    wire push = in_valid_i && in_ready_o;
    wire pop = out_valid_o && out_ready_i;
    assign in_ready_o = !valid_q;
    assign out_valid_o = valid_q;
    assign out_data_o = data_q;
    always_ff @(posedge clk) begin
        if (reset_n && push) data_q <= in_data_i;
    end
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) valid_q <= 1'b0;
        else if (push) valid_q <= 1'b1;
        else if (pop) valid_q <= 1'b0;
    end
endmodule
`default_nettype wire
