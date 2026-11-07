// SPDX-License-Identifier: Apache-2.0
`timescale 1ns/1ps
`default_nettype none
// Redistributable functional simulation of the two read-only AES lookup ports
// used here: one common clock, both enables high, reset/write disabled, one
// synchronous read latency. This is not a general FPGA block-RAM model.
module combined_public_aes_lookup_sim(
    input wire clk,
    input wire [7:0] address_a_i,address_b_i,
    output logic [7:0] data_a_o,data_b_o
);
    logic [7:0] table_q[0:255];
    function automatic [7:0] multiply(input [7:0] aa,bb);
        reg [7:0] a,b,z;
        begin
            a=aa;b=bb;z=0;
            for(integer i=0;i<8;i=i+1)begin
                if(b[0])z=z^a;
                a={a[6:0],1'b0}^({8{a[7]}}&8'h1b);
                b=b>>1;
            end
            multiply=z;
        end
    endfunction
    function automatic [7:0] substitute(input [7:0] x);
        reg [7:0] power,inverse;
        begin
            // x^254 in GF(2^8), with zero mapped to zero before the affine map.
            power=x;inverse=8'd1;
            for(integer bit_index=0;bit_index<8;bit_index=bit_index+1)begin
                if(bit_index!=0)inverse=multiply(inverse,power);
                power=multiply(power,power);
            end
            substitute=inverse^{inverse[6:0],inverse[7]}^{inverse[5:0],inverse[7:6]}^
                {inverse[4:0],inverse[7:5]}^{inverse[3:0],inverse[7:4]}^8'h63;
        end
    endfunction
    initial for(integer i=0;i<256;i=i+1)table_q[i]=substitute(8'(i));
    always_ff @(posedge clk)begin
        data_a_o<=table_q[address_a_i];
        data_b_o<=table_q[address_b_i];
    end
endmodule
`default_nettype wire
