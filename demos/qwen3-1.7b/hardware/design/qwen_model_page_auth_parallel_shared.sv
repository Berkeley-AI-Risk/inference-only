// PRIVATE parallel page verification experiment. Each worker uses the exact
// fixed-root verifier, retaining the page bytes until verification completes.
// Full pages are assigned round-robin and returned in the SAME submission
// order. A failure in ANY worker blocks all output immediately and is sticky
// until CLEAR/reset. There are no new application or weight-update ports.
// Invalid output payload is private/unspecified, as in the pinned verifier;
// only out_valid permits consumption. No FPGA timing/area claim is implied.
module qwen_model_page_auth_parallel_shared #(
    parameter integer WORKERS=4,
    parameter integer SLOTS=4,
    parameter ROOT_FILE="model-page-roots.hex",
    parameter [255:0] MODEL_TAG=256'h250e021a1e402acc45fa3a4ae7e925a7b5341e82d77ca2d69e4044b8c9b1fce3
) (
    input wire clk,input wire rst_n,input wire clear,
    input wire load_valid,output wire load_ready,input wire [15:0] load_page,
    input wire load_data_valid,output wire load_data_ready,
    input wire [2047:0] load_data,input wire load_last,input wire load_error,
    output wire out_valid,input wire out_ready,output wire [2047:0] out_data,
    output wire [15:0] out_page,output wire out_last,
    output wire error,output wire busy
);
    // One immutable root table for all private workers. The raw page bus
    // already reaches every worker unconditionally; preserve its two-cycle
    // address/read latency exactly. No root-write or software root-input port.
    (* ram_style="block" *) reg [255:0] roots [0:35924];
    initial $readmemh(ROOT_FILE,roots);
    (* MAX_FANOUT=64 *) reg [15:0] root_lookup_address;
    reg [255:0] fixed_root_read;
    always @(posedge clk) begin
        root_lookup_address<=load_page;
        fixed_root_read<=roots[root_lookup_address];
    end
    localparam integer WORKER_BITS=$clog2(WORKERS);
    initial if((WORKERS!=2 && WORKERS!=4) || (SLOTS!=4 && SLOTS!=8))
        $fatal(1,"Unsupported private parallel verifier geometry");
    reg failed,loading;
    reg [WORKER_BITS-1:0] write_worker,read_worker;
    reg [7:0] load_beat;
    wire alive=rst_n && !clear && !failed;
    wire [WORKERS-1:0] ready_header,ready_data,valid_output,last_output,worker_error,worker_busy;
    wire [WORKERS*2048-1:0] worker_data;
    wire [WORKERS*16-1:0] worker_page;
    // Do not combinationally gate header admission with a fault which depends
    // on that very admission. A simultaneous fault blocks OUTPUT immediately;
    // the latched failure cancels any accepted work on the following edge.
    assign load_ready=alive && !loading && ready_header[write_worker];
    assign load_data_ready=alive && loading && ready_data[write_worker];
    wire header_take=load_valid && load_ready;
    wire data_take=load_data_valid && load_data_ready;
    wire malformed_data=alive && load_data_valid && !loading;
    wire fault_event=alive && ((|worker_error) || malformed_data);
    assign error=rst_n && !clear && (failed || fault_event);
    assign out_valid=alive && !fault_event && valid_output[read_worker];
    assign out_data=worker_data[read_worker*2048+:2048];
    assign out_page=worker_page[read_worker*16+:16];
    assign out_last=last_output[read_worker];
    wire output_take=out_valid && out_ready;
    assign busy=alive && (loading || (|worker_busy));
    genvar worker;
    generate for(worker=0;worker<WORKERS;worker=worker+1) begin:workers
        qwen_model_page_auth_shared_worker #(.SLOTS(SLOTS),.ROOT_FILE(ROOT_FILE),.MODEL_TAG(MODEL_TAG)) verifier(
            .fixed_root_read(fixed_root_read),
            .clk(clk),.rst_n(rst_n),.clear(clear || failed),
            .load_valid(alive && !loading && write_worker==WORKER_BITS'(worker) && load_valid),
            .load_ready(ready_header[worker]),.load_page(load_page),
            .load_data_valid(alive && loading && write_worker==WORKER_BITS'(worker) && load_data_valid),
            .load_data_ready(ready_data[worker]),.load_data(load_data),.load_last(load_last),.load_error(load_error),
            .out_valid(valid_output[worker]),
            // A worker's transport-error detector can depend on its ready
            // input through shared RAM arbitration. Do not feed the aggregate
            // fault back into that ready input. On any fault the wrapper
            // suppresses external out_valid in the SAME cycle and discards all
            // worker state on the next edge. An internal advance during that
            // cancelled cycle cannot release bytes to the consumer.
            .out_ready(alive && read_worker==WORKER_BITS'(worker) && out_ready),
            .out_data(worker_data[worker*2048+:2048]),.out_page(worker_page[worker*16+:16]),
            .out_last(last_output[worker]),.error(worker_error[worker]),.busy(worker_busy[worker]));
    end endgenerate
    always @(posedge clk) begin
        if(!rst_n || clear) failed<=0;
        else if(fault_event) failed<=1;
        if(!alive || fault_event) begin
            loading<=0;write_worker<=0;read_worker<=0;load_beat<=0;
        end else begin
            if(header_take) begin loading<=1;load_beat<=0;end
            if(data_take) begin
                load_beat<=load_beat+1'b1;
                if(load_beat==8'd255) begin loading<=0;write_worker<=write_worker+1'b1;end
            end
            if(output_take && out_last) read_worker<=read_worker+1'b1;
        end
    end
endmodule
