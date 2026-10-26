
        if ($test$plusargs("NORMALIZER_SELECT_CLEAR")) begin : normalizer_clear_campaign
            integer owner, targets, before_cancel, after_cancel;
            logic [3:0] target_state;
            logic [9:0] target_row;
            bit reached;
            if (!$value$plusargs("NORMALIZER_SELECT_OWNER=%d",owner) || owner<0 || owner>3)
                $fatal(1,"normalizer CLEAR owner missing/invalid");
            targets=0;
            for (integer target=0; target<4; target++) begin
                case(target)
                    0: begin target_state=2; target_row=0; end
                    1: begin target_state=11; target_row=17; end
                    2: begin target_state=12; target_row=255; end
                    3: begin target_state=3; target_row=255; end
                endcase
                append_token(12'd378); launch_step(); reached=0;
                while (!reached) begin
                    case (owner)
                    0: reached=(dut.u_machine.u_token_shell.u_fixed_embedding.u_embedding_normalizer.state_q==target_state && dut.u_machine.u_token_shell.u_fixed_embedding.u_embedding_normalizer.scan_index_q==target_row);
                    1: reached=(dut.u_machine.u_six_layers.u_datapath.u_normalizer.state_q==target_state && dut.u_machine.u_six_layers.u_datapath.u_normalizer.scan_index_q==target_row);
                    2: reached=(dut.u_machine.u_six_layers.u_datapath.u_rmsnorm.u_frozen_vector_normalizer.state_q==target_state && dut.u_machine.u_six_layers.u_datapath.u_rmsnorm.u_frozen_vector_normalizer.scan_index_q==target_row);
                    3: reached=(dut.u_machine.u_token_shell.u_final_rmsnorm.u_frozen_vector_normalizer.state_q==target_state && dut.u_machine.u_token_shell.u_final_rmsnorm.u_frozen_vector_normalizer.scan_index_q==target_row);
                    endcase
                    if (fail_closed_o || token_valid_o)
                        $fatal(1,"normalizer CLEAR target missed before fault/token");
                    if (!reached) @(negedge core_clk_i);
                end
                case(owner)
                    0: begin if(!ns0_pending) $fatal(1,"embedding target unowned"); before_cancel=ns0_cancelled; end
                    1: begin if(!ns1_pending) $fatal(1,"projection target unowned"); before_cancel=ns1_cancelled; end
                    2: begin if(!ns2_pending) $fatal(1,"RMS target unowned"); before_cancel=ns2_cancelled; end
                    3: begin if(!ns3_pending) $fatal(1,"final RMS target unowned"); before_cancel=ns3_cancelled; end
                endcase
                clear_i=1;
                repeat (4) @(negedge core_clk_i);
                clear_i=0;
                while (!append_ready_o || expected_count_q!=0 ||
                       dut.u_model_cdc.reserved_q!=0 || dut.u_shared.busy_o ||
                       dut.u_auth.dma_state_q!=0 || raw_count_q!=0) begin
                    if (fail_closed_o || token_valid_o)
                        $fatal(1,"normalizer CLEAR did not drain privately");
                    @(negedge core_clk_i);
                end
                case(owner)
                    0: after_cancel=ns0_cancelled;
                    1: after_cancel=ns1_cancelled;
                    2: after_cancel=ns2_cancelled;
                    3: after_cancel=ns3_cancelled;
                endcase
                if (dut.u_machine.u_token_shell.tape_count_q!=0 ||
                    dut.u_machine.layer_committed_prefixes!=0 ||
                    model_requests_q!=model_responses_q || ep_pending ||
                    {ns0_pending,ns1_pending,ns2_pending,ns3_pending}!=0 || after_cancel!=before_cancel+1)
                    $fatal(1,"normalizer CLEAR retained public/private ownership");
                targets++;
                $display("NORMALIZER_SELECT_CLEAR owner=%0d target=%0d state=%0d row=%0d cancelled=%0d tape=0 prefixes=0 drained=1",
                    owner,target,target_state,target_row,after_cancel);
            end
            if (targets!=4) $fatal(1,"normalizer CLEAR target census incomplete");
            append_token(12'd378); measured_step(12'd200);
            if (fail_closed_o || dut.u_machine.layer_committed_prefixes!=={6{12'd1}} ||
                dut.u_machine.u_token_shell.tape_count_q!=2 || model_requests_q!=model_responses_q ||
                {ns0_pending,ns1_pending,ns2_pending,ns3_pending}!=0 || ep_pending)
                $fatal(1,"normalizer CLEAR final six-layer replay failed");
            $display("PASS normalizer_selection_clear owner=%0d targets=4 token=200 real_layers=6 actual_boot_sha=1 actual_prior_normalizers=4 public_commands=3 forced_state=0",owner);
            $finish;
            disable test_campaign;
        end
