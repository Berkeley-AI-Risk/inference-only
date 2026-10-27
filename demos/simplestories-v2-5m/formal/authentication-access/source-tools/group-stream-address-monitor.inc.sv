    reg f_descriptor_owned;
    reg [ADDR_W-1:0] f_fixed_base;
    reg [2:0] f_layer;
    reg [3:0] f_job;
    reg [5:0] f_group;
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            f_descriptor_owned<=0;f_fixed_base<=0;f_layer<=0;f_job<=0;f_group<=0;
        end else if (descriptor_transfer && descriptor_valid && !clear_i &&
            !fail_closed_q && !meta_fail && !upstream_fail_closed_i &&
            !(private_word_rsp_valid_i && owner_q==OWNER_NONE) &&
            !(owner_q==OWNER_WEIGHT && private_word_rsp_valid_i && outstanding_words_q==0) &&
            !(weight_response_accept && private_word_rsp_fault_i)) begin
            f_descriptor_owned<=1;f_fixed_base<=descriptor_word_base_wide[ADDR_W-1:0];
            f_layer<=fixed_layer_i;f_job<=fixed_job_i;f_group<=fixed_group_i;
        end
    end
    always_comb begin
        if (reset_n) begin
            if (descriptor_valid) begin
                assert(descriptor_columns==256 || descriptor_columns==682);
                assert(descriptor_word_base_wide+({11'd0,descriptor_columns}*21'd5/21'd2)<=211800);
            end
            if (f_descriptor_owned) begin
                assert(weight_base_word_q==f_fixed_base);
                assert(layer_q==f_layer && job_q==f_job && group_q==f_group);
            end
            assert({1'b0,weight_base_word_q}+group_words_q<=211800);
            if (state_q==ST_META_START || state_q==ST_META_RUN || state_q==ST_HEADER || state_q==ST_WEIGHT || state_q==ST_DONE)
                assert(f_descriptor_owned);
            if (private_word_req_valid_o) begin
                assert(private_word_req_index_o<211800 ||
                    (private_word_req_index_o>=METADATA_BASE_WORD && private_word_req_index_o<METADATA_BASE_WORD+2328));
                if (owner_q==OWNER_WEIGHT) begin
                    assert(state_q==ST_WEIGHT && issued_words_q<group_words_q);
                    assert(private_word_req_index_o==f_fixed_base+ADDR_W'(issued_words_q));
                end else begin
                    assert(owner_q==OWNER_META && private_word_req_index_o==meta_req_index && meta_req_valid);
                end
            end
            if (group_valid_o) begin
                assert(group_layer_o==f_layer && group_job_o==f_job && group_index_o==f_group);
                assert(metadata_count_q==valid_lanes_q);
            end
            cover(descriptor_transfer && descriptor_valid);
        end
    end
