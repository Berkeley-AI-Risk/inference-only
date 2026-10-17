// OCL-controlled full protected numerical machine with three clock domains.
// OCL is the token application boundary. All model/HBM/status ports are PRIVATE
// integration ports, not additional host services. In the final shell,
// model_ready must come only from the fixed-image loader. This wrapper does
// not yet connect provisioning, vendor HBM, unused shell ports or constraints.
module qwen_ocl_hbm_verified_machine #(
    parameter integer MODEL_PREFETCH_PAGES=8,
    parameter integer KV_CACHE_GROUPS=128,
    parameter integer KV_AUTH_SLOTS=128,
    parameter integer KV_PREFETCH_GROUPS=128,
    parameter SILU_ROM_FILE="silu-bf16.hex",
    parameter EXP_ROM_FILE="softmax-exp2.hex",
    parameter ROOT_FILE="model-page-roots.hex"
) (
    input wire shell_clk,input wire core_clk,input wire memory_clk,input wire rst_n,
    input wire model_ready,input wire model_loading,input wire model_error,
    input wire ingress_error,input wire [15:0] ingress_credit_blocks,input wire [31:0] ingress_received_bytes,
    input wire [31:0] ocl_awaddr,input wire ocl_awvalid,output wire ocl_awready,
    input wire [31:0] ocl_wdata,input wire [3:0] ocl_wstrb,input wire ocl_wvalid,output wire ocl_wready,
    output wire [1:0] ocl_bresp,output wire ocl_bvalid,input wire ocl_bready,
    input wire [31:0] ocl_araddr,input wire ocl_arvalid,output wire ocl_arready,
    output wire [31:0] ocl_rdata,output wire [1:0] ocl_rresp,output wire ocl_rvalid,input wire ocl_rready,
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
    wire cmd_valid,cmd_clear_valid,cmd_ready,response_valid,response_ready;
    wire [7:0] cmd_opcode;
    wire [31:0] cmd_token,response_token;
    wire [3:0] response_status;
    wire busy /* verilator public_flat_rd */;
    qwen_ocl_control host_control(
        .core_model_ready(model_ready),.core_model_loading(model_loading),.core_model_error(model_error),
        .core_cmd_valid(cmd_valid),.core_cmd_clear_valid(cmd_clear_valid),.core_cmd_ready(cmd_ready),.core_cmd_opcode(cmd_opcode),.core_cmd_token(cmd_token),
        .core_response_valid(response_valid),.core_response_ready(response_ready),
        .core_response_status(response_status),.core_response_token(response_token),.*);
    qwen_hbm_cdc_verified_machine #(
        .MODEL_PREFETCH_PAGES(MODEL_PREFETCH_PAGES),.KV_CACHE_GROUPS(KV_CACHE_GROUPS),
        .KV_AUTH_SLOTS(KV_AUTH_SLOTS),.KV_PREFETCH_GROUPS(KV_PREFETCH_GROUPS),
        .SILU_ROM_FILE(SILU_ROM_FILE),.EXP_ROM_FILE(EXP_ROM_FILE),.ROOT_FILE(ROOT_FILE)) inference(.cmd_clear_valid(cmd_clear_valid),.*);
endmodule
