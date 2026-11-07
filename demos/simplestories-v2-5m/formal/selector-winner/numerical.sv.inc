`ifdef NUMERICAL_JOIN
    // Independent fold over actual admitted/owned rows, never a native-best oracle.
    reg join_valid_q = 1'b0;
    reg [11:0] join_id_q = 12'd0;
    reg signed [49:0] join_raw_q = 50'sd0;
    reg signed [7:0] join_exp_q = 8'sd0;
    reg signed [51:0] join_score_q = 52'sd0;
    wire signed [51:0] join_pending_score =
        fold_normalized(obs_held_raw_q,obs_held_exp_q,obs_base_exp_q);
    wire join_replace = !join_valid_q ||
        $signed(join_pending_score) > $signed(join_score_q);
    wire join_healthy_winner = reset_n && obs_active_q && !obs_abort && state_q == ST_WINNER;
    always @(posedge clk) begin
        if (!reset_n || obs_abort || obs_start) begin
            join_valid_q <= 1'b0;
            join_id_q <= 12'd0;
            join_raw_q <= 50'sd0;
            join_exp_q <= 8'sd0;
            join_score_q <= 52'sd0;
        end else if (obs_consume) begin
            join_valid_q <= 1'b1;
            if (join_replace) begin
                join_id_q <= obs_held_id_q;
                join_raw_q <= obs_held_raw_q;
                join_exp_q <= obs_held_exp_q;
                join_score_q <= join_pending_score;
            end
        end
    end
    always @(posedge clk) begin
        if (reset_n && obs_active_q) begin
            assert(join_valid_q == (obs_consumed_q != 13'd0));
            assert(best_valid_q == join_valid_q);
            if (obs_owned_q)
                assert(fold_legal_exponent(obs_held_exp_q,obs_base_exp_q));
            if (join_valid_q) begin
                assert({1'b0,join_id_q} < obs_consumed_q);
                assert(fold_legal_exponent(join_exp_q,obs_base_exp_q));
                assert(fold_legal_exponent(best_exponent_q,obs_base_exp_q));
                assert(join_score_q == fold_normalized(join_raw_q,join_exp_q,obs_base_exp_q));
                assert(best_token_q == join_id_q);
                assert(best_scaled_q == join_raw_q);
                assert(best_exponent_q == join_exp_q);
            end
            if (join_healthy_winner) begin
                assert(winner_valid_o);
                assert(winner_token_id_o == join_id_q);
                assert(winner_scaled_raw_o == join_raw_q);
                assert(winner_source_exponent_o == join_exp_q);
            end
        end
    end
    // Direct output hold obligation during healthy WINNER backpressure.
    reg join_hold_q = 1'b0;
    reg [11:0] join_hold_id_q = 12'd0;
    reg signed [49:0] join_hold_raw_q = 50'sd0;
    reg signed [7:0] join_hold_exp_q = 8'sd0;
    always @(posedge clk) begin
        if (!reset_n || obs_abort || obs_start) begin
            join_hold_q <= 1'b0;
        end else begin
            join_hold_q <= join_healthy_winner && !winner_ready_i;
            if (join_healthy_winner) begin
                join_hold_id_q <= winner_token_id_o;
                join_hold_raw_q <= winner_scaled_raw_o;
                join_hold_exp_q <= winner_source_exponent_o;
            end
        end
        if (reset_n && obs_active_q && !obs_abort && join_hold_q) begin
            assert(state_q == ST_WINNER && winner_valid_o);
            assert(winner_token_id_o == join_hold_id_q);
            assert(winner_scaled_raw_o == join_hold_raw_q);
            assert(winner_source_exponent_o == join_hold_exp_q);
        end
    end
`ifdef WATCH_ROWS
    // Arbitrary constant ID; this nondriving choice is not an environment assumption.
    (* anyconst *) reg [11:0] join_watch_id;
    reg join_watch_seen_q = 1'b0;
    reg join_watch_consumed_q = 1'b0;
    reg signed [49:0] join_watch_raw_q = 50'sd0;
    reg signed [7:0] join_watch_exp_q = 8'sd0;
    wire signed [51:0] join_watch_score =
        fold_normalized(join_watch_raw_q,join_watch_exp_q,obs_base_exp_q);
    always @(posedge clk) begin
        if (!reset_n || obs_abort || obs_start) begin
            join_watch_seen_q <= 1'b0;
            join_watch_consumed_q <= 1'b0;
            join_watch_raw_q <= 50'sd0;
            join_watch_exp_q <= 8'sd0;
        end else if (obs_active_q) begin
            if (obs_accept && row_index_i == {1'b0,join_watch_id}) begin
                join_watch_seen_q <= 1'b1;
                join_watch_raw_q <= row_scaled_raw_i;
                join_watch_exp_q <= row_source_exponent_i;
            end
            if (obs_consume && obs_held_id_q == join_watch_id)
                join_watch_consumed_q <= 1'b1;
        end
    end
    always @(posedge clk) begin
        if (reset_n && obs_active_q) begin
            assert(join_watch_seen_q == ({1'b0,join_watch_id} < obs_admitted_q));
            assert(join_watch_consumed_q == ({1'b0,join_watch_id} < obs_consumed_q));
            if (join_watch_seen_q)
                assert(fold_legal_exponent(join_watch_exp_q,obs_base_exp_q));
            if (join_watch_seen_q && !join_watch_consumed_q) begin
                assert(obs_owned_q && obs_held_id_q == join_watch_id);
                assert(obs_held_raw_q == join_watch_raw_q);
                assert(obs_held_exp_q == join_watch_exp_q);
            end
            if (join_valid_q && join_id_q == join_watch_id) begin
                assert(join_watch_consumed_q);
                assert(join_raw_q == join_watch_raw_q);
                assert(join_exp_q == join_watch_exp_q);
            end
            if (join_watch_consumed_q) begin
                assert(join_valid_q);
                assert($signed(join_watch_score) <= $signed(join_score_q));
                if (join_watch_id < join_id_q)
                    assert($signed(join_watch_score) < $signed(join_score_q));
            end
        end
    end
`endif
`endif
