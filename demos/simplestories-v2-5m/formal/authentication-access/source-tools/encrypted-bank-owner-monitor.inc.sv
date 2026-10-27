    // Hash requests/returns are wired to the complete actual four-bank pool.
    // Crypto replies and producer/consumer traffic remain unrestricted.
    logic f_hash_owned_q;
    logic [255:0] f_hash_chain_q;
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin f_hash_owned_q<=0;f_hash_chain_q<=0;end
        else if(hash_request_valid_o && hash_request_ready_i) begin
            f_hash_owned_q<=1;f_hash_chain_q<=chain_q;
        end else if(hash_response_valid_i) f_hash_owned_q<=0;
    end
    always_ff @(posedge clk) if(reset_n && !fault_o) begin
        assert(state_q<=CR_STORE);
        assert(block_q<=64);
        if(hash_pending_i || hash_response_valid_i)
            assert(f_hash_owned_q && chain_q==f_hash_chain_q);
        if(state_q==READ0 || state_q==READ1 || state_q==CAP1 || state_q==LAUNCH)
            assert(!hash_pending_i && !hash_response_valid_i);
        if(state_q==COMPARE || verified_o) assert(!hash_pending_i && !hash_response_valid_i);
    end
