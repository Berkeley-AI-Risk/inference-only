    reg f_descriptor_owned;
    reg [ADDR_W-1:0] f_fixed_word;
    reg [3:0] f_fixed_lane;
    reg [15:0] f_received_value;
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            f_descriptor_owned<=0;f_fixed_word<=0;f_fixed_lane<=0;f_received_value<=0;
        end else begin
            if (request_transfer && descriptor_valid && !global_fault && !response_side_fault && !clear_i) begin
                f_descriptor_owned<=1;f_fixed_word<=derived_word_index;f_fixed_lane<=derived_lane;
            end
            if (private_response_transfer && state_q==ST_WAIT && !global_fault && !response_side_fault && !clear_i)
                f_received_value<=private_word_rsp_data_i[f_fixed_lane*16 +:16];
        end
    end
    always_comb begin
        if (reset_n) begin
            if (descriptor_valid) begin
                assert(derived_word_index<MODEL_WORDS);
                assert(derived_word_index>=ROPE_COS_BASE_WORD);
                assert(!(derived_word_index>=214773 && derived_word_index<SILU_BASE_WORD));
            end
            if (f_descriptor_owned) assert(word_index_q==f_fixed_word && lane_q==f_fixed_lane);
            if (state_q==ST_ISSUE || state_q==ST_WAIT || state_q==ST_HOLD)
                assert(f_descriptor_owned);
            if (private_word_req_valid_o) begin
                assert(private_word_req_index_o==f_fixed_word);
                assert(private_word_req_index_o<MODEL_WORDS && private_word_req_index_o>=ROPE_COS_BASE_WORD);
                assert(!(private_word_req_index_o>=214773 && private_word_req_index_o<SILU_BASE_WORD));
            end
            if (response_valid_o && !clear_i && !global_fault && !response_side_fault && !fail_q && !response_fault_o)
                assert(response_value_o==f_received_value);
            cover(private_word_req_valid_o && private_word_req_ready_i);
            cover(response_valid_o && !response_fault_o && !clear_i && !global_fault);
        end
    end
