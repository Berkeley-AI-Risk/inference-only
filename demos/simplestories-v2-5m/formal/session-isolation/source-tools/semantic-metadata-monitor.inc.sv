    // Metadata registers retain bits across CLEAR. Their current-session
    // writers must run before the corresponding operand can be admitted.
    reg f_hidden_meta,f_rms_meta,f_query_meta,f_key_meta,f_value_meta;
    reg f_attention_meta,f_output_meta,f_gate_meta,f_up_meta,f_head_meta;
    reg f_silu_owned;
    wire f_initial_hidden_write=engine_state_q==E_IDLE && !head_start_accept && stage_accept &&
        private_stage_i==expected_stage_q && private_layer_i==expected_layer_q && !transaction_seen_q;
    wire f_rms_metadata_write=engine_state_q==E_RMS && rms_result_fire &&
        rms_result_index==output_index_q[7:0] && rms_result_last==(output_index_q==255);
    wire f_projection_metadata_write=engine_state_q==E_PROJ && norm_result_fire &&
        norm_result_index==output_index_q && norm_result_last==(output_index_q==projection_result_count-1'b1);
    wire f_rope_metadata_write=engine_state_q==E_ROPE && norm_result_fire &&
        norm_result_index==output_index_q && norm_result_last==
            ((current_stage_q==STAGE_Q_ROPE)?(output_index_q==255):(output_index_q==127));
    wire f_elem_metadata_write=engine_state_q==E_ELEM && norm_result_fire &&
        norm_result_index==output_index_q && norm_result_last==
            ((current_stage_q==STAGE_SILU_MUL)?(output_index_q==681):(output_index_q==255));
    always @(posedge clk)begin
        if(!rst_n || clear_i)begin
            f_hidden_meta<=0;f_rms_meta<=0;f_query_meta<=0;f_key_meta<=0;f_value_meta<=0;
            f_attention_meta<=0;f_output_meta<=0;f_gate_meta<=0;f_up_meta<=0;f_head_meta<=0;
        end else begin
            if(f_initial_hidden_write)f_hidden_meta<=1;
            if(head_start_accept)f_head_meta<=1;
            if(f_rms_metadata_write)f_rms_meta<=1;
            if(f_projection_metadata_write)case(current_stage_q)
                STAGE_Q:f_query_meta<=1;
                STAGE_K:f_key_meta<=1;
                STAGE_V:f_value_meta<=1;
                STAGE_O,STAGE_DOWN:f_output_meta<=1;
                STAGE_GATE:f_gate_meta<=1;
                STAGE_UP:f_up_meta<=1;
            endcase
            if(f_rope_metadata_write)begin
                if(current_stage_q==STAGE_Q_ROPE)f_query_meta<=1;else f_key_meta<=1;
            end
            if(engine_state_q==E_ATTN && attention_result_valid && attention_result_descriptor_ok &&
               attention_store_lane_q==63)f_attention_meta<=1;
            if(f_elem_metadata_write)begin
                if(current_stage_q==STAGE_SILU_MUL)f_gate_meta<=1;else f_hidden_meta<=1;
            end
        end
        if(!rst_n || clear_i || (stage_accept &&
            (private_stage_i==STAGE_SILU_MUL || private_stage_i==STAGE_RESIDUAL_1 || private_stage_i==STAGE_RESIDUAL_2)))
            f_silu_owned<=0;
        else if(engine_state_q==E_ELEM && lookup_response_valid && lookup_response_ready && !lookup_response_fault)
            f_silu_owned<=1;
    end
    always @*if(rst_n && !clear_i && !fault_q)begin
        if(transaction_seen_q)assert(f_hidden_meta);
        if(expected_stage_q>=1)assert(f_rms_meta);
        if(expected_stage_q>=2)assert(f_query_meta);
        if(expected_stage_q>=3)assert(f_key_meta);
        if(expected_stage_q>=4)assert(f_value_meta);
        if(expected_stage_q>=8)assert(f_attention_meta);
        if(expected_stage_q>=9)assert(f_output_meta);
        if(expected_stage_q>=12)assert(f_gate_meta);
        if(expected_stage_q>=13)assert(f_up_meta);
        if(engine_state_q==E_RMS)assert(f_hidden_meta);
        if(engine_state_q==E_RMS && (output_index_q!=0 || output_done_q))assert(f_rms_meta);
        if(engine_state_q==E_PROJ && (output_index_q!=0 || output_done_q))case(current_stage_q)
            STAGE_Q:begin assert(f_query_meta);end
            STAGE_K:begin assert(f_key_meta);end
            STAGE_V:begin assert(f_value_meta);end
            STAGE_O,STAGE_DOWN:begin assert(f_output_meta);end
            STAGE_GATE:begin assert(f_gate_meta);end
            STAGE_UP:begin assert(f_up_meta);end
        endcase
        if(engine_state_q==E_ROPE && (output_index_q!=0 || output_done_q))begin
            if(current_stage_q==STAGE_Q_ROPE)assert(f_query_meta);else assert(f_key_meta);
        end
        if(engine_state_q==E_ATTN && (attention_result_head_q!=0 || output_done_q))assert(f_attention_meta);
        if(engine_state_q==E_ELEM && (output_index_q!=0 || output_done_q))begin
            if(current_stage_q==STAGE_SILU_MUL)assert(f_gate_meta);else assert(f_hidden_meta);
        end
        if(engine_state_q==E_HEAD)assert(f_head_meta);
        if(engine_state_q==E_ROPE)begin
            if(current_stage_q==STAGE_Q_ROPE)assert(f_query_meta);else assert(f_key_meta);
        end
        if(engine_state_q==E_KV)begin assert(f_key_meta);assert(f_value_meta);end
        if(engine_state_q==E_ATTN)assert(f_query_meta);
        if(engine_state_q==E_PROJ)begin
            if(current_stage_q==STAGE_DOWN)assert(f_gate_meta);
            else if(current_stage_q==STAGE_O)assert(f_attention_meta);
            else assert(f_rms_meta);
        end
        if(engine_state_q==E_ELEM)begin
            if(current_stage_q==STAGE_SILU_MUL)begin
                assert(f_gate_meta);assert(f_up_meta);
                if(silu_value_valid_q || lane_lut_response_q)assert(f_silu_owned);
            end else begin assert(f_hidden_meta);assert(f_output_meta);end
        end
    end
