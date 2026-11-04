`timescale 1ns/1ps
`default_nettype none

// Exact private W10 x A16 lane for the Tang Mega 138K fast-path experiment.
//
// Arora V's native signed 27x18 multiplier directly covers this fixed model's
// signed W10 coefficient and signed A16 activation.  Explicit sign extension
// preserves their two's-complement values:
//
//   signed(sext27(w10)) * signed(sext18(a16)) = w10 * a16.
//
// Every legal product has magnitude at most 16,744,448 and therefore fits the
// existing signed 26-bit result.  BOARD1_GW5_DSP selects one explicit,
// combinational MULTALU27X18 with every non-multiply feature disabled.  The
// default branch is a bit-exact four-state behavioral model.
/* verilator lint_off DECLFILENAME */
module board1_direct_signed_w10_a16_mul_impl (
    input  wire signed [15:0] activation_i,
    input  wire signed [9:0]  weight_i,
    output wire signed [25:0] product_o
);
    wire signed [26:0] weight_operand = {{17{weight_i[9]}}, weight_i};
    wire signed [17:0] activation_operand =
        {{2{activation_i[15]}}, activation_i};
    /* verilator lint_off UNUSEDSIGNAL */
    wire signed [47:0] dsp_product;
    /* verilator lint_on UNUSEDSIGNAL */

`ifdef BOARD1_GW5_DSP
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
    ) u_signed_product (
        .DOUT(dsp_product), .CASO(), .SOA(),
        .A(weight_operand), .SIA(27'd0), .B(activation_operand),
        .C(48'd0), .D(26'd0), .CASI(48'd0),
        .ACCSEL(1'b0), .PSEL(1'b0), .ASEL(1'b0),
        .PADDSUB(1'b0), .CSEL(1'b0), .CASISEL(1'b0),
        .ADDSUB(2'b00),
        .CLK(2'b00), .CE(2'b00), .RESET(2'b00)
    );
`else
    wire signed [44:0] behavioral_product =
        weight_operand * activation_operand;
    assign dsp_product = {{3{behavioral_product[44]}}, behavioral_product};
`endif

    assign product_o = dsp_product[25:0];
endmodule
/* verilator lint_on DECLFILENAME */

// Stable generic Board1 seam.  Simulation uses the behavioral branch above;
// GW5 synthesis selects the explicit primitive through BOARD1_GW5_DSP.
module board1_w10_a16_mul_exact (
    input  wire signed [15:0] activation_i,
    input  wire signed [9:0]  weight_i,
    output wire signed [25:0] product_o
);
    board1_direct_signed_w10_a16_mul_impl u_direct_signed (
        .activation_i(activation_i),
        .weight_i(weight_i),
        .product_o(product_o)
    );
endmodule

`default_nettype wire
