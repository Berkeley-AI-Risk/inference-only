// PRIVATE fixed-format SHA message framing. All parameters are build-time
// constants; neither model identity nor page geometry is host-selectable.
// Arithmetic/padding and ready/valid behavior match the released 1.7B framer.
module qwen_model_hash_frame #(
    // Only a parent which immediately gates ALL consumption on reset/CLEAR
    // may select private metadata. State reset and input admission are unchanged.
    parameter bit PRIVATE_OUTPUT_METADATA=1'b0,
    parameter integer PAGE_BITS=18,
    parameter integer PAGES=134705,
    parameter [255:0] MODEL_TAG=256'hd2e8e6bc0a5f3e019d133b6da82a89cd2379745f8908eff0c07f12bb559badf8
) (
    input wire clk,input wire rst_n,input wire clear,
    input wire in_valid,output wire in_ready,
    input wire root_mode,input wire [PAGE_BITS-1:0] page_index,
    input wire [3:0] leaf_index,input wire [6:0] block_index,
    input wire [1023:0] payload_pair,input wire [15:0] in_tag,
    output wire out_valid,input wire out_ready,
    output wire [511:0] block_data,output wire out_last,
    output wire out_error,output wire [15:0] out_tag
);
    initial if(PAGE_BITS<1 || PAGE_BITS>30 || PAGES<1 || PAGES>(1<<PAGE_BITS))
        $fatal(1,"Unsupported private page geometry");
    function automatic [63:0] little_endian(input [63:0] value);
        integer i;
        begin for(i=0;i<8;i=i+1)little_endian[63-i*8 -:8]=value[i*8 +:8];end
    endfunction
    wire alive=rst_n && !clear;
    reg valid,error,last;
    reg [511:0] data;
    reg [15:0] tag;
    assign out_valid=PRIVATE_OUTPUT_METADATA ? valid : alive && valid;
    assign in_ready=alive && (!valid || out_ready);
    assign block_data=out_valid && !error ? data : 512'b0;
    assign out_error=out_valid && error;
    assign out_last=out_valid && !error && last;
    assign out_tag=out_valid ? tag : 16'b0;
    wire malformed={1'b0,page_index}>=(PAGE_BITS+1)'(PAGES) || (root_mode && leaf_index!=0)
                    || (root_mode ? block_index>7'd8 : block_index>7'd64);
    wire final_block=root_mode ? block_index==7'd8 : block_index==7'd64;
    wire [63:0] node_index=root_mode ? {{(64-PAGE_BITS){1'b0}},page_index}
        : {{(60-PAGE_BITS){1'b0}},page_index,leaf_index};
    wire [63:0] message_bits=root_mode ? 64'd4424 : 64'd33096;
    wire [511:0] formatted=block_index==0
        ? {7'b0,root_mode,MODEL_TAG,little_endian(node_index),payload_pair[1023:840]}
        : (final_block ? {payload_pair[839:512],8'h80,112'b0,message_bits}
                       : payload_pair[839:328]);
    always @(posedge clk)begin
        if(!rst_n || clear)valid<=0;
        else if(in_ready)begin
            valid<=in_valid;
            if(in_valid)begin error<=malformed;last<=final_block;tag<=in_tag;data<=formatted;end
        end
    end
endmodule
