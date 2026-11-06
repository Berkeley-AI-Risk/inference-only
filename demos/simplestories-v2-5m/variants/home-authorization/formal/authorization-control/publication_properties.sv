    // Only frame admission is gated by publication_allowed_i. Subsequent
    // bytes intentionally drain. The chip-level mux separately clamps token
    // serial output as soon as the lease fails/expires.
    always_comb begin
        if(out_ready_o) assert(publication_allowed_i && !transport_pause_i);
        if(tx_valid && tx_ready && response_index_q==0)
            assert(publication_allowed_i && !transport_pause_i);
        if(transport_pause_i) assert(!tx_valid && !out_ready_o && !cmd_valid_o);
        if(uart_quiet_o) begin
            assert(tx_ready);
            assert(state_q!=BRIDGE_DRAIN);
            if(state_q==BRIDGE_SEND) assert(response_index_q==0 && !publication_allowed_i);
        end
        if(!rst_n) assert(!cmd_valid_o && !out_ready_o);
    end
    logic publication_past=0;
    always_ff @(posedge clk) begin
        publication_past<=1;
        if(publication_past && rst_n && $past(rst_n)) begin
            if($past(state_q)==BRIDGE_SEND && $past(response_index_q)==0 &&
               !$past(publication_allowed_i)) assert(response_index_q==0);
        end
    end
