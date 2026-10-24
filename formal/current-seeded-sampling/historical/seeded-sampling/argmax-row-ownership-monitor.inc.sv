    // Verification-only accepted-row counter; this output drives monitors only.
    reg [12:0] f_accepted_rows;
    assign f_observed_rows_o = f_accepted_rows;
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) f_accepted_rows <= 0;
        else if (clear_i || fail_closed_o || !model_locked_i) f_accepted_rows <= 0;
        else if (start_valid_i && start_ready_o) f_accepted_rows <= 0;
        else if (row_fire && row_legal) f_accepted_rows <= f_accepted_rows + 1'b1;
    end
    always_comb if (reset_n) begin
        assert(f_accepted_rows <= 4019);
        assert(expected_row_q <= 4018);
        if (!fail_closed_o && model_locked_i && !clear_i) begin
            if (state_q == ST_ROWS) assert(f_accepted_rows == expected_row_q);
            if (state_q == ST_COMPARE) begin
                assert(f_accepted_rows == expected_row_q + 1'b1);
                assert(pending_token_q == expected_row_q[11:0]);
            end
            if (state_q == ST_WINNER) assert(f_accepted_rows == 4019);
            if (row_fire && row_legal) assert(row_index_i == f_accepted_rows);
        end
    end
