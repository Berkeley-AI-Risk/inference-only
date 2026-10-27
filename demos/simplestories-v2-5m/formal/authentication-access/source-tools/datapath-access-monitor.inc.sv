    // Read-only properties over the actual scheduling and operand mux logic.
    always_comb begin
        if (rst_n) begin
            assert(engine_state_q == E_IDLE || engine_state_q == E_RMS ||
                engine_state_q == E_PROJ || engine_state_q == E_ROPE ||
                engine_state_q == E_KV || engine_state_q == E_ATTN ||
                engine_state_q == E_ELEM || engine_state_q == E_COMMIT ||
                engine_state_q == E_HEAD || engine_state_q == E_FAULT);
            assert(expected_layer_q <= 5 && current_layer_q <= 5);
            assert(expected_stage_q <= STAGE_KV_COMMIT && current_stage_q <= STAGE_KV_COMMIT);
            // A malformed numerical child result may latch fault and complete
            // its state on the same edge. The fault gate revokes access at
            // once; the explicit E_FAULT state follows on the next edge.
            if (fault_q) assert(!private_stage_ready_o && !private_head_start_ready_o);
            if (!fault_q && engine_state_q != E_IDLE && engine_state_q != E_HEAD && engine_state_q != E_FAULT) begin
                assert(current_layer_q == expected_layer_q && current_stage_q == expected_stage_q);
                assert(transaction_seen_q && current_position_q == transaction_position_q);
            end
            if (engine_state_q == E_RMS) assert(current_stage_q == STAGE_INPUT_RMS || current_stage_q == STAGE_POST_RMS);
            if (engine_state_q == E_PROJ) assert(current_stage_q == STAGE_Q || current_stage_q == STAGE_K ||
                current_stage_q == STAGE_V || current_stage_q == STAGE_O || current_stage_q == STAGE_GATE ||
                current_stage_q == STAGE_UP || current_stage_q == STAGE_DOWN);
            if (engine_state_q == E_ROPE) assert(current_stage_q == STAGE_Q_ROPE || current_stage_q == STAGE_K_ROPE);
            if (engine_state_q == E_KV) assert(current_stage_q == STAGE_KV_STAGE);
            if (engine_state_q == E_ATTN) assert(current_stage_q == STAGE_ATTENTION);
            if (engine_state_q == E_ELEM) assert(current_stage_q == STAGE_RESIDUAL_1 ||
                current_stage_q == STAGE_SILU_MUL || current_stage_q == STAGE_RESIDUAL_2);
            if (engine_state_q == E_COMMIT) assert(current_stage_q == STAGE_KV_COMMIT);
            if (projection_start_valid) begin
                assert(!fault_q && !clear_i && !service_start_seen_q);
                assert(engine_state_q == E_PROJ || engine_state_q == E_HEAD);
                if (engine_state_q == E_HEAD) assert(projection_layer == 7 && projection_job == 7);
                else begin
                    assert(projection_layer == current_layer_q && projection_layer <= 5);
                    assert(projection_job == projection_job_for_stage(current_stage_q) && projection_job <= 6);
                end
            end
            if (projection_activation_valid && engine_state_q == E_PROJ) begin
                assert(service_start_seen_q && norm_start_seen_q && !input_done_q);
                assert(projection_activation_last == (input_index_q == projection_activation_count - 1'b1));
                if (projection_uses_rms) assert(projection_activation == rms_ram_read_data && rms_read_valid_q);
                if (current_stage_q == STAGE_O) assert(projection_activation == attention_ram_read_data && attention_read_valid_q);
                if (current_stage_q == STAGE_DOWN) assert(projection_activation == gate_read_data && down_gate_valid_q);
            end
            if (rms_input_valid) assert(engine_state_q == E_RMS && hidden_read_valid_q && !input_done_q);
            if (lane_request_valid) begin
                assert(engine_state_q == E_ELEM || engine_state_q == E_ROPE);
                assert(lane_operation == 0 || lane_operation == 2 || lane_operation == 3);
                if (engine_state_q == E_ROPE) begin
                    assert(lane_operation == 0 && lane_first == rope_operand0_q && lane_second == rope_operand1_q);
                end
                if (engine_state_q == E_ELEM && current_stage_q == STAGE_SILU_MUL)
                    assert(lane_operation == 2 && lane_first == gate_read_data && lane_second == up_read_data);
                if (engine_state_q == E_ELEM && current_stage_q != STAGE_SILU_MUL)
                    assert(lane_operation == 3 && lane_first == hidden_ram_read_data && lane_second == output_ram_read_data);
            end
            if (gate_write_enable || up_write_enable || attention_ram_write_enable || rms_ram_write_enable ||
                output_ram_write_enable || hidden_ram_write_enable || query_ram_write_enable ||
                key_ram_write_enable || value_ram_write_enable || rope_raw_ram_write_enable)
                assert(!fault_q && !clear_i && model_lock_i && !upstream_fault_i && !child_fault);
            if (hidden_ram_write_enable) begin
                assert(hidden_ram_write_address == (private_ingress_write_i ? private_ingress_index_i : output_index_q[7:0]));
                assert(hidden_ram_write_data == (private_ingress_write_i ? private_ingress_mantissa_i : norm_result_mantissa));
            end
            if (attention_ram_write_enable) begin
                assert(engine_state_q == E_ATTN && attention_result_valid && attention_result_descriptor_ok);
                assert(attention_ram_write_address == {attention_result_head_q[1:0],attention_store_lane_q});
                assert(attention_ram_write_data == attention_result_vector[attention_store_lane_q*16 +:16]);
            end
            if (up_write_enable) assert(engine_state_q == E_PROJ && current_stage_q == STAGE_UP && projection_norm_result_order_ok);
            if (value_ram_write_enable) assert(engine_state_q == E_PROJ && current_stage_q == STAGE_V && projection_norm_result_order_ok);
            if (rope_raw_ram_write_enable) assert(engine_state_q == E_ROPE && rope_phase_q == RP_LANE_WAIT && lane_result_fire);
            if (scratch_read_enable) assert(scratch_read_address == (engine_state_q == E_PROJ ? input_index_q : elem_index_q));
            if (rms_ram_read_enable) assert(rms_ram_read_address == input_index_q[7:0]);
            if (attention_ram_read_enable) assert(attention_ram_read_address == input_index_q[7:0]);
            if (private_word_req_valid_o) begin
                assert(ddr_admission_live);
                assert(projection_word_req_valid != lookup_word_req_valid);
                assert(private_word_req_index_o == (projection_word_req_valid ? projection_word_req_index : lookup_word_req_index));
                assert(ddr_owner_q == DDR_NONE || (ddr_owner_q == DDR_PROJ && ddr_pending_q < 8));
            end
            if (!ddr_arbiter_fault_q) begin
                assert(ddr_pending_q <= 8 && ddr_owner_q != 3);
                assert((ddr_pending_q == 0) == (ddr_owner_q == DDR_NONE));
                if (ddr_owner_q == DDR_LOOK) assert(ddr_pending_q == 1);
            end
            if (projection_word_rsp_valid) assert(ddr_owner_q == DDR_PROJ && private_word_rsp_valid_i);
            if (lookup_word_rsp_valid) assert(ddr_owner_q == DDR_LOOK && private_word_rsp_valid_i);
            assert(!(projection_word_rsp_valid && lookup_word_rsp_valid));
            if (fault_q || clear_i) begin
                assert(!projection_start_valid && !rms_start_valid && !norm_start_valid && !lane_request_valid);
                assert(!lookup_request_valid && !kv_stage_begin_valid && !kv_commit_valid && !attention_start_valid);
            end
            cover(projection_start_valid && engine_state_q == E_HEAD && projection_job == 7);
            cover(engine_state_q == E_RMS && rms_start_valid);
        end
    end
