`timescale 1ns/1ps
`default_nettype none

// Full package candidate: exact Tang Mega 138K device-C pins, fixed model,
// only APPEND/STEP/CLEAR over UART. No host endpoint, raw DDR command, model
// selector or writable arithmetic program. Not yet hardware/timing qualified.
module tlm26_tang_top (
    input wire clk_50mhz,reset_button,uart_rx,
    output wire uart_tx,


    output wire [14:0] ddr_addr,
    output wire [2:0] ddr_bank,
    output wire ddr_cs,ddr_ras,ddr_cas,ddr_we,ddr_ck,ddr_ck_n,ddr_cke,ddr_odt,ddr_reset_n,
    output wire [3:0] ddr_dm,
    inout wire [31:0] ddr_dq,
    inout wire [3:0] ddr_dqs,ddr_dqs_n
);
    // All semantic state is now on core25. Physical app100 sees only u_transport.
    wire transport_good,transport_fault;
    wire [2:0] sem_cmd;
    wire [28:0] sem_addr;
    wire [255:0] sem_wr_data,sem_rd_data;
    wire [31:0] sem_wr_mask;
    wire sem_cmd_en,sem_cmd_ready,sem_wr_en,sem_wr_end,sem_wr_ready;
    wire sem_rd_valid,sem_rd_end,sem_burst,sem_sr,sem_ref;
    wire board_reset_n,app_clk,app_reset_n,trusted_clk,trusted_reset_n,pll_lock,calibrated;
    // Tested power-on delay and synchronous reset release from the physical
    // DDR diagnostic; kept despite the historical module's "probe" name.
    private_ddr_probe_reset u_board_reset (
        .clk(clk_50mhz),.reset_button(reset_button),.reset_n(board_reset_n));
    wire core_clk;
    wire common_async_reset_n=board_reset_n && trusted_reset_n && app_reset_n;
    (* async_reg="true",syn_preserve=1 *) logic [2:0] core_release_q;
    always_ff @(posedge core_clk or negedge common_async_reset_n) begin
        if(!common_async_reset_n) core_release_q<=0;
        else core_release_q<={core_release_q[1:0],1'b1};
    end
    wire core_reset_n=core_release_q[2];
    wire app_cmd_ready,app_cmd_en,app_wr_ready,app_wr_en,app_wr_end;
    wire [2:0] app_cmd;
    wire [28:0] app_addr;
    wire [255:0] app_wr_data,app_rd_data;
    wire [31:0] app_wr_mask;
    wire app_rd_valid,app_rd_end,app_burst,app_sr,app_ref;
    wire source_ready,boot_progress,loader_done,loader_valid,loader_ready,source_fault;
    wire [255:0] loader_data;
    wire [3:0] qspi_in,qspi_out,qspi_oe;
    wire request_valid,request_ready,request_write,response_valid,response_error;
    wire [18:0] request_word;
    wire [255:0] request_data,response_data;
    wire model_locked,memory_fault,core_fault,core_fault_in_app;

    board1_gowin_ddr3_raw_controller_shell u_raw_controller (
        .clk_50mhz(clk_50mhz),.reset_button_n(board_reset_n),
        // Historical port name; the pinned native divider is /4 = 12.5 MHz.
        .trusted_clk_25mhz_o(core_clk),.trusted_reset_n_o(trusted_reset_n),
        .core_clk_25mhz_o(),
        .app_clk_100mhz_o(app_clk),.app_reset_n_o(app_reset_n),
        .controller_pll_lock_o(pll_lock),.controller_init_calib_complete_o(calibrated),
        .app_cmd_ready_o(app_cmd_ready),.app_cmd_i(app_cmd),.app_cmd_en_i(app_cmd_en),.app_addr_i(app_addr),
        .app_wr_data_ready_o(app_wr_ready),.app_wr_data_i(app_wr_data),.app_wr_data_en_i(app_wr_en),
        .app_wr_data_end_i(app_wr_end),.app_wr_data_mask_i(app_wr_mask),.app_rd_data_o(app_rd_data),
        .app_rd_data_valid_o(app_rd_valid),.app_rd_data_end_o(app_rd_end),
        .app_burst_i(app_burst),.app_self_refresh_req_i(app_sr),.app_refresh_req_i(app_ref),
        .ddr_addr(ddr_addr),.ddr_bank(ddr_bank),.ddr_cs(ddr_cs),.ddr_ras(ddr_ras),.ddr_cas(ddr_cas),
        .ddr_we(ddr_we),.ddr_ck(ddr_ck),.ddr_ck_n(ddr_ck_n),.ddr_cke(ddr_cke),.ddr_odt(ddr_odt),
        .ddr_reset_n(ddr_reset_n),.ddr_dm(ddr_dm),.ddr_dq(ddr_dq),.ddr_dqs(ddr_dqs),.ddr_dqs_n(ddr_dqs_n));

    wire done,loader_fault,write_req,boot_tx,run_tx;
    wire [16:0] wordno;wire [255:0] staged;
    wire run=done && transport_good && !transport_fault && !loader_fault;
    wire rdreq;wire [21:0] rdadr;
    wire write_take=write_req && sem_cmd_ready && !done;
    wire read_take=rdreq && sem_cmd_ready && run;
    assign uart_tx=done ? run_tx : boot_tx;
    volatile_model_loader loader(.clk(core_clk),.rst_n(core_reset_n),.calibrated(transport_good),
      .uart_rx(uart_rx),.uart_tx(boot_tx),.loaded(done),.fault(loader_fault),.wr_req(write_req),
      .wr_ready(sem_cmd_ready),.wordno(wordno),.worddata(staged));
    tlm_product #(.CLKS_PER_BIT(109)) product(.clk(core_clk),.rst_n(run && core_reset_n),
      .uart_rx(uart_rx),.uart_tx(run_tx),.rd_req(rdreq),.rd_ready(sem_cmd_ready && run),
      .rd_byte_addr(rdadr),.rd_valid(sem_rd_valid),.rd_data(sem_rd_data));
    assign sem_cmd=done?3'd1:3'd0;
    assign sem_addr=done?{9'd0,rdadr[21:2]}:{9'd0,wordno,3'd0};
    assign sem_cmd_en=write_take || read_take;
    assign sem_wr_data=staged;assign sem_wr_en=write_take;assign sem_wr_end=write_take;
    assign sem_wr_mask=0;assign sem_burst=0;assign sem_sr=0;assign sem_ref=0;
    board1_thin_ddr_app_transport u_transport (
        .core_clk_i(core_clk),
        .core_reset_n_i(core_reset_n),
        .app_clk_i(app_clk),
        .app_reset_n_i(app_reset_n),
        .core_stop_i(1'b0),
        .core_fault_o(transport_fault),
        .core_controller_good_o(transport_good),
        .core_cmd_i(sem_cmd),
        .core_cmd_en_i(sem_cmd_en),
        .core_addr_i(sem_addr),
        .core_wr_data_i(sem_wr_data),
        .core_wr_en_i(sem_wr_en),
        .core_wr_end_i(sem_wr_end),
        .core_wr_mask_i(sem_wr_mask),
        .core_burst_i(sem_burst),
        .core_self_refresh_i(sem_sr),
        .core_refresh_i(sem_ref),
        .core_cmd_ready_o(sem_cmd_ready),
        .core_wr_ready_o(sem_wr_ready),
        .core_rd_data_o(sem_rd_data),
        .core_rd_valid_o(sem_rd_valid),
        .core_rd_end_o(sem_rd_end),
        .controller_pll_lock_i(pll_lock),
        .controller_calibrated_i(calibrated),
        .app_cmd_ready_i(app_cmd_ready),
        .app_wr_ready_i(app_wr_ready),
        .app_cmd_o(app_cmd),
        .app_cmd_en_o(app_cmd_en),
        .app_addr_o(app_addr),
        .app_wr_data_o(app_wr_data),
        .app_wr_en_o(app_wr_en),
        .app_wr_end_o(app_wr_end),
        .app_wr_mask_o(app_wr_mask),
        .app_rd_data_i(app_rd_data),
        .app_rd_valid_i(app_rd_valid),
        .app_rd_end_i(app_rd_end),
        .app_burst_o(app_burst),
        .app_self_refresh_o(app_sr),
        .app_refresh_o(app_ref));
endmodule
`default_nettype wire
