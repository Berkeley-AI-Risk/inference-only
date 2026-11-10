// PRIVATE full-page commitment calculator for the fixed K/V update engine.
// Derived from qwen_kv_page_hash.sv (sha256 578cdcaf014e6e26...). The only change is
// ZERO_WHEN_INVALID: the Qwen store sets it to 0 so the done_valid/alive cone
// does not fan out through 4,352 digest bits. root/manifest may be used only on
// done_valid, which is unchanged, as in the released model verifier.
//
// The caller owns a retained, immutable-for-this-operation 64-KiB private page.
// buffer_read_enable/address request two consecutive 64-byte big-endian words;
// buffer_read_pair must be registered by that private RAM on the same edge and
// held until the next enabled read. At word 1023 the second word is ignored.
// This is NOT an external-memory verifier or host hash service. It neither
// authenticates the caller nor publishes roots. The fixed writer compares an
// old-page result to its trusted root and publishes a new result only after
// writing the exact retained updated page/manifest to external memory.
module qwen_kvp_page_hash #(
    parameter integer LAYERS=28,
    parameter integer LAYER_BITS=$clog2(LAYERS),
    parameter [255:0] MODEL_TAG=256'h250e021a1e402acc45fa3a4ae7e925a7b5341e82d77ca2d69e4044b8c9b1fce3,
    parameter integer ZERO_WHEN_INVALID=1
) (
    input wire clk,input wire rst_n,input wire clear,
    input wire start_valid,output wire start_ready,
    input wire [63:0] start_epoch,input wire [LAYER_BITS-1:0] start_layer,
    input wire [15:0] start_group,input wire [4:0] start_count,
    output wire buffer_read_enable,output wire [9:0] buffer_read_word,
    input wire [1023:0] buffer_read_pair,
    output wire done_valid,input wire done_ready,
    output wire [255:0] root,output wire [4095:0] manifest,
    output wire error,output wire busy
);
    localparam [255:0] IV=256'h6a09e667bb67ae853c6ef372a54ff53a510e527f9b05688c1f83d9ab5be0cd19;
    initial if(ZERO_WHEN_INVALID!=0 && ZERO_WHEN_INVALID!=1)
        $fatal(1,"Invalid private page-hash payload setting");
    reg running,finished,failed;
    reg [63:0] epoch;
    reg [LAYER_BITS-1:0] layer;
    reg [4:0] count,scan_node;
    reg [15:0] page_group;
    reg [16:0] inflight,complete;
    reg [6:0] blocks [0:16];
    reg [255:0] chain [0:16];
    reg stage_valid;
    reg [4:0] stage_node;
    reg [6:0] stage_block;
    reg [255:0] stage_state,framed_state;
    wire alive=rst_n && !clear && !failed;
    assign start_ready=alive && !running && !finished;
    assign done_valid=alive && finished;
    assign error=rst_n && !clear && failed;
    assign busy=alive && (running || finished);
    wire digest_visible=ZERO_WHEN_INVALID==0 || done_valid;
    assign root=digest_visible ? chain[16] : 256'b0;
    genvar leaf;
    generate for(leaf=0;leaf<16;leaf=leaf+1)begin:manifest_words
        assign manifest[4095-256*leaf -:256]=digest_visible ? chain[leaf] : 256'b0;
    end endgenerate

    wire frame_ready,frame_valid,frame_error,frame_last,sha_ready,sha_valid,sha_busy;
    wire [511:0] frame_data;
    wire [15:0] frame_tag,sha_tag;
    wire [255:0] sha_result;
    wire eligible=running && !inflight[scan_node] && !complete[scan_node]
        && (scan_node!=5'd16 || (&complete[15:0]));
    wire launch=alive && eligible && (!stage_valid || frame_ready);
    wire [6:0] scan_block=blocks[scan_node];
    wire [5:0] scan_word=scan_block==0 ? 6'd0 : scan_block[5:0]-6'd1;
    assign buffer_read_enable=launch && scan_node!=5'd16;
    assign buffer_read_word=buffer_read_enable ? {scan_node[3:0],scan_word} : 10'b0;
    wire [2:0] root_word=stage_block==0 ? 3'd0 : stage_block[2:0]-3'd1;
    wire [3:0] d0={root_word,1'b0},d1=d0+4'd1,d2=d0+4'd2,d3=d0+4'd3;
    wire [1023:0] root_pair={chain[{1'b0,d0}],chain[{1'b0,d1}],chain[{1'b0,d2}],chain[{1'b0,d3}]};
    wire [1023:0] payload_pair=stage_node==5'd16 ? root_pair : buffer_read_pair;
    wire frame_take=stage_valid && frame_ready && alive;

    qwen_kv_hash_frame #(.LAYERS(LAYERS),.LAYER_BITS(LAYER_BITS),.MODEL_TAG(MODEL_TAG)) framer(
        .clk(clk),.rst_n(rst_n),.clear(clear || failed),
        .in_valid(stage_valid && alive),.in_ready(frame_ready),.epoch(epoch),.layer(layer),
        .page_group(page_group),.node_index(stage_node),.valid_positions(count),.block_index(stage_block),
        .payload_pair(payload_pair),.in_tag({11'b0,stage_node}),
        .out_valid(frame_valid),.out_ready(sha_ready),.block_data(frame_data),
        .out_last(frame_last),.out_error(frame_error),.out_tag(frame_tag));
    qwen_sha256_pipeline #(.TAG_BITS(16)) sha(
        .clk(clk),.rst_n(rst_n),.clear(clear || failed),
        .in_valid(frame_valid && !frame_error && alive),.in_ready(sha_ready),
        .block_data(frame_data),.initial_state(framed_state),.in_tag(frame_tag),
        .out_valid(sha_valid),.out_ready(alive),.final_state(sha_result),.out_tag(sha_tag),.busy(sha_busy));
    wire [4:0] returned=sha_tag[4:0];
    wire legal_result=running && sha_tag[15:5]==0 && returned<=5'd16
        && inflight[returned] && !complete[returned];
    wire final_block=returned==5'd16 ? blocks[returned]==7'd8 : blocks[returned]==7'd64;
    wire invalid_start=start_valid && start_ready
        && (int'(start_layer)>=LAYERS || start_group>=16'd2048 || start_count==0 || start_count>5'd16);
    wire fault=invalid_start || (alive && frame_valid && frame_error)
        || (alive && sha_valid && !legal_result);
    integer i;
    always @(posedge clk)begin
        if(!rst_n || clear)begin
            running<=0;finished<=0;failed<=0;inflight<=0;complete<=0;stage_valid<=0;scan_node<=0;
            epoch<=0;layer<=0;page_group<=0;count<=0;stage_node<=0;stage_block<=0;
            for(i=0;i<17;i=i+1)blocks[i]<=0;
        end else if(fault)begin
            failed<=1;running<=0;finished<=0;stage_valid<=0;
        end else if(alive)begin
            if(start_valid && start_ready)begin
                epoch<=start_epoch;layer<=start_layer;page_group<=start_group;count<=start_count;
                running<=1;finished<=0;inflight<=0;complete<=0;stage_valid<=0;scan_node<=0;
                for(i=0;i<17;i=i+1)blocks[i]<=0;
            end else begin
                if(running)scan_node<=scan_node==5'd16 ? 5'd0 : scan_node+5'd1;
                if(!stage_valid || frame_ready)stage_valid<=launch;
                if(launch)begin
                    stage_node<=scan_node;stage_block<=scan_block;
                    stage_state<=scan_block==0 ? IV : chain[scan_node];inflight[scan_node]<=1;
                end
                if(frame_take)framed_state<=stage_state;
                if(sha_valid)begin
                    chain[returned]<=sha_result;inflight[returned]<=0;
                    if(final_block)begin
                        complete[returned]<=1;
                        if(returned==5'd16)begin running<=0;finished<=1;end
                    end else blocks[returned]<=blocks[returned]+7'd1;
                end
                if(done_valid && done_ready)finished<=0;
            end
        end
    end
    wire unused_internal=^{sha_busy,frame_last};
endmodule
