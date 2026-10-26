`timescale 1ns/1ps
`default_nettype none

// The product integration reaches only the dynamic signed-A16 by signed-A16
// use of the former five-mode elementwise DSP lane.  Keeping that exact
// reachable operation in a dedicated private wrapper removes mux and decode
// logic without creating a public arithmetic interface.
module board1_fixed_elementwise_product_dsp (
    input  wire signed [15:0] first_i,
    input  wire signed [15:0] second_i,
    output wire signed [31:0] product_o
);
    wire signed [26:0] first_operand = {{11{first_i[15]}}, first_i};
    wire signed [17:0] second_operand = {{2{second_i[15]}}, second_i};
    wire signed [47:0] dsp_product;

`ifdef BOARD1_FIXED_ELEMENTWISE_PRODUCT_GW5_DSP
    MULTALU27X18 #(
        .AREG_CLK("BYPASS"), .BREG_CLK("BYPASS"),
        .DREG_CLK("BYPASS"), .C_IREG_CLK("BYPASS"),
        .PSEL_IREG_CLK("BYPASS"), .PADDSUB_IREG_CLK("BYPASS"),
        .ADDSUB0_IREG_CLK("BYPASS"), .ADDSUB1_IREG_CLK("BYPASS"),
        .CSEL_IREG_CLK("BYPASS"), .CASISEL_IREG_CLK("BYPASS"),
        .ACCSEL_IREG_CLK("BYPASS"), .PREG_CLK("BYPASS"),
        .ADDSUB0_PREG_CLK("BYPASS"), .ADDSUB1_PREG_CLK("BYPASS"),
        .CSEL_PREG_CLK("BYPASS"), .CASISEL_PREG_CLK("BYPASS"),
        .ACCSEL_PREG_CLK("BYPASS"), .C_PREG_CLK("BYPASS"),
        .OREG_CLK("BYPASS"), .FB_PREG_EN("FALSE"),
        .SOA_PREG_EN("FALSE"), .PRE_LOAD(48'd0),
        .DYN_P_SEL("FALSE"), .P_SEL(1'b0),
        .DYN_P_ADDSUB("FALSE"), .P_ADDSUB(1'b0),
        .DYN_A_SEL("FALSE"), .A_SEL(1'b0),
        .DYN_ADD_SUB_0("FALSE"), .ADD_SUB_0(1'b0),
        .DYN_ADD_SUB_1("FALSE"), .ADD_SUB_1(1'b0),
        .DYN_C_SEL("FALSE"), .C_SEL(1'b0),
        .DYN_CASI_SEL("FALSE"), .CASI_SEL(1'b0),
        .DYN_ACC_SEL("FALSE"), .ACC_SEL(1'b0),
        .MULT12X12_EN("FALSE")
    ) u_product (
        .DOUT(dsp_product), .CASO(), .SOA(),
        .A(first_operand), .SIA(27'd0), .B(second_operand),
        .C(48'd0), .D(26'd0), .CASI(48'd0),
        .ACCSEL(1'b0), .PSEL(1'b0), .ASEL(1'b0),
        .PADDSUB(1'b0), .CSEL(1'b0), .CASISEL(1'b0),
        .ADDSUB(2'b00), .CLK(2'b00), .CE(2'b00), .RESET(2'b00)
    );
`else
    wire signed [44:0] behavioral_product = first_operand * second_operand;
    assign dsp_product = {{3{behavioral_product[44]}}, behavioral_product};
`endif

    assign product_o = dsp_product[31:0];
endmodule

`default_nettype wire
