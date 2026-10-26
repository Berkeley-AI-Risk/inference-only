    logic f_source_read_seen_q,f_source_return_seen_q,f_physical_read_seen_q,f_runtime_observed_q;
    always_ff @(posedge core_clk_i or negedge core_reset_n) begin
        if (!core_reset_n) begin
            f_source_read_seen_q <= 0;
            f_source_return_seen_q <= 0;
        end else begin
            if (core_cmd_en_i && core_cmd_i == 1) f_source_read_seen_q <= 1;
            if (core_rd_valid_o) f_source_return_seen_q <= 1;
        end
    end
    always_ff @(posedge app_clk_i or negedge app_reset_n) begin
        if (!app_reset_n) f_physical_read_seen_q <= 0;
        else if (issue_read) f_physical_read_seen_q <= 1;
    end
    always_ff @(posedge core_clk_i or negedge common_reset_n) begin
        if (!common_reset_n) f_runtime_observed_q <= 0;
        else if (f_formal_runtime_locked_i) f_runtime_observed_q <= 1;
    end
    always_comb begin
        // Both source guarantees are independently proved on the full native
        // memory path. The actual top/reset correspondence discharges their
        // signal/clock/reset substitutions; neither is a client promise.
        if (core_reset_n && f_source_read_seen_q && core_cmd_en_i && core_cmd_i == 0)
            assume(core_addr_i[21:3] >= 19'd227072 && core_addr_i[21:3] < 19'd__KV_LIMIT__);
        if (f_formal_runtime_locked_i)
            assume(core_reset_n && f_source_read_seen_q && f_source_return_seen_q);
        if (physical_reads_q != 0) assert(f_physical_read_seen_q);
        if (capture_return) assert(f_physical_read_seen_q);
        if (core_rd_valid_o) assert(f_physical_read_seen_q);
        if (f_source_return_seen_q) assert(f_physical_read_seen_q);
        if (f_runtime_observed_q || f_formal_runtime_locked_i) assert(f_physical_read_seen_q);
        if ((f_runtime_observed_q || f_formal_runtime_locked_i) && app_cmd_en_o && app_cmd_o == 0)
            assert(app_addr_o[21:3] >= 19'd227072 && app_addr_o[21:3] < 19'd__KV_LIMIT__);
        cover(f_runtime_observed_q && app_cmd_en_o && app_cmd_o == 0 && app_wr_en_o);
    end
