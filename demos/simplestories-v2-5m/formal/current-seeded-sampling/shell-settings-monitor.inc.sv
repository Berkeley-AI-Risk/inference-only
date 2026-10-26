    // Verify the owning shell's empty-boundary certificate and configuration
    // admission alongside the original controller/tape and actual sampler.
    reg f_expected_settings_accept;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) f_expected_settings_accept <= 0;
        else f_expected_settings_accept <= settings_valid_i && !fail_q &&
            !upstream_fault_i && settings_ready_o && settings_empty_boundary &&
            settings_temperature_i <= 3 && !clear_i;
    end
    always_comb if (rst_n) begin
        assert(settings_accepted_o == f_expected_settings_accept);
        if (settings_valid_i) assert(!append_ready_o && !step_ready_o);
        if (settings_empty_boundary) begin
            assert(state_q == ST_IDLE && tape_count_q == 0 && committed_count_q == 0);
            assert(!last_hidden_valid_q && !private_layer_busy_i);
            assert(ddr_owner_q == DDR_OWNER_NONE && committed_prefixes_match);
            assert(!embed_busy && !rms_busy && !argmax_busy);
            assert(!embed_start_valid && !rms_start_valid && !argmax_start_valid);
            assert(!private_layer_start_valid_o && !private_head_start_valid_o);
            assert(!private_word_req_valid_o);
        end
        if (settings_accepted_o) begin
            assert(tape_count_q == 0 && committed_count_q == 0);
            assert(!token_valid_o);
        end
    end
