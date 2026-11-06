    (* anyseq *) wire proof_serial_rx,proof_command_ready,proof_result_valid;
    (* anyseq *) wire [11:0] proof_result_token;
    wire proof_uart_flight,proof_uart_first,proof_uart_quiet;
    wire [13:0] proof_uart_elapsed,proof_uart_rank;
    token_only_model0_uart_bridge #(.CLKS_PER_BIT(217)) u_actual_token_uart (
        .clk(core_clk),.rst_n(token_reset_n),.transport_pause_i(home_mode_q),
        .publication_allowed_i(publication_allowed_o),.uart_quiet_o(token_uart_quiet),
        .uart_rx_i(proof_serial_rx),.uart_tx_o(token_uart_tx),
        .cmd_ready_i(proof_command_ready),.out_valid_i(proof_result_valid),.out_token_i(proof_result_token),
        .proof_flight_o(proof_uart_flight),.proof_first_o(proof_uart_first),
        .proof_quiet_o(proof_uart_quiet),.proof_elapsed_o(proof_uart_elapsed),.proof_rank_o(proof_uart_rank));
    always_comb begin
        if(proof_uart_first) begin
            assert(publication_allowed_o && inference_enabled_o && !home_mode_q);
            assert(spec_permitted && admitted_root_i==spec_model);
            assert(lease_cycles_remaining_o>20000);
        end
        if(proof_uart_flight) begin
            assert(token_reset_n && inference_enabled_o && spec_permitted);
            assert(!home_mode_q);
            assert(admitted_root_i==spec_model);
            assert(lease_cycles_remaining_o>64'(proof_uart_rank));
            assert(proof_uart_elapsed<=10855);
        end
        if(!inference_enabled_o) begin
            assert(!proof_uart_first && !proof_uart_flight);
            assert(!proof_raw_valid && !proof_model_ready && !proof_kv_ready);
            if(!home_mode_q) assert(uart_tx==1'b1);
        end
    end
