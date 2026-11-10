// PRIVATE mutable K/V commitment framing. This is not a host hash service,
// page verifier, trusted-root manager, or complete K/V memory implementation.
// Epoch/coordinates/count come from fixed private ownership logic. MODEL_TAG
// is frozen at build time. Node 0..7 = K heads; 8..15 = V heads; 16 = page root.
//
// payload_pair is two aligned 64-byte words in big-endian byte order: words
// 0/1 for block zero, otherwise words (block_index-1)/block_index. Bytes beyond
// the leaf/root payload are ignored. The 48-byte header is defined independently
// in tools/kv_commitments.py and in the test's complete-message construction.
module qwen_kv_hash_frame #(
    parameter integer LAYERS=28,
    parameter integer LAYER_BITS=$clog2(LAYERS),
    parameter [255:0] MODEL_TAG=256'h250e021a1e402acc45fa3a4ae7e925a7b5341e82d77ca2d69e4044b8c9b1fce3
) (
    input wire clk,input wire rst_n,input wire clear,
    input wire in_valid,output wire in_ready,
    input wire [63:0] epoch,input wire [LAYER_BITS-1:0] layer,input wire [15:0] page_group,
    input wire [4:0] node_index,input wire [4:0] valid_positions,input wire [6:0] block_index,
    input wire [1023:0] payload_pair,input wire [15:0] in_tag,
    output wire out_valid,input wire out_ready,output wire [511:0] block_data,
    output wire out_last,output wire out_error,output wire [15:0] out_tag
);
    function automatic [63:0] little_endian(input [63:0] value);
        integer i;
        begin for(i=0;i<8;i=i+1)little_endian[63-i*8 -:8]=value[i*8 +:8];end
    endfunction
    wire alive=rst_n && !clear;
    reg valid,error,last;
    reg [511:0] data;
    reg [15:0] tag;
    assign out_valid=alive && valid;
    assign in_ready=alive && (!valid || out_ready);
    assign block_data=out_valid && !error ? data : 512'b0;
    assign out_error=out_valid && error;
    assign out_last=out_valid && !error && last;
    assign out_tag=out_valid ? tag : 16'b0;
    wire root_mode=node_index==5'd16;
    wire malformed=int'(layer)>=LAYERS || page_group>=16'd2048 || node_index>5'd16
        || valid_positions==0 || valid_positions>5'd16
        || (root_mode ? block_index>7'd8 : block_index>7'd64);
    wire final_block=root_mode ? block_index==7'd8 : block_index==7'd64;
    wire [383:0] header={root_mode ? 8'h21 : 8'h20,MODEL_TAG,little_endian(epoch),
        8'(layer),page_group[7:0],page_group[15:8],3'b0,node_index,3'b0,valid_positions,16'b0};
    wire [63:0] message_bits=root_mode ? 64'd4480 : 64'd33152;
    wire [511:0] formatted=block_index==0 ? {header,payload_pair[1023:896]}
        : (final_block ? {payload_pair[895:512],8'h80,56'b0,message_bits} : payload_pair[895:384]);
    always @(posedge clk) begin
        if(!rst_n || clear)valid<=0;
        else if(in_ready)begin
            valid<=in_valid;
            if(in_valid)begin error<=malformed;last<=final_block;tag<=in_tag;data<=formatted;end
        end
    end
endmodule
