// PRIVATE multi-page, verify-before-release model buffer. No application ports.
// The fixed memory controller supplies complete 64-KiB pages; roots and model
// identity are build-time constants. Input byte zero is load_data[7:0].
// Pages are released in submission order, only from the retained private copy.
// Failed verification/transport is sticky until CLEAR/reset; it releases no
// further data. The outer HBM reader must separately drain cancelled bus work
// before reusing this component after CLEAR. This is not that HBM bus adapter.
module qwen_model_page_auth_shared_worker #(
    parameter integer SLOTS=8,
    parameter ROOT_FILE="model-page-roots.hex",
    parameter [255:0] MODEL_TAG=256'h250e021a1e402acc45fa3a4ae7e925a7b5341e82d77ca2d69e4044b8c9b1fce3
) (
    input wire clk,input wire rst_n,input wire clear,
    input wire [255:0] fixed_root_read,
    input wire load_valid,output wire load_ready,input wire [15:0] load_page,
    input wire load_data_valid,output wire load_data_ready,
    input wire [2047:0] load_data,input wire load_last,input wire load_error,
    output wire out_valid,input wire out_ready,output wire [2047:0] out_data,
    output wire [15:0] out_page,output wire out_last,
    output wire error,output wire busy
);
    localparam integer SLOT_BITS=SLOTS>1 ? $clog2(SLOTS) : 1;
    localparam integer CONTEXT_BITS=SLOT_BITS+5;
    localparam integer CONTEXTS=1<<CONTEXT_BITS;
    localparam integer PAGE_ADDRESS_BITS=$clog2(SLOTS*256);
    localparam [255:0] IV=256'h6a09e667bb67ae853c6ef372a54ff53a510e527f9b05688c1f83d9ab5be0cd19;
    initial if(SLOTS!=1 && SLOTS!=2 && SLOTS!=4 && SLOTS!=8 && SLOTS!=16)
        $fatal(1,"Unsupported private model buffer count");
    function automatic [511:0] reverse_bytes(input [511:0] value);
        integer i;
        begin for(i=0;i<64;i=i+1) reverse_bytes[511-i*8 -:8]=value[i*8 +:8];end
    endfunction
    function automatic [SLOT_BITS-1:0] next_slot(input [SLOT_BITS-1:0] value);
        next_slot=value==SLOT_BITS'(SLOTS-1) ? {SLOT_BITS{1'b0}} : value+1'b1;
    endfunction

    // Nonzero configuration-time contents require block RAM: UltraRAM has no
    // user-defined INIT contents (AMD UG573). No runtime root-write port exists.
    // The enclosing PRIVATE wrapper owns the identical immutable ROM read pipeline.
    reg root_lookup_valid;
    reg [SLOT_BITS-1:0] root_lookup_slot;
    wire [255:0] root_lookup_data=fixed_root_read;
    // ROOT_ADDRESS198: a private ROM-address pipeline, not a release gate.
    // Root address is registered once in the enclosing wrapper.
    reg root_commit_valid;
    reg [SLOT_BITS-1:0] root_commit_slot;
    reg failed,loading,io_prefer_write;
    reg [SLOTS-1:0] occupied,filled,verified;
    reg [15:0] page_ids [0:SLOTS-1];
    // PAGE_ID_COMMIT103: private metadata is committed from a registered
    // accepted header. CLEAR may discard that slot while this write completes.
    // No consumer may use it until the unchanged filled/verified guards pass.
    reg [15:0] page_lookup_data;
    always @(posedge clk) begin
        page_lookup_data<=load_page;
        if(root_lookup_valid)page_ids[root_lookup_slot]<=page_lookup_data;
    end
    reg [255:0] expected_roots [0:SLOTS-1];
    reg [SLOT_BITS-1:0] write_slot,read_slot,inject_slot;
    reg [4:0] injected [0:SLOTS-1];
    reg [7:0] load_beat;
    reg [8:0] output_count;
    reg [CONTEXTS-1:0] inflight,complete;
    reg [6:0] blocks [0:CONTEXTS-1];
    (* ram_style="block" *) reg [255:0] chain [0:CONTEXTS-1];
    wire alive=rst_n && !clear && !failed;
    // Registered private cleanup only: immediate error and output rejection
    // below still use fault_event. All privately advanced work is discarded
    // by the existing sticky failure before it can become an output.
    wire fault_event;
    assign load_ready=alive && !loading && !occupied[write_slot];
    wire emit_intent;
    // Loading and verified-output reads share one physical RAM port. Hashing
    // uses the other. Alternate on contention so a run of verified pages cannot
    // starve new hash work, or vice versa. Transport honors backpressure.
    assign load_data_ready=alive && loading && (!emit_intent || io_prefer_write);
    wire load_take=load_valid && load_ready;
    wire data_take=load_data_valid && load_data_ready;
    wire malformed_header=load_take && load_page>=16'd35925;
    wire malformed_data=alive && (load_data_valid && !loading
        || data_take && (load_error || load_last!=(load_beat==8'd255)));
    // Dedicated synchronous ROM read, followed by a private slot register.
    // Keeping this separate avoids inferring an asynchronous ROM read feeding
    // several independently enabled slot registers.
    // ROOT_READ140: this register is private, not an authenticated output.
    // Only the unchanged accepted-header valid/slot control can commit it.
    // Invalid addresses may refresh invalid lookup bits; they cannot commit.
    // Unconditional address/read registers are shared; accepted-header commit stays local.

    // A ready-job FIFO interleaves independent leaves and roots. A returned
    // chaining state is requeued immediately instead of waiting for a sweep
    // across empty/busy contexts. Two enqueue banks admit a continuation and
    // a new leaf together; the hash pipeline still consumes one job per clock.
    reg [CONTEXT_BITS-1:0] queue_read_pointer,queue_write_pointer;
    reg [CONTEXT_BITS:0] queue_count;
    reg queue_head_valid,queue_head_bank;
    wire [CONTEXT_BITS+6:0] queue_bank_read [0:1];
    wire [CONTEXT_BITS-1:0] scan_context=queue_bank_read[queue_head_bank][CONTEXT_BITS-1:0];
    wire [SLOT_BITS-1:0] scan_slot=scan_context[CONTEXT_BITS-1:5];
    wire [4:0] scan_node=scan_context[4:0];
    wire scan_root=scan_node==5'd16;
    wire [6:0] scan_block=queue_bank_read[queue_head_bank][CONTEXT_BITS +: 7];
    // MODEL_JOB_GUARD203: the same predicate, factored by constant slot.
    // No failure is delayed and no authentication/release condition is removed.
    wire [16:0] selected_job_node;
    wire [SLOTS-1:0] legal_job_slot;
    genvar job_node,job_slot;
    generate
        for(job_node=0;job_node<17;job_node=job_node+1) begin:job_node_decode
            assign selected_job_node[job_node]=scan_node==5'(job_node);
        end
        for(job_slot=0;job_slot<SLOTS;job_slot=job_slot+1) begin:job_slot_guard
            wire [16:0] available_nodes=~complete[32*job_slot +:17] & ~inflight[32*job_slot +:17];
            wire root_ready=&complete[32*job_slot +:16];
            wire [16:0] qualified_nodes=available_nodes & {root_ready,16'hffff};
            assign legal_job_slot[job_slot]=scan_slot==SLOT_BITS'(job_slot)
                && filled[job_slot] && !verified[job_slot]
                && (|(selected_job_node & qualified_nodes));
        end
    endgenerate
    wire job_legal=|legal_job_slot;
    wire eligible=queue_head_valid && job_legal;
    reg stage_valid,stage_root;
    reg [3:0] stage_leaf;
    reg [6:0] stage_block;
    reg [15:0] stage_page,stage_tag;
    reg [255:0] stage_state,framed_state;
    wire frame_ready,frame_valid,frame_error,frame_last,sha_ready,sha_valid,sha_busy;
    wire [511:0] frame_data;
    wire [15:0] frame_tag,sha_tag;
    wire [255:0] sha_result;
    wire advance_stage=alive && (!stage_valid || frame_ready);
    wire launch=advance_stage && eligible;
    wire frame_take=stage_valid && frame_ready && alive;
    wire [CONTEXT_BITS-1:0] result_context=sha_tag[CONTEXT_BITS-1:0];
    wire [SLOT_BITS-1:0] result_slot=sha_tag[CONTEXT_BITS-1:5];
    wire [4:0] result_node=sha_tag[4:0];
    wire result_root=result_node==16;
    wire result_final=result_root ? blocks[result_context]==8 : blocks[result_context]==64;
    wire result_legal=sha_tag[15:CONTEXT_BITS]==0 && int'(result_slot)<SLOTS
        && result_node<=16 && inflight[result_context] && filled[result_slot];
    wire result_take=sha_valid && alive;
    wire root_mismatch=result_take && result_legal && result_root && result_final
        && sha_result!=expected_roots[result_slot];
    wire final_leaf=result_take && result_legal && result_final && !result_root
        && ((complete[32*result_slot +:16] | (16'b1<<result_node[3:0]))==16'hffff);
    wire requeue=result_take && result_legal && (!result_final || final_leaf);
    wire inject=alive && filled[inject_slot] && injected[inject_slot]<16;
    wire [CONTEXT_BITS-1:0] injected_context={inject_slot,1'b0,injected[inject_slot][3:0]};
    wire [CONTEXT_BITS-1:0] returned_context=final_leaf ? {result_slot,5'd16} : result_context;
    wire [1:0] enqueue_count={1'b0,requeue}+{1'b0,inject};
    wire [CONTEXT_BITS-1:0] enqueue_first=requeue ? returned_context : injected_context;
    // Private next-job metadata: new leaf/root jobs start at block zero.
    // A continuation snapshots the same increment committed below.
    wire [6:0] enqueue_first_block=requeue && !final_leaf
        ? blocks[result_context]+7'd1 : 7'd0;
    wire [CONTEXT_BITS-1:0] second_write_pointer=queue_write_pointer+1'b1;
    wire queue_overflow=(int'(queue_count)+int'(enqueue_count))>CONTEXTS;
    wire advance_head=alive && (!queue_head_valid || launch);
    wire fetch_head=advance_head && queue_count!=0;
    assign fault_event=malformed_header || malformed_data || (alive && frame_valid && frame_error)
        || (result_take && !result_legal) || root_mismatch
        || (alive && (queue_overflow || (queue_head_valid && !job_legal)));
    assign error=rst_n && !clear && (failed || fault_event);

    wire [2047:0] page_read,output_read;
    wire [1023:0] digest_read;
    wire [5:0] scan_word=scan_block==0 ? 6'd0 : scan_block[5:0]-6'd1;
    wire [5:0] stage_word=stage_block==0 ? 6'd0 : stage_block[5:0]-6'd1;
    wire [1:0] stage_bank=stage_word[1:0],stage_next_bank=stage_bank+2'd1;
    wire [511:0] payload_first=page_read[stage_bank*512 +:512];
    wire [511:0] payload_second=page_read[stage_next_bank*512 +:512];
    wire [1023:0] root_pair=stage_word[0]
        ? {digest_read[767:512],digest_read[1023:768],digest_read[255:0],digest_read[511:256]}
        : {digest_read[255:0],digest_read[511:256],digest_read[767:512],digest_read[1023:768]};
    wire [1023:0] payload_pair=stage_root ? root_pair : {payload_first,payload_second};

    qwen_model_hash_frame #(.MODEL_TAG(MODEL_TAG)) framer(
        .clk(clk),.rst_n(rst_n),.clear(clear || failed),
        .in_valid(stage_valid && alive),.in_ready(frame_ready),.root_mode(stage_root),
        .page_index(stage_page),.leaf_index(stage_leaf),.block_index(stage_block),
        .payload_pair(payload_pair),.in_tag(stage_tag),
        .out_valid(frame_valid),.out_ready(sha_ready),.block_data(frame_data),
        .out_last(frame_last),.out_error(frame_error),.out_tag(frame_tag));
    qwen_sha256_pipeline #(.TAG_BITS(16)) sha(
        .clk(clk),.rst_n(rst_n),.clear(clear || failed),
        .in_valid(frame_valid && !frame_error && alive),.in_ready(sha_ready),
        .block_data(frame_data),.initial_state(framed_state),.in_tag(frame_tag),
        .out_valid(sha_valid),.out_ready(alive),.final_state(sha_result),.out_tag(sha_tag),.busy(sha_busy));

    reg output_valid;
    reg [SLOT_BITS-1:0] output_slot;
    reg [7:0] output_beat;
    assign out_valid=alive && !fault_event && output_valid;
    assign out_last=output_beat==8'd255;
    assign out_page=page_ids[output_slot];
    wire output_take=out_valid && out_ready;
    wire advance_output=alive && (!output_valid || out_ready);
    assign emit_intent=advance_output && occupied[read_slot] && verified[read_slot] && output_count<9'd256;
    wire io_contention=emit_intent && loading && load_data_valid;
    wire emit=emit_intent && !(loading && load_data_valid && io_prefer_write);
    assign busy=alive && ((|occupied) || loading || stage_valid || frame_valid || sha_busy || output_valid
        || queue_head_valid || queue_count!=0);

    genvar queue_bank;
    generate for(queue_bank=0;queue_bank<2;queue_bank=queue_bank+1) begin:ready_queue
        (* ram_style="block" *) reg [CONTEXT_BITS+6:0] entries [0:CONTEXTS/2-1];
        reg [CONTEXT_BITS+6:0] read_data;
        wire first_write=enqueue_count!=0 && queue_write_pointer[0]==1'(queue_bank);
        wire second_write=enqueue_count==2 && second_write_pointer[0]==1'(queue_bank);
        wire [CONTEXT_BITS-2:0] write_address=first_write
            ? queue_write_pointer[CONTEXT_BITS-1:1] : second_write_pointer[CONTEXT_BITS-1:1];
        always @(posedge clk) begin
            if(alive && (first_write || second_write))
                entries[write_address]<=first_write ? {enqueue_first_block,enqueue_first}
                    : {7'd0,injected_context};
            if(fetch_head) read_data<=entries[queue_read_pointer[CONTEXT_BITS-1:1]];
        end
        assign queue_bank_read[queue_bank]=read_data;
    end endgenerate

    // Four deep, 64-byte-wide banks hold ALL page slots. Port A alternates
    // between loading and verified output; port B reads hash operands. This
    // avoids both three-port RAM inference and shallow per-page RAM waste.
    // No RAM contents are reset, and a filled page cannot be loaded again.
    genvar bank;
    generate for(bank=0;bank<4;bank=bank+1) begin:banks
        wire [511:0] read_data,output_data;
        wire hash_read=launch && !scan_root;
        wire [7:0] hash_row={scan_node[3:0],scan_word[5:2]}
            + (bank==0 && scan_word[1:0]==3 ? 8'd1 : 8'd0);
        wire [PAGE_ADDRESS_BITS-1:0] hash_address=PAGE_ADDRESS_BITS'({scan_slot,hash_row});
        wire [PAGE_ADDRESS_BITS-1:0] io_address=data_take
            ? PAGE_ADDRESS_BITS'({write_slot,load_beat}) : PAGE_ADDRESS_BITS'({read_slot,output_count[7:0]});
        (* keep_hierarchy="yes" *) qwen_auth_private_payload_ram #(.SLOTS(SLOTS)) payload_ram (
            .clk(clk),.io_enable(data_take || emit),.io_write(data_take),
            .io_address(io_address),.write_data(reverse_bytes(load_data[bank*512 +:512])),
            .hash_read(hash_read),.hash_address(hash_address),
            .output_data(output_data),.read_data(read_data));
        assign page_read[bank*512 +:512]=read_data;
        assign output_read[bank*512 +:512]=output_data;
        reg [255:0] digests [0:SLOTS*4-1];
        reg [255:0] digest_data;
        wire [1:0] digest_row=scan_word[2:1]+(bank<2 && scan_word[0] ? 2'd1 : 2'd0);
        wire [$clog2(SLOTS*4)-1:0] digest_address=$clog2(SLOTS*4)'({scan_slot,digest_row});
        wire [$clog2(SLOTS*4)-1:0] digest_write=$clog2(SLOTS*4)'({result_slot,result_node[3:2]});
        always @(posedge clk) begin
            if(result_take && result_legal && !result_root && result_final && result_node[1:0]==2'(bank))
                digests[digest_write]<=sha_result;
            if(launch && scan_root) digest_data<=digests[digest_address];
        end
        assign digest_read[bank*256 +:256]=digest_data;
    end
    for(bank=0;bank<4;bank=bank+1) begin:output_bytes
        assign out_data[bank*512 +:512]=reverse_bytes(output_read[bank*512 +:512]);
    end endgenerate

    integer i;
    always @(posedge clk) begin
        if(!rst_n || clear) failed<=0;
        else if(fault_event) failed<=1;
        if(!alive) begin
            occupied<=0;filled<=0;verified<=0;loading<=0;io_prefer_write<=1;
            write_slot<=0;read_slot<=0;inject_slot<=0;load_beat<=0;
            inflight<=0;complete<=0;stage_valid<=0;output_valid<=0;output_count<=0;
            root_lookup_valid<=0;root_commit_valid<=0;
            queue_head_valid<=0;queue_head_bank<=0;queue_read_pointer<=0;queue_write_pointer<=0;queue_count<=0;
            for(i=0;i<CONTEXTS;i=i+1) blocks[i]<=0;
            for(i=0;i<SLOTS;i=i+1) injected[i]<=0;
        end else begin
            if(io_contention) io_prefer_write<=!data_take;
            root_lookup_valid<=load_take;
            root_commit_valid<=root_lookup_valid;
            root_commit_slot<=root_lookup_slot;
            if(root_commit_valid) expected_roots[root_commit_slot]<=root_lookup_data;
            if(load_take) begin
                occupied[write_slot]<=1;filled[write_slot]<=0;verified[write_slot]<=0;
                root_lookup_slot<=write_slot;
                loading<=1;load_beat<=0;injected[write_slot]<=0;
                for(i=0;i<17;i=i+1) begin
                    blocks[32*write_slot+i]<=0;inflight[32*write_slot+i]<=0;complete[32*write_slot+i]<=0;
                end
            end
            if(data_take) begin
                load_beat<=load_beat+1'b1;
                if(load_beat==8'd255) begin
                    filled[write_slot]<=1;loading<=0;write_slot<=next_slot(write_slot);
                end
            end
            if(inject) begin
                injected[inject_slot]<=injected[inject_slot]+1'b1;
                if(injected[inject_slot]==15) inject_slot<=next_slot(inject_slot);
            end else inject_slot<=next_slot(inject_slot);
            queue_count<=queue_count+(CONTEXT_BITS+1)'(enqueue_count)-(CONTEXT_BITS+1)'(fetch_head);
            queue_write_pointer<=queue_write_pointer+CONTEXT_BITS'(enqueue_count);
            if(advance_head) queue_head_valid<=fetch_head;
            if(fetch_head) begin
                queue_head_bank<=queue_read_pointer[0];queue_read_pointer<=queue_read_pointer+1'b1;
            end
            if(advance_stage) begin
                stage_valid<=eligible;
                if(launch) begin
                    stage_root<=scan_root;stage_leaf<=scan_root ? 4'b0 : scan_node[3:0];
                    stage_page<=page_ids[scan_slot];stage_block<=scan_block;
                    stage_tag<={{(16-CONTEXT_BITS){1'b0}},scan_context};
                    stage_state<=scan_block==0 ? IV : chain[scan_context];
                    inflight[scan_context]<=1;
                end
            end
            if(frame_take) framed_state<=stage_state;
            if(result_take) begin
                chain[result_context]<=sha_result;inflight[result_context]<=0;
                if(result_final) begin
                    complete[result_context]<=1;
                    if(result_root) verified[result_slot]<=1;
                end else blocks[result_context]<=blocks[result_context]+1'b1;
            end
            if(advance_output) begin
                output_valid<=emit;
                if(emit) begin
                    output_slot<=read_slot;output_beat<=output_count[7:0];output_count<=output_count+1'b1;
                end
            end
            if(output_take && out_last) begin
                occupied[output_slot]<=0;filled[output_slot]<=0;verified[output_slot]<=0;
                read_slot<=next_slot(read_slot);output_count<=0;
            end
        end
    end
endmodule

// Fixed private verifier storage; this is not an application-accessible port.
// A filled slot is never loaded again while either read port can consume it.
(* keep_hierarchy="yes" *) module qwen_auth_private_payload_ram #(
    parameter integer SLOTS=8,
    parameter integer ADDRESS_BITS=$clog2(SLOTS*256)
) (
    input wire clk,io_enable,io_write,hash_read,
    input wire [ADDRESS_BITS-1:0] io_address,hash_address,
    input wire [511:0] write_data,
    output reg [511:0] output_data,read_data
);
    (* ram_style="ultra" *) reg [511:0] memory [0:SLOTS*256-1];
    always @(posedge clk) begin
        if(io_enable) begin
            if(io_write) memory[io_address]<=write_data;
            else output_data<=memory[io_address];
        end
    end
    always @(posedge clk) begin
        if(hash_read) read_data<=memory[hash_address];
    end
endmodule
