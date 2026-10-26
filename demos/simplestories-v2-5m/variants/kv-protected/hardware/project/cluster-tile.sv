`timescale 1ns/1ps
`default_nettype none

// PRIVATE fixed-model tile: one multiplier serves sixteen fixed rows.
// Accept beats at least sixteen clocks apart. Capture each whole weight word;
// unaccepted inputs cannot replace its remaining slices. Drain fifteen extra
// tail clocks before row emission. No public arithmetic or memory interface.
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
    logic slice_busy_q, beat_first_q, beat_last_q;
    logic [3:0] slice_q, op_group_q, product_group_q;
    logic op_valid_q, product_valid_q;
    logic op_first_q, op_last_q, product_first_q, product_last_q;
    logic [4:0] valid_lanes_q;
    logic [149:0] weight_tail_q;
    logic signed [15:0] activation_q;
    logic signed [9:0] weight_q [0:0];
    logic signed [25:0] product_q [0:0];
    logic [15:0] multiplier_q [0:15];
    logic signed [7:0] exponent_q [0:15];
    wire [15:0] bad_weight;
    wire [0:0] overflow;
    wire signed [34:0] read_dot [0:0];
    wire issue = (accept_i || slice_busy_q) && !kill_i && !begin_i;
    // Accumulation and row emission are disjoint in the private engine.
    // Sixteen accumulator contexts share one physical memory bank.
    wire [3:0] accumulator_address = read_i ? read_lane_i : product_group_q;

    genvar row, lane;
    generate for (row=0; row<16; row=row+1) begin : g_validate
        assign bad_weight[row] = (weights_i[row*10 +: 10] == 10'h200) ||
            ((row >= valid_lanes_q) && (weights_i[row*10 +: 10] != 10'd0));
    end endgenerate
    generate for (lane=0; lane<1; lane=lane+1) begin : g_lane
        logic signed [34:0] accumulator_q [0:15];
        wire signed [25:0] product;
        wire signed [34:0] previous_sum = accumulator_q[accumulator_address];
        wire signed [35:0] next_sum = product_first_q ?
            {{10{product_q[lane][25]}}, product_q[lane]} :
            $signed({previous_sum[34], previous_sum}) +
            $signed({{10{product_q[lane][25]}}, product_q[lane]});
        board1_w10_a16_mul_exact u_mul (
            .activation_i(activation_q), .weight_i(weight_q[lane]), .product_o(product));
        assign read_dot[lane] = previous_sum;
        assign overflow[lane] = next_sum[35] != next_sum[34];
        always_ff @(posedge clk) begin
            if (issue) weight_q[lane] <= accept_i ? weights_i[lane*10 +: 10] :
                                                    weight_tail_q[lane*10 +: 10];
            if (op_valid_q) product_q[lane] <= product;
            if (product_valid_q && !kill_i && !begin_i && !read_i)
                accumulator_q[product_group_q] <= next_sum[34:0];
        end
    end endgenerate

    // First overwrites every context. Reset/kill/begin revoke all valid tags.
    always_ff @(posedge clk) begin
        if (accept_i) begin
            activation_q <= activation_i;
            weight_tail_q <= weights_i[159:10];
        end else if (slice_busy_q) weight_tail_q <= {10'd0, weight_tail_q[149:10]};
        if (metadata_write_i) begin
            multiplier_q[metadata_lane_i] <= metadata_multiplier_i;
            exponent_q[metadata_lane_i] <= metadata_exponent_i;
        end
        if (read_i) begin
            dot_o <= read_dot[0];
            multiplier_o <= multiplier_q[read_lane_i];
            exponent_o <= exponent_q[read_lane_i];
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            slice_busy_q <= 0; slice_q <= 0;
            beat_first_q <= 0; beat_last_q <= 0;
            op_valid_q <= 0; product_valid_q <= 0;
            op_group_q <= 0; product_group_q <= 0;
            op_first_q <= 0; op_last_q <= 0;
            product_first_q <= 0; product_last_q <= 0;
            valid_lanes_q <= 0; done_o <= 0; fault_o <= 0;
        end else if (kill_i || begin_i) begin
            slice_busy_q <= 0; slice_q <= 0;
            beat_first_q <= 0; beat_last_q <= 0;
            op_valid_q <= 0; product_valid_q <= 0;
            op_group_q <= 0; product_group_q <= 0;
            op_first_q <= 0; op_last_q <= 0;
            product_first_q <= 0; product_last_q <= 0;
            done_o <= 0; fault_o <= 0;
            if (begin_i) valid_lanes_q <= valid_lanes_i;
        end else begin
            if (accept_i) begin
                slice_busy_q <= 1; slice_q <= 1;
                beat_first_q <= first_i; beat_last_q <= last_i;
            end else if (slice_busy_q) begin
                if (slice_q == 15) slice_busy_q <= 0;
                else slice_q <= slice_q+4'd1;
            end
            op_valid_q <= issue;
            product_valid_q <= op_valid_q;
            if (issue) begin
                op_group_q <= accept_i ? 4'd0 : slice_q;
                op_first_q <= accept_i ? first_i : beat_first_q;
                op_last_q <= accept_i ? last_i : beat_last_q;
            end
            product_group_q <= op_group_q;
            product_first_q <= op_first_q;
            product_last_q <= op_last_q;
            done_o <= product_valid_q && product_last_q && product_group_q == 15;
            if ((accept_i && ((|bad_weight) || activation_i == -16'sd32768 || slice_busy_q)) ||
                (read_i && (slice_busy_q || op_valid_q || product_valid_q)) ||
                (product_valid_q && (|overflow))) fault_o <= 1;
        end
    end
endmodule
`default_nettype wire

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
