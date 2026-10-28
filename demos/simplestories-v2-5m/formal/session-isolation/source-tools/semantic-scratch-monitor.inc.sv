    (* anyconst *) reg [9:0] f_word;
    reg f_rms_owned,f_query_owned,f_key_owned,f_value_owned;
    reg f_attention_owned,f_output_owned,f_gate_owned,f_up_owned;
    (* anyconst *) reg [4:0] f_rope_word;
    reg f_rope_owned,f_rope_read_live;
    reg [4:0] f_rope_read_tag;
    // This 1024-bit staging register deliberately has no data reset. Track
    // one arbitrary lane through each fresh 64-word query upload instead.
    reg f_query_lane_owned;
    reg f_rope_cos_owned,f_rope_sin_owned,f_rope_op0_owned,f_rope_op1_owned;
    reg f_rope_operand_read_live,f_rope_operand_is_query;
    reg [7:0] f_rope_operand_read_tag;
    wire f_new_attention=private_stage_valid_i && private_stage_ready_o &&
        private_stage_i==STAGE_ATTENTION;
    wire f_new_rope=private_stage_valid_i && private_stage_ready_o &&
        (private_stage_i==STAGE_Q_ROPE || private_stage_i==STAGE_K_ROPE);
    wire f_next_rope_head=engine_state_q==E_ROPE && rope_phase_q==RP_SECOND &&
        norm_input_fire && rope_second_index_q==31;
    wire f_layer_retire=engine_state_q==E_COMMIT && kv_commit_valid && kv_commit_ready;
    always @(posedge clk)begin
        if(!rst_n || clear_i || f_new_rope ||
           (engine_state_q==E_ROPE && rope_phase_q==RP_COS_REQ))begin
            f_rope_cos_owned<=0;f_rope_sin_owned<=0;f_rope_op0_owned<=0;f_rope_op1_owned<=0;
            f_rope_operand_read_live<=0;
        end else if(engine_state_q==E_ROPE)begin
            if(lookup_response_valid && lookup_response_ready && !lookup_response_fault)begin
                if(rope_phase_q==RP_COS_WAIT)f_rope_cos_owned<=1;
                if(rope_phase_q==RP_SIN_WAIT)f_rope_sin_owned<=1;
            end
            if(rope_phase_q==RP_OPERAND0_WAIT)f_rope_op0_owned<=1;
            if(rope_phase_q==RP_OPERAND1_WAIT)f_rope_op1_owned<=1;
            if(query_ram_read_enable || key_ram_read_enable)begin
                f_rope_operand_read_live<=1;
                f_rope_operand_is_query<=query_ram_read_enable;
                f_rope_operand_read_tag<=query_ram_read_enable ? query_ram_read_address : {1'b0,key_ram_read_address};
            end
        end
    end
    always @(posedge clk)begin
        if(!rst_n || clear_i || f_new_attention || attention_query_fire)
            f_query_lane_owned<=0;
        else if(engine_state_q==E_ATTN && attention_query_read_valid_q &&
                attention_query_load_lane_q==f_word[5:0])
            f_query_lane_owned<=1;
    end
    always @(posedge clk)begin
        if(!rst_n || clear_i || f_layer_retire)begin
            f_rms_owned<=0;f_query_owned<=0;f_key_owned<=0;f_value_owned<=0;
            f_attention_owned<=0;f_output_owned<=0;f_gate_owned<=0;f_up_owned<=0;
        end else begin
            if(rms_ram_write_enable && output_index_q==f_word)f_rms_owned<=1;
            if(query_ram_write_enable && {2'b0,output_index_q[7:0]}==f_word)f_query_owned<=1;
            if(key_ram_write_enable && {3'b0,output_index_q[6:0]}==f_word)f_key_owned<=1;
            if(value_ram_write_enable && {3'b0,output_index_q[6:0]}==f_word)f_value_owned<=1;
            if(attention_ram_write_enable && {2'b0,attention_ram_write_address}==f_word)f_attention_owned<=1;
            if(output_ram_write_enable && output_index_q==f_word)f_output_owned<=1;
            if(gate_write_enable && output_index_q==f_word)f_gate_owned<=1;
            if(up_write_enable && output_index_q==f_word)f_up_owned<=1;
        end
    end
    always @(posedge clk)begin
        if(!rst_n || clear_i || f_new_rope || f_next_rope_head)begin
            f_rope_owned<=0;f_rope_read_live<=0;
        end else begin
            if(rope_raw_ram_write_enable && rope_half_q==f_rope_word)f_rope_owned<=1;
            if(rope_raw_ram_read_enable)begin f_rope_read_live<=1;f_rope_read_tag<=rope_second_index_q;end
            if(engine_state_q==E_ROPE && rope_phase_q==RP_SECOND && norm_input_fire)f_rope_read_live<=0;
        end
    end
    always @*if(rst_n && !clear_i && !fault_q)begin
        if(expected_stage_q!=0 || expected_layer_q!=0 || transaction_seen_q)assert(lock_seen_q);
        if(engine_state_q==E_RMS)begin assert(output_index_q<=255);assert(input_index_q<=255);end
        if(engine_state_q==E_PROJ)begin
            assert(output_index_q<projection_result_count);
            assert(input_index_q<projection_activation_count);
        end
        if(engine_state_q==E_ELEM)begin
            assert(output_index_q<=((current_stage_q==STAGE_SILU_MUL)?681:255));
            assert(elem_index_q<=((current_stage_q==STAGE_SILU_MUL)?681:255));
        end
        if(engine_state_q==E_ROPE)assert(output_index_q<=((current_stage_q==STAGE_Q_ROPE)?255:127));
        if(engine_state_q==E_ATTN)begin assert(attention_head_q<=3);assert(attention_result_head_q<=3);end
        if(engine_state_q==E_ATTN)begin
            if(f_word[5:0]<attention_query_load_lane_q || attention_query_loaded_q)
                assert(f_query_lane_owned);
            if(attention_query_valid)begin
                assert(attention_query_loaded_q);assert(f_query_lane_owned);
            end
        end
        if(f_word<256)begin
            if(expected_stage_q>=1)assert(f_rms_owned);
            if(expected_stage_q>=2)assert(f_query_owned);
            if(expected_stage_q>=8)assert(f_attention_owned);
            if(expected_stage_q>=9)assert(f_output_owned);
            if(engine_state_q==E_RMS && (f_word<output_index_q || output_done_q))assert(f_rms_owned);
            if(engine_state_q==E_PROJ && current_stage_q==STAGE_Q &&
               (f_word<output_index_q || output_done_q))assert(f_query_owned);
            if(engine_state_q==E_PROJ && current_stage_q==STAGE_O &&
               (f_word<output_index_q || output_done_q))assert(f_output_owned);
            if(engine_state_q==E_ATTN && (output_done_q || {1'b0,f_word[7:0]}<
               {attention_result_head_q,attention_store_lane_q}))assert(f_attention_owned);
            if(rms_ram_read_enable)assert(f_rms_owned);
            if(query_ram_read_enable)assert(f_query_owned);
            if(attention_ram_read_enable)assert(f_attention_owned);
            if(output_ram_read_enable)assert(f_output_owned);
        end
        if(f_word<128)begin
            if(expected_stage_q>=3)assert(f_key_owned);
            if(expected_stage_q>=4)assert(f_value_owned);
            if(engine_state_q==E_PROJ && current_stage_q==STAGE_K &&
               (f_word<output_index_q || output_done_q))assert(f_key_owned);
            if(engine_state_q==E_PROJ && current_stage_q==STAGE_V &&
               (f_word<output_index_q || output_done_q))assert(f_value_owned);
            if(key_ram_read_enable)assert(f_key_owned);
            if(value_ram_read_enable)assert(f_value_owned);
        end
        if(f_word<682)begin
            if(expected_stage_q>=12)assert(f_gate_owned);
            if(expected_stage_q>=13)assert(f_up_owned);
            if(engine_state_q==E_PROJ && current_stage_q==STAGE_GATE &&
               (f_word<output_index_q || output_done_q))assert(f_gate_owned);
            if(engine_state_q==E_PROJ && current_stage_q==STAGE_UP &&
               (f_word<output_index_q || output_done_q))assert(f_up_owned);
            if(scratch_read_enable)assert(f_gate_owned);
            if(scratch_read_enable && engine_state_q==E_ELEM && current_stage_q==STAGE_SILU_MUL)
                assert(f_up_owned);
        end
        if(scratch_read_enable)assert(scratch_read_address<682);
        if(gate_write_enable || up_write_enable)assert(output_index_q<682);
        if(engine_state_q==E_ROPE)begin
            assert(rope_phase_q<=RP_SECOND_REQ);
            assert(rope_head_q<=((current_stage_q==STAGE_Q_ROPE)?3:1));
            if(rope_phase_q==RP_SIN_REQ || rope_phase_q==RP_SIN_WAIT ||
               rope_phase_q==RP_OPERAND0_REQ || rope_phase_q==RP_OPERAND0_WAIT ||
               rope_phase_q==RP_OPERAND1_REQ || rope_phase_q==RP_OPERAND1_WAIT ||
               rope_phase_q==RP_LANE_REQ || rope_phase_q==RP_LANE_WAIT)assert(f_rope_cos_owned);
            if(rope_phase_q==RP_OPERAND0_REQ || rope_phase_q==RP_OPERAND0_WAIT ||
               rope_phase_q==RP_OPERAND1_REQ || rope_phase_q==RP_OPERAND1_WAIT ||
               rope_phase_q==RP_LANE_REQ || rope_phase_q==RP_LANE_WAIT)assert(f_rope_sin_owned);
            if(rope_phase_q==RP_OPERAND1_REQ || rope_phase_q==RP_OPERAND1_WAIT ||
               rope_phase_q==RP_LANE_REQ || rope_phase_q==RP_LANE_WAIT)assert(f_rope_op0_owned);
            if(rope_phase_q==RP_LANE_REQ || rope_phase_q==RP_LANE_WAIT)assert(f_rope_op1_owned);
            if(rope_phase_q==RP_OPERAND0_WAIT || rope_phase_q==RP_OPERAND1_WAIT)begin
                assert(f_rope_operand_read_live);
                assert(f_rope_operand_is_query==(current_stage_q==STAGE_Q_ROPE));
                assert(f_rope_operand_read_tag==
                    {rope_head_q,6'd0}+{3'd0,rope_half_q}+
                    ((rope_phase_q==RP_OPERAND1_WAIT)?8'd32:8'd0));
            end
            if(lane_request_valid)begin
                assert(f_rope_cos_owned);assert(f_rope_sin_owned);
                assert(f_rope_op0_owned);assert(f_rope_op1_owned);
            end
            if(rope_phase_q!=RP_NORM_START)assert(norm_start_seen_q);
            if(rope_phase_q==RP_NORM_START)begin assert(rope_half_q==0);assert(rope_head_q==0);end
            if(rope_phase_q==RP_NORM_WAIT)assert(rope_half_q==0);
            if(rope_phase_q!=RP_NORM_START && rope_phase_q!=RP_SECOND_REQ &&
               rope_phase_q!=RP_SECOND && rope_phase_q!=RP_NORM_WAIT && f_rope_word<rope_half_q)
                assert(f_rope_owned);
            if(rope_phase_q==RP_SECOND_REQ || rope_phase_q==RP_SECOND)assert(f_rope_owned);
            if(rope_phase_q==RP_SECOND && norm_input_valid)begin
                assert(f_rope_read_live);assert(f_rope_read_tag==rope_second_index_q);
            end
        end
        if(rope_raw_ram_read_enable)assert(f_rope_owned);
    end
