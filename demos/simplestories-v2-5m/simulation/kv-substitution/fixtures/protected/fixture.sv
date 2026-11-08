// Alternate external DDR contents. Only this test fixture uses the case selector.
`define KG dut.u_kv_integrity
`define ATT dut.u_machine.u_six_layers.u_datapath.u_attention
int change_mode=0;
bit activated=0;
localparam integer START_OLD_ROW=374528;
function automatic [255:0] invert_lanes(input [255:0] original);
    for(integer i=0;i<16;i++)
        invert_lanes[i*16+:16]=16'd0-original[i*16+:16];
endfunction
function automatic bit selected(input [18:0] addr);
    return activated && ((change_mode==1 && addr>=START_OLD_ROW+4 && addr<=START_OLD_ROW+7) ||
        (change_mode!=0 && addr>=START_OLD_ROW+13 && addr<=START_OLD_ROW+16));
endfunction
wire [255:0] ordinary_word=!app_return ? 256'd0 : (raw_fifo[raw_rd_q]<IMAGE_WORDS ?
    model_memory[raw_fifo[raw_rd_q]] : scratch_memory[raw_fifo[raw_rd_q]-227072]);
wire [255:0] app_rdata=selected(raw_fifo[raw_rd_q]) ? invert_lanes(ordinary_word) : ordinary_word;
always @(posedge phy_clk_i) begin
    if (app_return && raw_owner_fifo[raw_rd_q] && raw_fifo[raw_rd_q]>=START_OLD_ROW &&
            raw_fifo[raw_rd_q]<START_OLD_ROW+36)
        $display("PHY_RD %0d %0d %064x %064x",app_cycle_q,raw_fifo[raw_rd_q],ordinary_word,app_rdata);
    if (app_cmd_en && app_cmd==0 && thin_issue_runtime)
        $display("PHY_WR %0d %0d %064x",app_cycle_q,app_addr[21:3],app_wdata);
end
bit seen_fault=0;
int compare_failures=0,head_rows=0,published=0;
logic [2:0] observed_layer;
logic [11:0] observed_position;
logic [1:0] observed_head;
logic [3:0] observed_word;
bit read_pending=0;
always @(posedge core_clk_i) begin
    if (!reset_n_i) read_pending<=0;
    if (`KG.s_rd_valid && `KG.s_rd_ready) begin
        if(read_pending) $fatal(1,"overlapping guard read");
        observed_layer<=`KG.s_rd_layer; observed_position<=`KG.s_rd_position;
        observed_head<=`KG.s_rd_head; observed_word<=`KG.s_rd_word;
        read_pending<=1;
    end
    if(`KG.s_rd_rsp_valid && `KG.s_rd_rsp_ready) begin
        if(!read_pending) $fatal(1,"unowned guard return");
        read_pending<=0;
    end
    if (token_valid_o && token_ready_i) begin
        published++;
        $display("TOKEN %0d %0d",core_cycle_q,token_o);
    end
    if (dut.u_machine.u_token_shell.head_result_transfer) head_rows++;
    if (`KG.live && `KG.state_q==`KG.HDIGEST && `KG.hash_digest_valid &&
        `KG.layer_q==4 && `KG.page_q==0) begin
        $display("DIGEST %0d %0d %0d %0d %0d %0d %0d %064x %064x",
            core_cycle_q,`KG.hash_write_q,`KG.layer_q,`KG.group_head_q,`KG.role_q,`KG.positions_q,
            `KG.epoch_q,`KG.hash_digest,`KG.expected_q);
        if (!`KG.hash_write_q && `KG.hash_digest!=`KG.expected_q) compare_failures++;
    end
    if (activated && observed_layer==4 && `KG.s_rd_rsp_valid)
        $display("GUARD_OFFER %0d %0d %0d %0d %0d %0d %064x",core_cycle_q,observed_position,
            observed_head,observed_word,`KG.s_rd_rsp_fault,`KG.s_rd_rsp_ready,`KG.s_rd_rsp_data);
    if (activated && `ATT.fixed_layer_i==4 && `ATT.fixed_position_i==1) begin
        if (`ATT.query_valid_i && `ATT.query_ready_o)
            $display("QUERY %0d %0d %0256x",`ATT.query_beat_q,$signed(`ATT.query_exponent_i),`ATT.query_vector_i);
        if (`ATT.private_cache_request_valid_o && `ATT.private_cache_request_ready_i)
            $display("ATT_REQ %0d %0d %0d %0d",core_cycle_q,`ATT.private_cache_request_position_o,
                `ATT.private_cache_request_kv_head_o,`ATT.private_cache_request_kind_o);
        if (`ATT.private_cache_response_valid_i && `ATT.private_cache_response_ready_o)
            $display("ATT_RSP %0d %0d %0256x",core_cycle_q,`ATT.private_cache_response_fault_i,`ATT.private_cache_response_value_vector_i);
        if (`ATT.result_valid_o && `ATT.result_ready_i)
            $display("ATT_OUT %0d %0d %0256x",core_cycle_q,$signed(`ATT.result_exponent_o),`ATT.result_vector_o);
    end
    if (`KG.fault_o && !seen_fault) begin
        seen_fault=1;
        $display("GUARD_FAULT %0d %0d %0d %0d %0d %0d",core_cycle_q,`KG.fault_q,`KG.hash_fault,
            `KG.cache_valid_q,`KG.state_q,`KG.s_rd_rsp_fault);
    end
end
