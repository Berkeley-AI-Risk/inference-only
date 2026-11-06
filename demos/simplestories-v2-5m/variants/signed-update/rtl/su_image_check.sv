`timescale 1ns/1ps
`default_nettype none
// Ordered DDR readback, not flash-side hashing. The expected digest comes
// only from the sealed, signed boot payload. No runtime restart of this block.
module su_image_check #(parameter bit USE_SHARED_COMPRESSOR=1'b0) (
    input wire clk,reset_n,start_i,
    input wire [255:0] expected_sha_i,
    input wire readback_valid_i,
    output wire readback_ready_o,
    input wire [7:0] readback_byte_i,
    input wire readback_last_i,
    output wire verified_o,
    output wire fault_o,
    output wire shared_request_o,
    output wire [511:0] shared_block_o,
    output wire [255:0] shared_state_o,
    input wire shared_accept_i,shared_done_i,
    input wire [255:0] shared_digest_i
);
    localparam integer IMAGE_BYTES=7265984;
    logic started_q,received_last_q,verified_q,fault_q;
    logic [22:0] count_q;
    logic [255:0] expected_q;
    wire sha_ready,sha_busy,sha_done,sha_fault;
    wire [31:0] sha_offset;
    wire [255:0] sha_digest;
`ifndef SYNTHESIS
    logic input_x_fault;
    always_comb begin
        input_x_fault=$isunknown(start_i) || $isunknown(readback_valid_i) || $isunknown(sha_done);
        if(start_i) input_x_fault=input_x_fault || $isunknown(expected_sha_i);
        if(readback_valid_i) input_x_fault=input_x_fault || $isunknown(readback_byte_i) || $isunknown(readback_last_i);
        if(sha_done) input_x_fault=input_x_fault || $isunknown(sha_digest);
    end
`else
    wire input_x_fault=1'b0;
`endif
    wire transfer=readback_valid_i && readback_ready_o;
    assign readback_ready_o=started_q && !received_last_q && !fault_o && sha_ready;
    assign verified_o=verified_q && !fault_o;
    assign fault_o=fault_q || sha_fault;
    su_sha256 #(.MAX_BYTES(IMAGE_BYTES),.USE_SHARED_COMPRESSOR(USE_SHARED_COMPRESSOR)) u_sha(
        .clk(clk),.reset_n(reset_n),.start_i(start_i && !started_q),.length_i(32'(IMAGE_BYTES)),
        .byte_valid_i(readback_valid_i && started_q && !received_last_q && !fault_q),
        .byte_ready_o(sha_ready),.byte_i(readback_byte_i),.byte_offset_o(sha_offset),
        .busy_o(sha_busy),.done_o(sha_done),.fault_o(sha_fault),.digest_o(sha_digest),
        .shared_request_o(shared_request_o),.shared_block_o(shared_block_o),.shared_state_o(shared_state_o),
        .shared_accept_i(shared_accept_i),.shared_done_i(shared_done_i),.shared_digest_i(shared_digest_i));
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            started_q<=0;received_last_q<=0;verified_q<=0;fault_q<=0;count_q<=0;expected_q<=0;
        end else if(input_x_fault || fault_o || (start_i && started_q) ||
                    (readback_valid_i && received_last_q)) begin
            fault_q<=1;verified_q<=0;
        end else begin
            if(start_i) begin started_q<=1;expected_q<=expected_sha_i;end
            if(transfer) begin
                if(readback_last_i != (count_q==23'(IMAGE_BYTES-1))) begin fault_q<=1;verified_q<=0;end
                else begin
                    count_q<=count_q+1;
                    if(count_q==23'(IMAGE_BYTES-1)) received_last_q<=1;
                end
            end
            if(sha_done) begin
                if(!received_last_q || sha_digest!=expected_q) begin fault_q<=1;verified_q<=0;end
                else verified_q<=1;
            end
        end
    end
endmodule
`default_nettype wire
