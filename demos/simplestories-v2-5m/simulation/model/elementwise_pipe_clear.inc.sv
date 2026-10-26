
        if ($test$plusargs("ELEMENTWISE_PIPE_CLEAR")) begin : elementwise_clear_campaign
            integer targets, previous_cancellations;
            logic [3:0] ep_target;
            targets=0;
            for (integer target=0; target<9; target++) begin
                case (target)
                    0: ep_target=4'd4;
                    1: ep_target=4'd11;
                    2: ep_target=4'd12;
                    3: ep_target=4'd7;
                    4: ep_target=4'd13;
                    5: ep_target=4'd14;
                    6: ep_target=4'd8;
                    7: ep_target=4'd15;
                    8: ep_target=4'd9;
                    default: $fatal(1,"invalid arithmetic CLEAR target");
                endcase
                append_token(12'd378); launch_step();
                while (!(dut.u_machine.u_six_layers.u_datapath.current_layer_q == 0 &&
                         dut.u_machine.u_six_layers.u_datapath.u_elementwise_lane.u_fixed_elementwise_product_compact_lane.state_q == ep_target)) begin
                    if (fail_closed_o || token_valid_o)
                        $fatal(1,"arithmetic CLEAR target not reached before fault/output");
                    @(negedge core_clk_i);
                end
                // Cancel at the already-observed negedge, before this state
                // can publish its result on the next active clock edge.
                previous_cancellations=ep_cancelled;
                clear_i=1;
                repeat(4) @(negedge core_clk_i);
                clear_i=0;
                while (!append_ready_o || expected_count_q!=0 ||
                       dut.u_model_cdc.reserved_q!=0 || dut.u_shared.busy_o ||
                       dut.u_auth.dma_state_q!=0 || raw_count_q!=0) begin
                    if (fail_closed_o || token_valid_o)
                        $fatal(1,"arithmetic CLEAR failed to drain privately");
                    @(negedge core_clk_i);
                end
                if (dut.u_machine.u_token_shell.tape_count_q!=0 ||
                    dut.u_machine.layer_committed_prefixes!=0 ||
                    model_requests_q!=model_responses_q || ep_pending ||
                    ep_cancelled!=previous_cancellations+1)
                    $fatal(1,"arithmetic CLEAR left public/private ownership");
                targets=targets+1;
                $display("ELEMENTWISE_PIPE_CLEAR target=%0d state=%0d cancelled=%0d tape=0 prefixes=0 drained=1",
                    target,ep_target,ep_cancelled);
            end
            if (targets!=9 || ep_cancelled!=9)
                $fatal(1,"arithmetic CLEAR campaign did not witness all nine cancellations");
            append_token(12'd378); measured_step(12'd200);
            if (fail_closed_o || dut.u_machine.layer_committed_prefixes!=={6{12'd1}} ||
                dut.u_machine.u_token_shell.tape_count_q!=2 || model_requests_q!=model_responses_q ||
                ep_pending || ep_rope==0 || ep_silu==0 || ep_residual==0)
                $fatal(1,"arithmetic CLEAR final six-layer replay failed");
            $display("PASS elementwise_pipeline_clear targets=9 cancelled=9 token=200 real_layers=6 actual_boot_sha=1 actual_old_rtl_shadow=1 public_commands=3 forced_state=0");
            $finish;
            disable test_campaign;
        end
