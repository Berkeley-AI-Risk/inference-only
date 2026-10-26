`timescale 1ns/1ps
`default_nettype none

module fixed_uart_rx #(
    parameter integer CLKS_PER_BIT = 234
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       serial_i,
    output logic      byte_valid_o,
    output logic [7:0] byte_o
);
    localparam integer HALF_BIT = CLKS_PER_BIT / 2;
    localparam integer COUNTER_BITS = $clog2(CLKS_PER_BIT + 1);

    typedef enum logic [1:0] {RX_IDLE, RX_START, RX_DATA, RX_STOP} rx_state_t;
    rx_state_t state_q;
    logic [COUNTER_BITS-1:0] counter_q;
    logic [2:0] bit_q;
    logic [7:0] shift_q;
    (* async_reg = "true", syn_preserve = 1 *) logic serial_meta_q;
    (* async_reg = "true", syn_preserve = 1 *) logic serial_sync_q;

    initial begin
        if (CLKS_PER_BIT < 4)
            $fatal(1, "CLKS_PER_BIT must be at least four");
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= RX_IDLE;
            counter_q <= '0;
            bit_q <= '0;
            shift_q <= '0;
            byte_o <= '0;
            byte_valid_o <= 1'b0;
            serial_meta_q <= 1'b1;
            serial_sync_q <= 1'b1;
        end else begin
            serial_meta_q <= serial_i;
            serial_sync_q <= serial_meta_q;
            byte_valid_o <= 1'b0;
            case (state_q)
                RX_IDLE: begin
                    if (!serial_sync_q) begin
                        counter_q <= COUNTER_BITS'(HALF_BIT - 1);
                        state_q <= RX_START;
                    end
                end
                RX_START: begin
                    if (counter_q != 0) begin
                        counter_q <= counter_q - 1'b1;
                    end else if (!serial_sync_q) begin
                        counter_q <= COUNTER_BITS'(CLKS_PER_BIT - 1);
                        bit_q <= 3'b0;
                        state_q <= RX_DATA;
                    end else begin
                        state_q <= RX_IDLE;
                    end
                end
                RX_DATA: begin
                    if (counter_q != 0) begin
                        counter_q <= counter_q - 1'b1;
                    end else begin
                        shift_q[bit_q] <= serial_sync_q;
                        counter_q <= COUNTER_BITS'(CLKS_PER_BIT - 1);
                        if (bit_q == 3'd7)
                            state_q <= RX_STOP;
                        else
                            bit_q <= bit_q + 1'b1;
                    end
                end
                RX_STOP: begin
                    if (counter_q != 0) begin
                        counter_q <= counter_q - 1'b1;
                    end else begin
                        if (serial_sync_q) begin
                            byte_o <= shift_q;
                            byte_valid_o <= 1'b1;
                        end
                        state_q <= RX_IDLE;
                    end
                end
                default: state_q <= RX_IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire
