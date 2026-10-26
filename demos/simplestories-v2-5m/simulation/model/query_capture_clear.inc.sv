
        if ($test$plusargs("QUERY_CAPTURE_CLEAR")) begin : query_clear_campaign
            integer targets;
            targets=0;
            for (integer target=0; target<=64; target++) begin
                append_token(12'd378);launch_step();
                while (!(dut.u_machine.u_six_layers.u_datapath.engine_state_q ==
                         QC_E_ATTN &&
                         dut.u_machine.u_six_layers.u_datapath.current_layer_q == 0 &&
                         dut.u_machine.u_six_layers.u_datapath.attention_head_q == 0 &&
                         ((target==64 && dut.u_machine.u_six_layers.u_datapath.attention_query_loaded_q) ||
                          (target<64 && dut.u_machine.u_six_layers.u_datapath.attention_query_read_valid_q &&
                           dut.u_machine.u_six_layers.u_datapath.attention_query_load_lane_q == 6'(target))))) begin
                    if(fail_closed_o || token_valid_o) $fatal(1,"query CLEAR target not reached before fault/output");
                    @(negedge core_clk_i);
                end
                // Assert on this observation edge, not one edge after the
                // selected return would already have been captured.
                clear_i=1;
                repeat(4) @(negedge core_clk_i);
                clear_i=0;
                while(!append_ready_o || expected_count_q!=0 ||
                      dut.u_model_cdc.reserved_q!=0 || dut.u_shared.busy_o ||
                      dut.u_auth.dma_state_q!=0 || raw_count_q!=0) begin
                    if(fail_closed_o || token_valid_o) $fatal(1,"query CLEAR did not drain privately");
                    @(negedge core_clk_i);
                end
                if(dut.u_machine.u_token_shell.tape_count_q!=0 ||
                   dut.u_machine.layer_committed_prefixes!=0 ||
                   model_requests_q!=model_responses_q)
                    $fatal(1,"query CLEAR left tape/prefix/response ownership");
                targets=targets+1;
                $display("QUERY_CAPTURE_CLEAR target=%0d cancelled_captures=%0d unowned_differences=%0d tape=0 prefixes=0 drained=1",
                    target,qc_cancel_captures,qc_unowned_differences);
            end
            if(targets!=65 || qc_cancel_captures==0 || qc_unowned_differences==0)
                $fatal(1,"query CLEAR campaign did not witness every target and cancelled private copy");
            append_token(12'd378);measured_step(12'd200);
            if(fail_closed_o || dut.u_machine.layer_committed_prefixes!=={6{12'd1}} ||
               dut.u_machine.u_token_shell.tape_count_q!=2 || model_requests_q!=model_responses_q ||
               qc_handshakes<24)
                $fatal(1,"query CLEAR final real-model replay failed");
            $display("PASS query_capture_clear targets=65 token=200 real_layers=6 actual_boot_sha=1 actual_capture_monitor=1 public_commands=3 model_inference=1");
            $finish;
            disable test_campaign;
        end
