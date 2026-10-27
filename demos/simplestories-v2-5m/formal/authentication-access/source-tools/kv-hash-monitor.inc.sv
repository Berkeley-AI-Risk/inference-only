    // Reference message: a 64-byte identity header followed by 5*positions
    // 32-byte words, with SHA-256 byte ordering and standard SHA padding.
    logic f_kv_active_q,f_kv_owned_q;
    logic [511:0] f_kv_header_q;
    logic [255:0] f_kv_chain_q,f_kv_owned_chain_q;
    logic [255:0] f_kv_even_q,f_kv_odd_q;
    logic [1:0] f_kv_halves_q;
    logic [6:0] f_kv_words_q,f_kv_total_q,f_kv_calls_q,f_kv_returns_q;
    logic [63:0] f_kv_length_q;
    wire f_kv_legal=layer_i<6 && positions_i>=1 && positions_i<=16;
    wire f_kv_wait=state_q==HWAIT || state_q==DWAIT || state_q==PWAIT;
    function automatic [255:0] f_kv_bytes(input [255:0] value);
        for(integer j=0;j<256;j=j+8)
            f_kv_bytes[j +:8]=value[255-j -:8];
    endfunction
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            f_kv_active_q<=0;f_kv_owned_q<=0;f_kv_header_q<=0;
            f_kv_chain_q<=IV;f_kv_owned_chain_q<=IV;
            f_kv_even_q<=0;f_kv_odd_q<=0;f_kv_halves_q<=0;
            f_kv_words_q<=0;f_kv_total_q<=0;f_kv_length_q<=0;
            f_kv_calls_q<=0;f_kv_returns_q<=0;
        end else if(clear_i) begin
            f_kv_active_q<=0;f_kv_owned_q<=0;f_kv_chain_q<=IV;
            f_kv_halves_q<=0;f_kv_words_q<=0;f_kv_calls_q<=0;f_kv_returns_q<=0;
        end else begin
            if(begin_fire) begin
                f_kv_active_q<=f_kv_legal;
                if(f_kv_legal) begin
                    f_kv_header_q<={128'h@DOMAIN@,epoch_i,32'(layer_i),32'(page_i),32'(head_i),32'(role_i),
                        32'(positions_i),32'd16,32'd32,96'd0};
                    f_kv_total_q<=7'(5*int'(positions_i));
                    f_kv_length_q<=64'(8*(64+160*int'(positions_i)));
                    f_kv_chain_q<=IV;f_kv_halves_q<=0;f_kv_words_q<=0;
                    f_kv_calls_q<=0;f_kv_returns_q<=0;
                end
            end else begin
                if(state_q==RESULT && digest_ready_i) f_kv_active_q<=0;
                if(word_fire) begin
                    f_kv_words_q<=f_kv_words_q+7'd1;
                    if(!f_kv_words_q[0]) begin f_kv_even_q<=word_i;f_kv_halves_q[0]<=1;end
                    else begin f_kv_odd_q<=word_i;f_kv_halves_q[1]<=1;end
                end
                if(sha_start) begin f_kv_calls_q<=f_kv_calls_q+7'd1;f_kv_halves_q<=0;end
                if(sha_done) begin f_kv_returns_q<=f_kv_returns_q+7'd1;f_kv_chain_q<=sha_state;end
            end
            if(sha_start) begin f_kv_owned_q<=1;f_kv_owned_chain_q<=hash_q;end
            else if(sha_done) f_kv_owned_q<=0;
        end
    end
    always_ff @(posedge clk) if(reset_n && !clear_i) begin
        assert(state_q<=FAULT);
        assert(!(sha_busy && sha_done));
        if(sha_busy || sha_done) assert(f_kv_wait && f_kv_owned_q && hash_q==f_kv_owned_chain_q);
        if(f_kv_wait) assert(sha_busy || sha_done);
        if(sha_start) assert(!sha_busy && !sha_done);
        if(fault_o) assert(!begin_ready_o && !word_ready_o && !digest_valid_o && digest_o==0);
        if(!fault_o) begin
            assert(hash_q==f_kv_chain_q);
            assert(f_kv_active_q==(state_q!=IDLE));
            assert(f_kv_owned_q==f_kv_wait);
            if(state_q!=HIGH && state_q!=DSTART) assert(f_kv_halves_q==0);
            if(state_q==HIGH) assert(block_q[511:256]==f_kv_bytes(f_kv_even_q));
            if(f_kv_active_q) begin
                assert(f_kv_total_q>=5 && f_kv_total_q<=80);
                assert(total_words_q==f_kv_total_q && words_q==f_kv_words_q && words_q<=total_words_q);
                assert(header_q==f_kv_header_q && length_bits_q==f_kv_length_q);
                assert(f_kv_total_q==7'(5*int'(f_kv_header_q[191:160])));
                assert(f_kv_length_q==64'(512+256*int'(f_kv_total_q)));
                if(state_q!=DSTART && state_q!=DWAIT && state_q!=RESULT) assert(!final_data_block_q);
                assert(f_kv_calls_q<=42 && f_kv_returns_q<=f_kv_calls_q);
                assert(f_kv_calls_q==f_kv_returns_q || f_kv_calls_q==f_kv_returns_q+7'd1);
                if(state_q==HSTART) assert(words_q==0 && f_kv_calls_q==0 && f_kv_returns_q==0);
                if(state_q==HWAIT) assert(words_q==0 && f_kv_calls_q==1 && f_kv_returns_q==0);
                if(state_q==LOW || state_q==HIGH) begin
                    assert(words_q<total_words_q);
                    assert(words_q[0]==(state_q==HIGH));
                    assert(f_kv_calls_q==7'd1+(words_q>>1) && f_kv_returns_q==f_kv_calls_q);
                    assert(f_kv_halves_q==(state_q==HIGH ? 2'd1 : 2'd0));
                end
                if(state_q==DSTART || state_q==DWAIT) begin
                    assert(words_q!=0);
                    assert(!words_q[0] || words_q==total_words_q);
                    assert(final_data_block_q==words_q[0]);
                    assert(f_kv_calls_q==(state_q==DSTART ? 7'd1 : 7'd2)+((words_q-7'd1)>>1));
                    assert(f_kv_returns_q==f_kv_calls_q-(state_q==DWAIT ? 7'd1 : 7'd0));
                end
                if(state_q==DSTART) begin
                    assert(f_kv_halves_q==(words_q[0] ? 2'd1 : 2'd3));
                    assert(sha_block[511:256]==f_kv_bytes(f_kv_even_q));
                    if(words_q[0]) assert(sha_block[255:0]=={1'b1,191'd0,f_kv_length_q});
                    else assert(sha_block[255:0]==f_kv_bytes(f_kv_odd_q));
                end
                if(state_q==PSTART || state_q==PWAIT) begin
                    assert(words_q==total_words_q && !words_q[0] && !final_data_block_q);
                    assert(f_kv_calls_q==(state_q==PSTART ? 7'd1 : 7'd2)+(total_words_q>>1));
                    assert(f_kv_returns_q==f_kv_calls_q-(state_q==PWAIT ? 7'd1 : 7'd0));
                end
                if(state_q==RESULT) begin
                    assert(words_q==total_words_q && final_data_block_q==total_words_q[0]);
                    assert(f_kv_calls_q==7'd2+(total_words_q>>1) && f_kv_returns_q==f_kv_calls_q);
                end
            end
            if(sha_start && state_q==HSTART) assert(sha_block==f_kv_header_q && hash_q==IV);
            if(sha_start && state_q==PSTART) assert(sha_block=={1'b1,447'd0,f_kv_length_q});
            if(digest_valid_o) assert(f_kv_active_q && state_q==RESULT && digest_o==f_kv_chain_q);
            if(!digest_valid_o) assert(digest_o==0);
        end
        cover(sha_start && state_q==HSTART);
        cover(digest_valid_o && digest_o==256'h@COVER_DIGEST@);
    end
