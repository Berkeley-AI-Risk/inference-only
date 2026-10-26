`timescale 1ns/1ps
`default_nettype none

// Exact parameter-selected 4097-word image: one synchronous 4096-word low
// ROM plus an independently initialized 32-bit endpoint. Both come from the
// same complete FILE load; no endpoint value or adjacency alias is assumed.
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
    logic [31:0] value_mem [0:4095];
    logic [31:0] endpoint_value;
    logic [31:0] low_data_q;
    logic endpoint_select_q;
    wire [31:0] rom_data_q = endpoint_select_q ? endpoint_value : low_data_q;
    logic response_valid_q;
    logic response_index_fault_q;
    wire invalid_index = (index_i > 13'd4096);
    wire invalid_encoding = rom_data_q[31] || (rom_data_q == 0) ||
                            (rom_data_q > 32'd1073741824);
    // Elaboration-only staging preserves all FILE words, including a distinct
    // or invalidly encoded endpoint. Runtime storage is the low ROM and the
    // endpoint constant; synthesis must remove this staging image.
    initial begin : load_complete_image
        logic [31:0] initialization_image [0:4096];
        integer address;
        $readmemh(FILE, initialization_image);
        // Bound each elaboration loop below the native frontend limit. The
        // four disjoint blocks copy every low word exactly once.
        for (address = 0; address < 1024; address = address + 1) begin
            value_mem[address] = initialization_image[address];
            value_mem[address + 1024] = initialization_image[address + 1024];
            value_mem[address + 2048] = initialization_image[address + 2048];
            value_mem[address + 3072] = initialization_image[address + 3072];
        end
        endpoint_value = initialization_image[4096];
    end

    // Read/selection are deliberately independent of reset/CLEAR. Invalid
    // addresses and bubbles hold the last selected payload, as before.
    always_ff @(posedge clk)
        if (request_valid_i && !invalid_index) begin
            if (index_i == 13'd4096)
                endpoint_select_q <= 1'b1;
            else begin
                low_data_q <= value_mem[index_i[11:0]];
                endpoint_select_q <= 1'b0;
            end
        end

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
