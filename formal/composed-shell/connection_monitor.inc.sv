    // Unlike the earlier front-end proof, the token now comes from the real
    // shell/argmax and production core masking, not a free backend input.
    always_comb begin
        if (reset_n_i) begin
            assert(f_core_clear_i == clear);
            assert(f_core_append_valid_i == append_valid);
            assert(f_core_append_token_i == append_token);
            assert(f_core_step_valid_i == step_valid);
            assert(f_core_token_ready_i == token_ready);
            if (result_valid) assert(result_token < 12'd4019);
            if (clear) assert(!append_ready && !step_ready && !token_valid);
            if (!result_valid) assert(result_token == 12'd0);
        end
    end
