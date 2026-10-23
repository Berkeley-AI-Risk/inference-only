`timescale 1ns/1ps
`default_nettype none
/* verilator lint_off DECLFILENAME */

// Private fixed-model arithmetic. The sqrt remains a frozen Board0 wrapper.
// RMSNorm division uses the exact bounded helper defined below.
module board1_fixed_rmsnorm_isqrt_u45_iterative (
    input  wire clk, input wire rst_n, input wire cancel_i,
    input  wire request_valid_i, output wire request_ready_o,
    input  wire [44:0] request_value_i,
    output wire response_valid_o, input wire response_ready_i,
    output wire [22:0] response_result_o, output wire response_fault_o
);
    board0_exact_isqrt_u45_iterative u_exact_board0_isqrt (
        .clk(clk), .rst_n(rst_n), .cancel_i(cancel_i),
        .request_valid_i(request_valid_i),
        .request_ready_o(request_ready_o),
        .request_value_i(request_value_i),
        .response_valid_o(response_valid_o),
        .response_ready_i(response_ready_i),
        .response_result_o(response_result_o),
        .response_fault_o(response_fault_o)
    );
endmodule

module board1_fixed_rmsnorm_rne_div_signed64_iterative (
    input  wire clk, input wire rst_n, input wire cancel_i,
    input  wire request_valid_i, output wire request_ready_o,
    input  wire signed [63:0] request_numerator_i,
    input  wire [63:0] request_denominator_i,
    output wire response_valid_o, input wire response_ready_i,
    output wire signed [63:0] response_result_o,
    output wire response_fault_o
);
    board1_rmsnorm_bounded28_divider u_exact_bounded_divider (
        .clk(clk), .rst_n(rst_n), .cancel_i(cancel_i),
        .request_valid_i(request_valid_i),
        .request_ready_o(request_ready_o),
        .request_numerator_i(request_numerator_i),
        .request_denominator_i(request_denominator_i),
        .response_valid_o(response_valid_o),
        .response_ready_i(response_ready_i),
        .response_result_o(response_result_o),
        .response_fault_o(response_fault_o)
    );
endmodule

/* verilator lint_on DECLFILENAME */

`default_nettype wire

`timescale 1ns/1ps
`default_nettype none

// Exact, single-client replacement for the combinational
// rne_div_signed64 helper used by the fixed model.  The magnitude quotient
// and remainder are formed with one restoring-division bit per clock; no
// synthesizable / or % operator is present.  A non-cancelled request always
// produces a held response exactly 28 clocks after its acceptance.
// PRIVATE caller bound: abs(numerator) < 2^28. RMSNorm supplies
// sign-extended int16 << 12, including -2^27. Not a general divider.
module board1_rmsnorm_bounded28_divider (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    cancel_i,

    input  wire                    request_valid_i,
    output logic                   request_ready_o,
    input  wire signed [63:0]      request_numerator_i,
    input  wire [63:0]             request_denominator_i,

    output logic                   response_valid_o,
    input  wire                    response_ready_i,
    output logic signed [63:0]     response_result_o,
    output logic                   response_fault_o
);
    logic                          busy_q;
    logic [5:0]                    iteration_q;
    logic                          negative_q;
    logic                          divide_by_zero_q;
    logic [63:0]                   divisor_q;
    logic [63:0]                   dividend_shift_q;
    logic [63:0]                   quotient_q;
    logic [64:0]                   remainder_q;

    logic [64:0]                   shifted_remainder;
    logic [64:0]                   reduced_remainder;
    logic [63:0]                   shifted_quotient;
    logic [63:0]                   rounded_magnitude;
    logic                          quotient_bit;
    logic                          round_up;

    // A response is deliberately retired before another request is admitted.
    // This makes the one-outstanding-request ownership unambiguous and costs
    // only one idle clock between independent operations.
    always_comb begin
        request_ready_o = rst_n && !cancel_i && !busy_q && !response_valid_o;

        shifted_remainder = {remainder_q[63:0], dividend_shift_q[63]};
        if (shifted_remainder >= {1'b0, divisor_q}) begin
            reduced_remainder = shifted_remainder - {1'b0, divisor_q};
            quotient_bit = 1'b1;
        end else begin
            reduced_remainder = shifted_remainder;
            quotient_bit = 1'b0;
        end
        shifted_quotient = {quotient_q[62:0], quotient_bit};

        // reduced_remainder is the final mathematical remainder during the
        // last iteration.  The 65-bit comparison cannot overflow at 2*r.
        round_up = ({reduced_remainder[63:0], 1'b0} >
                    {1'b0, divisor_q}) ||
                   (({reduced_remainder[63:0], 1'b0} ==
                     {1'b0, divisor_q}) && shifted_quotient[0]);
        rounded_magnitude = shifted_quotient +
                            {{63{1'b0}}, round_up};
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
                iteration_q <= 6'd36;
                negative_q <= request_numerator_i[63];
                divide_by_zero_q <= (request_denominator_i == 64'd0);
                divisor_q <= request_denominator_i;
                // Unary negation intentionally occurs at 64-bit width.  Its
                // bit pattern is also the correct magnitude for INT64_MIN.
                dividend_shift_q <= (request_numerator_i[63]
                    ? $unsigned(-request_numerator_i)
                    : $unsigned(request_numerator_i)) << 36;
                quotient_q <= 64'd0;
                remainder_q <= 65'd0;
                response_result_o <= 64'sd0;
                response_fault_o <= 1'b0;
            end else if (busy_q) begin
                dividend_shift_q <= {dividend_shift_q[62:0], 1'b0};
                quotient_q <= shifted_quotient;
                remainder_q <= reduced_remainder;

                if (iteration_q == 6'd63) begin
                    busy_q <= 1'b0;
                    response_valid_o <= 1'b1;
                    if (divide_by_zero_q) begin
                        // Preserve the legacy result while making the invalid
                        // divisor explicit to its fixed-model caller.
                        response_result_o <= 64'sd0;
                        response_fault_o <= 1'b1;
                    end else begin
                        response_result_o <= negative_q
                            ? $signed(~rounded_magnitude + 64'd1)
                            : $signed(rounded_magnitude);
                        response_fault_o <= 1'b0;
                    end
                end else begin
                    iteration_q <= iteration_q + 6'd1;
                end
            end
        end
    end
endmodule

`default_nettype wire
