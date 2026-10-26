`timescale 1ns/1ps
`default_nettype none

// Compact private fixed-model arithmetic array.
//
// Lanes 0--15 instantiate the frozen five-mode rich lane.  Lanes 16--63
// instantiate the frozen three-mode projection/head lane and therefore have
// no dynamic A16 operand, wide signed-26 operand, u16 scale operand, or
// associated wide mode mux.  The issue guard rejects any mode-3/4 request
// naming an upper lane before a result-valid bit can reach downstream state.
module board1_asymmetric_unified_dsp64 (
    input  wire                     request_valid_i,
    input  wire [2:0]               private_mode_i,
    input  wire [63:0]              requested_lanes_i,
    input  wire [64*16-1:0]         activation_i,
    input  wire [64*10-1:0]         direct_weight_i,
    input  wire [64*4-1:0]          coarse_weight0_i,
    input  wire [64*4-1:0]          coarse_weight1_i,
    input  wire [64*6-1:0]          residual_weight0_i,
    input  wire [64*6-1:0]          residual_weight1_i,
    input  wire [16*16-1:0]         dynamic_operand_i,
    input  wire [16*26-1:0]         wide_operand_i,
    input  wire [16*16-1:0]         scale_operand_i,
    output wire                     issue_valid_o,
    output wire [63:0]              issued_lanes_o,
    output wire                     illegal_request_o,
    output wire [64*32-1:0]         product0_o,
    output wire [64*32-1:0]         product1_o,
    output wire [16*48-1:0]         wide_product_o
);
    wire [16*32-1:0] rich_product0;
    wire [16*32-1:0] rich_product1;
    wire [16*48-1:0] rich_wide_product;
    wire [48*26-1:0] lean_product0;
    wire [48*26-1:0] lean_product1;

    board1_asymmetric_private_issue_guard u_guard (
        .request_valid_i(request_valid_i),
        .private_mode_i(private_mode_i),
        .requested_lanes_i(requested_lanes_i),
        .issue_valid_o(issue_valid_o),
        .issued_lanes_o(issued_lanes_o),
        .illegal_request_o(illegal_request_o)
    );

    genvar lane;
    generate
        for (lane = 0; lane < 16; lane = lane + 1) begin : g_rich
            board1_fixed_elementwise_dsp_lane u_lane (
                .mode_i(private_mode_i),
                .activation_i(activation_i[lane*16 +: 16]),
                .dynamic_operand_i(dynamic_operand_i[lane*16 +: 16]),
                .direct_weight_i(direct_weight_i[lane*10 +: 10]),
                .coarse_weight0_i(coarse_weight0_i[lane*4 +: 4]),
                .coarse_weight1_i(coarse_weight1_i[lane*4 +: 4]),
                .residual_weight0_i(residual_weight0_i[lane*6 +: 6]),
                .residual_weight1_i(residual_weight1_i[lane*6 +: 6]),
                .wide_operand_i(wide_operand_i[lane*26 +: 26]),
                .scale_operand_i(scale_operand_i[lane*16 +: 16]),
                .product0_o(rich_product0[lane*32 +: 32]),
                .product1_o(rich_product1[lane*32 +: 32]),
                .wide_product_o(rich_wide_product[lane*48 +: 48])
            );

            assign product0_o[lane*32 +: 32] = issued_lanes_o[lane] ?
                rich_product0[lane*32 +: 32] : 32'd0;
            assign product1_o[lane*32 +: 32] = issued_lanes_o[lane] ?
                rich_product1[lane*32 +: 32] : 32'd0;
            assign wide_product_o[lane*48 +: 48] = issued_lanes_o[lane] ?
                rich_wide_product[lane*48 +: 48] : 48'd0;
        end

        for (lane = 16; lane < 64; lane = lane + 1) begin : g_lean
            localparam integer LEAN = lane - 16;
            board1_unified_projection_head_mul_exact u_lane (
                .mode_i(private_mode_i[1:0]),
                .activation_i(activation_i[lane*16 +: 16]),
                .direct_weight_i(direct_weight_i[lane*10 +: 10]),
                .coarse_weight0_i(coarse_weight0_i[lane*4 +: 4]),
                .coarse_weight1_i(coarse_weight1_i[lane*4 +: 4]),
                .residual_weight0_i(residual_weight0_i[lane*6 +: 6]),
                .residual_weight1_i(residual_weight1_i[lane*6 +: 6]),
                .product0_o(lean_product0[LEAN*26 +: 26]),
                .product1_o(lean_product1[LEAN*26 +: 26])
            );

            assign product0_o[lane*32 +: 32] = issued_lanes_o[lane] ?
                {{6{lean_product0[LEAN*26 + 25]}},
                 lean_product0[LEAN*26 +: 26]} : 32'd0;
            assign product1_o[lane*32 +: 32] = issued_lanes_o[lane] ?
                {{6{lean_product1[LEAN*26 + 25]}},
                 lean_product1[LEAN*26 +: 26]} : 32'd0;
        end
    endgenerate
endmodule

`default_nettype wire
