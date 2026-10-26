    // Parent-level history is independent of the child implementation state.
    logic f_parent_runtime_seen_q;
    always_ff @(posedge app_clk_i or negedge app_domain_reset_n) begin
        if (!app_domain_reset_n) f_parent_runtime_seen_q <= 0;
        else if (private_model_locked_o) f_parent_runtime_seen_q <= 1;
    end
    wire f_parent_kv = app_addr_o[21:3] >= 19'd227072 &&
        app_addr_o[21:3] < 19'd__KV_LIMIT__;
    always_ff @(posedge app_clk_i) if (app_domain_reset_n) begin
        if ((f_parent_runtime_seen_q || private_model_locked_o) && app_cmd_en_o && app_cmd_o == 0)
            assert(f_parent_kv); // M01: actual parent output excludes model writes
        if (f_parent_runtime_seen_q) assert(f_runtime_phase); // M02: support linking histories
        if (f_parent_runtime_seen_q || private_model_locked_o)
            assert(!boot_cmd_ready && !boot_data_ready); // M03: no boot re-entry
        if (private_req_ready_o) assert(private_model_locked_o); // M04
        if (private_fail_closed_o) assert(!app_cmd_en_o && !app_wr_data_en_o); // M05
        if (private_fail_closed_o) assert(!private_model_locked_o); // M06
        assert(!app_burst_o && !app_self_refresh_req_o && !app_refresh_req_o); // M07
        if (app_wr_data_en_o) assert(app_cmd_en_o && app_cmd_o == 0); // M08
        if (private_model_locked_o && private_req_valid_i && private_req_write_i &&
            private_req_word_i < 19'd227062)
            assert(!app_cmd_en_o && !app_wr_data_en_o); // M09
    end
    always_ff @(posedge app_clk_i) if (app_domain_reset_n) begin
        cover(private_model_locked_o && private_req_ready_o && private_req_valid_i &&
            !private_req_write_i && private_req_word_i < 19'd227062 && app_cmd_en_o);
        cover(private_model_locked_o && private_req_ready_o && private_req_valid_i &&
            private_req_write_i && f_parent_kv && app_cmd_en_o && app_wr_data_en_o);
    end
