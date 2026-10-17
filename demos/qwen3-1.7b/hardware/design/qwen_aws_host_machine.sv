// AWS-facing guarded host machine. Clocks/HBM status and 24 private memory
// channels remain internal to the final shell top, not host-controlled ports.
// PCIS retains all 16 ID bits; OCL exposes only the fixed token ABI. SDA always
// returns zero/DECERR. Application CLEAR never resets guards, boot or HBM.
// rst_n/FLR are shell management signals. All private memory endpoints MUST
// reset with machine_reset_n/HBM resets; vendor integration remains unqualified.
// Compile-time boot overrides are for reduced-image control tests only.
module qwen_aws_host_machine #(
    parameter [31:0] BOOT_IMAGE_BYTES=32'd2354380800,
    parameter [255:0] BOOT_IMAGE_SHA256=256'h90d82ed9b90c58607f924190be0c15f18b70d849c536a2ccbddd259858979cd1,
    parameter integer MODEL_PREFETCH_PAGES=8,
    parameter integer KV_CACHE_GROUPS=128,
    parameter integer KV_AUTH_SLOTS=128,
    parameter integer KV_PREFETCH_GROUPS=128,
    parameter SILU_ROM_FILE="silu-bf16.hex",
    parameter EXP_ROM_FILE="softmax-exp2.hex",
    parameter integer STARTUP_TIMEOUT_CYCLES=250000000,
    parameter integer FLR_HOLD_CYCLES=64,
    parameter ROOT_FILE="model-page-roots.hex"
) (
    input wire shell_clk,input wire core_clk,input wire memory_clk,input wire rst_n,
    input wire flr_assert,output wire flr_done,
    input wire clock_ready,input wire clock_failed,
    input wire generated_core_reset_n,input wire generated_memory_reset_n,
    input wire generated_reference_reset_n,input wire hbm_ready,
    input wire [1:0] hbm_monitor_reset_n,
    output wire host_reset_n,output wire machine_reset_n,output wire online,
    output wire hbm_shell_reset_n,output wire hbm_memory_reset_n,
    output wire lifecycle_failed,output wire [3:0] lifecycle_error_code,
    output wire pcis_guard_error,
    input wire [1:0] pcis_awburst,input wire pcis_awlock,
    input wire [63:0] pcis_awaddr,input wire [15:0] pcis_awid,
    input wire [7:0] pcis_awlen,input wire [2:0] pcis_awsize,
    input wire pcis_awvalid,output wire pcis_awready,
    input wire [511:0] pcis_wdata,input wire [63:0] pcis_wstrb,
    input wire pcis_wlast,input wire pcis_wvalid,output wire pcis_wready,
    output wire [15:0] pcis_bid,output wire [1:0] pcis_bresp,
    output wire pcis_bvalid,input wire pcis_bready,
    input wire [63:0] pcis_araddr,input wire [15:0] pcis_arid,
    input wire [7:0] pcis_arlen,input wire [2:0] pcis_arsize,
    input wire pcis_arvalid,output wire pcis_arready,
    output wire [511:0] pcis_rdata,output wire [15:0] pcis_rid,
    output wire [1:0] pcis_rresp,output wire pcis_rlast,
    output wire pcis_rvalid,input wire pcis_rready,
    input wire [31:0] ocl_awaddr,input wire ocl_awvalid,output wire ocl_awready,
    input wire [31:0] ocl_wdata,input wire [3:0] ocl_wstrb,input wire ocl_wvalid,output wire ocl_wready,
    output wire [1:0] ocl_bresp,output wire ocl_bvalid,input wire ocl_bready,
    input wire [31:0] ocl_araddr,input wire ocl_arvalid,output wire ocl_arready,
    output wire [31:0] ocl_rdata,output wire [1:0] ocl_rresp,output wire ocl_rvalid,input wire ocl_rready,
    input wire [31:0] sda_awaddr,
    input wire  sda_awvalid,
    output wire  sda_awready,
    input wire [31:0] sda_wdata,
    input wire [3:0] sda_wstrb,
    input wire  sda_wvalid,
    output wire  sda_wready,
    output wire [1:0] sda_bresp,
    output wire  sda_bvalid,
    input wire  sda_bready,
    input wire [31:0] sda_araddr,
    input wire  sda_arvalid,
    output wire  sda_arready,
    output wire [31:0] sda_rdata,
    output wire [1:0] sda_rresp,
    output wire  sda_rvalid,
    input wire  sda_rready,
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
    wire pcis_guard_fault;
    wire host_guard_ready;
    qwen_aws_lifecycle #(.STARTUP_TIMEOUT_CYCLES(STARTUP_TIMEOUT_CYCLES),.FLR_HOLD_CYCLES(FLR_HOLD_CYCLES)) lifecycle(
        .interface_fault(pcis_guard_fault),.failed(lifecycle_failed),.error_code(lifecycle_error_code),.*);
    wire [63:0] mid_pcis_awaddr;
    wire [5:0] mid_pcis_awid;
    wire [7:0] mid_pcis_awlen;
    wire [2:0] mid_pcis_awsize;
    wire  mid_pcis_awvalid;
    wire  mid_pcis_awready;
    wire [511:0] mid_pcis_wdata;
    wire [63:0] mid_pcis_wstrb;
    wire  mid_pcis_wlast;
    wire  mid_pcis_wvalid;
    wire  mid_pcis_wready;
    wire [5:0] mid_pcis_bid;
    wire [1:0] mid_pcis_bresp;
    wire  mid_pcis_bvalid;
    wire  mid_pcis_bready;
    wire [63:0] mid_pcis_araddr;
    wire [5:0] mid_pcis_arid;
    wire [7:0] mid_pcis_arlen;
    wire [2:0] mid_pcis_arsize;
    wire  mid_pcis_arvalid;
    wire  mid_pcis_arready;
    wire [511:0] mid_pcis_rdata;
    wire [5:0] mid_pcis_rid;
    wire [1:0] mid_pcis_rresp;
    wire  mid_pcis_rlast;
    wire  mid_pcis_rvalid;
    wire  mid_pcis_rready;
    wire [63:0] app_pcis_awaddr;
    wire [5:0] app_pcis_awid;
    wire [7:0] app_pcis_awlen;
    wire [2:0] app_pcis_awsize;
    wire  app_pcis_awvalid;
    wire  app_pcis_awready;
    wire [511:0] app_pcis_wdata;
    wire [63:0] app_pcis_wstrb;
    wire  app_pcis_wlast;
    wire  app_pcis_wvalid;
    wire  app_pcis_wready;
    wire [5:0] app_pcis_bid;
    wire [1:0] app_pcis_bresp;
    wire  app_pcis_bvalid;
    wire  app_pcis_bready;
    wire [63:0] app_pcis_araddr;
    wire [5:0] app_pcis_arid;
    wire [7:0] app_pcis_arlen;
    wire [2:0] app_pcis_arsize;
    wire  app_pcis_arvalid;
    wire  app_pcis_arready;
    wire [511:0] app_pcis_rdata;
    wire [5:0] app_pcis_rid;
    wire [1:0] app_pcis_rresp;
    wire  app_pcis_rlast;
    wire  app_pcis_rvalid;
    wire  app_pcis_rready;
    wire [31:0] app_ocl_awaddr;
    wire  app_ocl_awvalid;
    wire  app_ocl_awready;
    wire [31:0] app_ocl_wdata;
    wire [3:0] app_ocl_wstrb;
    wire  app_ocl_wvalid;
    wire  app_ocl_wready;
    wire [1:0] app_ocl_bresp;
    wire  app_ocl_bvalid;
    wire  app_ocl_bready;
    wire [31:0] app_ocl_araddr;
    wire  app_ocl_arvalid;
    wire  app_ocl_arready;
    wire [31:0] app_ocl_rdata;
    wire [1:0] app_ocl_rresp;
    wire  app_ocl_rvalid;
    wire  app_ocl_rready;
    qwen_aws_pcis_adapter id_adapter(.clk(shell_clk),.rst_n(host_reset_n),
        .s_awburst(pcis_awburst),.s_awlock(pcis_awlock),
        .s_awaddr(pcis_awaddr),
        .s_awid(pcis_awid),
        .s_awlen(pcis_awlen),
        .s_awsize(pcis_awsize),
        .s_awvalid(pcis_awvalid),
        .s_awready(pcis_awready),
        .s_wdata(pcis_wdata),
        .s_wstrb(pcis_wstrb),
        .s_wlast(pcis_wlast),
        .s_wvalid(pcis_wvalid),
        .s_wready(pcis_wready),
        .s_bid(pcis_bid),
        .s_bresp(pcis_bresp),
        .s_bvalid(pcis_bvalid),
        .s_bready(pcis_bready),
        .s_araddr(pcis_araddr),
        .s_arid(pcis_arid),
        .s_arlen(pcis_arlen),
        .s_arsize(pcis_arsize),
        .s_arvalid(pcis_arvalid),
        .s_arready(pcis_arready),
        .s_rdata(pcis_rdata),
        .s_rid(pcis_rid),
        .s_rresp(pcis_rresp),
        .s_rlast(pcis_rlast),
        .s_rvalid(pcis_rvalid),
        .s_rready(pcis_rready),
        .m_awaddr(mid_pcis_awaddr),
        .m_awid(mid_pcis_awid),
        .m_awlen(mid_pcis_awlen),
        .m_awsize(mid_pcis_awsize),
        .m_awvalid(mid_pcis_awvalid),
        .m_awready(mid_pcis_awready),
        .m_wdata(mid_pcis_wdata),
        .m_wstrb(mid_pcis_wstrb),
        .m_wlast(mid_pcis_wlast),
        .m_wvalid(mid_pcis_wvalid),
        .m_wready(mid_pcis_wready),
        .m_bid(mid_pcis_bid),
        .m_bresp(mid_pcis_bresp),
        .m_bvalid(mid_pcis_bvalid),
        .m_bready(mid_pcis_bready),
        .m_araddr(mid_pcis_araddr),
        .m_arid(mid_pcis_arid),
        .m_arlen(mid_pcis_arlen),
        .m_arsize(mid_pcis_arsize),
        .m_arvalid(mid_pcis_arvalid),
        .m_arready(mid_pcis_arready),
        .m_rdata(mid_pcis_rdata),
        .m_rid(mid_pcis_rid),
        .m_rresp(mid_pcis_rresp),
        .m_rlast(mid_pcis_rlast),
        .m_rvalid(mid_pcis_rvalid),
        .m_rready(mid_pcis_rready));
    qwen_aws_pcis_gate provisioning_guard(.clk(shell_clk),.rst_n(host_reset_n),.online(host_guard_ready),
        .error(pcis_guard_error),.fault_request(pcis_guard_fault),
        .s_awaddr(mid_pcis_awaddr),
        .s_awid(mid_pcis_awid),
        .s_awlen(mid_pcis_awlen),
        .s_awsize(mid_pcis_awsize),
        .s_awvalid(mid_pcis_awvalid),
        .s_awready(mid_pcis_awready),
        .s_wdata(mid_pcis_wdata),
        .s_wstrb(mid_pcis_wstrb),
        .s_wlast(mid_pcis_wlast),
        .s_wvalid(mid_pcis_wvalid),
        .s_wready(mid_pcis_wready),
        .s_bid(mid_pcis_bid),
        .s_bresp(mid_pcis_bresp),
        .s_bvalid(mid_pcis_bvalid),
        .s_bready(mid_pcis_bready),
        .s_araddr(mid_pcis_araddr),
        .s_arid(mid_pcis_arid),
        .s_arlen(mid_pcis_arlen),
        .s_arsize(mid_pcis_arsize),
        .s_arvalid(mid_pcis_arvalid),
        .s_arready(mid_pcis_arready),
        .s_rdata(mid_pcis_rdata),
        .s_rid(mid_pcis_rid),
        .s_rresp(mid_pcis_rresp),
        .s_rlast(mid_pcis_rlast),
        .s_rvalid(mid_pcis_rvalid),
        .s_rready(mid_pcis_rready),
        .m_awaddr(app_pcis_awaddr),
        .m_awid(app_pcis_awid),
        .m_awlen(app_pcis_awlen),
        .m_awsize(app_pcis_awsize),
        .m_awvalid(app_pcis_awvalid),
        .m_awready(app_pcis_awready),
        .m_wdata(app_pcis_wdata),
        .m_wstrb(app_pcis_wstrb),
        .m_wlast(app_pcis_wlast),
        .m_wvalid(app_pcis_wvalid),
        .m_wready(app_pcis_wready),
        .m_bid(app_pcis_bid),
        .m_bresp(app_pcis_bresp),
        .m_bvalid(app_pcis_bvalid),
        .m_bready(app_pcis_bready),
        .m_araddr(app_pcis_araddr),
        .m_arid(app_pcis_arid),
        .m_arlen(app_pcis_arlen),
        .m_arsize(app_pcis_arsize),
        .m_arvalid(app_pcis_arvalid),
        .m_arready(app_pcis_arready),
        .m_rdata(app_pcis_rdata),
        .m_rid(app_pcis_rid),
        .m_rresp(app_pcis_rresp),
        .m_rlast(app_pcis_rlast),
        .m_rvalid(app_pcis_rvalid),
        .m_rready(app_pcis_rready));
    qwen_aws_axil_gate #(.OFFLINE_RESPONSE(2'b10)) control_guard(
        .clk(shell_clk),.rst_n(host_reset_n),.online(host_guard_ready),
        .s_awaddr(ocl_awaddr),
        .s_awvalid(ocl_awvalid),
        .s_awready(ocl_awready),
        .s_wdata(ocl_wdata),
        .s_wstrb(ocl_wstrb),
        .s_wvalid(ocl_wvalid),
        .s_wready(ocl_wready),
        .s_bresp(ocl_bresp),
        .s_bvalid(ocl_bvalid),
        .s_bready(ocl_bready),
        .s_araddr(ocl_araddr),
        .s_arvalid(ocl_arvalid),
        .s_arready(ocl_arready),
        .s_rdata(ocl_rdata),
        .s_rresp(ocl_rresp),
        .s_rvalid(ocl_rvalid),
        .s_rready(ocl_rready),
        .m_awaddr(app_ocl_awaddr),
        .m_awvalid(app_ocl_awvalid),
        .m_awready(app_ocl_awready),
        .m_wdata(app_ocl_wdata),
        .m_wstrb(app_ocl_wstrb),
        .m_wvalid(app_ocl_wvalid),
        .m_wready(app_ocl_wready),
        .m_bresp(app_ocl_bresp),
        .m_bvalid(app_ocl_bvalid),
        .m_bready(app_ocl_bready),
        .m_araddr(app_ocl_araddr),
        .m_arvalid(app_ocl_arvalid),
        .m_arready(app_ocl_arready),
        .m_rdata(app_ocl_rdata),
        .m_rresp(app_ocl_rresp),
        .m_rvalid(app_ocl_rvalid),
        .m_rready(app_ocl_rready));
    qwen_aws_axil_gate #(.OFFLINE_RESPONSE(2'b11)) closed_sda(
        .clk(shell_clk),.rst_n(host_reset_n),.online(1'b0),
        .s_awaddr(sda_awaddr),
        .s_awvalid(sda_awvalid),
        .s_awready(sda_awready),
        .s_wdata(sda_wdata),
        .s_wstrb(sda_wstrb),
        .s_wvalid(sda_wvalid),
        .s_wready(sda_wready),
        .s_bresp(sda_bresp),
        .s_bvalid(sda_bvalid),
        .s_bready(sda_bready),
        .s_araddr(sda_araddr),
        .s_arvalid(sda_arvalid),
        .s_arready(sda_arready),
        .s_rdata(sda_rdata),
        .s_rresp(sda_rresp),
        .s_rvalid(sda_rvalid),
        .s_rready(sda_rready),
        .m_awaddr(),
        .m_awvalid(),
        .m_awready(1'b0),
        .m_wdata(),
        .m_wstrb(),
        .m_wvalid(),
        .m_wready(1'b0),
        .m_bresp(2'b0),
        .m_bvalid(1'b0),
        .m_bready(),
        .m_araddr(),
        .m_arvalid(),
        .m_arready(1'b0),
        .m_rdata(32'b0),
        .m_rresp(2'b0),
        .m_rvalid(1'b0),
        .m_rready());
    qwen_host_hbm_verified_machine #(
        .BOOT_IMAGE_BYTES(BOOT_IMAGE_BYTES),.BOOT_IMAGE_SHA256(BOOT_IMAGE_SHA256),
        .MODEL_PREFETCH_PAGES(MODEL_PREFETCH_PAGES),.KV_CACHE_GROUPS(KV_CACHE_GROUPS),
        .KV_AUTH_SLOTS(KV_AUTH_SLOTS),.KV_PREFETCH_GROUPS(KV_PREFETCH_GROUPS),
        .SILU_ROM_FILE(SILU_ROM_FILE),.EXP_ROM_FILE(EXP_ROM_FILE),.ROOT_FILE(ROOT_FILE)) machine(
        .shell_clk(shell_clk),
        .core_clk(core_clk),
        .memory_clk(memory_clk),
        .rst_n(machine_reset_n),
        .pcis_awaddr(app_pcis_awaddr),
        .pcis_awid(app_pcis_awid),
        .pcis_awlen(app_pcis_awlen),
        .pcis_awsize(app_pcis_awsize),
        .pcis_awvalid(app_pcis_awvalid),
        .pcis_awready(app_pcis_awready),
        .pcis_wdata(app_pcis_wdata),
        .pcis_wstrb(app_pcis_wstrb),
        .pcis_wlast(app_pcis_wlast),
        .pcis_wvalid(app_pcis_wvalid),
        .pcis_wready(app_pcis_wready),
        .pcis_bid(app_pcis_bid),
        .pcis_bresp(app_pcis_bresp),
        .pcis_bvalid(app_pcis_bvalid),
        .pcis_bready(app_pcis_bready),
        .pcis_araddr(app_pcis_araddr),
        .pcis_arid(app_pcis_arid),
        .pcis_arlen(app_pcis_arlen),
        .pcis_arsize(app_pcis_arsize),
        .pcis_arvalid(app_pcis_arvalid),
        .pcis_arready(app_pcis_arready),
        .pcis_rdata(app_pcis_rdata),
        .pcis_rid(app_pcis_rid),
        .pcis_rresp(app_pcis_rresp),
        .pcis_rlast(app_pcis_rlast),
        .pcis_rvalid(app_pcis_rvalid),
        .pcis_rready(app_pcis_rready),
        .ocl_awaddr(app_ocl_awaddr),
        .ocl_awvalid(app_ocl_awvalid),
        .ocl_awready(app_ocl_awready),
        .ocl_wdata(app_ocl_wdata),
        .ocl_wstrb(app_ocl_wstrb),
        .ocl_wvalid(app_ocl_wvalid),
        .ocl_wready(app_ocl_wready),
        .ocl_bresp(app_ocl_bresp),
        .ocl_bvalid(app_ocl_bvalid),
        .ocl_bready(app_ocl_bready),
        .ocl_araddr(app_ocl_araddr),
        .ocl_arvalid(app_ocl_arvalid),
        .ocl_arready(app_ocl_arready),
        .ocl_rdata(app_ocl_rdata),
        .ocl_rresp(app_ocl_rresp),
        .ocl_rvalid(app_ocl_rvalid),
        .ocl_rready(app_ocl_rready),
        .model_axi_araddr(model_axi_araddr),
        .model_axi_arid(model_axi_arid),
        .model_axi_arlen(model_axi_arlen),
        .model_axi_arsize(model_axi_arsize),
        .model_axi_arburst(model_axi_arburst),
        .model_axi_arvalid(model_axi_arvalid),
        .model_axi_arready(model_axi_arready),
        .model_axi_rdata(model_axi_rdata),
        .model_axi_rid(model_axi_rid),
        .model_axi_rresp(model_axi_rresp),
        .model_axi_rlast(model_axi_rlast),
        .model_axi_rvalid(model_axi_rvalid),
        .model_axi_rready(model_axi_rready),
        .kv_axi_araddr(kv_axi_araddr),
        .kv_axi_arid(kv_axi_arid),
        .kv_axi_arlen(kv_axi_arlen),
        .kv_axi_arsize(kv_axi_arsize),
        .kv_axi_arburst(kv_axi_arburst),
        .kv_axi_arvalid(kv_axi_arvalid),
        .kv_axi_arready(kv_axi_arready),
        .kv_axi_rdata(kv_axi_rdata),
        .kv_axi_rid(kv_axi_rid),
        .kv_axi_rresp(kv_axi_rresp),
        .kv_axi_rlast(kv_axi_rlast),
        .kv_axi_rvalid(kv_axi_rvalid),
        .kv_axi_rready(kv_axi_rready),
        .kv_axi_awaddr(kv_axi_awaddr),
        .kv_axi_awid(kv_axi_awid),
        .kv_axi_awlen(kv_axi_awlen),
        .kv_axi_awsize(kv_axi_awsize),
        .kv_axi_awburst(kv_axi_awburst),
        .kv_axi_awvalid(kv_axi_awvalid),
        .kv_axi_awready(kv_axi_awready),
        .kv_axi_wdata(kv_axi_wdata),
        .kv_axi_wstrb(kv_axi_wstrb),
        .kv_axi_wlast(kv_axi_wlast),
        .kv_axi_wvalid(kv_axi_wvalid),
        .kv_axi_wready(kv_axi_wready),
        .kv_axi_bid(kv_axi_bid),
        .kv_axi_bresp(kv_axi_bresp),
        .kv_axi_bvalid(kv_axi_bvalid),
        .kv_axi_bready(kv_axi_bready),
        .model_axi_awaddr(model_axi_awaddr),
        .model_axi_awid(model_axi_awid),
        .model_axi_awlen(model_axi_awlen),
        .model_axi_awsize(model_axi_awsize),
        .model_axi_awburst(model_axi_awburst),
        .model_axi_awvalid(model_axi_awvalid),
        .model_axi_awready(model_axi_awready),
        .model_axi_wdata(model_axi_wdata),
        .model_axi_wstrb(model_axi_wstrb),
        .model_axi_wlast(model_axi_wlast),
        .model_axi_wvalid(model_axi_wvalid),
        .model_axi_wready(model_axi_wready),
        .model_axi_bid(model_axi_bid),
        .model_axi_bresp(model_axi_bresp),
        .model_axi_bvalid(model_axi_bvalid),
        .model_axi_bready(model_axi_bready));
endmodule
