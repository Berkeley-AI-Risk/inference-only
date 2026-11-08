        if(!model_locked_o || !append_ready_o || fail_closed_o) $fatal(1,"unsuccessful boot");
        if(!$value$plusargs("CASE=%d",change_mode) || change_mode>2) $fatal(1,"bad case");
        append_token(12'd378);
        launch_step();
        accept_token(12'd200);
        if(published!=1 || head_rows!=4019) $fatal(1,"first STEP incomplete");
        activated=1;
        integration_expect_fault=(change_mode!=0);
        for (int i=0;i<18;i++) begin
            logic [255:0] d;
            d=scratch_memory[START_OLD_ROW-227072+i];
            $display("SNAPSHOT %0d %064x %064x",START_OLD_ROW+i,d,
                selected(START_OLD_ROW+i) ? invert_lanes(d):d);
        end
        launch_step();
        if(change_mode==0) begin
            accept_token(12'd15);
            if(fail_closed_o || seen_fault || compare_failures!=0 || head_rows!=8038 || published!=2)
                $fatal(1,"control failed");
            $display("COMPLETED %0d %0d %0d",change_mode,published,head_rows);
        end else begin
            while(!fail_closed_o) begin
                if(token_valid_o) $fatal(1,"unexpected second candidate");
                @(negedge core_clk_i);
            end
            repeat (256) begin
                if(token_valid_o || step_ready_o || append_ready_o || !fail_closed_o) $fatal(1,"fault escaped");
                @(negedge core_clk_i);
            end
            if(compare_failures!=1 || !seen_fault || head_rows!=4019 || published!=1) $fatal(1,"wrong failure");
            $display("CLOSED %0d %0d %0d %0d 256",change_mode,published,head_rows,compare_failures);
        end
        $finish;
    end
