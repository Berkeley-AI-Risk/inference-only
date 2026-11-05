`timescale 1ns/1ps
module startup_reset(input core_clk,board_reset_n,trusted_reset_n,app_reset_n,
                     output core_reset_n_o, output qualified_reset_n_o);
    wire common_async_reset_n=board_reset_n && trusted_reset_n && app_reset_n;
    (* async_reg="true",syn_preserve=1 *) logic core_phase_release_q;
    always_ff @(negedge core_clk or negedge common_async_reset_n) begin
        if(!common_async_reset_n) core_phase_release_q<=0;
        else core_phase_release_q<=1'b1;
    end
    wire qualified_async_reset_n=common_async_reset_n && core_phase_release_q;
    (* async_reg="true",syn_preserve=1 *) logic [2:0] core_release_q;
    always_ff @(posedge core_clk or negedge qualified_async_reset_n) begin
        if(!qualified_async_reset_n) core_release_q<=0;
        else core_release_q<={core_release_q[1:0],1'b1};
    end
    wire core_reset_n=core_release_q[2];
assign core_reset_n_o=core_reset_n;
assign qualified_reset_n_o=qualified_async_reset_n;
endmodule

module proof(input core_clk,board_reset_n,trusted_reset_n,app_reset_n);
  wire ready;
  wire all_clear;
  startup_reset dut(core_clk,board_reset_n,trusted_reset_n,app_reset_n,ready,all_clear);
  reg [1:0] stable_edges;
  always @(posedge core_clk or negedge all_clear)
    if(!all_clear)stable_edges<=0;
    else if(stable_edges<3)stable_edges<=stable_edges+1;
  always @*begin
    assert(ready==(stable_edges==3));
    if(!all_clear)assert(!ready);
  end
endmodule
