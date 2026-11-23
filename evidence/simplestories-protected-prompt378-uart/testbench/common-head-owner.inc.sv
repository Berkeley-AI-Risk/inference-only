// Passive core-edge monitor. The shadow memory is only for comparisons.
`define J_SH u_uart.u_machine.u_machine.u_token_shell
`define J_AG `J_SH.u_exact_argmax
`define J_DP u_uart.u_machine.u_machine.u_six_layers.u_datapath
`define J_PR `J_DP.u_projection
`define J_RM `J_SH.u_final_rmsnorm
`define J_BR u_uart.u_fixed_uart

bit j_in_reset = 0;
int j_epoch = 0;
bit j_head = 0, j_pending_read = 0, j_successor_commit = 0;
longint j_read_cycle = 0;
int j_read_col = 0, j_writes = 0, j_reads = 0, j_weights = 0, j_nf_count = 0;
logic signed [15:0] j_shadow [0:255];
logic signed [15:0] j_expected_read;
wire j_command = u_uart.cmd_valid && u_uart.cmd_ready;
wire j_step = j_command && u_uart.cmd == 1;
wire j_clear = j_command && u_uart.cmd == 2;
wire j_capture = u_uart.result_valid && u_uart.result_ready &&
                 !(`J_BR.clear_pending_q && u_uart.cmd_ready);
wire j_commit = `J_SH.rst_n && !`J_SH.clear_i && !`J_SH.fail_q &&
                `J_SH.generated_commit && !`J_SH.private_head_result_valid_i &&
                !`J_SH.upstream_fault_i && !`J_SH.child_fault &&
                !`J_SH.lock_fault && !`J_SH.watchdog_fault &&
                !`J_SH.public_protocol_fault && !`J_SH.private_protocol_fault;

always @(posedge core_clk_i) begin : observe_c070_common_head
    if (!reset_n_i) begin
        if (!j_in_reset) begin
            j_epoch = j_epoch + 1;
            $display("HEAD_JOIN RESET %0d %0d", j_epoch, core_cycle_q);
        end
        j_in_reset = 1;
        j_head = 0;
        j_pending_read = 0;
        j_successor_commit = 0;
        j_writes = 0;
        j_reads = 0;
        j_weights = 0;
        j_nf_count = 0;
    end else begin
        j_in_reset = 0;
        if (j_step || (step_valid_i && step_ready_o))
            $display("HEAD_JOIN STEP %0d %0d %0d %0d %0d", j_epoch, core_cycle_q,
                     j_step, step_valid_i && step_ready_o, `J_SH.step_transfer);
        if (j_clear || clear_i) begin
            $display("HEAD_JOIN CLEAR %0d %0d %0d %0d %0d", j_epoch, core_cycle_q,
                     j_clear, clear_i, `J_SH.clear_i);
            j_head = 0;
            j_pending_read = 0;
            j_successor_commit = 0;
        end
        if (`J_SH.rms_start_transfer) begin
            j_nf_count = 0;
            $display("HEAD_JOIN RMS %0d %0d %0d %0d %0d", j_epoch, core_cycle_q,
                     `J_SH.replay_position_q, `J_RM.fixed_layer_i, `J_RM.fixed_norm_kind_i);
        end
        if (`J_SH.rms_result_transfer) begin
            if (j_head)
                $display("HEAD_JOIN ERROR %0d %0d 6", j_epoch, core_cycle_q);
            $display("HEAD_JOIN NF %0d %0d %0d %0d %0d %0d %0d", j_epoch, core_cycle_q,
                     `J_SH.rms_result_index, $signed(`J_SH.rms_result_mantissa),
                     $signed(`J_SH.rms_result_exponent), `J_SH.rms_result_last,
                     `J_SH.legal_rms_result_retire);
            j_nf_count = j_nf_count + 1;
        end
        if (`J_SH.head_start_transfer || `J_DP.head_start_accept)
            $display("HEAD_JOIN HEAD %0d %0d %0d %0d %0d", j_epoch, core_cycle_q,
                     `J_SH.head_start_transfer, `J_DP.head_start_accept,
                     $signed(`J_SH.private_head_activation_exponent_o));
        if (`J_SH.argmax_start_transfer)
            $display("HEAD_JOIN ARGSTART %0d %0d", j_epoch, core_cycle_q);
        if (`J_DP.projection_is_head && `J_PR.start_transfer) begin
            $display("HEAD_JOIN START %0d %0d %0d %0d %0d", j_epoch, core_cycle_q,
                     `J_PR.fixed_layer_i, `J_PR.fixed_job_i, $signed(`J_PR.activation_exponent_i));
            if (j_head || j_nf_count != 256)
                $display("HEAD_JOIN ERROR %0d %0d 1", j_epoch, core_cycle_q);
            j_head = 1;
            j_writes = 0;
            j_reads = 0;
            j_weights = 0;
        end
        if (j_head && `J_PR.activation_store_write) begin
            if (!`J_DP.projection_is_head || `J_PR.activation_count_q != j_writes || j_writes >= 256)
                $display("HEAD_JOIN ERROR %0d %0d 2", j_epoch, core_cycle_q);
            else begin
                j_shadow[j_writes] = `J_PR.activation_i;
                $display("HEAD_JOIN LOAD %0d %0d %0d %0d %0d %0d %0d %0d",
                         j_epoch, core_cycle_q, `J_PR.activation_count_q, $signed(`J_PR.activation_i),
                         $signed(`J_PR.activation_exponent_q), `J_PR.activation_last_i,
                         `J_SH.head_input_transfer, `J_SH.private_head_activation_index_o);
            end
            j_writes = j_writes + 1;
        end
        if (j_pending_read) begin
            if (`J_PR.activation_q !== j_expected_read || core_cycle_q != j_read_cycle + 1)
                $display("HEAD_JOIN ERROR %0d %0d 3", j_epoch, core_cycle_q);
            if (j_reads == 1)
                $display("HEAD_JOIN READ_Q %0d %0d %0d %0d", j_epoch, core_cycle_q,
                         j_read_col, $signed(`J_PR.activation_q));
            j_pending_read = 0;
        end
        if (j_head && `J_PR.activation_store_read) begin
            j_read_col = int'(`J_PR.activation_store_read_address);
            if (j_read_col != (j_reads % 256) || j_read_col >= j_writes)
                $display("HEAD_JOIN ERROR %0d %0d 4", j_epoch, core_cycle_q);
            else begin
                j_expected_read = j_shadow[j_read_col];
                j_read_cycle = core_cycle_q;
                j_pending_read = 1;
            end
            if (j_reads == 0)
                $display("HEAD_JOIN READ_ISSUE %0d %0d %0d", j_epoch, core_cycle_q, j_read_col);
            j_reads = j_reads + 1;
        end
        if (j_head && `J_PR.weight_transfer) begin
            if (`J_PR.column_q != (j_weights % 256) || `J_PR.group_q != (j_weights / 256) ||
                j_writes != 256 || j_reads != j_weights + 1 + int'(`J_PR.activation_store_read) ||
                `J_PR.activation_q !== j_shadow[int'(`J_PR.column_q[7:0])])
                $display("HEAD_JOIN ERROR %0d %0d 5", j_epoch, core_cycle_q);
            j_weights = j_weights + 1;
            if (`J_PR.column_q == 255)
                $display("HEAD_JOIN GROUP %0d %0d %0d %0d %0d", j_epoch, core_cycle_q,
                         `J_PR.group_q, j_weights, j_reads);
        end
        if (j_head && `J_AG.row_valid_i && !`J_AG.row_ready_o && `J_AG.row_last_i)
            $display("HEAD_JOIN STALL %0d %0d %0d %0d %0d %0d", j_epoch, core_cycle_q,
                     `J_AG.row_index_i, $signed(`J_AG.row_scaled_raw_i),
                     $signed(`J_AG.row_source_exponent_i), `J_AG.row_last_i);
        if (`J_DP.head_result_fire || `J_SH.head_result_transfer || `J_AG.row_fire)
            $display("HEAD_JOIN ROW %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
                     j_epoch, core_cycle_q, `J_DP.head_result_fire, `J_SH.head_result_transfer,
                     `J_AG.row_fire, `J_AG.row_index_i, $signed(`J_AG.row_scaled_raw_i),
                     $signed(`J_AG.row_source_exponent_i), `J_AG.row_last_i,
                     `J_PR.result_valid_o && `J_PR.result_ready_i &&
                     `J_PR.result_row_index_o == `J_AG.row_index_i &&
                     `J_PR.result_scaled_raw_o == `J_AG.row_scaled_raw_i &&
                     `J_PR.result_source_exponent_o == `J_AG.row_source_exponent_i &&
                     `J_PR.result_last_o == `J_AG.row_last_i);
        if (`J_SH.winner_transfer)
            $display("HEAD_JOIN WIN %0d %0d %0d %0d %0d", j_epoch, core_cycle_q,
                     `J_SH.argmax_winner_token, $signed(`J_SH.argmax_winner_scaled),
                     $signed(`J_SH.argmax_winner_exponent));
        if (j_successor_commit)
            $display("HEAD_JOIN HOLD %0d %0d %0d %0d", j_epoch, core_cycle_q,
                     `J_SH.state_q, `J_SH.generated_token_q);
        j_successor_commit = j_commit;
        if (j_commit)
            $display("HEAD_JOIN COMMIT %0d %0d %0d %0d %0d %0d", j_epoch, core_cycle_q,
                     `J_SH.completing_winner, j_writes, j_reads, j_weights);
        if (j_capture || (token_valid_o && token_ready_i)) begin
            $display("HEAD_JOIN CAP %0d %0d %0d %0d %0d %0d %0d %0d",
                     j_epoch, core_cycle_q, j_capture, token_valid_o && token_ready_i,
                     u_uart.result_token, token_o, `J_SH.generated_token_q, j_clear);
            j_head = 0;
        end
        if (`J_BR.tx_valid && `J_BR.tx_ready && `J_BR.response_index_q == 0 &&
            `J_BR.response_kind_q == 8'h81)
            $display("HEAD_JOIN FIRST %0d %0d %0d", j_epoch, core_cycle_q, `J_BR.response_token_q);
    end
end

`undef J_SH
`undef J_AG
`undef J_DP
`undef J_PR
`undef J_RM
`undef J_BR
