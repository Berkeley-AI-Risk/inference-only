// Private ready/valid stream crossing; not yet a complete memory/abort bridge.
// Independent clocks, registered Gray pointers and three synchronizer stages.
// RAM is synchronous simple-dual-port storage, with one output holding register.
// The output register adds one word beyond the 2**ADDRESS_BITS RAM capacity.
//
// rst_n is a COORDINATED fabric reset, asserted to BOTH sides together.
// Assertion is asynchronous, release is synchronized separately in each domain.
// Do NOT use this reset for APPEND/STEP/CLEAR or independent endpoint reset.
// Application cancellation must drain/retire a protocol barrier through the
// eventual memory bridge; this FIFO does not claim transaction quiescence.
//
// Physical use still needs Gray-bus skew/delay constraints, synchronizer
// placement/MTBF and CDC reports. Simulation cannot establish metastability
// safety. ASYNC_REG is necessary implementation metadata, not that evidence.
module qwen_async_stream_fifo #(
    parameter integer WIDTH=2049,
    parameter integer ADDRESS_BITS=6,
    parameter MEMORY_STYLE="block",
    // Keep public/default outputs zero when invalid. Only a private consumer
    // with a valid-qualified capture may opt out at compile time.
    parameter integer ZERO_WHEN_INVALID=1,
    // Private compile-time mode: only refresh an unpublished/free write slot.
    // Publication still requires source_valid && source_ready.
    parameter integer REFRESH_FREE_WRITE_SLOT=0
) (
    input wire rst_n,
    input wire source_clk,input wire source_valid,output wire source_ready,input wire [WIDTH-1:0] source_data,
    input wire destination_clk,output wire destination_valid,input wire destination_ready,output wire [WIDTH-1:0] destination_data
);
    localparam integer POINTER_BITS=ADDRESS_BITS+1;
    localparam integer DEPTH=1<<ADDRESS_BITS;
    localparam [POINTER_BITS-1:0] FULL_MASK={2'b11,{(ADDRESS_BITS-1){1'b0}}};
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [2:0] source_reset_release,destination_reset_release;
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [POINTER_BITS-1:0] read_gray_source_1,read_gray_source_2,read_gray_source_3;
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [POINTER_BITS-1:0] write_gray_destination_1,write_gray_destination_2,write_gray_destination_3;
    reg [POINTER_BITS-1:0] write_binary,write_gray,read_binary,read_gray;
    reg full,output_valid;
    (* ram_style=MEMORY_STYLE *) reg [WIDTH-1:0] memory [0:DEPTH-1];
    reg [WIDTH-1:0] output_data;
    // FIFO_LOCAL_RESET183: retain all three raw-reset synchronizer stages.
    // Only the ordinary distribution stages may be replicated. Their CLR
    // inputs now come from a local synchronized release, not the raw source.
    // Both domains still release on their fourth edge; CLEAR is not reset.
    (* SHREG_EXTRACT="NO" *) reg source_reset_distributed_q,destination_reset_distributed_q;
    always @(posedge source_clk or negedge source_reset_release[2])begin
        if(!source_reset_release[2])source_reset_distributed_q<=0;
        else source_reset_distributed_q<=1'b1;
    end
    always @(posedge destination_clk or negedge destination_reset_release[2])begin
        if(!destination_reset_release[2])destination_reset_distributed_q<=0;
        else destination_reset_distributed_q<=1'b1;
    end
    wire source_reset_n=source_reset_distributed_q;
    wire destination_reset_n=destination_reset_distributed_q;
    wire source_running=source_reset_n;
    wire destination_running=destination_reset_n;
    assign source_ready=source_running && !full;
    assign destination_valid=destination_running && output_valid;
    assign destination_data=ZERO_WHEN_INVALID!=0 ? (destination_valid ? output_data : {WIDTH{1'b0}}) : output_data;
    wire write_take=source_valid && source_ready;
    wire empty=read_gray==write_gray_destination_3;
    wire read_load=destination_running && !empty && (!output_valid || destination_ready);
    wire [POINTER_BITS-1:0] write_next=write_binary+POINTER_BITS'(write_take);
    wire [POINTER_BITS-1:0] write_gray_next=(write_next>>1)^write_next;
    wire [POINTER_BITS-1:0] read_next=read_binary+POINTER_BITS'(read_load);
    wire [POINTER_BITS-1:0] read_gray_next=(read_next>>1)^read_next;

    always @(posedge source_clk or negedge rst_n)begin
        if(!rst_n)source_reset_release<=0;
        else source_reset_release<={source_reset_release[1:0],1'b1};
    end
    always @(posedge destination_clk or negedge rst_n)begin
        if(!rst_n)destination_reset_release<=0;
        else destination_reset_release<={destination_reset_release[1:0],1'b1};
    end
    // The synchronized reset must drive the control flops themselves. Merely
    // masking VALID/READY during release would leave their reset recovery and
    // removal exposed to the unrelated external reset edge.
    always @(posedge source_clk or negedge source_reset_n)begin
        if(!source_reset_n)begin
            read_gray_source_1<=0;read_gray_source_2<=0;read_gray_source_3<=0;
            write_binary<=0;write_gray<=0;full<=0;
        end else begin
            read_gray_source_1<=read_gray;read_gray_source_2<=read_gray_source_1;read_gray_source_3<=read_gray_source_2;
            write_binary<=write_next;write_gray<=write_gray_next;
            full<=write_gray_next==(read_gray_source_3^FULL_MASK);
        end
    end
    always @(posedge destination_clk or negedge destination_reset_n)begin
        if(!destination_reset_n)begin
            write_gray_destination_1<=0;write_gray_destination_2<=0;write_gray_destination_3<=0;
            read_binary<=0;read_gray<=0;output_valid<=0;
        end else begin
            write_gray_destination_1<=write_gray;write_gray_destination_2<=write_gray_destination_1;write_gray_destination_3<=write_gray_destination_2;
            read_binary<=read_next;read_gray<=read_gray_next;
            if(read_load)output_valid<=1;
            else if(destination_ready)output_valid<=0;
        end
    end
    // No data-RAM reset; neither port uses a combinational RAM read.
    // Pointer ownership prevents read/write address collisions when the
    // required physical Gray-bus/synchronizer constraints are satisfied.
    // PRIVATE_RETURN_FIFO_REFRESH120: local full/reset guard remains.
    // A write without VALID does not advance either binary or Gray pointer.
    wire memory_write_enable=REFRESH_FREE_WRITE_SLOT!=0 ? source_ready : write_take;
    always @(posedge source_clk)if(memory_write_enable)memory[write_binary[ADDRESS_BITS-1:0]]<=source_data;
    always @(posedge destination_clk)if(read_load)output_data<=memory[read_binary[ADDRESS_BITS-1:0]];
endmodule
