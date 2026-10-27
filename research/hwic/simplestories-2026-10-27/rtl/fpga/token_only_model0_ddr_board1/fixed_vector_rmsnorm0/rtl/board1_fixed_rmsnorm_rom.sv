`timescale 1ns/1ps
`default_nettype none

// Immutable test-ROM realization of the product-private fixed-address norm
// seam.  Address is generated only by the six-layer schedule below the public
// APPEND/STEP/CLEAR controller; it is not a product or package interface.
module board1_fixed_rmsnorm_rom #(
    parameter integer FINAL_ONLY=0,
    parameter NORM_ROM_FILE =
        "fpga/token_only_model0_ddr_board1/fixed_vector_rmsnorm0/recorded/norm_rom34.memh"
) (
    input  wire                    clk,
    input  wire                    read_i,
    input  wire [11:0]             fixed_address_i,
    output logic signed [9:0]      coefficient_o,
    output logic [15:0]            multiplier_o,
    output logic signed [7:0]      tensor_exponent_o
);
    generate if(FINAL_ONLY)begin:g_final
        (* rom_style="block" *) logic[33:0] norm_rom[0:255];
        initial $readmemh("fixed/norm_final34.memh",norm_rom);
        always_ff @(posedge clk)if(read_i && fixed_address_i>=3072 && fixed_address_i<3328)begin
            coefficient_o<=$signed(norm_rom[fixed_address_i[7:0]][9:0]);
            multiplier_o<=norm_rom[fixed_address_i[7:0]][25:10];
            tensor_exponent_o<=$signed(norm_rom[fixed_address_i[7:0]][33:26]);
        end
    end else begin:g_layers
        (* rom_style="block" *) logic[33:0] norm_rom[0:3071];
        initial $readmemh("fixed/norm_layers34.memh",norm_rom);
        always_ff @(posedge clk)if(read_i && fixed_address_i<3072)begin
            coefficient_o<=$signed(norm_rom[fixed_address_i][9:0]);
            multiplier_o<=norm_rom[fixed_address_i][25:10];
            tensor_exponent_o<=$signed(norm_rom[fixed_address_i][33:26]);
        end
    end endgenerate

endmodule

`default_nettype wire
