`timescale 1ns/1ps
`default_nettype none

// Private fixed-model tile. Three stages separate operand capture, exact
// multiplication and accumulation. No tensor shape/address or public command.
// Payload has no reset: first_i overwrites every accumulator before any read.
module board1_projection_tile16 (
    input wire clk, reset_n, kill_i, begin_i,
    input wire [4:0] valid_lanes_i,
    input wire accept_i, first_i, last_i,
    input wire signed [15:0] activation_i,
    input wire [159:0] weights_i,
    input wire metadata_write_i,
    input wire [3:0] metadata_lane_i,
    input wire [15:0] metadata_multiplier_i,
    input wire signed [7:0] metadata_exponent_i,
    input wire read_i,
    input wire [3:0] read_lane_i,
    output logic signed [34:0] dot_o,
    output logic [15:0] multiplier_o,
    output logic signed [7:0] exponent_o,
    output logic done_o, fault_o
);
    logic op_valid_q, product_valid_q;
    logic op_first_q, op_last_q, product_first_q, product_last_q;
    logic [4:0] valid_lanes_q;
    logic signed [15:0] activation_q;
    logic signed [9:0] weight_q [0:15];
    logic signed [25:0] product_q [0:15];
    logic signed [34:0] accumulator_q [0:15];
    logic [15:0] multiplier_q [0:15];
    logic signed [7:0] exponent_q [0:15];
    wire signed [25:0] product [0:15];
    wire signed [35:0] next_sum [0:15];
    wire [15:0] bad_weight, overflow;

    genvar lane;
    generate for (lane=0; lane<16; lane=lane+1) begin : g_lane
        board1_w10_a16_mul_exact u_mul (
            .activation_i(activation_q), .weight_i(weight_q[lane]),
            .product_o(product[lane]));
        assign next_sum[lane] = product_first_q ?
            {{10{product_q[lane][25]}}, product_q[lane]} :
            $signed({accumulator_q[lane][34], accumulator_q[lane]}) +
            $signed({{10{product_q[lane][25]}}, product_q[lane]});
        assign overflow[lane] = next_sum[lane][35] != next_sum[lane][34];
        assign bad_weight[lane] = (weights_i[lane*10 +: 10] == 10'h200) ||
            ((lane >= valid_lanes_q) && (weights_i[lane*10 +: 10] != 10'd0));
        always_ff @(posedge clk) begin
            if (accept_i) weight_q[lane] <= weights_i[lane*10 +: 10];
            if (op_valid_q) product_q[lane] <= product[lane];
            if (product_valid_q) accumulator_q[lane] <= next_sum[lane][34:0];
        end
    end endgenerate

    always_ff @(posedge clk) begin
        if (accept_i) activation_q <= activation_i;
        if (metadata_write_i) begin
            multiplier_q[metadata_lane_i] <= metadata_multiplier_i;
            exponent_q[metadata_lane_i] <= metadata_exponent_i;
        end
        if (read_i) begin
            dot_o <= accumulator_q[read_lane_i];
            multiplier_o <= multiplier_q[read_lane_i];
            exponent_o <= exponent_q[read_lane_i];
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            op_valid_q <= 0; product_valid_q <= 0;
            op_first_q <= 0; op_last_q <= 0;
            product_first_q <= 0; product_last_q <= 0;
            valid_lanes_q <= 0; done_o <= 0; fault_o <= 0;
        end else if (kill_i || begin_i) begin
            op_valid_q <= 0; product_valid_q <= 0;
            op_first_q <= 0; op_last_q <= 0;
            product_first_q <= 0; product_last_q <= 0;
            done_o <= 0; fault_o <= 0;
            if (begin_i) valid_lanes_q <= valid_lanes_i;
        end else begin
            op_valid_q <= accept_i;
            product_valid_q <= op_valid_q;
            op_first_q <= first_i; op_last_q <= last_i;
            product_first_q <= op_first_q; product_last_q <= op_last_q;
            done_o <= product_valid_q && product_last_q;
            if ((accept_i && ((|bad_weight) || (activation_i == -16'sd32768))) ||
                (product_valid_q && (|overflow))) fault_o <= 1;
        end
    end
endmodule

// Exact private 27x18 product, with every non-multiply primitive feature tied
// off. Used only for the two fixed pieces of the row postscale operation.
module board1_projection_postscale_mul (
    input wire signed [26:0] a_i,
    input wire signed [17:0] b_i,
    output wire signed [47:0] product_o
);
`ifdef BOARD1_GW5_DSP
    MULTALU27X18 #(
        .AREG_CLK("BYPASS"), .BREG_CLK("BYPASS"), .DREG_CLK("BYPASS"),
        .C_IREG_CLK("BYPASS"), .PSEL_IREG_CLK("BYPASS"),
        .PADDSUB_IREG_CLK("BYPASS"), .ADDSUB0_IREG_CLK("BYPASS"),
        .ADDSUB1_IREG_CLK("BYPASS"), .CSEL_IREG_CLK("BYPASS"),
        .CASISEL_IREG_CLK("BYPASS"), .ACCSEL_IREG_CLK("BYPASS"),
        .PREG_CLK("BYPASS"), .ADDSUB0_PREG_CLK("BYPASS"),
        .ADDSUB1_PREG_CLK("BYPASS"), .CSEL_PREG_CLK("BYPASS"),
        .CASISEL_PREG_CLK("BYPASS"), .ACCSEL_PREG_CLK("BYPASS"),
        .C_PREG_CLK("BYPASS"), .OREG_CLK("BYPASS"),
        .FB_PREG_EN("FALSE"), .SOA_PREG_EN("FALSE"), .PRE_LOAD(48'd0),
        .DYN_P_SEL("FALSE"), .P_SEL(1'b0), .DYN_P_ADDSUB("FALSE"),
        .P_ADDSUB(1'b0), .DYN_A_SEL("FALSE"), .A_SEL(1'b0),
        .DYN_ADD_SUB_0("FALSE"), .ADD_SUB_0(1'b0),
        .DYN_ADD_SUB_1("FALSE"), .ADD_SUB_1(1'b0),
        .DYN_C_SEL("FALSE"), .C_SEL(1'b0), .DYN_CASI_SEL("FALSE"),
        .CASI_SEL(1'b0), .DYN_ACC_SEL("FALSE"), .ACC_SEL(1'b0),
        .MULT12X12_EN("FALSE")
    ) u_mul (
        .DOUT(product_o), .CASO(), .SOA(), .A(a_i), .B(b_i),
        .SIA(27'd0), .C(48'd0), .D(26'd0), .CASI(48'd0),
        .ACCSEL(1'b0), .PSEL(1'b0), .ASEL(1'b0), .PADDSUB(1'b0),
        .CSEL(1'b0), .CASISEL(1'b0), .ADDSUB(2'b00),
        .CLK(2'b00), .CE(2'b00), .RESET(2'b00));
`else
    assign product_o = a_i * b_i;
`endif
endmodule
`default_nettype wire
