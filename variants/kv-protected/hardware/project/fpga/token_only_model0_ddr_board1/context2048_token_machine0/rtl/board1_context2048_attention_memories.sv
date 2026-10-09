`timescale 1ns/1ps
`default_nettype none

// All memories in this milestone have one registered synchronous read port
// and one clocked write port.  Addresses are generated only by the enclosing
// fixed attention FSM; none is exposed at the product boundary.
module board1_context2048_attention_vector256x16 (
    input  wire                    clk,
    input  wire                    read_enable_i,
    input  wire [7:0]              read_address_i,
    output logic signed [15:0]     read_data_o,
    input  wire                    write_enable_i,
    input  wire [7:0]              write_address_i,
    input  wire signed [15:0]      write_data_i
);
    (* ram_style = "block", syn_ramstyle = "block_ram" *)
    logic signed [15:0] payload_mem [0:255];

    always_ff @(posedge clk) begin
        if (write_enable_i)
            payload_mem[write_address_i] <= write_data_i;
        if (read_enable_i)
            read_data_o <= payload_mem[read_address_i];
    end
endmodule

// The output store is deliberately 18 bits wide.  A head result first uses
// signed bits [16:0].  Global normalization later overwrites that same address
// with a sign-extended signed-16 result; no raw-output side array remains.
module board1_context2048_attention_vector256x18 (
    input  wire                    clk,
    input  wire                    read_enable_i,
    input  wire [7:0]              read_address_i,
    output logic signed [17:0]     read_data_o,
    input  wire                    write_enable_i,
    input  wire [7:0]              write_address_i,
    input  wire signed [17:0]      write_data_i
);
    (* ram_style = "block", syn_ramstyle = "block_ram" *)
    logic signed [17:0] payload_mem [0:255];

    always_ff @(posedge clk) begin
        if (write_enable_i)
            payload_mem[write_address_i] <= write_data_i;
        if (read_enable_i)
            read_data_o <= payload_mem[read_address_i];
    end
endmodule

// Three physical 2048x18 banks hold the 45-bit score workspace.  Every phase
// rewrites all banks together, which gives each bank exactly one syntactic
// write port.  Reads are registered.  The controller never asserts read and
// write together, so behavior does not depend on a device's read-during-write
// mode.
module board1_context2048_attention_workspace3x18 (
    input  wire                    clk,
    input  wire                    read_enable_i,
    input  wire [10:0]             read_address_i,
    output logic [17:0]            bank0_read_data_o,
    output logic [17:0]            bank1_read_data_o,
    output logic [17:0]            bank2_read_data_o,
    input  wire                    write_enable_i,
    input  wire [10:0]             write_address_i,
    input  wire [17:0]             bank0_write_data_i,
    input  wire [17:0]             bank1_write_data_i,
    input  wire [17:0]             bank2_write_data_i
);
    (* ram_style = "block", syn_ramstyle = "block_ram" *)
    logic [17:0] bank0_mem [0:2047];
    (* ram_style = "block", syn_ramstyle = "block_ram" *)
    logic [17:0] bank1_mem [0:2047];
    (* ram_style = "block", syn_ramstyle = "block_ram" *)
    logic [17:0] bank2_mem [0:2047];

    always_ff @(posedge clk) begin
        if (write_enable_i) begin
            bank0_mem[write_address_i] <= bank0_write_data_i;
            bank1_mem[write_address_i] <= bank1_write_data_i;
            bank2_mem[write_address_i] <= bank2_write_data_i;
        end
        if (read_enable_i) begin
            bank0_read_data_o <= bank0_mem[read_address_i];
            bank1_read_data_o <= bank1_mem[read_address_i];
            bank2_read_data_o <= bank2_mem[read_address_i];
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (read_enable_i && write_enable_i)
            $fatal(1,
                "workspace BSRAM read/write overlap: implementation must not depend on read-during-write behavior");
    end
`endif
endmodule

`default_nettype wire
