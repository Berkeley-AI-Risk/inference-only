    // Exact UART/shared/core settings payload and return feedback observations.
    always_comb if (reset_n_i) begin
        assert(f_core_settings_valid_i == settings_valid);
        assert(f_core_settings_temperature_i == settings_temperature);
        assert(f_core_settings_seed_i == settings_seed);
        assert(f_core_settings_ready_o == settings_ready);
        assert(f_core_settings_accepted_o == settings_accepted);
        assert(f_core_settings_rejected_o == settings_rejected);
        if (settings_valid) assert(!append_valid && !step_valid && !clear);
        if (settings_valid) assert(settings_temperature <= 3);
    end
