`timescale 1ns/1ps
`default_nettype none

// Exact private arithmetic lane shared by the ordinary transformer projections
// and the coarse/residual vocabulary-head passes.
//
// mode 0: one signed W10 x signed A16 result on product0_o; product1_o is zero.
// mode 1: two signed W4 x signed A16 coarse-head results.
// mode 2: two unsigned W6 x signed A16 residual-head results.
// mode 3: unreachable in the fixed controller and deliberately unspecified.
//
// Exactly one native signed 27x18 product is instantiated.  The head packing
// identities are the same exact identities proved in head_pair_dsp0; selecting
// mode 0 restores the ordinary sign-extended operands.  This module is a
// private, fixed-model lane and does not add any public arithmetic interface.
module board1_unified_projection_head_mul_exact (
    input  wire        [1:0]        mode_i,
    input  wire signed [15:0]       activation_i,
    input  wire signed [9:0]        direct_weight_i,
    input  wire signed [3:0]        coarse_weight0_i,
    input  wire signed [3:0]        coarse_weight1_i,
    input  wire        [5:0]        residual_weight0_i,
    input  wire        [5:0]        residual_weight1_i,
    output wire signed [25:0]       product0_o,
    output wire signed [25:0]       product1_o
);
    localparam [1:0] MODE_DIRECT   = 2'd0;
    localparam [1:0] MODE_COARSE   = 2'd1;
    localparam [1:0] MODE_RESIDUAL = 2'd2;

    wire signed [16:0] activation_extended =
        {activation_i[15], activation_i};
    wire [16:0] activation_magnitude = activation_i[15] ?
        $unsigned(-activation_extended) :
        $unsigned(activation_extended);

    wire signed [26:0] direct_operand =
        {{17{direct_weight_i[9]}}, direct_weight_i};
    wire signed [17:0] direct_activation_operand =
        {{2{activation_i[15]}}, activation_i};

    // q + 8 maps every signed W4 value [-8,7] into an unsigned four-bit field.
    wire [3:0] coarse_unsigned0 = coarse_weight0_i + 4'd8;
    wire [3:0] coarse_unsigned1 = coarse_weight1_i + 4'd8;
    wire signed [26:0] coarse_operand = $signed({
        3'b000, coarse_unsigned1, 16'b0, coarse_unsigned0
    });
    wire signed [26:0] residual_operand = $signed({
        residual_weight1_i, 15'b0, residual_weight0_i
    });
    wire signed [17:0] magnitude_operand =
        $signed({1'b0, activation_magnitude});

    reg signed [26:0] selected_a;
    reg signed [17:0] selected_b;
    always @* begin
        case (mode_i)
            MODE_DIRECT: begin
                selected_a = direct_operand;
                selected_b = direct_activation_operand;
            end
            MODE_COARSE: begin
                selected_a = coarse_operand;
                selected_b = magnitude_operand;
            end
            MODE_RESIDUAL: begin
                selected_a = residual_operand;
                selected_b = magnitude_operand;
            end
            default: begin
                selected_a = 27'bx;
                selected_b = 18'bx;
            end
        endcase
    end

    /* verilator lint_off UNUSEDSIGNAL */
    wire signed [47:0] dsp_product;
    /* verilator lint_on UNUSEDSIGNAL */

`ifdef BOARD1_UNIFIED_GW5_DSP
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
    ) u_shared_product (
        .DOUT(dsp_product), .CASO(), .SOA(),
        .A(selected_a), .SIA(27'd0), .B(selected_b),
        .C(48'd0), .D(26'd0), .CASI(48'd0),
        .ACCSEL(1'b0), .PSEL(1'b0), .ASEL(1'b0),
        .PADDSUB(1'b0), .CSEL(1'b0), .CASISEL(1'b0),
        .ADDSUB(2'b00),
        .CLK(2'b00), .CE(2'b00), .RESET(2'b00)
    );
`else
    wire signed [44:0] behavioral_product = selected_a * selected_b;
    assign dsp_product = {{3{behavioral_product[44]}}, behavioral_product};
`endif

    wire [19:0] coarse_raw0 = dsp_product[19:0];
    wire [19:0] coarse_raw1 = dsp_product[39:20];
    wire [19:0] coarse_bias_product = {activation_magnitude, 3'b000};
    wire signed [20:0] coarse_centered0 =
        $signed({1'b0, coarse_raw0}) -
        $signed({1'b0, coarse_bias_product});
    wire signed [20:0] coarse_centered1 =
        $signed({1'b0, coarse_raw1}) -
        $signed({1'b0, coarse_bias_product});
    wire signed [20:0] coarse_signed0 = activation_i[15] ?
        -coarse_centered0 : coarse_centered0;
    wire signed [20:0] coarse_signed1 = activation_i[15] ?
        -coarse_centered1 : coarse_centered1;

    wire [20:0] residual_raw0 = dsp_product[20:0];
    /* verilator lint_off UNUSEDSIGNAL */
    wire signed [47:0] residual_high_shifted = $signed(dsp_product) >>> 21;
    /* verilator lint_on UNUSEDSIGNAL */
    wire signed [23:0] residual_sign_correction =
        $signed({1'b0, activation_magnitude, 6'b000000});
    wire signed [23:0] residual_magnitude0 =
        $signed({3'b000, residual_raw0});
    wire signed [23:0] residual_magnitude1 =
        $signed(residual_high_shifted[23:0]) +
        (residual_weight1_i[5] ? residual_sign_correction : 24'sd0);
    wire signed [23:0] residual_signed0 = activation_i[15] ?
        -residual_magnitude0 : residual_magnitude0;
    wire signed [23:0] residual_signed1 = activation_i[15] ?
        -residual_magnitude1 : residual_magnitude1;

    reg signed [25:0] selected_product0;
    reg signed [25:0] selected_product1;
    always @* begin
        case (mode_i)
            MODE_DIRECT: begin
                selected_product0 = dsp_product[25:0];
                selected_product1 = 26'sd0;
            end
            MODE_COARSE: begin
                selected_product0 = {{5{coarse_signed0[20]}}, coarse_signed0};
                selected_product1 = {{5{coarse_signed1[20]}}, coarse_signed1};
            end
            MODE_RESIDUAL: begin
                selected_product0 = {{2{residual_signed0[23]}}, residual_signed0};
                selected_product1 = {{2{residual_signed1[23]}}, residual_signed1};
            end
            default: begin
                selected_product0 = 26'bx;
                selected_product1 = 26'bx;
            end
        endcase
    end

    assign product0_o = selected_product0;
    assign product1_o = selected_product1;
endmodule

`default_nettype wire
