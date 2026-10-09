    wire fp_old_fault;
    wire [3:0] fp_old_engine;
    wire [296:0] fp_old_private;
`ifdef SYNTHESIS
    wire fp_simulation_x_fault=1'b0;
`else
    wire fp_simulation_x_fault=`FP_DP.simulation_x_fault;
`endif
    fcp_stage_reference #(.ADDR_W(19)) fp_reference(
        .attention_done_ready(`FP_DP.attention_done_ready),
        .attention_done_valid(`FP_DP.attention_done_valid),
        .attention_query_fire(`FP_DP.attention_query_fire),
        .attention_ram_read_enable(`FP_DP.attention_ram_read_enable),
        .attention_result_descriptor_ok(`FP_DP.attention_result_descriptor_ok),
        .attention_result_exponent(`FP_DP.attention_result_exponent),
        .attention_result_fire(`FP_DP.attention_result_fire),
        .attention_result_last(`FP_DP.attention_result_last),
        .attention_result_valid(`FP_DP.attention_result_valid),
        .attention_start_ready(`FP_DP.attention_start_ready),
        .attention_start_valid(`FP_DP.attention_start_valid),
        .child_fault(`FP_DP.child_fault),
        .clear_i(`FP_DP.clear_i),
        .clk(`FP_DP.clk),
        .gate_read_data(`FP_DP.gate_read_data),
        .head_activation_fire(`FP_DP.head_activation_fire),
        .head_done_fire(`FP_DP.head_done_fire),
        .head_result_fire(`FP_DP.head_result_fire),
        .head_start_accept(`FP_DP.head_start_accept),
        .hidden_ram_read_enable(`FP_DP.hidden_ram_read_enable),
        .key_ram_read_data(`FP_DP.key_ram_read_data),
        .key_ram_read_enable(`FP_DP.key_ram_read_enable),
        .kv_commit_ready(`FP_DP.kv_commit_ready),
        .kv_commit_valid(`FP_DP.kv_commit_valid),
        .kv_pending_complete(`FP_DP.kv_pending_complete),
        .kv_stage_begin_ready(`FP_DP.kv_stage_begin_ready),
        .kv_stage_begin_valid(`FP_DP.kv_stage_begin_valid),
        .kv_stage_payload_ready(`FP_DP.kv_stage_payload_ready),
        .kv_stage_payload_valid(`FP_DP.kv_stage_payload_valid),
        .lane_lut_index(`FP_DP.lane_lut_index),
        .lane_lut_request(`FP_DP.lane_lut_request),
        .lane_request_ready(`FP_DP.lane_request_ready),
        .lane_request_valid(`FP_DP.lane_request_valid),
        .lane_result_fire(`FP_DP.lane_result_fire),
        .lookup_request_ready(`FP_DP.lookup_request_ready),
        .lookup_request_valid(`FP_DP.lookup_request_valid),
        .lookup_response_fault(`FP_DP.lookup_response_fault),
        .lookup_response_ready(`FP_DP.lookup_response_ready),
        .lookup_response_valid(`FP_DP.lookup_response_valid),
        .lookup_response_value(`FP_DP.lookup_response_value),
        .model_lock_i(`FP_DP.model_lock_i),
        .norm_done_ready(`FP_DP.norm_done_ready),
        .norm_done_valid(`FP_DP.norm_done_valid),
        .norm_input_fire(`FP_DP.norm_input_fire),
        .norm_result_exponent(`FP_DP.norm_result_exponent),
        .norm_result_fire(`FP_DP.norm_result_fire),
        .norm_result_index(`FP_DP.norm_result_index),
        .norm_result_last(`FP_DP.norm_result_last),
        .norm_start_ready(`FP_DP.norm_start_ready),
        .norm_start_valid(`FP_DP.norm_start_valid),
        .private_head_activation_exponent_i(`FP_DP.private_head_activation_exponent_i),
        .private_initial_exponent_i(`FP_DP.private_initial_exponent_i),
        .private_layer_i(`FP_DP.private_layer_i),
        .private_position_i(`FP_DP.private_position_i),
        .private_stage_i(`FP_DP.private_stage_i),
        .projection_activation_count(`FP_DP.projection_activation_count),
        .projection_activation_fire(`FP_DP.projection_activation_fire),
        .projection_done_ready(`FP_DP.projection_done_ready),
        .projection_done_valid(`FP_DP.projection_done_valid),
        .projection_result_count(`FP_DP.projection_result_count),
        .projection_result_last(`FP_DP.projection_result_last),
        .projection_start_ready(`FP_DP.projection_start_ready),
        .projection_start_valid(`FP_DP.projection_start_valid),
        .projection_uses_rms(`FP_DP.projection_uses_rms),
        .query_ram_read_data(`FP_DP.query_ram_read_data),
        .query_ram_read_enable(`FP_DP.query_ram_read_enable),
        .rms_done_ready(`FP_DP.rms_done_ready),
        .rms_done_valid(`FP_DP.rms_done_valid),
        .rms_input_fire(`FP_DP.rms_input_fire),
        .rms_ram_read_enable(`FP_DP.rms_ram_read_enable),
        .rms_result_exponent(`FP_DP.rms_result_exponent),
        .rms_result_fire(`FP_DP.rms_result_fire),
        .rms_result_index(`FP_DP.rms_result_index),
        .rms_result_last(`FP_DP.rms_result_last),
        .rms_start_ready(`FP_DP.rms_start_ready),
        .rms_start_valid(`FP_DP.rms_start_valid),
        .rst_n(`FP_DP.rst_n),
        .scratch_read_enable(`FP_DP.scratch_read_enable),
        .simulation_x_fault(fp_simulation_x_fault),
        .stage_accept(`FP_DP.stage_accept),
        .upstream_fault_i(`FP_DP.upstream_fault_i),
        .value_ram_read_enable(`FP_DP.value_ram_read_enable),
        .fault_o(fp_old_fault),
        .engine_o(fp_old_engine),
        .private_state_o(fp_old_private)
    );
    wire [296:0] fp_actual_private={`FP_DP.attention_exponent_q,`FP_DP.attention_head_q,`FP_DP.attention_query_load_lane_q,`FP_DP.attention_query_loaded_q,`FP_DP.attention_query_read_valid_q,`FP_DP.attention_read_valid_q,`FP_DP.attention_result_head_q,`FP_DP.attention_store_lane_q,`FP_DP.current_layer_q,`FP_DP.current_position_q,`FP_DP.current_stage_q,`FP_DP.down_gate_valid_q,`FP_DP.elem_index_q,`FP_DP.elem_phase_q,`FP_DP.expected_layer_q,`FP_DP.expected_stage_q,`FP_DP.gate_exponent_q,`FP_DP.head_activation_exponent_q,`FP_DP.head_last_seen_q,`FP_DP.head_result_index_q,`FP_DP.hidden_exponent_q,`FP_DP.hidden_read_valid_q,`FP_DP.input_done_q,`FP_DP.input_index_q,`FP_DP.key_exponent_q,`FP_DP.kv_read_valid_q,`FP_DP.lane_lut_response_q,`FP_DP.lock_seen_q,`FP_DP.norm_done_seen_q,`FP_DP.norm_start_seen_q,`FP_DP.output_done_q,`FP_DP.output_exponent_q,`FP_DP.output_index_q,`FP_DP.query_exponent_q,`FP_DP.rms_exponent_q,`FP_DP.rms_read_valid_q,`FP_DP.rope_cosine_q,`FP_DP.rope_half_q,`FP_DP.rope_head_q,`FP_DP.rope_operand0_q,`FP_DP.rope_operand1_q,`FP_DP.rope_phase_q,`FP_DP.rope_second_index_q,`FP_DP.rope_sine_q,`FP_DP.service_done_seen_q,`FP_DP.service_start_seen_q,`FP_DP.silu_value_q,`FP_DP.silu_value_valid_q,`FP_DP.stage_done_q,`FP_DP.transaction_position_q,`FP_DP.transaction_seen_q,`FP_DP.up_exponent_q,`FP_DP.value_exponent_q};
    wire fp_fault_owned_activity=|{`FP_DP.private_stage_ready_o,`FP_DP.private_stage_done_o,`FP_DP.private_head_start_ready_o,`FP_DP.private_head_activation_ready_o,`FP_DP.private_head_result_valid_o,`FP_DP.private_head_done_valid_o,`FP_DP.private_word_req_valid_o,`FP_DP.kv_write_req_valid_o,`FP_DP.kv_read_req_valid_o,`FP_DP.rms_start_valid,`FP_DP.rms_input_valid,`FP_DP.projection_start_valid,`FP_DP.projection_activation_valid,`FP_DP.norm_start_valid,`FP_DP.norm_input_valid,`FP_DP.lane_request_valid,`FP_DP.lookup_request_valid,`FP_DP.kv_stage_begin_valid,`FP_DP.kv_stage_payload_valid,`FP_DP.kv_commit_valid,`FP_DP.attention_start_valid,`FP_DP.attention_query_valid,`FP_DP.gate_write_enable,`FP_DP.up_write_enable,`FP_DP.attention_ram_write_enable,`FP_DP.rms_ram_write_enable,`FP_DP.output_ram_write_enable,`FP_DP.hidden_ram_write_enable,`FP_DP.query_ram_write_enable,`FP_DP.key_ram_write_enable,`FP_DP.value_ram_write_enable,`FP_DP.rope_raw_ram_write_enable};

    longint fp_clocks=0,fp_live_clocks=0,fp_fault_clocks=0,fp_different_clocks=0;
    longint fp_reset_clocks=0,fp_fault_edges=0,fp_injected_edges=0;
    longint fp_first_fault_engine=-1;
    bit fp_previous_fault,fp_previous_reset;
    logic [3:0] fp_previous_engine;
    always @(posedge core_clk_i) begin
        fp_previous_fault=`FP_DP.fault_q;
        fp_previous_reset=`FP_DP.rst_n;
        fp_previous_engine=`FP_DP.engine_state_q;
        if (`FP_DP.rst_n && fp_inject_fault) fp_injected_edges++;
        #1;
        fp_clocks++;
        if (fp_old_fault !== `FP_DP.fault_q || fp_old_engine !== `FP_DP.engine_state_q)
            $fatal(1,"FCP literal-controller fault/state mismatch");
        if (!`FP_DP.rst_n) fp_reset_clocks++;
        if (!`FP_DP.fault_q) begin
            fp_live_clocks++;
            if (fp_old_private !== fp_actual_private)
                $fatal(1,"FCP live private-state mismatch");
        end else begin
            fp_fault_clocks++;
            if (fp_old_private !== fp_actual_private) fp_different_clocks++;
            if (fp_fault_owned_activity || token_valid_o ||
                dut.u_machine.layer_result_valid || dut.u_machine.head_result_valid)
                $fatal(1,"FCP post-fault private/public consumer was enabled");
        end
        if (fp_previous_reset && `FP_DP.rst_n && !fp_previous_fault && `FP_DP.fault_q) begin
            fp_fault_edges++;
            if (fp_first_fault_engine<0) fp_first_fault_engine=fp_previous_engine;
        end
    end
    final begin
        $display("FCP_MODEL_MONITOR clocks=%0d live=%0d fault=%0d different=%0d reset=%0d fault_edges=%0d injected_edges=%0d first_fault_engine=%0d actual_registers=55 private_bits=297 actual_prior_rtl=1 native_ports_added=0",
            fp_clocks,fp_live_clocks,fp_fault_clocks,fp_different_clocks,fp_reset_clocks,
            fp_fault_edges,fp_injected_edges,fp_first_fault_engine);
    end
