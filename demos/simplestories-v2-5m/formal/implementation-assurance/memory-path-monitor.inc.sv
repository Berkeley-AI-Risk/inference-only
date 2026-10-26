    // Histories at the actual parent/transport interface, reset with the
    // same hard-reset epoch as the native memory ownership controller.
    logic f_path_read_seen_q,f_path_return_seen_q,f_path_runtime_seen_q;
    always_ff @(posedge app_clk_i or negedge app_domain_reset_n) begin
        if (!app_domain_reset_n) begin
            f_path_read_seen_q <= 0;
            f_path_return_seen_q <= 0;
            f_path_runtime_seen_q <= 0;
        end else begin
            if (app_cmd_en_o && app_cmd_o == 1) f_path_read_seen_q <= 1;
            if (app_rd_data_valid_i) f_path_return_seen_q <= 1;
            if (private_model_locked_o) f_path_runtime_seen_q <= 1;
        end
    end
    always_comb begin
        assert(app_release_q == 0 || app_release_q == 1 || app_release_q == 3 || app_release_q == 7);
        assert(app_release_q == f_observe_boot_app_release);
        if (app_domain_reset_n) begin
            if (f_path_read_seen_q) assert(f_observe_boot_read_seen);
            if (f_observe_boot_read_seen && !f_path_read_seen_q) assert(handoff_fault);
            if (f_observe_boot_return_seen) assert(f_path_return_seen_q);
            if (private_model_locked_o) assert(f_path_read_seen_q && f_path_return_seen_q);
            // Contract A1 for the actual downstream transport: a model-write
            // prefix, followed permanently by model reads and K/V traffic.
            if (f_path_read_seen_q && app_cmd_en_o && app_cmd_o == 0)
                assert(app_addr_o[21:3] >= 19'd227072 && app_addr_o[21:3] < 19'd__KV_LIMIT__);
            if ((f_path_runtime_seen_q || private_model_locked_o) && app_cmd_en_o && app_cmd_o == 0)
                assert(app_addr_o[21:3] >= 19'd227072 && app_addr_o[21:3] < 19'd__KV_LIMIT__);
            if (f_path_runtime_seen_q) assert(f_observe_runtime_phase);
            if (f_path_runtime_seen_q || private_model_locked_o) assert(!boot_cmd_ready && !boot_data_ready);
            if (private_req_ready_o) assert(private_model_locked_o);
            if (private_fail_closed_o) assert(!app_cmd_en_o && !app_wr_data_en_o && !private_model_locked_o);
            assert(!app_burst_o && !app_self_refresh_req_o && !app_refresh_req_o);
            if (app_wr_data_en_o) assert(app_cmd_en_o && app_cmd_o == 0);
            if (private_model_locked_o && private_req_valid_i && private_req_write_i && private_req_word_i < 19'd227062)
                assert(!app_cmd_en_o && !app_wr_data_en_o);
            cover(app_cmd_en_o && app_cmd_o == 0 && app_wr_data_en_o);
        end
    end
