    // Read-only observations of the actual core-to-shell settings connection.
    always_comb if (reset_n) begin
        assert(f_shell_settings_valid_i == (settings_valid_i && machine_active && !root_terminal));
        assert(f_shell_settings_temperature_i == settings_temperature_i);
        assert(f_shell_settings_seed_i == settings_seed_i);
        assert(settings_ready_o == (machine_active && !root_terminal && f_shell_settings_ready_o));
        assert(settings_accepted_o == f_shell_settings_accepted_o);
        assert(settings_rejected_o == f_shell_settings_rejected_o);
        if (!machine_active || root_terminal) assert(!settings_ready_o);
    end
