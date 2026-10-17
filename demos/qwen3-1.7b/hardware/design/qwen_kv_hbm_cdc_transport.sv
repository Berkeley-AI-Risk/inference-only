// PRIVATE two-clock K/V memory path. Writes and reads retain fixed internal
// owners; neither clock-domain crossing is a public memory or arithmetic API.
// Digital candidate only: no physical CDC constraints, HBM IP or shell yet.
module qwen_kv_hbm_cdc_transport (
    input wire core_clk,input wire memory_clk,input wire rst_n,
    input wire update_request_valid,output wire update_request_ready,input wire update_request_write,
    input wire [33:0] update_address,input wire [16:0] update_bytes,
    output wire update_read_valid,input wire update_read_ready,output wire [2047:0] update_read_data,
    output wire update_read_last,output wire update_read_error,
    input wire update_write_valid,output wire update_write_ready,input wire [2047:0] update_write_data,
    input wire update_write_last,output wire update_done_valid,input wire update_done_ready,output wire update_done_error,
    output wire update_error,input wire update_abort,output wire update_quiescent,
    input wire read_request_valid,output wire read_request_ready,input wire [33:0] read_address,input wire [12:0] read_bytes,
    output wire read_data_valid,input wire read_data_ready,output wire [2047:0] read_data,
    output wire read_last,output wire read_data_error,output wire read_error,input wire read_abort,output wire read_quiescent,
    output wire [16*34-1:0] axi_araddr,output wire [16*6-1:0] axi_arid,
    output wire [16*4-1:0] axi_arlen,output wire [16*3-1:0] axi_arsize,
    output wire [16*2-1:0] axi_arburst,output wire [15:0] axi_arvalid,input wire [15:0] axi_arready,
    input wire [4095:0] axi_rdata,input wire [16*6-1:0] axi_rid,
    input wire [16*2-1:0] axi_rresp,input wire [15:0] axi_rlast,input wire [15:0] axi_rvalid,output wire [15:0] axi_rready,
    output wire [16*34-1:0] axi_awaddr,output wire [16*6-1:0] axi_awid,
    output wire [16*4-1:0] axi_awlen,output wire [16*3-1:0] axi_awsize,
    output wire [16*2-1:0] axi_awburst,output wire [15:0] axi_awvalid,input wire [15:0] axi_awready,
    output wire [4095:0] axi_wdata,output wire [511:0] axi_wstrb,
    output wire [15:0] axi_wlast,output wire [15:0] axi_wvalid,input wire [15:0] axi_wready,
    input wire [16*6-1:0] axi_bid,input wire [16*2-1:0] axi_bresp,input wire [15:0] axi_bvalid,output wire [15:0] axi_bready
);
    wire memory_reset_n;
    wire m_update_request_valid;
    wire m_update_request_ready;
    wire m_update_request_write;
    wire [33:0] m_update_address;
    wire [16:0] m_update_bytes;
    wire m_update_read_valid;
    wire m_update_read_ready;
    wire [2047:0] m_update_read_data;
    wire m_update_read_last;
    wire m_update_read_error;
    wire m_update_write_valid;
    wire m_update_write_ready;
    wire [2047:0] m_update_write_data;
    wire m_update_write_last;
    wire m_update_done_valid;
    wire m_update_done_ready;
    wire m_update_done_error;
    wire m_update_error;
    wire m_update_abort;
    wire m_update_quiescent;
    wire m_read_request_valid;
    wire m_read_request_ready;
    wire [33:0] m_read_address;
    wire [16:0] m_read_bytes;
    wire m_read_data_valid;
    wire m_read_data_ready;
    wire [2047:0] m_read_data;
    wire m_read_last;
    wire m_read_data_error;
    wire m_read_error;
    wire m_read_abort;
    wire m_read_quiescent;
    qwen_private_memory_cdc #(.ALLOW_WRITE(1)) update_crossing(
        .rst_n(rst_n),.core_clk(core_clk),.memory_clk(memory_clk),.memory_reset_n(memory_reset_n),
        .core_abort(update_abort),
        .quiescent(update_quiescent),
        .error(update_error),
        .request_valid(update_request_valid),
        .request_ready(update_request_ready),
        .request_write(update_request_write),
        .request_address(update_address),
        .request_bytes(update_bytes),
        .read_valid(update_read_valid),
        .read_ready(update_read_ready),
        .read_data(update_read_data),
        .read_last(update_read_last),
        .read_error(update_read_error),
        .write_valid(update_write_valid),
        .write_ready(update_write_ready),
        .write_data(update_write_data),
        .write_last(update_write_last),
        .done_valid(update_done_valid),
        .done_ready(update_done_ready),
        .done_error(update_done_error),
        .memory_abort(m_update_abort),
        .memory_quiescent(m_update_quiescent),
        .memory_error(m_update_error),
        .memory_request_valid(m_update_request_valid),
        .memory_request_ready(m_update_request_ready),
        .memory_request_write(m_update_request_write),
        .memory_request_address(m_update_address),
        .memory_request_bytes(m_update_bytes),
        .memory_read_valid(m_update_read_valid),
        .memory_read_ready(m_update_read_ready),
        .memory_read_data(m_update_read_data),
        .memory_read_last(m_update_read_last),
        .memory_read_error(m_update_read_error),
        .memory_write_valid(m_update_write_valid),
        .memory_write_ready(m_update_write_ready),
        .memory_write_data(m_update_write_data),
        .memory_write_last(m_update_write_last),
        .memory_done_valid(m_update_done_valid),
        .memory_done_ready(m_update_done_ready),
        .memory_done_error(m_update_done_error));
    qwen_private_memory_cdc #(.ALLOW_WRITE(0)) read_crossing(
        .rst_n(rst_n),.core_clk(core_clk),.memory_clk(memory_clk),.memory_reset_n(),
        .core_abort(read_abort),
        .quiescent(read_quiescent),
        .error(read_error),
        .request_valid(read_request_valid),
        .request_ready(read_request_ready),
        .request_write(1'b0),
        .request_address(read_address),
        .request_bytes({4'b0,read_bytes}),
        .read_valid(read_data_valid),
        .read_ready(read_data_ready),
        .read_data(read_data),
        .read_last(read_last),
        .read_error(read_data_error),
        .write_valid(1'b0),
        .write_ready(),
        .write_data(2048'b0),
        .write_last(1'b0),
        .done_valid(),
        .done_ready(1'b1),
        .done_error(),
        .memory_abort(m_read_abort),
        .memory_quiescent(m_read_quiescent),
        .memory_error(m_read_error),
        .memory_request_valid(m_read_request_valid),
        .memory_request_ready(m_read_request_ready),
        .memory_request_write(),
        .memory_request_address(m_read_address),
        .memory_request_bytes(m_read_bytes),
        .memory_read_valid(m_read_data_valid),
        .memory_read_ready(m_read_data_ready),
        .memory_read_data(m_read_data),
        .memory_read_last(m_read_last),
        .memory_read_error(m_read_data_error),
        .memory_write_valid(),
        .memory_write_ready(1'b0),
        .memory_write_data(),
        .memory_write_last(),
        .memory_done_valid(1'b0),
        .memory_done_ready(),
        .memory_done_error(1'b0));
    qwen_kv_hbm_transport transport(
        .clk(memory_clk),
        .rst_n(memory_reset_n),
        .update_request_valid(m_update_request_valid),
        .update_request_ready(m_update_request_ready),
        .update_request_write(m_update_request_write),
        .update_address(m_update_address),
        .update_bytes(m_update_bytes),
        .update_read_valid(m_update_read_valid),
        .update_read_ready(m_update_read_ready),
        .update_read_data(m_update_read_data),
        .update_read_last(m_update_read_last),
        .update_read_error(m_update_read_error),
        .update_write_valid(m_update_write_valid),
        .update_write_ready(m_update_write_ready),
        .update_write_data(m_update_write_data),
        .update_write_last(m_update_write_last),
        .update_done_valid(m_update_done_valid),
        .update_done_ready(m_update_done_ready),
        .update_done_error(m_update_done_error),
        .update_error(m_update_error),
        .update_abort(m_update_abort),
        .update_quiescent(m_update_quiescent),
        .read_request_valid(m_read_request_valid),
        .read_request_ready(m_read_request_ready),
        .read_address(m_read_address),
        .read_bytes(m_read_bytes[12:0]),
        .read_data_valid(m_read_data_valid),
        .read_data_ready(m_read_data_ready),
        .read_data(m_read_data),
        .read_last(m_read_last),
        .read_data_error(m_read_data_error),
        .read_error(m_read_error),
        .read_abort(m_read_abort),
        .read_quiescent(m_read_quiescent),
        .axi_araddr(axi_araddr),
        .axi_arid(axi_arid),
        .axi_arlen(axi_arlen),
        .axi_arsize(axi_arsize),
        .axi_arburst(axi_arburst),
        .axi_arvalid(axi_arvalid),
        .axi_arready(axi_arready),
        .axi_rdata(axi_rdata),
        .axi_rid(axi_rid),
        .axi_rresp(axi_rresp),
        .axi_rlast(axi_rlast),
        .axi_rvalid(axi_rvalid),
        .axi_rready(axi_rready),
        .axi_awaddr(axi_awaddr),
        .axi_awid(axi_awid),
        .axi_awlen(axi_awlen),
        .axi_awsize(axi_awsize),
        .axi_awburst(axi_awburst),
        .axi_awvalid(axi_awvalid),
        .axi_awready(axi_awready),
        .axi_wdata(axi_wdata),
        .axi_wstrb(axi_wstrb),
        .axi_wlast(axi_wlast),
        .axi_wvalid(axi_wvalid),
        .axi_wready(axi_wready),
        .axi_bid(axi_bid),
        .axi_bresp(axi_bresp),
        .axi_bvalid(axi_bvalid),
        .axi_bready(axi_bready));
endmodule
