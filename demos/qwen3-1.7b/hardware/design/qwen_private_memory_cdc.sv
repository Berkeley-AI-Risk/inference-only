// PRIVATE fixed-owner read/write transaction crossing, not a host memory API.
// Requests, write payloads and cancellation barriers share one ordered FIFO.
// Responses and completion/fence acknowledgements share a second FIFO.
// Completion is forwarded only AFTER the downstream write acknowledgement and
// quiescence; enqueueing bytes alone must never publish an authenticated root.
//
// During abort the producer stops and appends a barrier after accepted payload.
// The consumer drains preceding payload (or discards it after an error), then
// aborts/drains the physical adapter and returns an ordered acknowledgement.
// A stalled physical B response can delay cancellation; it cannot be forgotten.
// Fabric reset is coordinated across both endpoints and the memory controller.
// Physical CDC/skew/MTBF constraints/qualification remain external.
module qwen_private_memory_cdc #(
    parameter integer ALLOW_WRITE=1,
    parameter integer FIFO_ADDRESS_BITS=6
) (
    input wire rst_n,input wire core_clk,input wire memory_clk,
    input wire core_abort,output wire quiescent,output wire error,
    input wire request_valid,output wire request_ready,input wire request_write,
    input wire [33:0] request_address,input wire [16:0] request_bytes,
    output wire read_valid,input wire read_ready,output wire [2047:0] read_data,output wire read_last,output wire read_error,
    input wire write_valid,output wire write_ready,input wire [2047:0] write_data,input wire write_last,
    output wire done_valid,input wire done_ready,output wire done_error,
    output wire memory_reset_n,output wire memory_abort,input wire memory_quiescent,input wire memory_error,
    output wire memory_request_valid,input wire memory_request_ready,output wire memory_request_write,
    output wire [33:0] memory_request_address,output wire [16:0] memory_request_bytes,
    input wire memory_read_valid,output wire memory_read_ready,input wire [2047:0] memory_read_data,
    input wire memory_read_last,input wire memory_read_error,
    output wire memory_write_valid,input wire memory_write_ready,output wire [2047:0] memory_write_data,output wire memory_write_last,
    input wire memory_done_valid,output wire memory_done_ready,input wire memory_done_error
);
    localparam [3:0] C_SEND=0,C_WAIT=1,C_SETTLE=2,C_ABORTED=3,C_IDLE=4,C_READ=5,
        C_READ_FINISH=6,C_WRITE=7,C_WRITE_FINISH=8,C_FAILED=9;
    localparam [2:0] M_IDLE=0,M_ISSUE=1,M_ACTIVE=2,M_FINISH=3,M_CANCEL=4,M_ACK=5;
    localparam [1:0] FORWARD_REQUEST=0,FORWARD_DATA=1,FORWARD_BARRIER=2;
    localparam [1:0] RETURN_DATA=0,RETURN_COMPLETE=1,RETURN_ACK=2;
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [2:0] core_reset_release,memory_reset_release;
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [2:0] memory_error_core;
    reg [3:0] core_state;
    reg [2:0] memory_state;
    reg core_failed,memory_failed,memory_writing;
    reg [8:0] core_remaining;
    reg [33:0] memory_address;
    reg [16:0] memory_bytes;
    wire core_reset_n=core_reset_release[2];
    // MEMORY_LOCAL201: retain all three synchronizer stages and the
    // fourth-edge release. Only the ordinary output stage may be replicated.
    // Assert it through the final local stage, not the raw cross-domain net.
    (* SHREG_EXTRACT="NO", MAX_FANOUT=64 *) reg memory_reset_distributed_q;
    always @(posedge memory_clk or negedge memory_reset_release[2])begin
        if(!memory_reset_release[2])memory_reset_distributed_q<=0;
        else memory_reset_distributed_q<=1'b1;
    end
    assign memory_reset_n=memory_reset_distributed_q;
    wire core_running=core_reset_n;
    wire memory_running=memory_reset_n;
    wire core_normal=core_state==C_IDLE || core_state==C_READ || core_state==C_READ_FINISH ||
        core_state==C_WRITE || core_state==C_WRITE_FINISH || core_state==C_FAILED;
    wire observed_error=memory_error_core[2];
    wire source_active=core_running && !core_abort && !core_failed && !observed_error;
    wire memory_fault=memory_error || (memory_read_valid && memory_read_error) || (memory_done_valid && memory_done_error);
    wire memory_blocked=memory_failed || memory_fault;
    wire f_valid,f_ready,mf_valid,mf_ready,r_valid,r_ready,cr_valid,cr_ready;
    wire [2050:0] f_data,mf_data,r_data,cr_data;
    wire [1:0] forward_type=mf_data[2050:2049],return_type=cr_data[2050:2049];
    wire barrier_head=mf_valid && forward_type==FORWARD_BARRIER;
    wire barrier_take=barrier_head && mf_ready;
    wire return_take=r_valid && r_ready;
    wire core_return_take=cr_valid && cr_ready;
    wire header_ok=(request_bytes==17'd256 || request_bytes==17'd512 ||
        request_bytes==17'd4096 || request_bytes==17'd65536) && request_address[7:0]==0 &&
        (!request_write || ALLOW_WRITE!=0);

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
    // FORWARD_LOCAL190: REQUEST, DATA and BARRIER retain one order.
    // Upstream readiness and both payload-write enables use only registered
    // local occupancy. Consumer readiness can update the small read pointer
    // and count, but cannot reach the upstream FIFO RAM enable combinationally.
    wire forward_fifo_valid,forward_fifo_ready;
    wire [2050:0] forward_fifo_data;
    reg [1:0] forward_count_q;
    reg forward_read_q,forward_write_q;
    reg [2050:0] forward_slot0_q,forward_slot1_q;
    assign forward_fifo_ready=memory_running && forward_count_q<2;
    assign mf_valid=memory_running && forward_count_q!=0;
    assign mf_data=forward_read_q ? forward_slot1_q : forward_slot0_q;
    wire forward_push=forward_fifo_valid && forward_fifo_ready;
    wire forward_pop=mf_valid && mf_ready;
    always @(posedge memory_clk or negedge memory_reset_n)begin
        if(!memory_reset_n)begin
            forward_count_q<=0;forward_read_q<=0;forward_write_q<=0;
        end else begin
            case({forward_push,forward_pop})
                2'b10:forward_count_q<=forward_count_q+1'b1;
                2'b01:forward_count_q<=forward_count_q-1'b1;
                default:forward_count_q<=forward_count_q;
            endcase
            if(forward_push)forward_write_q<=!forward_write_q;
            if(forward_pop)forward_read_q<=!forward_read_q;
        end
    end
    // Predict free-slot ownership after the unchanged count/pointer update.
    // Each kept register drives at most64 payload bits, not an entire slot.
    wire [1:0] forward_count_next=forward_push && !forward_pop ? forward_count_q+2'd1 :
        !forward_push && forward_pop ? forward_count_q-2'd1 : forward_count_q;
    wire forward_write_next=forward_write_q ^ forward_push;
    genvar forward_capture_bank;
    generate for(forward_capture_bank=0;forward_capture_bank<33;forward_capture_bank=forward_capture_bank+1)begin:forward_capture_banks
        localparam integer FIRST_BIT=forward_capture_bank*64;
        localparam integer BANK_BITS=(2051-FIRST_BIT>=64) ? 64 : 2051-FIRST_BIT;
        (* KEEP="TRUE", DONT_TOUCH="TRUE" *) reg slot0_capture_q,slot1_capture_q;
        always @(posedge memory_clk or negedge memory_reset_n)begin
            if(!memory_reset_n)begin slot0_capture_q<=1'b1;slot1_capture_q<=1'b0;end
            else begin
                slot0_capture_q<=forward_count_next<2 && !forward_write_next;
                slot1_capture_q<=forward_count_next<2 && forward_write_next;
            end
        end
        // Payload is private and unreset. Never overwrite a published slot.
        always @(posedge memory_clk)begin
            if(slot0_capture_q)forward_slot0_q[FIRST_BIT+:BANK_BITS]<=forward_fifo_data[FIRST_BIT+:BANK_BITS];
            if(slot1_capture_q)forward_slot1_q[FIRST_BIT+:BANK_BITS]<=forward_fifo_data[FIRST_BIT+:BANK_BITS];
        end
    end endgenerate
    // Free-slot refresh may sample invalid FIFO data. Only the unchanged
    // forward_push publishes a packet; a full queue cannot capture here.
    qwen_async_stream_fifo #(.WIDTH(2051),.ADDRESS_BITS(FIFO_ADDRESS_BITS),.MEMORY_STYLE("block"),.ZERO_WHEN_INVALID(0)) forward_stream(
        .rst_n(rst_n),.source_clk(core_clk),.source_valid(f_valid),.source_ready(f_ready),.source_data(f_data),
        .destination_clk(memory_clk),.destination_valid(forward_fifo_valid),.destination_ready(forward_fifo_ready),.destination_data(forward_fifo_data));
    // RETURN_LOCAL130: DATA, COMPLETE and ACK share one private order.
    // Live packet admission and all error/barrier guards remain below.
    // A full ring does not accept on the same edge as a downstream pop.
    wire return_fifo_ready,return_stage_valid;
    wire [2050:0] return_stage_data;
    reg [1:0] return_count_q;
    reg return_read_q,return_write_q;
    reg [2050:0] return_slot0_q,return_slot1_q;
    assign r_ready=memory_running && return_count_q<2;
    assign return_stage_valid=memory_running && return_count_q!=0;
    assign return_stage_data=return_read_q ? return_slot1_q : return_slot0_q;
    wire return_push=r_valid && r_ready;
    wire return_pop=return_stage_valid && return_fifo_ready;
    always @(posedge memory_clk or negedge memory_reset_n)begin
        if(!memory_reset_n)begin
            return_count_q<=0;return_read_q<=0;return_write_q<=0;
        end else begin
            case({return_push,return_pop})
                2'b10:return_count_q<=return_count_q+1'b1;
                2'b01:return_count_q<=return_count_q-1'b1;
                default:return_count_q<=return_count_q;
            endcase
            if(return_push)return_write_q<=!return_write_q;
            if(return_pop)return_read_q<=!return_read_q;
        end
    end
    // Predict the original enable after this edge's count/pointer update.
    // Each kept register drives at most64 payload bits, not an entire slot.
    wire [1:0] return_count_next=return_push && !return_pop ? return_count_q+2'd1 :
        !return_push && return_pop ? return_count_q-2'd1 : return_count_q;
    wire return_write_next=return_write_q ^ return_push;
    genvar return_capture_bank;
    generate for(return_capture_bank=0;return_capture_bank<33;return_capture_bank=return_capture_bank+1)begin:return_capture_banks
        localparam integer FIRST_BIT=return_capture_bank*64;
        localparam integer BANK_BITS=(2051-FIRST_BIT>=64) ? 64 : 2051-FIRST_BIT;
        (* KEEP="TRUE", DONT_TOUCH="TRUE" *) reg slot0_capture_q,slot1_capture_q;
        always @(posedge memory_clk or negedge memory_reset_n)begin
            if(!memory_reset_n)begin slot0_capture_q<=1'b1;slot1_capture_q<=1'b0;end
            else begin
                slot0_capture_q<=return_count_next<2 && !return_write_next;
                slot1_capture_q<=return_count_next<2 && return_write_next;
            end
        end
        // Payload has no reset; only free slots may be refreshed.
        always @(posedge memory_clk)begin
            if(slot0_capture_q)return_slot0_q[FIRST_BIT+:BANK_BITS]<=r_data[FIRST_BIT+:BANK_BITS];
            if(slot1_capture_q)return_slot1_q[FIRST_BIT+:BANK_BITS]<=r_data[FIRST_BIT+:BANK_BITS];
        end
    end endgenerate
    qwen_async_stream_fifo #(.WIDTH(2051),.ADDRESS_BITS(FIFO_ADDRESS_BITS),.MEMORY_STYLE("block"),.REFRESH_FREE_WRITE_SLOT(1)) return_stream(
        .rst_n(rst_n),.source_clk(memory_clk),.source_valid(return_stage_valid),.source_ready(return_fifo_ready),.source_data(return_stage_data),
        .destination_clk(core_clk),.destination_valid(cr_valid),.destination_ready(cr_ready),.destination_data(cr_data));

    assign f_valid=core_running && (core_state==C_SEND || (source_active &&
        ((core_state==C_IDLE && request_valid) || (ALLOW_WRITE!=0 && core_state==C_WRITE && write_valid))));
    assign f_data=core_state==C_SEND ? {FORWARD_BARRIER,2049'b0} :
        core_state==C_WRITE ? {FORWARD_DATA,write_last,write_data} :
        {FORWARD_REQUEST,1997'b0,request_write,request_bytes,request_address};
    assign request_ready=source_active && core_state==C_IDLE && f_ready;
    assign write_ready=source_active && ALLOW_WRITE!=0 && core_state==C_WRITE && f_ready;
    assign read_valid=source_active && core_state==C_READ && cr_valid && return_type==RETURN_DATA;
    assign read_data=read_valid ? cr_data[2047:0] : 2048'b0;
    assign read_last=read_valid && cr_data[2048];
    assign read_error=1'b0;
    assign done_valid=source_active && core_state==C_WRITE_FINISH && cr_valid && return_type==RETURN_COMPLETE;
    assign done_error=1'b0;
    assign error=core_running && (core_failed || observed_error);
    assign quiescent=core_running && !core_failed && !observed_error &&
        ((core_state==C_IDLE && !core_abort) || core_state==C_ABORTED);
    assign cr_ready=core_running && (!source_active ||
        (core_state==C_READ ? (return_type!=RETURN_DATA || read_ready) :
         core_state==C_WRITE_FINISH ? (return_type!=RETURN_COMPLETE || done_ready) : 1'b1));

    always @(posedge core_clk or negedge core_reset_n)begin
        if(!core_reset_n)begin core_state<=C_SEND;core_failed<=0;core_remaining<=0;end
        else if(core_abort && core_normal)core_state<=C_SEND;
        else if(observed_error && core_normal)begin core_state<=C_FAILED;core_failed<=1;end
        else case(core_state)
            C_SEND:if(f_valid && f_ready)core_state<=C_WAIT;
            C_WAIT:if(core_return_take && return_type==RETURN_ACK)core_state<=C_SETTLE;
            C_SETTLE:if(!observed_error)begin core_failed<=0;core_state<=core_abort ? C_ABORTED : C_IDLE;end
            C_ABORTED:begin
                // Another owner of a shared physical transport can fault while
                // this owner remains idle with abort held high. Retire a new
                // fence for that newly latched error; waiting for abort to fall
                // would deadlock a session owner waiting for our quiescence.
                if(observed_error)core_state<=C_SEND;
                else if(!core_abort)core_state<=C_IDLE;
            end
            C_IDLE:begin
                if(cr_valid)begin core_failed<=1;core_state<=C_FAILED;end
                else if(request_valid && request_ready)begin
                    core_remaining<=request_bytes[16:8];
                    if(!header_ok)begin core_failed<=1;core_state<=C_FAILED;end
                    else core_state<=request_write ? C_WRITE : C_READ;
                end
            end
            C_READ:if(core_return_take)begin
                if(return_type!=RETURN_DATA || cr_data[2048]!=(core_remaining==9'd1) || core_remaining==0)begin
                    core_failed<=1;core_state<=C_FAILED;
                end else begin
                    core_remaining<=core_remaining-9'd1;
                    if(cr_data[2048])core_state<=C_READ_FINISH;
                end
            end
            C_READ_FINISH:if(core_return_take)begin
                if(return_type==RETURN_COMPLETE)core_state<=C_IDLE;
                else begin core_failed<=1;core_state<=C_FAILED;end
            end
            C_WRITE:if(write_valid && write_ready)begin
                if(write_last!=(core_remaining==9'd1) || core_remaining==0)begin core_failed<=1;core_state<=C_FAILED;end
                else begin core_remaining<=core_remaining-9'd1;if(write_last)core_state<=C_WRITE_FINISH;end
            end
            C_WRITE_FINISH:if(core_return_take)begin
                if(return_type==RETURN_COMPLETE)core_state<=C_IDLE;
                else begin core_failed<=1;core_state<=C_FAILED;end
            end
            C_FAILED:begin end
            default:begin core_failed<=1;core_state<=C_FAILED;end
        endcase
    end

    // Errors discard queued old-session forward words so a barrier behind them
    // cannot deadlock. Without an error, write words keep their accepted order.
    assign mf_ready=memory_running && (barrier_head ? (memory_state!=M_CANCEL && memory_state!=M_ACK) :
        (memory_blocked || (memory_state==M_IDLE && forward_type==FORWARD_REQUEST) ||
         (memory_state==M_ACTIVE && memory_writing && forward_type==FORWARD_DATA && memory_write_ready)));
    // A barrier suppresses transfers immediately below. Its accepted
    // M_CANCEL state starts physical cancellation on the next memory clock.
    // Keep abort off the FIFO-data -> adapter -> return-FIFO-enable path.
    assign memory_abort=memory_running && (memory_state==M_CANCEL || memory_state==M_ACK);
    assign memory_request_valid=memory_running && memory_state==M_ISSUE && !barrier_head && !memory_blocked;
    assign memory_request_write=memory_writing;
    assign memory_request_address=memory_address;
    assign memory_request_bytes=memory_bytes;
    assign memory_write_valid=memory_running && memory_state==M_ACTIVE && memory_writing && !memory_blocked &&
        mf_valid && forward_type==FORWARD_DATA;
    // CDC_WRITE_PAYLOAD151: private payload is meaningful only with valid.
    // Preserve the unchanged valid/ready, failure and cancellation guards.
    assign memory_write_data=mf_data[2047:0];
    assign memory_write_last=memory_write_valid && mf_data[2048];
    assign memory_done_ready=memory_running && memory_state==M_ACTIVE && memory_writing && !barrier_head && !memory_blocked;
    assign memory_read_ready=memory_running && memory_state==M_ACTIVE && !memory_writing && !barrier_head && !memory_blocked && r_ready;
    assign r_valid=memory_running && !barrier_head &&
        ((memory_state==M_ACTIVE && !memory_writing && !memory_blocked && memory_read_valid) ||
         (memory_state==M_FINISH && !memory_blocked && memory_quiescent) ||
         (memory_state==M_ACK && !memory_fault && memory_quiescent));
    // RETURN_PACKET088: only DATA packets use payload/last fields.
    // COMPLETE and ACK are interpreted solely through their unchanged type.
    // Avoid a wide zeroing mux on their semantically unused private payload.
    assign r_data={memory_state==M_ACTIVE ? RETURN_DATA :
        memory_state==M_ACK ? RETURN_ACK : RETURN_COMPLETE,memory_read_last,memory_read_data};

    always @(posedge memory_clk or negedge memory_reset_n)begin
        if(!memory_reset_n)begin
            memory_state<=M_IDLE;memory_failed<=0;memory_writing<=0;memory_address<=0;memory_bytes<=0;
        end else begin
            if(memory_fault)memory_failed<=1;
            if(barrier_take)memory_state<=M_CANCEL;
            else case(memory_state)
                M_IDLE:if(mf_valid && mf_ready && !memory_blocked)begin
                    memory_writing<=mf_data[51];memory_bytes<=mf_data[50:34];memory_address<=mf_data[33:0];
                    if(mf_data[51] && ALLOW_WRITE==0)memory_failed<=1;
                    else memory_state<=M_ISSUE;
                end
                M_ISSUE:if(memory_request_valid && memory_request_ready)memory_state<=M_ACTIVE;
                M_ACTIVE:if((return_take && memory_read_last) || (memory_done_valid && memory_done_ready))memory_state<=M_FINISH;
                M_FINISH:if(return_take)memory_state<=M_IDLE;
                M_CANCEL:if(memory_quiescent && !memory_fault)memory_state<=M_ACK;
                M_ACK:if(return_take)begin memory_failed<=0;memory_state<=M_IDLE;end
                default:begin memory_failed<=1;memory_state<=M_CANCEL;end
            endcase
        end
    end
endmodule
