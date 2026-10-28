    reg f_request_owned,f_posted,f_value_owned;
    reg [ADDR_W-1:0] f_word_shadow;
    reg [3:0] f_lane_shadow;
    reg signed [15:0] f_value_shadow;
    always @(posedge clk)begin
        if(!reset_n || clear_i)begin f_request_owned<=0;f_posted<=0;f_value_owned<=0;end
        else begin
            if(request_transfer && descriptor_valid)begin
                f_request_owned<=1;f_word_shadow<=derived_word_index;
                f_lane_shadow<=derived_lane;f_value_owned<=0;
            end
            if(private_request_transfer)f_posted<=1;
            if(private_response_transfer)f_posted<=0;
            if(state_q==ST_WAIT && private_response_transfer && !global_fault && !response_side_fault)begin
                f_value_owned<=1;
                f_value_shadow<=private_word_rsp_data_i[f_lane_shadow*16 +:16];
            end
            if(response_transfer)begin f_request_owned<=0;f_value_owned<=0;end
        end
    end
    always @*if(reset_n && !clear_i && !fail_q && !global_fault && !response_side_fault)begin
        if(state_q==ST_ISSUE || state_q==ST_WAIT || state_q==ST_HOLD)begin
            assert(f_request_owned);assert(word_index_q==f_word_shadow);assert(lane_q==f_lane_shadow);
        end
        if(state_q==ST_WAIT)assert(f_posted);
        if(state_q==ST_IDLE || state_q==ST_ISSUE || state_q==ST_HOLD)assert(!f_posted);
        if(private_request_transfer)begin assert(f_request_owned);assert(!f_posted);end
        if(response_valid_o && !response_fault_o)begin
            assert(f_value_owned);assert(response_value_o==f_value_shadow);assert(!f_posted);
        end
        if(state_q==ST_DRAIN)begin assert(!request_ready_o);assert(!response_valid_o);end
        cover(response_valid_o && !response_fault_o);
        cover(state_q==ST_DRAIN && !f_posted);
    end
