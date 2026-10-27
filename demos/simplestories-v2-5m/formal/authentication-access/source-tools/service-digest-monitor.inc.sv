    // One arbitrary lane denotes every word of the complete fixed digest.
    (* anyconst *) logic [2:0] f_digest_lane;
    wire [31:0] f_reference_word=digest_rom[{fill_page_q,f_digest_lane}];
    wire f_digest_active=dma_state_q==ROM_READ || dma_state_q==ROM_CAPTURE;
    wire [2:0] f_partial_slot=digest_word_q-3'd1-f_digest_lane;
    always_ff @(posedge clk) if(reset_n && !fault_o) begin
        assert(dma_state_q<=SCAN);
        if(dma_state_q!=IDLE) assert(locked_seen_q);
        if(f_digest_active || dma_state_q==ALLOCATE || dma_state_q==FILL)
            assert(fill_page_q<PAGES);
        if(dma_state_q==ROM_CAPTURE)
            assert(digest_data_q==digest_rom[{fill_page_q,digest_word_q}]);
        // After n captures, reference lane j<n is n-1-j words from the LSB.
        // This relation does not assume initial values of the resetless buffer.
        if(f_digest_active && f_digest_lane<digest_word_q)
            assert(expected_digest_q[int'(f_partial_slot)*32 +: 32]==f_reference_word);
        if(dma_state_q==ALLOCATE || dma_state_q==FILL)
            assert(expected_digest_q[(7-int'(f_digest_lane))*32 +: 32]==f_reference_word);
        if(|bank_begin_valid) begin
            assert(dma_state_q==ALLOCATE && enabled && fill_page_q<PAGES);
            assert(expected_digest_q[(7-int'(f_digest_lane))*32 +: 32]==f_reference_word);
        end
        cover(|(bank_begin_valid & bank_begin_ready));
    end
