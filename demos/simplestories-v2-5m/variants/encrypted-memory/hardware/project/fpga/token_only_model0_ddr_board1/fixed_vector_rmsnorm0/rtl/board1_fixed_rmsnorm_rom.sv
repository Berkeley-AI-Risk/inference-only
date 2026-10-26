`timescale 1ns/1ps
`default_nettype none

// Immutable test-ROM realization of the product-private fixed-address norm
// seam.  Address is generated only by the six-layer schedule below the public
// APPEND/STEP/CLEAR controller; it is not a product or package interface.
module board1_fixed_rmsnorm_rom #(
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
    // 13 immutable vectors x 256 rows.  A synchronous read allows exact
    // device BSRAM inference; the file is independently reconstructed twice.
    (* nomem2reg, ram_style = "block" *)
    logic [33:0] norm_rom [0:3327];
    initial $readmemh(NORM_ROM_FILE, norm_rom);

    always_ff @(posedge clk) begin
        if (read_i && (fixed_address_i < 12'd3328)) begin
            coefficient_o <= $signed(norm_rom[fixed_address_i][9:0]);
            multiplier_o <= norm_rom[fixed_address_i][25:10];
            tensor_exponent_o <= $signed(norm_rom[fixed_address_i][33:26]);
        end
    end
endmodule

`default_nettype wire
