    reg f_word_owned;
    reg [255:0] f_word_shadow;
    reg [2:0] f_word_tag;
    wire f_capture_word=state_q==ST_WAIT && response_transfer && model_locked_i &&
        !upstream_fail_closed_i && !private_word_rsp_fault_i && !start_valid_i;
    always @(posedge clk)begin
        if(!reset_n || clear_i || request_transfer || (start_valid_i && start_ready_o))f_word_owned<=0;
        else if(f_capture_word)begin
            f_word_owned<=1;f_word_shadow<=private_word_rsp_data_i;f_word_tag<=word_in_group_q;
        end
    end
    always @*if(reset_n && !clear_i && !fail_closed_o)begin
        if(f_word_owned)assert(response_word_q==f_word_shadow);
        if(state_q==ST_EMIT)begin assert(f_word_owned);assert(f_word_tag==word_in_group_q);end
        if(metadata_valid_o)begin
            assert(f_word_owned);
            assert(metadata_exponent_o==$signed(f_word_shadow[record_in_word_q*32 +:8]));
            assert(metadata_multiplier_o==f_word_shadow[record_in_word_q*32+8 +:16]);
        end
        if(state_q==ST_DRAIN)begin assert(!metadata_valid_o);assert(!start_ready_o);end
    end
