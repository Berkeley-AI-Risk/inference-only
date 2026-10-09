`timescale 1ns/1ps
`default_nettype none

// Private fixed-geometry causal GQA engine for the selected model.
//
// Geometry is not programmable: 4 query heads, 2 KV heads, head dimension
// 64, context limit 2,048, and q_head -> kv_head is q_head[1].  The only
// multiplier datapath is one already-audited native 16x16 dynamic lane.  It
// is time-shared between Q*K score dots and probability*V dots.
// The cache seam below is an integration-private, derived-address client; it
// is not a public memory or matrix interface and must remain below the fixed
// model controller.
module board1_context2048_attention #(
    parameter EXP_FILE = "model_rtl_evidence/attention_sublayer/exp_neg_q30.memh",
    parameter integer MAX_COMPUTE_CYCLES = 40_000_000
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    clear_i,
    input  wire                    model_lock_i,
    input  wire                    upstream_fault_i,

    input  wire                    start_valid_i,
    output logic                   start_ready_o,
    input  wire [10:0]             fixed_position_i,
    input  wire signed [7:0]       query_exponent_i,

    // Four accepted beats, in hardwired query-head order 0,1,2,3.
    input  wire                    query_valid_i,
    output logic                   query_ready_o,
    input  wire [1023:0]           query_vector_i,
    input  wire                    query_last_i,

    // Private fixed-cache client. Exactly one request may be outstanding.
    // The role comes only from the frozen attention schedule, not the host.
    output logic                   private_cache_request_valid_o,
    output logic [1:0]             private_cache_request_kind_o,
    input  wire                    private_cache_request_ready_i,
    output logic [10:0]            private_cache_request_position_o,
    output logic                   private_cache_request_kv_head_o,
    input  wire                    private_cache_response_valid_i,
    output logic                   private_cache_response_ready_o,
    input  wire [1023:0]           private_cache_response_key_vector_i,
    input  wire signed [7:0]       private_cache_response_key_exponent_i,
    input  wire [1023:0]           private_cache_response_value_vector_i,
    input  wire signed [7:0]       private_cache_response_value_exponent_i,
    input  wire                    private_cache_response_fault_i,

    // Four output beats, again in immutable query-head order.
    output logic                   result_valid_o,
    input  wire                    result_ready_i,
    output logic [1023:0]          result_vector_o,
    output logic signed [7:0]      result_exponent_o,
    output logic                   result_last_o,
    output logic                   done_valid_o,
    input  wire                    done_ready_i,
    output logic                   busy_o,
    output logic                   range_fault_o
);
    localparam signed [63:0] I16_MAXIMUM = 64'sd32767;
    localparam signed [63:0] I16_MINIMUM = -64'sd32767;
    // RNE probability rounding can make the 2,048-entry probability sum at
    // most 32767 + 2048/2.  Thus each post-/32767 head output is bounded by
    // +/-33791 and needs 17 signed bits until the final mixed normalization.
    localparam signed [63:0] HEAD_OUTPUT_MAXIMUM = 64'sd33791;
    localparam signed [63:0] HEAD_OUTPUT_MINIMUM = -64'sd33791;
    localparam signed [38:0] SCORE_MAXIMUM_39 = (39'sd1 <<< 36) - 1'b1;
    localparam signed [38:0] SCORE_MINIMUM_39 = -((39'sd1 <<< 36) - 1'b1);

    function automatic signed [7:0] i16_first_fit_exponent(
        input signed [15:0] mantissa,
        input signed [7:0] source_exponent
    );
        logic [15:0] magnitude;
        integer bit_length;
        integer bit_index;
        integer required;
        begin
            if (mantissa == 0) begin
                i16_first_fit_exponent = -8'sd32;
            end else begin
                magnitude = mantissa[15] ? $unsigned(-mantissa) :
                                           $unsigned(mantissa);
                bit_length = 0;
                for (bit_index = 0; bit_index < 15; bit_index = bit_index + 1)
                    if (magnitude[bit_index]) bit_length = bit_index + 1;
                required = $signed(source_exponent) + bit_length - 15;
                if (required < -32)
                    i16_first_fit_exponent = -8'sd32;
                else if (required > 31)
                    i16_first_fit_exponent = 8'sd31;
                else
                    i16_first_fit_exponent = required[7:0];
            end
        end
    endfunction

    function automatic signed [7:0] i64_first_fit_exponent(
        input signed [63:0] value,
        input signed [7:0] source_exponent
    );
        logic [63:0] magnitude;
        integer bit_length;
        integer bit_index;
        integer wide_required;
        begin
            if (value == 0) begin
                i64_first_fit_exponent = -8'sd32;
            end else begin
                magnitude = value[63] ? $unsigned(-value) : $unsigned(value);
                bit_length = 0;
                for (bit_index = 0; bit_index < 64; bit_index = bit_index + 1)
                    if (magnitude[bit_index]) bit_length = bit_index + 1;
                wide_required = $signed(source_exponent) + bit_length - 15;
                if (wide_required < -32)
                    i64_first_fit_exponent = -8'sd32;
                else if (wide_required > 31)
                    i64_first_fit_exponent = 8'sd31;
                else
                    i64_first_fit_exponent = wide_required[7:0];
            end
        end
    endfunction

    typedef enum logic [5:0] {
        ST_IDLE                = 6'd0,
        ST_QUERY_LOAD          = 6'd1,
        ST_VALUE_EXP_REQUEST   = 6'd2,
        ST_VALUE_EXP_WAIT      = 6'd3,
        ST_SCORE_REQUEST       = 6'd4,
        ST_SCORE_WAIT          = 6'd5,
        ST_SCORE_NORM_FIND     = 6'd6,
        ST_SCORE_NORM_WRITE    = 6'd7,
        ST_SCORE_MAX           = 6'd8,
        ST_EXP                 = 6'd9,
        ST_PROBABILITY_REQUEST = 6'd10,
        ST_PROBABILITY_WAIT    = 6'd11,
        ST_VALUE_ZERO          = 6'd12,
        ST_VALUE_REQUEST       = 6'd13,
        ST_VALUE_WAIT          = 6'd14,
        ST_VALUE_DIV_REQUEST   = 6'd15,
        ST_VALUE_DIV_WAIT      = 6'd16,
        ST_NEXT_HEAD           = 6'd17,
        ST_OUTPUT_NORM_FIND    = 6'd18,
        ST_OUTPUT_NORM_WRITE   = 6'd19,
        ST_RESULT              = 6'd20,
        ST_DONE                = 6'd21,
        ST_EXP_WAIT            = 6'd22,
        ST_VALUE_ALIGN         = 6'd23,
        ST_VALUE_ACCUMULATE    = 6'd24,
        ST_VALUE_EXP_SCAN      = 6'd25,
        ST_SCORE_ACCUMULATE    = 6'd26,
        ST_CLEAR_DRAIN         = 6'd27,
        ST_SHIFT_WAIT          = 6'd28,
        ST_EXP_LUT_REQUEST     = 6'd29,
        ST_NORM_SELECT         = 6'd30,
        ST_FAULT               = 6'd31,
        ST_QUERY_STORE         = 6'd32,
        ST_SCORE_QUERY_USE     = 6'd33,
        ST_RESULT_READ         = 6'd34,
        ST_RESULT_CAPTURE      = 6'd35,
        ST_WORKSPACE_READ      = 6'd36,
        ST_OUTPUT_READ         = 6'd37,
        ST_ALIGN8_WAIT         = 6'd38,
        ST_EXP8_WAIT           = 6'd39,
        ST_NORM_CAPTURE        = 6'd40
    } state_t;

    localparam logic [2:0] SHIFT_CLIENT_VALUE_ALIGN       = 3'd0;
    localparam logic [2:0] SHIFT_CLIENT_SCORE_NORM_FIND   = 3'd1;
    localparam logic [2:0] SHIFT_CLIENT_SCORE_NORM_WRITE  = 3'd2;
    localparam logic [2:0] SHIFT_CLIENT_OUTPUT_NORM_FIND  = 3'd3;
    localparam logic [2:0] SHIFT_CLIENT_OUTPUT_NORM_WRITE = 3'd4;
    localparam logic [2:0] SHIFT_CLIENT_EXP               = 3'd5;

    state_t state_q;
    logic [10:0] position_q;
    logic signed [7:0] query_exponent_q;
    logic [1:0] query_beat_q;
    logic [1:0] attention_head_q;
    logic [10:0] scan_position_q;
    // Shared traversal coordinate: 0..2,047 for attention workspace and
    // 0..255 for the fixed four-head output store.
    logic [10:0] element_q;
    logic [5:0] coordinate_q;
    logic [1:0] result_beat_q;
    logic [31:0] compute_cycles_q;

    // These transient work registers deliberately have no reset or CLEAR data
    // assignment.  Narrow simulation-only validity state below proves that a
    // complete deterministic write precedes every architecturally live read.
    logic [1023:0] query_buffer_q;
    // The 45 live workspace bits occupy three explicit synchronous 2048x18
    // banks.  Every consumer first enters ST_WORKSPACE_READ and only consumes
    // the registered words on the following cycle.  All three banks are
    // overwritten together at a later edge, so no result depends on a block
    // RAM read-during-write mode.
    logic [17:0] workspace_bank0_read_data;
    logic [17:0] workspace_bank1_read_data;
    logic [17:0] workspace_bank2_read_data;
    state_t workspace_read_return_q;
    logic signed [37:0] value_accumulator_q [0:63];
    logic [127:0] aligned_value_groups_q [0:7];
    wire [127:0] aligned_value_selected_group =
        aligned_value_groups_q[coordinate_q[5:3]];
    wire signed [15:0] aligned_value_at_coordinate =
        $signed(aligned_value_selected_group[coordinate_q[2:0]*16 +: 16]);
    localparam logic [1:0] CAPTURE_NONE  = 2'd0;
    localparam logic [1:0] CAPTURE_KEY   = 2'd1;
    localparam logic [1:0] CAPTURE_VALUE = 2'd2;
    logic [1023:0] captured_cache_vector_q;
    logic [1:0] captured_cache_kind_q;
    logic signed [7:0] captured_value_exponent_q;
    logic signed [7:0] value_group_exponent_q [0:1];
    logic [1023:0] result_buffer_q;
    logic signed [7:0] value_align_candidate_q;
    logic value_align_any_nonzero_q;
    logic signed [7:0] value_align_exponent_q;
    logic signed [7:0] score_exponent_q;
    logic signed [15:0] score_max_q;
    // 2,048 nonnegative Q30 terms require 42 bits (maximum 2^41).
    logic [41:0] softmax_denominator_q;
    logic signed [7:0] normalize_candidate_q;
    logic normalize_all_fit_q;
    logic normalize_any_nonzero_q;
    logic normalize_output_q;
    logic signed [7:0] result_exponent_q;
    logic signed [37:0] score_accumulator_q;
    logic signed [7:0] pending_score_exponent_q;
    logic [12:0] exp_index_q;
    logic [2:0] shift_client_q;
    logic signed [15:0] query_bram_read_data;
    logic signed [17:0] output_bram_read_data;
    state_t output_read_return_q;
    logic query_bram_read_enable;
    logic query_bram_write_enable;
    logic [7:0] query_bram_read_address;
    logic [7:0] query_bram_write_address;
    logic signed [15:0] query_bram_write_data;
    logic output_bram_read_enable;
    logic output_bram_write_enable;
    logic [7:0] output_bram_read_address;
    logic [7:0] output_bram_write_address;
    logic signed [17:0] output_bram_write_data;
    logic output_bram_write_raw;
    // Only needed after a fault, because normal wait/drain states themselves
    // encode the one-outstanding invariant.
    logic fault_cache_outstanding_q;
    logic simulation_x_fault;
    logic exp_range_fault;

`ifndef SYNTHESIS
    localparam logic [2:0] WORKSPACE_INVALID = 3'd0;
    localparam logic [2:0] WORKSPACE_RAW     = 3'd1;
    localparam logic [2:0] WORKSPACE_SCORE   = 3'd2;
    localparam logic [2:0] WORKSPACE_EXP     = 3'd3;
    localparam logic [2:0] WORKSPACE_PROB    = 3'd4;
    logic [2:0] workspace_phase_q [0:2047];
    logic signed [36:0] workspace_raw_score_shadow_q [0:2047];
    logic signed [7:0] workspace_raw_exponent_shadow_q [0:2047];
    logic signed [15:0] workspace_score_shadow_q [0:2047];
    logic [30:0] workspace_exp_shadow_q [0:2047];
    logic [15:0] workspace_probability_shadow_q [0:2047];
    localparam logic [1:0] OUTPUT_INVALID = 2'd0;
    localparam logic [1:0] OUTPUT_RAW     = 2'd1;
    localparam logic [1:0] OUTPUT_NORMAL = 2'd2;
    logic [1:0] output_phase_q [0:255];
    logic signed [16:0] output_raw_shadow_q [0:255];
    logic signed [15:0] output_normal_shadow_q [0:255];
    logic workspace_read_valid_q;
    logic [10:0] workspace_read_address_q;
    logic output_read_valid_q;
    logic [7:0] output_read_address_q;
    logic overwrite_query_full_q;
    logic overwrite_key_full_q;
    logic overwrite_value_full_q;
    logic overwrite_accumulators_full_q;
    logic [63:0] overwrite_result_lanes_q;
`endif

    wire cache_request_state = (state_q == ST_VALUE_EXP_REQUEST) ||
                               (state_q == ST_SCORE_REQUEST) ||
                               (state_q == ST_VALUE_REQUEST);
    wire cache_wait_state = (state_q == ST_VALUE_EXP_WAIT) ||
                            (state_q == ST_SCORE_WAIT) ||
                            (state_q == ST_VALUE_WAIT);
    wire cache_drain_state = (state_q == ST_CLEAR_DRAIN);
    wire capture_kind_fault =
        (((state_q == ST_SCORE_ACCUMULATE) ||
          (state_q == ST_SCORE_QUERY_USE)) &&
         (captured_cache_kind_q != CAPTURE_KEY)) ||
        (((state_q == ST_VALUE_EXP_SCAN) ||
          (state_q == ST_VALUE_ALIGN) ||
          (state_q == ST_ALIGN8_WAIT) ||
          (state_q == ST_EXP8_WAIT)) &&
         (captured_cache_kind_q != CAPTURE_VALUE));
`ifndef SYNTHESIS
    // Case equality is deliberate here: an ambiguous response cannot count as
    // a consumed response in four-state verification.
    wire cache_response_known_handshake =
        (private_cache_response_valid_i === 1'b1) &&
        (private_cache_response_ready_o === 1'b1);
`else
    wire cache_response_known_handshake =
        private_cache_response_valid_i && private_cache_response_ready_o;
`endif
    wire interface_live = rst_n && !clear_i && model_lock_i &&
                          !upstream_fault_i && !range_fault_o &&
                          !simulation_x_fault && !exp_range_fault &&
                          !capture_kind_fault &&
                          (compute_cycles_q < MAX_COMPUTE_CYCLES);

    wire workspace_bram_read_enable = interface_live &&
                                      (state_q == ST_WORKSPACE_READ);
    wire [10:0] workspace_bram_read_address =
        (workspace_read_return_q == ST_VALUE_ACCUMULATE)
            ? scan_position_q : element_q;
    wire signed [36:0] workspace_raw_score_at_element = $signed(
        {workspace_bank2_read_data[0], workspace_bank1_read_data,
         workspace_bank0_read_data});
    wire signed [7:0] workspace_raw_exponent_at_element = $signed(
        workspace_bank2_read_data[8:1]);
    wire signed [15:0] workspace_score_at_element = $signed(
        workspace_bank0_read_data[15:0]);
    wire [30:0] workspace_exp_at_element =
        {workspace_bank1_read_data[12:0], workspace_bank0_read_data};
    wire signed [15:0] workspace_probability_at_scan = $signed(
        workspace_bank0_read_data[15:0]);

    logic workspace_bram_write_enable;
    logic [10:0] workspace_bram_write_address;
    logic [17:0] workspace_bank0_write_data;
    logic [17:0] workspace_bank1_write_data;
    logic [17:0] workspace_bank2_write_data;

    always_comb begin
        start_ready_o = interface_live && (state_q == ST_IDLE);
        query_ready_o = interface_live && (state_q == ST_QUERY_LOAD);
        private_cache_request_valid_o = cache_request_state &&
                                        interface_live;
        private_cache_request_kind_o = (state_q == ST_SCORE_REQUEST)
            ? 2'b01 : 2'b10;
        private_cache_request_position_o = scan_position_q;
        private_cache_request_kv_head_o = attention_head_q[1];
        private_cache_response_ready_o = cache_wait_state || cache_drain_state;
        result_valid_o = interface_live && (state_q == ST_RESULT);
        result_vector_o = (state_q == ST_RESULT) ? result_buffer_q : 1024'd0;
        result_exponent_o = (state_q == ST_RESULT) ? result_exponent_q : 8'sd0;
        result_last_o = (state_q == ST_RESULT) && (result_beat_q == 2'd3);
        done_valid_o = interface_live && (state_q == ST_DONE);
        busy_o = (state_q != ST_IDLE) && (state_q != ST_FAULT);
    end

    // Two immutable-role private lanes. The value path no longer feeds
    // the score multiplier/adder/writeback path through a shared input mux.
    // Prime coordinate zero, then prefetch Q/K[n+1] while consuming Q/K[n].
    // The synchronous query RAM and key register update on the same edge.
    // No arithmetic reassociation, extra multiplier, cache request or port.
    wire score_prefetch = (state_q == ST_SCORE_ACCUMULATE) ||
        ((state_q == ST_SCORE_QUERY_USE) && (coordinate_q != 6'd63));
    wire [5:0] score_prefetch_coordinate = (state_q == ST_SCORE_QUERY_USE)
        ? coordinate_q + 6'd1 : coordinate_q;
    logic signed [15:0] score_key_coordinate_q;
    always_ff @(posedge clk) begin
        if (rst_n && score_prefetch)
            score_key_coordinate_q <= $signed(
                captured_cache_vector_q[score_prefetch_coordinate*16 +: 16]);
    end
    wire signed [31:0] score_lane_product;
    wire signed [31:0] score_lane_unused_product;
    board1_unified_projection_head_dynamic_mul_exact u_score_lane (
        .mode_i(2'd3),
        .activation_i(query_bram_read_data),
        .dynamic_operand_i(score_key_coordinate_q),
        .direct_weight_i(10'sd0),
        .coarse_weight0_i(4'sd0),
        .coarse_weight1_i(4'sd0),
        .residual_weight0_i(6'd0),
        .residual_weight1_i(6'd0),
        .product0_o(score_lane_product),
        .product1_o(score_lane_unused_product)
    );
    wire signed [15:0] lane_activation = workspace_probability_at_scan;
    wire signed [15:0] lane_dynamic_operand = aligned_value_at_coordinate;
    wire signed [31:0] selected_lane_product;
    wire signed [31:0] lane_unused_product;
    board1_unified_projection_head_dynamic_mul_exact u_lane (
        .mode_i(2'd3),
        .activation_i(lane_activation),
        .dynamic_operand_i(lane_dynamic_operand),
        .direct_weight_i(10'sd0),
        .coarse_weight0_i(4'sd0),
        .coarse_weight1_i(4'sd0),
        .residual_weight0_i(6'd0),
        .residual_weight1_i(6'd0),
        .product0_o(selected_lane_product),
        .product1_o(lane_unused_product)
    );

    genvar generated_lane;

    // Response legality remains a fail-closed one-cycle acceptance gate.  The
    // expensive value first-fit scan, score reduction, and value accumulation
    // are deliberately serialized after acceptance.  This trades private
    // cycles for two private arithmetic roles without changing any observable
    // handshake or numerical result.
    wire [63:0] response_vector_legal_bits;
    generate
        for (generated_lane = 0; generated_lane < 64;
             generated_lane = generated_lane + 1) begin : g_leaf_checks
            wire signed [15:0] leaf_key = $signed(
                private_cache_response_key_vector_i[
                    generated_lane*16 +: 16]);
            wire signed [15:0] leaf_value = $signed(
                private_cache_response_value_vector_i[
                    generated_lane*16 +: 16]);
            assign response_vector_legal_bits[generated_lane] =
                (leaf_key != -16'sd32768) &&
                (leaf_value != -16'sd32768);
        end
    endgenerate
    wire response_vectors_legal_comb = &response_vector_legal_bits;

    wire [63:0] query_vector_legal_bits;
    generate
        for (generated_lane = 0; generated_lane < 64;
             generated_lane = generated_lane + 1) begin : g_query_checks
            wire signed [15:0] query_leaf = $signed(
                query_vector_i[generated_lane*16 +: 16]);
            assign query_vector_legal_bits[generated_lane] =
                (query_leaf != -16'sd32768);
        end
    endgenerate
    wire query_vector_legal_comb = &query_vector_legal_bits;

    // Highest set bit of OR(magnitudes) is the largest lane bit length.
    // The registered group summary replaces the scalar 64:1 mux path.
    wire [15:0] align8_response_magnitude_or;
    wire signed [15:0] captured_value_coordinate =
        $signed({1'b0, align8_response_magnitude_or[14:0]});
    wire signed [7:0] captured_value_fit_comb =
        i16_first_fit_exponent(captured_value_coordinate,
                               captured_value_exponent_q);
    wire signed [7:0] value_align_candidate_next_comb =
        (captured_value_fit_comb > value_align_candidate_q)
        ? captured_value_fit_comb : value_align_candidate_q;
    wire value_align_any_next_comb = value_align_any_nonzero_q ||
                                     (captured_value_coordinate != 0);
    wire signed [7:0] value_align_final_exponent_comb =
        value_align_any_next_comb ? value_align_candidate_next_comb : 8'sd0;
    wire signed [38:0] score_accumulator_next_comb =
        {{1{score_accumulator_q[37]}}, score_accumulator_q} +
        {{7{score_lane_product[31]}}, score_lane_product};
    wire signed [38:0] value_accumulator_next_comb =
        {{1{value_accumulator_q[coordinate_q][37]}},
         value_accumulator_q[coordinate_q]} +
        {{7{selected_lane_product[31]}}, selected_lane_product};
    wire signed [8:0] raw_score_exponent_comb =
        $signed(query_exponent_q) +
        $signed(private_cache_response_key_exponent_i) - 9'sd3;

    logic signed [63:0] normalize_source_value_comb;
    logic signed [7:0] normalize_source_exponent_comb;
    integer normalize_shift_comb;
    always_comb begin
        if (!normalize_output_q) begin
            normalize_source_value_comb =
                {{27{workspace_raw_score_at_element[36]}},
                 workspace_raw_score_at_element};
            normalize_source_exponent_comb =
                workspace_raw_exponent_at_element;
        end else begin
            normalize_source_value_comb =
                {{47{output_bram_read_data[16]}},
                 output_bram_read_data[16:0]};
            normalize_source_exponent_comb =
                value_group_exponent_q[element_q[7]];
        end
        normalize_shift_comb = $signed(normalize_candidate_q) -
                               $signed(normalize_source_exponent_comb);
    end
    // The extra private stage separates BSRAM/exponent calculation
    // from running maximum/control. No arithmetic function is changed.
    wire signed [7:0] normalize_first_fit_comb;
    wire normalize_source_nonzero_comb;
    board1_attention_norm_candidate_stage u_norm_stage (
        .clk(clk), .reset_n(rst_n), .capture_i(state_q == ST_NORM_CAPTURE),
        .value_i(normalize_source_value_comb),
        .source_exponent_i(normalize_source_exponent_comb),
        .first_fit_o(normalize_first_fit_comb),
        .nonzero_o(normalize_source_nonzero_comb)
    );
    wire normalize_last_comb = normalize_output_q
        ? (element_q == 11'd255)
        : (element_q == position_q);
    wire signed [7:0] normalize_candidate_next_comb =
        (normalize_first_fit_comb > normalize_candidate_q)
        ? normalize_first_fit_comb : normalize_candidate_q;

    logic signed [16:0] score_difference_comb;
    integer softmax_shift_comb;
    logic [30:0] exp_value_comb;
    logic exp_response_valid;
    logic exp_response_fault;
    logic [42:0] denominator_next_comb;
    always_comb begin
        score_difference_comb =
            workspace_score_at_element - $signed(score_max_q);
        softmax_shift_comb = -($signed(score_exponent_q) + 8);
        denominator_next_comb = {1'b0, softmax_denominator_q} +
                                {{12{1'b0}}, exp_value_comb};
    end

    // One iterative RNE shifter services five mutually exclusive private FSM
    // clients.  Its registered request/response boundary removes the former
    // long memory-to-barrel-to-memory path.
    logic shift_request_valid;
    logic shift_request_ready;
    logic signed [63:0] shift_request_value_comb;
    logic signed [8:0] shift_request_amount_comb;
    logic [2:0] shift_request_client_comb;
    logic shift_response_valid;
    logic shift_response_ready;
    logic signed [63:0] shift_response_result;
    logic shift_response_fault;
    always_comb begin
        shift_request_valid = 1'b0;
        shift_request_value_comb = normalize_source_value_comb;
        shift_request_amount_comb = normalize_shift_comb;
        shift_request_client_comb = SHIFT_CLIENT_SCORE_NORM_FIND;
        if (state_q == ST_EXP) begin
            shift_request_valid = interface_live;
            shift_request_value_comb =
                {{47{score_difference_comb[16]}}, score_difference_comb};
            shift_request_amount_comb = softmax_shift_comb;
            shift_request_client_comb = SHIFT_CLIENT_EXP;
        end else if (state_q == ST_SCORE_NORM_FIND) begin
            shift_request_valid = interface_live;
            shift_request_client_comb = SHIFT_CLIENT_SCORE_NORM_FIND;
        end else if (state_q == ST_SCORE_NORM_WRITE) begin
            shift_request_valid = interface_live;
            shift_request_client_comb = SHIFT_CLIENT_SCORE_NORM_WRITE;
        end else if (state_q == ST_OUTPUT_NORM_FIND) begin
            shift_request_valid = interface_live;
            shift_request_client_comb = SHIFT_CLIENT_OUTPUT_NORM_FIND;
        end else if (state_q == ST_OUTPUT_NORM_WRITE) begin
            shift_request_valid = interface_live;
            shift_request_client_comb = SHIFT_CLIENT_OUTPUT_NORM_WRITE;
        end
        shift_response_ready = (state_q == ST_SHIFT_WAIT);
    end
    wire shift_response_sample_fit = !shift_response_fault &&
        (shift_response_result >= I16_MINIMUM) &&
        (shift_response_result <= I16_MAXIMUM) &&
        (shift_response_result != -64'sd32768);

    logic div_request_valid;
    logic div_request_ready;
    logic signed [63:0] div_request_numerator;
    logic [63:0] div_request_denominator;
    logic div_response_valid;
    logic signed [63:0] div_response_result;
    logic div_response_fault;
    logic div_response_ready;

    always_comb begin
        query_bram_read_enable = interface_live && score_prefetch;
        query_bram_read_address = {attention_head_q, score_prefetch_coordinate};
        query_bram_write_enable = interface_live &&
                                  (state_q == ST_QUERY_STORE);
        query_bram_write_address = {query_beat_q, coordinate_q};
        query_bram_write_data = $signed(
            query_buffer_q[coordinate_q*16 +: 16]);

        output_bram_read_enable = interface_live &&
            ((state_q == ST_OUTPUT_READ) || (state_q == ST_RESULT_READ));
        output_bram_read_address = (state_q == ST_OUTPUT_READ)
            ? element_q[7:0] : {result_beat_q, coordinate_q};
        output_bram_write_raw = interface_live &&
            (state_q == ST_VALUE_DIV_WAIT) && div_response_valid &&
            div_response_ready && !div_response_fault &&
            (div_response_result >= HEAD_OUTPUT_MINIMUM) &&
            (div_response_result <= HEAD_OUTPUT_MAXIMUM);
        output_bram_write_enable = output_bram_write_raw ||
            (interface_live && (state_q == ST_SHIFT_WAIT) &&
             shift_response_valid && shift_response_ready &&
             shift_response_sample_fit &&
             (shift_client_q == SHIFT_CLIENT_OUTPUT_NORM_WRITE));
        output_bram_write_address = output_bram_write_raw
            ? {attention_head_q, coordinate_q} : element_q[7:0];
        output_bram_write_data = output_bram_write_raw
            ? {{1{div_response_result[16]}}, div_response_result[16:0]}
            : {{2{shift_response_result[15]}},
               shift_response_result[15:0]};
    end

    board1_context2048_attention_vector256x16 u_query_bram (
        .clk(clk), .read_enable_i(query_bram_read_enable),
        .read_address_i(query_bram_read_address),
        .read_data_o(query_bram_read_data),
        .write_enable_i(query_bram_write_enable),
        .write_address_i(query_bram_write_address),
        .write_data_i(query_bram_write_data)
    );

    board1_context2048_attention_vector256x18 u_output_bram (
        .clk(clk), .read_enable_i(output_bram_read_enable),
        .read_address_i(output_bram_read_address),
        .read_data_o(output_bram_read_data),
        .write_enable_i(output_bram_write_enable),
        .write_address_i(output_bram_write_address),
        .write_data_i(output_bram_write_data)
    );

    board1_context2048_attention_workspace3x18 u_workspace_bram (
        .clk(clk),
        .read_enable_i(workspace_bram_read_enable),
        .read_address_i(workspace_bram_read_address),
        .bank0_read_data_o(workspace_bank0_read_data),
        .bank1_read_data_o(workspace_bank1_read_data),
        .bank2_read_data_o(workspace_bank2_read_data),
        .write_enable_i(workspace_bram_write_enable),
        .write_address_i(workspace_bram_write_address),
        .bank0_write_data_i(workspace_bank0_write_data),
        .bank1_write_data_i(workspace_bank1_write_data),
        .bank2_write_data_i(workspace_bank2_write_data)
    );

    // Eight adjacent coordinates, with no new model/cache/host interface.
    wire align8_request_ready, align8_response_valid, align8_response_fault;
    wire [127:0] align8_response_vector;
    wire signed [8:0] align8_shift = $signed(value_align_exponent_q) -
                                    $signed(captured_value_exponent_q);
    board1_fixed_attention_align8 u_align8 (
        .clk(clk), .rst_n(rst_n), .clear_i(clear_i || (state_q == ST_FAULT)),
        .request_valid_i(interface_live && ((state_q == ST_VALUE_ALIGN) ||
                                             (state_q == ST_VALUE_EXP_SCAN))),
        .request_ready_o(align8_request_ready),
        .request_vector_i(captured_cache_vector_q[coordinate_q[5:3]*128 +: 128]),
        .request_shift_i((state_q == ST_VALUE_EXP_SCAN) ? 9'sd0 : align8_shift),
        .response_valid_o(align8_response_valid),
        .response_ready_i((state_q == ST_ALIGN8_WAIT) || (state_q == ST_EXP8_WAIT)),
        .response_vector_o(align8_response_vector),
        .response_magnitude_or_o(align8_response_magnitude_or),
        .response_fault_o(align8_response_fault)
    );

    board1_fixed_attention_rne_shift_iterative u_shift (
        .clk(clk), .rst_n(rst_n),
        .clear_i(clear_i || (state_q == ST_FAULT)),
        .request_valid_i(shift_request_valid),
        .request_ready_o(shift_request_ready),
        .request_value_i(shift_request_value_comb),
        .request_shift_i(shift_request_amount_comb),
        .response_valid_o(shift_response_valid),
        .response_ready_i(shift_response_ready),
        .response_result_o(shift_response_result),
        .response_fault_o(shift_response_fault)
    );

    board1_fixed_attention_exp_lut_sync #(.FILE(EXP_FILE)) u_exp_lut (
        .clk(clk), .rst_n(rst_n), .clear_i(clear_i),
        .request_valid_i(state_q == ST_EXP_LUT_REQUEST),
        .index_i(exp_index_q),
        .response_valid_o(exp_response_valid),
        .value_o(exp_value_comb),
        .response_fault_o(exp_response_fault),
        .range_fault_o(exp_range_fault)
    );

    wire [45:0] probability_exp_extended =
        {{15{1'b0}}, workspace_exp_at_element};
    wire [45:0] probability_numerator_comb =
        (probability_exp_extended << 15) - probability_exp_extended;
    always_comb begin
        div_request_valid = (state_q == ST_PROBABILITY_REQUEST) ||
                            (state_q == ST_VALUE_DIV_REQUEST);
        if (state_q == ST_PROBABILITY_REQUEST) begin
            div_request_numerator = $signed({18'd0,
                                             probability_numerator_comb});
            div_request_denominator = {22'd0, softmax_denominator_q};
        end else begin
            div_request_numerator =
                {{26{value_accumulator_q[coordinate_q][37]}},
                 value_accumulator_q[coordinate_q]};
            div_request_denominator = 64'd32767;
        end
        div_response_ready = (state_q == ST_PROBABILITY_WAIT) ||
                             (state_q == ST_VALUE_DIV_WAIT);
    end
    board1_fixed_attention_rne_div_signed64 u_divider (
        .clk(clk), .rst_n(rst_n),
        .cancel_i(clear_i || (state_q == ST_FAULT)),
        .request_valid_i(div_request_valid),
        .request_ready_o(div_request_ready),
        .request_numerator_i(div_request_numerator),
        .request_denominator_i(div_request_denominator),
        .response_valid_o(div_response_valid),
        .response_ready_i(div_response_ready),
        .response_result_o(div_response_result),
        .response_fault_o(div_response_fault)
    );

    always_comb begin
        workspace_bram_write_enable = 1'b0;
        workspace_bram_write_address = element_q;
        workspace_bank0_write_data = 18'd0;
        workspace_bank1_write_data = 18'd0;
        workspace_bank2_write_data = 18'd0;

        case (state_q)
            ST_SCORE_QUERY_USE: begin
                if (interface_live && (coordinate_q == 6'd63) &&
                    (score_accumulator_next_comb >= SCORE_MINIMUM_39) &&
                    (score_accumulator_next_comb <= SCORE_MAXIMUM_39)) begin
                    workspace_bram_write_enable = 1'b1;
                    workspace_bram_write_address = scan_position_q;
                    workspace_bank0_write_data =
                        score_accumulator_next_comb[17:0];
                    workspace_bank1_write_data =
                        score_accumulator_next_comb[35:18];
                    workspace_bank2_write_data =
                        {9'd0, pending_score_exponent_q,
                         score_accumulator_next_comb[36]};
                end
            end

            ST_SHIFT_WAIT: begin
                if (interface_live && shift_response_valid &&
                    shift_response_ready && shift_response_sample_fit &&
                    (shift_client_q == SHIFT_CLIENT_SCORE_NORM_WRITE)) begin
                    workspace_bram_write_enable = 1'b1;
                    workspace_bank0_write_data =
                        {2'd0, shift_response_result[15:0]};
                end
            end

            ST_EXP_WAIT: begin
                if (interface_live && exp_response_valid &&
                    !exp_response_fault && (denominator_next_comb != 0) &&
                    !denominator_next_comb[42]) begin
                    workspace_bram_write_enable = 1'b1;
                    workspace_bank0_write_data = exp_value_comb[17:0];
                    workspace_bank1_write_data =
                        {5'd0, exp_value_comb[30:18]};
                end
            end

            ST_PROBABILITY_WAIT: begin
                if (interface_live && div_response_valid &&
                    div_response_ready && !div_response_fault &&
                    (div_response_result >= 0) &&
                    (div_response_result <= 64'sd32767)) begin
                    workspace_bram_write_enable = 1'b1;
                    workspace_bank0_write_data =
                        {2'd0, div_response_result[15:0]};
                end
            end

            default: begin
            end
        endcase
    end

`ifndef SYNTHESIS
    always_comb begin
        simulation_x_fault = ((clear_i !== 1'b0) && (clear_i !== 1'b1)) ||
            ((model_lock_i !== 1'b0) && (model_lock_i !== 1'b1)) ||
            ((upstream_fault_i !== 1'b0) &&
             (upstream_fault_i !== 1'b1)) ||
            ((start_valid_i !== 1'b0) && (start_valid_i !== 1'b1));
        if (state_q == ST_QUERY_LOAD)
            simulation_x_fault = simulation_x_fault ||
                ((query_valid_i !== 1'b0) && (query_valid_i !== 1'b1)) ||
                ((query_last_i !== 1'b0) && (query_last_i !== 1'b1)) ||
                (query_valid_i && (^query_vector_i === 1'bx));
        if ((state_q == ST_IDLE) && (start_valid_i === 1'b1))
            simulation_x_fault = simulation_x_fault ||
                (^fixed_position_i === 1'bx) ||
                (^query_exponent_i === 1'bx);
        if (cache_request_state)
            simulation_x_fault = simulation_x_fault ||
                ((private_cache_request_ready_i !== 1'b0) &&
                 (private_cache_request_ready_i !== 1'b1));
        if (cache_wait_state || cache_drain_state)
            simulation_x_fault = simulation_x_fault ||
                ((private_cache_response_valid_i !== 1'b0) &&
                 (private_cache_response_valid_i !== 1'b1));
        if (cache_wait_state)
            simulation_x_fault = simulation_x_fault ||
                ((private_cache_response_fault_i !== 1'b0) &&
                 (private_cache_response_fault_i !== 1'b1)) ||
                (private_cache_response_valid_i &&
                 ((^private_cache_response_key_vector_i === 1'bx) ||
                  (^private_cache_response_key_exponent_i === 1'bx) ||
                  (^private_cache_response_value_vector_i === 1'bx) ||
                  (^private_cache_response_value_exponent_i === 1'bx)));
        if (state_q == ST_RESULT)
            simulation_x_fault = simulation_x_fault ||
                ((result_ready_i !== 1'b0) && (result_ready_i !== 1'b1));
        if (state_q == ST_DONE)
            simulation_x_fault = simulation_x_fault ||
                ((done_ready_i !== 1'b0) && (done_ready_i !== 1'b1));
    end
`else
    always_comb simulation_x_fault = 1'b0;
`endif

    // Private staging only: this latch does not authorize a response.
    // Capture on the existing response transfer edge without putting the
    // global fault/legality chain on all 1,024 clock enables. The unchanged
    // controller below alone validates kind/exponent/data and advances to a
    // consumer. A rejected or CLEAR-cancelled payload may be copied here,
    // but cannot become live; the next accepted response overwrites it.
    // Keep the upstream private K/V response masking and every validation,
    // ownership, drain, model-lock and publication check unchanged.
    always_ff @(posedge clk) begin
        if (rst_n && cache_wait_state && cache_response_known_handshake) begin
            if (state_q == ST_SCORE_WAIT)
                captured_cache_vector_q <= private_cache_response_key_vector_i;
            else
                captured_cache_vector_q <= private_cache_response_value_vector_i;
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
        end else if (clear_i) begin
        end else if (simulation_x_fault || upstream_fault_i || exp_range_fault ||
                     capture_kind_fault ||
                     ((state_q != ST_IDLE) && !model_lock_i) ||
                     ((state_q != ST_IDLE) &&
                      (compute_cycles_q >= MAX_COMPUTE_CYCLES))) begin
        end else if (state_q == ST_ALIGN8_WAIT) begin
            if (align8_response_valid) begin
                if (align8_response_fault) begin
                end else begin
                            aligned_value_groups_q[coordinate_q[5:3]] <=
                                align8_response_vector;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= ST_IDLE;
            position_q <= 11'd0;
            query_exponent_q <= 8'sd0;
            query_beat_q <= 2'd0;
            attention_head_q <= 2'd0;
            scan_position_q <= 11'd0;
            element_q <= 11'd0;
            coordinate_q <= 6'd0;
            result_beat_q <= 2'd0;
            compute_cycles_q <= 32'd0;
            value_align_candidate_q <= -8'sd32;
            value_align_any_nonzero_q <= 1'b0;
            value_align_exponent_q <= 8'sd0;
            score_exponent_q <= 8'sd0;
            score_max_q <= 16'sd0;
            softmax_denominator_q <= 42'd0;
            normalize_candidate_q <= -8'sd32;
            normalize_all_fit_q <= 1'b1;
            normalize_any_nonzero_q <= 1'b0;
            normalize_output_q <= 1'b0;
            result_exponent_q <= 8'sd0;
            pending_score_exponent_q <= 8'sd0;
            exp_index_q <= 13'd0;
            shift_client_q <= SHIFT_CLIENT_VALUE_ALIGN;
            score_accumulator_q <= 38'sd0;
            fault_cache_outstanding_q <= 1'b0;
            workspace_read_return_q <= ST_FAULT;
            output_read_return_q <= ST_FAULT;
            captured_cache_kind_q <= CAPTURE_NONE;
            captured_value_exponent_q <= 8'sd0;
            value_group_exponent_q[0] <= 8'sd0;
            value_group_exponent_q[1] <= 8'sd0;
            range_fault_o <= 1'b0;
        end else if (clear_i) begin
            if ((cache_wait_state || cache_drain_state ||
                 ((state_q == ST_FAULT) && fault_cache_outstanding_q)) &&
                !cache_response_known_handshake) begin
                state_q <= ST_CLEAR_DRAIN;
            end else begin
                state_q <= ST_IDLE;
            end
            fault_cache_outstanding_q <= 1'b0;
            position_q <= 11'd0;
            query_exponent_q <= 8'sd0;
            query_beat_q <= 2'd0;
            attention_head_q <= 2'd0;
            scan_position_q <= 11'd0;
            element_q <= 11'd0;
            coordinate_q <= 6'd0;
            result_beat_q <= 2'd0;
            compute_cycles_q <= 32'd0;
            value_align_candidate_q <= -8'sd32;
            value_align_any_nonzero_q <= 1'b0;
            value_align_exponent_q <= 8'sd0;
            score_exponent_q <= 8'sd0;
            score_max_q <= 16'sd0;
            softmax_denominator_q <= 42'd0;
            normalize_candidate_q <= -8'sd32;
            normalize_all_fit_q <= 1'b1;
            normalize_any_nonzero_q <= 1'b0;
            normalize_output_q <= 1'b0;
            result_exponent_q <= 8'sd0;
            pending_score_exponent_q <= 8'sd0;
            exp_index_q <= 13'd0;
            shift_client_q <= SHIFT_CLIENT_VALUE_ALIGN;
            score_accumulator_q <= 38'sd0;
            workspace_read_return_q <= ST_FAULT;
            output_read_return_q <= ST_FAULT;
            captured_cache_kind_q <= CAPTURE_NONE;
            captured_value_exponent_q <= 8'sd0;
            value_group_exponent_q[0] <= 8'sd0;
            value_group_exponent_q[1] <= 8'sd0;
            range_fault_o <= 1'b0;
        end else if (simulation_x_fault || upstream_fault_i || exp_range_fault ||
                     capture_kind_fault ||
                     ((state_q != ST_IDLE) && !model_lock_i) ||
                     ((state_q != ST_IDLE) &&
                      (compute_cycles_q >= MAX_COMPUTE_CYCLES))) begin
            state_q <= ST_FAULT;
            range_fault_o <= 1'b1;
            if ((state_q != ST_FAULT) &&
                (cache_wait_state || cache_drain_state) &&
                !cache_response_known_handshake)
                fault_cache_outstanding_q <= 1'b1;
        end else begin
            if (state_q == ST_IDLE)
                compute_cycles_q <= 32'd0;
            else if (state_q != ST_FAULT)
                compute_cycles_q <= compute_cycles_q + 1'b1;

            case (state_q)
                ST_IDLE: begin
                    range_fault_o <= 1'b0;
                    if (start_valid_i && start_ready_o) begin
                        if ((query_exponent_i < -8'sd32) ||
                            (query_exponent_i > 8'sd31)) begin
                            state_q <= ST_FAULT;
                            range_fault_o <= 1'b1;
                        end else begin
                            position_q <= fixed_position_i;
                            query_exponent_q <= query_exponent_i;
                            query_beat_q <= 2'd0;
                            state_q <= ST_QUERY_LOAD;
                        end
                    end
                end

                ST_QUERY_LOAD: begin
                    if (query_valid_i && query_ready_o) begin
                        if (!query_vector_legal_comb ||
                            (query_last_i != (query_beat_q == 2'd3))) begin
                            state_q <= ST_FAULT;
                            range_fault_o <= 1'b1;
                        end else begin
                            query_buffer_q <= query_vector_i;
                            coordinate_q <= 6'd0;
                            state_q <= ST_QUERY_STORE;
                        end
                    end
                end

                ST_QUERY_STORE: begin
                    if (coordinate_q == 6'd63) begin
                        coordinate_q <= 6'd0;
                        if (query_beat_q == 2'd3) begin
                                attention_head_q <= 2'd0;
                                scan_position_q <= 11'd0;
                                value_align_candidate_q <= -8'sd32;
                                value_align_any_nonzero_q <= 1'b0;
                                state_q <= ST_VALUE_EXP_REQUEST;
                        end else begin
                            query_beat_q <= query_beat_q + 1'b1;
                            state_q <= ST_QUERY_LOAD;
                        end
                    end else begin
                        coordinate_q <= coordinate_q + 1'b1;
                    end
                end

                ST_VALUE_EXP_REQUEST: begin
                    if (private_cache_request_valid_o &&
                        private_cache_request_ready_i) begin
                        captured_cache_kind_q <= CAPTURE_NONE;
                        state_q <= ST_VALUE_EXP_WAIT;
                    end
                end

                ST_VALUE_EXP_WAIT: begin
                    if (private_cache_response_valid_i &&
                        private_cache_response_ready_o) begin
                        if (private_cache_response_fault_i ||
                            !response_vectors_legal_comb ||
                            (private_cache_response_value_exponent_i < -8'sd32) ||
                            (private_cache_response_value_exponent_i > 8'sd31)) begin
                            state_q <= ST_FAULT;
                            range_fault_o <= 1'b1;
                        end else begin
                            captured_cache_kind_q <= CAPTURE_VALUE;
                            captured_value_exponent_q <=
                                private_cache_response_value_exponent_i;
                            coordinate_q <= 6'd0;
                            state_q <= ST_VALUE_EXP_SCAN;
                        end
                    end
                end

                ST_VALUE_EXP_SCAN: begin
                    if (interface_live && align8_request_ready)
                        state_q <= ST_EXP8_WAIT;
                end

                ST_EXP8_WAIT: begin
                    if (align8_response_valid) begin
                        if (align8_response_fault || align8_response_magnitude_or[15]) begin
                            state_q <= ST_FAULT;
                            range_fault_o <= 1'b1;
                        end else begin
                            if (captured_value_coordinate != 0) begin
                                value_align_any_nonzero_q <= 1'b1;
                                if (captured_value_fit_comb >
                                    value_align_candidate_q)
                                    value_align_candidate_q <=
                                        captured_value_fit_comb;
                            end
                            if (coordinate_q == 6'd56) begin
                                coordinate_q <= 6'd0;
                                if (scan_position_q == position_q) begin
                                    value_align_exponent_q <=
                                        value_align_final_exponent_comb;
                                    value_group_exponent_q[attention_head_q[1]] <=
                                        value_align_final_exponent_comb;
                                    scan_position_q <= 11'd0;
                                    state_q <= ST_SCORE_REQUEST;
                                end else begin
                                    scan_position_q <= scan_position_q + 1'b1;
                                    state_q <= ST_VALUE_EXP_REQUEST;
                                end
                            end else begin
                                coordinate_q <= coordinate_q + 6'd8;
                                state_q <= ST_VALUE_EXP_SCAN;
                            end
                        end
                    end
                end

                ST_SCORE_REQUEST: begin
                    if (private_cache_request_valid_o &&
                        private_cache_request_ready_i) begin
                        captured_cache_kind_q <= CAPTURE_NONE;
                        state_q <= ST_SCORE_WAIT;
                    end
                end

                ST_SCORE_WAIT: begin
                    if (private_cache_response_valid_i &&
                        private_cache_response_ready_o) begin
                        if (private_cache_response_fault_i ||
                            !response_vectors_legal_comb ||
                            (private_cache_response_key_exponent_i < -8'sd32) ||
                            (private_cache_response_key_exponent_i > 8'sd31)) begin
                            state_q <= ST_FAULT;
                            range_fault_o <= 1'b1;
                        end else begin
                            captured_cache_kind_q <= CAPTURE_KEY;
                            pending_score_exponent_q <=
                                raw_score_exponent_comb[7:0];
                            score_accumulator_q <= 38'sd0;
                            coordinate_q <= 6'd0;
                            state_q <= ST_SCORE_ACCUMULATE;
                        end
                    end
                end

                ST_SCORE_ACCUMULATE: begin
                    state_q <= ST_SCORE_QUERY_USE;
                end

                ST_SCORE_QUERY_USE: begin
                    if (coordinate_q != 6'd63) begin
                        score_accumulator_q <=
                            score_accumulator_next_comb[37:0];
                        coordinate_q <= coordinate_q + 1'b1;
                        state_q <= ST_SCORE_QUERY_USE;
                    end else if ((score_accumulator_next_comb <
                                  SCORE_MINIMUM_39) ||
                                 (score_accumulator_next_comb >
                                  SCORE_MAXIMUM_39)) begin
                        state_q <= ST_FAULT;
                        range_fault_o <= 1'b1;
                    end else begin
                        coordinate_q <= 6'd0;
                        if (scan_position_q == position_q) begin
                            element_q <= 11'd0;
                            normalize_candidate_q <= -8'sd32;
                            normalize_all_fit_q <= 1'b1;
                            normalize_any_nonzero_q <= 1'b0;
                            normalize_output_q <= 1'b0;
                            workspace_read_return_q <= ST_NORM_CAPTURE;
                            state_q <= ST_WORKSPACE_READ;
                        end else begin
                            scan_position_q <= scan_position_q + 1'b1;
                            state_q <= ST_SCORE_REQUEST;
                        end
                    end
                end

                ST_NORM_CAPTURE: begin
                    state_q <= ST_NORM_SELECT;
                end

                ST_NORM_SELECT: begin
                    if (normalize_source_nonzero_comb) begin
                        normalize_any_nonzero_q <= 1'b1;
                        if (normalize_first_fit_comb >
                            normalize_candidate_q)
                            normalize_candidate_q <=
                                normalize_first_fit_comb;
                    end
                    if (normalize_last_comb) begin
                        element_q <= 11'd0;
                        normalize_all_fit_q <= 1'b1;
                        if (!normalize_any_nonzero_q &&
                            !normalize_source_nonzero_comb) begin
                            normalize_candidate_q <= 8'sd0;
                            if (normalize_output_q) begin
                                output_read_return_q <=
                                    ST_OUTPUT_NORM_WRITE;
                                state_q <= ST_OUTPUT_READ;
                            end else begin
                                workspace_read_return_q <=
                                    ST_SCORE_NORM_WRITE;
                                state_q <= ST_WORKSPACE_READ;
                            end
                        end else begin
                            normalize_candidate_q <=
                                normalize_candidate_next_comb;
                            if (normalize_output_q) begin
                                output_read_return_q <= ST_OUTPUT_NORM_FIND;
                                state_q <= ST_OUTPUT_READ;
                            end else begin
                                workspace_read_return_q <= ST_SCORE_NORM_FIND;
                                state_q <= ST_WORKSPACE_READ;
                            end
                        end
                    end else begin
                        element_q <= element_q + 1'b1;
                        if (normalize_output_q) begin
                            output_read_return_q <= ST_NORM_CAPTURE;
                            state_q <= ST_OUTPUT_READ;
                        end else begin
                            workspace_read_return_q <= ST_NORM_CAPTURE;
                            state_q <= ST_WORKSPACE_READ;
                        end
                    end
                end

                ST_WORKSPACE_READ: begin
                    state_q <= workspace_read_return_q;
                end

                ST_OUTPUT_READ: begin
                    state_q <= output_read_return_q;
                end

                ST_SCORE_NORM_FIND,
                ST_SCORE_NORM_WRITE,
                ST_OUTPUT_NORM_FIND,
                ST_OUTPUT_NORM_WRITE,
                ST_EXP: begin
                    if (shift_request_valid && shift_request_ready) begin
                        shift_client_q <= shift_request_client_comb;
                        state_q <= ST_SHIFT_WAIT;
                    end
                end

                ST_SHIFT_WAIT: begin
                    if (shift_response_valid && shift_response_ready) begin
                        if (shift_response_fault) begin
                            state_q <= ST_FAULT;
                            range_fault_o <= 1'b1;
                        end else begin
                          case (shift_client_q)
                            SHIFT_CLIENT_SCORE_NORM_FIND: begin
                                if (!shift_response_sample_fit)
                                    normalize_all_fit_q <= 1'b0;
                                if (element_q == position_q) begin
                                    if (normalize_all_fit_q &&
                                        shift_response_sample_fit) begin
                                        element_q <= 11'd0;
                                        workspace_read_return_q <=
                                            ST_SCORE_NORM_WRITE;
                                        state_q <= ST_WORKSPACE_READ;
                                    end else if (normalize_candidate_q ==
                                                 8'sd31) begin
                                        state_q <= ST_FAULT;
                                        range_fault_o <= 1'b1;
                                    end else begin
                                        normalize_candidate_q <=
                                            normalize_candidate_q + 8'sd1;
                                        normalize_all_fit_q <= 1'b1;
                                        normalize_any_nonzero_q <= 1'b0;
                                        element_q <= 11'd0;
                                        workspace_read_return_q <=
                                            ST_SCORE_NORM_FIND;
                                        state_q <= ST_WORKSPACE_READ;
                                    end
                                end else begin
                                    element_q <= element_q + 1'b1;
                                    workspace_read_return_q <=
                                        ST_SCORE_NORM_FIND;
                                    state_q <= ST_WORKSPACE_READ;
                                end
                            end

                            SHIFT_CLIENT_SCORE_NORM_WRITE: begin
                                if (!shift_response_sample_fit) begin
                                    state_q <= ST_FAULT;
                                    range_fault_o <= 1'b1;
                                end else begin
                                    if (element_q == position_q) begin
                                        score_exponent_q <=
                                            normalize_candidate_q;
                                        element_q <= 11'd0;
                                        score_max_q <= 16'sd0;
                                        workspace_read_return_q <= ST_SCORE_MAX;
                                        state_q <= ST_WORKSPACE_READ;
                                    end else begin
                                        element_q <= element_q + 1'b1;
                                        workspace_read_return_q <=
                                            ST_SCORE_NORM_WRITE;
                                        state_q <= ST_WORKSPACE_READ;
                                    end
                                end
                            end

                            SHIFT_CLIENT_OUTPUT_NORM_FIND: begin
                                if (!shift_response_sample_fit)
                                    normalize_all_fit_q <= 1'b0;
                                if (element_q == 11'd255) begin
                                    if (normalize_all_fit_q &&
                                        shift_response_sample_fit) begin
                                        element_q <= 11'd0;
                                        output_read_return_q <=
                                            ST_OUTPUT_NORM_WRITE;
                                        state_q <= ST_OUTPUT_READ;
                                    end else if (normalize_candidate_q ==
                                                 8'sd31) begin
                                        state_q <= ST_FAULT;
                                        range_fault_o <= 1'b1;
                                    end else begin
                                        normalize_candidate_q <=
                                            normalize_candidate_q + 1'b1;
                                        normalize_all_fit_q <= 1'b1;
                                        normalize_any_nonzero_q <= 1'b0;
                                        element_q <= 11'd0;
                                        output_read_return_q <=
                                            ST_OUTPUT_NORM_FIND;
                                        state_q <= ST_OUTPUT_READ;
                                    end
                                end else begin
                                    element_q <= element_q + 1'b1;
                                    output_read_return_q <=
                                        ST_OUTPUT_NORM_FIND;
                                    state_q <= ST_OUTPUT_READ;
                                end
                            end

                            SHIFT_CLIENT_OUTPUT_NORM_WRITE: begin
                                if (!shift_response_sample_fit) begin
                                    state_q <= ST_FAULT;
                                    range_fault_o <= 1'b1;
                                end else begin
                                    if (element_q == 11'd255) begin
                                        result_exponent_q <=
                                            normalize_candidate_q;
                                        result_beat_q <= 2'd0;
                                        coordinate_q <= 6'd0;
                                        state_q <= ST_RESULT_READ;
                                    end else begin
                                        element_q <= element_q + 1'b1;
                                        output_read_return_q <=
                                            ST_OUTPUT_NORM_WRITE;
                                        state_q <= ST_OUTPUT_READ;
                                    end
                                end
                            end

                            SHIFT_CLIENT_EXP: begin
                                if (shift_response_result > 0) begin
                                    state_q <= ST_FAULT;
                                    range_fault_o <= 1'b1;
                                end else begin
                                    exp_index_q <=
                                        (shift_response_result < -64'sd4096)
                                        ? 13'd4096
                                        : $unsigned(-$signed(
                                            shift_response_result[12:0]));
                                    state_q <= ST_EXP_LUT_REQUEST;
                                end
                            end

                            default: begin
                                state_q <= ST_FAULT;
                                range_fault_o <= 1'b1;
                            end
                          endcase
                        end
                    end
                end

                ST_SCORE_MAX: begin
                    if ((element_q == 0) ||
                        (workspace_score_at_element >
                         $signed(score_max_q)))
                        score_max_q <= workspace_score_at_element;
                    if (element_q == position_q) begin
                        element_q <= 11'd0;
                        softmax_denominator_q <= 42'd0;
                        workspace_read_return_q <= ST_EXP;
                        state_q <= ST_WORKSPACE_READ;
                    end else begin
                        element_q <= element_q + 1'b1;
                        workspace_read_return_q <= ST_SCORE_MAX;
                        state_q <= ST_WORKSPACE_READ;
                    end
                end

                ST_EXP_LUT_REQUEST:
                    state_q <= ST_EXP_WAIT;

                ST_EXP_WAIT: begin
                    if (exp_response_valid) begin
                        if (exp_response_fault ||
                            (denominator_next_comb == 0) ||
                            denominator_next_comb[42]) begin
                            state_q <= ST_FAULT;
                            range_fault_o <= 1'b1;
                        end else begin
                        softmax_denominator_q <= denominator_next_comb[41:0];
                        if (element_q == position_q) begin
                            element_q <= 11'd0;
                            workspace_read_return_q <=
                                ST_PROBABILITY_REQUEST;
                            state_q <= ST_WORKSPACE_READ;
                        end else begin
                            element_q <= element_q + 1'b1;
                            workspace_read_return_q <= ST_EXP;
                            state_q <= ST_WORKSPACE_READ;
                        end
                        end
                    end
                end

                ST_PROBABILITY_REQUEST:
                    if (div_request_valid && div_request_ready)
                        state_q <= ST_PROBABILITY_WAIT;

                ST_PROBABILITY_WAIT: begin
                    if (div_response_valid && div_response_ready) begin
                        if (div_response_fault || (div_response_result < 0) ||
                            (div_response_result > 64'sd32767)) begin
                            state_q <= ST_FAULT;
                            range_fault_o <= 1'b1;
                        end else begin
                            if (element_q == position_q) begin
                                scan_position_q <= 11'd0;
                                coordinate_q <= 6'd0;
                                state_q <= ST_VALUE_ZERO;
                            end else begin
                                element_q <= element_q + 1'b1;
                                workspace_read_return_q <=
                                    ST_PROBABILITY_REQUEST;
                                state_q <= ST_WORKSPACE_READ;
                            end
                        end
                    end
                end

                ST_VALUE_ZERO: begin
                    // One addressed write each cycle: physically implementable
                    // in the same private single-write-port accumulator RAM.
                    // No live use until all 64 coordinates have been cleared.
                    value_accumulator_q[coordinate_q] <= 38'sd0;
                    scan_position_q <= 11'd0;
                    if (coordinate_q == 6'd63) begin
                        coordinate_q <= 6'd0;
                        state_q <= ST_VALUE_REQUEST;
                    end else begin
                        coordinate_q <= coordinate_q + 1'b1;
                    end
                end

                ST_VALUE_REQUEST: begin
                    if (private_cache_request_valid_o &&
                        private_cache_request_ready_i) begin
                        captured_cache_kind_q <= CAPTURE_NONE;
                        state_q <= ST_VALUE_WAIT;
                    end
                end

                ST_VALUE_WAIT: begin
                    if (private_cache_response_valid_i &&
                        private_cache_response_ready_o) begin
                        if (private_cache_response_fault_i ||
                            !response_vectors_legal_comb ||
                            (private_cache_response_value_exponent_i < -8'sd32) ||
                            (private_cache_response_value_exponent_i > 8'sd31)) begin
                            state_q <= ST_FAULT;
                            range_fault_o <= 1'b1;
                        end else begin
                            captured_cache_kind_q <= CAPTURE_VALUE;
                            captured_value_exponent_q <=
                                private_cache_response_value_exponent_i;
                            coordinate_q <= 6'd0;
                            state_q <= ST_VALUE_ALIGN;
                        end
                    end
                end

                ST_VALUE_ALIGN: begin
                    if (interface_live && align8_request_ready)
                        state_q <= ST_ALIGN8_WAIT;
                end

                ST_ALIGN8_WAIT: begin
                    if (align8_response_valid) begin
                        if (align8_response_fault) begin
                            state_q <= ST_FAULT;
                            range_fault_o <= 1'b1;
                        end else begin

                            if (coordinate_q == 6'd56) begin
                                coordinate_q <= 6'd0;
                                workspace_read_return_q <= ST_VALUE_ACCUMULATE;
                                state_q <= ST_WORKSPACE_READ;
                            end else begin
                                coordinate_q <= coordinate_q + 6'd8;
                                state_q <= ST_VALUE_ALIGN;
                            end
                        end
                    end
                end

                ST_VALUE_ACCUMULATE: begin
                    value_accumulator_q[coordinate_q] <=
                        value_accumulator_next_comb[37:0];
                    if (coordinate_q != 6'd63) begin
                        coordinate_q <= coordinate_q + 1'b1;
                    end else if (scan_position_q == position_q) begin
                        coordinate_q <= 6'd0;
                        state_q <= ST_VALUE_DIV_REQUEST;
                    end else begin
                        coordinate_q <= 6'd0;
                        scan_position_q <= scan_position_q + 1'b1;
                        state_q <= ST_VALUE_REQUEST;
                    end
                end

                ST_VALUE_DIV_REQUEST:
                    if (div_request_valid && div_request_ready)
                        state_q <= ST_VALUE_DIV_WAIT;

                ST_VALUE_DIV_WAIT: begin
                    if (div_response_valid && div_response_ready) begin
                        if (div_response_fault ||
                            (div_response_result < HEAD_OUTPUT_MINIMUM) ||
                            (div_response_result > HEAD_OUTPUT_MAXIMUM)) begin
                            state_q <= ST_FAULT;
                            range_fault_o <= 1'b1;
                        end else begin
                            if (coordinate_q == 6'd63) begin
                                state_q <= ST_NEXT_HEAD;
                            end else begin
                                coordinate_q <= coordinate_q + 1'b1;
                                state_q <= ST_VALUE_DIV_REQUEST;
                            end
                        end
                    end
                end

                ST_NEXT_HEAD: begin
                    if (attention_head_q == 2'd3) begin
                        element_q <= 11'd0;
                        normalize_candidate_q <= -8'sd32;
                        normalize_all_fit_q <= 1'b1;
                        normalize_any_nonzero_q <= 1'b0;
                        normalize_output_q <= 1'b1;
                        output_read_return_q <= ST_NORM_CAPTURE;
                        state_q <= ST_OUTPUT_READ;
                    end else begin
                        attention_head_q <= attention_head_q + 1'b1;
                        scan_position_q <= 11'd0;
                        if (attention_head_q == 2'd1) begin
                            value_align_candidate_q <= -8'sd32;
                            value_align_any_nonzero_q <= 1'b0;
                            state_q <= ST_VALUE_EXP_REQUEST;
                        end else begin
                            state_q <= ST_SCORE_REQUEST;
                        end
                    end
                end

                ST_RESULT_READ: begin
                    state_q <= ST_RESULT_CAPTURE;
                end

                ST_RESULT_CAPTURE: begin
                    result_buffer_q[coordinate_q*16 +: 16] <=
                        output_bram_read_data;
                    if (coordinate_q == 6'd63) begin
                        coordinate_q <= 6'd0;
                        state_q <= ST_RESULT;
                    end else begin
                        coordinate_q <= coordinate_q + 1'b1;
                        state_q <= ST_RESULT_READ;
                    end
                end

                ST_RESULT: begin
                    if (result_valid_o && result_ready_i) begin
                        if (result_beat_q == 2'd3) begin
                            state_q <= ST_DONE;
                        end else begin
                            result_beat_q <= result_beat_q + 1'b1;
                            coordinate_q <= 6'd0;
                            state_q <= ST_RESULT_READ;
                        end
                    end
                end

                ST_DONE:
                    if (done_valid_o && done_ready_i)
                        state_q <= ST_IDLE;

                ST_CLEAR_DRAIN: begin
                    range_fault_o <= 1'b0;
                    if (cache_response_known_handshake) begin
                        state_q <= ST_IDLE;
                    end
                end

                ST_FAULT: begin
                    range_fault_o <= 1'b1;
                    state_q <= ST_FAULT;
                end

                default: begin
                    state_q <= ST_FAULT;
                    range_fault_o <= 1'b1;
                end
            endcase
        end
    end

`ifndef SYNTHESIS
    // Executable overwrite-before-use proof obligations for the 6,528 bits
    // whose reset/CLEAR data cones were removed.  These flags are verification
    // state only and disappear from synthesis.  Case inequality and X checks
    // make the obligations fail closed in four-state simulation.
    integer overwrite_check_lane;
    integer workspace_check_index;
    integer output_check_index;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (workspace_check_index = 0; workspace_check_index < 2048;
                 workspace_check_index = workspace_check_index + 1)
                workspace_phase_q[workspace_check_index] <=
                    WORKSPACE_INVALID;
            for (output_check_index = 0; output_check_index < 256;
                 output_check_index = output_check_index + 1)
                output_phase_q[output_check_index] <= OUTPUT_INVALID;
            workspace_read_valid_q <= 1'b0;
            workspace_read_address_q <= 11'd0;
            output_read_valid_q <= 1'b0;
            output_read_address_q <= 8'd0;
            overwrite_query_full_q <= 1'b0;
            overwrite_key_full_q <= 1'b0;
            overwrite_value_full_q <= 1'b0;
            overwrite_accumulators_full_q <= 1'b0;
            overwrite_result_lanes_q <= 64'd0;
        end else if (clear_i || simulation_x_fault || upstream_fault_i ||
                     exp_range_fault ||
                     ((state_q != ST_IDLE) && !model_lock_i) ||
                     ((state_q != ST_IDLE) &&
                      (compute_cycles_q >= MAX_COMPUTE_CYCLES))) begin
            for (workspace_check_index = 0; workspace_check_index < 2048;
                 workspace_check_index = workspace_check_index + 1)
                workspace_phase_q[workspace_check_index] <=
                    WORKSPACE_INVALID;
            for (output_check_index = 0; output_check_index < 256;
                 output_check_index = output_check_index + 1)
                output_phase_q[output_check_index] <= OUTPUT_INVALID;
            workspace_read_valid_q <= 1'b0;
            output_read_valid_q <= 1'b0;
            overwrite_query_full_q <= 1'b0;
            overwrite_key_full_q <= 1'b0;
            overwrite_value_full_q <= 1'b0;
            overwrite_accumulators_full_q <= 1'b0;
            overwrite_result_lanes_q <= 64'd0;
        end else begin
            if ((state_q == ST_IDLE) && start_valid_i && start_ready_o) begin
                for (workspace_check_index = 0;
                     workspace_check_index < 2048;
                     workspace_check_index = workspace_check_index + 1)
                    workspace_phase_q[workspace_check_index] <=
                        WORKSPACE_INVALID;
                for (output_check_index = 0; output_check_index < 256;
                     output_check_index = output_check_index + 1)
                    output_phase_q[output_check_index] <= OUTPUT_INVALID;
                workspace_read_valid_q <= 1'b0;
                output_read_valid_q <= 1'b0;
                overwrite_query_full_q <= 1'b0;
                overwrite_key_full_q <= 1'b0;
                overwrite_value_full_q <= 1'b0;
                overwrite_accumulators_full_q <= 1'b0;
                overwrite_result_lanes_q <= 64'd0;
            end

            if (state_q == ST_WORKSPACE_READ) begin
                workspace_read_valid_q <= 1'b1;
                workspace_read_address_q <= workspace_bram_read_address;
            end
            if ((state_q == ST_OUTPUT_READ) ||
                (state_q == ST_RESULT_READ)) begin
                output_read_valid_q <= 1'b1;
                output_read_address_q <= output_bram_read_address;
            end
            // Registered-read validity is a single-use token, not merely a
            // historical-address flag.  Clients that can stall retain it
            // until their request handshake; the probability word remains
            // live through all 64 coordinate accumulations.
            if (((state_q == ST_NORM_SELECT) && !normalize_output_q) ||
                (state_q == ST_SCORE_MAX) ||
                (((state_q == ST_SCORE_NORM_FIND) ||
                  (state_q == ST_SCORE_NORM_WRITE) ||
                  (state_q == ST_EXP)) &&
                 shift_request_valid && shift_request_ready) ||
                ((state_q == ST_PROBABILITY_REQUEST) &&
                 div_request_valid && div_request_ready) ||
                ((state_q == ST_VALUE_ACCUMULATE) &&
                 (coordinate_q == 6'd63)))
                workspace_read_valid_q <= 1'b0;
            if (((state_q == ST_NORM_SELECT) && normalize_output_q) ||
                (((state_q == ST_OUTPUT_NORM_FIND) ||
                  (state_q == ST_OUTPUT_NORM_WRITE)) &&
                 shift_request_valid && shift_request_ready) ||
                (state_q == ST_RESULT_CAPTURE))
                output_read_valid_q <= 1'b0;

            // Workspace lifetime proof.  Each successful stage transition
            // records an independent shadow.  Consumer-state checks below
            // therefore catch both a stale-phase access and a wrong bit-field
            // decode, while remaining simulation-only.
            if (((state_q == ST_NORM_SELECT) && !normalize_output_q) ||
                (state_q == ST_SCORE_NORM_FIND) ||
                (state_q == ST_SCORE_NORM_WRITE) ||
                (state_q == ST_SCORE_MAX) || (state_q == ST_EXP) ||
                (state_q == ST_PROBABILITY_REQUEST)) begin
                if ((workspace_read_valid_q !== 1'b1) ||
                    (workspace_read_address_q !== element_q))
                    $fatal(1,
                        "workspace BSRAM consume without matching registered read");
            end
            if (state_q == ST_VALUE_ACCUMULATE) begin
                if ((workspace_read_valid_q !== 1'b1) ||
                    (workspace_read_address_q !== scan_position_q))
                    $fatal(1,
                        "workspace probability consume without matching registered read");
            end
            if (((state_q == ST_NORM_SELECT) && normalize_output_q) ||
                (state_q == ST_OUTPUT_NORM_FIND) ||
                (state_q == ST_OUTPUT_NORM_WRITE)) begin
                if ((output_read_valid_q !== 1'b1) ||
                    (output_read_address_q !== element_q))
                    $fatal(1,
                        "output BSRAM consume without matching registered read");
            end

            if ((state_q == ST_SCORE_QUERY_USE) &&
                (coordinate_q == 6'd63) &&
                (score_accumulator_next_comb >= SCORE_MINIMUM_39) &&
                (score_accumulator_next_comb <= SCORE_MAXIMUM_39)) begin
                if ((workspace_phase_q[scan_position_q] !==
                     WORKSPACE_INVALID) &&
                    (workspace_phase_q[scan_position_q] !== WORKSPACE_PROB))
                    $fatal(1,
                        "workspace phase: raw write did not replace invalid/probability");
                workspace_phase_q[scan_position_q] <= WORKSPACE_RAW;
                workspace_raw_score_shadow_q[scan_position_q] <=
                    score_accumulator_next_comb[36:0];
                workspace_raw_exponent_shadow_q[scan_position_q] <=
                    pending_score_exponent_q;
            end

            if ((state_q == ST_NORM_SELECT) && !normalize_output_q) begin
                if (workspace_phase_q[element_q] !== WORKSPACE_RAW)
                    $fatal(1,
                        "workspace phase: raw normalization read before raw write");
                if ((workspace_raw_score_at_element !==
                     workspace_raw_score_shadow_q[element_q]) ||
                    (workspace_raw_exponent_at_element !==
                     workspace_raw_exponent_shadow_q[element_q]))
                    $fatal(1,
                        "workspace field: raw score/exponent decode mismatch");
            end
            if ((state_q == ST_SCORE_NORM_FIND) ||
                (state_q == ST_SCORE_NORM_WRITE)) begin
                if (workspace_phase_q[element_q] !== WORKSPACE_RAW)
                    $fatal(1,
                        "workspace phase: iterative raw read after overwrite");
                if ((workspace_raw_score_at_element !==
                     workspace_raw_score_shadow_q[element_q]) ||
                    (workspace_raw_exponent_at_element !==
                     workspace_raw_exponent_shadow_q[element_q]))
                    $fatal(1,
                        "workspace field: iterative raw decode mismatch");
            end

            if ((state_q == ST_SHIFT_WAIT) && shift_response_valid &&
                shift_response_ready && shift_response_sample_fit &&
                (shift_client_q == SHIFT_CLIENT_SCORE_NORM_WRITE)) begin
                if (workspace_phase_q[element_q] !== WORKSPACE_RAW)
                    $fatal(1,
                        "workspace phase: score write did not replace raw");
                workspace_phase_q[element_q] <= WORKSPACE_SCORE;
                workspace_score_shadow_q[element_q] <=
                    shift_response_result[15:0];
            end

            if ((state_q == ST_SCORE_MAX) || (state_q == ST_EXP)) begin
                if (workspace_phase_q[element_q] !== WORKSPACE_SCORE)
                    $fatal(1,
                        "workspace phase: normalized-score read before score write");
                if (workspace_score_at_element !==
                    workspace_score_shadow_q[element_q])
                    $fatal(1,
                        "workspace field: normalized-score decode mismatch");
            end

            if ((state_q == ST_EXP_WAIT) && exp_response_valid &&
                !exp_response_fault && (denominator_next_comb != 0) &&
                !denominator_next_comb[42]) begin
                if (workspace_phase_q[element_q] !== WORKSPACE_SCORE)
                    $fatal(1,
                        "workspace phase: exponential write did not replace score");
                workspace_phase_q[element_q] <= WORKSPACE_EXP;
                workspace_exp_shadow_q[element_q] <= exp_value_comb;
            end

            if (state_q == ST_PROBABILITY_REQUEST) begin
                if (workspace_phase_q[element_q] !== WORKSPACE_EXP)
                    $fatal(1,
                        "workspace phase: exponential read before exp write");
                if (workspace_exp_at_element !==
                    workspace_exp_shadow_q[element_q])
                    $fatal(1,
                        "workspace field: exponential decode mismatch");
            end

            if ((state_q == ST_PROBABILITY_WAIT) && div_response_valid &&
                div_response_ready && !div_response_fault &&
                (div_response_result >= 0) &&
                (div_response_result <= 64'sd32767)) begin
                if (workspace_phase_q[element_q] !== WORKSPACE_EXP)
                    $fatal(1,
                        "workspace phase: probability write did not replace exp");
                workspace_phase_q[element_q] <= WORKSPACE_PROB;
                workspace_probability_shadow_q[element_q] <=
                    div_response_result[15:0];
            end

            if (state_q == ST_VALUE_ACCUMULATE) begin
                if (workspace_phase_q[scan_position_q] !== WORKSPACE_PROB)
                    $fatal(1,
                        "workspace phase: probability read before probability write");
                if (workspace_probability_at_scan !==
                    $signed(workspace_probability_shadow_q[scan_position_q]))
                    $fatal(1,
                        "workspace field: probability decode mismatch");
            end

            // Output lifetime proof for the in-place 17-bit raw -> 16-bit
            // normalized transition in one 18-bit BSRAM.
            if (output_bram_write_raw) begin
                if (output_phase_q[{attention_head_q, coordinate_q}] !==
                    OUTPUT_INVALID)
                    $fatal(1,
                        "output phase: raw write did not replace invalid");
                output_phase_q[{attention_head_q, coordinate_q}] <=
                    OUTPUT_RAW;
                output_raw_shadow_q[{attention_head_q, coordinate_q}] <=
                    div_response_result[16:0];
            end
            if (((state_q == ST_NORM_SELECT) && normalize_output_q) ||
                (state_q == ST_OUTPUT_NORM_FIND) ||
                (state_q == ST_OUTPUT_NORM_WRITE)) begin
                if (output_phase_q[element_q] !== OUTPUT_RAW)
                    $fatal(1,
                        "output phase: raw normalization read before raw write");
                if ((output_bram_read_data[17] !==
                     output_bram_read_data[16]) ||
                    (output_bram_read_data[16:0] !==
                     output_raw_shadow_q[element_q]))
                    $fatal(1,
                        "output field: raw 17-bit decode mismatch");
            end
            if ((state_q == ST_SHIFT_WAIT) && shift_response_valid &&
                shift_response_ready && shift_response_sample_fit &&
                (shift_client_q == SHIFT_CLIENT_OUTPUT_NORM_WRITE)) begin
                if (output_phase_q[element_q] !== OUTPUT_RAW)
                    $fatal(1,
                        "output phase: normalized write did not replace raw");
                output_phase_q[element_q] <= OUTPUT_NORMAL;
                output_normal_shadow_q[element_q] <=
                    shift_response_result[15:0];
            end
            if (state_q == ST_RESULT_CAPTURE) begin
                if ((output_read_valid_q !== 1'b1) ||
                    (output_read_address_q !==
                     {result_beat_q, coordinate_q}) ||
                    (output_phase_q[{result_beat_q, coordinate_q}] !==
                     OUTPUT_NORMAL) ||
                    (output_bram_read_data[15:0] !==
                     output_normal_shadow_q[
                         {result_beat_q, coordinate_q}]))
                    $fatal(1,
                        "output phase: result consume before normalized overwrite/read");
            end
            if (output_bram_read_enable && output_bram_write_enable)
                $fatal(1,
                    "output BSRAM read/write overlap: read-during-write dependence forbidden");

            if ((state_q == ST_QUERY_LOAD) && query_valid_i &&
                query_ready_o && query_vector_legal_comb &&
                (query_last_i == (query_beat_q == 2'd3)))
                overwrite_query_full_q <= 1'b1;
            if (state_q == ST_QUERY_STORE) begin
                if ((overwrite_query_full_q !== 1'b1) ||
                    (^query_buffer_q === 1'bx))
                    $fatal(1,
                        "overwrite-before-use: query staging read before full write");
                if (coordinate_q == 6'd63)
                    overwrite_query_full_q <= 1'b0;
            end

            if ((state_q == ST_SCORE_REQUEST) &&
                private_cache_request_valid_o &&
                private_cache_request_ready_i)
                overwrite_key_full_q <= 1'b0;
            if ((state_q == ST_SCORE_WAIT) &&
                private_cache_response_valid_i &&
                private_cache_response_ready_o &&
                !private_cache_response_fault_i &&
                response_vectors_legal_comb &&
                (private_cache_response_key_exponent_i >= -8'sd32) &&
                (private_cache_response_key_exponent_i <= 8'sd31) &&
                (raw_score_exponent_comb >= -9'sd128) &&
                (raw_score_exponent_comb <= 9'sd127))
                overwrite_key_full_q <= 1'b1;
            if (state_q == ST_SCORE_QUERY_USE) begin
                if ((overwrite_key_full_q !== 1'b1) ||
                    (captured_cache_kind_q !== CAPTURE_KEY) ||
                    (^captured_cache_vector_q === 1'bx))
                    $fatal(1,
                        "overwrite-before-use: captured key read before full write");
            end

            if (((state_q == ST_VALUE_EXP_REQUEST) ||
                 (state_q == ST_VALUE_REQUEST)) &&
                private_cache_request_valid_o &&
                private_cache_request_ready_i)
                overwrite_value_full_q <= 1'b0;
            if (((state_q == ST_VALUE_EXP_WAIT) ||
                 (state_q == ST_VALUE_WAIT)) &&
                private_cache_response_valid_i &&
                private_cache_response_ready_o &&
                !private_cache_response_fault_i &&
                response_vectors_legal_comb &&
                (private_cache_response_value_exponent_i >= -8'sd32) &&
                (private_cache_response_value_exponent_i <= 8'sd31))
                overwrite_value_full_q <= 1'b1;
            if ((state_q == ST_VALUE_EXP_SCAN) ||
                (state_q == ST_EXP8_WAIT) ||
                (state_q == ST_VALUE_ALIGN)) begin
                if ((overwrite_value_full_q !== 1'b1) ||
                    (captured_cache_kind_q !== CAPTURE_VALUE) ||
                    (^captured_cache_vector_q === 1'bx))
                    $fatal(1,
                        "overwrite-before-use: captured value read before full write");
            end

            if ((state_q == ST_VALUE_ZERO) && (coordinate_q == 6'd63))
                overwrite_accumulators_full_q <= 1'b1;
            if (state_q == ST_NEXT_HEAD)
                overwrite_accumulators_full_q <= 1'b0;
            if ((state_q == ST_VALUE_ACCUMULATE) ||
                (state_q == ST_VALUE_DIV_REQUEST)) begin
                if (overwrite_accumulators_full_q !== 1'b1)
                    $fatal(1,
                        "overwrite-before-use: value accumulator read before zeroing");
                if (^value_accumulator_q[coordinate_q] === 1'bx)
                    $fatal(1,
                        "overwrite-before-use: selected value accumulator is unknown");
            end

            if ((state_q == ST_SHIFT_WAIT) && shift_response_valid &&
                shift_response_ready && shift_response_sample_fit &&
                (shift_client_q == SHIFT_CLIENT_OUTPUT_NORM_WRITE) &&
                (element_q == 11'd255))
                overwrite_result_lanes_q <= 64'd0;
            if (state_q == ST_RESULT_CAPTURE) begin
                if (^output_bram_read_data === 1'bx)
                    $fatal(1,
                        "overwrite-before-use: output BSRAM lane is unknown");
                overwrite_result_lanes_q[coordinate_q] <= 1'b1;
            end
            if (state_q == ST_RESULT) begin
                if ((overwrite_result_lanes_q !== {64{1'b1}}) ||
                    (^result_buffer_q === 1'bx))
                    $fatal(1,
                        "overwrite-before-use: result exposed before all 64 lanes written");
                if (result_valid_o && result_ready_i &&
                    (result_beat_q != 2'd3))
                    overwrite_result_lanes_q <= 64'd0;
            end

            // At the first post-clear use, check both complete coverage and
            // the actual zero values, not merely that old payload is known.
            if ((state_q == ST_VALUE_REQUEST) &&
                (scan_position_q == 11'd0)) begin
                for (overwrite_check_lane = 0; overwrite_check_lane < 64;
                     overwrite_check_lane = overwrite_check_lane + 1)
                    if (value_accumulator_q[overwrite_check_lane] !== 38'sd0)
                        $fatal(1,
                            "overwrite-before-use: accumulator lane %0d not cleared",
                            overwrite_check_lane);
            end
        end
    end
`endif
`ifndef SYNTHESIS
    logic [7:0] aligned_groups_written_q;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            aligned_groups_written_q <= 8'd0;
        else if (clear_i || !model_lock_i || upstream_fault_i ||
                 simulation_x_fault || (state_q == ST_FAULT))
            aligned_groups_written_q <= 8'd0;
        else begin
            if (state_q == ST_VALUE_REQUEST)
                aligned_groups_written_q <= 8'd0;
            if ((state_q == ST_VALUE_ALIGN) || (state_q == ST_ALIGN8_WAIT)) begin
                if ((coordinate_q[2:0] !== 3'd0) ||
                    (captured_cache_kind_q !== CAPTURE_VALUE) ||
                    (overwrite_value_full_q !== 1'b1))
                    $fatal(1, "align8 group is not a validated aligned coordinate");
            end
            if ((state_q == ST_ALIGN8_WAIT) && align8_response_valid &&
                !align8_response_fault) begin
                if (aligned_groups_written_q[coordinate_q[5:3]] !== 1'b0 ||
                    (^align8_response_vector === 1'bx))
                    $fatal(1, "align8 duplicate group or unknown result");
                aligned_groups_written_q[coordinate_q[5:3]] <= 1'b1;
            end
            if (state_q == ST_VALUE_ACCUMULATE) begin
                if (aligned_groups_written_q !== 8'hff ||
                    (^aligned_value_at_coordinate === 1'bx))
                    $fatal(1, "align8 accumulate before all eight groups written");
            end
        end
    end
`endif
`ifndef SYNTHESIS
    logic [7:0] exp_groups_consumed_q;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            exp_groups_consumed_q <= 8'd0;
        else if (clear_i || !model_lock_i || upstream_fault_i ||
                 simulation_x_fault || (state_q == ST_FAULT))
            exp_groups_consumed_q <= 8'd0;
        else begin
            if (state_q == ST_VALUE_EXP_REQUEST)
                exp_groups_consumed_q <= 8'd0;
            if ((state_q == ST_VALUE_EXP_SCAN) || (state_q == ST_EXP8_WAIT)) begin
                if (coordinate_q[2:0] !== 3'd0 ||
                    captured_cache_kind_q !== CAPTURE_VALUE ||
                    overwrite_value_full_q !== 1'b1)
                    $fatal(1,"exp8 group lacks fresh validated input");
            end
            if (state_q == ST_EXP8_WAIT && align8_response_valid &&
                !align8_response_fault) begin
                if ((^align8_response_magnitude_or === 1'bx) ||
                    align8_response_magnitude_or[15] ||
                    exp_groups_consumed_q[coordinate_q[5:3]] !== 1'b0)
                    $fatal(1,"exp8 unknown/illegal/duplicate summary");
                if (coordinate_q == 6'd56 && exp_groups_consumed_q !== 8'h7f)
                    $fatal(1,"exp8 final exponent before seven earlier groups");
                exp_groups_consumed_q[coordinate_q[5:3]] <= 1'b1;
            end
        end
    end
`endif
`ifndef SYNTHESIS
    // Resetless data does not authorize a multiply or write. The unchanged
    // controller owns its use; CLEAR/reset/faults revoke that ownership.
    logic score_key_owned_q;
    logic signed [15:0] score_key_shadow_q;
    logic [5:0] score_key_coordinate_shadow_q;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            score_key_owned_q <= 1'b0;
        else if (!interface_live)
            score_key_owned_q <= 1'b0;
        else begin
            if (score_prefetch) begin
                if (score_key_owned_q !== (state_q == ST_SCORE_QUERY_USE) ||
                    overwrite_key_full_q !== 1'b1 ||
                    captured_cache_kind_q !== CAPTURE_KEY ||
                    (^captured_cache_vector_q === 1'bx))
                    $fatal(1,"score lane capture lacks fresh validated key");
                score_key_owned_q <= 1'b1;
                score_key_shadow_q <= $signed(
                    captured_cache_vector_q[score_prefetch_coordinate*16 +: 16]);
                score_key_coordinate_shadow_q <= score_prefetch_coordinate;
            end
            if (state_q == ST_SCORE_QUERY_USE) begin
                if (score_key_owned_q !== 1'b1 ||
                    score_key_coordinate_q !== score_key_shadow_q ||
                    coordinate_q !== score_key_coordinate_shadow_q ||
                    score_key_coordinate_q !== $signed(
                        captured_cache_vector_q[coordinate_q*16 +: 16]) ||
                    (^score_lane_product === 1'bx))
                    $fatal(1,"score lane used stale/unknown/wrong-coordinate key");
                score_key_owned_q <= score_prefetch;
            end
        end
    end
`endif
`ifndef SYNTHESIS
    // The original memory-phase/knownness assertions at ST_NORM_SELECT
    // remain intact. This adds independent freshness across the new edge.
    logic norm_stage_owned_q;
    logic signed [7:0] norm_stage_fit_shadow_q;
    logic norm_stage_nonzero_shadow_q;
    logic [10:0] norm_stage_element_shadow_q;
    logic norm_stage_output_shadow_q;
    logic signed [63:0] norm_stage_value_shadow_q;
    logic signed [7:0] norm_stage_exponent_shadow_q;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            norm_stage_owned_q <= 1'b0;
        else if (!interface_live)
            norm_stage_owned_q <= 1'b0;
        else begin
            if (state_q == ST_NORM_CAPTURE) begin
                if (norm_stage_owned_q !== 1'b0 ||
                    (^normalize_source_value_comb === 1'bx) ||
                    (^normalize_source_exponent_comb === 1'bx) ||
                    (normalize_output_q ?
                        (output_read_valid_q !== 1'b1 || output_read_address_q !== element_q) :
                        (workspace_read_valid_q !== 1'b1 || workspace_read_address_q !== element_q)))
                    $fatal(1,"norm stage capture lacks fresh known registered read");
                norm_stage_owned_q <= 1'b1;
                norm_stage_fit_shadow_q <= i64_first_fit_exponent(
                    normalize_source_value_comb, normalize_source_exponent_comb);
                norm_stage_nonzero_shadow_q <= (normalize_source_value_comb != 0);
                norm_stage_element_shadow_q <= element_q;
                norm_stage_output_shadow_q <= normalize_output_q;
                norm_stage_value_shadow_q <= normalize_source_value_comb;
                norm_stage_exponent_shadow_q <= normalize_source_exponent_comb;
            end
            if (state_q == ST_NORM_SELECT) begin
                if (norm_stage_owned_q !== 1'b1 ||
                    normalize_first_fit_comb !== norm_stage_fit_shadow_q ||
                    normalize_source_nonzero_comb !== norm_stage_nonzero_shadow_q ||
                    element_q !== norm_stage_element_shadow_q ||
                    normalize_output_q !== norm_stage_output_shadow_q ||
                    normalize_source_value_comb !== norm_stage_value_shadow_q ||
                    normalize_source_exponent_comb !== norm_stage_exponent_shadow_q)
                    $fatal(1,"norm stage consumed stale/wrong-row/wrong-phase payload");
                norm_stage_owned_q <= 1'b0;
            end
        end
    end
`endif
`ifndef SYNTHESIS

    // SCORE_PREFETCH_CHECKER_BEGIN (simulation only)
    logic [255:0] score_query_known_q;
    logic signed [15:0] score_query_shadow_q [0:255];
    logic signed [63:0] score_sum_shadow_q;
    wire signed [15:0] score_expected_query =
        score_query_shadow_q[{attention_head_q,coordinate_q}];
    wire signed [15:0] score_expected_key = $signed(
        captured_cache_vector_q[coordinate_q*16 +: 16]);
    wire signed [31:0] score_expected_product =
        score_expected_query * score_expected_key;
    wire signed [63:0] score_expected_sum = score_sum_shadow_q +
        {{32{score_expected_product[31]}},score_expected_product};
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            score_query_known_q <= 0;
            score_sum_shadow_q <= 0;
        end else if (!interface_live) begin
            score_query_known_q <= 0;
            score_sum_shadow_q <= 0;
        end else begin
            if (query_bram_write_enable) begin
                score_query_known_q[query_bram_write_address] <= 1'b1;
                score_query_shadow_q[query_bram_write_address] <= query_bram_write_data;
            end
            if (query_bram_write_enable && query_bram_read_enable)
                $fatal(1,"score prefetch query read/write overlap");
            if (state_q == ST_SCORE_ACCUMULATE) begin
                if (coordinate_q !== 6'd0)
                    $fatal(1,"score prefetch initial capture not coordinate zero");
                score_sum_shadow_q <= 0;
            end
            if (state_q == ST_SCORE_QUERY_USE) begin
                if (score_query_known_q[{attention_head_q,coordinate_q}] !== 1'b1 ||
                    (^score_expected_query === 1'bx) ||
                    query_bram_read_data !== score_expected_query)
                    $fatal(1,"score prefetch query coordinate/data mismatch");
                if (score_key_coordinate_q !== score_expected_key ||
                    score_lane_product !== score_expected_product)
                    $fatal(1,"score prefetch key/product mismatch");
                if ($signed(score_accumulator_q) !== score_sum_shadow_q ||
                    $signed(score_accumulator_next_comb) !== score_expected_sum)
                    $fatal(1,"score prefetch ordered accumulation mismatch");
                score_sum_shadow_q <= score_expected_sum;
            end
        end
    end
    // SCORE_PREFETCH_CHECKER_END
`endif
endmodule

`default_nettype wire

`timescale 1ns/1ps
`default_nettype none

// Integration-private, fixed eight-coordinate VALUE alignment. This is not
// a host arithmetic port. The parent alone supplies validated model K/V data
// and an exponent difference from its immutable attention schedule.
//
// The arithmetic matches the signed-64 RNE shifter followed by the parent's
// [-32767,32767] fit check, including shifts below -62 faulting even for zero.
// One owned request: capture magnitude/control, calculate, hold until taken.
// Payload registers are resetless; narrow state revokes all data on CLEAR.
module board1_fixed_attention_align8 (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 clear_i,
    input  wire                 request_valid_i,
    output wire                 request_ready_o,
    input  wire [127:0]         request_vector_i,
    input  wire signed [8:0]    request_shift_i,
    output wire                 response_valid_o,
    input  wire                 response_ready_i,
    output wire [127:0]         response_vector_o,
    output wire [15:0]          response_magnitude_or_o,
    output wire                 response_fault_o
);
    localparam [1:0] EMPTY = 2'd0, CALCULATE = 2'd1, HOLD = 2'd2;
    logic [1:0] state_q;
    logic [15:0] magnitude_q [0:7];
    logic [7:0] negative_q;
    logic [3:0] amount_q;
    logic left_q, far_left_q, zero_right_q, bad_shift_q;
    logic [127:0] result_q;
    logic fault_q;
    logic [15:0] magnitude_or_q;
    wire [8:0] unsigned_amount = request_shift_i[8]
        ? $unsigned(-request_shift_i) : $unsigned(request_shift_i);
    wire [7:0] lane_fault;
    wire [127:0] lane_result;

    assign request_ready_o = rst_n && !clear_i && (state_q == EMPTY);
    assign response_valid_o = rst_n && !clear_i && (state_q == HOLD);
    assign response_vector_o = result_q;
    assign response_fault_o = fault_q;
    assign response_magnitude_or_o = magnitude_or_q;

    genvar lane;
    generate for (lane = 0; lane < 8; lane = lane + 1) begin : g_lane
        wire signed [15:0] source_value = $signed(request_vector_i[lane*16 +: 16]);
        // At most 14 legal left shifts; keep all significant bits to detect
        // fit failures rather than truncate into an apparently legal value.
        wire [30:0] left_value = {15'd0, magnitude_q[lane]} << amount_q;
        // Fractional low 16 bits retain guard/sticky information for all
        // nontrivial right shifts (1..15). Larger counts round to zero.
        wire [31:0] right_value = {magnitude_q[lane], 16'd0} >> amount_q;
        wire round_up = right_value[15] &&
            ((|right_value[14:0]) || right_value[16]);
        wire [16:0] right_rounded = {1'b0, right_value[31:16]} +
            {{16{1'b0}}, round_up};
        wire [15:0] magnitude_result = left_q ? left_value[15:0] :
            (zero_right_q ? 16'd0 : right_rounded[15:0]);
        assign lane_fault[lane] = bad_shift_q ||
            (left_q ? ((far_left_q && magnitude_q[lane] != 0) ||
                       (!far_left_q && (|left_value[30:15]))) :
                      (!zero_right_q && (|right_rounded[16:15])));
        assign lane_result[lane*16 +: 16] = lane_fault[lane] ? 16'd0 :
            (negative_q[lane] ? (~magnitude_result + 16'd1) : magnitude_result);
        always_ff @(posedge clk) begin
            if (request_valid_i && request_ready_o) begin
                magnitude_q[lane] <= source_value[15]
                    ? $unsigned(-source_value) : $unsigned(source_value);
                negative_q[lane] <= source_value[15];
            end
        end
    end endgenerate

    always_ff @(posedge clk) begin
        if (request_valid_i && request_ready_o) begin
            amount_q <= unsigned_amount[3:0];
            left_q <= request_shift_i < 0;
            far_left_q <= request_shift_i <= -9'sd15;
            zero_right_q <= request_shift_i >= 9'sd16;
            bad_shift_q <= request_shift_i < -9'sd62;
        end
        if (state_q == CALCULATE) begin
            result_q <= lane_result;
            fault_q <= |lane_fault;
            // Same owner and hold lifetime as the aligned result.
            magnitude_or_q <= magnitude_q[0] | magnitude_q[1] | magnitude_q[2] | magnitude_q[3] | magnitude_q[4] | magnitude_q[5] | magnitude_q[6] | magnitude_q[7];
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state_q <= EMPTY;
        else if (clear_i)
            state_q <= EMPTY;
        else case (state_q)
            EMPTY: if (request_valid_i && request_ready_o) state_q <= CALCULATE;
            CALCULATE: state_q <= HOLD;
            HOLD: if (response_valid_o && response_ready_i) state_q <= EMPTY;
            default: state_q <= EMPTY;
        endcase
    end
endmodule

`default_nettype wire

`timescale 1ns/1ps
`default_nettype none
// Private nine-bit normalization candidate stage.
// Resetless payload never authorizes a result. Only the unchanged
// parent fault/public gates and fresh capture/use states own its use.
module board1_attention_norm_candidate_stage(
    input wire clk, reset_n, capture_i,
    input wire signed [63:0] value_i,
    input wire signed [7:0] source_exponent_i,
    output logic signed [7:0] first_fit_o,
    output logic nonzero_o
);
    function automatic signed [7:0] i64_first_fit_exponent(
        input signed [63:0] value,
        input signed [7:0] source_exponent
    );
        logic [63:0] magnitude;
        integer bit_length;
        integer bit_index;
        integer wide_required;
        begin
            if (value == 0) begin
                i64_first_fit_exponent = -8'sd32;
            end else begin
                magnitude = value[63] ? $unsigned(-value) : $unsigned(value);
                bit_length = 0;
                for (bit_index = 0; bit_index < 64; bit_index = bit_index + 1)
                    if (magnitude[bit_index]) bit_length = bit_index + 1;
                wide_required = $signed(source_exponent) + bit_length - 15;
                if (wide_required < -32)
                    i64_first_fit_exponent = -8'sd32;
                else if (wide_required > 31)
                    i64_first_fit_exponent = 8'sd31;
                else
                    i64_first_fit_exponent = wide_required[7:0];
            end
        end
    endfunction
    always_ff @(posedge clk) begin
        if (reset_n && capture_i) begin
            first_fit_o <= i64_first_fit_exponent(value_i, source_exponent_i);
            nonzero_o <= (value_i != 0);
        end
    end
endmodule
`default_nettype wire
