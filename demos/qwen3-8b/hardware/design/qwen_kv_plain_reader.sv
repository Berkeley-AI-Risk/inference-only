// PRIVATE baseline attention reader: cached external K/V WITHOUT integrity.
// The writer supplies a private committed-prefix count for lookup_layer. It
// must abort/drain this reader before every update, CLEAR or session change.
// Counts and coordinates never come from software. No runtime bypass switch.
//
// Same payload layout, cache geometry, read-ahead policy and numerical-facing
// vector order as the protected reader, but no digest reads or SHA operations.
// Reading a whole leaf may fetch uncommitted padding; only committed vectors
// can reach the numerical core. External tampering of committed bytes is NOT
// rejected by this baseline. Raw reads are private single-outstanding requests.
module qwen_kv_plain_reader #(
    parameter integer CACHE_GROUPS=128,
    parameter integer PREFETCH_GROUPS=128,
    parameter integer ZERO_WHEN_INVALID=1,
    parameter integer FACTOR_VALID_GUARD=0,
    parameter integer ZERO_METADATA_WHEN_INVALID=1
) (
    input wire clk,input wire rst_n,input wire read_abort,input wire owner_abort,
    input wire [5:0] memory_layer,input wire [2:0] memory_head,
    input wire key_ready,input wire [14:0] key_position,
    output wire key_valid,output wire [2047:0] keys,
    input wire value_ready,input wire [14:0] value_position,input wire value_group,
    output wire value_valid,output wire [1023:0] values,
    output wire error,output wire quiescent,
    output wire [5:0] lookup_layer,input wire metadata_valid,input wire [15:0] committed_positions,
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
    localparam [2:0] IDLE=0,LOOKUP=1,HEADER=2,DATA=3,DRAIN=4,ALLOCATE=5;
    initial if(CACHE_GROUPS<4 || CACHE_GROUPS>256 || (CACHE_GROUPS&(CACHE_GROUPS-1))!=0
        || PREFETCH_GROUPS<1 || PREFETCH_GROUPS>CACHE_GROUPS || (PREFETCH_GROUPS&(PREFETCH_GROUPS-1))!=0
        || (ZERO_WHEN_INVALID!=0 && ZERO_WHEN_INVALID!=1)
        || (FACTOR_VALID_GUARD!=0 && FACTOR_VALID_GUARD!=1)
        || (ZERO_METADATA_WHEN_INVALID!=0 && ZERO_METADATA_WHEN_INVALID!=1))
        $fatal(1,"Invalid private baseline K/V reader cache geometry");
    function automatic [CACHE_BITS-1:0] cache_slot(input [3:0] node,input [10:0] page_group);
        cache_slot={node[3],page_group[GROUP_BITS-1:0]};
    endfunction
    reg failed,draining,output_valid,output_value,output_half;
    reg [5:0] output_layer;
    reg [2:0] output_head;
    reg [14:0] output_position;
    reg [CACHE_LEAVES-1:0] cache_valid,cache_pending;
    reg [20:0] cache_tag [0:CACHE_LEAVES-1];
    reg [4:0] cache_count [0:CACHE_LEAVES-1];
    reg prefix_known;
    reg [5:0] prefix_layer;
    reg [15:0] prefix_positions;
    reg prefetch_enabled;
    reg [5:0] anchor_layer;
    reg [3:0] anchor_node;
    reg [10:0] anchor_group;
    reg [PREFETCH_BITS-1:0] prefetch_offset;
    reg [2:0] fetch_state;
    reg [5:0] fetch_layer;
    reg [3:0] fetch_node;
    reg [10:0] fetch_group;
    reg [3:0] raw_count;
    wire stopped=!rst_n || read_abort || owner_abort || draining || failed;
    wire alive=!stopped;
    wire fault_event;
    assign raw_abort=stopped;
    assign error=rst_n && failed;
    wire demand=alive && !output_valid && (key_ready || value_ready);
    wire demand_value=!key_ready;
    wire [14:0] demand_position=demand_value ? value_position : key_position;
    wire [3:0] demand_node={demand_value,memory_head};
    wire [10:0] demand_group=demand_position[14:4];
    wire [20:0] demand_tag={memory_layer,demand_node,demand_group};
    wire [CACHE_BITS-1:0] demand_slot=cache_slot(demand_node,demand_group);
    wire demand_match=cache_tag[demand_slot]==demand_tag;
    // A newly reserved slot is unavailable immediately, including
    // the cycle before its tag and validity bits are physically updated.
    wire demand_allocating=fetch_state==ALLOCATE && demand_slot==fetch_slot;
    wire demand_hit=cache_valid[demand_slot] && demand_match && !demand_allocating;
    wire demand_pending=(cache_pending[demand_slot] && demand_match) || demand_allocating;
    wire bad_demand=demand && (memory_layer>=6'd36
        || (prefix_known && prefix_layer==memory_layer && {1'b0,demand_position}>=prefix_positions)
        || (demand_hit && {1'b0,demand_position[3:0]}>=cache_count[demand_slot]));
    wire read_issue=demand && demand_hit && !fault_event;
    wire [CACHE_BITS+3:0] cache_read_address={demand_slot,demand_position[3:0]};
    wire [2047:0] cache_read;
    wire output_fault;
    assign key_valid=alive && !output_fault && output_valid && !output_value;
    assign value_valid=alive && !output_fault && output_valid && output_value;
    // Compile-time PRIVATE payload option. Valid/fault/abort, committed-prefix
    // and owner checks above and below are unchanged. When zero masking is
    // omitted, consumers may use these retained RAM bits ONLY on the unchanged
    // valid/ready handshake. These buses are not public outputs or memory APIs.
    // This keeps the long demand/fault/clear cone out of arithmetic operands;
    // it does not assert valid early or release a cancelled/uncommitted vector.
    assign keys=ZERO_WHEN_INVALID!=0 && !key_valid ? 2048'b0 : cache_read;
    assign values=ZERO_WHEN_INVALID!=0 && !value_valid ? 1024'b0
        : (output_half ? cache_read[2047:1024] : cache_read[1023:0]);
    wire output_take=output_valid && (output_value ? value_ready : key_ready) && alive;
    wire bad_held_request=alive && output_valid && (memory_layer!=output_layer || memory_head!=output_head
        || (output_value ? (value_position!=output_position || value_group!=output_half) : key_position!=output_position));

    wire [11:0] prefetch_group={1'b0,anchor_group}+12'(prefetch_offset);
    wire [15:0] prefetch_position={prefetch_group,4'b0};
    reg candidate_valid;
    reg [5:0] candidate_layer;
    reg [3:0] candidate_node;
    reg [10:0] candidate_group;
    reg [CACHE_BITS-1:0] candidate_slot;
    reg [20:0] candidate_tag;
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
    wire reserve=alive && fetch_state==IDLE && candidate_valid && !fault_event;
    wire [CACHE_BITS-1:0] fetch_slot=cache_slot(fetch_node,fetch_group);
    // PRIVATE lookup payload, not a request/acceptance signal. The owner may
    // calculate a count for the retained layer even during cancellation. Only
    // metadata_take can consume that count, with the original alive/state/valid
    // and prefix checks. Removing this optional zero mask prevents abort from
    // passing through the owner's count arithmetic before gating attention.
    assign lookup_layer=ZERO_METADATA_WHEN_INVALID!=0 && !(alive && fetch_state==LOOKUP)
        ? 6'b0 : fetch_layer;
    wire metadata_take=alive && fetch_state==LOOKUP && metadata_valid;
    wire [16:0] group_base={2'b0,fetch_group,4'b0};
    wire [16:0] group_remaining={1'b0,committed_positions}-group_base;
    wire [4:0] expected_count=group_remaining>=17'd16 ? 5'd16 : group_remaining[4:0];
    wire bad_metadata=metadata_take && (fetch_layer>=6'd36 || committed_positions==0
        || committed_positions>16'd32768 || {1'b0,committed_positions}<=group_base
        || (prefix_known && prefix_layer==fetch_layer && committed_positions!=prefix_positions));
    wire [16:0] page_index={fetch_layer,fetch_group};
    assign raw_request_valid=alive && fetch_state==HEADER;
    assign raw_address=raw_request_valid
        ? 34'd8828026880+{1'b0,page_index,16'b0}+{18'b0,fetch_node,12'b0} : 34'b0;
    assign raw_bytes=raw_request_valid ? 13'd4096 : 13'b0;
    assign raw_data_ready=alive && fetch_state==DATA;
    wire header_take=raw_request_valid && raw_request_ready;
    wire raw_take=raw_data_valid && raw_data_ready;
    wire malformed_raw=alive && (raw_error || (raw_data_valid && fetch_state!=DATA)
        || (raw_take && (raw_data_error || raw_last!=(raw_count==4'd15))));
    assign fault_event=alive && (bad_demand || bad_held_request || bad_metadata || malformed_raw);
    // A demand exists only when !output_valid. Consequently bad_demand is
    // false whenever an output could be valid. Factoring that impossible
    // combination out of the OUTPUT predicate avoids propagating the demand
    // cache-tag/count lookup through attention ready/valid. The full fault
    // predicate still drives failure, cancellation, RAM writes and read issue.
    // Every possible fault while output_valid remains a same-cycle output gate.
    assign output_fault=FACTOR_VALID_GUARD!=0
        ? alive && (bad_held_request || bad_metadata || malformed_raw) : fault_event;
    wire fill_take=raw_take && !fault_event;
    wire [CACHE_BITS+3:0] cache_write_address={fetch_slot,raw_count};
    assign quiescent=rst_n && raw_quiescent
        && (stopped || (!output_valid && fetch_state==IDLE && !(|cache_pending)));
    // PRIVATE payload captures only. DATA owns an invalid pending slot.
    // A fault/cancellation can leave unused bits there, but still clears all
    // validity. A read register may change only while no output is published;
    // every actual read_issue loads the same word before publication. Keep
    // fill_take/read_issue and all state/publication/abort rules unchanged.
    wire private_fill_capture=fetch_state==DATA && raw_data_valid;
    wire private_read_capture=!output_valid;
    genvar bank;
    generate for(bank=0;bank<4;bank=bank+1)begin:cache_words
        (* ram_style="block" *) reg [511:0] memory [0:CACHE_LEAVES*16-1];
        reg [511:0] read_data;
        always @(posedge clk)begin
            if(private_fill_capture)memory[cache_write_address]<=raw_data[bank*512+:512];
            if(private_read_capture)read_data<=memory[cache_read_address];
        end
        assign cache_read[bank*512+:512]=read_data;
    end endgenerate
    always @(posedge clk)begin
        if(!rst_n || read_abort || owner_abort)begin failed<=0;draining<=1;end
        else if(fault_event)begin failed<=1;draining<=1;end
        else if(draining && raw_quiescent)draining<=0;
        if(stopped || fault_event)begin
            output_valid<=0;cache_valid<=0;cache_pending<=0;prefix_known<=0;prefix_layer<=0;prefix_positions<=0;
            prefetch_enabled<=0;anchor_layer<=0;anchor_node<=0;anchor_group<=0;prefetch_offset<=0;
            fetch_state<=IDLE;fetch_layer<=0;fetch_node<=0;fetch_group<=0;raw_count<=0;
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
            // PRIVATE_ALLOCATION_STAGE: use the captured descriptor, not
            // the same-cycle attention-ready/tag-lookup cone. The enclosing
            // stopped/fault branch still dominates all metadata writes.
            if(fetch_state==ALLOCATE)begin
                cache_pending[fetch_slot]<=1;cache_valid[fetch_slot]<=0;
                cache_tag[fetch_slot]<={fetch_layer,fetch_node,fetch_group};
                fetch_state<=LOOKUP;
            end
            if(metadata_take)begin
                prefix_known<=1;prefix_layer<=fetch_layer;prefix_positions<=committed_positions;
                cache_count[fetch_slot]<=expected_count;fetch_state<=HEADER;
            end
            if(header_take)begin fetch_state<=DATA;raw_count<=0;end
            if(fill_take)begin raw_count<=raw_count+1'b1;if(raw_count==4'd15)fetch_state<=DRAIN;end
            if(fetch_state==DRAIN && raw_quiescent)begin
                cache_valid[fetch_slot]<=1;cache_pending[fetch_slot]<=0;fetch_state<=IDLE;
            end
        end
    end
endmodule
