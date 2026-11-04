`timescale 1ns/1ps
`default_nettype none
// Private byte-stream wrapper. SHA padding is generated here, never supplied
// by the package. The compressor is the frozen native SimpleStories module.
module su_sha256 #(
    parameter integer MAX_BYTES=8000000
) (
    input wire clk, reset_n, start_i,
    input wire [31:0] length_i,
    input wire byte_valid_i,
    output wire byte_ready_o,
    input wire [7:0] byte_i,
    output wire [31:0] byte_offset_o,
    output wire busy_o,
    output logic done_o, fault_o,
    output logic [255:0] digest_o
);
    localparam [255:0] IV=256'h6a09e667bb67ae853c6ef372a54ff53a510e527f9b05688c1f83d9ab5be0cd19;
    localparam [2:0] IDLE=0,FILL=1,LAUNCH=2,WAIT_HASH=3,FAILED=7;
    logic [2:0] state_q;
    logic [31:0] length_q, padded_q, offset_q;
    logic [511:0] block_q;
    logic [255:0] chain_q;
    wire compressor_busy, compressor_done;
    wire [255:0] compressor_digest;
    wire [63:0] bit_length={32'd0,length_q}<<3;
    wire payload=offset_q<length_q;
    wire transfer=state_q==FILL && (!payload || byte_valid_i);
    logic [7:0] next_byte;
    always_comb begin
        next_byte=0;
        if(payload) next_byte=byte_i;
        else if(offset_q==length_q) next_byte=8'h80;
        else if(offset_q>=padded_q-8)
            next_byte=bit_length[63-int'(offset_q-(padded_q-8))*8 -: 8];
    end
    assign byte_ready_o=state_q==FILL && payload && !fault_o;
    assign byte_offset_o=offset_q;
    assign busy_o=state_q!=IDLE && state_q!=FAILED;
    board1_sha256_compact_compress u_compress(
        .clk_i(clk),.reset_n_i(reset_n),.start_i(state_q==LAUNCH),
        .block_i(block_q),.state_i(chain_q),.busy_o(compressor_busy),
        .done_o(compressor_done),.state_o(compressor_digest));
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            state_q<=IDLE;length_q<=0;padded_q<=0;offset_q<=0;
            block_q<=0;chain_q<=IV;done_o<=0;fault_o<=0;digest_o<=0;
        end else begin
            done_o<=0;
            if((start_i && state_q!=IDLE) ||
               (state_q==LAUNCH && compressor_busy)) begin
                state_q<=FAILED;fault_o<=1;digest_o<=0;
            end else case(state_q)
                IDLE: if(start_i) begin
                    if(length_i>MAX_BYTES) begin state_q<=FAILED;fault_o<=1;end
                    else begin
                        length_q<=length_i;padded_q<=((length_i+32'd72)>>6)<<6;
                        offset_q<=0;chain_q<=IV;state_q<=FILL;
                    end
                end
                FILL: if(transfer) begin
                    block_q[511-int'(offset_q[5:0])*8 -: 8]<=next_byte;
                    offset_q<=offset_q+1;
                    if(offset_q[5:0]==63) state_q<=LAUNCH;
                end
                LAUNCH: state_q<=WAIT_HASH;
                WAIT_HASH: if(compressor_done) begin
                    chain_q<=compressor_digest;
                    if(offset_q==padded_q) begin
                        digest_o<=compressor_digest;done_o<=1;state_q<=IDLE;
                    end else state_q<=FILL;
                end
                FAILED: begin fault_o<=1;digest_o<=0;end
                default: begin state_q<=FAILED;fault_o<=1;digest_o<=0;end
            endcase
        end
    end
endmodule
`default_nettype wire
