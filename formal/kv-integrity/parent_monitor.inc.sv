    // Read-only history of guard-verified words assembled by the real atomic
    // controller. No cryptographic assumption or controller input constraint.
    reg f_seen, f_previous_clear;
    reg [8:0] f_verified_mask;
    reg [63:0] f_row_epoch;
    reg [2063:0] f_guard_row;
    reg [2:0] f_request_layer;
    reg [11:0] f_request_position;
    reg f_request_head;
    reg [1:0] f_request_kind;
    reg [63:0] f_guard_epoch_before;
    reg f_guard_clear_edge;
    wire f_good_piece = a_f_read_piece && !a_fault_q;
    wire f_good_attention = attention_cache_rsp_valid && !attention_cache_rsp_fault;
    always_ff @(posedge core_clk_i or negedge child_reset_n) begin
        if (!child_reset_n) begin
            f_seen <= 0;
            f_previous_clear <= 0;
            f_verified_mask <= 0;
            f_row_epoch <= 0;
            f_guard_row <= 0;
            f_request_layer <= 0; f_request_position <= 0;
            f_request_head <= 0; f_request_kind <= 0;
            f_guard_epoch_before <= 0; f_guard_clear_edge <= 0;
        end else begin
            f_seen <= 1;
            f_previous_clear <= clear_i;
            f_guard_epoch_before <= g_epoch_q;
            f_guard_clear_edge <= clear_i && !g_clear_seen_q;
            if (a_f_attention) begin
                f_request_layer <= a_attention_layer_i;
                f_request_position <= a_attention_position_i;
                f_request_head <= a_attention_kv_head_i[0];
                f_request_kind <= a_attention_req_kind_i;
            end
            if (a_f_read_begin) begin
                f_verified_mask <= 0;
                f_row_epoch <= g_epoch_q;
                f_guard_row <= 0;
            end
            if (f_good_piece) begin
                f_verified_mask[a_read_word_q] <= 1;
                case (a_read_word_q)
                    0: f_guard_row[255:0] <= kv_read_rsp_data;
                    1: f_guard_row[511:256] <= kv_read_rsp_data;
                    2: f_guard_row[767:512] <= kv_read_rsp_data;
                    3: f_guard_row[1023:768] <= kv_read_rsp_data;
                    4: f_guard_row[1279:1024] <= kv_read_rsp_data;
                    5: f_guard_row[1535:1280] <= kv_read_rsp_data;
                    6: f_guard_row[1791:1536] <= kv_read_rsp_data;
                    7: f_guard_row[2047:1792] <= kv_read_rsp_data;
                    8: f_guard_row[2063:2048] <= kv_read_rsp_data[15:0];
                    default: begin end
                endcase
            end
            if (layer_clear) begin
                f_verified_mask <= 0;
                f_row_epoch <= 0;
                f_guard_row <= 0;
            end
        end
    end

    always_comb begin
        if (reset_n_i) begin
            assert(!clear_i || layer_clear || !child_reset_n);
            if (root_terminal) begin
                assert(!kv_write_req_valid && !kv_read_req_valid);
                assert(!child_kv_write_cpl_valid && !child_kv_read_rsp_valid);
                assert(kv_write_cpl_ready && kv_read_rsp_ready);
            end
            if (clear_i) begin
                assert(!kv_write_req_valid && !kv_read_req_valid);
                assert(!f_good_attention);
            end
            if (kv_integrity_fault) begin
                assert(root_terminal);
                assert(!f_good_attention);
            end
            if (!child_reset_n) assert(!f_good_attention);
            if (g_write_fire) begin
                assert(child_reset_n && !root_terminal && !layer_clear);
                assert(a_f_stage_filled);
            end
            if (child_kv_read_rsp_valid && child_kv_read_rsp_ready)
                assert(kv_read_rsp_valid && kv_read_rsp_ready && !root_terminal);
        end
        if (child_reset_n) begin
            if (f_seen && f_guard_clear_edge && !(&f_guard_epoch_before))
                assert(g_epoch_q == f_guard_epoch_before + 64'd1);
            assert(a_kv_read_rsp_data_i == kv_read_rsp_data);
            if (!a_fault_q) assert(f_verified_mask == a_f_read_mask);
            if (!a_fault_q)
                assert((a_f_read_expected & a_f_read_bitmask) == (f_guard_row & a_f_read_bitmask));
            if (f_previous_clear) begin
                assert(kv_committed_prefixes == 0 && !a_pending_persisted_q);
                assert(f_verified_mask == 0);
                assert(g_prefixes == 0 && !g_cache_valid_q);
            end
            if (f_good_piece) begin
                assert(!clear_i && !root_terminal && !g_aborted_q);
                assert(g_cache_valid_q && g_f_verified && g_cache_epoch_q == g_epoch_q);
                assert(g_owner_q == 2 && a_state_q == 6);
                assert(g_f_stage_request_layer == a_pending_layer_q);
                assert(g_f_stage_request_position == a_response_position_q);
                assert(g_f_stage_request_head == a_response_head_q && g_f_stage_request_word == a_read_word_q);
                assert(f_row_epoch == g_epoch_q);
            end
            if (f_verified_mask != 0 && !layer_clear && !a_fault_q)
                assert(f_row_epoch == g_epoch_q);
            if (!a_fault_q && !a_terminal_fault_event && !layer_clear) begin
                if (a_f_attention_owned && !a_response_fault_q && !a_read_aborted_q) begin
                    assert(a_pending_layer_q == f_request_layer);
                    assert(a_response_position_q == f_request_position &&
                        a_response_head_q == f_request_head && a_response_kind_q == f_request_kind);
                end
                if (a_state_q == 6 && !a_read_aborted_q) begin
                    assert(g_owner_q == 2 && !g_aborted_q && g_f_stage_request);
                    assert(g_f_stage_request_layer == a_pending_layer_q);
                    assert(g_f_stage_request_position == a_response_position_q);
                    assert(g_f_stage_request_head == a_response_head_q && g_f_stage_request_word == a_read_word_q);
                end
                if ((a_state_q == 5 || a_state_q == 6 || a_state_q == 7) &&
                    !a_response_from_pending_q && !a_response_fault_q && !a_read_aborted_q)
                    assert(f_row_epoch == g_epoch_q);
            end
            if (f_good_attention && !attention_cache_rsp_from_pending) begin
                assert((f_verified_mask & a_f_required_read_mask) == a_f_required_read_mask);
                assert(f_row_epoch == g_epoch_q);
                if (a_response_kind_q != 2)
                    assert(attention_cache_key == a_f_read_expected[1023:0] &&
                        attention_cache_key_exp == a_f_read_expected[2055:2048]);
                if (a_response_kind_q != 1)
                    assert(attention_cache_value == a_f_read_expected[2047:1024] &&
                        attention_cache_value_exp == a_f_read_expected[2063:2056]);
                if (a_response_kind_q != 2)
                    assert(attention_cache_key == f_guard_row[1023:0] && attention_cache_key_exp == f_guard_row[2055:2048]);
                if (a_response_kind_q != 1)
                    assert(attention_cache_value == f_guard_row[2047:1024] && attention_cache_value_exp == f_guard_row[2063:2056]);
            end
            if (f_good_attention) begin
                assert(a_pending_layer_q == f_request_layer && a_response_position_q == f_request_position &&
                    a_response_head_q == f_request_head && a_response_kind_q == f_request_kind);
            end
            if (f_good_attention && attention_cache_rsp_from_pending) begin
                assert(a_f_stage_filled && a_f_completed_writes == 18);
                if (a_response_kind_q != 2)
                    assert(attention_cache_key_exp == a_f_key_exponents[a_response_head_q*8 +:8]);
                if (a_response_kind_q != 1)
                    assert(attention_cache_value_exp == a_f_value_exponents[a_response_head_q*8 +:8]);
            end
            if (a_kv_write_req_valid_o && a_write_word_q == 8)
                assert(a_kv_write_req_data_o[15:0] == {a_f_value_exponents[a_write_head_q*8 +:8], a_f_key_exponents[a_write_head_q*8 +:8]});
        end
    end
