// PRIVATE fixed-image reader between qwen_fixed_core and the page transport.
// No address, cache, root, hash or raw-memory port is an application interface.
// Only fixed internal model scheduling may drive the request side.
//
// Model pages are authenticated and copied to private caches before use. Weight
// and auxiliary pages use separate direct-mapped regions, so a weight stream
// cannot evict repeatedly used scales/norms/rotary data. Bounded sequential
// weight prefetch is internal, not host-programmable.
//
// raw_* is an IN-ORDER single-page transport contract, not an AXI/HBM adapter.
// A raw request fetches exactly 64 KiB in 256-byte little-endian beats. On abort,
// transport drains/withdraws outstanding work and asserts raw_quiescent. No new
// request is issued until that drain finishes. In normal operation quiescent
// refers to outstanding responses TO THE CORE; fixed-data prefetch may continue.
module qwen_model_reader #(
    parameter integer WEIGHT_PAGES=16,
    parameter integer AUX_PAGES=8,
    parameter integer AUTH_SLOTS=8,
    parameter integer PREFETCH_PAGES=8,
    parameter ROOT_FILE="model-page-roots.hex"
) (
    input wire clk,input wire rst_n,input wire core_abort,
    input wire request_valid,output wire request_ready,
    input wire [31:0] request_address,input wire [17:0] request_bytes,
    output wire data_valid,input wire data_ready,output wire [2047:0] data,
    output wire data_last,output wire error,output wire quiescent,
    output wire raw_request_valid,input wire raw_request_ready,output wire [15:0] raw_page,
    input wire raw_data_valid,output wire raw_data_ready,input wire [2047:0] raw_data,
    input wire raw_last,input wire raw_error,
    output wire raw_abort,input wire raw_quiescent
);
    localparam integer CACHE_PAGES=WEIGHT_PAGES+AUX_PAGES;
    localparam integer CACHE_BITS=$clog2(CACHE_PAGES);
    localparam integer CACHE_ADDRESS_BITS=$clog2(CACHE_PAGES*256);
    localparam integer PREFETCH_BITS=PREFETCH_PAGES>1 ? $clog2(PREFETCH_PAGES) : 1;
    localparam [1:0] FETCH_IDLE=0,FETCH_HEADER=1,FETCH_DATA=2,FETCH_AUTH_HEADER=3;
    initial begin
        if(WEIGHT_PAGES<4 || WEIGHT_PAGES>64 || (WEIGHT_PAGES&(WEIGHT_PAGES-1))!=0
                || AUX_PAGES<2 || AUX_PAGES>32 || (AUX_PAGES&(AUX_PAGES-1))!=0
                || PREFETCH_PAGES<1 || PREFETCH_PAGES>WEIGHT_PAGES/2
                || (PREFETCH_PAGES&(PREFETCH_PAGES-1))!=0)
            $fatal(1,"Invalid private fixed-model cache geometry");
    end
    function automatic [CACHE_BITS-1:0] cache_slot(input [15:0] page);
        cache_slot=page<16'd26252 ? CACHE_BITS'(page & 16'(WEIGHT_PAGES-1))
            : CACHE_BITS'(WEIGHT_PAGES)+CACHE_BITS'(page & 16'(AUX_PAGES-1));
    endfunction

    reg draining,failed,front_active;
    wire output_valid,output_last,output_short,output_high_half;
    reg [2:0] response_count,reserved_count;
    reg [1:0] response_read,response_write;
    reg read_pending,read_last_q,read_short_q,read_high_half_q;
    reg [2047:0] response_words [0:3];
    reg [3:0] response_lasts,response_shorts,response_high_halves;
    wire [2047:0] output_word=response_words[response_read];
    assign output_valid=response_count!=0;
    assign output_last=response_lasts[response_read];
    assign output_short=response_shorts[response_read];
    assign output_high_half=response_high_halves[response_read];
    wire response_take=data_valid && data_ready;
    reg [31:0] address;
    reg [17:0] remaining;
    reg [CACHE_PAGES-1:0] cache_valid,cache_pending;
    reg [15:0] cache_tag [0:CACHE_PAGES-1];
    reg prefetch_enabled;
    reg [15:0] weight_anchor;
    reg [PREFETCH_BITS-1:0] prefetch_offset;
    reg [1:0] fetch_state;
    reg [15:0] fetch_page;
    reg [7:0] raw_count,fill_count;
    reg [15:0] fill_page;
    wire stopped=!rst_n || core_abort || draining || failed;
    wire alive=!stopped;
    wire fault_event,transport_fault;
    assign raw_abort=stopped;
    assign request_ready=alive && !front_active && reserved_count==0;
    wire request_take=request_valid && request_ready;
    wire [32:0] request_end={1'b0,request_address}+{15'b0,request_bytes};
    // These are the exact transfer geometries used by the selected fixed
    // decoder. Only a single 128-byte scale transfer may start at half a beat.
    wire valid_size=request_bytes==128 || request_bytes==256 || request_bytes==4096
        || request_bytes==65536 || request_bytes==196608;
    wire malformed_request=request_take && (!valid_size || request_address[6:0]!=0
        || (request_bytes!=128 && request_address[7]) || request_end>33'd2354380800);
    wire [15:0] front_page=address[31:16];
    wire [CACHE_BITS-1:0] front_slot=cache_slot(front_page);
    wire front_match=cache_tag[front_slot]==front_page;
    wire front_hit=cache_valid[front_slot] && front_match;
    wire front_pending=cache_pending[front_slot] && front_match;
    // Credits include queued responses AND the synchronous RAM read
    // in flight. No consumer-ready or combinational fault path drives the RAM
    // enable. A fault can cause an extra PRIVATE read, never a data release:
    // data_valid is masked immediately, and the queue is discarded below.
    wire read_issue=alive && front_active && front_hit && reserved_count<3'd4;
    wire [CACHE_ADDRESS_BITS-1:0] read_address=CACHE_ADDRESS_BITS'({front_slot,address[15:8]});
    wire [2047:0] cache_read;
    assign data_valid=alive && !transport_fault && output_valid;
    assign data_last=data_valid && output_last;
    assign data=output_short
        ? {1024'b0,(output_high_half ? output_word[2047:1024] : output_word[1023:0])} : output_word;
    // A malformed core header is accepted only when no older core response
    // exists. Latch its failure before reporting it: the core may mask its
    // request when it sees error, so combinational header->error feedback can
    // erase its own cause. Transport failures still mask an existing response
    // immediately and do not depend on the current core request.
    // Transport/authentication faults still suppress data_valid and
    // cache publication in the SAME cycle and set failed on this edge.
    // Notify the core through that sticky register, avoiding a combinational
    // path from raw-memory response metadata through unrelated K/V/attention.
    // A currently verified response may not escape the immediate data gate.
    assign error=rst_n && !core_abort && failed;
    assign quiescent=rst_n && reserved_count==0
        && (stopped ? raw_quiescent : !front_active);

    // Missing demanded pages take priority. Already-reserved pages are not
    // requested twice. A reserved direct-map slot cannot be reused until its
    // verified copy is fully installed, even after a prefetch-window change.
    wire [16:0] prefetch_wide={1'b0,weight_anchor}+17'(prefetch_offset);
    reg candidate_valid;
    reg [15:0] candidate_page;
    reg [CACHE_BITS-1:0] candidate_slot;
    always @* begin
        candidate_valid=0;candidate_page=0;candidate_slot=0;
        if(front_active && !front_hit && !front_pending) begin
            candidate_page=front_page;candidate_slot=front_slot;
            candidate_valid=!cache_pending[front_slot];
        end else if(prefetch_enabled && prefetch_wide<17'd26252) begin
            candidate_page=prefetch_wide[15:0];candidate_slot=cache_slot(prefetch_wide[15:0]);
            candidate_valid=!cache_pending[candidate_slot]
                && !(cache_valid[candidate_slot] && cache_tag[candidate_slot]==candidate_page)
                && !(front_active && candidate_slot==front_slot && front_hit && candidate_page!=front_page);
        end
    end
    wire auth_load_ready,auth_data_ready,auth_valid,auth_last,auth_error,auth_busy;
    wire [15:0] auth_page;
    wire [2047:0] auth_data;
    wire reserve=alive && fetch_state==FETCH_IDLE && candidate_valid && auth_load_ready && !fault_event;
    // Reserve the verifier's private page slot before requesting bytes.
    // No ready signal feeds back through raw admission into verifier faults.
    wire auth_header_valid=alive && fetch_state==FETCH_AUTH_HEADER;
    wire auth_header_take=auth_header_valid && auth_load_ready;
    assign raw_request_valid=alive && fetch_state==FETCH_HEADER;
    assign raw_page=raw_request_valid ? fetch_page : 16'b0;
    wire raw_header_take=raw_request_valid && raw_request_ready;
    assign raw_data_ready=alive && fetch_state==FETCH_DATA && auth_data_ready;
    wire raw_take=raw_data_valid && raw_data_ready;
    qwen_model_page_auth_parallel_shared #(.WORKERS(4),.SLOTS(8),.ROOT_FILE(ROOT_FILE)) verifier(
        .clk(clk),.rst_n(rst_n),.clear(stopped),
        .load_valid(auth_header_valid),.load_ready(auth_load_ready),.load_page(fetch_page),
        .load_data_valid(alive && fetch_state==FETCH_DATA && raw_data_valid),.load_data_ready(auth_data_ready),
        .load_data(raw_data),.load_last(raw_last),.load_error(raw_error),
        .out_valid(auth_valid),.out_ready(alive),.out_data(auth_data),.out_page(auth_page),.out_last(auth_last),
        .error(auth_error),.busy(auth_busy));

    wire [CACHE_BITS-1:0] fill_slot=cache_slot(auth_page);
    wire bad_verified_response=auth_valid && (!cache_pending[fill_slot] || cache_tag[fill_slot]!=auth_page
        || (fill_count!=0 && fill_page!=auth_page) || auth_last!=(fill_count==255));
    wire bad_raw=raw_data_valid && fetch_state!=FETCH_DATA;
    assign transport_fault=alive && (raw_error || auth_error || bad_raw || bad_verified_response);
    assign fault_event=transport_fault || (alive && malformed_request);
    wire fill_take=alive && auth_valid && !fault_event;
    // Private pending slots are invalid. Extra writes at the current fill
    // position cannot overwrite an already accepted prefix or a valid page.
    // Only the unchanged fill_take advances that position; only its verified
    // final beat publishes a page. Fault/CLEAR still invalidate all slots and
    // suppress consumption immediately. No unverified byte becomes readable.
    // This changes physical RAM writes, not validity, authentication or I/O.
    wire cache_fill_write=alive && cache_pending[fill_slot];
    wire [CACHE_ADDRESS_BITS-1:0] write_address=CACHE_ADDRESS_BITS'({fill_slot,fill_count});
    genvar bank;
    generate for(bank=0;bank<4;bank=bank+1) begin:cache_banks
        (* ram_style="ultra" *) reg [511:0] memory [0:CACHE_PAGES*256-1];
        reg [511:0] read_data;
        always @(posedge clk) begin
            if(cache_fill_write) memory[write_address]<=auth_data[bank*512 +:512];
            if(read_issue) read_data<=memory[read_address];
        end
        assign cache_read[bank*512 +:512]=read_data;
    end endgenerate

    // PRIVATE_RESPONSE_CAPTURE: the outstanding synchronous read owns an
    // unpublished response slot. A fault/CLEAR may still capture these private
    // bits, but clears occupancy and suppresses every valid output immediately.
    // The unchanged queue control alone publishes a response and advances it.
    always @(posedge clk) begin
        if(read_pending) response_words[response_write]<=cache_read;
    end

    // PRIVATE_TAG_CAPTURE: tag storage is not a validity bit. A capture
    // coincident with fault_event is discarded by the unchanged all-slot
    // valid/pending invalidation on that edge. No read or publication gate
    // is relaxed, and normal reservations capture exactly the same tag.
    wire cache_tag_capture=alive && fetch_state==FETCH_IDLE && candidate_valid && auth_load_ready;
    always @(posedge clk) begin
        if(cache_tag_capture) cache_tag[candidate_slot]<=candidate_page;
    end

    always @(posedge clk) begin
        if(!rst_n || core_abort) begin failed<=0;draining<=1;end
        else if(fault_event) begin failed<=1;draining<=1;end
        else if(draining && raw_quiescent) draining<=0;
        if(stopped || fault_event) begin
            front_active<=0;address<=0;remaining<=0;
            response_count<=0;reserved_count<=0;response_read<=0;response_write<=0;
            read_pending<=0;
            cache_valid<=0;cache_pending<=0;prefetch_enabled<=0;weight_anchor<=0;prefetch_offset<=0;
            fetch_state<=FETCH_IDLE;fetch_page<=0;raw_count<=0;fill_count<=0;fill_page<=0;
        end else begin
            if(request_take) begin
                front_active<=1;address<=request_address;remaining<=request_bytes;
                if(request_address<32'd1720451072) begin
                    prefetch_enabled<=1;weight_anchor<=request_address[31:16];prefetch_offset<=0;
                end
            end
            // The RAM updates cache_read on the issuing edge; its
            // captured word and metadata enter the response queue next edge.
            // Data arrays need no reset: only the registered occupancy grants
            // visibility, and every new response overwrites its entire slot.
            read_pending<=read_issue;
            if(read_issue) begin
                read_last_q<=remaining<=256;read_short_q<=remaining==128;read_high_half_q<=address[7];
                address<=address+(remaining==128 ? 32'd128 : 32'd256);
                remaining<=remaining-(remaining==128 ? 18'd128 : 18'd256);
                if(address<32'd1720451072) weight_anchor<=front_page;
                if(remaining<=256) front_active<=0;
            end
            if(read_pending) begin
                response_lasts[response_write]<=read_last_q;
                response_shorts[response_write]<=read_short_q;
                response_high_halves[response_write]<=read_high_half_q;
                response_write<=response_write+1'b1;
            end
            if(response_take) response_read<=response_read+1'b1;
            case({read_pending,response_take})
                2'b10:response_count<=response_count+1'b1;
                2'b01:response_count<=response_count-1'b1;
                default: ;
            endcase
            case({read_issue,response_take})
                2'b10:reserved_count<=reserved_count+1'b1;
                2'b01:reserved_count<=reserved_count-1'b1;
                default: ;
            endcase
            if(fetch_state==FETCH_IDLE) begin
                if(!request_take) prefetch_offset<=prefetch_offset==PREFETCH_BITS'(PREFETCH_PAGES-1)
                    ? {PREFETCH_BITS{1'b0}} : prefetch_offset+1'b1;
                if(reserve) begin
                    fetch_page<=candidate_page;fetch_state<=FETCH_AUTH_HEADER;
                    cache_pending[candidate_slot]<=1;cache_valid[candidate_slot]<=0;
                end
            end
            if(auth_header_take) fetch_state<=FETCH_HEADER;
            if(raw_header_take) begin fetch_state<=FETCH_DATA;raw_count<=0;end
            if(raw_take) begin
                raw_count<=raw_count+1'b1;
                if(raw_count==255) fetch_state<=FETCH_IDLE;
            end
            if(fill_take) begin
                fill_count<=fill_count+1'b1;fill_page<=auth_page;
                if(auth_last) begin cache_valid[fill_slot]<=1;cache_pending[fill_slot]<=0;end
            end
        end
    end
endmodule
