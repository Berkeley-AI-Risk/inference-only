`timescale 1ns/1ps
`default_nettype none

// One-bit-per-cycle signed 64-bit shift with the oracle's exact RNE rule.
// Negative shift counts mean left shift.  Counts below -62 fault and counts
// above 62 produce zero, matching the fixed-attention oracle helper.  A left
// result which cannot be represented in signed 64 bits also faults instead of
// silently wrapping; all legal attention-engine requests are proven to remain
// in range.  Only one private request can be in flight and CLEAR cancels it
// deterministically.
module board1_fixed_attention_rne_shift_iterative (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    clear_i,
    input  wire                    request_valid_i,
    output logic                   request_ready_o,
    input  wire signed [63:0]      request_value_i,
    input  wire signed [8:0]       request_shift_i,
    output logic                   response_valid_o,
    input  wire                    response_ready_i,
    output logic signed [63:0]     response_result_o,
    output logic                   response_fault_o
);
    logic busy_q;
    logic left_q;
    logic negative_q;
    logic [5:0] remaining_q;
    logic [63:0] work_q;
    logic sticky_q;

    wire [63:0] right_quotient_next = {1'b0, work_q[63:1]};
    wire right_round_up = work_q[0] &&
                          (sticky_q || right_quotient_next[0]);
    wire [63:0] right_rounded_next = right_quotient_next +
                                     {{63{1'b0}}, right_round_up};
    wire left_overflow_next = work_q[63] != work_q[62];

    always_comb begin
        request_ready_o = rst_n && !clear_i && !busy_q &&
                          !response_valid_o;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy_q <= 1'b0;
            left_q <= 1'b0;
            negative_q <= 1'b0;
            remaining_q <= 6'd0;
            work_q <= 64'd0;
            sticky_q <= 1'b0;
            response_valid_o <= 1'b0;
            response_result_o <= 64'sd0;
            response_fault_o <= 1'b0;
        end else if (clear_i) begin
            busy_q <= 1'b0;
            left_q <= 1'b0;
            negative_q <= 1'b0;
            remaining_q <= 6'd0;
            work_q <= 64'd0;
            sticky_q <= 1'b0;
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
                response_result_o <= 64'sd0;
                response_fault_o <= 1'b0;
                sticky_q <= 1'b0;
                negative_q <= request_value_i[63];
                if (request_shift_i == 0) begin
                    busy_q <= 1'b0;
                    response_valid_o <= 1'b1;
                    response_result_o <= request_value_i;
                end else if (request_shift_i < -9'sd62) begin
                    busy_q <= 1'b0;
                    response_valid_o <= 1'b1;
                    response_result_o <= 64'sd0;
                    response_fault_o <= 1'b1;
                end else if (request_shift_i > 9'sd62) begin
                    busy_q <= 1'b0;
                    response_valid_o <= 1'b1;
                    response_result_o <= 64'sd0;
                end else begin
                    busy_q <= 1'b1;
                    left_q <= request_shift_i < 0;
                    remaining_q <= (request_shift_i < 0)
                        ? $unsigned(-request_shift_i)
                        : $unsigned(request_shift_i);
                    work_q <= (request_shift_i < 0)
                        ? $unsigned(request_value_i)
                        : (request_value_i[63]
                            ? $unsigned(-request_value_i)
                            : $unsigned(request_value_i));
                end
            end else if (busy_q) begin
                if (work_q == 0) begin
                    busy_q <= 1'b0;
                    response_valid_o <= 1'b1;
                    response_result_o <= 64'sd0;
                end else if (left_q) begin
                    if (left_overflow_next) begin
                        busy_q <= 1'b0;
                        response_valid_o <= 1'b1;
                        response_result_o <= 64'sd0;
                        response_fault_o <= 1'b1;
                    end else if (remaining_q == 6'd1) begin
                        busy_q <= 1'b0;
                        response_valid_o <= 1'b1;
                        response_result_o <= $signed(work_q << 1);
                    end else begin
                        work_q <= work_q << 1;
                        remaining_q <= remaining_q - 1'b1;
                    end
                end else if (remaining_q == 6'd1) begin
                    busy_q <= 1'b0;
                    response_valid_o <= 1'b1;
                    response_result_o <= negative_q
                        ? $signed(~right_rounded_next + 64'd1)
                        : $signed(right_rounded_next);
                end else begin
                    work_q <= right_quotient_next;
                    sticky_q <= sticky_q || work_q[0];
                    remaining_q <= remaining_q - 1'b1;
                end
            end
        end
    end
endmodule

`default_nettype wire
