
`ifdef FOLD_CHECK
    // Independent common-base integer normalization for a legal exponent bank.
    function automatic signed [51:0] fold_normalized;
        input signed [49:0] value;
        input signed [7:0] exponent_value;
        input signed [7:0] base_value;
        reg signed [8:0] delta;
        begin
            delta = $signed({base_value[7],base_value}) -
                    $signed({exponent_value[7],exponent_value});
            case (delta)
                9'sd0: fold_normalized = {value,2'b00};
                9'sd1: fold_normalized = {value[49],value,1'b0};
                9'sd2: fold_normalized = {{2{value[49]}},value};
                default: fold_normalized = 52'sd0;
            endcase
        end
    endfunction
    function automatic fold_legal_exponent;
        input signed [7:0] exponent_value;
        input signed [7:0] base_value;
        reg signed [8:0] delta;
        begin
            delta = $signed({base_value[7],base_value}) -
                    $signed({exponent_value[7],exponent_value});
            fold_legal_exponent = delta == 0 || delta == 1 || delta == 2;
        end
    endfunction
    wire fold_reference_greater =
        $signed(fold_normalized(pending_scaled_q,pending_exponent_q,row_zero_exponent_q)) >
        $signed(fold_normalized(best_scaled_q,best_exponent_q,row_zero_exponent_q));
    wire fold_choose_pending = !best_valid_q || fold_reference_greater;
    wire fold_healthy_compare = reset_n && !clear_i && model_locked_i &&
        !upstream_fail_closed_i && !fail_q && state_q == ST_COMPARE &&
        (!best_valid_q ||
         (fold_legal_exponent(pending_exponent_q,row_zero_exponent_q) &&
          fold_legal_exponent(best_exponent_q,row_zero_exponent_q)));
    reg fold_past_valid = 1'b0;
    always @(posedge clk) begin
        fold_past_valid <= 1'b1;
        if (fold_past_valid && reset_n && $past(fold_healthy_compare)) begin
            assert(best_valid_q);
            assert(best_token_q == ($past(fold_choose_pending) ?
                   $past(pending_token_q) : $past(best_token_q)));
            assert(best_scaled_q == ($past(fold_choose_pending) ?
                   $past(pending_scaled_q) : $past(best_scaled_q)));
            assert(best_exponent_q == ($past(fold_choose_pending) ?
                   $past(pending_exponent_q) : $past(best_exponent_q)));
        end
    end
`endif
