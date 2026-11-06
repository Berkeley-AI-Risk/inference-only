    // Universally quantified arbitrary signature byte. The real synchronous
    // 1292-byte RAM is retained; no replacement memory model is assumed.
    (* anyconst *) logic [10:0] spec_watch;
    logic spec_initial=1;
    always_ff @(posedge clk) spec_initial<=0;
    always_comb if(spec_initial) assume(!reset_n);
    logic spec_written;
    logic [7:0] spec_value;
    always_comb assume(spec_watch<1292);
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin spec_written<=0;spec_value<=0;end
        else begin
            if(state_q==SEND && request_ready_i && index_q==127) spec_written<=0;
            if(state_q==RECEIVE && grant_valid_i && grant_ready_o && index_q==spec_watch+128) begin
                spec_written<=1;spec_value<=grant_byte_i;
            end
        end
    end
    always_comb if(reset_n) begin
        assert(state_q==COLLECT || state_q==SEND || state_q==RECEIVE || state_q==ARM ||
               state_q==ARM_WAIT || state_q==START || state_q==VERIFY || state_q==RUN || state_q==FAIL);
        if(fault_q) assert(state_q==FAIL);
        if(state_q==SEND) assert(index_q<=127);
        if(state_q==RECEIVE) begin
            assert(index_q<=1419);
            if(index_q>spec_watch+128) assert(spec_written);
        end
        if(spec_written) assert(signature_mem[spec_watch]==spec_value);
        if(state_q==ARM || state_q==ARM_WAIT || state_q==START || state_q==VERIFY || state_q==RUN)
            assert(spec_written);
        if((state_q==ARM_WAIT || state_q==START || state_q==VERIFY || state_q==RUN) &&
           signature_ready && signature_address==spec_watch)
            assert(shared_signature_byte_o==spec_value);
    end
