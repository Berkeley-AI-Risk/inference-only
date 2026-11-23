// This observer only reads the existing bench and production RTL hierarchy.
`define FRAME_SHELL u_uart.u_machine.u_machine.u_token_shell
`define FRAME_DP u_uart.u_machine.u_machine.u_six_layers.u_datapath
`define FRAME_RMS u_uart.u_machine.u_machine.u_token_shell.u_final_rmsnorm
`define FRAME_PROJ u_uart.u_machine.u_machine.u_six_layers.u_datapath.u_projection

    integer frame_step_q = 0;
    always @(posedge core_clk_i) begin : observe_final_layer_frame
        if (!reset_n_i) begin
            frame_step_q = 0;
        end else if ($test$plusargs("OBSERVE_FINAL_LAYER_FRAME") && frame_step_q < 3) begin
            if (append_valid_i && append_ready_o)
                $display("FINAL_FRAME APPEND %0d", append_token_i);
            if (step_valid_i && step_ready_o) begin
                frame_step_q = frame_step_q + 1;
                if (frame_step_q <= 2)
                    $display("FINAL_FRAME STEP %0d", frame_step_q);
            end
            if (frame_step_q == 1 || frame_step_q == 2) begin
                if (`FRAME_SHELL.embed_start_transfer)
                    $display("FINAL_FRAME EMBED %0d %0d %0d", frame_step_q,
                        `FRAME_SHELL.replay_position_q, `FRAME_SHELL.u_fixed_embedding.fixed_token_i);
                if (`FRAME_DP.hidden_ram_write_enable && !`FRAME_DP.private_ingress_write_i &&
                        `FRAME_DP.current_layer_q == 3'd5 && `FRAME_DP.current_stage_q == 5'd15)
                    $display("FINAL_FRAME RESIDUAL %0d %0d %0d %0d %0d %0d", frame_step_q,
                        `FRAME_DP.current_position_q, `FRAME_DP.hidden_ram_write_address,
                        $signed(`FRAME_DP.hidden_ram_write_data), $signed(`FRAME_DP.norm_result_exponent),
                        `FRAME_DP.norm_result_last);
                if (`FRAME_SHELL.legal_layer_result_retire)
                    $display("FINAL_FRAME EXPORT %0d %0d %0d %0d %0d %0d", frame_step_q,
                        `FRAME_SHELL.replay_position_q, `FRAME_SHELL.private_layer_result_index_i,
                        $signed(`FRAME_SHELL.private_layer_result_mantissa_i),
                        $signed(`FRAME_SHELL.private_layer_result_exponent_i),
                        `FRAME_SHELL.private_layer_result_last_i);
                if (`FRAME_SHELL.semantic_commit_retire)
                    $display("FINAL_FRAME COMMIT %0d %0d %h", frame_step_q,
                        `FRAME_SHELL.replay_position_q, u_uart.u_machine.u_machine.layer_committed_prefixes);
                if (`FRAME_RMS.start_valid_i && `FRAME_RMS.start_ready_o)
                    $display("FINAL_FRAME RMS_START %0d %0d %0d %0d %0d", frame_step_q,
                        `FRAME_SHELL.replay_position_q, `FRAME_RMS.fixed_layer_i,
                        `FRAME_RMS.fixed_norm_kind_i, $signed(`FRAME_RMS.input_exponent_i));
                if (`FRAME_RMS.vector_write_enable)
                    $display("FINAL_FRAME RMS_WORD %0d %0d %0d %0d %0d %0d", frame_step_q,
                        `FRAME_SHELL.replay_position_q, `FRAME_RMS.input_row_index_i,
                        $signed(`FRAME_RMS.input_mantissa_i), $signed(`FRAME_RMS.input_exponent_q),
                        `FRAME_RMS.input_last_i);
                if (`FRAME_RMS.result_valid_o && `FRAME_RMS.result_ready_i)
                    $display("FINAL_HEAD RMS_OUT %0d %0d %0d %0d %0d %0d %0d", frame_step_q,
                        `FRAME_SHELL.replay_position_q, core_cycle_q, `FRAME_RMS.result_row_index_o,
                        $signed(`FRAME_RMS.result_mantissa_o), $signed(`FRAME_RMS.result_exponent_o),
                        `FRAME_RMS.result_last_o);
                if (`FRAME_DP.projection_is_head && `FRAME_PROJ.start_valid_i && `FRAME_PROJ.start_ready_o)
                    $display("FINAL_HEAD PROJ_START %0d %0d %0d %0d %0d %0d", frame_step_q,
                        `FRAME_SHELL.replay_position_q, core_cycle_q, `FRAME_PROJ.fixed_layer_i,
                        `FRAME_PROJ.fixed_job_i, $signed(`FRAME_PROJ.activation_exponent_i));
                if (`FRAME_DP.projection_is_head && `FRAME_PROJ.activation_store_write)
                    $display("FINAL_HEAD RAM_WRITE %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d", frame_step_q,
                        `FRAME_SHELL.replay_position_q, core_cycle_q, `FRAME_PROJ.activation_count_q,
                        $signed(`FRAME_PROJ.activation_i), $signed(`FRAME_PROJ.activation_exponent_q),
                        `FRAME_PROJ.activation_last_i, `FRAME_PROJ.job_q, `FRAME_SHELL.head_input_transfer,
                        `FRAME_SHELL.private_head_activation_index_o);
                if (`FRAME_SHELL.head_result_transfer)
                    $display("FINAL_SCORE ROW %0d %0d %0d %0d %0d %0d %0d", frame_step_q,
                        `FRAME_SHELL.replay_position_q, core_cycle_q,
                        `FRAME_SHELL.private_head_result_row_index_i,
                        $signed(`FRAME_SHELL.private_head_result_scaled_raw_i),
                        $signed(`FRAME_SHELL.private_head_result_source_exponent_i),
                        `FRAME_SHELL.private_head_result_last_i);
                if (`FRAME_SHELL.winner_transfer)
                    $display("FINAL_SCORE WINNER %0d %0d %0d %0d %0d %0d", frame_step_q,
                        `FRAME_SHELL.replay_position_q, core_cycle_q, `FRAME_SHELL.argmax_winner_token,
                        $signed(`FRAME_SHELL.argmax_winner_scaled),
                        $signed(`FRAME_SHELL.argmax_winner_exponent));
                if (token_valid_o && token_ready_i)
                    $display("FINAL_FRAME TOKEN %0d %0d", frame_step_q, token_o);
            end
        end
    end
`undef FRAME_PROJ
`undef FRAME_RMS
`undef FRAME_DP
`undef FRAME_SHELL
