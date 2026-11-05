`timescale 1ns/1ps
`default_nettype none

// Two-entry private request FIFO.  Besides absorbing short controller stalls,
// it deliberately breaks the combinational ready path between the fixed lock
// bridge and the protected controller adapter.  This prevents a fragile
// cross-hierarchy ready/valid timing loop while retaining one request per
// application clock after the FIFO is primed.
module board1_ddr_request_fifo2 #(
    parameter integer ADDR_W = 25
) (
    input  wire               clk,
    input  wire               reset_n,
    input  wire               abort_i,
    input  wire               in_valid_i,
    output wire               in_ready_o,
    input  wire               in_write_i,
    input  wire [ADDR_W-1:0]  in_addr_i,
    input  wire [255:0]       in_data_i,
    output wire               out_valid_o,
    input  wire               out_ready_i,
    output wire               out_write_o,
    output wire [ADDR_W-1:0]  out_addr_o,
    output wire [255:0]       out_data_o
);
    logic write_q [0:1];
    logic [ADDR_W-1:0] addr_q [0:1];
    logic [255:0] data_q [0:1];
    logic wr_ptr_q;
    logic rd_ptr_q;
    logic [1:0] count_q;

    wire push = in_valid_i && in_ready_o;
    wire pop = out_valid_o && out_ready_i;

    assign in_ready_o = (count_q != 2) && !abort_i;
    assign out_valid_o = (count_q != 0) && !abort_i;
    assign out_write_o = write_q[rd_ptr_q];
    assign out_addr_o = addr_q[rd_ptr_q];
    assign out_data_o = data_q[rd_ptr_q];

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            wr_ptr_q <= 1'b0;
            rd_ptr_q <= 1'b0;
            count_q <= 2'd0;
        end else if (abort_i) begin
            wr_ptr_q <= 1'b0;
            rd_ptr_q <= 1'b0;
            count_q <= 2'd0;
        end else begin
            case ({push, pop})
                2'b10: count_q <= count_q + 2'd1;
                2'b01: count_q <= count_q - 2'd1;
                default: begin
                end
            endcase
            if (push) begin
                write_q[wr_ptr_q] <= in_write_i;
                addr_q[wr_ptr_q] <= in_addr_i;
                data_q[wr_ptr_q] <= in_data_i;
                wr_ptr_q <= wr_ptr_q + 1'b1;
            end
            if (pop)
                rd_ptr_q <= rd_ptr_q + 1'b1;
        end
    end

`ifdef FORMAL
    always_ff @(posedge clk) begin
        if (reset_n) begin
            assert (count_q <= 2);
            if (abort_i)
                assert (!in_ready_o && !out_valid_o);
        end
    end
`endif
endmodule

`default_nettype wire
