// PRIVATE fixed-format model commitment block framer. Not a host SHA service.
// MODEL_TAG is a compile-time identity, never loaded from application software.
// Data bytes are big-endian within payload_pair. For block zero, supply payload
// words 0/1. Otherwise supply aligned payload words (block_index-1)/block_index.
// The last word beyond the payload is ignored. A private page buffer owns reads.
module qwen_model_hash_frame #(
    parameter [255:0] MODEL_TAG=256'h250e021a1e402acc45fa3a4ae7e925a7b5341e82d77ca2d69e4044b8c9b1fce3
) (
    input wire clk,input wire rst_n,input wire clear,
    input wire in_valid,output wire in_ready,
    input wire root_mode,input wire [15:0] page_index,
    input wire [3:0] leaf_index,input wire [6:0] block_index,
    input wire [1023:0] payload_pair,input wire [15:0] in_tag,
    output wire out_valid,input wire out_ready,
    output wire [511:0] block_data,output wire out_last,
    output wire out_error,output wire [15:0] out_tag
);
    function automatic [63:0] little_endian(input [63:0] value);
        integer i;
        begin for(i=0;i<8;i=i+1) little_endian[63-i*8 -:8]=value[i*8 +:8];end
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
    wire malformed=page_index>=16'd35925 || (root_mode && leaf_index!=0)
                    || (root_mode ? block_index>7'd8 : block_index>7'd64);
    wire final_block=root_mode ? block_index==7'd8 : block_index==7'd64;
    wire [63:0] node_index=root_mode ? {48'b0,page_index} : {44'b0,page_index,leaf_index};
    wire [63:0] message_bits=root_mode ? 64'd4424 : 64'd33096;
    wire [511:0] formatted=block_index==0
        ? {7'b0,root_mode,MODEL_TAG,little_endian(node_index),payload_pair[1023:840]}
        : (final_block ? {payload_pair[839:512],8'h80,112'b0,message_bits}
                       : payload_pair[839:328]);
    always @(posedge clk) begin
        if(!rst_n || clear) valid<=0;
        else if(in_ready) begin
            valid<=in_valid;
            if(in_valid) begin
                error<=malformed;last<=final_block;tag<=in_tag;
                data<=formatted;
            end
        end
    end
endmodule
