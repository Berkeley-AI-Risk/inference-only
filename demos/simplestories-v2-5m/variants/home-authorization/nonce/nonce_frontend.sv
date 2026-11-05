`timescale 1ns/1ps
`default_nettype none
// Private entropy consumer, simple health screens, and SHA-256 conditioner.
// Health screens do not establish entropy or SP 800-90B compliance.
module nonce_frontend #(
    parameter bit USE_SHARED_HASH=1'b0,
    parameter integer SAMPLE_BYTES=512,
    parameter integer STARTUP_CYCLES=1024,
    parameter integer TIMEOUT_CYCLES=25000000,
    parameter integer MAX_IDENTICAL_BYTES=16
)(
    input wire clk,reset_n,request_i,
    output wire entropy_enable_o,
    input wire entropy_valid_i,
    input wire [7:0] entropy_byte_i,
    output wire nonce_valid_o,
    output wire [255:0] nonce_o,
    output wire fault_o,
    output wire shared_hash_start_o,shared_hash_byte_valid_o,
    output wire [7:0] shared_hash_byte_o,
    input wire shared_hash_available_i,shared_hash_done_i,shared_hash_fault_i,
    input wire [31:0] shared_hash_offset_i,
    input wire [255:0] shared_hash_digest_i
);
    localparam [3:0] QUIET=0,WARM=1,COLLECT=2,HASH_START=3,HASH_WAIT=4,READY=5,FAILED=15;
    localparam CW=$clog2(SAMPLE_BYTES+1),TW=$clog2(TIMEOUT_CYCLES+1),QW=$clog2(STARTUP_CYCLES+1);
    localparam [127:0] DOMAIN=128'h53415749432d4e4f4e43452d76310000;
    logic [3:0] state_q;
    logic [TW-1:0] timeout_q;
    logic [QW-1:0] delay_q;
    logic [CW-1:0] count_q;
    logic [15:0] ones_q;
    logic [7:0] previous_q;
    logic [7:0] repeat_q;
    logic [255:0] nonce_q;
    (* ram_style="block" *) logic [7:0] samples[0:SAMPLE_BYTES-1];
    logic [7:0] sample_byte_q;
    logic [CW-1:0] sample_address_q;
    logic sample_valid_q;
    wire hash_ready,hash_busy,hash_done,hash_fault;
    wire [31:0] hash_offset;
    wire [255:0] hash_digest;
    wire sample_payload=hash_offset>=16 && hash_offset<16+SAMPLE_BYTES;
    wire [CW-1:0] sample_address=CW'(hash_offset-16);
    wire hash_byte_valid=state_q==HASH_WAIT && (!sample_payload ||
        (sample_valid_q && sample_address_q==sample_address));
    logic [7:0] hash_byte;
    function automatic [3:0] pop8(input [7:0] x);
        pop8=4'(x[0])+4'(x[1])+4'(x[2])+4'(x[3])+4'(x[4])+4'(x[5])+4'(x[6])+4'(x[7]);
    endfunction
    wire [15:0] new_ones=ones_q+16'(pop8(entropy_byte_i));
    wire timed_out=state_q!=QUIET && state_q!=READY && timeout_q==TW'(TIMEOUT_CYCLES-1);
    assign entropy_enable_o=state_q==WARM || state_q==COLLECT;
    assign fault_o=state_q==FAILED || hash_fault;
    assign nonce_valid_o=state_q==READY && request_i && !fault_o;
    assign nonce_o=nonce_valid_o ? nonce_q : 256'd0;
    always_comb begin
        hash_byte=0;
        if(hash_offset<16)hash_byte=DOMAIN[{~hash_offset[3:0],3'b000} +:8];
        else if(hash_offset<16+SAMPLE_BYTES)hash_byte=sample_byte_q;
    end
    assign shared_hash_start_o=state_q==HASH_START && (!USE_SHARED_HASH || shared_hash_available_i);
    assign shared_hash_byte_valid_o=hash_byte_valid;
    assign shared_hash_byte_o=hash_byte;
    generate if(USE_SHARED_HASH)begin:g_shared
        assign hash_offset=shared_hash_offset_i;
        assign hash_digest=shared_hash_digest_i;
        assign hash_done=shared_hash_done_i;
        assign hash_fault=shared_hash_fault_i;
        assign hash_ready=1'b0;
        assign hash_busy=1'b0;
    end else begin:g_local
      su_sha256 #(.MAX_BYTES(SAMPLE_BYTES+16)) u_conditioner(
        .clk(clk),.reset_n(reset_n),.start_i(state_q==HASH_START),.length_i(32'(SAMPLE_BYTES+16)),
        .byte_valid_i(hash_byte_valid),.byte_ready_o(hash_ready),.byte_i(hash_byte),.byte_offset_o(hash_offset),
        .busy_o(hash_busy),.done_o(hash_done),.fault_o(hash_fault),.digest_o(hash_digest));
    end endgenerate
    always_ff @(posedge clk)begin
        if(state_q==COLLECT && request_i && entropy_valid_i)samples[count_q]<=entropy_byte_i;
        if(state_q==HASH_WAIT && sample_payload)begin
            sample_byte_q<=samples[sample_address];sample_address_q<=sample_address;
        end
    end
    always_ff @(posedge clk or negedge reset_n)begin
        if(!reset_n)sample_valid_q<=0;
        else sample_valid_q<=state_q==HASH_WAIT && sample_payload;
    end
    always_ff @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            state_q<=QUIET;timeout_q<=0;delay_q<=0;count_q<=0;ones_q<=0;
            previous_q<=0;repeat_q<=0;nonce_q<=0;
        end else if(hash_fault || timed_out)state_q<=FAILED;
        else if(state_q!=FAILED)begin
            if(state_q!=QUIET && state_q!=READY)begin
                timeout_q<=timeout_q+1'b1;
            end
            if(!request_i && state_q!=QUIET)begin state_q<=QUIET;delay_q<=0;nonce_q<=0;end
            else case(state_q)
                QUIET:begin
                    if(delay_q<QW'(STARTUP_CYCLES))delay_q<=delay_q+1'b1;
                    else if(request_i)begin
                        state_q<=WARM;delay_q<=0;timeout_q<=0;count_q<=0;ones_q<=0;repeat_q<=0;
                    end
                end
                WARM:begin
                    if(delay_q==QW'(STARTUP_CYCLES-1))begin state_q<=COLLECT;delay_q<=0;end
                    else delay_q<=delay_q+1'b1;
                end
                COLLECT:if(entropy_valid_i)begin
                    previous_q<=entropy_byte_i;
                    repeat_q<=(count_q!=0 && entropy_byte_i==previous_q)?repeat_q+1'b1:8'd1;
                    ones_q<=new_ones;
                    if(count_q!=0 && entropy_byte_i==previous_q && repeat_q>=MAX_IDENTICAL_BYTES-1)
                        state_q<=FAILED;
                    else if(count_q==CW'(SAMPLE_BYTES-1))begin
                        if(new_ones<SAMPLE_BYTES*2 || new_ones>SAMPLE_BYTES*6)state_q<=FAILED;
                        else state_q<=HASH_START;
                    end else count_q<=count_q+1'b1;
                end
                HASH_START:if(!USE_SHARED_HASH || shared_hash_available_i)state_q<=HASH_WAIT;
                HASH_WAIT:if(hash_done)begin nonce_q<=hash_digest;state_q<=READY;end
                READY:begin end
                default:state_q<=FAILED;
            endcase
        end
    end
endmodule
`default_nettype wire
