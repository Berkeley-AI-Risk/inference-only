        if($test$plusargs("CLEAR_AT_MODEL_RESPONSE")) begin : active_clear_campaign
            integer waiting,owner_min;
            owner_min=1;
            if($value$plusargs("CLEAR_OWNER_MIN=%d",owner_min)) begin end
            if(owner_min<1 || owner_min>16) $fatal(1,"unsupported test owner minimum");
            append_token(12'd378);launch_step();
            waiting=0;
            while(!(dut.model_rsp_valid && dut.model_rsp_ready &&
                dut.u_machine.u_private_ddr_arbiter.owner_count_q>=owner_min) && !fail_closed_o && waiting<1000000) begin
                @(negedge core_clk_i);waiting=waiting+1;
            end
            if(fail_closed_o || waiting==1000000 || !busy_o || expected_count_q==0)
                $fatal(1,"active CLEAR did not reach a real owned response");
            $display("ACTIVE_CLEAR_EDGE owner_count=%0d auth_requests=%0d auth_responses=%0d",
                dut.u_machine.u_private_ddr_arbiter.owner_count_q,
                dut.u_auth.request_count_q,dut.u_auth.response_count_q);
            // We are at a falling edge, before the offered response would
            // transfer. No internal force, seeded cache or fake model lock.
            clear_i=1;
            #1;
            if(append_ready_o || step_ready_o || token_valid_o)
                $fatal(1,"active CLEAR did not immediately close public actions");
            repeat(3) @(negedge core_clk_i);
            clear_i=0;
            waiting=0;
            while((busy_o || !append_ready_o) && !fail_closed_o && waiting<2000000) begin
                @(negedge core_clk_i);waiting=waiting+1;
            end
            if(fail_closed_o || waiting==2000000)
                $fatal(1,"active CLEAR failed to drain: shell=%0d owners=%0d auth_requests=%0d auth_responses=%0d model_rsp=%b",
                    dut.u_machine.u_token_shell.state_q,
                    dut.u_machine.u_private_ddr_arbiter.owner_count_q,
                    dut.u_auth.request_count_q,dut.u_auth.response_count_q,dut.model_rsp_valid);
            if(expected_count_q!=0 || model_requests_q!=model_responses_q ||
                dut.u_machine.u_private_ddr_arbiter.owner_count_q!=0 ||
                dut.u_auth.request_count_q!=0 || dut.u_auth.response_count_q!=0)
                $fatal(1,"CLEAR reopened before every old model owner drained");
            $display("ACTIVE_CLEAR_DRAIN min_owners=%0d requests=%0d responses=%0d",owner_min,model_requests_q,model_responses_q);
            if(dut.u_machine.u_token_shell.tape_count_q!=0 ||
                dut.u_machine.layer_committed_prefixes!==72'd0 || step_ready_o || token_valid_o)
                $fatal(1,"active CLEAR did not revoke old tape/cache state");
            append_token(12'd378);measured_step(12'd200);
            if(dut.u_machine.layer_committed_prefixes!=={6{12'd1}} ||
                dut.u_machine.u_token_shell.tape_count_q!=2 ||
                dut.u_machine.u_token_shell.token_tape_q[1]!=200)
                $fatal(1,"active CLEAR fresh replay differs");
            $display("PASS active_clear_at_model_response actual_boot_sha=1 forced_state=0 fresh_token=200");
            $finish;
            disable test_campaign;
        end
