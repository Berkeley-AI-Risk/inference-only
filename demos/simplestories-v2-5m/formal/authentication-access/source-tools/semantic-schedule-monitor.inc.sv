    reg [8:0] f_ingress_words;
    reg [6:0] f_completed_stages;
    reg f_stage_owned;
    reg f_previous_clear;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            f_ingress_words<=0;f_completed_stages<=0;f_stage_owned<=0;f_previous_clear<=0;
        end else begin
            f_previous_clear<=clear_i;
            if (start_fire) begin
                f_ingress_words<=0;f_completed_stages<=0;f_stage_owned<=0;
            end
            if (private_ingress_write_o) f_ingress_words<=f_ingress_words+1'b1;
            if (stage_start_fire) f_stage_owned<=1;
            if (!clear_i && !fault_q && !protocol_fault && state_q==S_STAGE_WAIT && private_stage_done_i) begin
                f_completed_stages<=f_completed_stages+1'b1;f_stage_owned<=0;
            end
            if (clear_i || fault_q || protocol_fault) f_stage_owned<=0;
            if (clear_i) begin
                f_ingress_words<=0;f_completed_stages<=0;
            end
        end
    end
    always_comb begin
        if (rst_n) begin
            assert(layer_q<=5 && stage_q<=STAGE_KV_COMMIT);
            assert(f_ingress_words<=256 && f_completed_stages<=102);
            if (!fault_q && !clear_i && !protocol_fault) begin
                if (state_q!=S_IDLE && state_q!=S_INGRESS && state_q!=S_FAULT)
                    assert(f_ingress_words==256);
                if (state_q==S_RESULT || state_q==S_RESULT_REQ)
                    assert(f_completed_stages==101 && layer_q==5 && stage_q==STAGE_RESIDUAL_2);
                if (state_q==S_STAGE_START || state_q==S_STAGE_WAIT) begin
                    assert(f_ingress_words==256);
                    assert({4'd0,layer_q}*7'd17 + {2'd0,stage_q} == f_completed_stages);
                end
                assert(f_stage_owned == (state_q==S_STAGE_WAIT));
                if (state_q==S_INGRESS) begin
                    assert(f_ingress_words=={1'b0,stream_index_q});
                    assert(f_completed_stages==0 && layer_q==0 && stage_q==STAGE_INPUT_RMS);
                end
                if (result_valid_o) assert(f_completed_stages==101 && layer_q==5 && stage_q==STAGE_RESIDUAL_2);
                if (done_valid_o) assert(f_completed_stages==102 && layer_q==5 && stage_q==STAGE_KV_COMMIT);
            end
            if (private_ingress_write_o) begin
                assert(input_valid_i && input_ready_o && input_legal && !fault_q);
                assert(input_index_i==stream_index_q && input_last_i==(stream_index_q==255));
                assert(input_mantissa_i!=16'h8000);
                assert(state_q==S_INGRESS && !clear_i);
            end
            if (private_stage_valid_o) begin
                assert(state_q==S_STAGE_START && !clear_i && !fault_q);
                assert(private_stage_o==stage_q && private_layer_o==layer_q);
                assert(private_position_o==position_q && private_input_exponent_o==input_exponent_q);
            end
            if (result_valid_o) begin
                assert(state_q==S_RESULT && !clear_i && !fault_q);
                assert(result_index_o==stream_index_q && result_last_o==(stream_index_q==255));
            end
            if (fault_q || clear_i) assert(!private_stage_valid_o && !private_ingress_write_o && !result_valid_o && !done_valid_o);
            if (f_previous_clear) assert(f_ingress_words==0 && f_completed_stages==0 && !f_stage_owned);
            cover(state_q==S_INGRESS && input_fire && input_legal);
            cover(fault_q && !private_stage_valid_o && !private_ingress_write_o);
        end
    end
