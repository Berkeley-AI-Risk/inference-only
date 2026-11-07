// PRIVATE trusted-state owner for an append-only, integrity-protected tensor
// store. MODEL-INDEPENDENT: geometry, root width and initial epoch are
// compile-time parameters. No application-visible root/address/hash API exists,
// and this module knows nothing about AWS, HBM or the hash function.
//
// Derived from qwen_kv_root_owner.sv (sha256 a509483c6023aeb9...). Behavior at the
// default parameters is unchanged apart from ZERO_METADATA_WHEN_INVALID, which
// the Qwen store sets to 0 to take the operating/clear cone out of the payload
// datapath, following the released plain K/V writer and reader.
//
// Only the fixed update engine may begin/commit a transaction. It must
// authenticate retained old bytes, construct the new page, and wait for every
// external write to complete BEFORE asserting commit_valid. This module enforces
// coordinates, epoch, publication order and validity; it does not hash or
// transfer data.
//
// Read lookup is serialized against an update transaction. Committed positions
// are derived from the fixed position-major, layer-minor append schedule.
// RAM has no reset/initial contents: reset/CLEAR invalidate all old roots using
// the schedule counters. transport_quiescent must mean cancelled old work can
// no longer modify memory or produce a response. Per-operation read cancellation
// is NOT this module's session_clear signal.
module kvi_root_owner #(
    parameter integer LAYERS=28,
    parameter integer LAYER_BITS=5,
    parameter integer POSITION_BITS=15,
    parameter integer PAGE_POSITION_BITS=4,
    parameter integer ROOT_BITS=256,
    parameter [63:0] INITIAL_EPOCH=64'd0,
    parameter integer ZERO_METADATA_WHEN_INVALID=1
) (
    input wire clk,input wire rst_n,input wire session_clear,
    input wire external_fault,input wire transport_quiescent,
    output wire transport_abort,output wire quiescent,output wire error,

    input wire begin_valid,output wire begin_ready,
    input wire [LAYER_BITS-1:0] begin_layer,input wire [POSITION_BITS:0] begin_position,
    output wire metadata_valid,input wire metadata_ready,
    output wire [63:0] metadata_epoch,output wire [LAYER_BITS-1:0] metadata_layer,
    output wire [POSITION_BITS:0] metadata_position,output wire [PAGE_POSITION_BITS:0] metadata_old_count,
    output wire [ROOT_BITS-1:0] metadata_old_root,

    input wire commit_valid,output wire commit_ready,
    input wire [63:0] commit_epoch,input wire [LAYER_BITS-1:0] commit_layer,
    input wire [POSITION_BITS:0] commit_position,input wire [ROOT_BITS-1:0] commit_root,
    output wire published_valid,input wire published_ready,

    input wire lookup_valid,output wire lookup_ready,
    input wire [LAYER_BITS-1:0] lookup_layer,input wire [POSITION_BITS:0] lookup_position,
    output wire result_valid,input wire result_ready,
    output wire [63:0] result_epoch,output wire [LAYER_BITS-1:0] result_layer,
    output wire [POSITION_BITS:0] result_position,output wire [PAGE_POSITION_BITS:0] result_count,
    output wire [POSITION_BITS:0] result_total_positions,
    output wire [ROOT_BITS-1:0] result_root
);
    localparam integer GROUP_BITS=POSITION_BITS-PAGE_POSITION_BITS;
    localparam integer ROOT_DEPTH=LAYERS<<GROUP_BITS;
    localparam [LAYER_BITS-1:0] LAST_LAYER=LAYER_BITS'(LAYERS-1);
    localparam [LAYER_BITS-1:0] LAYER_LIMIT=LAYER_BITS'(LAYERS);
    localparam [POSITION_BITS+1:0] POSITION_LIMIT={2'b01,{POSITION_BITS{1'b0}}};
    localparam [POSITION_BITS+1:0] PAGE_POSITIONS=(POSITION_BITS+2)'(1)<<PAGE_POSITION_BITS;
    initial if(LAYERS<1 || LAYER_BITS<1 || (LAYERS>>LAYER_BITS)!=0 || (LAYERS-1)>>(LAYER_BITS-1)==0 && LAYERS>2
        || PAGE_POSITION_BITS<1 || GROUP_BITS<1 || ROOT_BITS<1
        || (ZERO_METADATA_WHEN_INVALID!=0 && ZERO_METADATA_WHEN_INVALID!=1))
        $fatal(1,"Invalid private root-owner geometry");
    localparam [2:0] IDLE=0,W_META=1,W_COMMIT=2,W_PUBLISHED=3,R_RESULT=4;
    reg [2:0] state;
    reg [63:0] epoch;
    reg [LAYER_BITS-1:0] next_layer;
    reg [POSITION_BITS:0] next_position;
    reg failed,exhausted,clear_seen,draining;
    reg [LAYER_BITS-1:0] saved_layer;
    reg [PAGE_POSITION_BITS:0] saved_count;
    reg [POSITION_BITS:0] saved_position,saved_total_positions;
    // Write-filled trusted state: unlike immutable model roots, UltraRAM does
    // not need nonzero initialization here. Physical fit/timing still required.
    (* ram_style="ultra" *) reg [ROOT_BITS-1:0] roots [0:ROOT_DEPTH-1];
    reg [ROOT_BITS-1:0] root_q;

    wire operating=rst_n && !session_clear && !draining && !failed && !exhausted;
    assign error=rst_n && (failed || exhausted);
    assign transport_abort=!rst_n || session_clear || draining || failed || exhausted;
    assign quiescent=rst_n && !draining && state==IDLE && transport_quiescent
        && (!session_clear || clear_seen);
    // Register faults before reporting them: request/output suppression must
    // not form a combinational loop through a consumer's fault detection.
    assign commit_ready=operating && (state==W_COMMIT || state==IDLE);
    assign begin_ready=operating && state==IDLE && !commit_valid;
    assign lookup_ready=operating && state==IDLE && !commit_valid && !begin_valid;
    assign metadata_valid=operating && state==W_META;
    assign published_valid=operating && state==W_PUBLISHED;
    assign result_valid=operating && state==R_RESULT;
    // Compile-time PRIVATE payload option. Consumers use these buses only on the
    // unchanged valid signals above, and neither valid signal changes with it.
    wire metadata_visible=ZERO_METADATA_WHEN_INVALID==0 || metadata_valid;
    wire result_visible=ZERO_METADATA_WHEN_INVALID==0 || result_valid;
    assign metadata_epoch=metadata_visible ? epoch : 64'b0;
    assign metadata_layer=metadata_visible ? saved_layer : {LAYER_BITS{1'b0}};
    assign metadata_position=metadata_visible ? saved_position : {(POSITION_BITS+1){1'b0}};
    assign metadata_old_count=metadata_visible ? saved_count : {(PAGE_POSITION_BITS+1){1'b0}};
    assign metadata_old_root=metadata_visible && saved_count!=0 ? root_q : {ROOT_BITS{1'b0}};
    assign result_epoch=result_visible ? epoch : 64'b0;
    assign result_layer=result_visible ? saved_layer : {LAYER_BITS{1'b0}};
    assign result_position=result_visible ? saved_position : {(POSITION_BITS+1){1'b0}};
    assign result_count=result_visible ? saved_count : {(PAGE_POSITION_BITS+1){1'b0}};
    // The private reader uses this trusted prefix bound for safe prefetch.
    // It must not guess whether another full group exists from result_count.
    assign result_total_positions=result_visible ? saved_total_positions : {(POSITION_BITS+1){1'b0}};
    assign result_root=result_visible ? root_q : {ROOT_BITS{1'b0}};

    wire begin_fire=begin_valid && begin_ready;
    wire lookup_fire=lookup_valid && lookup_ready;
    wire commit_fire=commit_valid && commit_ready;
    wire begin_ok=begin_layer<LAYER_LIMIT && {1'b0,begin_position}<POSITION_LIMIT
        && begin_layer==next_layer && begin_position==next_position;
    wire commit_ok=state==W_COMMIT && commit_epoch==epoch
        && commit_layer==saved_layer && commit_position==saved_position;
    wire [POSITION_BITS+1:0] layer_count={1'b0,next_position}
        +(lookup_layer<next_layer ? (POSITION_BITS+2)'(1) : (POSITION_BITS+2)'(0));
    wire lookup_ok=lookup_layer<LAYER_LIMIT && {1'b0,lookup_position}<POSITION_LIMIT
        && {1'b0,lookup_position}<layer_count;
    wire [POSITION_BITS+1:0] group_base={2'b0,lookup_position[POSITION_BITS-1:PAGE_POSITION_BITS],{PAGE_POSITION_BITS{1'b0}}};
    wire [POSITION_BITS+1:0] group_remaining=layer_count-group_base;
    wire [PAGE_POSITION_BITS:0] lookup_count=group_remaining>=PAGE_POSITIONS
        ? {1'b1,{PAGE_POSITION_BITS{1'b0}}} : group_remaining[PAGE_POSITION_BITS:0];
    wire [LAYER_BITS+GROUP_BITS-1:0] root_address=begin_fire
        ? {begin_layer,begin_position[POSITION_BITS-1:PAGE_POSITION_BITS]}
        : {lookup_layer,lookup_position[POSITION_BITS-1:PAGE_POSITION_BITS]};
    wire root_read=!external_fault && ((begin_fire && begin_ok && begin_position[PAGE_POSITION_BITS-1:0]!=0)
        || (lookup_fire && lookup_ok));
    wire root_write=!external_fault && commit_fire && commit_ok;
    // One synchronous read port and one synchronous write port. They are never
    // used together; no same-address read/write behavior is relied upon.
    always @(posedge clk) begin
        if(root_read)root_q<=roots[root_address];
        if(root_write)roots[{saved_layer,saved_position[POSITION_BITS-1:PAGE_POSITION_BITS]}]<=commit_root;
    end

    always @(posedge clk) begin
        if(!rst_n)begin
            state<=IDLE;epoch<=INITIAL_EPOCH;next_layer<=0;next_position<=0;
            failed<=0;exhausted<=0;clear_seen<=0;draining<=1;
            saved_layer<=0;saved_position<=0;saved_count<=0;saved_total_positions<=0;
        end else if(session_clear)begin
            state<=IDLE;next_layer<=0;next_position<=0;
            clear_seen<=1;
            if(!clear_seen)begin
                draining<=1;
                if(epoch==64'hffffffffffffffff || exhausted)begin
                    failed<=1;exhausted<=1;
                end else begin epoch<=epoch+64'd1;failed<=0;end
            end else if(transport_quiescent)draining<=0;
        end else begin
            clear_seen<=0;
            if(draining)begin
                if(transport_quiescent)draining<=0;
            end else if(!failed && !exhausted)begin
                if(external_fault || (begin_fire && !begin_ok)
                    || (lookup_fire && !lookup_ok) || (commit_fire && !commit_ok))begin
                    failed<=1;draining<=1;state<=IDLE;
                end else case(state)
                    IDLE:begin
                        if(begin_fire)begin
                            saved_layer<=begin_layer;saved_position<=begin_position;
                            saved_count<={1'b0,begin_position[PAGE_POSITION_BITS-1:0]};state<=W_META;
                        end else if(lookup_fire)begin
                            saved_layer<=lookup_layer;saved_position<=lookup_position;
                            saved_count<=lookup_count;saved_total_positions<=layer_count[POSITION_BITS:0];state<=R_RESULT;
                        end
                    end
                    W_META:if(metadata_ready)state<=W_COMMIT;
                    W_COMMIT:if(commit_fire)begin
                        if(next_layer==LAST_LAYER)begin next_layer<=0;next_position<=next_position+1'b1;end
                        else next_layer<=next_layer+1'b1;
                        state<=W_PUBLISHED;
                    end
                    W_PUBLISHED:if(published_ready)state<=IDLE;
                    R_RESULT:if(result_ready)state<=IDLE;
                    default:begin failed<=1;draining<=1;state<=IDLE;end
                endcase
            end
        end
    end
endmodule
