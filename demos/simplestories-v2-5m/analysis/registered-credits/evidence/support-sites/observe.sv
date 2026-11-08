`define EMB dut.u_machine.u_token_shell.u_fixed_embedding
`define PROJ dut.u_machine.u_six_layers.u_datapath.u_projection.u_group_stream
bit trace_active=0;
bit [1774:0] page_seen=0;
int requested_token=-1;
wire take_proj=(`PROJ.fixed_layer_i==0 && `PROJ.fixed_job_i==6 && `PROJ.fixed_group_i<=1) ||
    (`PROJ.fixed_layer_i<=1 && `PROJ.fixed_job_i==0 && `PROJ.fixed_group_i==0);
wire saved_proj=(`PROJ.layer_q==0 && `PROJ.job_q==6 && `PROJ.group_q<=1) ||
    (`PROJ.layer_q<=1 && `PROJ.job_q==0 && `PROJ.group_q==0);
always @(posedge core_clk_i) if (trace_active) begin
    if (`EMB.group_valid && `EMB.group_ready)
        $display("HEADER %0d %0d %0d %0d %0d",core_cycle_q,`EMB.token_q,`EMB.token_group,`EMB.token_lane,`EMB.selected_header_multiplier);
    if (`EMB.norm_input_valid && `EMB.norm_input_ready && (`EMB.column_q==0 || `EMB.column_q==255))
        $display("EMBED %0d %0d %0d %0d %0d %0d",core_cycle_q,`EMB.token_q,`EMB.column_q,
            $signed(`EMB.selected_coefficient),`EMB.row_multiplier_q,$signed(`EMB.selected_product));
    if (`EMB.private_word_req_valid_o && `EMB.private_word_req_ready_i && (`EMB.u_tied_group_reader.u_metadata_reader.word_in_group_q==0 && `EMB.u_tied_group_reader.state_q!=4 || `EMB.u_tied_group_reader.state_q==4 && `EMB.u_tied_group_reader.issued_words_q==0))
        $display("EMB_ADDR %0d %0d %0d",core_cycle_q,`EMB.u_tied_group_reader.state_q,`EMB.private_word_req_index_o);
    if (`PROJ.descriptor_transfer && take_proj)
        $display("PROJ_DESC %0d %0d %0d %0d %0d %0d %0d",core_cycle_q,`PROJ.fixed_layer_i,`PROJ.fixed_job_i,
            `PROJ.fixed_group_i,`PROJ.descriptor_columns,`PROJ.descriptor_beat_base,`PROJ.descriptor_word_base_wide);
    if (saved_proj && `PROJ.private_word_req_valid_o && `PROJ.private_word_req_ready_i &&
        ((`PROJ.state_q==4 && `PROJ.issued_words_q==0) ||
         (`PROJ.state_q==2 && `PROJ.u_metadata_reader.word_in_group_q==0)))
        $display("PROJ_ADDR %0d %0d %0d %0d %0d %0d",core_cycle_q,`PROJ.layer_q,`PROJ.job_q,`PROJ.group_q,`PROJ.state_q,`PROJ.private_word_req_index_o);
end
always @(posedge phy_clk_i) if (trace_active && raw_read_fire && thin_issue_runtime && app_addr[21:3]<227062 && app_addr[9:3]==0) begin
    if (!page_seen[app_addr[21:10]]) begin
        page_seen[app_addr[21:10]]<=1;
        $display("RAM_PAGE %0d %0d",app_cycle_q,app_addr[21:3]);
    end
end
