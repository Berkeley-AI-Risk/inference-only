    // Verification-only obligations on the real core gates and shell outputs.
    always_comb begin
        if (reset_n) begin
            assert(f_shell_clear_i == (clear_i && machine_active));
            assert(f_shell_append_valid_i == (append_valid_i && machine_active));
            assert(f_shell_append_token_i == append_token_i);
            assert(f_shell_step_valid_i == (step_valid_i && machine_active));
            assert(f_shell_token_ready_i == (token_ready_i && machine_active));
            if (append_valid_i && append_ready_o) assert(f_shell_append_transfer);
            if (step_valid_i && step_ready_o) assert(f_shell_step_transfer);
            if (machine_active && !aggregate_fail) begin
                assert(f_shell_append_transfer == (append_valid_i && append_ready_o));
                assert(f_shell_step_transfer == (step_valid_i && step_ready_o));
            end
            if (token_valid_o) begin
                assert(token_o < 12'd4019);
                assert(shell_token_valid && token_o == shell_token);
                assert(machine_active && child_reset_n && !aggregate_fail);
            end
            if (clear_i) assert(!append_ready_o && !step_ready_o && !token_valid_o);
            if (!machine_active || aggregate_fail)
                assert(!append_ready_o && !step_ready_o && !token_valid_o);
            if (!token_valid_o) assert(token_o == 12'd0);
            if (append_valid_i && append_ready_o)
                assert(machine_active && child_reset_n && shell_append_ready);
            if (step_valid_i && step_ready_o)
                assert(machine_active && child_reset_n && shell_step_ready);
            if (root_terminal) assert(!kv_write_req_valid_o && !kv_read_req_valid_o);
        end
    end
