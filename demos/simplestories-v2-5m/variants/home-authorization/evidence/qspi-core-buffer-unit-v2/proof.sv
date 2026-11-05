module LUT1 #(parameter [1:0] INIT=2'h0)(output F,input I0);assign F=INIT[I0];endmodule
module reset_block(input core_clk_i,trusted_clk_i,core_reset_n_i,trusted_reset_n_i,
 output core_ready,slow_ready,qualified_core);
    wire common_reset_n=trusted_reset_n_i && core_reset_n_i;
    (* async_reg="true",syn_preserve=1 *) logic [2:0] slow_release_q,core_release_q;
    always_ff @(posedge trusted_clk_i or negedge common_reset_n)
        if(!common_reset_n) slow_release_q<=0;else slow_release_q<={slow_release_q[1:0],1'b1};
    wire core_reset_pad_0 /* synthesis syn_keep=1 */;
    LUT1 #(.INIT(2'h2)) u_core_reset_pad_0(.I0(common_reset_n),.F(core_reset_pad_0));
    wire core_reset_pad_1 /* synthesis syn_keep=1 */;
    LUT1 #(.INIT(2'h2)) u_core_reset_pad_1(.I0(core_reset_pad_0),.F(core_reset_pad_1));
    always_ff @(posedge core_clk_i or negedge core_reset_pad_1)
        if(!core_reset_pad_1) core_release_q<=0;else core_release_q<={core_release_q[1:0],1'b1};

assign core_ready=core_release_q[2];assign slow_ready=slow_release_q[2];
assign qualified_core=core_reset_pad_1;
endmodule

module proof(input core_clk_i,trusted_clk_i,core_reset_n_i,trusted_reset_n_i);
wire c,s,qualified;wire common=core_reset_n_i&&trusted_reset_n_i;
reset_block dut(core_clk_i,trusted_clk_i,core_reset_n_i,trusted_reset_n_i,c,s,qualified);
reg[1:0] cn,sn;
always @(posedge core_clk_i or negedge qualified)
 if(!qualified)cn<=0;else if(cn<3)cn<=cn+1;
always @(posedge trusted_clk_i or negedge common)
 if(!common)sn<=0;else if(sn<3)sn<=sn+1;
always @*begin
 assert(c==(cn==3));assert(s==(sn==3));
 if(!common)begin assert(!c);assert(!s);end
end
endmodule
