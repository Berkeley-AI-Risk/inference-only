// PRIVATE baseline K/V writer: no integrity/freshness claim for external bytes.
// Same fixed layer/position and K[0..1023], V[0..1023] producer contract as the
// protected writer. Addresses never come from software. Exactly sixteen new
// 256-byte vectors are stored, without old-page reads or digest-list writes.
// This is a separately built baseline, NOT a runtime integrity-bypass input.
//
// A raw completion means the bytes are visible to subsequent reads, not merely
// queued. Cancellation waits until raw_quiescent AND reader_quiescent guarantee
// that no old work can respond or modify memory. rst_n is coordinated with the
// memory fabric. All ports below are private; none is an application interface.
module qwen_kv_plain_writer #(
    parameter integer ZERO_METADATA_WHEN_INVALID=1
) (
    input wire clk,input wire rst_n,input wire clear,
    input wire write_start_valid,output wire write_start_ready,
    input wire [4:0] write_layer,input wire [14:0] write_position,
    input wire write_valid,output wire write_ready,
    input wire write_value,input wire [9:0] write_index,input wire [15:0] write_data,
    output wire write_done_valid,input wire write_done_ready,output wire write_done_error,
    output wire error,output wire quiescent,
    input wire reader_fault,input wire reader_quiescent,output wire reader_abort,
    input wire [4:0] lookup_layer,output wire metadata_valid,
    output wire [15:0] committed_positions,
    output wire raw_request_valid,input wire raw_request_ready,
    output wire raw_request_write,output wire [33:0] raw_address,output wire [16:0] raw_bytes,
    input wire raw_read_valid,
    output wire raw_write_valid,input wire raw_write_ready,output wire [2047:0] raw_write_data,
    output wire raw_write_last,input wire raw_done_valid,output wire raw_done_ready,input wire raw_done_error,
    input wire raw_error,output wire raw_abort,input wire raw_quiescent
);
    localparam [3:0] IDLE=0,GATHER=1,REQUEST=2,SEND=3,ACK=4,DRAIN_VECTOR=5,PUBLISH=6,COMPLETE=7;
    initial if(ZERO_METADATA_WHEN_INVALID!=0 && ZERO_METADATA_WHEN_INVALID!=1)
        $fatal(1,"Invalid private metadata payload setting");
    reg [3:0] state;
    reg failed,draining,clear_seen;
    reg [4:0] next_layer,layer;
    reg [15:0] next_position;
    reg [14:0] position;
    reg [10:0] vector_index;
    wire [2047:0] vector_data;
    wire operating=rst_n && !clear && !draining && !failed;
    wire all_quiet=raw_quiescent && reader_quiescent;
    assign raw_abort=!rst_n || clear || draining || failed;
    assign reader_abort=raw_abort || write_start_valid || (state!=IDLE && state!=COMPLETE);
    assign error=rst_n && failed;
    assign quiescent=rst_n && !draining && state==IDLE && all_quiet && (!clear || clear_seen);
    assign write_start_ready=operating && state==IDLE && all_quiet;
    assign write_ready=operating && state==GATHER;
    assign write_done_valid=operating && state==COMPLETE;
    assign write_done_error=1'b0; // Failures use the sticky global error.
    assign metadata_valid=operating && (state==IDLE || state==COMPLETE) && lookup_layer<5'd28;
    // This payload goes only to the private reader. metadata_valid remains
    // unchanged and is required for consumption. Keeping invalid count bits
    // unmasked takes clear/operating out of the count datapath, without making
    // an uncommitted prefix valid or changing the writer's publication point.
    assign committed_positions=ZERO_METADATA_WHEN_INVALID!=0 && !metadata_valid
        ? 16'b0 : next_position+(lookup_layer<next_layer ? 16'd1 : 16'd0);
    wire start_take=write_start_valid && write_start_ready;
    wire input_take=write_valid && write_ready;
    wire request_take=raw_request_valid && raw_request_ready;
    wire write_take=raw_write_valid && raw_write_ready;
    wire done_take=raw_done_valid && raw_done_ready;
    assign raw_request_valid=operating && state==REQUEST;
    assign raw_request_write=raw_request_valid;
    // Same page/leaf/vector layout as the protected design. The vector index
    // is held at the final scalar of each head until its write has drained.
    wire [33:0] vector_address=34'd4294967296+{2'b0,layer,position[14:4],16'b0}
        +{18'b0,vector_index[10:7],position[3:0],8'b0};
    assign raw_address=raw_request_valid ? vector_address : 34'b0;
    assign raw_bytes=raw_request_valid ? 17'd256 : 17'b0;
    assign raw_write_valid=operating && state==SEND;
    assign raw_write_data=raw_write_valid ? vector_data : 2048'b0;
    assign raw_write_last=raw_write_valid;
    assign raw_done_ready=operating && state==ACK;
    wire bad_start=start_take && (write_layer>=5'd28 || next_position>=16'd32768
        || write_layer!=next_layer || {1'b0,write_position}!=next_position);
    wire bad_input=input_take && {write_value,write_index}!=vector_index;
    wire bad_done=done_take && raw_done_error;
    wire unsolicited_done=raw_done_valid && state!=ACK && !(state==SEND && write_take);
    wire fault=operating && (reader_fault || raw_error || raw_read_valid
        || bad_start || bad_input || bad_done || unsolicited_done);
    // Little-endian BF16 vector packing. Every one of the 128 slots is filled
    // before emission; no initialized buffer contents or partial strobes needed.
    // Constant slices share a small scalar-index decoder. A variable wide
    // part-select write needlessly synthesized a large data-routing network.
    genvar scalar;
    generate for(scalar=0;scalar<128;scalar=scalar+1)begin:vector_scalars
        reg [15:0] data;
        always @(posedge clk)begin
            if(input_take && !fault && vector_index[6:0]==7'(scalar))data<=write_data;
        end
        assign vector_data[scalar*16+:16]=data;
    end endgenerate
    always @(posedge clk)begin
        if(!rst_n)begin
            state<=IDLE;failed<=0;draining<=1;clear_seen<=0;
            next_layer<=0;next_position<=0;layer<=0;position<=0;vector_index<=0;
        end else if(clear)begin
            state<=IDLE;failed<=0;clear_seen<=1;next_layer<=0;next_position<=0;
            layer<=0;position<=0;vector_index<=0;
            if(!clear_seen)draining<=1;
            else if(all_quiet)draining<=0;
        end else begin
            clear_seen<=0;
            if(draining)begin
                if(all_quiet)draining<=0;
            end else if(fault)begin
                failed<=1;draining<=1;state<=IDLE;
            end else if(operating)case(state)
                IDLE:if(start_take)begin
                    layer<=write_layer;position<=write_position;vector_index<=0;state<=GATHER;
                end
                GATHER:if(input_take)begin
                    if(vector_index[6:0]==7'd127)state<=REQUEST;
                    else vector_index<=vector_index+11'd1;
                end
                REQUEST:if(request_take)state<=SEND;
                SEND:if(write_take)state<=ACK;
                ACK:if(done_take)state<=DRAIN_VECTOR;
                DRAIN_VECTOR:if(all_quiet)begin
                    if(vector_index==11'd2047)state<=PUBLISH;
                    else begin vector_index<=vector_index+11'd1;state<=GATHER;end
                end
                PUBLISH:if(all_quiet)begin
                    if(next_layer==5'd27)begin next_layer<=0;next_position<=next_position+16'd1;end
                    else next_layer<=next_layer+5'd1;
                    state<=COMPLETE;
                end
                COMPLETE:if(write_done_ready)state<=IDLE;
                default:begin failed<=1;draining<=1;state<=IDLE;end
            endcase
        end
    end
endmodule
