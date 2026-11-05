`timescale 1ns/1ps
module startup_reset(input core_clk,board_reset_n,trusted_reset_n,app_reset_n,
                     output core_reset_n_o);
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
endmodule
