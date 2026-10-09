`timescale 1ns/1ps
`default_nettype none
// IPUG281-2.6E section 4.4.3 requires rst_n release synchronous to clk.
// Do not drive reset release directly from the multi-bit POR decode/button.
module private_ddr_probe_reset #(
    parameter integer POR_BITS = 18
) (
    input wire clk, reset_button,
    output wire reset_n
);
    logic [POR_BITS-1:0] poweron_q = 0;
    (* async_reg = "true", syn_preserve = 1 *)
    logic [2:0] release_q = 0;
    always_ff @(posedge clk) begin
        if (reset_button) poweron_q <= 0;
        else if (!(&poweron_q)) poweron_q <= poweron_q + 1'b1;
    end
    always_ff @(posedge clk or posedge reset_button) begin
        if (reset_button) release_q <= 0;
        else release_q <= {release_q[1:0], (&poweron_q)};
    end
    assign reset_n = release_q[2];
    initial begin
        if (POR_BITS < 2 || POR_BITS > 24) $fatal(1, "invalid POR geometry");
    end
endmodule
`default_nettype wire
