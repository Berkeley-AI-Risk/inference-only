    // Controller proof: binary clocked state with an abstract SHA child that
    // completes only after a complete page. Hash value correctness is separate.
    logic spec_initial=1;
    always_ff @(posedge clk) spec_initial<=0;
    always_comb if(spec_initial) assume(!reset_n);
    logic [23:0] spec_inputs;
    logic [11:0] spec_pages;
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin spec_inputs<=0;spec_pages<=0;end
        else if(!fault_o) begin
            if(input_fire) spec_inputs<=spec_inputs+1;
            if(state_q==WAIT_HASH && sha_done && sha_digest==expected_q)
                spec_pages<=spec_pages+1;
        end
    end
    always_comb if(reset_n) begin
        assert(state_q==IDLE || state_q==PAGE_START || state_q==EXPECT_READ ||
               state_q==EXPECT_CAPTURE || state_q==PAYLOAD || state_q==ZERO_TAIL ||
               state_q==WAIT_HASH || state_q==VERIFIED || state_q==FAILED);
        assert(page_q<PAGES);
        assert(page_byte_q<PAGE_BYTES);
        assert(spec_inputs<=IMAGE_BYTES);
        assert(spec_pages<=PAGES);
        if(fault_q) assert(state_q==FAILED);
        if(verified_o) begin
            assert(spec_inputs==IMAGE_BYTES);
            assert(spec_pages==PAGES);
            assert(page_q==PAGES-1);
            assert(!readback_ready_o && !digest_read_o);
        end
        if(state_q!=VERIFIED && state_q!=FAILED) assert(spec_pages=={1'b0,page_q});
        if(state_q==IDLE || state_q==PAGE_START || state_q==EXPECT_READ || state_q==EXPECT_CAPTURE)
            assert(spec_inputs==24'(page_q*PAGE_BYTES));
        if(state_q==EXPECT_READ || state_q==EXPECT_CAPTURE) assert(page_byte_q==0);
        if(state_q==PAYLOAD) begin
            assert(spec_inputs==24'(page_q*PAGE_BYTES)+24'(page_byte_q));
            if(page_q==PAGES-1) assert(page_byte_q<TAIL_BYTES);
        end
        if(state_q==ZERO_TAIL) begin
            assert(page_q==PAGES-1);
            assert(spec_inputs==IMAGE_BYTES);
            assert(page_byte_q>=TAIL_BYTES);
            assert(!readback_ready_o);
        end
        if(state_q==WAIT_HASH)
            assert(spec_inputs==24'(page_q*PAGE_BYTES)+24'(page_q==PAGES-1 ? TAIL_BYTES : PAGE_BYTES));
        if(digest_read_o) assert(digest_address_o<PAGES*8);
        if(readback_ready_o) assert(state_q==PAYLOAD && !fault_o);
    end
    logic spec_past_valid=0;
    always_ff @(posedge clk) begin
        spec_past_valid<=1;
        if(spec_past_valid && reset_n && $past(reset_n)) begin
            if($past(fault_o)) assert(fault_o);
            if($past(state_q==WAIT_HASH && sha_done && sha_digest!=expected_q))
                assert(fault_o && !verified_o);
            if($past(state_q==PAYLOAD && input_fire && readback_last_i!=final_input))
                assert(fault_o && !verified_o);
        end
    end
