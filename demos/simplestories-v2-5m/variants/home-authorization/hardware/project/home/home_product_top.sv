`timescale 1ns/1ps
`default_nettype none
module board1_home_auth_product_top (
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
    wire core_clk,core_reset_n,nonce_request,nonce_valid,nonce_fault,raw_enable,raw_valid,model_ready;
    wire hash_start,hash_byte_valid,hash_available,hash_done,hash_fault;
    wire [7:0] hash_byte;
    wire [31:0] hash_offset;
    wire [255:0] hash_digest;
    wire [255:0] nonce,registered_nonce;
    wire [7:0] raw_byte;
    sawic_entropy_source u_entropy(.clk_i(core_clk),.rstn_i(core_reset_n),.enable_i(raw_enable),.valid_o(raw_valid),.data_o(raw_byte));
    nonce_frontend #(.USE_SHARED_HASH(1'b1))u_nonce(.clk(core_clk),.reset_n(core_reset_n),
        .request_i(nonce_request && (!1'b1 || model_ready)),
        .entropy_enable_o(raw_enable),.entropy_valid_i(raw_valid),.entropy_byte_i(raw_byte),
        .nonce_valid_o(nonce_valid),.nonce_o(nonce),.private_nonce_data_o(registered_nonce),.fault_o(nonce_fault),
        .shared_hash_start_o(hash_start),.shared_hash_byte_valid_o(hash_byte_valid),.shared_hash_byte_o(hash_byte),
        .shared_hash_available_i(hash_available),.shared_hash_done_i(hash_done),.shared_hash_fault_i(hash_fault),
        .shared_hash_offset_i(hash_offset),.shared_hash_digest_i(hash_digest));
    board1_home_auth_core #(.SHARE_NONCE_HASH(1'b1),.SHARE_LMS_HASH(1'b1),.HOME_RESPONSE_CYCLES(100000000),.HOME_LEASE_CYCLES(250000000),
        .HOME_RENEW_CYCLES(125000000)) u_core(
        .private_nonce_valid_i(nonce_valid),.private_nonce_fault_i(nonce_fault),.private_nonce_i(registered_nonce),
        .private_nonce_request_o(nonce_request),.private_core_clk_o(core_clk),.private_core_reset_n_o(core_reset_n),
        .private_model_ready_o(model_ready),
        .private_nonce_hash_start_i(hash_start),.private_nonce_hash_byte_valid_i(hash_byte_valid),.private_nonce_hash_byte_i(hash_byte),
        .private_nonce_hash_available_o(hash_available),.private_nonce_hash_done_o(hash_done),.private_nonce_hash_fault_o(hash_fault),
        .private_nonce_hash_offset_o(hash_offset),.private_nonce_hash_digest_o(hash_digest),
        .clk_50mhz(clk_50mhz),.reset_button(reset_button),.uart_rx(uart_rx),.uart_tx(uart_tx),
        .flash_dq(flash_dq),.flash_csn(flash_csn),.flash_sclk(flash_sclk),
        .ddr_addr(ddr_addr),.ddr_bank(ddr_bank),.ddr_cs(ddr_cs),.ddr_ras(ddr_ras),.ddr_cas(ddr_cas),.ddr_we(ddr_we),
        .ddr_ck(ddr_ck),.ddr_ck_n(ddr_ck_n),.ddr_cke(ddr_cke),.ddr_odt(ddr_odt),.ddr_reset_n(ddr_reset_n),
        .ddr_dm(ddr_dm),.ddr_dq(ddr_dq),.ddr_dqs(ddr_dqs),.ddr_dqs_n(ddr_dqs_n));
endmodule
`default_nettype wire
