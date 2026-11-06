`timescale 1ns/1ps
`default_nettype none
// Private byte-stream wrapper. SHA padding is generated here, never supplied
// by the package. The compressor is the frozen native SimpleStories module.
module packing_candidate #(
    parameter bit USE_SHARED_COMPRESSOR=1'b0,
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
    output logic [255:0] digest_o,
    output wire shared_request_o,
    output wire [511:0] shared_block_o,
    output wire [255:0] shared_state_o,
    input wire shared_accept_i,shared_done_i,
    input wire [255:0] shared_digest_i,
    input wire formal_local_busy_i,formal_local_done_i,
    input wire [255:0] formal_local_digest_i,
    output wire [2:0] formal_state_o,
    output wire [31:0] formal_packed_o,
    output wire [63:0] formal_lengths_o
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
    wire compressor_accept=USE_SHARED_COMPRESSOR ? shared_accept_i : 1'b1;
    assign shared_request_o=USE_SHARED_COMPRESSOR && state_q==LAUNCH && !fault_o;
    assign shared_block_o=block_q;
    assign shared_state_o=chain_q;
    generate if(USE_SHARED_COMPRESSOR) begin:g_shared_compressor
        assign compressor_busy=1'b0;
        assign compressor_done=shared_done_i;
        assign compressor_digest=shared_digest_i;
    end else begin:g_local_compressor
    // Explicit common child-response contract for this wrapper-only proof.
    assign compressor_busy=formal_local_busy_i;
    assign compressor_done=formal_local_done_i;
    assign compressor_digest=formal_local_digest_i;
    end endgenerate
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
                    block_q<={block_q[503:0],next_byte};
                    offset_q<=offset_q+1;
                    if(offset_q[5:0]==63) state_q<=LAUNCH;
                end
                LAUNCH: if(compressor_accept) state_q<=WAIT_HASH;
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
    assign formal_state_o=state_q;
    assign formal_lengths_o={length_q,padded_q};
    assign formal_packed_o=32'd0;

endmodule
`default_nettype wire

`timescale 1ns/1ps
`default_nettype none
// Private byte-stream wrapper. SHA padding is generated here, never supplied
// by the package. The compressor is the frozen native SimpleStories module.
module packing_reference #(
    parameter bit USE_SHARED_COMPRESSOR=1'b0,
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
    output logic [255:0] digest_o,
    output wire shared_request_o,
    output wire [511:0] shared_block_o,
    output wire [255:0] shared_state_o,
    input wire shared_accept_i,shared_done_i,
    input wire [255:0] shared_digest_i,
    input wire formal_local_busy_i,formal_local_done_i,
    input wire [255:0] formal_local_digest_i,
    output wire [2:0] formal_state_o,
    output wire [31:0] formal_packed_o,
    output wire [63:0] formal_lengths_o
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
    wire compressor_accept=USE_SHARED_COMPRESSOR ? shared_accept_i : 1'b1;
    assign shared_request_o=USE_SHARED_COMPRESSOR && state_q==LAUNCH && !fault_o;
    assign shared_block_o=block_q;
    assign shared_state_o=chain_q;
    generate if(USE_SHARED_COMPRESSOR) begin:g_shared_compressor
        assign compressor_busy=1'b0;
        assign compressor_done=shared_done_i;
        assign compressor_digest=shared_digest_i;
    end else begin:g_local_compressor
    // Explicit common child-response contract for this wrapper-only proof.
    assign compressor_busy=formal_local_busy_i;
    assign compressor_done=formal_local_done_i;
    assign compressor_digest=formal_local_digest_i;
    end endgenerate
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
                LAUNCH: if(compressor_accept) state_q<=WAIT_HASH;
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
    assign formal_state_o=state_q;
    assign formal_lengths_o={length_q,padded_q};
    assign formal_packed_o=32'd0;

endmodule
`default_nettype wire


module packing_miter #(parameter integer SHARED=1, LIMIT=4096, FAST_COVER=0)(
    input wire clk,reset_n,start_i,byte_valid_i,
    input wire [31:0] length_i,
    input wire [7:0] byte_i,
    input wire shared_accept_i,shared_done_i,
    input wire [255:0] shared_digest_i,
    input wire local_busy,local_done,
    input wire [255:0] local_digest);
    wire ready_a,ready_b,busy_a,busy_b,done_a,done_b,fault_a,fault_b,req_a,req_b;
    wire [31:0] off_a,off_b,packed_a,packed_b;
    wire [2:0] state_a,state_b;
    wire [255:0] digest_a,digest_b,chain_a,chain_b;
    wire [511:0] block_a,block_b;
    wire [63:0] lengths_a,lengths_b;
    packing_candidate #(.USE_SHARED_COMPRESSOR(SHARED),.MAX_BYTES(LIMIT)) a(
        .clk(clk),.reset_n(reset_n),.start_i(start_i),.length_i(length_i),
        .byte_valid_i(byte_valid_i),.byte_ready_o(ready_a),.byte_i(byte_i),
        .byte_offset_o(off_a),.busy_o(busy_a),.done_o(done_a),.fault_o(fault_a),.digest_o(digest_a),
        .shared_request_o(req_a),.shared_block_o(block_a),.shared_state_o(chain_a),
        .shared_accept_i(shared_accept_i),.shared_done_i(shared_done_i),.shared_digest_i(shared_digest_i),
        .formal_local_busy_i(local_busy),.formal_local_done_i(local_done),.formal_local_digest_i(local_digest),
        .formal_state_o(state_a),.formal_packed_o(packed_a),.formal_lengths_o(lengths_a));
    packing_reference #(.USE_SHARED_COMPRESSOR(SHARED),.MAX_BYTES(LIMIT)) b(
        .clk(clk),.reset_n(reset_n),.start_i(start_i),.length_i(length_i),
        .byte_valid_i(byte_valid_i),.byte_ready_o(ready_b),.byte_i(byte_i),
        .byte_offset_o(off_b),.busy_o(busy_b),.done_o(done_b),.fault_o(fault_b),.digest_o(digest_b),
        .shared_request_o(req_b),.shared_block_o(block_b),.shared_state_o(chain_b),
        .shared_accept_i(shared_accept_i),.shared_done_i(shared_done_i),.shared_digest_i(shared_digest_i),
        .formal_local_busy_i(local_busy),.formal_local_done_i(local_done),.formal_local_digest_i(local_digest),
        .formal_state_o(state_b),.formal_packed_o(packed_b),.formal_lengths_o(lengths_b));
    reg past_valid=0;
    reg [7:0] witness_cycle=0;
    always @(posedge clk) past_valid<=1;
    always @(posedge clk) if(witness_cycle<70) witness_cycle<=witness_cycle+1;
    always @* if(!past_valid) assume(!reset_n);
    always @* if(FAST_COVER) begin
        assume(length_i==0);
        assume(reset_n==(witness_cycle!=0));
        assume(start_i==(witness_cycle==1));
        assume(!local_busy);
        assume(shared_accept_i);
    end
    wire [1023:0] doubled_block={block_b,block_b};
    wire [1023:0] rotated_block=doubled_block<<{off_b[5:0],3'b0};
    wire [511:0] expected_block=rotated_block[1023:512];
    always @(posedge clk) if(past_valid) begin
        assert({ready_a,busy_a,done_a,fault_a,req_a,off_a,digest_a,chain_a,state_a}==
               {ready_b,busy_b,done_b,fault_b,req_b,off_b,digest_b,chain_b,state_b});
        assert(lengths_a==lengths_b);
        if(state_a==0 || state_a==2 || state_a==3) begin
            assert(off_a[5:0]==0);
            assert(block_a==block_b);
        end
        if(state_a==1) assert(block_a==expected_block);
        cover(state_a==2 && !fault_a);
    end

endmodule
