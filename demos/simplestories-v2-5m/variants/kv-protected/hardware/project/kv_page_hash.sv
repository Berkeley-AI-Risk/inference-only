`timescale 1ns/1ps
`default_nettype none

// PRIVATE hashing stage for sixteen-position, one-head, one-role K/V pages. Not a public command.
// Inputs must come from the trusted guard/controller, never from the host.
// DDR words are hashed in little-endian byte order; the identity header uses
// network byte order and matches role-pages-v2/model.py header exactly.
module kv_page_hash (
    input wire clk, reset_n, clear_i,
    input wire begin_valid_i,
    output wire begin_ready_o,
    input wire [63:0] epoch_i,
    input wire [2:0] layer_i,
    input wire [6:0] page_i,
    input wire head_i, role_i,
    input wire [4:0] positions_i,
    input wire word_valid_i,
    output wire word_ready_o,
    input wire [255:0] word_i,
    output wire digest_valid_o,
    input wire digest_ready_i,
    output wire [255:0] digest_o,
    output wire fault_o
);
    localparam [3:0] IDLE=0,HSTART=1,HWAIT=2,LOW=3,HIGH=4,
                     DSTART=5,DWAIT=6,PSTART=7,PWAIT=8,RESULT=9,FAULT=10;
    localparam [255:0] IV=256'h6a09e667bb67ae853c6ef372a54ff53a510e527f9b05688c1f83d9ab5be0cd19;
    logic [3:0] state_q;
    logic [511:0] header_q, block_q;
    logic [255:0] hash_q;
    logic [6:0] words_q, total_words_q;
    logic final_data_block_q;
    logic [63:0] length_bits_q;
    wire sha_done,sha_busy;
    wire [255:0] sha_state;
    wire live=reset_n && !clear_i && state_q!=FAULT;
    assign begin_ready_o=live && state_q==IDLE;
    assign word_ready_o=live && (state_q==LOW || state_q==HIGH);
    assign digest_valid_o=live && state_q==RESULT;
    assign digest_o=digest_valid_o ? hash_q : 256'd0;
    assign fault_o=reset_n && state_q==FAULT;
    wire sha_start=live && (state_q==HSTART || state_q==DSTART || state_q==PSTART);
    wire [511:0] sha_block=state_q==HSTART ? header_q :
        state_q==PSTART ? {1'b1,447'd0,length_bits_q} : block_q;

    board1_sha256_compact_compress u_sha (
        .clk_i(clk),.reset_n_i(reset_n && !clear_i),.start_i(sha_start),
        .block_i(sha_block),.state_i(hash_q),.busy_o(sha_busy),
        .done_o(sha_done),.state_o(sha_state)
    );

    function automatic [255:0] byte_order(input [255:0] value);
        for(integer i=0;i<32;i=i+1)
            byte_order[255-8*i -:8]=value[8*i +:8];
    endfunction

    wire begin_fire=begin_valid_i && begin_ready_o;
    wire word_fire=word_valid_i && word_ready_o;
`ifndef SYNTHESIS
    wire unknown_control=$isunknown({clear_i,begin_valid_i,word_valid_i,digest_ready_i}) ||
        (begin_fire && $isunknown({epoch_i,layer_i,page_i,head_i,role_i,positions_i})) ||
        (word_fire && $isunknown(word_i));
`else
    wire unknown_control=1'b0;
`endif
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            state_q<=IDLE;words_q<=0;total_words_q<=0;final_data_block_q<=0;
            hash_q<=IV;length_bits_q<=0;
        end else if(state_q==FAULT || unknown_control) begin
            state_q<=FAULT;
        end else if(clear_i) begin
            state_q<=IDLE;words_q<=0;total_words_q<=0;final_data_block_q<=0;hash_q<=IV;
        end else case(state_q)
            IDLE: if(begin_fire) begin
                if(layer_i>=6 || positions_i==0 || positions_i>16) state_q<=FAULT;
                else begin
                    // Domain[16], epoch u64, seven u32 fields, twelve zero bytes.
                    header_q<={128'h494f2d4b562d524f4c452d7632000000,epoch_i,
                        29'd0,layer_i,25'd0,page_i,31'd0,head_i,31'd0,role_i,
                        27'd0,positions_i,32'd16,32'd32,96'd0};
                    total_words_q<={positions_i,2'b0}+{2'd0,positions_i};
                    words_q<=0;hash_q<=IV;final_data_block_q<=0;
                    length_bits_q<=64'd512+{49'd0,positions_i,10'd0}+{51'd0,positions_i,8'd0};
                    state_q<=HSTART;
                end
            end
            HSTART: state_q<=HWAIT;
            HWAIT: if(sha_done) begin hash_q<=sha_state;state_q<=LOW;end
            LOW: if(word_fire) begin
                // Assemble each half in its final register. The compressor
                // starts only after both halves (or odd padding) are ready.
                block_q[511:256]<=byte_order(word_i);
                words_q<=words_q+1'b1;
                if(words_q==total_words_q-1'b1) begin
                    // An odd count leaves 32 bytes in the final block.
                    // The marker, zeros and bit length fit in its second half.
                    block_q[255:0]<={1'b1,191'd0,length_bits_q};
                    final_data_block_q<=1;state_q<=DSTART;
                end else state_q<=HIGH;
            end
            HIGH: if(word_fire) begin
                block_q[255:0]<=byte_order(word_i);words_q<=words_q+1'b1;state_q<=DSTART;
            end
            DSTART: state_q<=DWAIT;
            DWAIT: if(sha_done) begin
                hash_q<=sha_state;
                state_q<=final_data_block_q ? RESULT : (words_q==total_words_q ? PSTART : LOW);
            end
            PSTART: state_q<=PWAIT;
            PWAIT: if(sha_done) begin hash_q<=sha_state;state_q<=RESULT;end
            RESULT: if(digest_ready_i) state_q<=IDLE;
            default: state_q<=FAULT;
        endcase
    end
endmodule
`default_nettype wire
