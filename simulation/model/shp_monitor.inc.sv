    wire sp_old_fault,sp_old_owner;
    wire [4:0] sp_old_state;
    wire [129:0] sp_old_data;
`ifdef SYNTHESIS
    wire sp_simulation_x_fault=1'b0;
`else
    wire sp_simulation_x_fault=`SP_SHELL.simulation_x_fault;
`endif
    shp_shell_reference #(.ADDR_W(19),.MAX_NO_PROGRESS_CYCLES(100000000)) sp_reference(
        .append_transfer(`SP_SHELL.append_transfer),
        .argmax_busy(`SP_SHELL.argmax_busy),
        .argmax_start_ready(`SP_SHELL.argmax_start_ready),
        .argmax_start_valid(`SP_SHELL.argmax_start_valid),
        .argmax_winner_token(`SP_SHELL.argmax_winner_token),
        .child_fault(`SP_SHELL.child_fault),
        .clear_i(`SP_SHELL.clear_i),
        .cleared_prefixes_match(`SP_SHELL.cleared_prefixes_match),
        .clk(`SP_SHELL.clk),
        .committed_prefixes_match(`SP_SHELL.committed_prefixes_match),
        .completing_winner(`SP_SHELL.completing_winner),
        .compute_active(`SP_SHELL.compute_active),
        .embed_busy(`SP_SHELL.embed_busy),
        .embed_done_transfer(`SP_SHELL.embed_done_transfer),
        .embed_result_exponent(`SP_SHELL.embed_result_exponent),
        .embed_result_index(`SP_SHELL.embed_result_index),
        .embed_result_last(`SP_SHELL.embed_result_last),
        .embed_result_mantissa(`SP_SHELL.embed_result_mantissa),
        .embed_result_transfer(`SP_SHELL.embed_result_transfer),
        .embed_result_valid(`SP_SHELL.embed_result_valid),
        .embed_start_ready(`SP_SHELL.embed_start_ready),
        .embed_start_valid(`SP_SHELL.embed_start_valid),
        .embedding_read_q(`SP_SHELL.embedding_read_q),
        .final_norm_read_q(`SP_SHELL.final_norm_read_q),
        .head_done_transfer(`SP_SHELL.head_done_transfer),
        .head_last_transfer(`SP_SHELL.head_last_transfer),
        .head_terminals_complete(`SP_SHELL.head_terminals_complete),
        .layer5_read_q(`SP_SHELL.layer5_read_q),
        .layer_done_transfer(`SP_SHELL.layer_done_transfer),
        .layer_input_transfer(`SP_SHELL.layer_input_transfer),
        .layer_result_transfer(`SP_SHELL.layer_result_transfer),
        .layer_start_transfer(`SP_SHELL.layer_start_transfer),
        .lock_fault(`SP_SHELL.lock_fault),
        .model_lock_i(`SP_SHELL.model_lock_i),
        .next_prefixes_match(`SP_SHELL.next_prefixes_match),
        .private_head_activation_ready_i(`SP_SHELL.private_head_activation_ready_i),
        .private_head_activation_valid_o(`SP_SHELL.private_head_activation_valid_o),
        .private_head_result_valid_i(`SP_SHELL.private_head_result_valid_i),
        .private_head_start_ready_i(`SP_SHELL.private_head_start_ready_i),
        .private_head_start_valid_o(`SP_SHELL.private_head_start_valid_o),
        .private_layer_busy_i(`SP_SHELL.private_layer_busy_i),
        .private_layer_result_exponent_i(`SP_SHELL.private_layer_result_exponent_i),
        .private_layer_result_index_i(`SP_SHELL.private_layer_result_index_i),
        .private_layer_result_last_i(`SP_SHELL.private_layer_result_last_i),
        .private_layer_result_mantissa_i(`SP_SHELL.private_layer_result_mantissa_i),
        .private_layer_result_valid_i(`SP_SHELL.private_layer_result_valid_i),
        .private_protocol_fault(`SP_SHELL.private_protocol_fault),
        .public_protocol_fault(`SP_SHELL.public_protocol_fault),
        .replay_is_needed(`SP_SHELL.replay_is_needed),
        .rms_busy(`SP_SHELL.rms_busy),
        .rms_done_transfer(`SP_SHELL.rms_done_transfer),
        .rms_input_ready(`SP_SHELL.rms_input_ready),
        .rms_input_valid(`SP_SHELL.rms_input_valid),
        .rms_result_exponent(`SP_SHELL.rms_result_exponent),
        .rms_result_index(`SP_SHELL.rms_result_index),
        .rms_result_last(`SP_SHELL.rms_result_last),
        .rms_result_mantissa(`SP_SHELL.rms_result_mantissa),
        .rms_result_transfer(`SP_SHELL.rms_result_transfer),
        .rms_result_valid(`SP_SHELL.rms_result_valid),
        .rms_start_ready(`SP_SHELL.rms_start_ready),
        .rms_start_valid(`SP_SHELL.rms_start_valid),
        .rst_n(`SP_SHELL.rst_n),
        .simulation_x_fault(sp_simulation_x_fault),
        .step_transfer(`SP_SHELL.step_transfer),
        .token_transfer(`SP_SHELL.token_transfer),
        .upstream_fault_i(`SP_SHELL.upstream_fault_i),
        .verified_forward_progress(`SP_SHELL.verified_forward_progress),
        .watchdog_fault(`SP_SHELL.watchdog_fault),
        .winner_transfer(`SP_SHELL.winner_transfer),
        .fault_o(sp_old_fault),
        .state_o(sp_old_state),
        .owner_o(sp_old_owner),
        .data_o(sp_old_data)
    );
    initial if (`SP_SHELL.MAX_NO_PROGRESS_CYCLES!=100000000) $fatal(1,"SHP shadow deadline mismatch");
    wire [129:0] sp_actual_data={`SP_SHELL.capture_index_q,`SP_SHELL.committed_count_q,`SP_SHELL.embedding_exponent_q,`SP_SHELL.final_norm_exponent_q,`SP_SHELL.generated_token_q,`SP_SHELL.head_done_seen_q,`SP_SHELL.last_hidden_valid_q,`SP_SHELL.layer5_exponent_q,`SP_SHELL.no_progress_cycles_q,`SP_SHELL.replay_position_q,`SP_SHELL.stream_index_q,`SP_SHELL.tape_count_q,`SP_SHELL.winner_seen_q,`SP_SHELL.winner_token_q};
    wire sp_owned_activity=|{`SP_SHELL.append_ready_o,`SP_SHELL.step_ready_o,`SP_SHELL.token_valid_o,`SP_SHELL.append_transfer,`SP_SHELL.generated_commit,`SP_SHELL.embed_result_transfer,`SP_SHELL.layer_result_transfer,`SP_SHELL.rms_result_transfer,`SP_SHELL.embed_start_valid,`SP_SHELL.private_layer_start_valid_o,`SP_SHELL.private_layer_input_valid_o,`SP_SHELL.private_layer_result_ready_o,`SP_SHELL.private_layer_done_ready_o,`SP_SHELL.rms_start_valid,`SP_SHELL.rms_input_valid,`SP_SHELL.private_head_start_valid_o,`SP_SHELL.private_head_activation_valid_o,`SP_SHELL.private_head_result_ready_o,`SP_SHELL.private_head_done_ready_o,`SP_SHELL.argmax_start_valid};

    longint sp_clocks=0,sp_live_clocks=0,sp_fault_clocks=0,sp_different_clocks=0;
    longint sp_reset_clocks=0,sp_fault_edges=0,sp_injected_edges=0;
    longint sp_first_fault_state=-1,sp_injected_owner=-1;
    bit sp_previous_fault,sp_previous_reset;
    logic [4:0] sp_previous_state;
    always @(posedge core_clk_i) begin
        sp_previous_fault=`SP_SHELL.fail_q;
        sp_previous_reset=`SP_SHELL.rst_n;
        sp_previous_state=`SP_SHELL.state_q;
        if (`SP_SHELL.rst_n && sp_inject_fault) begin
            sp_injected_edges++;
            sp_injected_owner=`SP_SHELL.ddr_owner_q;
        end
        #1;
        sp_clocks++;
        if (sp_old_fault !== `SP_SHELL.fail_q || sp_old_state !== `SP_SHELL.state_q ||
            sp_old_owner !== `SP_SHELL.ddr_owner_q)
            $fatal(1,"SHP literal-controller fault/state/owner mismatch");
        if (!`SP_SHELL.rst_n) sp_reset_clocks++;
        if (!`SP_SHELL.fail_q) begin
            sp_live_clocks++;
            if (sp_old_data !== sp_actual_data) $fatal(1,"SHP live private-state mismatch");
        end else begin
            sp_fault_clocks++;
            if (sp_old_data !== sp_actual_data) sp_different_clocks++;
            if (sp_owned_activity || token_valid_o)
                $fatal(1,"SHP post-fault public/owned consumer still enabled");
        end
        if (sp_previous_reset && `SP_SHELL.rst_n && !sp_previous_fault && `SP_SHELL.fail_q) begin
            sp_fault_edges++;
            if (sp_first_fault_state<0) sp_first_fault_state=sp_previous_state;
        end
    end
    final begin
        $display("SHP_MODEL_MONITOR clocks=%0d live=%0d fault=%0d different=%0d reset=%0d fault_edges=%0d injected_edges=%0d first_fault_state=%0d injected_owner=%0d actual_registers=17 private_bits=130 owner_always_equal=1 actual_prior_rtl=1 native_ports_added=0",
            sp_clocks,sp_live_clocks,sp_fault_clocks,sp_different_clocks,sp_reset_clocks,
            sp_fault_edges,sp_injected_edges,sp_first_fault_state,sp_injected_owner);
    end
