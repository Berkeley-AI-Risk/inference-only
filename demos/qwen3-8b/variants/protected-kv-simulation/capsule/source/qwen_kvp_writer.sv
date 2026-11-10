// PRIVATE K/V update path: ordered roots + retained page + hash-before-edit.
// Derived from qwen_kv_writer.sv (sha256 1e137cea689e30fa...). Changes: the trusted
// owner moved out to kvi_root_owner (ports below, connected only inside
// qwen_kvp_store); update_active added; address map moved to qwen_kvp_address;
// ZERO_WHEN_INVALID passed to the page hash. The update FSM and every check are
// unchanged. update_active matches the plain writer's whole-update reader hold.
//
// The numerical core supplies exactly K[0..1023], then V[0..1023], at the next
// fixed layer/position. These ports are NOT an application memory/write API.
//
// Raw transport is a private, single-outstanding command stream. A read returns
// 256 256-byte beats. A write returns exactly one completion AFTER all accepted
// data is complete and visible to subsequent reads. A successful completion is not
// merely enqueue acceptance. raw_quiescent/reader_quiescent during cancellation
// mean old work can no longer modify memory or produce a response. No host can
// supply these acknowledgements in the final integration.
module qwen_kvp_writer #(
    parameter integer LAYERS=28,
    parameter integer LAYER_BITS=$clog2(LAYERS),
    parameter [255:0] MODEL_TAG=256'h250e021a1e402acc45fa3a4ae7e925a7b5341e82d77ca2d69e4044b8c9b1fce3,
    parameter [33:0] PAYLOAD_BASE=34'd4294967296,
    parameter [33:0] DIGEST_BASE=34'd8589934592,
    parameter integer ZERO_WHEN_INVALID=1
) (
    input wire clk,input wire rst_n,input wire clear,
    input wire write_start_valid,output wire write_start_ready,
    input wire [LAYER_BITS-1:0] write_layer,input wire [14:0] write_position,
    input wire write_valid,output wire write_ready,
    input wire write_value,input wire [9:0] write_index,input wire [15:0] write_data,
    output wire write_done_valid,input wire write_done_ready,output wire write_done_error,
    output wire error,output wire quiescent,

    output wire update_active,
    input wire reader_fault,input wire reader_quiescent,output wire reader_abort,

    output wire owner_external_fault,output wire owner_transport_quiescent,
    input wire owner_abort,input wire owner_quiescent,input wire owner_error,
    output wire owner_begin_valid,input wire owner_begin_ready,
    output wire [LAYER_BITS-1:0] owner_begin_layer,output wire [15:0] owner_begin_position,
    input wire owner_metadata_valid,output wire owner_metadata_ready,
    input wire [63:0] owner_epoch,input wire [LAYER_BITS-1:0] owner_layer,
    input wire [15:0] owner_position,input wire [4:0] owner_count,input wire [255:0] owner_root,
    output wire owner_commit_valid,input wire owner_commit_ready,
    output wire [63:0] owner_commit_epoch,output wire [LAYER_BITS-1:0] owner_commit_layer,
    output wire [15:0] owner_commit_position,output wire [255:0] owner_commit_root,
    input wire owner_published_valid,output wire owner_published_ready,

    output wire raw_request_valid,input wire raw_request_ready,output wire raw_request_write,
    output wire [33:0] raw_address,output wire [16:0] raw_bytes,
    input wire raw_read_valid,output wire raw_read_ready,input wire [2047:0] raw_read_data,
    input wire raw_read_last,input wire raw_read_error,
    output wire raw_write_valid,input wire raw_write_ready,output wire [2047:0] raw_write_data,
    output wire raw_write_last,input wire raw_done_valid,output wire raw_done_ready,input wire raw_done_error,
    input wire raw_error,output wire raw_abort,input wire raw_quiescent
);
    localparam [4:0] IDLE=0,META=1,ZERO_PAGE=2,READ_REQUEST=3,READ_PAGE=4,
        OLD_START=5,OLD_HASH=6,GATHER=7,NEW_START=8,NEW_HASH=9,
        PAGE_REQUEST=10,PAGE_WRITE=11,PAGE_ACK=12,MANIFEST_REQUEST=13,
        MANIFEST_WRITE=14,MANIFEST_ACK=15,PUBLISH=16,PUBLISH_ACK=17,COMPLETE=18;
    reg [4:0] state;
    reg failed;
    reg [LAYER_BITS-1:0] layer;
    reg [4:0] old_count;
    reg [14:0] position;
    reg [63:0] epoch;
    reg [255:0] old_root,new_root;
    reg [4095:0] manifest_data;
    reg [7:0] beat;
    reg [10:0] vector_index;
    reg [8:0] output_count;
    reg output_valid,manifest_beat;
    reg [7:0] output_beat;
    wire writer_fault;
    wire operating=rst_n && !clear && !failed && !owner_error && !owner_abort;
    wire can_begin=operating && state==IDLE && raw_quiescent && reader_quiescent;
    assign write_start_ready=can_begin && owner_begin_ready;
    wire begin_take=write_start_valid && write_start_ready;
    assign write_ready=operating && state==GATHER;
    wire vector_take=write_valid && write_ready;
    assign write_done_valid=operating && state==COMPLETE;
    assign write_done_error=1'b0; // All failures use the sticky global error.
    assign error=rst_n && (failed || owner_error);
    assign raw_abort=owner_abort || failed;
    assign reader_abort=raw_abort;
    // Whole-update reader hold, matching the released plain writer's window.
    // The store applies it through the reader's read_abort path, not owner_abort:
    // read_abort still drains any owner response already in flight.
    assign update_active=state!=IDLE && state!=COMPLETE;
    assign owner_external_fault=failed || reader_fault || writer_fault;
    assign owner_transport_quiescent=raw_quiescent && reader_quiescent;
    assign owner_begin_valid=can_begin && write_start_valid;
    assign owner_begin_layer=write_layer;
    assign owner_begin_position={1'b0,write_position};
    assign owner_metadata_ready=operating && state==META;
    assign owner_commit_valid=operating && state==PUBLISH && raw_quiescent;
    assign owner_commit_epoch=epoch;
    assign owner_commit_layer=layer;
    assign owner_commit_position={1'b0,position};
    assign owner_commit_root=new_root;
    assign owner_published_ready=operating && state==PUBLISH_ACK;

    wire [33:0] page_address,manifest_address,unused_leaf_address;
    qwen_kvp_address #(.LAYER_BITS(LAYER_BITS),.PAYLOAD_BASE(PAYLOAD_BASE),.DIGEST_BASE(DIGEST_BASE)) layout(.layer(layer),.group(position[14:4]),.node(4'b0),
        .page_address(page_address),.leaf_address(unused_leaf_address),.digest_address(manifest_address));
    assign raw_request_valid=operating && (state==READ_REQUEST || state==PAGE_REQUEST || state==MANIFEST_REQUEST);
    assign raw_request_write=raw_request_valid && state!=READ_REQUEST;
    assign raw_address=raw_request_valid ? (state==MANIFEST_REQUEST ? manifest_address : page_address) : 34'b0;
    assign raw_bytes=raw_request_valid ? (state==MANIFEST_REQUEST ? 17'd512 : 17'd65536) : 17'b0;
    assign raw_read_ready=operating && state==READ_PAGE;
    wire read_take=raw_read_valid && raw_read_ready;
    wire request_take=raw_request_valid && raw_request_ready;
    assign raw_write_valid=operating && ((state==PAGE_WRITE && output_valid) || state==MANIFEST_WRITE);
    assign raw_write_last=raw_write_valid && (state==MANIFEST_WRITE ? manifest_beat : output_beat==8'd255);
    wire write_take=raw_write_valid && raw_write_ready;
    assign raw_done_ready=operating && (state==PAGE_ACK || state==MANIFEST_ACK);
    wire done_take=raw_done_valid && raw_done_ready;
    wire emit=operating && state==PAGE_WRITE && (!output_valid || raw_write_ready) && output_count<9'd256;
    wire zero_page=operating && state==ZERO_PAGE;

    wire hash_start_ready,hash_done_valid,hash_error,hash_busy,hash_read;
    wire [9:0] hash_word;
    wire [255:0] hash_root;
    wire [4095:0] hash_manifest;
    wire [1023:0] hash_pair;
    wire hash_start=operating && (state==OLD_START || state==NEW_START);
    wire hash_done_ready=operating && (state==OLD_HASH || state==NEW_HASH);
    wire [4:0] hash_count=(state==OLD_START || state==OLD_HASH) ? old_count : old_count+5'd1;
    qwen_kvp_page_hash #(.LAYERS(LAYERS),.LAYER_BITS(LAYER_BITS),.MODEL_TAG(MODEL_TAG),.ZERO_WHEN_INVALID(ZERO_WHEN_INVALID)) page_hash(
        .clk(clk),.rst_n(rst_n),.clear(clear || failed || owner_abort),
        .start_valid(hash_start),.start_ready(hash_start_ready),.start_epoch(epoch),.start_layer(layer),
        .start_group({5'b0,position[14:4]}),.start_count(hash_count),
        .buffer_read_enable(hash_read),.buffer_read_word(hash_word),.buffer_read_pair(hash_pair),
        .done_valid(hash_done_valid),.done_ready(hash_done_ready),.root(hash_root),.manifest(hash_manifest),
        .error(hash_error),.busy(hash_busy));
    assign quiescent=owner_quiescent && state==IDLE && !hash_busy;

    wire bad_metadata=state==META && owner_metadata_valid
        && (owner_layer!=layer || owner_position!={1'b0,position} || owner_count!={1'b0,position[3:0]});
    wire bad_vector=vector_take && {write_value,write_index}!=vector_index;
    wire bad_read=read_take && (raw_read_error || raw_read_last!=(beat==8'd255));
    wire bad_done=done_take && raw_done_error;
    wire unsolicited_read=raw_read_valid && state!=READ_PAGE && !(state==READ_REQUEST && request_take);
    wire unsolicited_done=raw_done_valid && state!=PAGE_ACK && state!=MANIFEST_ACK
        && !(write_take && raw_write_last);
    wire bad_old_root=state==OLD_HASH && hash_done_valid && hash_root!=old_root;
    assign writer_fault=operating && (raw_error || hash_error || bad_metadata || bad_vector
        || bad_read || bad_done || unsolicited_read || unsolicited_done || bad_old_root
        || (hash_read && emit));

    function automatic [511:0] reverse_bytes(input [511:0] value);
        integer j;
        begin for(j=0;j<64;j=j+1)reverse_bytes[511-j*8 -:8]=value[j*8 +:8];end
    endfunction
    wire [2047:0] hash_words,page_output,manifest_output;
    reg [1:0] hash_bank;
    wire [1:0] next_hash_bank=hash_bank+2'd1;
    assign hash_pair={hash_words[hash_bank*512 +:512],hash_words[next_hash_bank*512 +:512]};
    always @(posedge clk)if(hash_read)hash_bank<=hash_word[1:0];
    wire [2047:0] manifest_chunk=manifest_beat ? manifest_data[2047:0] : manifest_data[4095:2048];
    genvar bank,lane;
    generate for(bank=0;bank<4;bank=bank+1)begin:banks
        wire [511:0] hash_data,output_data;
        wire patch=vector_take && write_index[6:5]==2'(bank);
        wire [7:0] patch_row={write_value,write_index[9:7],position[3:0]};
        wire [7:0] io_address=(zero_page || read_take) ? beat : (patch ? patch_row : output_count[7:0]);
        wire [7:0] hash_address=hash_word[9:2]+(bank==0 && hash_word[1:0]==3 ? 8'd1 : 8'd0);
        // Hashing and writeback are disjoint phases. Share their RAM read port
        // explicitly rather than inferring a replicated copy for each reader.
        wire [7:0] shared_read_address=hash_read ? hash_address : output_count[7:0];
        wire [511:0] loaded=reverse_bytes(raw_read_data[bank*512 +:512]);
        // Fixed-width byte-enable groups avoid a variable 512-bit part-select
        // write, which the preliminary mapper fragmented into hundreds of
        // largely empty RAM blocks. All four 16-bit enables share one address.
        for(lane=0;lane<8;lane=lane+1)begin:words
            (* ram_style="block" *) reg [63:0] memory [0:255];
            reg [63:0] read_part;
            wire patch_word=patch && write_index[4:2]==3'(lane);
            integer column;
            always @(posedge clk)begin
                for(column=0;column<4;column=column+1)begin
                    if(!writer_fault && (zero_page || read_take || (patch_word && write_index[1:0]==2'(column))))
                        memory[io_address][63-column*16 -:16]<=zero_page ? 16'b0
                            : (read_take ? loaded[511-lane*64-column*16 -:16] : {write_data[7:0],write_data[15:8]});
                end
                if((emit || hash_read) && !writer_fault)read_part<=memory[shared_read_address];
            end
            assign hash_data[511-lane*64 -:64]=read_part;
            assign output_data[511-lane*64 -:64]=read_part;
        end
        assign hash_words[bank*512 +:512]=hash_data;
        assign page_output[bank*512 +:512]=reverse_bytes(output_data);
        assign manifest_output[bank*512 +:512]=reverse_bytes(manifest_chunk[2047-bank*512 -:512]);
    end endgenerate
    assign raw_write_data=raw_write_valid ? (state==MANIFEST_WRITE ? manifest_output : page_output) : 2048'b0;

    always @(posedge clk)begin
        if(!rst_n || clear)failed<=0;
        else if(writer_fault || owner_error || reader_fault)failed<=1;
        if(!operating || writer_fault)begin
            state<=IDLE;beat<=0;vector_index<=0;output_count<=0;output_valid<=0;manifest_beat<=0;
            layer<=0;position<=0;old_count<=0;epoch<=0;output_beat<=0;
        end else begin
            if(state==PAGE_WRITE && (!output_valid || raw_write_ready))begin
                output_valid<=emit;
                if(emit)begin output_beat<=output_count[7:0];output_count<=output_count+9'd1;end
            end else if(state!=PAGE_WRITE)output_valid<=0;
            case(state)
                IDLE:if(begin_take)begin layer<=write_layer;position<=write_position;state<=META;end
                META:if(owner_metadata_valid)begin
                    epoch<=owner_epoch;old_count<=owner_count;old_root<=owner_root;beat<=0;
                    state<=owner_count==0 ? ZERO_PAGE : READ_REQUEST;
                end
                ZERO_PAGE:begin
                    if(beat==8'd255)begin vector_index<=0;state<=GATHER;end else beat<=beat+8'd1;
                end
                READ_REQUEST:if(request_take)begin beat<=0;state<=READ_PAGE;end
                READ_PAGE:if(read_take)begin if(beat==8'd255)state<=OLD_START;else beat<=beat+8'd1;end
                OLD_START:if(hash_start_ready)state<=OLD_HASH;
                OLD_HASH:if(hash_done_valid)begin vector_index<=0;state<=GATHER;end
                GATHER:if(vector_take)begin if(vector_index==11'd2047)state<=NEW_START;else vector_index<=vector_index+11'd1;end
                NEW_START:if(hash_start_ready)state<=NEW_HASH;
                NEW_HASH:if(hash_done_valid)begin new_root<=hash_root;manifest_data<=hash_manifest;state<=PAGE_REQUEST;end
                PAGE_REQUEST:if(request_take)begin output_count<=0;state<=PAGE_WRITE;end
                PAGE_WRITE:if(write_take && raw_write_last)begin output_valid<=0;state<=PAGE_ACK;end
                PAGE_ACK:if(done_take)state<=MANIFEST_REQUEST;
                MANIFEST_REQUEST:if(request_take)begin manifest_beat<=0;state<=MANIFEST_WRITE;end
                MANIFEST_WRITE:if(write_take)begin if(manifest_beat)state<=MANIFEST_ACK;else manifest_beat<=1;end
                MANIFEST_ACK:if(done_take)state<=PUBLISH;
                PUBLISH:if(raw_quiescent && owner_commit_ready)state<=PUBLISH_ACK;
                PUBLISH_ACK:if(owner_published_valid)state<=COMPLETE;
                COMPLETE:if(write_done_ready)state<=IDLE;
                default:begin failed<=1;state<=IDLE;end
            endcase
        end
    end
endmodule
