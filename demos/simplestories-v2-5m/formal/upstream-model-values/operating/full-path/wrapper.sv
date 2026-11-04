module board1_runtime_transport_join(
    input wire core_clk,app_clk,trusted_clk,board_reset_n,trusted_reset_n,app_reset_n,pll_lock,calibrated,
    input wire source_ready,boot_progress,loader_done,loader_valid,source_fault,
    input wire[255:0]loader_data,
    input wire core_fault,
    input wire model_app_req_valid,model_cdc_app_fault,
    input wire[18:0]model_app_req_word,
    output wire model_app_req_ready,model_app_rsp_valid,model_app_rsp_error,
    output wire[255:0]model_app_rsp_data,
    input wire private_kv_req_valid_o,private_kv_req_write_o,private_kv_rsp_ready_o,
    input wire[18:0]private_kv_req_word_address_o,
    input wire[255:0]private_kv_req_write_data_o,
    output wire private_kv_req_ready_i,private_kv_rsp_valid_i,private_kv_rsp_error_i,
    output wire[255:0]private_kv_rsp_data_i,
    output wire shared_app_fault,
    input wire f_observe_clear_i,
    input wire app_cmd_ready,app_wr_ready,app_rd_valid,app_rd_end,input wire[255:0]app_rd_data,
    output wire loader_ready,request_ready,response_valid,response_error,model_locked,memory_fault,
    output wire transport_fault,output wire[255:0]response_data,
    output wire[2:0]app_cmd,output wire app_cmd_en,app_wr_en,app_wr_end,
    output wire[28:0]app_addr,output wire[255:0]app_wr_data,output wire[31:0]app_wr_mask,
    output wire app_burst,app_sr,app_ref,
    input wire f_boot_private_loader_ready_o,
    input wire [2:0] f_boot_app_cmd_o,
    input wire f_boot_app_cmd_en_o,
    input wire [28:0] f_boot_app_addr_o,
    input wire [255:0] f_boot_app_wr_data_o,
    input wire f_boot_app_wr_data_en_o,
    input wire f_boot_app_wr_data_end_o,
    input wire [31:0] f_boot_app_wr_data_mask_o,
    input wire f_boot_app_burst_o,
    input wire f_boot_app_self_refresh_req_o,
    input wire f_boot_app_refresh_req_o,
    input wire f_boot_model_locked_o,
    input wire f_boot_fail_closed_o,
    input wire f_boot_watchdog_fault_o
);

    wire core_clk_alias_unused=core_clk;
    wire transport_good,core_fault_in_app;
    wire[2:0]sem_cmd;wire[28:0]sem_addr;wire[255:0]sem_wr_data,sem_rd_data;wire[31:0]sem_wr_mask;
    wire sem_cmd_en,sem_cmd_ready,sem_wr_en,sem_wr_end,sem_wr_ready,sem_rd_valid,sem_rd_end,sem_burst,sem_sr,sem_ref;
    wire common_async_reset_n=board_reset_n && trusted_reset_n && app_reset_n;
    (* async_reg="true",syn_preserve=1 *) logic [2:0] core_release_q;
    always_ff @(posedge core_clk or negedge common_async_reset_n) begin
        if(!common_async_reset_n) core_release_q<=0;
        else core_release_q<={core_release_q[1:0],1'b1};
    end
    wire core_reset_n=core_release_q[2];


    wire f_cdc_model_app_req_valid,f_cdc_model_app_req_ready,f_cdc_model_app_rsp_valid,f_cdc_model_app_rsp_error;
    wire [18:0]f_cdc_model_app_req_word;wire[255:0]f_cdc_model_app_rsp_data;
    wire f_cdc_core_fault,f_cdc_app_fault;
    wire request_valid,request_write;
    wire[18:0]request_word;wire[255:0]request_data;
    wire app_clk_i=core_clk,reset_n_i=core_reset_n;
    wire private_model_locked_i=model_locked;
    wire private_endpoint_upstream_fault_i=memory_fault;
    wire private_endpoint_req_valid_o,private_endpoint_req_write_o;
    wire[18:0]private_endpoint_req_word_address_o;
    wire[255:0]private_endpoint_req_write_data_o;
    wire private_endpoint_req_ready_i=request_ready;
    wire private_endpoint_rsp_valid_i=response_valid;
    wire private_endpoint_rsp_error_i=response_error;
    wire[255:0]private_endpoint_rsp_data_i=response_data;
    wire private_endpoint_rsp_ready_o;
    wire[24:0]shared_raw_word;
    wire shared_kv_req_ready,shared_kv_rsp_valid,shared_kv_rsp_ready;
    assign request_valid=private_endpoint_req_valid_o;
    assign request_write=private_endpoint_req_write_o;
    assign request_word=private_endpoint_req_word_address_o;
    assign request_data=private_endpoint_req_write_data_o;
    board1_private_booted_shared_ddr u_memory (
        .trusted_clk_i(trusted_clk),.trusted_reset_n_i(trusted_reset_n),.app_clk_i(core_clk),.app_reset_n_i(core_reset_n),
        .private_fixed_source_ready_i(source_ready),.private_boot_progress_i(boot_progress),
        .private_loader_done_i(loader_done),.private_loader_valid_i(loader_valid),.private_loader_data_i(loader_data),
        .private_loader_ready_o(loader_ready),.private_source_fault_i(source_fault || transport_fault),.private_runtime_app_fault_i(core_fault_in_app),
        .private_req_valid_i(request_valid),.private_req_write_i(request_write),.private_req_word_i(request_word),
        .private_req_data_i(request_data),.private_req_ready_o(request_ready),.private_rsp_valid_o(response_valid),
        .private_rsp_error_o(response_error),.private_rsp_data_o(response_data),
        .private_model_locked_o(model_locked),.private_fail_closed_o(memory_fault),
        .controller_pll_lock_i(transport_good),.controller_init_calib_complete_i(transport_good),
        .app_cmd_ready_i(sem_cmd_ready),.app_wr_data_ready_i(sem_wr_ready),.app_cmd_o(sem_cmd),.app_cmd_en_o(sem_cmd_en),
        .app_addr_o(sem_addr),.app_wr_data_o(sem_wr_data),.app_wr_data_en_o(sem_wr_en),.app_wr_data_end_o(sem_wr_end),
        .app_wr_data_mask_o(sem_wr_mask),.app_rd_data_i(sem_rd_data),.app_rd_data_valid_i(sem_rd_valid),.app_rd_data_end_i(sem_rd_end),
        .app_burst_o(sem_burst),.app_self_refresh_req_o(sem_sr),.app_refresh_req_o(sem_ref),
        .f_boot_private_loader_ready_o(f_boot_private_loader_ready_o),
        .f_boot_app_cmd_o(f_boot_app_cmd_o),
        .f_boot_app_cmd_en_o(f_boot_app_cmd_en_o),
        .f_boot_app_addr_o(f_boot_app_addr_o),
        .f_boot_app_wr_data_o(f_boot_app_wr_data_o),
        .f_boot_app_wr_data_en_o(f_boot_app_wr_data_en_o),
        .f_boot_app_wr_data_end_o(f_boot_app_wr_data_end_o),
        .f_boot_app_wr_data_mask_o(f_boot_app_wr_data_mask_o),
        .f_boot_app_burst_o(f_boot_app_burst_o),
        .f_boot_app_self_refresh_req_o(f_boot_app_self_refresh_req_o),
        .f_boot_app_refresh_req_o(f_boot_app_refresh_req_o),
        .f_boot_model_locked_o(f_boot_model_locked_o),
        .f_boot_fail_closed_o(f_boot_fail_closed_o),
        .f_boot_watchdog_fault_o(f_boot_watchdog_fault_o)
    );
    board1_thin_ddr_app_transport u_transport (
        .core_clk_i(core_clk),
        .core_reset_n_i(core_reset_n),
        .app_clk_i(app_clk),
        .app_reset_n_i(app_reset_n),
        .core_stop_i(memory_fault || core_fault),
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
        .app_refresh_o(app_ref)
    );
    board1_fixed_endpoint_fault_cdc u_core_fault_cdc (
        .core_reset_n_i(core_reset_n),.core_fail_closed_i(core_fault),.app_clk_i(core_clk),
        .app_reset_n_i(core_reset_n),.app_fail_closed_o(core_fault_in_app));

    logic kv_write_pending_q;
    // reset_n_i is released synchronously to core_clk_i by the parent.
    // The app-side transport shares its asynchronous assertion but owns a
    // separate synchronized release. Neither domain resets on public CLEAR.
    (* async_reg="true",syn_preserve=1 *) logic [2:0] app_runtime_release_q;
    always_ff @(posedge app_clk_i or negedge reset_n_i) begin
        if(!reset_n_i) app_runtime_release_q<=0;
        else app_runtime_release_q<={app_runtime_release_q[1:0],1'b1};
    end
    wire app_runtime_reset_n=app_runtime_release_q[2];

    // The existing typed endpoint retires a WRITE on its request handshake
    // and expects response_valid only for READs. Capture a write into the
    // arbiter once, but do not acknowledge it to that endpoint until the
    // arbiter's completion certifies raw command+data acceptance. This state
    // does not reset on CLEAR, so already offered writes retain drain ownership.
    assign private_kv_req_ready_i=private_kv_req_write_o ?
        (kv_write_pending_q && shared_kv_rsp_valid) : shared_kv_req_ready;
    assign private_kv_rsp_valid_i=shared_kv_rsp_valid && !kv_write_pending_q;
    assign shared_kv_rsp_ready=kv_write_pending_q || private_kv_rsp_ready_o;
    always_ff @(posedge app_clk_i or negedge app_runtime_reset_n) begin
        if(!app_runtime_reset_n) kv_write_pending_q<=0;
        else if(kv_write_pending_q && shared_kv_rsp_valid) kv_write_pending_q<=0;
        else if(private_kv_req_valid_o && shared_kv_req_ready && private_kv_req_write_o)
            kv_write_pending_q<=1;
    end

    board1_private_shared_ddr_transaction_boundary u_shared (
        .clk(app_clk_i),.reset_n(app_runtime_reset_n),.model_locked_i(private_model_locked_i),
        .upstream_fault_i(private_endpoint_upstream_fault_i || f_cdc_app_fault),
        .model_req_valid_i(f_cdc_model_app_req_valid),.model_req_ready_o(f_cdc_model_app_req_ready),
        .model_req_word_i(f_cdc_model_app_req_word),.model_rsp_valid_o(f_cdc_model_app_rsp_valid),
        .model_rsp_data_o(f_cdc_model_app_rsp_data),.model_rsp_error_o(f_cdc_model_app_rsp_error),
        .kv_req_valid_i(private_kv_req_valid_o && !kv_write_pending_q),.kv_req_ready_o(shared_kv_req_ready),
        .kv_req_word_i(private_kv_req_word_address_o),.kv_req_write_i(private_kv_req_write_o),
        .kv_req_data_i(private_kv_req_write_data_o),.kv_rsp_valid_o(shared_kv_rsp_valid),
        .kv_rsp_ready_i(shared_kv_rsp_ready),.kv_rsp_data_o(private_kv_rsp_data_i),
        .kv_rsp_error_o(private_kv_rsp_error_i),.raw_req_valid_o(private_endpoint_req_valid_o),
        .raw_req_ready_i(private_endpoint_req_ready_i),.raw_req_word_o(shared_raw_word),
        .raw_req_write_o(private_endpoint_req_write_o),.raw_req_data_o(private_endpoint_req_write_data_o),
        .raw_rsp_valid_i(private_endpoint_rsp_valid_i),.raw_rsp_data_i(private_endpoint_rsp_data_i),
        .raw_rsp_error_i(private_endpoint_rsp_error_i),.busy_o(),.fault_o(shared_app_fault));
    assign private_endpoint_req_word_address_o=shared_raw_word[18:0];
    // The raw adapter has no return backpressure; reservations guarantee room.
    assign private_endpoint_rsp_ready_o=1'b1;

    board1_private_model_ddr_cdc u_model_cdc(
      .core_clk_i(core_clk),.core_reset_n_i(core_reset_n),.core_upstream_fault_i(core_fault),
      .core_req_valid_i(model_app_req_valid),.core_req_ready_o(model_app_req_ready),.core_req_word_i(model_app_req_word),
      .core_rsp_valid_o(model_app_rsp_valid),.core_rsp_data_o(model_app_rsp_data),.core_rsp_error_o(model_app_rsp_error),
      .core_fault_o(f_cdc_core_fault),.app_clk_i(core_clk),.app_reset_n_i(app_runtime_reset_n),
      .app_upstream_fault_i(private_endpoint_upstream_fault_i || shared_app_fault),
      .app_req_valid_o(f_cdc_model_app_req_valid),.app_req_ready_i(f_cdc_model_app_req_ready),.app_req_word_o(f_cdc_model_app_req_word),
      .app_rsp_valid_i(f_cdc_model_app_rsp_valid),.app_rsp_data_i(f_cdc_model_app_rsp_data),.app_rsp_error_i(f_cdc_model_app_rsp_error),.app_fault_o(f_cdc_app_fault));

endmodule
