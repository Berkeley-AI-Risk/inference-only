`ifdef INVOCATION_CHECK
    // This observer never drives a production input or register.
    reg obs_active_q = 1'b0;
    reg obs_owned_q = 1'b0;
    reg [12:0] obs_admitted_q = 13'd0;
    reg [12:0] obs_consumed_q = 13'd0;
    reg [11:0] obs_held_id_q = 12'd0;
    reg signed [49:0] obs_held_raw_q = 50'sd0;
    reg signed [7:0] obs_held_exp_q = 8'sd0;
    reg signed [7:0] obs_base_exp_q = 8'sd0;
    reg obs_base_valid_q = 1'b0;
    wire obs_abort = clear_i || !model_locked_i ||
        upstream_fail_closed_i || fail_q || state_q == ST_FAIL ||
        (row_fire && !row_legal);
    wire obs_start = reset_n && start_valid_i && start_ready_o;
    wire obs_accept = reset_n && obs_active_q && !obs_abort &&
        row_fire && row_legal;
    wire obs_consume = reset_n && obs_active_q && !obs_abort &&
        state_q == ST_COMPARE;
    wire signed [8:0] obs_input_delta =
        $signed({obs_base_exp_q[7],obs_base_exp_q}) -
        $signed({row_source_exponent_i[7],row_source_exponent_i});
    always @(posedge clk) begin
        if (!reset_n || obs_abort) begin
            obs_active_q <= 1'b0;
            obs_owned_q <= 1'b0;
            obs_admitted_q <= 13'd0;
            obs_consumed_q <= 13'd0;
            obs_held_id_q <= 12'd0;
            obs_held_raw_q <= 50'sd0;
            obs_held_exp_q <= 8'sd0;
            obs_base_exp_q <= 8'sd0;
            obs_base_valid_q <= 1'b0;
        end else if (obs_start) begin
            obs_active_q <= 1'b1;
            obs_owned_q <= 1'b0;
            obs_admitted_q <= 13'd0;
            obs_consumed_q <= 13'd0;
            obs_held_id_q <= 12'd0;
            obs_held_raw_q <= 50'sd0;
            obs_held_exp_q <= 8'sd0;
            obs_base_exp_q <= 8'sd0;
            obs_base_valid_q <= 1'b0;
        end else if (obs_active_q) begin
            if (obs_accept) begin
                obs_owned_q <= 1'b1;
                obs_admitted_q <= obs_admitted_q + 13'd1;
                obs_held_id_q <= row_index_i[11:0];
                obs_held_raw_q <= row_scaled_raw_i;
                obs_held_exp_q <= row_source_exponent_i;
                if (obs_admitted_q == 13'd0)
                    obs_base_exp_q <= row_source_exponent_i;
            end
            if (obs_consume) begin
                obs_owned_q <= 1'b0;
                obs_consumed_q <= obs_consumed_q + 13'd1;
                if (obs_consumed_q == 13'd0)
                    obs_base_valid_q <= 1'b1;
            end
            if (winner_valid_o && winner_ready_i)
                obs_active_q <= 1'b0;
        end
    end
    always @(posedge clk) begin
        if (reset_n && obs_active_q) begin
            assert(state_q == ST_ROWS || state_q == ST_COMPARE || state_q == ST_WINNER);
            assert(obs_admitted_q <= 13'd4019);
            assert(obs_consumed_q <= obs_admitted_q);
            assert(obs_admitted_q == obs_consumed_q + (obs_owned_q ? 13'd1 : 13'd0));
            assert(obs_owned_q == (state_q == ST_COMPARE));
            if (state_q == ST_ROWS || state_q == ST_COMPARE) begin
                assert(expected_row_q == obs_consumed_q);
                assert(obs_consumed_q < 13'd4019);
            end
            if (state_q == ST_WINNER) begin
                assert(obs_admitted_q == 13'd4019);
                assert(obs_consumed_q == 13'd4019);
            end
            if (obs_owned_q) begin
                assert(pending_token_q == obs_held_id_q);
                assert(pending_scaled_q == obs_held_raw_q);
                assert(pending_exponent_q == obs_held_exp_q);
                assert(obs_held_id_q == obs_consumed_q[11:0]);
                if (obs_consumed_q == 13'd0)
                    assert(obs_base_exp_q == obs_held_exp_q);
            end
            assert(obs_base_valid_q == (obs_consumed_q != 13'd0));
            if (obs_base_valid_q)
                assert(row_zero_exponent_q == obs_base_exp_q);
            else
                assert(row_zero_exponent_q == 8'sd0);
            if (obs_accept) begin
                assert(state_q == ST_ROWS && !obs_owned_q);
                assert(row_index_i == obs_admitted_q);
                assert(obs_admitted_q < 13'd4019);
                assert(row_last_i == (obs_admitted_q == 13'd4018));
                if (obs_admitted_q != 13'd0)
                    assert(obs_input_delta == 9'sd0 || obs_input_delta == 9'sd1 || obs_input_delta == 9'sd2);
            end
            if (obs_consume) begin
                assert(obs_owned_q);
                assert(!row_ready_o && !row_fire);
            end
        end
    end
    // Reachability witness only; this is not an input constraint.
    reg obs_stall_seen_q = 1'b0;
    reg obs_followup_seen_q = 1'b0;
    always @(posedge clk) begin
        if (!reset_n || obs_abort || obs_start) begin
            obs_stall_seen_q <= 1'b0;
            obs_followup_seen_q <= 1'b0;
        end else begin
            if (obs_consume && obs_consumed_q == 13'd0 &&
                row_valid_i && !row_ready_o && row_index_i == 13'd1 &&
                pending_token_q == 12'd0)
                obs_stall_seen_q <= 1'b1;
            if (obs_stall_seen_q && obs_consume &&
                obs_consumed_q == 13'd1 && pending_token_q == 12'd1)
                obs_followup_seen_q <= 1'b1;
        end
    end
    wire obs_witness_complete = obs_active_q && obs_stall_seen_q &&
        obs_followup_seen_q && obs_admitted_q == 13'd2 &&
        obs_consumed_q == 13'd2 && !obs_owned_q &&
        obs_base_valid_q && row_zero_exponent_q == obs_base_exp_q;
`endif
