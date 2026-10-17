// Host-connected protected numerical machine. OCL exposes APPEND/STEP/CLEAR;
// PCIS accepts only the fixed startup image through the bounded receiver.
// There is no external model_ready, expected digest, raw-memory or tensor port
// on the HOST surface. All model/K/V AXI ports below are private HBM wiring.
// Boot IMAGE_* parameters are build-time test overrides, not host registers.
// Production builds must bind the selected image identity and fixed root table.
//
// Model writes use channels 0..7 and cease at seal. Runtime model reads retain
// fixed-root verification. K/V uses channels 8..23. The application CLEAR does
// not enter startup and cannot reopen/restart it. Coordinated fabric reset
// must also reset the HBM fabric. Vendor HBM, actual AWS shell termination,
// physical CDC constraints and timing are still separate qualification work.
module qwen_host_hbm_verified_machine #(
    parameter [31:0] BOOT_IMAGE_BYTES=32'd2354380800,
    parameter [255:0] BOOT_IMAGE_SHA256=256'h90d82ed9b90c58607f924190be0c15f18b70d849c536a2ccbddd259858979cd1,
    parameter integer MODEL_PREFETCH_PAGES=8,
    parameter integer KV_CACHE_GROUPS=128,
    parameter integer KV_AUTH_SLOTS=128,
    parameter integer KV_PREFETCH_GROUPS=128,
    parameter SILU_ROM_FILE="silu-bf16.hex",
    parameter EXP_ROM_FILE="softmax-exp2.hex",
    parameter ROOT_FILE="model-page-roots.hex"
) (
    input wire shell_clk,input wire core_clk,input wire memory_clk,input wire rst_n,
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
    input wire [16*6-1:0] kv_axi_bid,input wire [16*2-1:0] kv_axi_bresp,input wire [15:0] kv_axi_bvalid,output wire [15:0] kv_axi_bready,
    output wire [8*34-1:0] model_axi_awaddr,output wire [8*6-1:0] model_axi_awid,
    output wire [8*4-1:0] model_axi_awlen,output wire [8*3-1:0] model_axi_awsize,
    output wire [8*2-1:0] model_axi_awburst,output wire [7:0] model_axi_awvalid,input wire [7:0] model_axi_awready,
    output wire [2047:0] model_axi_wdata,output wire [255:0] model_axi_wstrb,
    output wire [7:0] model_axi_wlast,output wire [7:0] model_axi_wvalid,input wire [7:0] model_axi_wready,
    input wire [8*6-1:0] model_axi_bid,input wire [8*2-1:0] model_axi_bresp,input wire [7:0] model_axi_bvalid,output wire [7:0] model_axi_bready
);
    wire model_ready /* verilator public_flat_rd */;
    wire model_loading /* verilator public_flat_rd */;
    wire model_error /* verilator public_flat_rd */;
    wire ingress_error /* verilator public_flat_rd */;
    wire [15:0] ingress_credit_blocks;
    wire [31:0] ingress_received_bytes /* verilator public_flat_rd */;
    wire [31:0] accepted_bytes /* verilator public_flat_rd */;
    qwen_pcis_model_hbm_boot #(.IMAGE_BYTES(BOOT_IMAGE_BYTES),.IMAGE_SHA256(BOOT_IMAGE_SHA256)) startup(
        .loading(model_loading),.error(model_error),
        .axi_awaddr(model_axi_awaddr),.axi_awid(model_axi_awid),.axi_awlen(model_axi_awlen),
        .axi_awsize(model_axi_awsize),.axi_awburst(model_axi_awburst),.axi_awvalid(model_axi_awvalid),.axi_awready(model_axi_awready),
        .axi_wdata(model_axi_wdata),.axi_wstrb(model_axi_wstrb),.axi_wlast(model_axi_wlast),.axi_wvalid(model_axi_wvalid),.axi_wready(model_axi_wready),
        .axi_bid(model_axi_bid),.axi_bresp(model_axi_bresp),.axi_bvalid(model_axi_bvalid),.axi_bready(model_axi_bready),.*);
    qwen_ocl_hbm_verified_machine #(
        .MODEL_PREFETCH_PAGES(MODEL_PREFETCH_PAGES),.KV_CACHE_GROUPS(KV_CACHE_GROUPS),
        .KV_AUTH_SLOTS(KV_AUTH_SLOTS),.KV_PREFETCH_GROUPS(KV_PREFETCH_GROUPS),
        .SILU_ROM_FILE(SILU_ROM_FILE),.EXP_ROM_FILE(EXP_ROM_FILE),.ROOT_FILE(ROOT_FILE)) application(.*);
endmodule
