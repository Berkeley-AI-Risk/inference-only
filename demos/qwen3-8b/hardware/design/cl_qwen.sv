// Fixed-Qwen AWS F2 custom-logic top, pinned to HDK v2.3.4 interfaces.
// Candidate integration: vendor simulation, CDC constraints, routing and timing
// are NOT qualified. No boot-size/digest override is exposed by this top.
// Raw shell buses do not connect to HBM, clock CSRs, tensor memory or debug.
// Only the restricted PCIS loader and token OCL endpoint receive host traffic.
// The pinned AWS header declares input logic ports without an explicit net
// kind. Vivado requires the normal wire default while reading that header;
// restore strict declarations immediately afterward for our implementation.
`default_nettype wire
module cl_qwen (
`include "cl_ports.vh"
);
`default_nettype none
    wire core_clk,memory_clk;
    wire host_reset_n,machine_reset_n,online,hbm_shell_reset_n,hbm_memory_reset_n;
    wire generated_core_reset_n,generated_memory_reset_n,generated_reference_reset_n;
    wire clock_ready,clock_failed,hbm_ready,lifecycle_failed,pcis_guard_error;
    wire raw_hbm_ready,clock_control_reset_n;
    wire vendor_hbm_controller_reset_n,vendor_hbm_axi_reset_n;
    wire lifecycle_flr_done,hbm_flr_done;
    wire [3:0] clock_error_code,lifecycle_error_code;
    qwen_aws_hbm_reset fixed_hbm_reset(
        .shell_clk(clk_main_a0),.reference_clk(clk_hbm_ref),.memory_clk(memory_clk),
        .rst_n(rst_main_n),.release_request(hbm_shell_reset_n),
        .flr_assert(sh_cl_flr_assert),.raw_hbm_ready(raw_hbm_ready),
        .clock_control_reset_n(clock_control_reset_n),
        .hbm_controller_reset_n(vendor_hbm_controller_reset_n),
        .hbm_axi_reset_n(vendor_hbm_axi_reset_n),
        .qualified_hbm_ready(hbm_ready),.flr_reset_done(hbm_flr_done));
    assign cl_sh_flr_done=lifecycle_flr_done && hbm_flr_done;
    // Development PCI identifiers follow the permitted upstream example values.
    // Any AFI registration manifest must agree with these fixed values.
    assign cl_sh_id0=32'hf0041d0f;
    assign cl_sh_id1=32'h1d51fedc;
    assign cl_sh_status0=32'b0;
    assign cl_sh_status1=32'b0;
    assign cl_sh_status2=32'b0;
    // Read-only management display is one shell cycle behind internal status.
    // Do not use this register for online, reset, fault or authentication gates.
    // A synchronous clear keeps this nonfunctional display off during shell reset.
    reg [15:0] management_status;
    always @(posedge clk_main_a0) begin
        if(!rst_main_n) management_status<=16'b0;
        else management_status<={lifecycle_error_code,clock_error_code,2'b0,
            clock_failed,pcis_guard_error,hbm_ready,clock_ready,lifecycle_failed,online};
    end
    assign cl_sh_status_vled=management_status;
    assign cl_sh_dma_wr_full='0;
    assign cl_sh_dma_rd_full='0;
    assign cl_sh_pcim_awid='0;
    assign cl_sh_pcim_awaddr='0;
    assign cl_sh_pcim_awlen='0;
    assign cl_sh_pcim_awsize='0;
    assign cl_sh_pcim_awburst='0;
    assign cl_sh_pcim_awcache='0;
    assign cl_sh_pcim_awlock='0;
    assign cl_sh_pcim_awprot='0;
    assign cl_sh_pcim_awqos='0;
    assign cl_sh_pcim_awuser='0;
    assign cl_sh_pcim_awvalid='0;
    assign cl_sh_pcim_wid='0;
    assign cl_sh_pcim_wdata='0;
    assign cl_sh_pcim_wstrb='0;
    assign cl_sh_pcim_wlast='0;
    assign cl_sh_pcim_wuser='0;
    assign cl_sh_pcim_wvalid='0;
    assign cl_sh_pcim_bready='0;
    assign cl_sh_pcim_arid='0;
    assign cl_sh_pcim_araddr='0;
    assign cl_sh_pcim_arlen='0;
    assign cl_sh_pcim_arsize='0;
    assign cl_sh_pcim_arburst='0;
    assign cl_sh_pcim_arcache='0;
    assign cl_sh_pcim_arlock='0;
    assign cl_sh_pcim_arprot='0;
    assign cl_sh_pcim_arqos='0;
    assign cl_sh_pcim_aruser='0;
    assign cl_sh_pcim_arvalid='0;
    assign cl_sh_pcim_rready='0;
    assign cl_sh_apppf_irq_req='0;
    assign cl_sh_dma_pcis_ruser='0;
    assign tdo='0;
    assign PCIE_EP_TXP='0;
    assign PCIE_EP_TXN='0;
    assign PCIE_RP_PERSTN='0;
    assign PCIE_RP_TXP='0;
    assign PCIE_RP_TXN='0;

    // Disabled DDR still supplies the mandatory physical pin termination.
    wire rst_main_n_sync=host_reset_n;
`include "unused_ddr_template.inc"

    wire [31:0] clock_awaddr;
    wire  clock_awvalid;
    wire  clock_awready;
    wire [31:0] clock_wdata;
    wire [3:0] clock_wstrb;
    wire  clock_wvalid;
    wire  clock_wready;
    wire [1:0] clock_bresp;
    wire  clock_bvalid;
    wire  clock_bready;
    wire [31:0] clock_araddr;
    wire  clock_arvalid;
    wire  clock_arready;
    wire [31:0] clock_rdata;
    wire [1:0] clock_rresp;
    wire  clock_rvalid;
    wire  clock_rready;
    // Ordinary FLR must not stop/reset the clock generator while the HBM
    // wrapper is still propagating full-controller and AXI resets.
    qwen_aws_clock_startup fixed_clock_control(.clk(clk_main_a0),.rst_n(clock_control_reset_n),
        .ready(clock_ready),.failed(clock_failed),.error_code(clock_error_code),
        .m_awaddr(clock_awaddr),
        .m_awvalid(clock_awvalid),
        .m_awready(clock_awready),
        .m_wdata(clock_wdata),
        .m_wstrb(clock_wstrb),
        .m_wvalid(clock_wvalid),
        .m_wready(clock_wready),
        .m_bresp(clock_bresp),
        .m_bvalid(clock_bvalid),
        .m_bready(clock_bready),
        .m_araddr(clock_araddr),
        .m_arvalid(clock_arvalid),
        .m_arready(clock_arready),
        .m_rdata(clock_rdata),
        .m_rresp(clock_rresp),
        .m_rvalid(clock_rvalid),
        .m_rready(clock_rready));
    // The instance name is part of the pinned vendor build-script contract.
    aws_clk_gen #(.CLK_GRP_A_EN(0),.CLK_GRP_B_EN(0),.CLK_GRP_C_EN(1),.CLK_HBM_EN(1)) AWS_CLK_GEN(
        .i_clk_main_a0(clk_main_a0),.i_clk_hbm_ref(clk_hbm_ref),.i_rst_main_n(clock_control_reset_n),
        .s_axil_ctrl_awaddr(clock_awaddr),
        .s_axil_ctrl_awvalid(clock_awvalid),
        .s_axil_ctrl_awready(clock_awready),
        .s_axil_ctrl_wdata(clock_wdata),
        .s_axil_ctrl_wstrb(clock_wstrb),
        .s_axil_ctrl_wvalid(clock_wvalid),
        .s_axil_ctrl_wready(clock_wready),
        .s_axil_ctrl_bresp(clock_bresp),
        .s_axil_ctrl_bvalid(clock_bvalid),
        .s_axil_ctrl_bready(clock_bready),
        .s_axil_ctrl_araddr(clock_araddr),
        .s_axil_ctrl_arvalid(clock_arvalid),
        .s_axil_ctrl_arready(clock_arready),
        .s_axil_ctrl_rdata(clock_rdata),
        .s_axil_ctrl_rresp(clock_rresp),
        .s_axil_ctrl_rvalid(clock_rvalid),
        .s_axil_ctrl_rready(clock_rready),
        .o_clk_hbm_ref(),
        .o_clk_main_a0(),
        .o_clk_extra_a1(),
        .o_clk_extra_a2(),
        .o_clk_extra_a3(),
        .o_clk_extra_b0(),
        .o_clk_extra_b1(),
        .o_clk_extra_c0(),
        .o_clk_extra_c1(core_clk),
        .o_clk_hbm_axi(memory_clk),
        .o_cl_rst_hbm_axi_n(generated_memory_reset_n),
        .o_cl_rst_hbm_ref_n(generated_reference_reset_n),
        .o_cl_rst_c1_n(generated_core_reset_n),
        .o_cl_rst_c0_n(),
        .o_cl_rst_b1_n(),
        .o_cl_rst_b0_n(),
        .o_cl_rst_a3_n(),
        .o_cl_rst_a2_n(),
        .o_cl_rst_a1_n(),
        .o_cl_rst_main_n());

    wire [8*34-1:0] model_axi_araddr;
    wire [8*6-1:0] model_axi_arid;
    wire [8*4-1:0] model_axi_arlen;
    wire [8*3-1:0] model_axi_arsize;
    wire [8*2-1:0] model_axi_arburst;
    wire [7:0] model_axi_arvalid;
    wire [7:0] model_axi_arready;
    wire [8*256-1:0] model_axi_rdata;
    wire [8*6-1:0] model_axi_rid;
    wire [8*2-1:0] model_axi_rresp;
    wire [7:0] model_axi_rlast;
    wire [7:0] model_axi_rvalid;
    wire [7:0] model_axi_rready;
    wire [16*34-1:0] kv_axi_araddr;
    wire [16*6-1:0] kv_axi_arid;
    wire [16*4-1:0] kv_axi_arlen;
    wire [16*3-1:0] kv_axi_arsize;
    wire [16*2-1:0] kv_axi_arburst;
    wire [15:0] kv_axi_arvalid;
    wire [15:0] kv_axi_arready;
    wire [4095:0] kv_axi_rdata;
    wire [16*6-1:0] kv_axi_rid;
    wire [16*2-1:0] kv_axi_rresp;
    wire [15:0] kv_axi_rlast;
    wire [15:0] kv_axi_rvalid;
    wire [15:0] kv_axi_rready;
    wire [16*34-1:0] kv_axi_awaddr;
    wire [16*6-1:0] kv_axi_awid;
    wire [16*4-1:0] kv_axi_awlen;
    wire [16*3-1:0] kv_axi_awsize;
    wire [16*2-1:0] kv_axi_awburst;
    wire [15:0] kv_axi_awvalid;
    wire [15:0] kv_axi_awready;
    wire [4095:0] kv_axi_wdata;
    wire [511:0] kv_axi_wstrb;
    wire [15:0] kv_axi_wlast;
    wire [15:0] kv_axi_wvalid;
    wire [15:0] kv_axi_wready;
    wire [16*6-1:0] kv_axi_bid;
    wire [16*2-1:0] kv_axi_bresp;
    wire [15:0] kv_axi_bvalid;
    wire [15:0] kv_axi_bready;
    wire [8*34-1:0] model_axi_awaddr;
    wire [8*6-1:0] model_axi_awid;
    wire [8*4-1:0] model_axi_awlen;
    wire [8*3-1:0] model_axi_awsize;
    wire [8*2-1:0] model_axi_awburst;
    wire [7:0] model_axi_awvalid;
    wire [7:0] model_axi_awready;
    wire [2047:0] model_axi_wdata;
    wire [255:0] model_axi_wstrb;
    wire [7:0] model_axi_wlast;
    wire [7:0] model_axi_wvalid;
    wire [7:0] model_axi_wready;
    wire [8*6-1:0] model_axi_bid;
    wire [8*2-1:0] model_axi_bresp;
    wire [7:0] model_axi_bvalid;
    wire [7:0] model_axi_bready;
    qwen_aws_host_machine #(.MODEL_PREFETCH_PAGES(32)) fixed_machine(
        .shell_clk(clk_main_a0),
        .core_clk(core_clk),
        .memory_clk(memory_clk),
        .rst_n(rst_main_n),
        .flr_assert(sh_cl_flr_assert),
        .flr_done(lifecycle_flr_done),
        .clock_ready(clock_ready),
        .clock_failed(clock_failed),
        .generated_core_reset_n(generated_core_reset_n),
        .generated_memory_reset_n(generated_memory_reset_n),
        .generated_reference_reset_n(generated_reference_reset_n),
        .hbm_ready(hbm_ready),
        .hbm_monitor_reset_n({hbm_apb_preset_n_1,hbm_apb_preset_n_0}),
        .host_reset_n(host_reset_n),
        .machine_reset_n(machine_reset_n),
        .online(online),
        .hbm_shell_reset_n(hbm_shell_reset_n),
        .hbm_memory_reset_n(hbm_memory_reset_n),
        .lifecycle_failed(lifecycle_failed),
        .lifecycle_error_code(lifecycle_error_code),
        .pcis_guard_error(pcis_guard_error),
        .pcis_awburst(sh_cl_dma_pcis_awburst),
        .pcis_awlock(sh_cl_dma_pcis_awlock),
        .pcis_awaddr(sh_cl_dma_pcis_awaddr),
        .pcis_awid(sh_cl_dma_pcis_awid),
        .pcis_awlen(sh_cl_dma_pcis_awlen),
        .pcis_awsize(sh_cl_dma_pcis_awsize),
        .pcis_awvalid(sh_cl_dma_pcis_awvalid),
        .pcis_awready(cl_sh_dma_pcis_awready),
        .pcis_wdata(sh_cl_dma_pcis_wdata),
        .pcis_wstrb(sh_cl_dma_pcis_wstrb),
        .pcis_wlast(sh_cl_dma_pcis_wlast),
        .pcis_wvalid(sh_cl_dma_pcis_wvalid),
        .pcis_wready(cl_sh_dma_pcis_wready),
        .pcis_bid(cl_sh_dma_pcis_bid),
        .pcis_bresp(cl_sh_dma_pcis_bresp),
        .pcis_bvalid(cl_sh_dma_pcis_bvalid),
        .pcis_bready(sh_cl_dma_pcis_bready),
        .pcis_araddr(sh_cl_dma_pcis_araddr),
        .pcis_arid(sh_cl_dma_pcis_arid),
        .pcis_arlen(sh_cl_dma_pcis_arlen),
        .pcis_arsize(sh_cl_dma_pcis_arsize),
        .pcis_arvalid(sh_cl_dma_pcis_arvalid),
        .pcis_arready(cl_sh_dma_pcis_arready),
        .pcis_rdata(cl_sh_dma_pcis_rdata),
        .pcis_rid(cl_sh_dma_pcis_rid),
        .pcis_rresp(cl_sh_dma_pcis_rresp),
        .pcis_rlast(cl_sh_dma_pcis_rlast),
        .pcis_rvalid(cl_sh_dma_pcis_rvalid),
        .pcis_rready(sh_cl_dma_pcis_rready),
        .ocl_awaddr(ocl_cl_awaddr),
        .ocl_awvalid(ocl_cl_awvalid),
        .ocl_awready(cl_ocl_awready),
        .ocl_wdata(ocl_cl_wdata),
        .ocl_wstrb(ocl_cl_wstrb),
        .ocl_wvalid(ocl_cl_wvalid),
        .ocl_wready(cl_ocl_wready),
        .ocl_bresp(cl_ocl_bresp),
        .ocl_bvalid(cl_ocl_bvalid),
        .ocl_bready(ocl_cl_bready),
        .ocl_araddr(ocl_cl_araddr),
        .ocl_arvalid(ocl_cl_arvalid),
        .ocl_arready(cl_ocl_arready),
        .ocl_rdata(cl_ocl_rdata),
        .ocl_rresp(cl_ocl_rresp),
        .ocl_rvalid(cl_ocl_rvalid),
        .ocl_rready(ocl_cl_rready),
        .sda_awaddr(sda_cl_awaddr),
        .sda_awvalid(sda_cl_awvalid),
        .sda_awready(cl_sda_awready),
        .sda_wdata(sda_cl_wdata),
        .sda_wstrb(sda_cl_wstrb),
        .sda_wvalid(sda_cl_wvalid),
        .sda_wready(cl_sda_wready),
        .sda_bresp(cl_sda_bresp),
        .sda_bvalid(cl_sda_bvalid),
        .sda_bready(sda_cl_bready),
        .sda_araddr(sda_cl_araddr),
        .sda_arvalid(sda_cl_arvalid),
        .sda_arready(cl_sda_arready),
        .sda_rdata(cl_sda_rdata),
        .sda_rresp(cl_sda_rresp),
        .sda_rvalid(cl_sda_rvalid),
        .sda_rready(sda_cl_rready),
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

    wire [33:0] hbm_axi_araddr [0:23];
    wire [1:0] hbm_axi_arburst [0:23];
    wire [5:0] hbm_axi_arid [0:23];
    wire [3:0] hbm_axi_arlen [0:23];
    wire [2:0] hbm_axi_arsize [0:23];
    wire hbm_axi_arvalid [0:23];
    wire [33:0] hbm_axi_awaddr [0:23];
    wire [1:0] hbm_axi_awburst [0:23];
    wire [5:0] hbm_axi_awid [0:23];
    wire [3:0] hbm_axi_awlen [0:23];
    wire [2:0] hbm_axi_awsize [0:23];
    wire hbm_axi_awvalid [0:23];
    wire hbm_axi_rready [0:23];
    wire hbm_axi_bready [0:23];
    wire [255:0] hbm_axi_wdata [0:23];
    wire hbm_axi_wlast [0:23];
    wire [31:0] hbm_axi_wstrb [0:23];
    wire hbm_axi_wvalid [0:23];
    wire hbm_axi_arready [0:23];
    wire hbm_axi_awready [0:23];
    wire [255:0] hbm_axi_rdata [0:23];
    wire [5:0] hbm_axi_rid [0:23];
    wire hbm_axi_rlast [0:23];
    wire [1:0] hbm_axi_rresp [0:23];
    wire hbm_axi_rvalid [0:23];
    wire hbm_axi_wready [0:23];
    wire [5:0] hbm_axi_bid [0:23];
    wire [1:0] hbm_axi_bresp [0:23];
    wire hbm_axi_bvalid [0:23];
    // Fixed lane ownership: model 0..7, K/V payload 8..15, K/V manifest 16..23.
    // Address fields already contain the physical HBM channel number.
    genvar lane;
    generate for(lane=0;lane<8;lane=lane+1)begin:model_lanes
        assign hbm_axi_araddr[lane]=model_axi_araddr[lane*34 +:34];
        assign hbm_axi_arid[lane]=model_axi_arid[lane*6 +:6];
        assign hbm_axi_arlen[lane]=model_axi_arlen[lane*4 +:4];
        assign hbm_axi_arsize[lane]=model_axi_arsize[lane*3 +:3];
        assign hbm_axi_arburst[lane]=model_axi_arburst[lane*2 +:2];
        assign hbm_axi_arvalid[lane]=model_axi_arvalid[lane*1 +:1];
        assign model_axi_arready[lane*1 +:1]=hbm_axi_arready[lane];
        assign model_axi_rdata[lane*256 +:256]=hbm_axi_rdata[lane];
        assign model_axi_rid[lane*6 +:6]=hbm_axi_rid[lane];
        assign model_axi_rresp[lane*2 +:2]=hbm_axi_rresp[lane];
        assign model_axi_rlast[lane*1 +:1]=hbm_axi_rlast[lane];
        assign model_axi_rvalid[lane*1 +:1]=hbm_axi_rvalid[lane];
        assign hbm_axi_rready[lane]=model_axi_rready[lane*1 +:1];
        assign hbm_axi_awaddr[lane]=model_axi_awaddr[lane*34 +:34];
        assign hbm_axi_awid[lane]=model_axi_awid[lane*6 +:6];
        assign hbm_axi_awlen[lane]=model_axi_awlen[lane*4 +:4];
        assign hbm_axi_awsize[lane]=model_axi_awsize[lane*3 +:3];
        assign hbm_axi_awburst[lane]=model_axi_awburst[lane*2 +:2];
        assign hbm_axi_awvalid[lane]=model_axi_awvalid[lane*1 +:1];
        assign model_axi_awready[lane*1 +:1]=hbm_axi_awready[lane];
        assign hbm_axi_wdata[lane]=model_axi_wdata[lane*256 +:256];
        assign hbm_axi_wstrb[lane]=model_axi_wstrb[lane*32 +:32];
        assign hbm_axi_wlast[lane]=model_axi_wlast[lane*1 +:1];
        assign hbm_axi_wvalid[lane]=model_axi_wvalid[lane*1 +:1];
        assign model_axi_wready[lane*1 +:1]=hbm_axi_wready[lane];
        assign model_axi_bid[lane*6 +:6]=hbm_axi_bid[lane];
        assign model_axi_bresp[lane*2 +:2]=hbm_axi_bresp[lane];
        assign model_axi_bvalid[lane*1 +:1]=hbm_axi_bvalid[lane];
        assign hbm_axi_bready[lane]=model_axi_bready[lane*1 +:1];
    end
    for(lane=0;lane<16;lane=lane+1)begin:kv_lanes
        assign hbm_axi_araddr[lane+8]=kv_axi_araddr[lane*34 +:34];
        assign hbm_axi_arid[lane+8]=kv_axi_arid[lane*6 +:6];
        assign hbm_axi_arlen[lane+8]=kv_axi_arlen[lane*4 +:4];
        assign hbm_axi_arsize[lane+8]=kv_axi_arsize[lane*3 +:3];
        assign hbm_axi_arburst[lane+8]=kv_axi_arburst[lane*2 +:2];
        assign hbm_axi_arvalid[lane+8]=kv_axi_arvalid[lane*1 +:1];
        assign kv_axi_arready[lane*1 +:1]=hbm_axi_arready[lane+8];
        assign kv_axi_rdata[lane*256 +:256]=hbm_axi_rdata[lane+8];
        assign kv_axi_rid[lane*6 +:6]=hbm_axi_rid[lane+8];
        assign kv_axi_rresp[lane*2 +:2]=hbm_axi_rresp[lane+8];
        assign kv_axi_rlast[lane*1 +:1]=hbm_axi_rlast[lane+8];
        assign kv_axi_rvalid[lane*1 +:1]=hbm_axi_rvalid[lane+8];
        assign hbm_axi_rready[lane+8]=kv_axi_rready[lane*1 +:1];
        assign hbm_axi_awaddr[lane+8]=kv_axi_awaddr[lane*34 +:34];
        assign hbm_axi_awid[lane+8]=kv_axi_awid[lane*6 +:6];
        assign hbm_axi_awlen[lane+8]=kv_axi_awlen[lane*4 +:4];
        assign hbm_axi_awsize[lane+8]=kv_axi_awsize[lane*3 +:3];
        assign hbm_axi_awburst[lane+8]=kv_axi_awburst[lane*2 +:2];
        assign hbm_axi_awvalid[lane+8]=kv_axi_awvalid[lane*1 +:1];
        assign kv_axi_awready[lane*1 +:1]=hbm_axi_awready[lane+8];
        assign hbm_axi_wdata[lane+8]=kv_axi_wdata[lane*256 +:256];
        assign hbm_axi_wstrb[lane+8]=kv_axi_wstrb[lane*32 +:32];
        assign hbm_axi_wlast[lane+8]=kv_axi_wlast[lane*1 +:1];
        assign hbm_axi_wvalid[lane+8]=kv_axi_wvalid[lane*1 +:1];
        assign kv_axi_wready[lane*1 +:1]=hbm_axi_wready[lane+8];
        assign kv_axi_bid[lane*6 +:6]=hbm_axi_bid[lane+8];
        assign kv_axi_bresp[lane*2 +:2]=hbm_axi_bresp[lane+8];
        assign kv_axi_bvalid[lane*1 +:1]=hbm_axi_bvalid[lane+8];
        assign hbm_axi_bready[lane+8]=kv_axi_bready[lane*1 +:1];
    end endgenerate
    cfg_bus_t hbm_stats();
    assign hbm_stats.addr=32'b0;
    assign hbm_stats.wdata=32'b0;
    assign hbm_stats.wr=1'b0;
    assign hbm_stats.rd=1'b0;
    assign hbm_stats.user=3'b0;
    cl_mem_hbm_wrapper #(.NUM_OF_AXI_PORTS(24),.AXI4_INTERFACE(0),.AXLEN_WIDTH(4)) HBM(
        .apb_clk(clk_hbm_ref),.i_clk_250m(clk_main_a0),.i_rst_250m_n(vendor_hbm_controller_reset_n),
        .i_clk_450m(memory_clk),.i_rst_450m_n(vendor_hbm_axi_reset_n),
        .i_axi_araddr(hbm_axi_araddr),
        .i_axi_arburst(hbm_axi_arburst),
        .i_axi_arid(hbm_axi_arid),
        .i_axi_arlen(hbm_axi_arlen),
        .i_axi_arsize(hbm_axi_arsize),
        .i_axi_arvalid(hbm_axi_arvalid),
        .i_axi_awaddr(hbm_axi_awaddr),
        .i_axi_awburst(hbm_axi_awburst),
        .i_axi_awid(hbm_axi_awid),
        .i_axi_awlen(hbm_axi_awlen),
        .i_axi_awsize(hbm_axi_awsize),
        .i_axi_awvalid(hbm_axi_awvalid),
        .i_axi_rready(hbm_axi_rready),
        .i_axi_bready(hbm_axi_bready),
        .i_axi_wdata(hbm_axi_wdata),
        .i_axi_wlast(hbm_axi_wlast),
        .i_axi_wstrb(hbm_axi_wstrb),
        .i_axi_wvalid(hbm_axi_wvalid),
        .o_axi_arready(hbm_axi_arready),
        .o_axi_awready(hbm_axi_awready),
        .o_axi_rdata(hbm_axi_rdata),
        .o_axi_rid(hbm_axi_rid),
        .o_axi_rlast(hbm_axi_rlast),
        .o_axi_rresp(hbm_axi_rresp),
        .o_axi_rvalid(hbm_axi_rvalid),
        .o_axi_wready(hbm_axi_wready),
        .o_axi_bid(hbm_axi_bid),
        .o_axi_bresp(hbm_axi_bresp),
        .o_axi_bvalid(hbm_axi_bvalid),
        .i_hbm_apb_preset_n_0(hbm_apb_preset_n_0),
        .o_hbm_apb_paddr_0(hbm_apb_paddr_0),
        .o_hbm_apb_pprot_0(hbm_apb_pprot_0),
        .o_hbm_apb_psel_0(hbm_apb_psel_0),
        .o_hbm_apb_penable_0(hbm_apb_penable_0),
        .o_hbm_apb_pwrite_0(hbm_apb_pwrite_0),
        .o_hbm_apb_pwdata_0(hbm_apb_pwdata_0),
        .o_hbm_apb_pstrb_0(hbm_apb_pstrb_0),
        .o_hbm_apb_pready_0(hbm_apb_pready_0),
        .o_hbm_apb_prdata_0(hbm_apb_prdata_0),
        .o_hbm_apb_pslverr_0(hbm_apb_pslverr_0),
        .i_hbm_apb_preset_n_1(hbm_apb_preset_n_1),
        .o_hbm_apb_paddr_1(hbm_apb_paddr_1),
        .o_hbm_apb_pprot_1(hbm_apb_pprot_1),
        .o_hbm_apb_psel_1(hbm_apb_psel_1),
        .o_hbm_apb_penable_1(hbm_apb_penable_1),
        .o_hbm_apb_pwrite_1(hbm_apb_pwrite_1),
        .o_hbm_apb_pwdata_1(hbm_apb_pwdata_1),
        .o_hbm_apb_pstrb_1(hbm_apb_pstrb_1),
        .o_hbm_apb_pready_1(hbm_apb_pready_1),
        .o_hbm_apb_prdata_1(hbm_apb_prdata_1),
        .o_hbm_apb_pslverr_1(hbm_apb_pslverr_1),
        .hbm_stat_bus(hbm_stats),.o_cl_sh_hbm_stat_int(),.o_hbm_ready(raw_hbm_ready));
endmodule
`default_nettype wire
