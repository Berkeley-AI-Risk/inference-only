    // Independent transaction witness for the newly inserted transport. None
    // of these arrays/counters enters production RTL or supplies model data.
    logic [276:0] thin_expected_commands[0:63];
    logic [256:0] thin_expected_responses[0:63];
    longint thin_accepted=0,thin_issued=0,thin_read_accepted=0;
    longint thin_returns=0,thin_delivered=0,thin_max_reserved=0;
    longint thin_stop_drained=0,thin_clear_inflight=0;
    wire thin_issue_runtime=thin_expected_commands[thin_issued%64][276];
    wire thin_core_accept=sem_cmd_en && sem_cmd_ready;
    time thin_phy_last=0;
    always @(posedge core_clk_i or negedge reset_n_i) begin
        if(!reset_n_i) begin
            thin_accepted<=0;thin_read_accepted<=0;thin_delivered<=0;
            thin_max_reserved<=0;thin_clear_inflight<=0;
        end else begin
            if(u_transport.reserved_q != thin_read_accepted-thin_delivered)
                $fatal(1,"THIN response reservations are not conserved");
            if(u_transport.reserved_q>32) $fatal(1,"THIN response reservation overflow");
            if(u_transport.reserved_q>thin_max_reserved) thin_max_reserved<=u_transport.reserved_q;
            if(thin_accepted-thin_issued>32 || thin_accepted<thin_issued)
                $fatal(1,"THIN command ownership bound");
            if(thin_core_accept) begin
                if(private_endpoint_upstream_fault_i || fail_closed_o)
                    $fatal(1,"THIN accepted new command after core fault");
                if(!sem_wr_ready || (sem_cmd!=0 && sem_cmd!=1) ||
                    (sem_cmd==0 && (!sem_wr_en || !sem_wr_end || sem_wr_mask!=0)))
                    $fatal(1,"THIN malformed semantic command");
                thin_expected_commands[thin_accepted%64]<={private_model_locked_i,sem_cmd==0,sem_addr[21:3],sem_wr_data};
                thin_accepted<=thin_accepted+1;
                if(sem_cmd==1) thin_read_accepted<=thin_read_accepted+1;
            end
            if(sem_rd_valid) begin
                if(thin_delivered>=thin_returns || {sem_rd_end,sem_rd_data} !== thin_expected_responses[thin_delivered%64])
                    $fatal(1,"THIN return data/order differs from physical response");
                thin_delivered<=thin_delivered+1;
            end
            if(clear_i && thin_accepted!=thin_issued) thin_clear_inflight<=thin_clear_inflight+1;
            if(transport_fault) $fatal(1,"THIN unexpected transport fault core=%b app=%b",u_transport.core_fault_q,u_transport.app_fault_q);
        end
    end
    always @(posedge phy_clk_i or negedge reset_n_i) begin
        if(!reset_n_i) begin thin_issued<=0;thin_returns<=0;thin_stop_drained<=0;end
        else begin
            if(app_cmd_en) begin
                if(thin_issued>=thin_accepted || {app_cmd==0,app_addr[21:3],app_wdata} !== thin_expected_commands[thin_issued%64][275:0])
                    $fatal(1,"THIN physical command differs from immutable accepted owner");
                if(private_endpoint_upstream_fault_i || fail_closed_o) thin_stop_drained<=thin_stop_drained+1;
                thin_issued<=thin_issued+1;
            end
            if(app_return) begin
                if(thin_returns-thin_delivered>=64) $fatal(1,"THIN return oracle overflow");
                thin_expected_responses[thin_returns%64]<={1'b1,app_rdata};
                thin_returns<=thin_returns+1;
            end
        end
    end
    always @(posedge phy_clk_i) begin
        if(thin_phy_last!=0 && $time-thin_phy_last!=10) $fatal(1,"THIN physical app clock period");
        thin_phy_last=$time;
    end
    final begin
        if(thin_phy_last==0) $fatal(1,"THIN no physical clock observations");
        $display("THIN_TRANSPORT_MONITOR accepted=%0d issued=%0d reads=%0d physical_returns=%0d delivered=%0d max_reserved=%0d stop_drained=%0d clear_inflight=%0d",thin_accepted,thin_issued,thin_read_accepted,thin_returns,thin_delivered,thin_max_reserved,thin_stop_drained,thin_clear_inflight);
    end
