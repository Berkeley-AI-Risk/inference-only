// Two-clock PRIVATE model-page path. Digital integration candidate, not yet
// physically constrained/routed or connected to the vendor HBM IP/AWS shell.
module qwen_model_hbm_cdc_reader (
    input wire rst_n,input wire core_clk,input wire memory_clk,
    input wire core_abort,output wire quiescent,output wire error,
    input wire request_valid,output wire request_ready,input wire [17:0] request_page,
    output wire data_valid,input wire data_ready,output wire [2047:0] data,output wire data_last,
    output wire [8*34-1:0] axi_araddr,output wire [8*6-1:0] axi_arid,
    output wire [8*4-1:0] axi_arlen,output wire [8*3-1:0] axi_arsize,
    output wire [8*2-1:0] axi_arburst,output wire [7:0] axi_arvalid,input wire [7:0] axi_arready,
    input wire [8*256-1:0] axi_rdata,input wire [8*6-1:0] axi_rid,
    input wire [8*2-1:0] axi_rresp,input wire [7:0] axi_rlast,input wire [7:0] axi_rvalid,
    output wire [7:0] axi_rready
);
    wire memory_reset_n,memory_abort,memory_quiescent,memory_error;
    wire memory_request_valid,memory_request_ready;
    wire [17:0] memory_request_page;
    wire memory_data_valid,memory_data_ready,memory_data_last;
    wire [2047:0] memory_data;
    qwen_model_page_cdc crossing(
        .rst_n(rst_n),.core_clk(core_clk),.memory_clk(memory_clk),
        .core_abort(core_abort),.quiescent(quiescent),.error(error),
        .request_valid(request_valid),.request_ready(request_ready),.request_page(request_page),
        .data_valid(data_valid),.data_ready(data_ready),.data(data),.data_last(data_last),
        .memory_reset_n(memory_reset_n),.memory_abort(memory_abort),
        .memory_quiescent(memory_quiescent),.memory_error(memory_error),
        .memory_request_valid(memory_request_valid),.memory_request_ready(memory_request_ready),.memory_request_page(memory_request_page),
        .memory_data_valid(memory_data_valid),.memory_data_ready(memory_data_ready),.memory_data(memory_data),.memory_data_last(memory_data_last));
    qwen_model_hbm_reader transport(
        .clk(memory_clk),.rst_n(memory_reset_n),.core_abort(memory_abort),.quiescent(memory_quiescent),.error(memory_error),
        .request_valid(memory_request_valid),.request_ready(memory_request_ready),.request_page(memory_request_page),
        .data_valid(memory_data_valid),.data_ready(memory_data_ready),.data(memory_data),.data_last(memory_data_last),
        .axi_araddr(axi_araddr),.axi_arid(axi_arid),.axi_arlen(axi_arlen),.axi_arsize(axi_arsize),.axi_arburst(axi_arburst),
        .axi_arvalid(axi_arvalid),.axi_arready(axi_arready),.axi_rdata(axi_rdata),.axi_rid(axi_rid),.axi_rresp(axi_rresp),
        .axi_rlast(axi_rlast),.axi_rvalid(axi_rvalid),.axi_rready(axi_rready));
endmodule
