    reg f_descriptor_owned;
    reg [ADDR_W-1:0] f_fixed_base;
    reg [2:0] f_layer;
    reg [3:0] f_job;
    reg [5:0] f_group;
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            f_descriptor_owned<=0;f_fixed_base<=0;f_layer<=0;f_job<=0;f_group<=0;
        end else if (start_valid_i && start_ready_o && descriptor_valid && !clear_i &&
            !upstream_fail_closed_i && !(private_word_rsp_valid_i && !request_outstanding_q) &&
            !(private_word_rsp_fault_i && response_transfer)) begin
            f_descriptor_owned<=1;f_fixed_base<=descriptor_base_word;
            f_layer<=fixed_layer_i;f_job<=fixed_job_i;f_group<=fixed_group_i;
        end
    end
    always_comb begin
        if (reset_n) begin
            if (descriptor_valid) begin
                assert(descriptor_base_word>=METADATA_BASE_WORD);
                assert(descriptor_base_word+7 < METADATA_BASE_WORD+2328);
            end
            if (f_descriptor_owned) begin
                assert(f_fixed_base>=METADATA_BASE_WORD && f_fixed_base+7<METADATA_BASE_WORD+2328);
                assert(group_base_word_q==f_fixed_base);
                assert(layer_q==f_layer && job_q==f_job && group_q==f_group);
            end
            if (state_q==ST_REQUEST || state_q==ST_WAIT || state_q==ST_EMIT || state_q==ST_DONE)
                assert(f_descriptor_owned);
            if (private_word_req_valid_o) begin
                assert(state_q==ST_REQUEST && !clear_i && !fail_closed_o && model_locked_i);
                assert(private_word_req_index_o==f_fixed_base+ADDR_W'(word_in_group_q));
                assert(private_word_req_index_o>=METADATA_BASE_WORD && private_word_req_index_o<METADATA_BASE_WORD+2328);
            end
            if (metadata_valid_o) begin
                assert(current_lane_is_real && current_real_record_is_legal);
                assert(metadata_row_index_o==({7'd0,f_group}<<6)+{7'd0,current_lane});
            end
            cover(private_word_req_valid_o && private_word_req_ready_i);
        end
    end
