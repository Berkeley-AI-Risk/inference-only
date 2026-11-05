`timescale 1ns/1ps
`default_nettype none

// Full package candidate: exact Tang Mega 138K device-C pins, fixed model,
// only APPEND/STEP/CLEAR over UART. No host endpoint, raw DDR command, model
// selector or writable arithmetic program. Not yet hardware/timing qualified.
module board1_home_auth_core #(
    parameter bit SHARE_NONCE_HASH=1'b0,
    parameter bit SHARE_LMS_HASH=1'b0,
    parameter longint unsigned HOME_RESPONSE_CYCLES=250000000,
    parameter longint unsigned HOME_LEASE_CYCLES=1500000000,
    parameter longint unsigned HOME_RENEW_CYCLES=375000000
) (
    input wire private_nonce_valid_i,private_nonce_fault_i,
    input wire [255:0] private_nonce_i,
    output wire private_nonce_request_o,
    output wire private_core_clk_o,private_core_reset_n_o,
    output wire private_model_ready_o,
    input wire private_nonce_hash_start_i,private_nonce_hash_byte_valid_i,
    input wire [7:0] private_nonce_hash_byte_i,
    output wire private_nonce_hash_available_o,private_nonce_hash_done_o,private_nonce_hash_fault_o,
    output wire [31:0] private_nonce_hash_offset_o,
    output wire [255:0] private_nonce_hash_digest_o,
    input wire clk_50mhz,reset_button,uart_rx,
    output wire uart_tx,
    inout wire [3:0] flash_dq,
    output wire flash_csn,flash_sclk,
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
    (* async_reg="true",syn_preserve=1 *) logic core_phase_release_q;
    always_ff @(negedge core_clk or negedge common_async_reset_n) begin
        if(!common_async_reset_n) core_phase_release_q<=0;
        else core_phase_release_q<=1'b1;
    end
    wire qualified_async_reset_n=common_async_reset_n && core_phase_release_q;
    (* async_reg="true",syn_preserve=1 *) logic [2:0] core_release_q;
    always_ff @(posedge core_clk or negedge qualified_async_reset_n) begin
        if(!qualified_async_reset_n) core_release_q<=0;
        else core_release_q<={core_release_q[1:0],1'b1};
    end
    wire core_reset_n=core_release_q[2];
    wire app_cmd_ready,app_cmd_en,app_wr_ready,app_wr_en,app_wr_end;
    wire [2:0] app_cmd;
    wire [28:0] app_addr;
    wire [255:0] app_wr_data,app_rd_data;
    wire [31:0] app_wr_mask;
    wire app_rd_valid,app_rd_end,app_burst,app_sr,app_ref;
    wire swic_byte_valid,swic_byte_ready,swic_byte_model,swic_byte_last,swic_qspi_fault,swic_ingress_fault;
    wire [7:0] swic_byte;
    wire [255:0] swic_image_sha;
    wire swic_digest_read,swic_metadata_read,swic_boot_metadata_read;
    wire [13:0] swic_digest_address;
    wire [11:0] swic_metadata_address,swic_boot_metadata_address;
    wire [31:0] swic_digest_data;
    wire [191:0] swic_metadata_data;
    wire swic_body_norm_read,swic_head_norm_read;
    wire [11:0] swic_body_norm_address,swic_head_norm_address;
    wire [33:0] swic_body_norm_data,swic_head_norm_data;
    wire source_ready,boot_progress,loader_done,loader_valid,loader_ready,source_fault;
    wire [255:0] loader_data;
    wire [3:0] qspi_in,qspi_out,qspi_oe;
    wire request_valid,request_ready,request_write,response_valid,response_error;
    wire [18:0] request_word;
    wire [255:0] request_data,response_data;
    wire model_locked,memory_fault,core_fault,core_fault_in_app;
    assign private_model_ready_o=model_locked && !memory_fault && !source_fault;
    localparam [127:0] HOME_DEVICE=128'h395c83e440d5252bfa59f6138e5ed3b8;
    localparam [255:0] HOME_GEOMETRY=256'h2128664c0025b4ed2ddbd53b2178ea926fe1b3c5e817a2b043a2abc9ee41f078;
    localparam [127:0] HOME_KEY_ID=128'hc044bbc6bdd6530b85e435fd6184137a;
    localparam [255:0] HOME_KEY_ROOT=256'h90c220be722a4b158990b9cff559c0eae3dfd5b45746f8363a1adfe0231556d2;
    wire home_enabled,home_failed,home_accepted,home_request_valid,home_request_last,home_request_ready;
    wire [7:0] home_request_byte,home_grant_byte;
    wire home_grant_valid,home_grant_last,home_grant_ready,home_transport_fault;
    wire [255:0] model_commitment;
    wire [63:0] home_remaining;
    wire home_publication_allowed;
    wire token_uart_tx,token_uart_quiet,home_uart_tx;
    wire lease_crypto_reset_n,lease_crypto_start,lease_signature_ready;
    wire [7:0]lease_signature_byte,lease_message_byte,lease_message_address;
    wire [10:0]lease_signature_address;
    wire lease_crypto_busy,lease_crypto_done,lease_crypto_valid,lease_crypto_fault;
    logic home_mode_q /* synthesis syn_maxfan = 64 */;
    logic home_stop_q;
    wire permit_register_reset_n = core_reset_n && !home_failed &&
                                   !home_transport_fault && !home_stop_q;
    logic token_reset_asserted /* synthesis syn_preserve = 1 */;
    always_ff @(posedge core_clk or negedge permit_register_reset_n) begin
        if (!permit_register_reset_n) token_reset_asserted <= 1'b1;
        else if (home_accepted) token_reset_asserted <= 1'b0;
    end
    wire token_reset_n=~token_reset_asserted;
    always_ff @(posedge core_clk or negedge core_reset_n) begin
        if(!core_reset_n) begin home_mode_q<=0;home_stop_q<=0;end
        else begin
            if(home_failed || home_transport_fault) home_stop_q<=1;
            if(home_accepted) home_mode_q<=0;
            else if(home_request_valid && token_uart_quiet) home_mode_q<=1;
        end
    end
    assign uart_tx=home_mode_q ? home_uart_tx : (home_enabled ? token_uart_tx : 1'b1);
    home_boot_gate #(.USE_SHARED_VERIFIER(1'b1),.DEVICE_ID(HOME_DEVICE),.GEOMETRY(HOME_GEOMETRY),
        .HOME_KEY_ID(HOME_KEY_ID),.HOME_KEY_ROOT(HOME_KEY_ROOT),
        .RESPONSE_LIMIT_CYCLES(HOME_RESPONSE_CYCLES),.LEASE_CYCLES(HOME_LEASE_CYCLES),
        .RENEW_LEAD_CYCLES(HOME_RENEW_CYCLES)) u_home (
        .clk(core_clk),.reset_n(core_reset_n),.nonce_valid_i(private_nonce_valid_i),
        .nonce_fault_i(private_nonce_fault_i),.nonce_i(private_nonce_i),.nonce_request_o(private_nonce_request_o),
        .admitted_root_valid_i(model_locked),.admitted_root_i(model_commitment),
        .model_fault_i(memory_fault || source_fault || home_transport_fault),
        .request_valid_o(home_request_valid),.request_last_o(home_request_last),
        .request_byte_o(home_request_byte),.request_ready_i(home_request_ready),
        .grant_valid_i(home_grant_valid),.grant_last_i(home_grant_last),
        .grant_byte_i(home_grant_byte),.grant_ready_o(home_grant_ready),
        .inference_enabled_o(home_enabled),.failed_o(home_failed),.new_lease_o(home_accepted),
        .lease_cycles_remaining_o(home_remaining),.publication_allowed_o(home_publication_allowed),
        .shared_reset_n_o(lease_crypto_reset_n),.shared_start_o(lease_crypto_start),
        .shared_signature_byte_o(lease_signature_byte),.shared_signature_ready_o(lease_signature_ready),
        .shared_message_byte_o(lease_message_byte),.shared_signature_address_i(lease_signature_address),
        .shared_message_address_i(lease_message_address),.shared_busy_i(lease_crypto_busy),
        .shared_done_i(lease_crypto_done),.shared_valid_i(lease_crypto_valid),.shared_fault_i(lease_crypto_fault));
    home_uart_transport u_home_uart (
        .clk(core_clk),.reset_n(core_reset_n),.enabled_i(home_mode_q),.uart_rx_i(uart_rx),.uart_tx_o(home_uart_tx),
        .request_valid_i(home_request_valid),.request_last_i(home_request_last),
        .request_byte_i(home_request_byte),.request_ready_o(home_request_ready),
        .grant_valid_o(home_grant_valid),.grant_last_o(home_grant_last),
        .grant_byte_o(home_grant_byte),.grant_ready_i(home_grant_ready),.fault_o(home_transport_fault));


    for(genvar lane=0;lane<4;lane=lane+1) begin : g_flash_iobuf
        assign flash_dq[lane]=qspi_oe[lane] ? qspi_out[lane] : 1'bz;
        assign qspi_in[lane]=flash_dq[lane];
    end
    board1_gowin_ddr3_raw_controller_shell u_raw_controller (
        .clk_50mhz(clk_50mhz),.reset_button_n(board_reset_n),
        // Historical port name; the pinned native divider is /4 = 12.5 MHz.
        .trusted_clk_25mhz_o(trusted_clk),.trusted_reset_n_o(trusted_reset_n),
        .core_clk_25mhz_o(core_clk),
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
    logic metadata_collision_q;
    always_ff @(posedge core_clk or negedge core_reset_n) begin
        if(!core_reset_n) metadata_collision_q<=0;
        else if(swic_boot_metadata_read && swic_metadata_read) metadata_collision_q<=1;
    end
    assign source_fault=swic_qspi_fault || swic_ingress_fault || metadata_collision_q;
    swic_qspi_boot_source u_fixed_qspi_boot(
        .trusted_clk_i(trusted_clk),.trusted_reset_n_i(trusted_reset_n),.core_clk_i(core_clk),.core_reset_n_i(core_reset_n),
        .allow_model_i(source_ready),.byte_valid_o(swic_byte_valid),.byte_ready_i(swic_byte_ready),
        .byte_o(swic_byte),.byte_model_o(swic_byte_model),.byte_last_o(swic_byte_last),.fail_closed_o(swic_qspi_fault),
        .qspi_cs_n_o(flash_csn),.qspi_sck_o(flash_sclk),.qspi_dq_i(qspi_in),.qspi_dq_o(qspi_out),.qspi_dq_oe_o(qspi_oe));
    swic_boot_ingress #(.SHARE_VERIFIER(1'b1),.SHARE_NONCE_HASH(SHARE_NONCE_HASH),.SHARE_LMS_HASH(SHARE_LMS_HASH))u_signed_boot(
        .clk(core_clk),.reset_n(core_reset_n),.byte_valid_i(swic_byte_valid),.byte_ready_o(swic_byte_ready),
        .byte_model_i(swic_byte_model),.byte_last_i(swic_byte_last),.byte_i(swic_byte),
        .allow_model_o(source_ready),.progress_o(boot_progress),.loader_valid_o(loader_valid),
        .loader_data_o(loader_data),.loader_ready_i(loader_ready),.loader_done_o(loader_done),
        .image_sha_o(swic_image_sha),.model_commitment_o(model_commitment),.fault_o(swic_ingress_fault),
        .digest_read_i(swic_digest_read),.digest_address_i(swic_digest_address),.digest_data_o(swic_digest_data),
        .metadata_read_i(swic_boot_metadata_read || swic_metadata_read),
        .metadata_address_i(swic_boot_metadata_read ? swic_boot_metadata_address : swic_metadata_address),
        .metadata_data_o(swic_metadata_data),
        .lease_crypto_reset_n_i(lease_crypto_reset_n),.lease_crypto_start_i(lease_crypto_start),
        .lease_key_id_i(HOME_KEY_ID),.lease_key_root_i(HOME_KEY_ROOT),
        .lease_signature_byte_i(lease_signature_byte),.lease_signature_ready_i(lease_signature_ready),
        .lease_message_byte_i(lease_message_byte),.lease_signature_address_o(lease_signature_address),
        .lease_message_address_o(lease_message_address),.lease_crypto_busy_o(lease_crypto_busy),
        .lease_crypto_done_o(lease_crypto_done),.lease_crypto_valid_o(lease_crypto_valid),.lease_crypto_fault_o(lease_crypto_fault),
        .nonce_hash_start_i(private_nonce_hash_start_i),.nonce_hash_byte_valid_i(private_nonce_hash_byte_valid_i),
        .nonce_hash_byte_i(private_nonce_hash_byte_i),.nonce_hash_available_o(private_nonce_hash_available_o),
        .nonce_hash_done_o(private_nonce_hash_done_o),.nonce_hash_fault_o(private_nonce_hash_fault_o),
        .nonce_hash_offset_o(private_nonce_hash_offset_o),.nonce_hash_digest_o(private_nonce_hash_digest_o));
    board1_private_booted_shared_ddr u_memory (
        .trusted_clk_i(trusted_clk),.trusted_reset_n_i(trusted_reset_n),.app_clk_i(core_clk),.app_reset_n_i(core_reset_n),
        .private_fixed_source_ready_i(source_ready),.private_boot_progress_i(boot_progress),
        .private_loader_done_i(loader_done),.private_loader_valid_i(loader_valid),.private_loader_data_i(loader_data),
        .private_loader_ready_o(loader_ready),.private_source_fault_i(source_fault || transport_fault),.private_runtime_app_fault_i(core_fault_in_app || home_stop_q),
        .private_req_valid_i(request_valid),.private_req_write_i(request_write),.private_req_word_i(request_word),
        .private_req_data_i(request_data),.private_req_ready_o(request_ready),.private_rsp_valid_o(response_valid),
        .private_rsp_error_o(response_error),.private_rsp_data_o(response_data),
        .private_model_locked_o(model_locked),.private_fail_closed_o(memory_fault),
        .controller_pll_lock_i(transport_good),.controller_init_calib_complete_i(transport_good),
        .app_cmd_ready_i(sem_cmd_ready),.app_wr_data_ready_i(sem_wr_ready),.app_cmd_o(sem_cmd),.app_cmd_en_o(sem_cmd_en),
        .app_addr_o(sem_addr),.app_wr_data_o(sem_wr_data),.app_wr_data_en_o(sem_wr_en),.app_wr_data_end_o(sem_wr_end),
        .app_wr_data_mask_o(sem_wr_mask),.app_rd_data_i(sem_rd_data),.app_rd_data_valid_i(sem_rd_valid),.app_rd_data_end_i(sem_rd_end),
         .app_burst_o(sem_burst),.app_self_refresh_req_o(sem_sr),.app_refresh_req_o(sem_ref),
        .private_signed_admitted_i(source_ready),.private_signed_image_sha_i(swic_image_sha),
        .private_boot_metadata_read_o(swic_boot_metadata_read),.private_boot_metadata_address_o(swic_boot_metadata_address),
        .private_boot_metadata_data_i(swic_metadata_data),
        .private_body_norm_read_i(swic_body_norm_read),.private_head_norm_read_i(swic_head_norm_read),
        .private_body_norm_address_i(swic_body_norm_address),.private_head_norm_address_i(swic_head_norm_address),
        .private_body_norm_data_o(swic_body_norm_data),.private_head_norm_data_o(swic_head_norm_data));
    board1_private_shared_uart_core u_uart_core (
        .core_clk_i(core_clk),.app_clk_i(core_clk),.reset_n_i(token_reset_n),
        .private_transport_pause_i(home_mode_q),.private_publication_allowed_i(home_publication_allowed),
        .private_uart_quiet_o(token_uart_quiet),.uart_rx_i(uart_rx),.uart_tx_o(token_uart_tx),
        .private_model_locked_i(model_locked),.private_endpoint_upstream_fault_i(memory_fault),
        .private_endpoint_req_valid_o(request_valid),.private_endpoint_req_write_o(request_write),
        .private_endpoint_req_ready_i(request_ready),.private_endpoint_req_word_address_o(request_word),
        .private_endpoint_req_write_data_o(request_data),.private_endpoint_rsp_valid_i(response_valid),
         .private_endpoint_rsp_error_i(response_error),.private_endpoint_rsp_data_i(response_data),.private_fail_closed_o(core_fault),
        .private_digest_read_o(swic_digest_read),.private_digest_address_o(swic_digest_address),.private_digest_data_i(swic_digest_data),
        .private_metadata_read_o(swic_metadata_read),.private_metadata_address_o(swic_metadata_address),.private_metadata_data_i(swic_metadata_data),
        .private_body_norm_read_o(swic_body_norm_read),.private_head_norm_read_o(swic_head_norm_read),
        .private_body_norm_address_o(swic_body_norm_address),.private_head_norm_address_o(swic_head_norm_address),
        .private_body_norm_data_i(swic_body_norm_data),.private_head_norm_data_i(swic_head_norm_data));
    board1_fixed_endpoint_fault_cdc u_core_fault_cdc (
        .core_reset_n_i(core_reset_n),.core_fail_closed_i(core_fault),.app_clk_i(core_clk),
        .app_reset_n_i(core_reset_n),.app_fail_closed_o(core_fault_in_app));
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
        .app_refresh_o(app_ref));
assign private_core_clk_o=core_clk;
    assign private_core_reset_n_o=core_reset_n;
endmodule
`default_nettype wire
