    // These histories observe the wrapper's actual command/return boundary.
    logic f_wrapper_read_seen_q,f_wrapper_return_seen_q;
    always_ff @(posedge app_clk_i or negedge app_domain_reset_n) begin
        if (!app_domain_reset_n) begin
            f_wrapper_read_seen_q <= 0;
            f_wrapper_return_seen_q <= 0;
        end else begin
            if (app_cmd_en_o && app_cmd_o == 1) f_wrapper_read_seen_q <= 1;
            if (app_rd_data_valid_i) f_wrapper_return_seen_q <= 1;
        end
    end
    always_comb begin
        assert(app_release_q == 0 || app_release_q == 1 || app_release_q == 3 || app_release_q == 7);
        assert(trusted_release_q == 0 || trusted_release_q == 1 || trusted_release_q == 3 || trusted_release_q == 7);
        if (app_domain_reset_n) begin
            if (loader_protocol_fault_q) assert(app_fault_q);
            if (watchdog_fault_q) assert(app_fault_q);
            if (f_wrapper_read_seen_q) assert(f_observe_inner_read_seen);
            // Every current-cycle suppression term is latched into the
            // wrapper fault. A suppressed inner read cannot create LOCK.
            if (f_observe_inner_read_seen && !f_wrapper_read_seen_q) assert(app_fault_q);
            if (f_observe_inner_final_return) assert(f_wrapper_return_seen_q);
            if (model_locked_o) assert(f_wrapper_read_seen_q && f_wrapper_return_seen_q);
            if (f_wrapper_read_seen_q && app_cmd_en_o && app_cmd_o == 0)
                assert(app_addr_o[21:3] >= 19'd227072 && app_addr_o[21:3] < 19'd448256);
            if (model_locked_o && app_cmd_en_o && app_cmd_o == 0)
                assert(app_addr_o[21:3] >= 19'd227072 && app_addr_o[21:3] < 19'd448256);
            if (output_fail) assert(!app_cmd_en_o && !app_wr_data_en_o);
            if (app_fault_q) assert(!model_locked_o && !app_cmd_en_o);
            if (model_locked_o) assert(boundary_model_locked && !app_fault_q && !endpoint_fail);
            if (app_cmd_en_o) assert(boundary_app_cmd_en && !physical_suppress_now);
            cover(app_cmd_en_o && app_cmd_o == 0 && app_wr_data_en_o);
        end
    end
