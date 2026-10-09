    // Verification-only front-end obligations. Backend inputs are arbitrary.
    always_comb begin
        if (reset_n_i) begin
            assert(clear == decoded_clear);
            assert(!(append_valid && step_valid));
            assert(!(clear && (append_valid || step_valid)));
            assert(append_valid == (cmd_valid && cmd == 2'd0));
            assert(step_valid == (cmd_valid && cmd == 2'd1));
            assert(clear == (cmd_valid && cmd == 2'd2));
            if (append_valid) begin
                assert(append_token == command_token);
                assert({1'b0, append_token} < 13'd4019);
            end
            assert((cmd_valid && cmd_ready) ==
                ((append_valid && append_ready) || (step_valid && step_ready) || clear));
            if (clear) assert(cmd_ready);
            assert(token_ready == result_ready);
            assert(result_valid == token_valid);
            assert(result_token == (token_valid ? token : 12'd0));
            if (cmd_valid) assert(cmd == 0 || cmd == 1 || cmd == 2);
        end
    end
