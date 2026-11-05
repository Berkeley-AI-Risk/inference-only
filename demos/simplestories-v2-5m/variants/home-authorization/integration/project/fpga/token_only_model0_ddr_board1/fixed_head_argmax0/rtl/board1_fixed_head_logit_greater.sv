`timescale 1ns/1ps
`default_nettype none

// Fixed-model comparison, not a general exponent/shift service. The unchanged
// parent accepts only row-zero's exponent and its two predecessors, making
// every live comparison's exponent difference one of -2,-1,0,1,2. Compute all
// five wiring-only alignments in parallel; exponent decoding selects a bit,
// rather than driving a variable shifter followed by a long wide comparison.
module board1_fixed_head_logit_greater (
    input  wire signed [49:0] left_value_i,
    input  wire signed [7:0]  left_exponent_i,
    input  wire signed [49:0] right_value_i,
    input  wire signed [7:0]  right_exponent_i,
    output logic              greater_o
);
    wire signed [51:0] left_wide = {{2{left_value_i[49]}}, left_value_i};
    wire signed [51:0] right_wide = {{2{right_value_i[49]}}, right_value_i};
    wire signed [51:0] left_one = {left_value_i[49], left_value_i, 1'b0};
    wire signed [51:0] right_one = {right_value_i[49], right_value_i, 1'b0};
    wire signed [51:0] left_two = {left_value_i, 2'b00};
    wire signed [51:0] right_two = {right_value_i, 2'b00};
    wire signed [8:0] exponent_delta =
        $signed({left_exponent_i[7], left_exponent_i}) -
        $signed({right_exponent_i[7], right_exponent_i});
    wire [4:0] comparison;

    board1_fixed_head_compare52_tree u_right_two (
        .left_i(left_wide), .right_i(right_two), .greater_o(comparison[0]));
    board1_fixed_head_compare52_tree u_right_one (
        .left_i(left_wide), .right_i(right_one), .greater_o(comparison[1]));
    board1_fixed_head_compare52_tree u_equal (
        .left_i(left_wide), .right_i(right_wide), .greater_o(comparison[2]));
    board1_fixed_head_compare52_tree u_left_one (
        .left_i(left_one), .right_i(right_wide), .greater_o(comparison[3]));
    board1_fixed_head_compare52_tree u_left_two (
        .left_i(left_two), .right_i(right_wide), .greater_o(comparison[4]));

    always @* begin
        case (exponent_delta)
            -9'sd2: greater_o = comparison[0];
            -9'sd1: greater_o = comparison[1];
             9'sd0: greater_o = comparison[2];
             9'sd1: greater_o = comparison[3];
             9'sd2: greater_o = comparison[4];
            // Not a substitute for validation: the unchanged parent rejects
            // illegal row metadata before this result may update the winner.
            default: greater_o = 1'b0;
        endcase
    end
endmodule

// Signed 52-bit comparison: sign-bit inversion gives unsigned order. Compare
// four-bit leaves, then combine high/low ranges in a balanced four-level tree.
// Strict greater preserves the lowest-token-ID rule on equal logits.
module board1_fixed_head_compare52_tree (
    input  wire signed [51:0] left_i,
    input  wire signed [51:0] right_i,
    output wire greater_o
);
    wire [63:0] left_ordered = {12'd0, ~left_i[51], left_i[50:0]};
    wire [63:0] right_ordered = {12'd0, ~right_i[51], right_i[50:0]};
    wire [30:0] equal_node;
    wire [30:0] greater_node;
    genvar leaf, node;
    generate
        for (leaf = 0; leaf < 16; leaf = leaf + 1) begin : g_leaf
            assign equal_node[15 + leaf] =
                left_ordered[leaf*4 +: 4] == right_ordered[leaf*4 +: 4];
            assign greater_node[15 + leaf] =
                left_ordered[leaf*4 +: 4] > right_ordered[leaf*4 +: 4];
        end
        for (node = 0; node < 15; node = node + 1) begin : g_node
            assign equal_node[node] = equal_node[2*node + 2] && equal_node[2*node + 1];
            assign greater_node[node] = greater_node[2*node + 2] ||
                (equal_node[2*node + 2] && greater_node[2*node + 1]);
        end
    endgenerate
    assign greater_o = greater_node[0];
endmodule

`default_nettype wire
