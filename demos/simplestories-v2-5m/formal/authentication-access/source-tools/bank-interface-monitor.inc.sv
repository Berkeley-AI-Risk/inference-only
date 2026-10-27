    // This reference is a single pending request, not an authentication oracle.
    // No private SHA or crypto behavior is assumed by these interface facts.
    logic f_ref_pending_q;
    logic [6:0] f_ref_word_q;
    logic [10:0] f_ref_page_q;
    logic f_ref_past_valid=0;
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin f_ref_pending_q<=0;f_ref_word_q<=0;f_ref_page_q<=0;end
        else if(cancel_read_i) f_ref_pending_q<=0;
        else if(read_fire) begin
            f_ref_pending_q<=1;f_ref_word_q<=read_word_i;f_ref_page_q<=page_o;
        end else if(response_valid_o && response_ready_i) f_ref_pending_q<=0;
    end
    always_ff @(posedge clk) begin
        f_ref_past_valid<=1;
        if(reset_n) begin
            assert(fault_o==(state_q==FAILED));
            if(f_ref_past_valid && $past(reset_n) && $past(fault_o)) assert(fault_o);
            if(!fault_o) begin
                assert(response_valid_q==f_ref_pending_q);
                if(response_valid_q) assert(verified_o);
                if(f_ref_pending_q) begin
                    assert(verified_o && f_ref_word_q<valid_words_q);
                    assert(f_ref_page_q==page_o);
                end
                assert(response_valid_o==(f_ref_pending_q && !cancel_read_i));
                if(read_ready_o) assert(verified_o && !cancel_read_i && !begin_valid_i &&
                    (!f_ref_pending_q || response_ready_i));
                if(begin_fire) assert(!f_ref_pending_q && !read_fire);
                if(!response_valid_o) assert(response_data_o==0);
                if(cancel_read_i) assert(!read_ready_o && !response_valid_o);
                cover(begin_fire);
            end
        end
    end
