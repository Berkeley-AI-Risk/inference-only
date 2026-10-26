`timescale 1ns/1ps
`default_nettype none

// Private, cancelable, round-to-nearest-even signed/unsigned divider.
// PRIVATE caller bound: abs(numerator) < 2^46. Probability operands
// are zero-extended 46-bit values; value operands are signed 38-bit.
// The first 18 zero iterations are omitted. An exact zero-quotient-prefix
// shortcut skips another 30 bits when that prefix is smaller than the
// denominator. Both paths retain the original low46 magnitude behavior.
// Two bits retire per clock. There is deliberately
// only one request in flight and no synthesizable division or remainder
// operator in this implementation.
module board1_fixed_attention_rne_div_signed64 (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    cancel_i,
    input  wire                    request_valid_i,
    output logic                   request_ready_o,
    input  wire signed [63:0]      request_numerator_i,
    input  wire        [63:0]      request_denominator_i,
    output logic                   response_valid_o,
    input  wire                    response_ready_i,
    output logic signed [63:0]     response_result_o,
    output logic                   response_fault_o
);
    wire [63:0] request_magnitude = request_numerator_i[63]
        ? $unsigned(-request_numerator_i) : $unsigned(request_numerator_i);
    wire [29:0] request_prefix = request_magnitude[45:16];
    wire prefix_is_zero_quotient = {34'd0, request_prefix} < request_denominator_i;

    logic busy_q;
    logic [5:0] iteration_q;
    logic negative_q;
    logic divide_by_zero_q;
    logic [63:0] divisor_q;
    logic [63:0] dividend_shift_q;
    logic [63:0] quotient_q;
    logic [64:0] remainder_q;

    logic [64:0] shifted_remainder;
    logic [64:0] reduced_remainder;
    logic [63:0] shifted_quotient;
    logic [63:0] rounded_magnitude;
    logic [64:0] first_shifted_remainder, first_reduced_remainder;
    logic [63:0] first_shifted_quotient;
    logic first_quotient_bit;
    logic quotient_bit;
    logic round_up;

    always_comb begin
        request_ready_o = rst_n && !cancel_i && !busy_q &&
                          !response_valid_o;
        first_shifted_remainder = {remainder_q[63:0], dividend_shift_q[63]};
        if (first_shifted_remainder >= {1'b0, divisor_q}) begin
            first_reduced_remainder = first_shifted_remainder - {1'b0, divisor_q};
            first_quotient_bit = 1'b1;
        end else begin
            first_reduced_remainder = first_shifted_remainder;
            first_quotient_bit = 1'b0;
        end
        first_shifted_quotient = {quotient_q[62:0], first_quotient_bit};
        shifted_remainder = {first_reduced_remainder[63:0], dividend_shift_q[62]};
        if (shifted_remainder >= {1'b0, divisor_q}) begin
            reduced_remainder = shifted_remainder - {1'b0, divisor_q};
            quotient_bit = 1'b1;
        end else begin
            reduced_remainder = shifted_remainder;
            quotient_bit = 1'b0;
        end
        shifted_quotient = {first_shifted_quotient[62:0], quotient_bit};
        round_up = ({reduced_remainder[63:0], 1'b0} >
                    {1'b0, divisor_q}) ||
                   (({reduced_remainder[63:0], 1'b0} ==
                     {1'b0, divisor_q}) && shifted_quotient[0]);
        rounded_magnitude = shifted_quotient + {{63{1'b0}}, round_up};
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy_q <= 1'b0;
            iteration_q <= 6'd0;
            negative_q <= 1'b0;
            divide_by_zero_q <= 1'b0;
            divisor_q <= 64'd0;
            dividend_shift_q <= 64'd0;
            quotient_q <= 64'd0;
            remainder_q <= 65'd0;
            response_valid_o <= 1'b0;
            response_result_o <= 64'sd0;
            response_fault_o <= 1'b0;
        end else if (cancel_i) begin
            busy_q <= 1'b0;
            iteration_q <= 6'd0;
            negative_q <= 1'b0;
            divide_by_zero_q <= 1'b0;
            divisor_q <= 64'd0;
            dividend_shift_q <= 64'd0;
            quotient_q <= 64'd0;
            remainder_q <= 65'd0;
            response_valid_o <= 1'b0;
            response_result_o <= 64'sd0;
            response_fault_o <= 1'b0;
        end else begin
            if (response_valid_o && response_ready_i) begin
                response_valid_o <= 1'b0;
                response_result_o <= 64'sd0;
                response_fault_o <= 1'b0;
            end
            if (request_valid_i && request_ready_o) begin
                busy_q <= 1'b1;
                iteration_q <= prefix_is_zero_quotient ? 6'd48 : 6'd18;
                negative_q <= request_numerator_i[63];
                divide_by_zero_q <= (request_denominator_i == 64'd0);
                divisor_q <= request_denominator_i;
                dividend_shift_q <= prefix_is_zero_quotient
                    ? (request_magnitude << 48) : (request_magnitude << 18);
                quotient_q <= 64'd0;
                remainder_q <= prefix_is_zero_quotient
                    ? {35'd0, request_prefix} : 65'd0;
                response_result_o <= 64'sd0;
                response_fault_o <= 1'b0;
            end else if (busy_q) begin
                dividend_shift_q <= {dividend_shift_q[61:0], 2'b0};
                quotient_q <= shifted_quotient;
                remainder_q <= reduced_remainder;
                if (iteration_q == 6'd62) begin
                    busy_q <= 1'b0;
                    response_valid_o <= 1'b1;
                    if (divide_by_zero_q) begin
                        response_result_o <= 64'sd0;
                        response_fault_o <= 1'b1;
                    end else begin
                        response_result_o <= negative_q
                            ? $signed(~rounded_magnitude + 64'd1)
                            : $signed(rounded_magnitude);
                        response_fault_o <= 1'b0;
                    end
                end else begin
                    iteration_q <= iteration_q + 6'd2;
                end
            end
        end
    end
endmodule

`default_nettype wire
