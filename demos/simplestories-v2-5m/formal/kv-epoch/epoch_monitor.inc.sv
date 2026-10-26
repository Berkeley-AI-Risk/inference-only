    // Verification-only coordinate selector. It observes actual staging
    // registers and outputs; it cannot drive a production path.
    (* anyconst *) reg [6:0] f_coordinate;
    wire [15:0] f_staged_key = f_coordinate[6] ?
        staged_key_head1_q[f_coordinate[5:0]*16 +: 16] :
        staged_key_head0_q[f_coordinate[5:0]*16 +: 16];
    wire [15:0] f_staged_value = f_coordinate[6] ?
        staged_value_head1_q[f_coordinate[5:0]*16 +: 16] :
        staged_value_head0_q[f_coordinate[5:0]*16 +: 16];
    wire f_begin = !terminal_fault_event && stage_begin_valid_i &&
        stage_begin_ready_o && stage_begin_legal;
    wire f_payload = !terminal_fault_event && stage_payload_valid_i &&
        stage_payload_ready_o && stage_payload_legal;
    wire f_commit = !terminal_fault_event && commit_valid_i &&
        commit_ready_o && commit_legal;
    wire f_attention = attention_req_valid_i && attention_req_ready_o;
    wire f_read_begin = f_attention && !terminal_fault_event &&
        attention_request_legal && !attention_request_pending;
    wire f_read_piece = state_q == ST_READ_WAIT && !clear_i &&
        kv_read_rsp_valid_i && kv_read_rsp_ready_o && !read_aborted_q &&
        !terminal_fault_event && !kv_read_rsp_fault_i;
    wire f_write_piece = state_q == ST_WRITE_WAIT && !clear_i &&
        kv_write_cpl_valid_i && kv_write_cpl_ready_o && !write_aborted_q &&
        !terminal_fault_event && !kv_write_cpl_fault_i;
    reg f_seen;
    reg f_previous_clear;
    reg f_previous_fault;
    reg f_stage_active;
    reg f_stage_filled;
    reg f_coordinate_written;
    reg [15:0] f_expected_key;
    reg [15:0] f_expected_value;
    reg [15:0] f_key_exponents;
    reg [15:0] f_value_exponents;
    reg [4:0] f_completed_writes;
    reg f_attention_owned;
    reg [8:0] f_read_mask;
    reg [2063:0] f_read_expected;
    reg [71:0] f_expected_prefixes;
    wire [2063:0] f_read_bitmask = {{16{f_read_mask[8]}},
        {256{f_read_mask[7]}}, {256{f_read_mask[6]}},
        {256{f_read_mask[5]}}, {256{f_read_mask[4]}},
        {256{f_read_mask[3]}}, {256{f_read_mask[2]}},
        {256{f_read_mask[1]}}, {256{f_read_mask[0]}}};
    wire [8:0] f_required_read_mask = response_kind_q == REQ_KEY_ONLY ?
        9'b100001111 : response_kind_q == REQ_VALUE_ONLY ? 9'b111110000 : 9'b111111111;
    wire [8:0] f_prior_read_mask = ((9'b1 << read_word_q) - 9'b1) & f_required_read_mask;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            f_seen <= 0;
            f_previous_clear <= 0;
            f_previous_fault <= 0;
            f_stage_active <= 0;
            f_stage_filled <= 0;
            f_coordinate_written <= 0;
            f_expected_key <= 0;
            f_expected_value <= 0;
            f_key_exponents <= 0;
            f_value_exponents <= 0;
            f_completed_writes <= 0;
            f_attention_owned <= 0;
            f_read_mask <= 0;
            f_read_expected <= 0;
            f_expected_prefixes <= 0;
        end else begin
            f_seen <= 1;
            f_previous_clear <= clear_i;
            f_previous_fault <= fault_q;
            f_expected_prefixes <= committed_prefixes_o;
            if (f_commit)
                f_expected_prefixes[commit_layer_i*12 +: 12] <=
                    committed_prefix_q[commit_layer_i] + 12'd1;
            if (f_begin) begin
                f_stage_active <= 1;
                f_stage_filled <= 0;
                f_coordinate_written <= 0;
                f_completed_writes <= 0;
                f_key_exponents <= stage_key_exponents_i;
                f_value_exponents <= stage_value_exponents_i;
            end
            if (f_payload) begin
                if (stage_coordinate_i == f_coordinate) begin
                    f_coordinate_written <= 1;
                    f_expected_key <= stage_key_i;
                    f_expected_value <= stage_value_i;
                end
                if (stage_coordinate_i == 7'd127) f_stage_filled <= 1;
            end
            if (f_write_piece) f_completed_writes <= f_completed_writes + 5'd1;
            if (f_commit) begin
                f_stage_active <= 0;
                f_stage_filled <= 0;
                f_completed_writes <= 0;
            end
            if (f_attention) f_attention_owned <= 1;
            if (attention_rsp_valid_o && attention_rsp_ready_i) f_attention_owned <= 0;
            if (f_read_begin) begin
                f_read_mask <= 0;
                f_read_expected <= 0;
            end
            if (f_read_piece) begin
                f_read_mask[read_word_q] <= 1;
                case (read_word_q)
                    0: f_read_expected[255:0] <= kv_read_rsp_data_i;
                    1: f_read_expected[511:256] <= kv_read_rsp_data_i;
                    2: f_read_expected[767:512] <= kv_read_rsp_data_i;
                    3: f_read_expected[1023:768] <= kv_read_rsp_data_i;
                    4: f_read_expected[1279:1024] <= kv_read_rsp_data_i;
                    5: f_read_expected[1535:1280] <= kv_read_rsp_data_i;
                    6: f_read_expected[1791:1536] <= kv_read_rsp_data_i;
                    7: f_read_expected[2047:1792] <= kv_read_rsp_data_i;
                    8: f_read_expected[2063:2048] <= kv_read_rsp_data_i[15:0];
                    default: begin end
                endcase
            end
            if (clear_i) begin
                f_stage_active <= 0;
                f_stage_filled <= 0;
                f_coordinate_written <= 0;
                f_completed_writes <= 0;
                f_read_mask <= 0;
                f_read_expected <= 0;
                f_expected_prefixes <= 0;
            end
        end
    end

    always_comb begin
        if (reset_n) begin
            assert(state_q <= ST_RESPONSE);
            assert(write_word_q <= 8 && read_word_q <= 8);
            if (state_q == ST_WRITE_REQ) assert(!write_aborted_q);
            if (state_q == ST_READ_REQ) assert(!read_aborted_q && !response_fault_q);
            if (state_q == ST_READ_WAIT) assert(!response_fault_q);
            assert(committed_prefix_q[0] <= 2048 && committed_prefix_q[1] <= 2048 &&
                   committed_prefix_q[2] <= 2048 && committed_prefix_q[3] <= 2048 &&
                   committed_prefix_q[4] <= 2048 && committed_prefix_q[5] <= 2048);
            if (!f_seen) assert(state_q == ST_IDLE && committed_prefixes_o == 0 && !pending_persisted_q);
            if (f_seen) assert(committed_prefixes_o == f_expected_prefixes);
            if (f_previous_fault) assert(fault_q);
            if (f_previous_clear) begin
                assert(committed_prefixes_o == 0 && !pending_persisted_q);
                assert(!f_stage_active && !f_stage_filled && !f_coordinate_written && f_read_mask == 0);
            end
            if (clear_i || fault_q) begin
                assert(!stage_begin_ready_o && !stage_payload_ready_o && !commit_ready_o && !attention_req_ready_o);
                assert(!kv_write_req_valid_o && !kv_read_req_valid_o);
            end
            if (attention_rsp_valid_o) assert(f_attention_owned);
            assert(f_attention_owned == (state_q == ST_READ_REQ || state_q == ST_READ_WAIT || state_q == ST_RESPONSE));
            if (attention_rsp_fault_o)
                assert(attention_rsp_key_vector_o == 0 && attention_rsp_value_vector_o == 0 &&
                       attention_rsp_key_exponent_o == 0 && attention_rsp_value_exponent_o == 0);
            assert((assembled_row_q & f_read_bitmask) == (f_read_expected & f_read_bitmask));
            if (!fault_q && !terminal_fault_event) begin
                if (state_q == ST_IDLE) assert(!pending_persisted_q && !f_stage_active);
                if (state_q == ST_PENDING) assert(pending_persisted_q);
                if (state_q == ST_STAGE) assert(f_stage_active && !f_stage_filled);
                if (state_q == ST_STAGE) assert(f_completed_writes == 0);
                if (state_q == ST_WRITE_WAIT && write_aborted_q)
                    assert(!f_stage_active && !f_stage_filled && f_completed_writes == 0);
                if (state_q == ST_READ_WAIT && read_aborted_q)
                    assert(!f_stage_active && !f_stage_filled && !pending_persisted_q);
                if (state_q == ST_RESPONSE && response_fault_q)
                    assert(!f_stage_active && !f_stage_filled && !pending_persisted_q);
                if (f_stage_active) begin
                    assert(pending_layer_q < 6 && pending_position_q < 2048);
                    assert(pending_key_exponents_q == f_key_exponents && pending_value_exponents_q == f_value_exponents);
                    assert(pending_position_q == committed_prefix_q[pending_layer_q]);
                end
                if (f_coordinate_written) begin
                    assert(f_staged_key == f_expected_key);
                    assert(f_staged_value == f_expected_value);
                end
                if (state_q == ST_STAGE && f_coordinate < expected_coordinate_q)
                    assert(f_coordinate_written);
                if (f_stage_filled) assert(f_coordinate_written);
                if ((state_q == ST_WRITE_REQ || state_q == ST_WRITE_WAIT) && !write_aborted_q) begin
                    assert(f_stage_active && f_stage_filled);
                    assert(f_completed_writes == (write_head_q ? 5'd9 : 5'd0) + {1'b0, write_word_q});
                end
                if (pending_persisted_q) begin
                    assert(f_stage_active && f_stage_filled && f_completed_writes == 18);
                    assert(pending_layer_q < 6 && pending_position_q < 2048);
                    assert(pending_key_exponents_q == f_key_exponents && pending_value_exponents_q == f_value_exponents);
                    assert(pending_position_q == committed_prefix_q[pending_layer_q]);
                end
                if ((state_q == ST_READ_REQ || state_q == ST_READ_WAIT) && !read_aborted_q && !response_fault_q) begin
                    assert(pending_persisted_q && f_stage_filled && !response_from_pending_q);
                    assert(response_kind_q <= REQ_VALUE_ONLY);
                    assert(response_position_q < committed_prefix_q[pending_layer_q]);
                    assert((f_read_mask & f_prior_read_mask) == f_prior_read_mask);
                    if (response_kind_q == REQ_KEY_ONLY) assert(read_word_q < 4 || read_word_q == 8);
                    if (response_kind_q == REQ_VALUE_ONLY) assert(read_word_q >= 4);
                end
            end
            if (kv_write_req_valid_o) begin
                assert(kv_write_req_shadow_address_o >= 227072 && kv_write_req_shadow_address_o < 448256);
                if (kv_write_req_head_o[0] == f_coordinate[6]) begin
                    if (write_word_q < 4 && write_word_q[1:0] == f_coordinate[5:4])
                        assert(kv_write_req_data_o[f_coordinate[3:0]*16 +: 16] == f_expected_key);
                    if (write_word_q >= 4 && write_word_q < 8 && write_word_q[1:0] == f_coordinate[5:4])
                        assert(kv_write_req_data_o[f_coordinate[3:0]*16 +: 16] == f_expected_value);
                end
                if (write_word_q == 8) assert(kv_write_req_data_o[255:16] == 0);
            end
            if (kv_read_req_valid_o) begin
                assert(kv_read_req_shadow_address_o >= 227072 && kv_read_req_shadow_address_o < 448256);
                assert(response_position_q < committed_prefix_q[pending_layer_q]);
            end
            if (attention_rsp_valid_o && !attention_rsp_fault_o) begin
                assert(pending_persisted_q && f_stage_filled);
                assert(response_kind_q <= REQ_VALUE_ONLY);
                if (response_from_pending_q) begin
                    assert(response_position_q == pending_position_q);
                    if (response_head_q == f_coordinate[6]) begin
                        if (response_kind_q != REQ_VALUE_ONLY)
                            assert(attention_rsp_key_vector_o[f_coordinate[5:0]*16 +: 16] == f_expected_key);
                        if (response_kind_q != REQ_KEY_ONLY)
                            assert(attention_rsp_value_vector_o[f_coordinate[5:0]*16 +: 16] == f_expected_value);
                    end
                end else begin
                    assert((f_read_mask & f_required_read_mask) == f_required_read_mask);
                    if (response_kind_q != REQ_VALUE_ONLY)
                        assert(attention_rsp_key_vector_o == f_read_expected[1023:0] &&
                               attention_rsp_key_exponent_o == f_read_expected[2055:2048]);
                    if (response_kind_q != REQ_KEY_ONLY)
                        assert(attention_rsp_value_vector_o == f_read_expected[2047:1024] &&
                               attention_rsp_value_exponent_o == f_read_expected[2063:2056]);
                end
                if (response_kind_q == REQ_VALUE_ONLY) assert(attention_rsp_key_vector_o == 0 && attention_rsp_key_exponent_o == 0);
                if (response_kind_q == REQ_KEY_ONLY) assert(attention_rsp_value_vector_o == 0 && attention_rsp_value_exponent_o == 0);
            end
        end
    end
