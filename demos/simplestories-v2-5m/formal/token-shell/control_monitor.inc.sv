    // Verification-only monitor. This stage retains the real embedding,
    // normalization, argmax and memories. External private ports are arbitrary.
    // It proves control/tape-register properties, not the numerical model or
    // post-CLEAR equality of future outputs across unequal private memories.
    wire f_fatal = upstream_fault_i || child_fault || lock_fault ||
        watchdog_fault || public_protocol_fault || private_protocol_fault ||
        ((state_q == ST_IDLE) && model_lock_i && !committed_prefixes_match);
    wire f_store_result = !clear_i && !fail_q &&
        state_q == ST_HEAD_TERMINALS && !private_head_result_valid_i &&
        head_terminals_complete && completing_winner < VOCABULARY_SIZE &&
        tape_count_q < TAPE_CAPACITY;
    wire f_add_append = !clear_i && !fail_q && state_q == ST_IDLE &&
        ddr_owner_q == DDR_OWNER_NONE && append_transfer;
    wire f_add_prefix = !clear_i && !fail_q && state_q == ST_LAYER_COMMIT &&
        !private_layer_busy_i && next_prefixes_match;
    reg f_seen_edge;
    reg f_pending_step;
    reg f_result_committed;
    reg f_previous_clear;
    reg f_previous_fail;
    reg f_previous_hold;
    reg [11:0] f_expected_count;
    reg [11:0] f_expected_prefix;
    reg [11:0] f_previous_token;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            f_seen_edge <= 0;
            f_pending_step <= 0;
            f_result_committed <= 0;
            f_previous_clear <= 0;
            f_previous_fail <= 0;
            f_previous_hold <= 0;
            f_expected_count <= 0;
            f_expected_prefix <= 0;
            f_previous_token <= 0;
        end else begin
            f_seen_edge <= 1;
            f_previous_clear <= clear_i;
            f_previous_fail <= fail_q;
            f_previous_hold <= state_q == ST_TOKEN_HOLD && !token_transfer &&
                !clear_i && !fail_q && !f_fatal;
            f_previous_token <= generated_token_q;
            f_expected_count <= clear_i ? 12'd0 :
                ((f_add_append || f_store_result) ? tape_count_q + 12'd1 : tape_count_q);
            f_expected_prefix <= clear_i ? 12'd0 :
                (f_add_prefix ? replay_position_q + 12'd1 : committed_count_q);
            if (step_transfer) begin
                f_pending_step <= 1;
                f_result_committed <= 0;
            end
            if (f_store_result) f_result_committed <= 1;
            if (token_transfer || f_fatal || fail_q) f_pending_step <= 0;
            if (clear_i) begin
                f_pending_step <= 0;
                f_result_committed <= 0;
            end
        end
    end

    always_comb begin
        if (rst_n) begin
            if (!f_seen_edge) begin
                assert(state_q == ST_IDLE && tape_count_q == 0 && committed_count_q == 0);
                assert(replay_position_q == 0 && generated_token_q == 0 && !fail_q);
            end
            assert(state_q <= ST_CLEAR_DRAIN || state_q == ST_FAIL);
            assert(tape_count_q <= 12'd2049);
            assert(committed_count_q <= tape_count_q);
            assert(replay_position_q <= 12'd2048);
            if (compute_active) begin
                assert(f_pending_step);
                assert(!f_result_committed);
                assert(tape_count_q != 0 && tape_count_q <= 12'd2048);
                assert(replay_position_q < tape_count_q);
            end
            if ((state_q == ST_IDLE || state_q == ST_TOKEN_HOLD) && tape_count_q != 0)
                assert(committed_count_q < tape_count_q);
            if (state_q == ST_CLEAR_DRAIN) begin
                assert(tape_count_q == 0 && committed_count_q == 0 && replay_position_q == 0);
                assert(!last_hidden_valid_q && generated_token_q == 0 && !f_pending_step && !f_result_committed);
            end
            if (f_store_result) begin
                assert(f_pending_step);
                assert(!f_result_committed);
            end
            if (token_valid_o) begin
                assert(f_pending_step && f_result_committed);
                assert(token_o < 12'd4019);
                assert(tape_count_q >= 2);
                assert(!append_ready_o && !step_ready_o);
            end
            if (clear_i) begin
                assert(!append_ready_o && !step_ready_o && !token_valid_o);
                assert(private_layer_clear_o);
            end
            if (fail_q) assert(!append_ready_o && !step_ready_o && !token_valid_o);
            if (append_transfer) begin
                assert(state_q == ST_IDLE && tape_count_q < 12'd2048);
                assert(!step_transfer);
            end
            if (step_transfer)
                assert(state_q == ST_IDLE && tape_count_q > 0 && tape_count_q <= 12'd2048);
            if (tape_count_q == 12'd2049) assert(!append_ready_o && !step_ready_o);
            if (private_layer_start_valid_o) assert(replay_position_q < 12'd2048);
            if (f_seen_edge) begin
                assert(tape_count_q == f_expected_count);
                assert(committed_count_q == f_expected_prefix);
                if (f_previous_fail) assert(fail_q);
                if (f_previous_clear) begin
                    assert(tape_count_q == 0 && committed_count_q == 0);
                    assert(replay_position_q == 0 && !last_hidden_valid_q);
                    assert(generated_token_q == 0 && !f_pending_step);
                end
                if (f_previous_hold) begin
                    assert(state_q == ST_TOKEN_HOLD);
                    assert(generated_token_q == f_previous_token);
                end
            end
        end
    end
