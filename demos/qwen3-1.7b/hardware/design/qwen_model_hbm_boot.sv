// PRIVATE fixed-image boot path: compute-clock loader, ordered CDC bridge and
// region-zero HBM write adapter. This is not an AWS PCIS endpoint. A bounded
// shell-clock FIFO/ingress validator is still required in front of stream_*.
// The host never supplies the physical memory address or expected model hash.
// No CLEAR/reopen input exists. Runtime fixed-root model verification remains
// mandatory after model_ready; the boot hash checks the incoming stream only.
module qwen_model_hbm_boot #(
    parameter [31:0] IMAGE_BYTES=32'd2354380800,
    parameter [255:0] IMAGE_SHA256=256'h90d82ed9b90c58607f924190be0c15f18b70d849c536a2ccbddd259858979cd1
) (
    input wire rst_n,input wire core_clk,input wire memory_clk,
    input wire stream_valid,output wire stream_ready,input wire [511:0] stream_data,input wire stream_last,
    output wire model_ready,output wire loading,output wire error,output wire [31:0] accepted_bytes,
    output wire [8*34-1:0] axi_awaddr,output wire [8*6-1:0] axi_awid,
    output wire [8*4-1:0] axi_awlen,output wire [8*3-1:0] axi_awsize,
    output wire [8*2-1:0] axi_awburst,output wire [7:0] axi_awvalid,input wire [7:0] axi_awready,
    output wire [2047:0] axi_wdata,output wire [255:0] axi_wstrb,
    output wire [7:0] axi_wlast,output wire [7:0] axi_wvalid,input wire [7:0] axi_wready,
    input wire [8*6-1:0] axi_bid,input wire [8*2-1:0] axi_bresp,input wire [7:0] axi_bvalid,output wire [7:0] axi_bready
);
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [2:0] core_reset_release;
    wire core_reset_n=core_reset_release[2];
    always @(posedge core_clk or negedge rst_n)begin
        if(!rst_n)core_reset_release<=0;
        else core_reset_release<={core_reset_release[1:0],1'b1};
    end
    wire request_valid,request_ready,write_valid,write_ready,write_last,done_valid,done_ready,done_error;
    wire [33:0] address;
    wire [16:0] bytes;
    wire [2047:0] data;
    wire abort,quiescent,transport_error;
    wire memory_reset_n,memory_abort,memory_quiescent,memory_error;
    wire memory_request_valid,memory_request_ready,memory_write_valid,memory_write_ready,memory_write_last;
    wire memory_done_valid,memory_done_ready;
    wire [33:0] memory_address;
    wire [16:0] memory_bytes;
    wire [2047:0] memory_data;
    qwen_model_boot_loader #(.IMAGE_BYTES(IMAGE_BYTES),.IMAGE_SHA256(IMAGE_SHA256)) loader(
        .clk(core_clk),.rst_n(core_reset_n),.stream_valid(stream_valid),.stream_ready(stream_ready),
        .stream_data(stream_data),.stream_last(stream_last),.model_ready(model_ready),.loading(loading),
        .error(error),.accepted_bytes(accepted_bytes),
        .memory_request_valid(request_valid),.memory_request_ready(request_ready),.memory_address(address),.memory_bytes(bytes),
        .memory_write_valid(write_valid),.memory_write_ready(write_ready),.memory_write_data(data),.memory_write_last(write_last),
        .memory_done_valid(done_valid),.memory_done_ready(done_ready),.memory_done_error(done_error),
        .memory_error(transport_error),.memory_abort(abort),.memory_quiescent(quiescent));
    qwen_private_memory_cdc #(.ALLOW_WRITE(1)) crossing(
        .rst_n(rst_n),.core_clk(core_clk),.memory_clk(memory_clk),
        .core_abort(abort),.quiescent(quiescent),.error(transport_error),
        .request_valid(request_valid),.request_ready(request_ready),.request_write(1'b1),
        .request_address(address),.request_bytes(bytes),
        .read_valid(),.read_ready(1'b1),.read_data(),.read_last(),.read_error(),
        .write_valid(write_valid),.write_ready(write_ready),.write_data(data),.write_last(write_last),
        .done_valid(done_valid),.done_ready(done_ready),.done_error(done_error),
        .memory_reset_n(memory_reset_n),.memory_abort(memory_abort),
        .memory_quiescent(memory_quiescent),.memory_error(memory_error),
        .memory_request_valid(memory_request_valid),.memory_request_ready(memory_request_ready),.memory_request_write(),
        .memory_request_address(memory_address),.memory_request_bytes(memory_bytes),
        .memory_read_valid(1'b0),.memory_read_ready(),.memory_read_data(2048'b0),.memory_read_last(1'b0),.memory_read_error(1'b0),
        .memory_write_valid(memory_write_valid),.memory_write_ready(memory_write_ready),
        .memory_write_data(memory_data),.memory_write_last(memory_write_last),
        .memory_done_valid(memory_done_valid),.memory_done_ready(memory_done_ready),.memory_done_error(1'b0));
    qwen_hbm_write_transport #(.REGION(0)) transport(
        .clk(memory_clk),.rst_n(memory_reset_n),.core_abort(memory_abort),.quiescent(memory_quiescent),.error(memory_error),
        .request_valid(memory_request_valid),.request_ready(memory_request_ready),
        .request_address(memory_address),.request_bytes(memory_bytes),
        .write_valid(memory_write_valid),.write_ready(memory_write_ready),.write_data(memory_data),.write_last(memory_write_last),
        .done_valid(memory_done_valid),.done_ready(memory_done_ready),.*);
endmodule
