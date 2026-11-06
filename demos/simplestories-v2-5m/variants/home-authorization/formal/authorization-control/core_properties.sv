    // This is the selected top-level permit register / mux and selected
    // runtime reset release chain, copied byte-for-byte by the runner.
    wire core_clk=clk, core_reset_n=reset_n;
    wire home_failed=failed_o, home_accepted=new_lease_o;
    wire home_enabled=inference_enabled_o, home_request_valid=request_valid_o;
    (* anyseq *) wire home_transport_fault, token_uart_quiet, home_uart_tx, token_uart_tx;
    wire uart_tx;
    // INSERT_ACTUAL_CORE_BLOCK
    wire app_clk_i=clk, reset_n_i=token_reset_n;
    // INSERT_ACTUAL_RUNTIME_RESET
    (* anyseq *) wire proof_model_valid,proof_kv_valid,proof_write,proof_raw_ready,proof_kv_rsp_ready,proof_rsp_valid,proof_rsp_error;
    (* anyseq *) wire [18:0] proof_model_word,proof_kv_word;
    (* anyseq *) wire [255:0] proof_data,proof_response_data;
    wire proof_raw_valid,proof_model_ready,proof_kv_ready;
    board1_private_shared_ddr_arbiter u_actual_runtime_gate (
        .clk(clk),.reset_n(app_runtime_reset_n),
        .model_locked_i(admitted_root_valid_i),.upstream_fault_i(model_fault_i),
        .model_req_valid_i(proof_model_valid),.model_req_word_i(proof_model_word),
        .model_req_ready_o(proof_model_ready),
        .kv_req_valid_i(proof_kv_valid),.kv_req_word_i(proof_kv_word),
        .kv_req_write_i(proof_write),.kv_req_data_i(proof_data),.kv_req_ready_o(proof_kv_ready),
        .kv_rsp_ready_i(proof_kv_rsp_ready),.raw_req_valid_o(proof_raw_valid),
        .raw_req_ready_i(proof_raw_ready),.raw_rsp_valid_i(proof_rsp_valid),
        .raw_rsp_error_i(proof_rsp_error),.raw_rsp_data_i(proof_response_data));
    always_comb begin
        if(reset_n) begin
            assert(state_q==COLLECT || state_q==SEND || state_q==RECEIVE || state_q==ARM ||
                   state_q==ARM_WAIT || state_q==START || state_q==VERIFY || state_q==RUN || state_q==FAIL);
            if(fault_q) assert(state_q==FAIL);
            if(state_q==SEND || state_q==RECEIVE || state_q==ARM || state_q==ARM_WAIT ||
               state_q==START || state_q==VERIFY || state_q==RUN) assert(have_root_q);
            if(lease_active_q) assert(have_root_q);
            if(token_reset_n) assert(lease_active_q && !failed_o);
            if(app_runtime_reset_n) assert(token_reset_n);
        end
        if(!inference_enabled_o) begin
            assert(!token_reset_n);
            assert(!app_runtime_reset_n);
            assert(!proof_raw_valid && !proof_model_ready && !proof_kv_ready);
            if(!home_mode_q) assert(uart_tx==1'b1);
        end
        if(home_stop_q || home_transport_fault || failed_o) assert(!token_reset_n);
    end
