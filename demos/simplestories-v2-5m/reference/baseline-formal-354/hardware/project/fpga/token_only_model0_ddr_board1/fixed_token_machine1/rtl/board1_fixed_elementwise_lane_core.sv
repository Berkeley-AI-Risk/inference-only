`timescale 1ns/1ps
`default_nettype none

// Exact-name compatibility seam for the frozen six-layer datapath.
// The wrapper adds no state, arithmetic, operation, or externally visible
// port; it selects the separately verified product-specialized successor.
module board1_fixed_elementwise_lane_core (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    clear_i,
    input  wire                    request_valid_i,
    output wire                    request_ready_o,
    input  wire [2:0]              operation_i,
    input  wire signed [15:0]      first_i,
    input  wire signed [15:0]      second_i,
    input  wire signed [9:0]       coefficient_i,
    input  wire [15:0]             multiplier_i,
    input  wire signed [15:0]      cosine_i,
    input  wire signed [15:0]      sine_i,
    input  wire signed [7:0]       first_exponent_i,
    input  wire signed [7:0]       second_exponent_i,
    input  wire signed [7:0]       common_exponent_i,
    input  wire signed [7:0]       target_exponent_i,

    output wire                    lut_request_o,
    output wire [15:0]             lut_index_o,
    input  wire                    lut_response_valid_i,
    input  wire signed [15:0]      lut_value_i,
    input  wire                    lut_fault_i,

    output wire                    result_valid_o,
    input  wire                    result_ready_i,
    output wire signed [15:0]      result0_o,
    output wire signed [15:0]      result1_o,
    output wire signed [15:0]      auxiliary_o,
    output wire signed [49:0]      raw0_o,
    output wire signed [49:0]      raw1_o,
    output wire signed [7:0]       source_exponent_o,
    output wire                    range_fault_o
);
    board1_fixed_elementwise_product_compact_lane
        u_fixed_elementwise_product_compact_lane (
        .clk(clk),
        .rst_n(rst_n),
        .clear_i(clear_i),
        .request_valid_i(request_valid_i),
        .request_ready_o(request_ready_o),
        .operation_i(operation_i),
        .first_i(first_i),
        .second_i(second_i),
        .coefficient_i(coefficient_i),
        .multiplier_i(multiplier_i),
        .cosine_i(cosine_i),
        .sine_i(sine_i),
        .first_exponent_i(first_exponent_i),
        .second_exponent_i(second_exponent_i),
        .common_exponent_i(common_exponent_i),
        .target_exponent_i(target_exponent_i),
        .lut_request_o(lut_request_o),
        .lut_index_o(lut_index_o),
        .lut_response_valid_i(lut_response_valid_i),
        .lut_value_i(lut_value_i),
        .lut_fault_i(lut_fault_i),
        .result_valid_o(result_valid_o),
        .result_ready_i(result_ready_i),
        .result0_o(result0_o),
        .result1_o(result1_o),
        .auxiliary_o(auxiliary_o),
        .raw0_o(raw0_o),
        .raw1_o(raw1_o),
        .source_exponent_o(source_exponent_o),
        .range_fault_o(range_fault_o)
    );
endmodule

`default_nettype wire
