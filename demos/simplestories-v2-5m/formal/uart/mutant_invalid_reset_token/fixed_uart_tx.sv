`timescale 1ns/1ps
`default_nettype none

module fixed_uart_tx #(
    parameter integer CLKS_PER_BIT = 234
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       byte_valid_i,
    output wire       byte_ready_o,
    input  wire [7:0] byte_i,
    output wire       serial_o
);
    localparam integer COUNTER_BITS = $clog2(CLKS_PER_BIT + 1);
    logic [COUNTER_BITS-1:0] counter_q;
    logic [3:0] bit_q;
    logic [9:0] shift_q;
    logic busy_q;

    initial begin
        if (CLKS_PER_BIT < 4)
            $fatal(1, "CLKS_PER_BIT must be at least four");
    end

    assign byte_ready_o = !busy_q;
    assign serial_o = busy_q ? shift_q[0] : 1'b1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter_q <= '0;
            bit_q <= '0;
            shift_q <= 10'h3ff;
            busy_q <= 1'b0;
        end else if (!busy_q) begin
            if (byte_valid_i) begin
                shift_q <= {1'b1, byte_i, 1'b0};
                counter_q <= COUNTER_BITS'(CLKS_PER_BIT - 1);
                bit_q <= 4'b0;
                busy_q <= 1'b1;
            end
        end else if (counter_q != 0) begin
            counter_q <= counter_q - 1'b1;
        end else if (bit_q == 4'd9) begin
            busy_q <= 1'b0;
        end else begin
            shift_q <= {1'b1, shift_q[9:1]};
            counter_q <= COUNTER_BITS'(CLKS_PER_BIT - 1);
            bit_q <= bit_q + 1'b1;
        end
    end
endmodule

`default_nettype wire
