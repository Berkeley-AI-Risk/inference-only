    // Arbitrary slot selects an extra read-only RAM port; never feeds the DUT.
    (* anyconst *) reg [11:0] f_buffer_slot;
    reg [12:0] f_rows_written, f_mass_written;
    reg f_logit_owned, f_mass_owned;
    reg signed [51:0] f_logit_value;
    reg [30:0] f_mass_value;
    wire signed [51:0] f_logit_observed = logits[f_buffer_slot];
    wire [30:0] f_mass_observed = mass[f_buffer_slot];
    wire f_buffer_healthy = !f_fatal && !clear_i && model_locked_i;
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            f_rows_written <= 0; f_mass_written <= 0;
            f_logit_owned <= 0; f_mass_owned <= 0;
            f_logit_value <= 0; f_mass_value <= 0;
        end else if (clear_i || f_fatal || start_fire || f_accept) begin
            f_rows_written <= 0; f_mass_written <= 0;
            f_logit_owned <= 0; f_mass_owned <= 0;
        end else begin
            if (row_fire) f_rows_written <= f_rows_written + 1'b1;
            if (row_fire && !greedy_mode && row_index_i == {1'b0,f_buffer_slot}) begin
                f_logit_owned <= 1;
                f_logit_value <= align_logit(row_scaled_raw_i,
                    $signed({row_source_exponent_i[7],row_source_exponent_i}),
                    row_index_i == 0 ?
                        $signed({row_source_exponent_i[7],row_source_exponent_i}) : zero_exponent_q);
            end
            if (state_q == STORE && live && !invalid_lut) begin
                f_mass_written <= f_mass_written + 1'b1;
                if (cursor_q == f_buffer_slot) begin
                    f_mass_owned <= 1;
                    f_mass_value <= next_weight;
                end
            end
        end
    end
    always_comb if (reset_n) begin
        assert(f_rows_written <= 4019);
        assert(f_mass_written <= 4019);
        if (f_buffer_slot < 4019 && f_logit_owned) assert(f_logit_observed == f_logit_value);
        if (f_buffer_slot < 4019 && f_mass_owned) assert(f_mass_observed == f_mass_value);
        if (!fail_closed_o) begin
            if (!greedy_mode && f_buffer_slot < f_rows_written) assert(f_logit_owned);
            if (f_buffer_slot < f_mass_written) assert(f_mass_owned);
        end
        if (f_buffer_healthy) begin
            if (state_q == COLLECT) begin
                assert(f_rows_written == f_child_rows);
                assert(f_mass_written == 0);
                assert(cursor_q == 0);
            end
            if (state_q >= ROW_READ && state_q <= WINNER) begin
                assert(f_rows_written == 4019);
                if (f_buffer_slot < 4019) assert(f_logit_owned);
            end
            if (state_q >= ROW_READ && state_q <= STORE) assert(f_mass_written == {1'b0,cursor_q});
            if (state_q >= RNG_ADD && state_q <= WINNER) assert(f_mass_written == 4019);
            if (state_q == ROW_READ && cursor_q == f_buffer_slot) assert(f_logit_owned);
            if (state_q == CDF_READ && cursor_q == f_buffer_slot) assert(f_mass_owned);
        end
    end
