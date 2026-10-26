`timescale 1ns/1ps
`default_nettype none

// Exact, single-client replacement for isqrt_u45.  This is the same 23-step
// binary digit-by-digit algorithm as the legacy function, spatially folded so
// one root bit is produced per clock.  A non-cancelled request always produces
// a held response exactly 23 clocks after its acceptance.
module board0_exact_isqrt_u45_iterative (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    cancel_i,

    input  wire                    request_valid_i,
    output logic                   request_ready_o,
    input  wire [44:0]             request_value_i,

    output logic                   response_valid_o,
    input  wire                    response_ready_i,
    output logic [22:0]            response_result_o,
    output logic                   response_fault_o
);
    logic                          busy_q;
    logic [4:0]                    iteration_q;
    logic [45:0]                   radicand_shift_q;
    logic [46:0]                   remainder_q;
    logic [22:0]                   root_q;

    logic [46:0]                   shifted_remainder;
    logic [46:0]                   trial;
    logic [46:0]                   reduced_remainder;
    logic [22:0]                   shifted_root;
    logic                          root_bit;

    always_comb begin
        request_ready_o = rst_n && !cancel_i && !busy_q && !response_valid_o;

        shifted_remainder = (remainder_q << 2) |
                            {{45{1'b0}}, radicand_shift_q[45:44]};
        trial = ({24'd0, root_q} << 2) | 47'd1;
        if (shifted_remainder >= trial) begin
            reduced_remainder = shifted_remainder - trial;
            root_bit = 1'b1;
        end else begin
            reduced_remainder = shifted_remainder;
            root_bit = 1'b0;
        end
        shifted_root = {root_q[21:0], root_bit};
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy_q <= 1'b0;
            iteration_q <= 5'd0;
            radicand_shift_q <= 46'd0;
            remainder_q <= 47'd0;
            root_q <= 23'd0;
            response_valid_o <= 1'b0;
            response_result_o <= 23'd0;
            response_fault_o <= 1'b0;
        end else if (cancel_i) begin
            busy_q <= 1'b0;
            iteration_q <= 5'd0;
            radicand_shift_q <= 46'd0;
            remainder_q <= 47'd0;
            root_q <= 23'd0;
            response_valid_o <= 1'b0;
            response_result_o <= 23'd0;
            response_fault_o <= 1'b0;
        end else begin
            if (response_valid_o && response_ready_i) begin
                response_valid_o <= 1'b0;
                response_result_o <= 23'd0;
                response_fault_o <= 1'b0;
            end

            if (request_valid_i && request_ready_o) begin
                busy_q <= 1'b1;
                iteration_q <= 5'd0;
                // The leading zero makes the 45-bit radicand into exactly 23
                // two-bit groups, matching {2'b00,value} in the old function.
                radicand_shift_q <= {1'b0, request_value_i};
                remainder_q <= 47'd0;
                root_q <= 23'd0;
                response_result_o <= 23'd0;
                response_fault_o <= 1'b0;
            end else if (busy_q) begin
                radicand_shift_q <= {radicand_shift_q[43:0], 2'b00};
                remainder_q <= reduced_remainder;
                root_q <= shifted_root;

                if (iteration_q == 5'd22) begin
                    busy_q <= 1'b0;
                    response_valid_o <= 1'b1;
                    response_result_o <= shifted_root;
                    response_fault_o <= 1'b0;
                end else begin
                    iteration_q <= iteration_q + 5'd1;
                end
            end
        end
    end
endmodule

`default_nettype wire
