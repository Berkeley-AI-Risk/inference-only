`timescale 1ns/1ps
`default_nettype none

// Fixed private 682x16 semantic scratchpad.  The payload has no reset or
// CLEAR path: the enclosing semantic schedule alone determines validity.
// One synchronous read and one synchronous write permit direct BSRAM
// inference without exposing an address or payload seam above the datapath.
module board1_fixed_semantic_scratch_ram (
    input  wire                    clk,
    input  wire                    private_read_enable_i,
    input  wire [9:0]              private_read_address_i,
    output logic signed [15:0]     private_read_data_o,
    input  wire                    private_write_enable_i,
    input  wire [9:0]              private_write_address_i,
    input  wire signed [15:0]      private_write_data_i
);
    (* ram_style = "block", syn_ramstyle = "block_ram" *)
    logic signed [15:0] payload_mem [0:681];

    always_ff @(posedge clk) begin
        if (private_write_enable_i)
            payload_mem[private_write_address_i] <= private_write_data_i;
        if (private_read_enable_i)
            private_read_data_o <= payload_mem[private_read_address_i];
    end
endmodule

`default_nettype wire
