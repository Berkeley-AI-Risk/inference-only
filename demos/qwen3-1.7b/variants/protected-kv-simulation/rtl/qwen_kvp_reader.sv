// PRIVATE one-attention-pair K/V reader. All identities/addresses come from
// Derived from qwen_kv_reader.sv (sha256 1446fdd9e73a0980...), carrying forward the
// released qwen_kv_plain_reader changes: compile-time ZERO_WHEN_INVALID,
// FACTOR_VALID_GUARD and ZERO_METADATA_WHEN_INVALID; PRIVATE_ALLOCATION_STAGE;
// private cache-fill and read captures. Protected additions: the verifier's
// register-only out_present drives response checks; out_valid alone releases a
// fill. Only bytes from the retained-leaf verifier ever reach the cache RAM.
//
// the fixed numerical schedule and private root owner, never application I/O.
// It keeps separate K/V leaf caches and bounded sequential group read-ahead.
// Only the retained-leaf verifier's approved output can enter either cache.
//
// read_abort cancels one reader without clearing the root-owner session. The
// integration MUST also assert it before every writer begin (write_start_valid
// is suitable) and wait for quiescent before changing K/V. This invalidates old
// cache versions. owner_abort additionally means the owner has invalidated any
// pending lookup response. A mere reader abort must drain that response instead.
//
// Raw transport: one request, 16 payload or two manifest 256-byte beats, in
// order. raw_quiescent on abort means old requests cannot produce responses.
// This module is not the physical AXI/HBM adapter or the full numerical core.
module qwen_kvp_reader #(
    parameter integer CACHE_GROUPS=128,
    parameter integer AUTH_SLOTS=128,
    parameter integer PREFETCH_GROUPS=128,
    parameter integer ZERO_WHEN_INVALID=1,
    parameter integer FACTOR_VALID_GUARD=0,
    parameter integer ZERO_METADATA_WHEN_INVALID=1
) (
    input wire clk,input wire rst_n,input wire read_abort,input wire owner_abort,
    input wire [4:0] memory_layer,input wire [2:0] memory_head,
    input wire key_ready,input wire [14:0] key_position,
    output wire key_valid,output wire [2047:0] keys,
    input wire value_ready,input wire [14:0] value_position,input wire value_group,
    output wire value_valid,output wire [1023:0] values,
    output wire error,output wire quiescent,

    output wire lookup_valid,input wire lookup_ready,
    output wire [4:0] lookup_layer,output wire [15:0] lookup_position,
    input wire result_valid,output wire result_ready,
    input wire [63:0] result_epoch,input wire [4:0] result_layer,
    input wire [15:0] result_position,input wire [4:0] result_count,
    input wire [15:0] result_total_positions,input wire [255:0] result_root,

    output wire raw_request_valid,input wire raw_request_ready,
    output wire [33:0] raw_address,output wire [12:0] raw_bytes,
    input wire raw_data_valid,output wire raw_data_ready,input wire [2047:0] raw_data,
    input wire raw_last,input wire raw_data_error,input wire raw_error,
    output wire raw_abort,input wire raw_quiescent
);
    localparam integer GROUP_BITS=$clog2(CACHE_GROUPS);
    localparam integer CACHE_BITS=GROUP_BITS+1;
    localparam integer CACHE_LEAVES=CACHE_GROUPS*2;
    localparam integer PREFETCH_BITS=PREFETCH_GROUPS>1 ? $clog2(PREFETCH_GROUPS) : 1;
    localparam [3:0] IDLE=0,LOOKUP=1,META=2,AUTH_START=3,
        PAYLOAD_HEADER=4,PAYLOAD_DATA=5,MANIFEST_HEADER=6,MANIFEST_DATA=7,ALLOCATE=8;
    initial if(CACHE_GROUPS<4 || CACHE_GROUPS>256 || (CACHE_GROUPS&(CACHE_GROUPS-1))!=0
        || PREFETCH_GROUPS<1 || PREFETCH_GROUPS>CACHE_GROUPS || (PREFETCH_GROUPS&(PREFETCH_GROUPS-1))!=0
        || (ZERO_WHEN_INVALID!=0 && ZERO_WHEN_INVALID!=1)
        || (FACTOR_VALID_GUARD!=0 && FACTOR_VALID_GUARD!=1)
        || (ZERO_METADATA_WHEN_INVALID!=0 && ZERO_METADATA_WHEN_INVALID!=1))
        $fatal(1,"Invalid private K/V reader cache geometry");
    function automatic [CACHE_BITS-1:0] cache_slot(input [3:0] node,input [10:0] page_group);
        cache_slot={node[3],page_group[GROUP_BITS-1:0]};
    endfunction
    reg failed,draining,lookup_pending,output_valid,output_value,output_half;
    reg [4:0] output_layer;
    reg [2:0] output_head;
    reg [14:0] output_position;
    reg [CACHE_LEAVES-1:0] cache_valid,cache_pending;
    reg [19:0] cache_tag [0:CACHE_LEAVES-1];
    reg [4:0] cache_count [0:CACHE_LEAVES-1];
    reg epoch_known,prefix_known;
    reg [63:0] epoch;
    reg [4:0] prefix_layer;
    reg [15:0] prefix_positions;
    reg prefetch_enabled;
    reg [4:0] anchor_layer;
    reg [3:0] anchor_node;
    reg [10:0] anchor_group;
    reg [PREFETCH_BITS-1:0] prefetch_offset;
    reg [3:0] fetch_state;
    reg [4:0] fetch_layer,fetch_count;
    reg [3:0] fetch_node;
    reg [10:0] fetch_group;
    reg [63:0] fetch_epoch;
    reg [255:0] fetch_root;
    reg [3:0] raw_count,fill_count;
    reg [19:0] fill_tag;
    wire stopped=!rst_n || read_abort || owner_abort || draining || failed;
    wire alive=!stopped;
    wire fault_event;
    assign raw_abort=stopped;
    // Do not mask a recorded failure with read_abort: the attention circuit can
    // assert abort combinationally when it observes this error.
    assign error=rst_n && failed;

    wire demand=alive && !output_valid && (key_ready || value_ready);
    wire demand_value=!key_ready;
    wire [14:0] demand_position=demand_value ? value_position : key_position;
    wire [3:0] demand_node={demand_value,memory_head};
    wire [10:0] demand_group=demand_position[14:4];
    wire [19:0] demand_tag={memory_layer,demand_node,demand_group};
    wire [CACHE_BITS-1:0] demand_slot=cache_slot(demand_node,demand_group);
    wire demand_match=cache_tag[demand_slot]==demand_tag;
    wire [CACHE_BITS-1:0] fetch_slot=cache_slot(fetch_node,fetch_group);
    // A newly reserved slot is unavailable immediately, including
    // the cycle before its tag and validity bits are physically updated.
    wire demand_allocating=fetch_state==ALLOCATE && demand_slot==fetch_slot;
    wire demand_hit=cache_valid[demand_slot] && demand_match && !demand_allocating;
    wire demand_pending=(cache_pending[demand_slot] && demand_match) || demand_allocating;
    wire bad_demand=demand && (memory_layer>=5'd28
        || (prefix_known && prefix_layer==memory_layer && {1'b0,demand_position}>=prefix_positions)
        || (demand_hit && {1'b0,demand_position[3:0]}>=cache_count[demand_slot]));
    wire read_issue=demand && demand_hit && !fault_event;
    wire [CACHE_BITS+3:0] read_address={demand_slot,demand_position[3:0]};
    wire [2047:0] cache_read;
    wire output_fault;
    assign key_valid=alive && !output_fault && output_valid && !output_value;
    assign value_valid=alive && !output_fault && output_valid && output_value;
    // Compile-time PRIVATE payload option, as in the released plain reader.
    // Consumers use these retained verified bits only on the unchanged
    // valid/ready handshake. These buses are not public outputs or memory APIs.
    assign keys=ZERO_WHEN_INVALID!=0 && !key_valid ? 2048'b0 : cache_read;
    assign values=ZERO_WHEN_INVALID!=0 && !value_valid ? 1024'b0
        : (output_half ? cache_read[2047:1024] : cache_read[1023:0]);
    wire output_take=output_valid && (output_value ? value_ready : key_ready) && alive;
    wire bad_held_request=alive && output_valid && (memory_layer!=output_layer || memory_head!=output_head
        || (output_value ? (value_position!=output_position || value_group!=output_half) : key_position!=output_position));

    wire [11:0] prefetch_group={1'b0,anchor_group}+12'(prefetch_offset);
    wire [15:0] prefetch_position={prefetch_group,4'b0};
    reg candidate_valid;
    reg [4:0] candidate_layer;
    reg [3:0] candidate_node;
    reg [10:0] candidate_group;
    reg [CACHE_BITS-1:0] candidate_slot;
    reg [19:0] candidate_tag;
    always @* begin
        candidate_valid=0;candidate_layer=0;candidate_node=0;candidate_group=0;candidate_slot=0;candidate_tag=0;
        if(demand && !demand_hit && !demand_pending && !bad_demand)begin
            candidate_layer=memory_layer;candidate_node=demand_node;candidate_group=demand_group;
            candidate_slot=demand_slot;candidate_tag=demand_tag;candidate_valid=!cache_pending[demand_slot];
        end else if(prefetch_enabled && prefix_known && prefix_layer==anchor_layer
                && !prefetch_group[11] && prefetch_position<prefix_positions)begin
            candidate_layer=anchor_layer;candidate_node=anchor_node;candidate_group=prefetch_group[10:0];
            candidate_slot=cache_slot(anchor_node,prefetch_group[10:0]);candidate_tag={anchor_layer,anchor_node,prefetch_group[10:0]};
            candidate_valid=!cache_pending[candidate_slot]
                && !(cache_valid[candidate_slot] && cache_tag[candidate_slot]==candidate_tag)
                && !(demand && demand_hit && candidate_slot==demand_slot && candidate_tag!=demand_tag);
        end
    end
    wire auth_load_ready,auth_data_ready,auth_valid,auth_present,auth_last,auth_error,auth_busy;
    wire [63:0] auth_epoch;
    wire [4:0] auth_layer,auth_node,auth_count;
    wire [15:0] auth_group;
    wire [3:0] auth_vector;
    wire [2047:0] auth_data;
    wire reserve=alive && fetch_state==IDLE && candidate_valid && auth_load_ready && !fault_event;
    assign lookup_valid=alive && fetch_state==LOOKUP;
    // PRIVATE lookup payload, not a request/acceptance signal. The owner consumes
    // it only on lookup_valid && lookup_ready.
    wire lookup_visible=ZERO_METADATA_WHEN_INVALID==0 || lookup_valid;
    assign lookup_layer=lookup_visible ? fetch_layer : 5'b0;
    assign lookup_position=lookup_visible ? {1'b0,fetch_group,4'b0} : 16'b0;
    wire lookup_take=lookup_valid && lookup_ready;
    assign result_ready=rst_n && lookup_pending && (stopped || fetch_state==META);
    wire result_take=result_valid && result_ready;
    wire [16:0] group_base={2'b0,fetch_group,4'b0};
    wire [16:0] group_remaining={1'b0,result_total_positions}-group_base;
    wire [4:0] expected_count=group_remaining>=17'd16 ? 5'd16 : group_remaining[4:0];
    wire bad_metadata=alive && result_valid && (!lookup_pending || fetch_state!=META
        || result_layer!=fetch_layer || result_position!={1'b0,fetch_group,4'b0}
        || result_total_positions==0 || result_total_positions>16'd32768 || {1'b0,result_total_positions}<=group_base
        || result_count!=expected_count || (epoch_known && result_epoch!=epoch)
        || (prefix_known && prefix_layer==fetch_layer && result_total_positions!=prefix_positions));

    wire payload_mode=fetch_state==PAYLOAD_HEADER || fetch_state==PAYLOAD_DATA;
    wire data_state=fetch_state==PAYLOAD_DATA || fetch_state==MANIFEST_DATA;
    wire [33:0] leaf_address,digest_address,unused_page_address;
    qwen_kvp_address layout(.layer(fetch_layer),.group(fetch_group),.node(fetch_node),
        .page_address(unused_page_address),.leaf_address(leaf_address),.digest_address(digest_address));
    assign raw_request_valid=alive && (fetch_state==PAYLOAD_HEADER || fetch_state==MANIFEST_HEADER);
    assign raw_address=!raw_request_valid ? 34'b0 : (payload_mode ? leaf_address : digest_address);
    assign raw_bytes=raw_request_valid ? (payload_mode ? 13'd4096 : 13'd512) : 13'b0;
    wire raw_header_take=raw_request_valid && raw_request_ready;
    assign raw_data_ready=alive && data_state && auth_data_ready;
    wire raw_take=raw_data_valid && raw_data_ready;
    wire raw_final=payload_mode ? raw_count==4'd15 : raw_count==4'd1;
    wire malformed_raw=alive && (raw_error || (raw_data_valid && !data_state)
        || (raw_take && (raw_data_error || raw_last!=raw_final)));
    qwen_kvp_leaf_auth #(.SLOTS(AUTH_SLOTS),.ZERO_WHEN_INVALID(ZERO_WHEN_INVALID)) verifier(
        .clk(clk),.rst_n(rst_n),.clear(stopped),
        .load_valid(alive && fetch_state==AUTH_START),.load_ready(auth_load_ready),
        .load_epoch(fetch_epoch),.load_layer(fetch_layer),.load_group({5'b0,fetch_group}),
        .load_node({1'b0,fetch_node}),.load_count(fetch_count),.load_root(fetch_root),
        .load_data_valid(alive && data_state && raw_data_valid),.load_data_ready(auth_data_ready),
        .load_data(raw_data),.load_last(fetch_state==MANIFEST_DATA && raw_count==1),
        .load_error(raw_error || raw_data_error || raw_last!=raw_final),
        .out_valid(auth_valid),.out_present(auth_present),.out_ready(alive),.out_data(auth_data),
        .out_epoch(auth_epoch),.out_layer(auth_layer),.out_group(auth_group),.out_node(auth_node),.out_count(auth_count),
        .out_vector(auth_vector),.out_last(auth_last),.error(auth_error),.busy(auth_busy));
    wire [19:0] auth_tag={auth_layer,auth_node[3:0],auth_group[10:0]};
    wire [CACHE_BITS-1:0] fill_slot=cache_slot(auth_node[3:0],auth_group[10:0]);
    // auth_present, not auth_valid: the same checks on the same registered beat,
    // without passing the verifier's hash comparison through key/value valid.
    // This can only fault more often than auth_valid would; the verifier fault
    // itself is reported through auth_error on the next clock, as before.
    wire bad_verified_response=auth_present && (auth_layer>=5'd28 || auth_group>=16'd2048 || auth_node>=5'd16
        || !epoch_known || auth_epoch!=epoch || !cache_pending[fill_slot] || cache_tag[fill_slot]!=auth_tag
        || cache_count[fill_slot]!=auth_count || auth_vector!=fill_count || auth_last!=(fill_count==15)
        || (fill_count!=0 && fill_tag!=auth_tag));
    assign fault_event=alive && (bad_demand || bad_held_request || bad_metadata || malformed_raw || auth_error || bad_verified_response);
    // A demand exists only when !output_valid, so bad_demand is false whenever an
    // output could be valid. Factoring that impossible combination out of the
    // OUTPUT predicate keeps the demand tag/count lookup out of attention
    // ready/valid. The full fault_event still drives failure, cancellation,
    // cache metadata and read issue. Every fault possible while output_valid
    // remains a same-cycle output gate.
    assign output_fault=FACTOR_VALID_GUARD!=0
        ? alive && (bad_held_request || bad_metadata || malformed_raw || auth_error || bad_verified_response)
        : fault_event;
    wire fill_take=alive && auth_valid && !fault_event;
    wire [CACHE_BITS+3:0] write_address={fill_slot,fill_count};
    assign quiescent=rst_n && raw_quiescent && !lookup_pending
        && (stopped || (!auth_busy && !output_valid && fetch_state==IDLE && !(|cache_pending)));
    // PRIVATE payload captures only. The source is always the verifier's retained
    // output register, and only verified leaves are ever emitted into it. A
    // present beat either targets the invalid pending slot, or coincides with a
    // fault that invalidates the whole cache by the next clock. Valid is set only
    // after fill_take has counted all sixteen beats. A read register may change
    // only while no output is published; every read_issue loads the same word
    // before publication. fill_take/read_issue and all state rules are unchanged.
    wire private_fill_capture=auth_present;
    wire private_read_capture=!output_valid;
    genvar bank;
    generate for(bank=0;bank<4;bank=bank+1)begin:cache_words
        (* ram_style="block" *) reg [511:0] memory [0:CACHE_LEAVES*16-1];
        reg [511:0] read_data;
        always @(posedge clk)begin
            if(private_fill_capture)memory[write_address]<=auth_data[bank*512 +:512];
            if(private_read_capture)read_data<=memory[read_address];
        end
        assign cache_read[bank*512 +:512]=read_data;
    end endgenerate

    always @(posedge clk)begin
        if(!rst_n || owner_abort)lookup_pending<=0;
        else begin
            if(lookup_take)lookup_pending<=1;
            if(result_take)lookup_pending<=0;
        end
        if(!rst_n || read_abort || owner_abort)begin failed<=0;draining<=1;end
        else if(fault_event)begin failed<=1;draining<=1;end
        else if(draining && raw_quiescent && !lookup_pending)draining<=0;
        if(stopped || fault_event)begin
            output_valid<=0;cache_valid<=0;cache_pending<=0;epoch_known<=0;prefix_known<=0;
            epoch<=0;prefix_layer<=0;prefix_positions<=0;prefetch_enabled<=0;
            anchor_layer<=0;anchor_node<=0;anchor_group<=0;prefetch_offset<=0;
            fetch_state<=IDLE;fetch_layer<=0;fetch_node<=0;fetch_group<=0;fetch_count<=0;fetch_epoch<=0;
            raw_count<=0;fill_count<=0;fill_tag<=0;
        end else begin
            if(output_take)output_valid<=0;
            if(demand)begin
                prefetch_enabled<=1;anchor_layer<=memory_layer;anchor_node<=demand_node;anchor_group<=demand_group;
                if(!prefetch_enabled || anchor_layer!=memory_layer || anchor_node!=demand_node || anchor_group!=demand_group)
                    prefetch_offset<=0;
            end
            if(read_issue)begin
                output_valid<=1;output_value<=demand_value;output_half<=value_group;
                output_layer<=memory_layer;output_head<=memory_head;output_position<=demand_position;
            end
            if(fetch_state==IDLE)begin
                if(!demand || (prefetch_enabled && anchor_layer==memory_layer && anchor_node==demand_node && anchor_group==demand_group))
                    prefetch_offset<=prefetch_offset==PREFETCH_BITS'(PREFETCH_GROUPS-1)
                        ? {PREFETCH_BITS{1'b0}} : prefetch_offset+1'b1;
                if(reserve)begin
                    fetch_layer<=candidate_layer;fetch_node<=candidate_node;fetch_group<=candidate_group;fetch_state<=ALLOCATE;
                end
            end
            // PRIVATE_ALLOCATION_STAGE: use the captured descriptor, not the
            // same-cycle attention-ready/tag-lookup cone. The enclosing
            // stopped/fault branch still dominates all metadata writes.
            if(fetch_state==ALLOCATE)begin
                cache_pending[fetch_slot]<=1;cache_valid[fetch_slot]<=0;
                cache_tag[fetch_slot]<={fetch_layer,fetch_node,fetch_group};
                fetch_state<=LOOKUP;
            end
            if(lookup_take)fetch_state<=META;
            if(result_take)begin
                fetch_epoch<=result_epoch;fetch_count<=result_count;fetch_root<=result_root;
                epoch_known<=1;epoch<=result_epoch;prefix_known<=1;prefix_layer<=result_layer;prefix_positions<=result_total_positions;
                cache_count[fetch_slot]<=result_count;fetch_state<=AUTH_START;
            end
            if(fetch_state==AUTH_START && auth_load_ready)fetch_state<=PAYLOAD_HEADER;
            if(raw_header_take)begin fetch_state<=payload_mode ? PAYLOAD_DATA : MANIFEST_DATA;raw_count<=0;end
            if(raw_take)begin
                raw_count<=raw_count+1'b1;
                if(raw_final)fetch_state<=payload_mode ? MANIFEST_HEADER : IDLE;
            end
            if(fill_take)begin
                fill_count<=fill_count+1'b1;fill_tag<=auth_tag;
                if(auth_last)begin cache_valid[fill_slot]<=1;cache_pending[fill_slot]<=0;end
            end
        end
    end
endmodule
