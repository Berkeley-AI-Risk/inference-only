`timescale 1ns/1ps
`default_nettype none
// PRIVATE LOCAL SIMULATION target. All private service and memory ports end at
// labeled test fixtures. No production provisioning/clock/epoch implementation.
module combined_board_harness(
    input wire clk,power_reset_n,session_reset_n,
    input wire [31:0] private_epoch_i,
    input wire [63:0] private_trusted_now_i,
    input wire manifest_valid_i,manifest_last_i,
    input wire [7:0] manifest_byte_i,
    output wire manifest_ready_o,
    input wire cipher_valid_i,
    input wire [255:0] cipher_word_i,
    output wire cipher_ready_o,
    input wire private_nonce_valid_i,
    input wire [255:0] private_nonce_i,
    output wire private_nonce_request_o,
    output wire home_request_valid_o,home_request_last_o,
    output wire [7:0] home_request_byte_o,
    input wire home_request_ready_i,
    input wire grant_valid_i,grant_last_i,
    input wire [7:0] grant_byte_i,
    output wire grant_ready_o,
    input wire append_valid_i,
    input wire [11:0] append_token_i,
    output wire append_ready_o,
    input wire step_valid_i,token_ready_i,clear_i,
    output wire step_ready_o,token_valid_o,
    output wire [11:0] token_o,
    output wire memory_req_valid_o,memory_req_write_o,
    output wire [18:0] memory_req_word_o,
    output wire [255:0] memory_req_data_o,
    input wire memory_req_ready_i,memory_rsp_valid_i,memory_rsp_error_i,
    input wire [255:0] memory_rsp_data_i,
    output wire boot_locked_o,runtime_enabled_o,new_lease_o,expired_o,fault_o,
    output wire [255:0] admitted_model_o,authorization_context_o,
    output wire [63:0] dropped_response_count_o,
    output wire memory_drained_o
);
    wire reset_n=power_reset_n && session_reset_n;
    logic [1:0] flash_state_q;
    logic [18:0] slot_byte_q;
    logic [17:0] image_word_q;
    logic [4:0] image_byte_q;
    wire src_valid,src_ready,src_model,src_last;
    wire [7:0] src_byte;
    assign src_valid=flash_state_q==0 ? manifest_valid_i :
                     flash_state_q==1 ? 1'b1 : flash_state_q==2 && cipher_valid_i;
    assign src_byte=flash_state_q==0 ? manifest_byte_i : flash_state_q==1 ? 8'hff : cipher_word_i[int'(image_byte_q)*8+:8];
    assign src_model=flash_state_q==2;
    assign src_last=(flash_state_q==1 && slot_byte_q==262143) ||
                   (flash_state_q==2 && image_word_q==227061 && image_byte_q==31);
    assign manifest_ready_o=flash_state_q==0 && src_ready;
    assign cipher_ready_o=flash_state_q==2 && image_byte_q==31 && src_ready;
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin flash_state_q<=0;slot_byte_q<=0;image_word_q<=0;image_byte_q<=0;end
        else if(src_valid && src_ready) begin
            if(flash_state_q==0) begin
                slot_byte_q<=slot_byte_q+1'b1;
                if(manifest_last_i)flash_state_q<=1;
            end else if(flash_state_q==1) begin
                slot_byte_q<=slot_byte_q+1'b1;
                if(slot_byte_q==262143)flash_state_q<=2;
            end else if(flash_state_q==2) begin
                if(image_byte_q==31) begin
                    image_byte_q<=0;
                    if(image_word_q==227061)flash_state_q<=3;
                    else image_word_q<=image_word_q+1'b1;
                end else image_byte_q<=image_byte_q+1'b1;
            end
        end
    end
    wire loader_valid,loader_done,loader_ready,scan_valid,scan_ready,memory_fault;
    wire [255:0] loader_data,scan_data;
    wire rt_valid,rt_write,rt_ready,rt_rsp_valid,rt_rsp_error;
    wire [18:0] rt_word;
    wire [255:0] rt_data,rt_rsp_data;
    combined_board_memory u_loader(.clk(clk),.reset_n(reset_n),.upstream_fault_i(1'b0),.boot_locked_i(boot_locked_o),
        .loader_valid_i(loader_valid),.loader_done_i(loader_done),.loader_data_i(loader_data),.loader_ready_o(loader_ready),
        .cipher_valid_o(scan_valid),.cipher_data_o(scan_data),.cipher_ready_i(scan_ready),
        .runtime_req_valid_i(rt_valid),.runtime_req_write_i(rt_write),.runtime_req_word_i(rt_word),.runtime_req_data_i(rt_data),
        .runtime_req_ready_o(rt_ready),.runtime_rsp_valid_o(rt_rsp_valid),.runtime_rsp_error_o(rt_rsp_error),.runtime_rsp_data_o(rt_rsp_data),
        .phy_req_valid_o(memory_req_valid_o),.phy_req_write_o(memory_req_write_o),.phy_req_word_o(memory_req_word_o),.phy_req_data_o(memory_req_data_o),
        .phy_req_ready_i(memory_req_ready_i),.phy_rsp_valid_i(memory_rsp_valid_i),.phy_rsp_error_i(memory_rsp_error_i),.phy_rsp_data_i(memory_rsp_data_i),
        .fault_o(memory_fault),.readback_done_o());
    combined_board_core #(.HOME_RESPONSE_CYCLES(8000000),.HOME_LEASE_CYCLES(120000000),.HOME_RENEW_CYCLES(80000000)) u_board(
        .clk(clk),
        .power_reset_n(power_reset_n),
        .session_reset_n(session_reset_n),
        .private_epoch_i(private_epoch_i),
        .private_trusted_now_i(private_trusted_now_i),
        .manifest_valid_i(src_valid),
        .manifest_last_i(src_last),
        .manifest_byte_i(src_byte),
        .manifest_ready_o(src_ready),
        .cipher_valid_i(scan_valid),
        .cipher_word_i(scan_data),
        .cipher_ready_o(scan_ready),
        .private_nonce_valid_i(private_nonce_valid_i),
        .private_nonce_i(private_nonce_i),
        .private_nonce_request_o(private_nonce_request_o),
        .home_request_valid_o(home_request_valid_o),
        .home_request_last_o(home_request_last_o),
        .home_request_byte_o(home_request_byte_o),
        .home_request_ready_i(home_request_ready_i),
        .grant_valid_i(grant_valid_i),
        .grant_last_i(grant_last_i),
        .grant_byte_i(grant_byte_i),
        .grant_ready_o(grant_ready_o),
        .append_valid_i(append_valid_i),
        .append_token_i(append_token_i),
        .append_ready_o(append_ready_o),
        .step_valid_i(step_valid_i),
        .token_ready_i(token_ready_i),
        .clear_i(clear_i),
        .step_ready_o(step_ready_o),
        .token_valid_o(token_valid_o),
        .token_o(token_o),
        .memory_req_valid_o(rt_valid),
        .memory_req_write_o(rt_write),
        .memory_req_word_o(rt_word),
        .memory_req_data_o(rt_data),
        .memory_req_ready_i(rt_ready),
        .memory_rsp_valid_i(rt_rsp_valid),
        .memory_rsp_error_i(rt_rsp_error),
        .memory_rsp_data_i(rt_rsp_data),
        .boot_locked_o(boot_locked_o),
        .runtime_enabled_o(runtime_enabled_o),
        .new_lease_o(new_lease_o),
        .expired_o(expired_o),
        .fault_o(fault_o),
        .admitted_model_o(admitted_model_o),
        .authorization_context_o(authorization_context_o),
        .dropped_response_count_o(dropped_response_count_o),
        .memory_drained_o(memory_drained_o),
        .manifest_model_i(src_model),
        .private_source_fault_i(memory_fault),
        .private_nonce_fault_i(1'b0),
        .allow_model_o(),
        .boot_loader_valid_o(loader_valid),
        .boot_loader_done_o(loader_done),
        .boot_loader_data_o(loader_data),
        .boot_loader_ready_i(loader_ready)
    );
endmodule
`default_nettype wire
