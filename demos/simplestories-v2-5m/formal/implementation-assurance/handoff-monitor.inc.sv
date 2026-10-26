    // Read-only specification monitor. This history observes the externally
    // reported runtime epoch; it does not drive any production signal.
    logic f_runtime_seen_q, f_history_valid_q;
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            f_runtime_seen_q <= 0;
            f_history_valid_q <= 0;
        end else begin
            f_history_valid_q <= 1;
            if (runtime_locked_o) f_runtime_seen_q <= 1;
        end
    end
    wire f_model = app_addr_o[21:3] < 19'd227062;
    wire f_kv = app_addr_o[21:3] >= 19'd227072 &&
                app_addr_o[21:3] < 19'd__KV_LIMIT__;
    wire f_aligned = app_addr_o[28:22] == 0 && app_addr_o[2:0] == 0;
    wire f_runtime_epoch = f_runtime_seen_q || runtime_locked_o;
    wire f_selected_write_attempt = runtime_q && runtime_cmd_en_i && runtime_cmd_i == 0;
    wire f_runtime_model_attempt = f_selected_write_attempt &&
        runtime_addr_i[28:22] == 0 && runtime_addr_i[2:0] == 0 &&
        runtime_addr_i[21:3] < 19'd227062;

    always_ff @(posedge clk) if (reset_n) begin
        // Main security conclusions, including arbitrary malicious requests.
        if (f_runtime_epoch && app_cmd_en_o && app_cmd_o == 0)
            assert(f_kv); // P01: no model writes after observed runtime lock
        if (f_runtime_seen_q) assert(runtime_q); // P02: epoch cannot return to boot
        if (runtime_q && app_cmd_en_o && app_cmd_o == 0)
            assert(f_kv); // P03: no write during initial runtime edge either
        if (f_runtime_model_attempt)
            assert(!app_cmd_en_o && !app_data_en_o); // P04: block at issue
        if (f_runtime_epoch)
            assert(!boot_cmd_ready_o && !boot_data_ready_o); // P05: boot isolated
        if (app_cmd_en_o) begin
            assert(f_aligned); // P06
            assert(app_cmd_o == 0 || app_cmd_o == 1); // P07
            assert(f_model || f_kv); // P08: reserved gap excluded
            if (!runtime_q) assert(f_model); // P09: boot confined to model
        end
        if (app_data_en_o) begin
            assert(app_cmd_en_o && app_cmd_o == 0); // P10: no orphan data
            assert(app_data_end_o && app_mask_o == 0); // P11
            assert(app_cmd_ready_i == app_data_ready_i); // P12: paired acceptance
        end
        if (!controller_good_i || fault_o || boot_fault_i || runtime_fault_i)
            assert(!app_cmd_en_o && !app_data_en_o); // P13: fail closed now
        if (runtime_locked_o)
            assert(runtime_q && boot_locked_i && !fault_o); // P14
        assert(!(boot_read_valid_o && runtime_read_valid_o)); // P15
        assert(pending_q <= 32); // P16: support for bounded credits
        if (fault_o) assert(!runtime_locked_o); // P17
        if (f_history_valid_q && $past(reset_n)) begin
            if ($past(runtime_q)) assert(runtime_q); // P18: ownership monotone
            if ($past(fault_o)) assert(fault_o); // P19: fault monotone
            if (!$past(runtime_q) && runtime_q)
                assert($past(pending_q) == 0 && !$past(app_read_valid_i) &&
                    $past(boot_locked_i) && !$past(boot_cmd_en_i) &&
                    !$past(boot_data_en_i)); // P20: only quiescent transfer
            if ($past(f_runtime_model_attempt)) assert(fault_o); // P21
        end
    end

    // Reachability checks prevent "everything is always disabled" evidence.
    always_ff @(posedge clk) if (reset_n) begin
        cover(!runtime_q && app_cmd_en_o && app_cmd_ready_i && app_cmd_o == 0);
        cover(runtime_locked_o && app_cmd_en_o && app_cmd_ready_i &&
            app_cmd_o == 1 && f_model);
        cover(runtime_locked_o && app_cmd_en_o && app_cmd_ready_i &&
            app_cmd_o == 0 && f_kv);
        cover(runtime_locked_o && f_runtime_model_attempt && !app_cmd_en_o && !app_data_en_o);
    end
