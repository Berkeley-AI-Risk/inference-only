// Complete protected Qwen token machine with separately clocked private HBM
// transports. Only cmd/response is the application boundary, in core_clk.
// model_ready must also belong to core_clk. Raw AXI belongs inside the image,
// never a host-visible memory service. No vendor HBM, provisioning or AWS shell
// is instantiated yet; physical CDC/skew/reset/timing qualification is pending.
// rst_n is a coordinated reset of both domains AND the memory fabric. CLEAR
// instead retires ordered memory cancellation fences without resetting buses.
module qwen_hbm_cdc_verified_machine #(
    parameter integer MODEL_PREFETCH_PAGES=8,
    parameter integer KV_CACHE_GROUPS=128,
    parameter integer KV_AUTH_SLOTS=128,
    parameter integer KV_PREFETCH_GROUPS=128,
    parameter SILU_ROM_FILE="silu-bf16.hex",
    parameter EXP_ROM_FILE="softmax-exp2.hex",
    parameter ROOT_FILE="model-page-roots.hex"
) (
    input wire core_clk,input wire memory_clk,input wire rst_n,input wire model_ready,
    input wire cmd_valid,input wire cmd_clear_valid,output wire cmd_ready,input wire [7:0] cmd_opcode,input wire [31:0] cmd_token,
    output wire response_valid,input wire response_ready,
    output wire [3:0] response_status,output wire [31:0] response_token,output wire busy,
    output wire [8*34-1:0] model_axi_araddr,output wire [8*6-1:0] model_axi_arid,
    output wire [8*4-1:0] model_axi_arlen,output wire [8*3-1:0] model_axi_arsize,
    output wire [8*2-1:0] model_axi_arburst,output wire [7:0] model_axi_arvalid,input wire [7:0] model_axi_arready,
    input wire [8*256-1:0] model_axi_rdata,input wire [8*6-1:0] model_axi_rid,
    input wire [8*2-1:0] model_axi_rresp,input wire [7:0] model_axi_rlast,input wire [7:0] model_axi_rvalid,
    output wire [7:0] model_axi_rready,
    output wire [16*34-1:0] kv_axi_araddr,output wire [16*6-1:0] kv_axi_arid,
    output wire [16*4-1:0] kv_axi_arlen,output wire [16*3-1:0] kv_axi_arsize,
    output wire [16*2-1:0] kv_axi_arburst,output wire [15:0] kv_axi_arvalid,input wire [15:0] kv_axi_arready,
    input wire [4095:0] kv_axi_rdata,input wire [16*6-1:0] kv_axi_rid,
    input wire [16*2-1:0] kv_axi_rresp,input wire [15:0] kv_axi_rlast,input wire [15:0] kv_axi_rvalid,output wire [15:0] kv_axi_rready,
    output wire [16*34-1:0] kv_axi_awaddr,output wire [16*6-1:0] kv_axi_awid,
    output wire [16*4-1:0] kv_axi_awlen,output wire [16*3-1:0] kv_axi_awsize,
    output wire [16*2-1:0] kv_axi_awburst,output wire [15:0] kv_axi_awvalid,input wire [15:0] kv_axi_awready,
    output wire [4095:0] kv_axi_wdata,output wire [511:0] kv_axi_wstrb,
    output wire [15:0] kv_axi_wlast,output wire [15:0] kv_axi_wvalid,input wire [15:0] kv_axi_wready,
    input wire [16*6-1:0] kv_axi_bid,input wire [16*2-1:0] kv_axi_bresp,input wire [15:0] kv_axi_bvalid,output wire [15:0] kv_axi_bready
);
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [2:0] core_reset_release;
    wire core_reset_n /* verilator public_flat_rd */;
    // CORE_LOCAL194: only this ordinary stage may be replicated.
    // Its asynchronous assertion comes through the intact final local
    // synchronizer. Release requires one additional core edge. Application
    // CLEAR remains a separate signal and does not enter this reset chain.
    (* SHREG_EXTRACT="NO", MAX_FANOUT=64 *) reg core_reset_distributed_q;
    always @(posedge core_clk or negedge core_reset_release[2])begin
        if(!core_reset_release[2])core_reset_distributed_q<=0;
        else core_reset_distributed_q<=1'b1;
    end
    assign core_reset_n=core_reset_distributed_q;
    always @(posedge core_clk or negedge rst_n)begin
        if(!rst_n)core_reset_release<=0;
        else core_reset_release<={core_reset_release[1:0],1'b1};
    end
    wire raw_model_request_valid /* verilator public_flat_rd */;
    wire raw_model_request_ready /* verilator public_flat_rd */;
    wire [15:0] raw_model_page /* verilator public_flat_rd */;
    wire raw_model_data_valid /* verilator public_flat_rd */;
    wire raw_model_data_ready /* verilator public_flat_rd */;
    wire [2047:0] raw_model_data /* verilator public_flat_rd */;
    wire raw_model_last /* verilator public_flat_rd */;
    wire raw_model_error /* verilator public_flat_rd */;
    wire raw_model_abort /* verilator public_flat_rd */;
    wire raw_model_quiescent /* verilator public_flat_rd */;
    wire kv_update_request_valid /* verilator public_flat_rd */;
    wire kv_update_request_ready /* verilator public_flat_rd */;
    wire kv_update_request_write /* verilator public_flat_rd */;
    wire [33:0] kv_update_address /* verilator public_flat_rd */;
    wire [16:0] kv_update_bytes /* verilator public_flat_rd */;
    wire kv_update_read_valid /* verilator public_flat_rd */;
    wire kv_update_read_ready /* verilator public_flat_rd */;
    wire [2047:0] kv_update_read_data /* verilator public_flat_rd */;
    wire kv_update_read_last /* verilator public_flat_rd */;
    wire kv_update_read_error /* verilator public_flat_rd */;
    wire kv_update_write_valid /* verilator public_flat_rd */;
    wire kv_update_write_ready /* verilator public_flat_rd */;
    wire [2047:0] kv_update_write_data /* verilator public_flat_rd */;
    wire kv_update_write_last /* verilator public_flat_rd */;
    wire kv_update_done_valid /* verilator public_flat_rd */;
    wire kv_update_done_ready /* verilator public_flat_rd */;
    wire kv_update_done_error /* verilator public_flat_rd */;
    wire kv_update_error /* verilator public_flat_rd */;
    wire kv_update_abort /* verilator public_flat_rd */;
    wire kv_update_quiescent /* verilator public_flat_rd */;
    wire kv_read_request_valid /* verilator public_flat_rd */;
    wire kv_read_request_ready /* verilator public_flat_rd */;
    wire [33:0] kv_read_address /* verilator public_flat_rd */;
    wire [12:0] kv_read_bytes /* verilator public_flat_rd */;
    wire kv_read_data_valid /* verilator public_flat_rd */;
    wire kv_read_data_ready /* verilator public_flat_rd */;
    wire [2047:0] kv_read_data /* verilator public_flat_rd */;
    wire kv_read_last /* verilator public_flat_rd */;
    wire kv_read_data_error /* verilator public_flat_rd */;
    wire kv_read_error /* verilator public_flat_rd */;
    wire kv_read_abort /* verilator public_flat_rd */;
    wire kv_read_quiescent /* verilator public_flat_rd */;
    qwen_verified_machine #(.MODEL_PREFETCH_PAGES(MODEL_PREFETCH_PAGES),
        .KV_CACHE_GROUPS(KV_CACHE_GROUPS),.KV_AUTH_SLOTS(KV_AUTH_SLOTS),.KV_PREFETCH_GROUPS(KV_PREFETCH_GROUPS),
        .SILU_ROM_FILE(SILU_ROM_FILE),.EXP_ROM_FILE(EXP_ROM_FILE),.ROOT_FILE(ROOT_FILE)) verified(.clk(core_clk),.rst_n(core_reset_n),.cmd_clear_valid(cmd_clear_valid),.*);
    qwen_model_hbm_cdc_reader model_transport(
        .core_clk(core_clk),.memory_clk(memory_clk),.rst_n(rst_n),.core_abort(raw_model_abort),.quiescent(raw_model_quiescent),.error(raw_model_error),
        .request_valid(raw_model_request_valid),.request_ready(raw_model_request_ready),.request_page(raw_model_page),
        .data_valid(raw_model_data_valid),.data_ready(raw_model_data_ready),.data(raw_model_data),.data_last(raw_model_last),
        .axi_araddr(model_axi_araddr),
        .axi_arid(model_axi_arid),
        .axi_arlen(model_axi_arlen),
        .axi_arsize(model_axi_arsize),
        .axi_arburst(model_axi_arburst),
        .axi_arvalid(model_axi_arvalid),
        .axi_arready(model_axi_arready),
        .axi_rdata(model_axi_rdata),
        .axi_rid(model_axi_rid),
        .axi_rresp(model_axi_rresp),
        .axi_rlast(model_axi_rlast),
        .axi_rvalid(model_axi_rvalid),
        .axi_rready(model_axi_rready));
    qwen_kv_hbm_cdc_transport kv_transport(.core_clk(core_clk),.memory_clk(memory_clk),.rst_n(rst_n),
        .update_request_valid(kv_update_request_valid),
        .update_request_ready(kv_update_request_ready),
        .update_request_write(kv_update_request_write),
        .update_address(kv_update_address),
        .update_bytes(kv_update_bytes),
        .update_read_valid(kv_update_read_valid),
        .update_read_ready(kv_update_read_ready),
        .update_read_data(kv_update_read_data),
        .update_read_last(kv_update_read_last),
        .update_read_error(kv_update_read_error),
        .update_write_valid(kv_update_write_valid),
        .update_write_ready(kv_update_write_ready),
        .update_write_data(kv_update_write_data),
        .update_write_last(kv_update_write_last),
        .update_done_valid(kv_update_done_valid),
        .update_done_ready(kv_update_done_ready),
        .update_done_error(kv_update_done_error),
        .update_error(kv_update_error),
        .update_abort(kv_update_abort),
        .update_quiescent(kv_update_quiescent),
        .read_request_valid(kv_read_request_valid),
        .read_request_ready(kv_read_request_ready),
        .read_address(kv_read_address),
        .read_bytes(kv_read_bytes),
        .read_data_valid(kv_read_data_valid),
        .read_data_ready(kv_read_data_ready),
        .read_data(kv_read_data),
        .read_last(kv_read_last),
        .read_data_error(kv_read_data_error),
        .read_error(kv_read_error),
        .read_abort(kv_read_abort),
        .read_quiescent(kv_read_quiescent),
        .axi_araddr(kv_axi_araddr),
        .axi_arid(kv_axi_arid),
        .axi_arlen(kv_axi_arlen),
        .axi_arsize(kv_axi_arsize),
        .axi_arburst(kv_axi_arburst),
        .axi_arvalid(kv_axi_arvalid),
        .axi_arready(kv_axi_arready),
        .axi_rdata(kv_axi_rdata),
        .axi_rid(kv_axi_rid),
        .axi_rresp(kv_axi_rresp),
        .axi_rlast(kv_axi_rlast),
        .axi_rvalid(kv_axi_rvalid),
        .axi_rready(kv_axi_rready),
        .axi_awaddr(kv_axi_awaddr),
        .axi_awid(kv_axi_awid),
        .axi_awlen(kv_axi_awlen),
        .axi_awsize(kv_axi_awsize),
        .axi_awburst(kv_axi_awburst),
        .axi_awvalid(kv_axi_awvalid),
        .axi_awready(kv_axi_awready),
        .axi_wdata(kv_axi_wdata),
        .axi_wstrb(kv_axi_wstrb),
        .axi_wlast(kv_axi_wlast),
        .axi_wvalid(kv_axi_wvalid),
        .axi_wready(kv_axi_wready),
        .axi_bid(kv_axi_bid),
        .axi_bresp(kv_axi_bresp),
        .axi_bvalid(kv_axi_bvalid),
        .axi_bready(kv_axi_bready));
endmodule
