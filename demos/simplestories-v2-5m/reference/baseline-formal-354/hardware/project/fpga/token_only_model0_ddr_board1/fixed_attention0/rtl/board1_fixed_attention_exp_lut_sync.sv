`timescale 1ns/1ps
`default_nettype none

// Immutable exact 4097-entry Q2.30 exp(-i/256) table.  A registered read is
// intentional: it preserves a single physical BSRAM port, including the
// clipped endpoint i=4096.
module board1_fixed_attention_exp_lut_sync #(
    parameter FILE = "model_rtl_evidence/attention_sublayer/exp_neg_q30.memh"
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    clear_i,
    input  wire                    request_valid_i,
    input  wire [12:0]             index_i,
    output logic                   response_valid_o,
    output logic [30:0]            value_o,
    output logic                   response_fault_o,
    output logic                   range_fault_o
);
    (* nomem2reg, rom_style = "block" *)
    logic [31:0] value_mem [0:4096];
    logic [31:0] rom_data_q;
    logic response_valid_q;
    logic response_index_fault_q;
    wire invalid_index = (index_i > 13'd4096);
    wire invalid_encoding = rom_data_q[31] || (rom_data_q == 0) ||
                            (rom_data_q > 32'd1073741824);
    initial $readmemh(FILE, value_mem);

    always_ff @(posedge clk)
        if (request_valid_i && !invalid_index)
            rom_data_q <= value_mem[index_i];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            response_valid_q <= 1'b0;
            response_index_fault_q <= 1'b0;
            range_fault_o <= 1'b0;
        end else if (clear_i) begin
            response_valid_q <= 1'b0;
            response_index_fault_q <= 1'b0;
            range_fault_o <= 1'b0;
        end else begin
            response_valid_q <= request_valid_i;
            response_index_fault_q <= request_valid_i && invalid_index;
            if ((request_valid_i && invalid_index) ||
                (response_valid_q && invalid_encoding))
                range_fault_o <= 1'b1;
        end
    end

    always_comb begin
        response_valid_o = response_valid_q;
        response_fault_o = response_valid_q &&
                           (response_index_fault_q || invalid_encoding);
        value_o = invalid_encoding ? 31'd0 : rom_data_q[30:0];
    end
endmodule

`default_nettype wire
