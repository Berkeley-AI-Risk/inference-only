    // Verification-only observation. No DUT inputs or internal values are cut.
    reg f_seen;
    reg f_pending;
    reg [127:0] f_seed;
    reg [1:0] f_temperature;
    reg [63:0] f_rng_lo, f_rng_hi;
    reg f_expected_accept, f_expected_reject;
    reg f_previous_fail, f_previous_clear, f_previous_healthy_clear;
    reg f_previous_hold;
    reg [11:0] f_previous_token;
    wire f_fatal = fail_q || greedy_fault || upstream_fail_closed_i ||
                   (state_q != IDLE && !model_locked_i);
    wire f_offer = !f_fatal && !clear_i && state_q == IDLE &&
                   settings_valid_i && settings_ready_o;
    wire f_accept = f_offer && settings_empty_boundary_i && settings_temperature_i <= 3;
    wire f_reject = f_offer && (!settings_empty_boundary_i || settings_temperature_i > 3);
    wire f_commit = !f_fatal && !clear_i && state_q == WINNER &&
                    winner_valid_o && winner_ready_i;
    function automatic [63:0] f_rotate(input [63:0] value, input integer amount);
        f_rotate = {value,value} >> (64-amount);
    endfunction
    wire [63:0] f_mix = f_rng_lo ^ f_rng_hi;
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            f_seen <= 0; f_pending <= 0; f_seed <= 128'd1; f_temperature <= 0;
            f_rng_lo <= 1; f_rng_hi <= 0;
            f_expected_accept <= 0; f_expected_reject <= 0;
            f_previous_fail <= 0; f_previous_clear <= 0; f_previous_healthy_clear <= 0;
            f_previous_hold <= 0; f_previous_token <= 0;
        end else begin
            f_seen <= 1;
            f_previous_fail <= fail_q;
            f_previous_clear <= clear_i;
            f_previous_healthy_clear <= clear_i && !f_fatal;
            f_previous_hold <= winner_valid_o && !winner_ready_i && !f_fatal && !clear_i;
            f_previous_token <= winner_token_id_o;
            f_expected_accept <= f_accept;
            f_expected_reject <= f_reject;
            if (start_fire) f_pending <= 1;
            if ((winner_valid_o && winner_ready_i) || clear_i || f_fatal) f_pending <= 0;
            if (!f_fatal) begin
                if (clear_i) begin
                    f_rng_lo <= f_seed[63:0]; f_rng_hi <= f_seed[127:64];
                end else if (f_accept) begin
                    f_seed <= settings_seed_i == 0 ? 128'd1 : settings_seed_i;
                    f_temperature <= settings_temperature_i[1:0];
                    f_rng_lo <= settings_seed_i == 0 ? 64'd1 : settings_seed_i[63:0];
                    f_rng_hi <= settings_seed_i[127:64];
                end else if (f_commit) begin
                    f_rng_lo <= f_rotate(f_rng_lo,49) ^ f_mix ^ (f_mix << 21);
                    f_rng_hi <= f_rotate(f_mix,28);
                end
            end
        end
    end
    always_comb if (reset_n) begin
        assert(state_q <= WINNER || state_q == FAIL);
        assert(temperature_q == f_temperature);
        assert(seed_q == f_seed);
        assert(rng_lo_q == f_rng_lo);
        assert(rng_hi_q == f_rng_hi);
        assert(seed_q != 0);
        assert(settings_accepted_o == f_expected_accept);
        assert(settings_rejected_o == f_expected_reject);
        assert(!(settings_accepted_o && settings_rejected_o));
        assert(cursor_q <= 4018);
        assert(sampled_token_q <= 4018);
        if (state_q >= ROW_READ && state_q <= WINNER) assert(temperature_q != 0);
        if (winner_valid_o) assert(f_pending);
        if (state_q != IDLE && state_q != FAIL && !fail_closed_o) assert(f_pending);
        if (winner_valid_o && !greedy_mode) assert(winner_token_id_o < 4019);
        if (state_q == IDLE) assert(!f_pending);
        if (start_fire) begin
            assert(state_q == IDLE && !settings_valid_i && !f_pending);
            assert(model_locked_i && !clear_i && !fail_closed_o);
        end
        if (settings_valid_i) assert(!start_ready_o);
        if (f_accept) assert(settings_ready_o && settings_empty_boundary_i && settings_temperature_i <= 3);
        if (f_commit) assert(!greedy_mode && f_pending);
        if (clear_i || fail_closed_o || !model_locked_i) begin
            assert(!settings_ready_o && !start_ready_o && !row_ready_o && !winner_valid_o);
        end
        if (!winner_valid_o) begin
            assert(winner_token_id_o == 0);
            assert(winner_scaled_raw_o == 0 && winner_source_exponent_o == 0);
        end
        if (winner_valid_o && !greedy_mode)
            assert(winner_scaled_raw_o == 0 && winner_source_exponent_o == 0);
        if (row_fire) assert(state_q == COLLECT && live && greedy_row_ready);
        if (state_q == FAIL) assert(fail_q);
        if (!f_seen) begin
            assert(state_q == IDLE && temperature_q == 0 && seed_q == 1);
            assert(rng_lo_q == 1 && rng_hi_q == 0);
        end
        if (f_previous_fail) assert(fail_q);
        if (f_previous_clear) assert(!winner_valid_o || state_q == COLLECT);
        if (f_previous_healthy_clear) begin
            assert(state_q == IDLE && cursor_q == 0 && total_q == 0 && cumulative_q == 0);
            assert(rng_lo_q == seed_q[63:0] && rng_hi_q == seed_q[127:64]);
        end
        if (f_previous_hold && live) begin
            assert(winner_valid_o);
            assert(winner_token_id_o == f_previous_token);
        end
    end
