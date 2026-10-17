// PRIVATE fixed-image provisioning controller. The shell-facing bounded FIFO
// is not implemented here. No host address, expected digest, chaining state,
// model selector or reopen/CLEAR command enters this module.
//
// Accept exactly IMAGE_BYTES as sequential 64-byte blocks, byte zero in [7:0].
// The controller owns all page addresses, emits fixed 64 KiB writes, and checks
// the whole-image SHA-256 against a compile-time constant before model_ready.
// Every runtime model read must STILL pass the fixed-root page verifier: this
// startup check alone does not protect against later external-memory tampering.
//
// A memory/format/hash failure latches until coordinated fabric reset. Ordinary
// application CLEAR is intentionally absent and cannot rewrite model weights.
// Inputs/outputs are in clk; rst_n must have synchronized release in that domain.
// The private write transport must acknowledge actual completion, not enqueueing.
module qwen_model_boot_loader #(
    parameter [31:0] IMAGE_BYTES=32'd2354380800,
    parameter [255:0] IMAGE_SHA256=256'h90d82ed9b90c58607f924190be0c15f18b70d849c536a2ccbddd259858979cd1
) (
    input wire clk,input wire rst_n,
    input wire stream_valid,output wire stream_ready,input wire [511:0] stream_data,input wire stream_last,
    output wire model_ready,output wire loading,output wire error,output wire [31:0] accepted_bytes,
    output wire memory_request_valid,input wire memory_request_ready,
    output wire [33:0] memory_address,output wire [16:0] memory_bytes,
    output wire memory_write_valid,input wire memory_write_ready,
    output wire [2047:0] memory_write_data,output wire memory_write_last,
    input wire memory_done_valid,output wire memory_done_ready,input wire memory_done_error,
    input wire memory_error,output wire memory_abort,input wire memory_quiescent
);
    localparam [3:0] START=0,REQUEST=1,RECEIVE=2,WAIT_DONE=3,NEXT_PAGE=4,PADDING=5,CHECK_HASH=6,SEALED=7,FAILED=8;
    localparam [25:0] TOTAL_BLOCKS=26'(IMAGE_BYTES>>6);
    localparam [15:0] LAST_PAGE=16'((IMAGE_BYTES>>16)-1);
    localparam [63:0] IMAGE_BITS={32'b0,IMAGE_BYTES}<<3;
    localparam [255:0] IV=256'h6a09e667bb67ae853c6ef372a54ff53a510e527f9b05688c1f83d9ab5be0cd19;
    reg [3:0] state;
    reg failed,sealed,hash_pending,pending_padding,word_valid,word_last;
    reg [25:0] blocks_accepted;
    reg [15:0] page;
    reg [2047:0] word_buffer;
    reg [255:0] chain;
    wire alive=rst_n && !failed && !memory_error;
    wire input_last_expected=blocks_accepted==TOTAL_BLOCKS-26'd1;
    wire framing_ok=stream_last==input_last_expected;
    wire sha_in_valid,sha_in_ready,sha_out_valid,sha_out_ready,sha_out_tag;
    wire [511:0] data_block,sha_block;
    wire [255:0] sha_result;
    wire sha_in_take=sha_in_valid && sha_in_ready;
    wire sha_out_take=sha_out_valid && sha_out_ready;
    wire stream_take=stream_valid && stream_ready;
    wire write_take=memory_write_valid && memory_write_ready;
    wire done_take=memory_done_valid && memory_done_ready;

    initial if(IMAGE_BYTES==0 || IMAGE_BYTES[15:0]!=0 || IMAGE_BYTES>32'd2354380800)
        $fatal(1,"Invalid bounded model image geometry");

    assign stream_ready=alive && state==RECEIVE && !hash_pending && !word_valid &&
        blocks_accepted<TOTAL_BLOCKS && sha_in_ready;
    assign model_ready=rst_n && sealed && !failed && !memory_error;
    assign loading=rst_n && !sealed && !failed && !memory_error;
    assign error=rst_n && (failed || memory_error);
    assign accepted_bytes={blocks_accepted,6'b0};
    assign memory_request_valid=alive && state==REQUEST;
    assign memory_address={2'b0,page,16'b0};
    assign memory_bytes=17'd65536;
    assign memory_write_valid=alive && state==RECEIVE && word_valid;
    assign memory_write_data=memory_write_valid ? word_buffer : 2048'b0;
    assign memory_write_last=memory_write_valid && word_last;
    assign memory_done_ready=alive && state==WAIT_DONE;
    assign memory_abort=!rst_n || failed || memory_error;

    genvar byte_index;
    generate for(byte_index=0;byte_index<64;byte_index=byte_index+1)begin:sha_byte_order
        assign data_block[511-byte_index*8 -:8]=stream_data[byte_index*8 +:8];
    end endgenerate
    assign sha_in_valid=alive && !hash_pending &&
        ((state==RECEIVE && stream_valid && !word_valid && blocks_accepted<TOTAL_BLOCKS && framing_ok)
         || state==PADDING);
    assign sha_block=state==PADDING ? {8'h80,440'b0,IMAGE_BITS} : data_block;
    assign sha_out_ready=alive && hash_pending;
    qwen_sha256_pipeline #(.TAG_BITS(1)) checksum(
        .clk(clk),.rst_n(rst_n),.clear(failed),.in_valid(sha_in_valid),.in_ready(sha_in_ready),
        .block_data(sha_block),.initial_state(chain),.in_tag(state==PADDING),
        .out_valid(sha_out_valid),.out_ready(sha_out_ready),.final_state(sha_result),.out_tag(sha_out_tag),.busy());

    // Bulk payload storage has no reset; all four slices must be filled before
    // word_valid is asserted. Reset invalidates the counters/ownership instead.
    always @(posedge clk)if(stream_take && framing_ok)
        word_buffer[blocks_accepted[1:0]*512+:512]<=stream_data;
    always @(posedge clk)begin
        if(!rst_n)begin
            state<=START;failed<=0;sealed<=0;hash_pending<=0;pending_padding<=0;
            word_valid<=0;word_last<=0;blocks_accepted<=0;page<=0;chain<=IV;
        end else if(failed)begin
            state<=FAILED;sealed<=0;word_valid<=0;hash_pending<=0;
        end else begin
            if(sha_in_take)begin hash_pending<=1;pending_padding<=state==PADDING;end
            if(sha_out_take)begin
                hash_pending<=0;
                if(!pending_padding)chain<=sha_result;
            end
            if(stream_take && framing_ok)begin
                blocks_accepted<=blocks_accepted+26'd1;
                if(blocks_accepted[1:0]==2'd3)begin
                    word_valid<=1;word_last<=blocks_accepted[9:0]==10'd1023;
                end
            end
            if(write_take)word_valid<=0;
            case(state)
                START:if(memory_quiescent && !memory_error)state<=REQUEST;
                REQUEST:if(memory_request_valid && memory_request_ready)state<=RECEIVE;
                RECEIVE:if(write_take && word_last)state<=WAIT_DONE;
                WAIT_DONE:if(done_take)state<=NEXT_PAGE;
                NEXT_PAGE:if(memory_quiescent && !hash_pending && !word_valid)begin
                    if(page==LAST_PAGE)state<=PADDING;
                    else begin page<=page+16'd1;state<=REQUEST;end
                end
                PADDING:if(sha_in_take)state<=CHECK_HASH;
                CHECK_HASH:if(sha_out_take)begin
                    if(sha_result==IMAGE_SHA256 && blocks_accepted==TOTAL_BLOCKS && memory_quiescent)begin
                        sealed<=1;state<=SEALED;
                    end else begin failed<=1;state<=FAILED;end
                end
                SEALED:begin end
                default:begin failed<=1;sealed<=0;state<=FAILED;end
            endcase
            if(memory_error || (stream_take && !framing_ok) || (done_take && memory_done_error) ||
               (sha_out_valid && (!hash_pending || sha_out_tag!=pending_padding)))begin
                failed<=1;sealed<=0;word_valid<=0;state<=FAILED;
            end
        end
    end
endmodule
