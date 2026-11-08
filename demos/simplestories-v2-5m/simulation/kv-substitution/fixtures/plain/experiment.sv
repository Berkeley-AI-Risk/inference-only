// Testbench instrumentation only. No internal RTL state is driven.
`define OBS_ATTN dut.u_machine.u_six_layers.u_datapath.u_attention
wire negate_l0=$test$plusargs("NEGATE_V");
wire negate_l4=$test$plusargs("NEGATE_L4");
wire alternate_history=negate_l0 || negate_l4;
wire [18:0] first_value_word=negate_l4 ? 19'd374537 : 19'd227081;
wire selected_old_v=app_return && raw_owner_fifo[raw_rd_q] &&
    raw_fifo[raw_rd_q]>=first_value_word && raw_fifo[raw_rd_q]<first_value_word+19'd8;
wire [255:0] ordinary_word=!app_return ? 256'd0 : (raw_fifo[raw_rd_q]<IMAGE_WORDS ?
    model_memory[raw_fifo[raw_rd_q]] : scratch_memory[raw_fifo[raw_rd_q]-227072]);
wire [255:0] alternate_word;
for(genvar i=0;i<16;i++) begin
    assign alternate_word[16*i+:16]=16'd0-ordinary_word[16*i+:16];
end
wire [255:0] delivered_word=selected_old_v && alternate_history ? alternate_word : ordinary_word;
wire [255:0] app_rdata=delivered_word ^ (runtime_corrupt_return ? 256'd1 : 256'd0);

always @(posedge phy_clk_i) begin
    if (app_return && raw_owner_fifo[raw_rd_q] && raw_fifo[raw_rd_q]>=227072)
        $display("KV_RETURN %0d %0d %064x %064x",app_cycle_q,raw_fifo[raw_rd_q],ordinary_word,delivered_word);
    if (app_cmd_en && app_cmd==0 && thin_issue_runtime)
        $display("KV_WRITE %0d %0d %064x",app_cycle_q,app_addr[21:3],app_wdata);
end
always @(posedge core_clk_i) begin
    if ((`OBS_ATTN.fixed_layer_i==0 || `OBS_ATTN.fixed_layer_i==4) && `OBS_ATTN.fixed_position_i==1) begin
        if(`OBS_ATTN.query_valid_i && `OBS_ATTN.query_ready_o)
            $display("L%0d_QUERY %0d %0d %0256x",`OBS_ATTN.fixed_layer_i,`OBS_ATTN.query_beat_q,$signed(`OBS_ATTN.query_exponent_i),`OBS_ATTN.query_vector_i);
        if(`OBS_ATTN.result_valid_o && `OBS_ATTN.result_ready_i)
            $display("L%0d_ATTENTION %0d %0d %0256x",`OBS_ATTN.fixed_layer_i,`OBS_ATTN.result_beat_q,$signed(`OBS_ATTN.result_exponent_o),`OBS_ATTN.result_vector_o);
        if(`OBS_ATTN.state_q==`OBS_ATTN.ST_VALUE_ACCUMULATE && `OBS_ATTN.coordinate_q==0)
            $display("L%0d_PV %0d %0d %0d %0d",`OBS_ATTN.fixed_layer_i,`OBS_ATTN.attention_head_q,`OBS_ATTN.scan_position_q,
                $signed(`OBS_ATTN.workspace_probability_at_scan),$signed(`OBS_ATTN.aligned_value_selected_group[15:0]));
    end
end

// Passive observation at the existing public token handshake.
always @(posedge core_clk_i) if(token_valid_o && token_ready_i)
    $display("TOKEN %0d %0d",core_cycle_q,token_o);
