    // Observe actual accepted compressor calls. No owner promise is assumed.
    logic f_sha_owned_q;
    logic [255:0] f_sha_chain_q;
    logic [511:0] f_sha_block_q;
    logic f_owner_past_valid=0;
    wire f_sha_start=(state_q==LAUNCH && !fault_o);
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            f_sha_owned_q<=0;f_sha_chain_q<=0;f_sha_block_q<=0;
        end else if(f_sha_start && !sha_busy) begin
            f_sha_owned_q<=1;f_sha_chain_q<=chain_q;f_sha_block_q<=sha_block_q;
        end else if(sha_done) f_sha_owned_q<=0;
    end
    always_ff @(posedge clk) begin
        f_owner_past_valid<=1;
        if(reset_n) begin
            assert(state_q<=READY || state_q==FAILED);
            assert(fault_o==(state_q==FAILED));
            assert(!(sha_busy && sha_done));
            if(sha_busy || sha_done) assert(state_q==HASH || state_q==FAILED);
            if(state_q==HASH && !fault_o) assert(sha_busy || sha_done);
            if(sha_busy || sha_done) assert(f_sha_owned_q);
            if(f_sha_owned_q && (sha_busy || sha_done)) assert(chain_q==f_sha_chain_q);
            if(f_sha_start) assert(!sha_busy && !sha_done);
            if(sha_done && state_q==HASH) assert(f_sha_owned_q && chain_q==f_sha_chain_q);
            if(verified_o) assert(!sha_busy && !sha_done);
            if(f_owner_past_valid && $past(reset_n)) begin
                if($past(begin_fire)) assert(chain_q==SHA_IV);
                else if($past(state_q==HASH && sha_done)) assert(chain_q==$past(sha_state));
                else assert(chain_q==$past(chain_q));
                if($past(f_sha_start && !sha_busy)) begin
                    assert(f_sha_owned_q && f_sha_chain_q==$past(chain_q));
                    assert(f_sha_block_q==$past(sha_block_q));
                end
            end
            cover(f_sha_start && !sha_busy);
            cover(sha_done && state_q==HASH);
        end
    end
