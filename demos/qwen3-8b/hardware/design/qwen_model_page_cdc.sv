// PRIVATE model-page stream clock crossing with an ordered cancellation fence.
// Neither interface is an application API. At most one 64 KiB page is owned.
// CLEAR uses core_abort, never rst_n. A barrier follows accepted requests;
// its acknowledgement follows every earlier response AND downstream drainage.
// Normal completion also waits for a separate downstream-quiescent marker.
//
// memory_error is made sticky in the memory domain and synchronized separately
// from data. Thus a full/stalled return FIFO cannot hide an error indefinitely.
// After a barrier ACK, the core waits for that synchronized error to clear
// before reopening. ID/framing faults that prevent downstream quiescence never
// receive a barrier ACK; recovery requires a coordinated fabric reset.
//
// Only the pre-handshake PRIVATE page request can be cancelled. The downstream
// AXI adapter owns accepted ARVALID and must preserve/drain actual bus traffic.
// rst_n resets both FIFO ends AND the memory fabric together. Independent reset
// is unsupported. Physical CDC constraints/placement/MTBF remain unqualified.
module qwen_model_page_cdc #(
    parameter integer RETURN_ADDRESS_BITS=6
) (
    input wire rst_n,input wire core_clk,input wire memory_clk,
    input wire core_abort,output wire quiescent,output wire error,
    input wire request_valid,output wire request_ready,input wire [17:0] request_page,
    output wire data_valid,input wire data_ready,output wire [2047:0] data,output wire data_last,
    output wire memory_reset_n,output wire memory_abort,
    input wire memory_quiescent,input wire memory_error,
    output wire memory_request_valid,input wire memory_request_ready,output wire [17:0] memory_request_page,
    input wire memory_data_valid,output wire memory_data_ready,input wire [2047:0] memory_data,input wire memory_data_last
);
    localparam [3:0] C_SEND=0,C_WAIT=1,C_SETTLE=2,C_ABORTED=3,C_IDLE=4,C_PAGE=5,C_FINISH=6,C_FAILED=7;
    localparam [2:0] M_IDLE=0,M_ISSUE=1,M_PAGE=2,M_FINISH=3,M_CANCEL=4,M_ACK=5;
    localparam [1:0] RETURN_DATA=0,RETURN_DONE=1,RETURN_ACK=2;
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [2:0] core_reset_release,memory_reset_release;
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [2:0] memory_error_core;
    reg [3:0] core_state;
    reg [2:0] memory_state;
    reg core_failed,memory_failed;
    reg [7:0] core_beat;
    reg [17:0] memory_page;
    wire core_reset_n=core_reset_release[2];
    assign memory_reset_n=memory_reset_release[2];
    wire core_running=core_reset_n;
    wire memory_running=memory_reset_n;
    wire core_normal=core_state==C_IDLE || core_state==C_PAGE || core_state==C_FINISH || core_state==C_FAILED;
    wire observed_error=memory_error_core[2];
    wire request_fifo_valid,request_fifo_ready,request_at_memory_valid,request_at_memory_ready;
    wire [18:0] request_fifo_data,request_at_memory_data;
    wire return_fifo_valid,return_fifo_ready,return_at_core_valid,return_at_core_ready;
    wire [2050:0] return_fifo_data,return_at_core_data;
    wire [1:0] return_type=return_at_core_data[2050:2049];
    wire barrier_head=request_at_memory_valid && request_at_memory_data[18];
    wire memory_blocked=memory_error || memory_failed;
    wire barrier_take=request_at_memory_valid && request_at_memory_ready && barrier_head;
    wire memory_return_take=return_fifo_valid && return_fifo_ready;
    wire core_return_take=return_at_core_valid && return_at_core_ready;

    always @(posedge core_clk or negedge rst_n)begin
        if(!rst_n)core_reset_release<=0;
        else core_reset_release<={core_reset_release[1:0],1'b1};
    end
    always @(posedge memory_clk or negedge rst_n)begin
        if(!rst_n)memory_reset_release<=0;
        else memory_reset_release<={memory_reset_release[1:0],1'b1};
    end
    always @(posedge core_clk or negedge core_reset_n)begin
        if(!core_reset_n)memory_error_core<=0;
        else memory_error_core<={memory_error_core[1:0],memory_failed};
    end
    qwen_async_stream_fifo #(.WIDTH(19),.ADDRESS_BITS(3),.MEMORY_STYLE("distributed")) requests(
        .rst_n(rst_n),.source_clk(core_clk),.source_valid(request_fifo_valid),.source_ready(request_fifo_ready),.source_data(request_fifo_data),
        .destination_clk(memory_clk),.destination_valid(request_at_memory_valid),.destination_ready(request_at_memory_ready),.destination_data(request_at_memory_data));
    // PRIVATE_MODEL_RETURN059_BEGIN
    reg return_pipe_valid;
    reg [2050:0] return_pipe_data;
    wire return_pipe_ready;
    assign return_fifo_ready=!return_pipe_valid || return_pipe_ready;
    always @(posedge memory_clk or negedge memory_reset_n)begin
        if(!memory_reset_n)return_pipe_valid<=0;
        else if(return_fifo_ready)return_pipe_valid<=return_fifo_valid;
    end
    // Capture invalid payload as well when the slot is free. Only the small
    // valid register depends on the incoming valid/quiescence path. The FIFO
    // writes payload only when this slot is valid; stalled payload is held.
    always @(posedge memory_clk)begin
        if(return_fifo_ready)return_pipe_data<=return_fifo_data;
    end
    // Do not flush on a barrier or core CLEAR: DATA/DONE/ACK ordering matters.
    // PRIVATE_MODEL_RETURN059_END
    qwen_async_stream_fifo #(.WIDTH(2051),.ADDRESS_BITS(RETURN_ADDRESS_BITS),.MEMORY_STYLE("block")) responses(
        .rst_n(rst_n),.source_clk(memory_clk),.source_valid(return_pipe_valid),.source_ready(return_pipe_ready),.source_data(return_pipe_data),
        .destination_clk(core_clk),.destination_valid(return_at_core_valid),.destination_ready(return_at_core_ready),.destination_data(return_at_core_data));

    assign request_fifo_valid=core_running && (core_state==C_SEND ||
        (core_state==C_IDLE && !core_abort && !core_failed && !observed_error && request_valid));
    assign request_fifo_data=core_state==C_SEND ? {1'b1,18'b0} : {1'b0,request_page};
    assign request_ready=core_running && core_state==C_IDLE && !core_abort && !core_failed && !observed_error && request_fifo_ready;
    assign data_valid=core_running && core_state==C_PAGE && !core_abort && !core_failed && !observed_error &&
        return_at_core_valid && return_type==RETURN_DATA;
    // PRIVATE_RETURN_PAYLOAD: invalid bytes are not observable by the API.
    // Keep data_valid and every downstream valid-qualified capture unchanged.
    assign data=return_at_core_data[2047:0];
    // PRIVATE_LAST_METADATA: downstream use remains VALID-qualified.
    assign data_last=return_at_core_data[2048];
    assign error=core_running && (core_failed || observed_error);
    assign quiescent=core_running && !core_failed && !observed_error &&
        ((core_state==C_IDLE && !core_abort) || core_state==C_ABORTED);
    // During cancellation/error, drain returned data regardless of the core's
    // data_ready. This lets the ordered fence progress even from a full FIFO.
    assign return_at_core_ready=core_running && (core_state!=C_PAGE || core_abort || core_failed ||
        observed_error || return_type!=RETURN_DATA || data_ready);

    always @(posedge core_clk or negedge core_reset_n)begin
        if(!core_reset_n)begin core_state<=C_SEND;core_failed<=0;core_beat<=0;end
        else if(core_abort && core_normal)core_state<=C_SEND;
        else if(observed_error && core_normal)begin core_state<=C_FAILED;core_failed<=1;end
        else case(core_state)
            C_SEND:if(request_fifo_valid && request_fifo_ready)core_state<=C_WAIT;
            C_WAIT:if(core_return_take && return_type==RETURN_ACK)core_state<=C_SETTLE;
            C_SETTLE:if(!observed_error)begin
                core_failed<=0;core_state<=core_abort ? C_ABORTED : C_IDLE;
            end
            C_ABORTED:if(!core_abort)core_state<=C_IDLE;
            C_IDLE:begin
                if(return_at_core_valid)begin core_failed<=1;core_state<=C_FAILED;end
                else if(request_valid && request_ready)begin core_beat<=0;core_state<=C_PAGE;end
            end
            C_PAGE:if(core_return_take)begin
                if(return_type!=RETURN_DATA || return_at_core_data[2048]!=(core_beat==8'd255))begin
                    core_failed<=1;core_state<=C_FAILED;
                end else if(return_at_core_data[2048])core_state<=C_FINISH;
                else core_beat<=core_beat+8'd1;
            end
            C_FINISH:if(core_return_take)begin
                if(return_type==RETURN_DONE)core_state<=C_IDLE;
                else begin core_failed<=1;core_state<=C_FAILED;end
            end
            C_FAILED:begin end
            default:begin core_failed<=1;core_state<=C_FAILED;end
        endcase
    end

    // A barrier can preempt an issued/failed page even with return backpressure.
    assign request_at_memory_ready=memory_running &&
        ((barrier_head && memory_state!=M_CANCEL && memory_state!=M_ACK) ||
         (!barrier_head && memory_state==M_IDLE && !memory_blocked));
    assign memory_abort=memory_running && (barrier_head || memory_state==M_CANCEL || memory_state==M_ACK);
    assign memory_request_valid=memory_running && memory_state==M_ISSUE && !barrier_head && !memory_blocked;
    assign memory_request_page=memory_page;
    assign memory_data_ready=memory_running && memory_state==M_PAGE && !barrier_head && !memory_blocked && return_fifo_ready;
    assign return_fifo_valid=memory_running && !barrier_head &&
        ((memory_state==M_PAGE && !memory_blocked && memory_data_valid) ||
         (memory_state==M_FINISH && !memory_blocked && memory_quiescent) ||
         (memory_state==M_ACK && !memory_error && memory_quiescent));
    // MODEL_PACKET204: only DATA packets use these private lower bits.
    // Keep the exact type and every publication/cancellation/error guard.
    assign return_fifo_data={memory_state==M_PAGE ? RETURN_DATA :
        memory_state==M_ACK ? RETURN_ACK : RETURN_DONE,memory_data_last,memory_data};

    always @(posedge memory_clk or negedge memory_reset_n)begin
        if(!memory_reset_n)begin memory_state<=M_IDLE;memory_page<=0;memory_failed<=0;end
        else begin
            if(memory_error)memory_failed<=1;
            if(barrier_take)memory_state<=M_CANCEL;
            else case(memory_state)
                M_IDLE:if(request_at_memory_valid && request_at_memory_ready)begin
                    memory_page<=request_at_memory_data[17:0];memory_state<=M_ISSUE;
                end
                M_ISSUE:if(memory_request_valid && memory_request_ready)memory_state<=M_PAGE;
                M_PAGE:if(memory_return_take && memory_data_last)memory_state<=M_FINISH;
                M_FINISH:if(memory_return_take)memory_state<=M_IDLE;
                M_CANCEL:if(memory_quiescent && !memory_error)memory_state<=M_ACK;
                M_ACK:if(memory_return_take)begin memory_failed<=0;memory_state<=M_IDLE;end
                default:begin memory_failed<=1;memory_state<=M_CANCEL;end
            endcase
        end
    end
endmodule
