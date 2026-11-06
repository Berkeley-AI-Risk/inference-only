    // First byte accepted -> all five 10-bit bytes drain and bridge becomes
    // quiet within 5*(10*217)+4 inter-byte edges+1 bridge edge = 10855 clocks.
    // Reset/pause abort the obligation; the composition separately proves
    // that nonterminal authorization transport cannot pause a partial packet.
    logic spec_flight;
    logic [13:0] spec_elapsed;
    wire spec_first=tx_valid && tx_ready && response_index_q==0;
    wire [13:0] spec_rank=(state_q==BRIDGE_SEND && response_index_q!=0) ?
        (14'd5-14'(response_index_q))*14'd2171+14'(proof_tx_remaining)+14'd1 :
        state_q==BRIDGE_DRAIN ? 14'(proof_tx_remaining)+14'd1 : 14'd0;
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin spec_flight<=0;spec_elapsed<=0;end
        else if(transport_pause_i) begin spec_flight<=0;spec_elapsed<=0;end
        else if(spec_first) begin spec_flight<=1;spec_elapsed<=0;end
        else if(spec_flight) begin
            if(uart_quiet_o) spec_flight<=0;
            else spec_elapsed<=spec_elapsed+1'b1;
        end
    end
    always_comb if(rst_n) begin
        assert(state_q==BRIDGE_IDLE || state_q==BRIDGE_OFFER || state_q==BRIDGE_WAIT_RESULT ||
               state_q==BRIDGE_SEND || state_q==BRIDGE_DRAIN);
        if(state_q==BRIDGE_SEND) assert(response_index_q<=4);
        if(state_q==BRIDGE_DRAIN) assert(response_index_q==4);
    end
    always_comb if(rst_n && !transport_pause_i) begin
        if(spec_flight) begin
            assert(uart_quiet_o || state_q==BRIDGE_DRAIN ||
                   (state_q==BRIDGE_SEND && response_index_q>=1 && response_index_q<=4));
            assert(spec_elapsed+spec_rank==14'd10855);
            assert(spec_elapsed<=10855);
            if(!uart_quiet_o) assert(spec_rank>0);
            if(spec_elapsed==10855) assert(uart_quiet_o);
        end
    end
