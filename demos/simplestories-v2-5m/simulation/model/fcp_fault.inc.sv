
        if ($test$plusargs("FCP_FAULT")) begin : fcp_fault_campaign
            integer target,with_clear,reboot,quiet_model,quiet_writes;
            bit reached;
            if (!$value$plusargs("FCP_TARGET=%d",target) || target<1 || target>8 ||
                !$value$plusargs("FCP_CLEAR=%d",with_clear) || with_clear<0 || with_clear>1 ||
                !$value$plusargs("FCP_REBOOT=%d",reboot) || reboot<0 || reboot>1)
                $fatal(1,"FCP fault test parameters missing/invalid");
            append_token(12'd378);launch_step();reached=0;
            while (!reached) begin
                case(target)
                    1: reached=(`FP_DP.engine_state_q==1 && `FP_DP.rms_result_valid && `FP_DP.output_index_q==17);
                    2: reached=(`FP_DP.engine_state_q==2 && `FP_DP.norm_result_valid && `FP_DP.output_index_q==17);
                    3: reached=(`FP_DP.engine_state_q==3 && `FP_DP.lane_result_valid);
                    4: reached=(`FP_DP.engine_state_q==4 && `FP_DP.kv_read_valid_q && `FP_DP.input_index_q==17);
                    5: reached=(`FP_DP.engine_state_q==5 && `FP_DP.attention_query_read_valid_q && `FP_DP.attention_query_load_lane_q==17);
                    6: reached=(`FP_DP.engine_state_q==6 && `FP_DP.norm_result_valid && `FP_DP.output_index_q==17);
                    7: reached=(`FP_DP.engine_state_q==7 && 1'b1);
                    8: reached=(`FP_DP.engine_state_q==8 && `FP_DP.head_result_fire && `FP_DP.head_result_index_q==17);
                endcase
                if (fail_closed_o || token_valid_o)
                    $fatal(1,"FCP active fault target missed");
                if (!reached) @(negedge core_clk_i);
            end
            if (!`FP_DP.rst_n || fp_fault_edges!=0 || fp_injected_edges!=0)
                $fatal(1,"FCP target did not have live fault-free ownership");
            fp_expect_fault=1;fp_inject_fault=1;clear_i=with_clear;
            @(negedge core_clk_i);
            if (!`FP_DP.fault_q || `FP_DP.engine_state_q!=15 || !fail_closed_o ||
                fp_fault_edges!=1 || fp_injected_edges!=1 || fp_first_fault_engine!=target)
                $fatal(1,"FCP did not take the intended fatal edge immediately");
            fp_inject_fault=0;clear_i=0;
            // Already accepted reads may drain/discard. A sticky root fault
            // may reset private children; that does not grant public recovery.
            repeat(64) begin
                @(negedge core_clk_i);
                if (!fail_closed_o || append_ready_o || step_ready_o || token_valid_o)
                    $fatal(1,"FCP fault did not keep the public interface closed");
            end
            quiet_model=model_requests_q;quiet_writes=endpoint_kv_writes_q;
            for(integer attempt=0;attempt<128;attempt++) begin
                clear_i=(attempt%3==0);append_valid_i=1;append_token_i=378;
                step_valid_i=1;token_ready_i=1;
                @(negedge core_clk_i);
                if (!fail_closed_o || model_locked_o || append_ready_o || step_ready_o || token_valid_o ||
                    private_endpoint_req_valid_o || app_cmd_en || app_wr_en ||
                    model_requests_q!=quiet_model || endpoint_kv_writes_q!=quiet_writes)
                    $fatal(1,"FCP CLEAR/APPEND/STEP revived terminal work");
            end
            clear_i=0;append_valid_i=0;append_token_i=0;step_valid_i=0;token_ready_i=0;
            if (raw_count_q!=0 || fp_fault_clocks==0 || fp_fault_edges!=1 || fp_first_fault_engine!=target)
                $fatal(1,"FCP fault coverage/drain census incomplete");
            $display("FCP_FAULT_CLOSED engine=%0d simultaneous_clear=%0d injected_edges=1 sticky_public=1 public_attempts=128 external_drained=1 no_new_requests=1",target,with_clear);
            if (reboot) begin
                // Genuine reset, ordered image reload, full readback and SHA;
                // no injected lock, forced state or seeded scratch/weights.
                reset_n_i=0;fp_expect_fault=0;
                repeat(8) @(negedge core_clk_i);
                if (fail_closed_o || model_locked_o || append_ready_o || step_ready_o || token_valid_o)
                    $fatal(1,"FCP hardware reset did not close the public surface");
                reset_n_i=1;
                while (!model_locked_o && !fail_closed_o) begin
                    @(negedge core_clk_i);
                    if (!model_locked_o && (append_ready_o || step_ready_o || token_valid_o))
                        $fatal(1,"FCP reset recovery skipped authenticated boot");
                end
                repeat(12) @(negedge core_clk_i);
                if (fail_closed_o || !model_locked_o || !append_ready_o ||
                    loader_words_q!=IMAGE_WORDS || boot_writes_q!=IMAGE_WORDS ||
                    boot_reads_q!=IMAGE_WORDS || boot_returns_q!=IMAGE_WORDS)
                    $fatal(1,"FCP reset recovery did not reauthenticate all fixed weights");
                $display("FCP_REBOOT_AUTHENTICATED words=%0d actual_boot_sha=1 forced_state=0",boot_returns_q);
                append_token(12'd378);measured_step(12'd200);
                if (dut.u_machine.layer_committed_prefixes!=={6{12'd1}} ||
                    dut.u_machine.u_token_shell.tape_count_q!=2 || fail_closed_o)
                    $fatal(1,"FCP reset six-layer replay did not recover exactly");
            end
            $display("PASS fcp_fault engine=%0d simultaneous_clear=%0d reboot=%0d real_layers=6 public_commands=3 actual_boot_sha=1 input_fault_only=1 forced_state=0",target,with_clear,reboot);
            $finish;
            disable test_campaign;
        end
