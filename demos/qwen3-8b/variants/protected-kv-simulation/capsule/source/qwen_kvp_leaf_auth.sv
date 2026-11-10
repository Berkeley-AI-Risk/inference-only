// PRIVATE retained-leaf verifier for attention. Not a host memory/hash API.
// Derived from qwen_kv_leaf_auth.sv (sha256 8cd35de6b77a58db...). Changes: compile-
// time ZERO_WHEN_INVALID following the released qwen_model_page_auth (out_valid
// is unchanged and is the only release decision), and out_present, which the
// reader uses for its registered-only response checks. out_present never
// authorizes a cache fill: the fill still requires out_valid.
//
// A trusted root-owner lookup supplies epoch/layer/group/count/root. The fixed
// reader supplies one head/kind node and loads 16 payload beats followed by two
// manifest beats, each 256 bytes with byte zero at [7:0]. This component first
// authenticates the retained manifest, then the retained leaf. Only those same
// retained bytes are emitted, in submission order, after both checks pass.
//
// Output always contains all 16 vectors of the leaf, including padding. The
// private reader must use out_count to reject requests beyond the committed
// prefix. It must also bind its cache to the returned identity, serialize reads
// against writer updates, and drain old transport work before reusing after
// CLEAR/reset. Those ownership/transport duties are NOT implemented here.
module qwen_kvp_leaf_auth #(
    parameter integer SLOTS=128,
    parameter integer LAYERS=28,
    parameter integer LAYER_BITS=$clog2(LAYERS),
    parameter [255:0] MODEL_TAG=256'h250e021a1e402acc45fa3a4ae7e925a7b5341e82d77ca2d69e4044b8c9b1fce3,
    parameter integer ZERO_WHEN_INVALID=1
) (
    input wire clk,input wire rst_n,input wire clear,
    input wire load_valid,output wire load_ready,
    input wire [63:0] load_epoch,input wire [LAYER_BITS-1:0] load_layer,
    input wire [15:0] load_group,input wire [4:0] load_node,input wire [4:0] load_count,
    input wire [255:0] load_root,
    input wire load_data_valid,output wire load_data_ready,
    input wire [2047:0] load_data,input wire load_last,input wire load_error,
    output wire out_valid,output wire out_present,input wire out_ready,output wire [2047:0] out_data,
    output wire [63:0] out_epoch,output wire [LAYER_BITS-1:0] out_layer,
    output wire [15:0] out_group,output wire [4:0] out_node,output wire [4:0] out_count,
    output wire [3:0] out_vector,output wire out_last,
    output wire error,output wire busy
);
    localparam integer SLOT_BITS=$clog2(SLOTS);
    localparam [255:0] IV=256'h6a09e667bb67ae853c6ef372a54ff53a510e527f9b05688c1f83d9ab5be0cd19;
    initial if(SLOTS!=4 && SLOTS!=8 && SLOTS!=16 && SLOTS!=32 && SLOTS!=64 && SLOTS!=128)
        $fatal(1,"Unsupported private K/V leaf-buffer count");
    initial if(ZERO_WHEN_INVALID!=0 && ZERO_WHEN_INVALID!=1)
        $fatal(1,"Invalid private K/V verifier payload setting");
    function automatic [511:0] reverse64(input [511:0] value);
        integer i;
        begin for(i=0;i<64;i=i+1)reverse64[511-i*8 -:8]=value[i*8 +:8];end
    endfunction
    function automatic [255:0] reverse32(input [255:0] value);
        integer i;
        begin for(i=0;i<32;i=i+1)reverse32[255-i*8 -:8]=value[i*8 +:8];end
    endfunction
    reg failed,loading,io_prefer_write;
    reg [SLOTS-1:0] occupied,filled,verified,leaf_phase,inflight;
    reg [63:0] epochs [0:SLOTS-1];
    reg [LAYER_BITS-1:0] layers [0:SLOTS-1];
    reg [4:0] nodes [0:SLOTS-1],counts [0:SLOTS-1];
    reg [15:0] groups [0:SLOTS-1];
    reg [255:0] expected_roots [0:SLOTS-1],expected_leaves [0:SLOTS-1];
    reg [255:0] chain [0:SLOTS-1];
    reg [6:0] blocks [0:SLOTS-1];
    reg [SLOT_BITS-1:0] write_slot,read_slot;
    reg [4:0] load_beat,output_count;
    wire alive=rst_n && !clear && !failed;
    wire fault_event,emit_intent;
    assign load_ready=alive && !loading && !occupied[write_slot];
    // Payload loading and verified output share one RAM port. Manifest loading
    // has separate RAM and can overlap output; hashing uses a second RAM port.
    assign load_data_ready=alive && loading
        && (load_beat[4] || !emit_intent || io_prefer_write);
    wire load_take=load_valid && load_ready;
    wire data_take=load_data_valid && load_data_ready;
    wire payload_write=data_take && !load_beat[4];
    wire malformed_header=load_take && (int'(load_layer)>=LAYERS || load_group>=16'd2048
        || load_node>=5'd16 || load_count==0 || load_count>5'd16);
    wire malformed_data=alive && (load_data_valid && !loading
        || data_take && (load_error || load_last!=(load_beat==5'd17)));

    // At most one hash job is outstanding per leaf slot. A two-bank FIFO can
    // enqueue a returning chain and a newly loaded leaf on the same clock.
    reg [SLOT_BITS-1:0] queue_read_pointer,queue_write_pointer;
    reg [SLOT_BITS:0] queue_count;
    reg queue_head_valid,queue_head_bank;
    wire [SLOT_BITS-1:0] queue_bank_read [0:1];
    wire [SLOT_BITS-1:0] scan_slot=queue_bank_read[queue_head_bank];
    wire scan_root=!leaf_phase[scan_slot];
    wire [6:0] scan_block=blocks[scan_slot];
    wire job_legal=filled[scan_slot] && occupied[scan_slot]
        && !verified[scan_slot] && !inflight[scan_slot];
    wire eligible=queue_head_valid && job_legal;
    reg stage_valid;
    reg [63:0] stage_epoch;
    reg [LAYER_BITS-1:0] stage_layer;
    reg [4:0] stage_node,stage_count;
    reg [15:0] stage_group,stage_tag;
    reg [6:0] stage_block;
    reg [255:0] stage_state,framed_state;
    wire frame_ready,frame_valid,frame_error,frame_last,sha_ready,sha_valid,sha_busy;
    wire [511:0] frame_data;
    wire [15:0] frame_tag,sha_tag;
    wire [255:0] sha_result;
    wire advance_stage=alive && (!stage_valid || frame_ready);
    wire launch=advance_stage && eligible && !fault_event;
    wire frame_take=stage_valid && frame_ready && alive;
    wire [SLOT_BITS-1:0] result_slot=sha_tag[SLOT_BITS-1:0];
    wire result_root=!leaf_phase[result_slot];
    wire result_final=result_root ? blocks[result_slot]==7'd8 : blocks[result_slot]==7'd64;
    wire result_legal=sha_tag[15:SLOT_BITS]==0 && inflight[result_slot]
        && filled[result_slot] && occupied[result_slot] && !verified[result_slot];
    wire result_take=sha_valid && alive;
    wire mismatch=result_take && result_legal && result_final
        && sha_result!=(result_root ? expected_roots[result_slot] : expected_leaves[result_slot]);
    wire requeue=result_take && result_legal && (!result_final || result_root);
    wire inject=data_take && load_beat==5'd17;
    wire [1:0] enqueue_count={1'b0,requeue}+{1'b0,inject};
    wire [SLOT_BITS-1:0] enqueue_first=requeue ? result_slot : write_slot;
    wire [SLOT_BITS-1:0] second_write_pointer=queue_write_pointer+1'b1;
    wire queue_overflow=(int'(queue_count)+int'(enqueue_count))>SLOTS;
    wire advance_head=alive && (!queue_head_valid || launch);
    wire fetch_head=advance_head && queue_count!=0 && !fault_event;
    assign fault_event=malformed_header || malformed_data || (alive && frame_valid && frame_error)
        || (result_take && !result_legal) || mismatch
        || (alive && (queue_overflow || (queue_head_valid && !job_legal)));
    // Latch failure before reporting it to avoid a request/error-mask feedback
    // path in the caller. An output is suppressed on the detecting cycle too.
    assign error=rst_n && !clear && failed;

    wire [2047:0] payload_read,manifest_read,output_read;
    wire [5:0] scan_word=scan_block==0 ? 6'd0 : scan_block[5:0]-6'd1;
    wire [5:0] stage_word=stage_block==0 ? 6'd0 : stage_block[5:0]-6'd1;
    wire [1:0] stage_bank=stage_word[1:0],stage_next_bank=stage_bank+2'd1;
    wire [2047:0] selected_read=stage_node==5'd16 ? manifest_read : payload_read;
    wire [1023:0] hash_pair={selected_read[stage_bank*512 +:512],selected_read[stage_next_bank*512 +:512]};
    qwen_kv_hash_frame #(.LAYERS(LAYERS),.LAYER_BITS(LAYER_BITS),.MODEL_TAG(MODEL_TAG)) framer(
        .clk(clk),.rst_n(rst_n),.clear(clear || failed),
        .in_valid(stage_valid && alive),.in_ready(frame_ready),.epoch(stage_epoch),.layer(stage_layer),
        .page_group(stage_group),.node_index(stage_node),.valid_positions(stage_count),.block_index(stage_block),
        .payload_pair(hash_pair),.in_tag(stage_tag),
        .out_valid(frame_valid),.out_ready(sha_ready),.block_data(frame_data),
        .out_last(frame_last),.out_error(frame_error),.out_tag(frame_tag));
    qwen_sha256_pipeline #(.TAG_BITS(16)) sha(
        .clk(clk),.rst_n(rst_n),.clear(clear || failed),
        .in_valid(frame_valid && !frame_error && alive),.in_ready(sha_ready),
        .block_data(frame_data),.initial_state(framed_state),.in_tag(frame_tag),
        .out_valid(sha_valid),.out_ready(alive),.final_state(sha_result),.out_tag(sha_tag),.busy(sha_busy));

    reg output_valid;
    reg [SLOT_BITS-1:0] output_slot;
    reg [3:0] output_beat;
    assign out_valid=alive && !fault_event && output_valid;
    // A retained verified beat exists. Register-only; excludes this module's
    // same-cycle hash comparison. Only out_valid releases the beat.
    assign out_present=alive && output_valid;
    wire out_visible=ZERO_WHEN_INVALID==0 || out_valid;
    assign out_last=out_visible && output_beat==4'd15;
    assign out_vector=out_visible ? output_beat : 4'b0;
    assign out_epoch=out_visible ? epochs[output_slot] : 64'b0;
    assign out_layer=out_visible ? layers[output_slot] : {LAYER_BITS{1'b0}};
    assign out_group=out_visible ? groups[output_slot] : 16'b0;
    assign out_node=out_visible ? nodes[output_slot] : 5'b0;
    assign out_count=out_visible ? counts[output_slot] : 5'b0;
    wire output_take=out_valid && out_ready;
    wire advance_output=alive && (!output_valid || out_ready);
    assign emit_intent=advance_output && occupied[read_slot] && verified[read_slot] && output_count<5'd16;
    wire io_contention=emit_intent && loading && !load_beat[4] && load_data_valid;
    wire emit=emit_intent && !(loading && !load_beat[4] && load_data_valid && io_prefer_write) && !fault_event;
    assign busy=alive && ((|occupied) || loading || stage_valid || frame_valid || sha_busy || output_valid
        || queue_head_valid || queue_count!=0);

    genvar bank;
    generate for(bank=0;bank<2;bank=bank+1)begin:ready_queue
        (* ram_style="block" *) reg [SLOT_BITS-1:0] entries [0:SLOTS/2-1];
        reg [SLOT_BITS-1:0] read_data;
        wire first_write=enqueue_count!=0 && queue_write_pointer[0]==1'(bank);
        wire second_write=enqueue_count==2 && second_write_pointer[0]==1'(bank);
        wire [SLOT_BITS-2:0] address=first_write
            ? queue_write_pointer[SLOT_BITS-1:1] : second_write_pointer[SLOT_BITS-1:1];
        always @(posedge clk)begin
            if(alive && !fault_event && (first_write || second_write))
                entries[address]<=first_write ? enqueue_first : write_slot;
            if(fetch_head && queue_read_pointer[0]==1'(bank))
                read_data<=entries[queue_read_pointer[SLOT_BITS-1:1]];
        end
        assign queue_bank_read[bank]=read_data;
    end
    for(bank=0;bank<4;bank=bank+1)begin:retained_words
        (* ram_style="block" *) reg [511:0] payload [0:SLOTS*16-1];
        (* ram_style="block" *) reg [511:0] manifests [0:SLOTS*2-1];
        reg [511:0] hash_payload,hash_manifest,output_data;
        wire [3:0] payload_row=scan_word[5:2]+(bank==0 && scan_word[1:0]==3 ? 4'd1 : 4'd0);
        wire manifest_row=scan_word[2]^(bank==0 && scan_word[1:0]==3);
        wire [SLOT_BITS+3:0] payload_address=payload_write
            ? {write_slot,load_beat[3:0]} : {read_slot,output_count[3:0]};
        always @(posedge clk)begin
            if(payload_write && !fault_event)payload[payload_address]<=reverse64(load_data[bank*512 +:512]);
            if(emit)output_data<=payload[payload_address];
            if(data_take && load_beat[4] && !fault_event)
                manifests[{write_slot,load_beat[0]}]<=reverse64(load_data[bank*512 +:512]);
            if(launch && !scan_root)hash_payload<=payload[{scan_slot,payload_row}];
            if(launch && scan_root)hash_manifest<=manifests[{scan_slot,manifest_row}];
        end
        assign payload_read[bank*512 +:512]=hash_payload;
        assign manifest_read[bank*512 +:512]=hash_manifest;
        assign output_read[bank*512 +:512]=output_data;
        assign out_data[bank*512 +:512]=out_visible ? reverse64(output_read[bank*512 +:512]) : 512'b0;
    end endgenerate

    integer i;
    always @(posedge clk)begin
        if(!rst_n || clear)failed<=0;
        else if(fault_event)failed<=1;
        if(!alive || fault_event)begin
            occupied<=0;filled<=0;verified<=0;leaf_phase<=0;inflight<=0;
            loading<=0;io_prefer_write<=1;write_slot<=0;read_slot<=0;load_beat<=0;
            stage_valid<=0;output_valid<=0;output_count<=0;
            queue_head_valid<=0;queue_head_bank<=0;queue_read_pointer<=0;queue_write_pointer<=0;queue_count<=0;
            for(i=0;i<SLOTS;i=i+1)blocks[i]<=0;
        end else begin
            if(io_contention)io_prefer_write<=!payload_write;
            if(load_take)begin
                occupied[write_slot]<=1;filled[write_slot]<=0;verified[write_slot]<=0;
                leaf_phase[write_slot]<=0;inflight[write_slot]<=0;blocks[write_slot]<=0;
                epochs[write_slot]<=load_epoch;layers[write_slot]<=load_layer;groups[write_slot]<=load_group;
                nodes[write_slot]<=load_node;counts[write_slot]<=load_count;expected_roots[write_slot]<=load_root;
                loading<=1;load_beat<=0;
            end
            if(data_take)begin
                load_beat<=load_beat+5'd1;
                if(load_beat[4] && load_beat[0]==nodes[write_slot][3])
                    expected_leaves[write_slot]<=reverse32(load_data[nodes[write_slot][2:0]*256 +:256]);
                if(load_beat==5'd17)begin
                    filled[write_slot]<=1;loading<=0;write_slot<=write_slot+1'b1;
                end
            end
            queue_count<=queue_count+(SLOT_BITS+1)'(enqueue_count)-(SLOT_BITS+1)'(fetch_head);
            queue_write_pointer<=queue_write_pointer+SLOT_BITS'(enqueue_count);
            if(advance_head)queue_head_valid<=fetch_head;
            if(fetch_head)begin queue_head_bank<=queue_read_pointer[0];queue_read_pointer<=queue_read_pointer+1'b1;end
            if(advance_stage)begin
                stage_valid<=eligible;
                if(launch)begin
                    stage_epoch<=epochs[scan_slot];stage_layer<=layers[scan_slot];stage_group<=groups[scan_slot];
                    stage_node<=scan_root ? 5'd16 : nodes[scan_slot];stage_count<=counts[scan_slot];
                    stage_block<=scan_block;stage_tag<={{(16-SLOT_BITS){1'b0}},scan_slot};
                    stage_state<=scan_block==0 ? IV : chain[scan_slot];inflight[scan_slot]<=1;
                end
            end
            if(frame_take)framed_state<=stage_state;
            if(result_take)begin
                chain[result_slot]<=sha_result;inflight[result_slot]<=0;
                if(result_final)begin
                    if(result_root)begin leaf_phase[result_slot]<=1;blocks[result_slot]<=0;end
                    else verified[result_slot]<=1;
                end else blocks[result_slot]<=blocks[result_slot]+7'd1;
            end
            if(advance_output)begin
                output_valid<=emit;
                if(emit)begin output_slot<=read_slot;output_beat<=output_count[3:0];output_count<=output_count+5'd1;end
            end
            if(output_take && out_last)begin
                occupied[output_slot]<=0;filled[output_slot]<=0;verified[output_slot]<=0;
                read_slot<=read_slot+1'b1;output_count<=0;
            end
        end
    end
    wire unused_internal=^{sha_busy,frame_last};
endmodule
