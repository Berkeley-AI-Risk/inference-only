`timescale 1ns/1ps
`default_nettype none
// Exclusive ownership of the physical UART for one home-authorization turn.
// Outbound: A6 followed by the canonical 128-byte request. Inbound: the exact
// 1420-byte grant. Signature verification supplies frame integrity.
module home_uart_transport #(
    parameter integer CLKS_PER_BIT=217
)(
    input wire clk, reset_n, enabled_i, uart_rx_i,
    output wire uart_tx_o,
    input wire request_valid_i, request_last_i,
    input wire [7:0] request_byte_i,
    output wire request_ready_o,
    output wire grant_valid_o, grant_last_o,
    output wire [7:0] grant_byte_o,
    input wire grant_ready_i,
    output wire fault_o
);
    localparam [2:0] PREFIX=0,REQUEST=1,DRAIN=2,DONE=3;
    logic [2:0] state_q;
    logic [10:0] grant_count_q;
    logic fault_q;
    wire local_reset_n=reset_n && enabled_i;
    wire tx_ready,rx_valid;
    wire [7:0] rx_byte;
    wire tx_valid=!fault_q && (state_q==PREFIX || (state_q==REQUEST && request_valid_i));
    wire [7:0] tx_byte=state_q==PREFIX ? 8'ha6 : request_byte_i;
    fixed_uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx(
        .clk(clk),.rst_n(local_reset_n),.byte_valid_i(tx_valid),
        .byte_ready_o(tx_ready),.byte_i(tx_byte),.serial_o(uart_tx_o));
    fixed_uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx(
        .clk(clk),.rst_n(local_reset_n),.serial_i(uart_rx_i),
        .byte_valid_o(rx_valid),.byte_o(rx_byte));
    assign request_ready_o=enabled_i && !fault_q && state_q==REQUEST && tx_ready;
    assign grant_valid_o=enabled_i && !fault_q && state_q==DONE && grant_count_q<1420 && rx_valid;
    assign grant_byte_o=rx_byte;
    assign grant_last_o=grant_count_q==1419;
    assign fault_o=fault_q;
    always_ff @(posedge clk or negedge local_reset_n) begin
        if(!local_reset_n) begin state_q<=PREFIX;grant_count_q<=0;fault_q<=0;end
        else begin
            case(state_q)
                PREFIX: if(tx_ready) state_q<=REQUEST;
                REQUEST: if(request_valid_i && tx_ready && request_last_i) state_q<=DRAIN;
                DRAIN: if(tx_ready) state_q<=DONE;
                DONE: begin end
                default: fault_q<=1;
            endcase
            if(rx_valid) begin
                if(state_q!=DONE || grant_count_q>=1420 || !grant_ready_i) fault_q<=1;
                else grant_count_q<=grant_count_q+1'b1;
            end
        end
    end
endmodule
`default_nettype wire
