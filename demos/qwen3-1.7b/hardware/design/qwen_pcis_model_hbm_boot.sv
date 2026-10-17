// Startup provisioning path: bounded shell PCIS -> stream CDC -> fixed-image
// hash/loader -> private transaction CDC -> model-only AXI write channels.
// No host address enters either memory adapter. Readable ingress status belongs
// to shell_clk; model_ready/loading/error/accepted_bytes belong to core_clk.
// model_ready must be the inference core's sole boot permission.
//
// Malformed ingress is fatal until coordinated fabric reset, not application
// CLEAR. A rejected/incomplete stream may leave the private loader waiting for
// its remaining bytes; this wrapper does not claim an ingress-error drain fence.
// It closes inference permission and never resets an in-flight AXI transaction.
// Physical CDC/skew/MTBF, vendor HBM and actual shell wiring remain unqualified.
module qwen_pcis_model_hbm_boot #(
    parameter [31:0] IMAGE_BYTES=32'd2354380800,
    parameter [255:0] IMAGE_SHA256=256'h90d82ed9b90c58607f924190be0c15f18b70d849c536a2ccbddd259858979cd1
) (
    input wire rst_n,input wire shell_clk,input wire core_clk,input wire memory_clk,
    input wire [63:0] pcis_awaddr,input wire [5:0] pcis_awid,
    input wire [7:0] pcis_awlen,input wire [2:0] pcis_awsize,
    input wire pcis_awvalid,output wire pcis_awready,
    input wire [511:0] pcis_wdata,input wire [63:0] pcis_wstrb,
    input wire pcis_wlast,input wire pcis_wvalid,output wire pcis_wready,
    output wire [5:0] pcis_bid,output wire [1:0] pcis_bresp,
    output wire pcis_bvalid,input wire pcis_bready,
    input wire [63:0] pcis_araddr,input wire [5:0] pcis_arid,
    input wire [7:0] pcis_arlen,input wire [2:0] pcis_arsize,
    input wire pcis_arvalid,output wire pcis_arready,
    output wire [511:0] pcis_rdata,output wire [5:0] pcis_rid,
    output wire [1:0] pcis_rresp,output wire pcis_rlast,
    output wire pcis_rvalid,input wire pcis_rready,
    output wire ingress_error,output wire [15:0] ingress_credit_blocks,output wire [31:0] ingress_received_bytes,
    output wire model_ready,output wire loading,output wire error,output wire [31:0] accepted_bytes,
    output wire [8*34-1:0] axi_awaddr,output wire [8*6-1:0] axi_awid,
    output wire [8*4-1:0] axi_awlen,output wire [8*3-1:0] axi_awsize,
    output wire [8*2-1:0] axi_awburst,output wire [7:0] axi_awvalid,input wire [7:0] axi_awready,
    output wire [2047:0] axi_wdata,output wire [255:0] axi_wstrb,
    output wire [7:0] axi_wlast,output wire [7:0] axi_wvalid,input wire [7:0] axi_wready,
    input wire [8*6-1:0] axi_bid,input wire [8*2-1:0] axi_bresp,input wire [7:0] axi_bvalid,output wire [7:0] axi_bready
);
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [2:0] shell_reset_release,core_reset_release;
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [2:0] ready_to_shell,error_to_shell,ingress_error_to_core;
    wire shell_reset_n=shell_reset_release[2],core_reset_n=core_reset_release[2];
    wire boot_ready,boot_loading,boot_error;
    reg ready_shell_source,error_shell_source;
    // Delay only the shell-bound status copies. Native boot/inference guards
    // below still see boot_ready/boot_error immediately in the core domain.
    always @(posedge core_clk or negedge core_reset_n)begin
        if(!core_reset_n)begin ready_shell_source<=0;error_shell_source<=0;end
        else begin ready_shell_source<=boot_ready;error_shell_source<=boot_error;end
    end
    always @(posedge shell_clk or negedge rst_n)begin
        if(!rst_n)shell_reset_release<=0;
        else shell_reset_release<={shell_reset_release[1:0],1'b1};
    end
    always @(posedge core_clk or negedge rst_n)begin
        if(!rst_n)core_reset_release<=0;
        else core_reset_release<={core_reset_release[1:0],1'b1};
    end
    always @(posedge shell_clk or negedge shell_reset_n)begin
        if(!shell_reset_n)begin ready_to_shell<=0;error_to_shell<=0;end
        else begin ready_to_shell<={ready_to_shell[1:0],ready_shell_source};error_to_shell<={error_to_shell[1:0],error_shell_source};end
    end
    always @(posedge core_clk or negedge core_reset_n)begin
        if(!core_reset_n)ingress_error_to_core<=0;
        else ingress_error_to_core<={ingress_error_to_core[1:0],ingress_error};
    end
    assign error=core_reset_n && (boot_error || ingress_error_to_core[2]);
    assign model_ready=core_reset_n && boot_ready && !error;
    assign loading=core_reset_n && boot_loading && !error;
    wire shell_stream_valid,shell_stream_ready,shell_stream_last;
    wire [511:0] shell_stream_data;
    wire core_stream_valid,core_stream_ready,core_stream_last;
    wire [511:0] core_stream_data;
    qwen_pcis_model_ingress #(.IMAGE_BYTES(IMAGE_BYTES)) ingress(
        .clk(shell_clk),.rst_n(shell_reset_n),.loader_ready(ready_to_shell[2]),.loader_error(error_to_shell[2]),
        .error(ingress_error),.credit_blocks(ingress_credit_blocks),.received_bytes(ingress_received_bytes),
        .stream_valid(shell_stream_valid),.stream_ready(shell_stream_ready),
        .stream_data(shell_stream_data),.stream_last(shell_stream_last),.*);
    qwen_async_stream_fifo #(.WIDTH(513),.ADDRESS_BITS(6)) ingress_crossing(
        .rst_n(rst_n),.source_clk(shell_clk),.source_valid(shell_stream_valid),.source_ready(shell_stream_ready),
        .source_data({shell_stream_last,shell_stream_data}),.destination_clk(core_clk),
        .destination_valid(core_stream_valid),.destination_ready(core_stream_ready),
        .destination_data({core_stream_last,core_stream_data}));
    qwen_model_hbm_boot #(.IMAGE_BYTES(IMAGE_BYTES),.IMAGE_SHA256(IMAGE_SHA256)) boot(
        .stream_valid(core_stream_valid),.stream_ready(core_stream_ready),
        .stream_data(core_stream_data),.stream_last(core_stream_last),
        .model_ready(boot_ready),.loading(boot_loading),.error(boot_error),.*);
endmodule
