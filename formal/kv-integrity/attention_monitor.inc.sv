    // Proof-only history. Actual capture, prefetch, aligner, row registers and
    // schedule are retained; numerical results from other children are free.
    (* anyconst *) reg [5:0] f_att_coordinate;
    reg f_att_owned, f_att_valid, f_att_score_valid, f_att_align_owned;
    reg f_att_previous_clear;
    reg [1:0] f_att_kind, f_att_request_kind;
    reg [10:0] f_att_position;
    reg f_att_head;
    reg [1023:0] f_att_vector;
    reg [7:0] f_att_exponent;
    reg [7:0] f_att_query_exponent;
    wire [7:0] f_att_score_exponent = $signed(f_att_query_exponent) + $signed(f_att_exponent) - 8'sd3;
    wire [8:0] f_att_expected_shift = state_q == ST_VALUE_EXP_SCAN ? 9'd0 :
        {value_align_exponent_q[7], value_align_exponent_q} - {f_att_exponent[7], f_att_exponent};
    reg [15:0] f_att_score_value;
    reg [5:0] f_att_score_coordinate;
    reg [7:0] f_att_aligned_mask;
    reg [15:0] f_att_aligned_value;
    wire f_att_request = private_cache_request_valid_o && private_cache_request_ready_i;
    wire f_att_transfer = cache_wait_state && cache_response_known_handshake;
    wire f_att_accept = interface_live && f_att_transfer && !private_cache_response_fault_i &&
        response_vectors_legal_comb && ((state_q == ST_SCORE_WAIT) ?
        ($signed(private_cache_response_key_exponent_i) >= -32 && $signed(private_cache_response_key_exponent_i) <= 31) :
        ($signed(private_cache_response_value_exponent_i) >= -32 && $signed(private_cache_response_value_exponent_i) <= 31));
    wire f_att_key_use = interface_live && (state_q == ST_SCORE_ACCUMULATE || state_q == ST_SCORE_QUERY_USE);
    wire f_att_value_use = interface_live && (state_q == ST_VALUE_EXP_SCAN || state_q == ST_EXP8_WAIT ||
        state_q == ST_VALUE_ALIGN || state_q == ST_ALIGN8_WAIT || state_q == ST_VALUE_ACCUMULATE ||
        (state_q == ST_WORKSPACE_READ && workspace_read_return_q == ST_VALUE_ACCUMULATE));
    wire f_att_align_request = interface_live && align8_request_ready &&
        (state_q == ST_VALUE_EXP_SCAN || state_q == ST_VALUE_ALIGN);
    wire f_att_align_response = align8_response_valid && (state_q == ST_EXP8_WAIT || state_q == ST_ALIGN8_WAIT);
    wire f_att_aligned_write = interface_live && state_q == ST_ALIGN8_WAIT && align8_response_valid && !align8_response_fault;
    // Read the same arbitrary coordinate from the packed eight-value rows.
    // This observation does not constrain or replace the production storage.
    wire [127:0] f_att_observed_group = aligned_value_groups_q[f_att_coordinate[5:3]];
    wire [15:0] f_att_observed_aligned = f_att_observed_group[f_att_coordinate[2:0]*16 +:16];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            f_att_owned <= 0; f_att_valid <= 0; f_att_kind <= 0;
            f_att_request_kind <= 0; f_att_position <= 0; f_att_head <= 0;
            f_att_vector <= 0; f_att_exponent <= 0;
            f_att_query_exponent <= 0;
            f_att_score_valid <= 0; f_att_score_value <= 0; f_att_score_coordinate <= 0;
            f_att_align_owned <= 0; f_att_aligned_mask <= 0; f_att_aligned_value <= 0;
            f_att_previous_clear <= 0;
        end else begin
            f_att_previous_clear <= clear_i;
            if (start_valid_i && start_ready_o && $signed(query_exponent_i) >= -32 && $signed(query_exponent_i) < 32)
                f_att_query_exponent <= query_exponent_i;
            if (f_att_request) begin
                f_att_owned <= 1;
                f_att_request_kind <= private_cache_request_kind_o;
                f_att_position <= private_cache_request_position_o;
                f_att_head <= private_cache_request_kv_head_o;
            end
            if (cache_response_known_handshake) f_att_owned <= 0;
            if (f_att_request || f_att_transfer) f_att_valid <= 0;
            if (f_att_accept) begin
                f_att_valid <= 1;
                f_att_kind <= state_q == ST_SCORE_WAIT ? CAPTURE_KEY : CAPTURE_VALUE;
                f_att_vector <= state_q == ST_SCORE_WAIT ? private_cache_response_key_vector_i : private_cache_response_value_vector_i;
                f_att_exponent <= state_q == ST_SCORE_WAIT ? private_cache_response_key_exponent_i : private_cache_response_value_exponent_i;
            end
            if (score_prefetch) begin
                f_att_score_valid <= f_att_valid && f_att_kind == CAPTURE_KEY;
                f_att_score_value <= f_att_vector[score_prefetch_coordinate*16 +:16];
                f_att_score_coordinate <= score_prefetch_coordinate;
            end
            if (f_att_align_request) f_att_align_owned <= 1;
            if (f_att_align_response) f_att_align_owned <= 0;
            if (f_att_aligned_write) begin
                f_att_aligned_mask[coordinate_q[5:3]] <= 1;
                if (f_att_coordinate[5:3] == coordinate_q[5:3])
                    f_att_aligned_value <= align8_response_vector[f_att_coordinate[2:0]*16 +:16];
            end
            if (f_att_request || f_att_transfer) begin
                f_att_score_valid <= 0;
                f_att_aligned_mask <= 0;
            end
            if (clear_i || state_q == ST_FAULT) begin
                f_att_valid <= 0; f_att_score_valid <= 0;
                f_att_aligned_mask <= 0; f_att_align_owned <= 0;
            end
            if (clear_i) f_att_query_exponent <= 0;
        end
    end

    always_comb begin
        if (rst_n) begin
            assert(state_q <= ST_NORM_CAPTURE);
            assert(!fault_cache_outstanding_q || state_q == ST_FAULT);
            assert(range_fault_o == (state_q == ST_FAULT));
            if (state_q == ST_VALUE_ALIGN || state_q == ST_ALIGN8_WAIT ||
                state_q == ST_VALUE_EXP_SCAN || state_q == ST_EXP8_WAIT)
                assert(coordinate_q[2:0] == 0);
            assert(workspace_read_return_q == ST_FAULT || workspace_read_return_q == ST_NORM_CAPTURE ||
                workspace_read_return_q == ST_SCORE_NORM_FIND || workspace_read_return_q == ST_SCORE_NORM_WRITE ||
                workspace_read_return_q == ST_SCORE_MAX || workspace_read_return_q == ST_EXP ||
                workspace_read_return_q == ST_PROBABILITY_REQUEST || workspace_read_return_q == ST_VALUE_ACCUMULATE);
            assert(output_read_return_q == ST_FAULT || output_read_return_q == ST_NORM_CAPTURE ||
                output_read_return_q == ST_OUTPUT_NORM_FIND || output_read_return_q == ST_OUTPUT_NORM_WRITE);
            assert(f_att_owned == (cache_wait_state || cache_drain_state || (state_q == ST_FAULT && fault_cache_outstanding_q)));
            if (cache_wait_state) begin
                assert(f_att_request_kind == (state_q == ST_SCORE_WAIT ? 1 : 2));
                assert(scan_position_q == f_att_position && attention_head_q[1] == f_att_head);
            end
            if (f_att_valid) assert(captured_cache_vector_q == f_att_vector);
            if (f_att_previous_clear) begin
                assert(!f_att_valid && !f_att_score_valid && f_att_aligned_mask == 0);
                assert(state_q == ST_IDLE || state_q == ST_CLEAR_DRAIN);
            end
            if (clear_i || !model_lock_i || upstream_fault_i || range_fault_o) begin
                assert(!f_att_key_use && !f_att_value_use);
                assert(!private_cache_request_valid_o && !result_valid_o && !done_valid_o);
            end
            if (f_att_key_use) begin
                assert(f_att_valid && f_att_kind == CAPTURE_KEY && captured_cache_kind_q == CAPTURE_KEY);
                assert(scan_position_q == f_att_position && attention_head_q[1] == f_att_head);
                assert(query_exponent_q == f_att_query_exponent);
                assert(pending_score_exponent_q == f_att_score_exponent);
            end
            if (f_att_value_use) begin
                assert(f_att_valid && f_att_kind == CAPTURE_VALUE && captured_cache_kind_q == CAPTURE_VALUE);
                assert(scan_position_q == f_att_position && attention_head_q[1] == f_att_head);
                assert(captured_value_exponent_q == f_att_exponent);
            end
            if (interface_live && state_q == ST_SCORE_QUERY_USE) begin
                assert(f_att_score_valid && f_att_score_coordinate == coordinate_q);
                assert(score_key_coordinate_q == f_att_score_value);
                assert(score_key_coordinate_q == f_att_vector[coordinate_q*16 +:16]);
            end
            if (interface_live && (state_q == ST_ALIGN8_WAIT || state_q == ST_EXP8_WAIT))
                assert(f_att_align_owned);
            if (f_att_align_request) begin
                assert(f_att_valid && f_att_kind == CAPTURE_VALUE);
                assert(f_att_aligner_vector == f_att_vector[coordinate_q[5:3]*128 +:128]);
                assert(f_att_aligner_shift == f_att_expected_shift);
            end
            if (interface_live && state_q != ST_IDLE && state_q != ST_CLEAR_DRAIN)
                assert(query_exponent_q == f_att_query_exponent);
            if (f_att_aligned_mask[f_att_coordinate[5:3]])
                assert(f_att_observed_aligned == f_att_aligned_value);
            if (interface_live && state_q == ST_VALUE_ALIGN)
                assert(f_att_aligned_mask == ((8'b1 << coordinate_q[5:3]) - 1'b1));
            if (interface_live && state_q == ST_ALIGN8_WAIT)
                assert(f_att_aligned_mask == ((8'b1 << coordinate_q[5:3]) - 1'b1));
            if (interface_live && (state_q == ST_VALUE_ACCUMULATE ||
                (state_q == ST_WORKSPACE_READ && workspace_read_return_q == ST_VALUE_ACCUMULATE)))
                assert(f_att_aligned_mask == 8'hff);
            if (interface_live && state_q == ST_VALUE_ACCUMULATE && coordinate_q == f_att_coordinate)
                assert(lane_dynamic_operand == f_att_aligned_value);
        end
    end
