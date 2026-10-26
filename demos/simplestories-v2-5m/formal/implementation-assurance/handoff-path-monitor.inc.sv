    // Clock-stutter-safe observational histories; no $past state is assumed.
    logic f_path_runtime_seen_q,f_path_fault_seen_q;
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            f_path_runtime_seen_q <= 0;
            f_path_fault_seen_q <= 0;
        end else begin
            if (runtime_locked_o) f_path_runtime_seen_q <= 1;
            if (fault_o) f_path_fault_seen_q <= 1;
        end
    end
    wire f_path_model = app_addr_o[21:3] < 19'd227062;
    wire f_path_kv = app_addr_o[21:3] >= 19'd227072 && app_addr_o[21:3] < 19'd__KV_LIMIT__;
    always_comb if (reset_n) begin
        if (f_path_runtime_seen_q) assert(runtime_q);
        if (f_path_fault_seen_q) assert(fault_o);
        if ((f_path_runtime_seen_q || runtime_q) && app_cmd_en_o && app_cmd_o == 0) assert(f_path_kv);
        if (runtime_q || f_path_runtime_seen_q) assert(!boot_cmd_ready_o && !boot_data_ready_o);
        if (app_cmd_en_o) begin
            assert(app_addr_o[28:22] == 0 && app_addr_o[2:0] == 0);
            assert(app_cmd_o == 0 || app_cmd_o == 1);
            assert(f_path_model || f_path_kv);
            if (!runtime_q) assert(f_path_model);
        end
        if (app_data_en_o) begin
            assert(app_cmd_en_o && app_cmd_o == 0);
            assert(app_data_end_o && app_mask_o == 0);
            assert(app_cmd_ready_i == app_data_ready_i);
        end
        if (!controller_good_i || fault_o || boot_fault_i || runtime_fault_i)
            assert(!app_cmd_en_o && !app_data_en_o);
        if (runtime_locked_o) assert(runtime_q && boot_locked_i && !fault_o);
        assert(!(boot_read_valid_o && runtime_read_valid_o));
        assert(pending_q <= 32);
        if (fault_o) assert(!runtime_locked_o);
        if (runtime_q && runtime_cmd_en_i && runtime_cmd_i == 0 &&
            runtime_addr_i[28:22] == 0 && runtime_addr_i[2:0] == 0 &&
            runtime_addr_i[21:3] < 19'd227062)
            assert(!app_cmd_en_o && !app_data_en_o);
    end
