`timescale 1ns/1ps
`default_nettype none

// Entire mutable cache is inside the sealed top. Its sole caller is the
// unchanged typed capability boundary. Reset/CLEAR invalidate controller
// ownership, not payload bits; every legal cache read follows committed writes.
// Ordinary synchronous SRAM RTL, requiring real memory views for physical use.
module hwic_private_kv_ram (
    input wire clk, reset_n, enabled_i,
    input wire request_valid_i,
    output wire request_ready_o,
    input wire [18:0] request_word_i,
    input wire request_write_i,
    input wire [255:0] request_data_i,
    output logic response_valid_o,
    input wire response_ready_i,
    output logic [255:0] response_data_o,
    output logic response_error_o,
    output logic fault_o
);
    localparam integer BASE=227072, WORDS=221184;
    (* ram_style="block" *) logic [255:0] payload [0:WORDS-1];
    wire legal=request_word_i>=BASE && request_word_i<BASE+WORDS;
    assign request_ready_o=reset_n && enabled_i && !fault_o &&
        (!response_valid_o || response_ready_i);
    // Synchronous memory has no reset, scan, public debug or readback path.
    always_ff @(posedge clk) begin
        if(request_valid_i && request_ready_o && legal) begin
            if(request_write_i) payload[request_word_i-BASE]<=request_data_i;
            else response_data_o<=payload[request_word_i-BASE];
        end
    end
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            response_valid_o<=0; response_error_o<=0; fault_o<=0;
        end else begin
            if(response_valid_o && response_ready_i) response_valid_o<=0;
            if(request_valid_i && request_ready_o) begin
                if(!legal) fault_o<=1;
                // Typed boundary retires a write on request acceptance. Only
                // reads return data; no unsolicited write response is created.
                if(!request_write_i) begin
                    response_valid_o<=1; response_error_o<=!legal;
                end
            end
        end
    end
endmodule
`default_nettype wire
