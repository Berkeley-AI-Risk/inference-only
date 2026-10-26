`timescale 1ns/1ps
`default_nettype none

// One private arithmetic lane implementing the BFP-v5 signed RNE shift.
// Negative shift counts mean a checked left shift.  Positive counts mean a
// magnitude right shift followed by round-to-nearest, ties-to-even.  The
// request and response are both held under backpressure and CLEAR cancels an
// in-flight operation without leaving a stale response.
module board1_fixed_vector_rne_shift_iterative (
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
    wire [5:0] request_shift_magnitude = request_shift_i[8]
        ? (~request_shift_i[5:0] + 1'b1) : request_shift_i[5:0];

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
                    remaining_q <= request_shift_magnitude;
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
                        ? -$signed(right_rounded_next)
                        : $signed(right_rounded_next);
                end else begin
                    work_q <= right_quotient_next;
                    sticky_q <= sticky_q || work_q[0];
                    remaining_q <= remaining_q - 1'b1;
                end
            end
        end
    end

`ifdef FORMAL
    always_ff @(posedge clk) begin
        if (rst_n && !$past(clear_i) && $past(response_valid_o) &&
            !$past(response_ready_i)) begin
            assert(response_valid_o);
            assert(response_result_o == $past(response_result_o));
            assert(response_fault_o == $past(response_fault_o));
        end
        if (rst_n && clear_i) begin
            assert(!response_valid_o);
        end
        assert(!(busy_q && response_valid_o));
    end
`endif
endmodule

`default_nettype wire
