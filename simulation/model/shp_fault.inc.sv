
        if ($test$plusargs("SHP_FAULT")) begin : shp_fault_campaign
            integer target,with_clear,reboot,quiet_model,quiet_writes;
            bit reached;
            if (!$value$plusargs("SHP_TARGET=%d",target) || !(target==3 || target==8 || target==14 || target==21 || target==22) ||
                !$value$plusargs("SHP_CLEAR=%d",with_clear) || with_clear<0 || with_clear>1 ||
                !$value$plusargs("SHP_REBOOT=%d",reboot) || reboot<0 || reboot>1)
                $fatal(1,"SHP fault test parameters missing/invalid");
            append_token(12'd378);launch_step();reached=0;
            while (!reached) begin
                case(target)
                    3: reached=(`SP_SHELL.state_q==3 && `SP_SHELL.embed_result_valid && `SP_SHELL.capture_index_q==17);
                    8: reached=(`SP_SHELL.state_q==8 && `SP_SHELL.private_layer_result_valid_i && `SP_SHELL.capture_index_q==17);
                    14: reached=(`SP_SHELL.state_q==14 && `SP_SHELL.rms_result_valid && `SP_SHELL.capture_index_q==17);
                    21: reached=(`SP_SHELL.state_q==21);
                    22: reached=(`SP_SHELL.state_q==22 && token_valid_o);
                endcase
                if (fail_closed_o || (token_valid_o && target!=22))
                    $fatal(1,"SHP active fault target missed");
                if (!reached) @(negedge core_clk_i);
            end
            if (!`SP_SHELL.rst_n || sp_fault_edges!=0 || sp_injected_edges!=0)
                $fatal(1,"SHP target did not have live fault-free ownership");
            if (target==22) begin
                repeat(4) begin
                    @(negedge core_clk_i);
                    if (!token_valid_o || token_o!=200 || token_ready_i)
                        $fatal(1,"SHP pre-fault held token was not the exact unaccepted result");
                end
                $display("SHP_HELD_TOKEN token=200 accepted=0");
            end
            if (target==3 && !`SP_SHELL.ddr_owner_q)
                $fatal(1,"SHP embedding target had no real read ownership");
            sp_expect_fault=1;sp_inject_fault=1;clear_i=with_clear;
            @(negedge core_clk_i);
            if (!`SP_SHELL.fail_q || `SP_SHELL.state_q!=31 || !fail_closed_o ||
                sp_fault_edges!=1 || sp_injected_edges!=1 || sp_first_fault_state!=target)
                $fatal(1,"SHP did not take the intended fatal edge immediately");
            sp_inject_fault=0;clear_i=0;
            // Already accepted reads may drain/discard. A sticky root fault
            // may reset private children; that does not grant public recovery.
            repeat(64) begin
                @(negedge core_clk_i);
                if (!fail_closed_o || append_ready_o || step_ready_o || token_valid_o)
                    $fatal(1,"SHP fault did not keep the public interface closed");
            end
            quiet_model=model_requests_q;quiet_writes=endpoint_kv_writes_q;
            for(integer attempt=0;attempt<128;attempt++) begin
                clear_i=(attempt%3==0);append_valid_i=1;append_token_i=378;
                step_valid_i=1;token_ready_i=1;
                @(negedge core_clk_i);
                if (!fail_closed_o || model_locked_o || append_ready_o || step_ready_o || token_valid_o ||
                    private_endpoint_req_valid_o || app_cmd_en || app_wr_en ||
                    model_requests_q!=quiet_model || endpoint_kv_writes_q!=quiet_writes)
                    $fatal(1,"SHP CLEAR/APPEND/STEP revived terminal work");
            end
            clear_i=0;append_valid_i=0;append_token_i=0;step_valid_i=0;token_ready_i=0;
            if (raw_count_q!=0 || sp_fault_clocks==0 || sp_fault_edges!=1 || sp_first_fault_state!=target)
                $fatal(1,"SHP fault coverage/drain census incomplete");
            $display("SHP_FAULT_CLOSED state=%0d simultaneous_clear=%0d injected_edges=1 sticky_public=1 public_attempts=128 external_drained=1 no_new_requests=1",target,with_clear);
            if (reboot) begin
                // Genuine reset, ordered image reload, full readback and SHA;
                // no injected lock, forced state or seeded scratch/weights.
                reset_n_i=0;sp_expect_fault=0;
                repeat(8) @(negedge core_clk_i);
                if (fail_closed_o || model_locked_o || append_ready_o || step_ready_o || token_valid_o)
                    $fatal(1,"SHP hardware reset did not close the public surface");
                reset_n_i=1;
                while (!model_locked_o && !fail_closed_o) begin
                    @(negedge core_clk_i);
                    if (!model_locked_o && (append_ready_o || step_ready_o || token_valid_o))
                        $fatal(1,"SHP reset recovery skipped authenticated boot");
                end
                repeat(12) @(negedge core_clk_i);
                if (fail_closed_o || !model_locked_o || !append_ready_o ||
                    loader_words_q!=IMAGE_WORDS || boot_writes_q!=IMAGE_WORDS ||
                    boot_reads_q!=IMAGE_WORDS || boot_returns_q!=IMAGE_WORDS)
                    $fatal(1,"SHP reset recovery did not reauthenticate all fixed weights");
                $display("SHP_REBOOT_AUTHENTICATED words=%0d actual_boot_sha=1 forced_state=0",boot_returns_q);
                append_token(12'd378);measured_step(12'd200);
                if (dut.u_machine.layer_committed_prefixes!=={6{12'd1}} ||
                    dut.u_machine.u_token_shell.tape_count_q!=2 || fail_closed_o)
                    $fatal(1,"SHP reset six-layer replay did not recover exactly");
            end
            $display("PASS shp_fault state=%0d simultaneous_clear=%0d reboot=%0d real_layers=6 public_commands=3 actual_boot_sha=1 input_fault_only=1 forced_state=0",target,with_clear,reboot);
            $finish;
            disable test_campaign;
        end
