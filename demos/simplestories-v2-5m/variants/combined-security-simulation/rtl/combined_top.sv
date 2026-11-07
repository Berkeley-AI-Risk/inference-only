`timescale 1ns/1ps
`default_nettype none
// PRIVATE LOCAL SIMULATION target. All private service and memory ports end at
// labeled test fixtures. No production provisioning/clock/epoch implementation.
module combined_top(
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
    `include "fixture_constants.svh"
    // Portable synchronous AES lookup model; no vendor global-reset cell.
    wire reset_n=power_reset_n && session_reset_n;
    wire sealed,admission_fault;
    wire [255:0] expected_image;
    wire digest_read,boot_digest_read,runtime_digest_read;
    wire [13:0] digest_address,boot_digest_address,runtime_digest_address;
    wire [31:0] digest_data;
    wire metadata_read,boot_metadata_read,runtime_metadata_read;
    wire [11:0] metadata_address,boot_metadata_address,runtime_metadata_address;
    wire [191:0] metadata_data;
    wire lease_reset_n,lease_start,lease_signature_ready;
    wire [7:0] lease_signature_byte,lease_message_byte,lease_message_address;
    wire [10:0] lease_signature_address;
    wire lease_busy,lease_done,lease_valid,lease_fault;
    assign digest_read=boot_locked_o ? runtime_digest_read : boot_digest_read;
    assign digest_address=boot_locked_o ? runtime_digest_address : boot_digest_address;
    assign metadata_read=boot_locked_o ? runtime_metadata_read : boot_metadata_read;
    assign metadata_address=boot_locked_o ? runtime_metadata_address : boot_metadata_address;
    // Original real threshold verifier; complete canonical frame from a
    // behavioral flash source, with no admission/validity seeding.
    swic_boot_admission #(.SHARE_VERIFIER(1'b1),.SHARE_LMS_HASH(1'b1)) u_admission(.clk(clk),.reset_n(reset_n),
        .boot_valid_i(manifest_valid_i),.boot_ready_o(manifest_ready_o),.boot_byte_i(manifest_byte_i),.boot_last_i(manifest_last_i),
        .sealed_o(sealed),.fail_closed_o(admission_fault),.expected_image_sha_o(expected_image),.model_commitment_o(admitted_model_o),
        .digest_read_i(digest_read),.digest_address_i(digest_address),.digest_data_o(digest_data),
        .metadata_read_i(metadata_read),.metadata_address_i(metadata_address),.metadata_data_o(metadata_data),
        .lease_crypto_reset_n_i(lease_reset_n),.lease_crypto_start_i(lease_start),.lease_key_id_i(HOME_KEY_ID),.lease_key_root_i(HOME_KEY_ROOT),
        .lease_signature_byte_i(lease_signature_byte),.lease_message_byte_i(lease_message_byte),.lease_signature_ready_i(lease_signature_ready),
        .lease_signature_address_o(lease_signature_address),.lease_message_address_o(lease_message_address),
        .lease_crypto_busy_o(lease_busy),.lease_crypto_done_o(lease_done),.lease_crypto_valid_o(lease_valid),.lease_crypto_fault_o(lease_fault),
        .nonce_hash_start_i(1'b0),.nonce_hash_byte_valid_i(1'b0),.nonce_hash_byte_i(8'd0),.nonce_hash_available_o(),
        .nonce_hash_done_o(),.nonce_hash_fault_o(),.nonce_hash_offset_o(),.nonce_hash_digest_o());
    // Modeled two-entry private vault: unknown signed models have no key.
    // Public keys are compiled into the unchanged AES/SIV fixture engines.
    wire vault_known=sealed && (admitted_model_o==MODEL_A || admitted_model_o==MODEL_B);
    wire model_slot=admitted_model_o==MODEL_B;
    wire [31:0] key_domain=model_slot ? 32'd2 : 32'd1;
    wire [95:0] model_nonce=model_slot ? NONCE_B : NONCE_A;
    logic scan_started_q,vault_fault_q;
    wire scan_start=vault_known && !scan_started_q && private_epoch_i!=0;
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin scan_started_q<=0;vault_fault_q<=0;end
        else begin
            if(scan_start) scan_started_q<=1;
            if(sealed && (!vault_known || private_epoch_i==0)) vault_fault_q<=1;
        end
    end
    wire plain_valid,plain_ready,cipher_fault,scan_fault;
    wire [255:0] plain_word;
    combined_cipher_stream u_decrypt(.clk(clk),.reset_n(reset_n),.enabled_i(vault_known && scan_started_q && !boot_locked_o),
        .model_slot_i(model_slot),.model_nonce_i(model_nonce),.cipher_valid_i(cipher_valid_i),.cipher_ready_o(cipher_ready_o),
        .cipher_word_i(cipher_word_i),.plain_valid_o(plain_valid),.plain_ready_i(plain_ready),.plain_word_o(plain_word),.fault_o(cipher_fault));
    wire body_norm_read,head_norm_read;
    wire [11:0] body_norm_address,head_norm_address;
    wire [33:0] body_norm_data,head_norm_data;
    combined_boot_scan u_scan(.clk(clk),.reset_n(reset_n),.start_i(scan_start),.source_fault_i(admission_fault || vault_fault_q || cipher_fault),
        .expected_image_sha_i(expected_image),.word_valid_i(plain_valid),.word_ready_o(plain_ready),.word_data_i(plain_word),
        .boot_locked_o(boot_locked_o),.fault_o(scan_fault),
        .digest_read_o(boot_digest_read),.digest_address_o(boot_digest_address),.digest_data_i(digest_data),
        .metadata_read_o(boot_metadata_read),.metadata_address_o(boot_metadata_address),.metadata_data_i(metadata_data),
        .body_norm_read_i(body_norm_read),.head_norm_read_i(head_norm_read),.body_norm_address_i(body_norm_address),
        .head_norm_address_i(head_norm_address),.body_norm_data_o(body_norm_data),.head_norm_data_o(head_norm_data));
    wire context_valid,context_fault;
    combined_identity_hash u_context(.clk(clk),.reset_n(reset_n),.enable_i(boot_locked_o && vault_known),
        .model_root_i(admitted_model_o),.epoch_i(private_epoch_i),.key_domain_i(key_domain),
        .valid_o(context_valid),.digest_o(authorization_context_o),.fault_o(context_fault));
    wire home_enabled,home_failed,home_publication,guard_failed,core_fault;
    logic core_fault_q;
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) core_fault_q<=0;
        else if(core_fault) core_fault_q<=1;
    end
    wire [63:0] home_remaining;
    logic root_ready_q;
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) root_ready_q<=0;
        else if(boot_locked_o && context_valid && memory_drained_o) root_ready_q<=1;
    end
    home_boot_gate #(.USE_SHARED_VERIFIER(1'b1),.DEVICE_ID(HOME_DEVICE),.GEOMETRY(HOME_GEOMETRY),.HOME_KEY_ID(HOME_KEY_ID),.HOME_KEY_ROOT(HOME_KEY_ROOT),
        .RESPONSE_LIMIT_CYCLES(8000000),.LEASE_CYCLES(20000000),.RENEW_LEAD_CYCLES(12000000)) u_home (
        .clk(clk),.reset_n(reset_n),.nonce_valid_i(private_nonce_valid_i),.nonce_fault_i(1'b0),.nonce_i(private_nonce_i),
        .nonce_request_o(private_nonce_request_o),.admitted_root_valid_i(root_ready_q),.admitted_root_i(authorization_context_o),
        .model_fault_i(admission_fault || vault_fault_q || scan_fault || context_fault || guard_failed || core_fault_q),
        .request_valid_o(home_request_valid_o),.request_last_o(home_request_last_o),.request_byte_o(home_request_byte_o),.request_ready_i(home_request_ready_i),
        .grant_valid_i(grant_valid_i),.grant_last_i(grant_last_i),.grant_byte_i(grant_byte_i),.grant_ready_o(grant_ready_o),
        .inference_enabled_o(home_enabled),.failed_o(home_failed),.new_lease_o(new_lease_o),.lease_cycles_remaining_o(home_remaining),
        .publication_allowed_o(home_publication),.shared_reset_n_o(lease_reset_n),.shared_start_o(lease_start),
        .shared_signature_byte_o(lease_signature_byte),.shared_message_byte_o(lease_message_byte),
        .shared_signature_ready_o(lease_signature_ready),.shared_signature_address_i(lease_signature_address),.shared_message_address_i(lease_message_address),
        .shared_busy_i(lease_busy),.shared_done_i(lease_done),.shared_valid_i(lease_valid),.shared_fault_i(lease_fault));
    wire guard_append,guard_step,guard_publish,runtime_reset_n,mem_owned,mem_live,mem_issue;
    wire core_step_ready,core_token_valid,core_busy;
    wire [11:0] core_token;
    wire core_mem_valid,core_mem_write,core_mem_ready;
    wire [18:0] core_mem_word;
    wire [255:0] core_mem_data;
    wire read_accepted=memory_req_valid_o && memory_req_ready_i && !memory_req_write_o;
    combined_lease_guard u_guard(.clk(clk),.power_reset_n(power_reset_n),.session_reset_n(session_reset_n),
        .admitted_i(boot_locked_o && vault_known),.context_valid_i(context_valid),.home_enabled_i(home_enabled),.home_failed_i(home_failed),
        .new_lease_i(new_lease_o),.context_i(authorization_context_o),.epoch_i(private_epoch_i),.trusted_now_i(private_trusted_now_i),
        .clear_i(clear_i),.consumer_idle_i(!core_busy && !core_token_valid && !core_fault),
        .step_valid_i(step_valid_i),.step_ready_i(core_step_ready && guard_step),
        .token_valid_i(core_token_valid && home_publication && !core_fault),.token_ready_i(token_ready_i),
        .append_allowed_o(guard_append),.step_allowed_o(guard_step),.publication_allowed_o(guard_publish),.runtime_reset_n_o(runtime_reset_n),.expired_o(expired_o),.failed_o(guard_failed),
        .memory_read_accepted_i(read_accepted),.memory_response_i(memory_rsp_valid_i),.memory_response_owned_o(mem_owned),.memory_response_live_o(mem_live),
        .memory_issue_allowed_o(mem_issue),.drained_o(memory_drained_o),.dropped_response_count_o(dropped_response_count_o));
    assign runtime_enabled_o=runtime_reset_n;
    assign fault_o=admission_fault || vault_fault_q || cipher_fault || scan_fault || context_fault || home_failed || guard_failed || core_fault;
    assign step_ready_o=core_step_ready && guard_step;
    assign token_valid_o=core_token_valid && guard_publish && home_publication && !core_fault;
    assign token_o=token_valid_o ? core_token : 12'd0;
    assign memory_req_valid_o=core_mem_valid && mem_issue;
    assign memory_req_write_o=memory_req_valid_o && core_mem_write;
    assign memory_req_word_o=memory_req_valid_o ? core_mem_word : 19'd0;
    assign memory_req_data_o=memory_req_valid_o ? core_mem_data : 256'd0;
    assign core_mem_ready=memory_req_ready_i && mem_issue;
    wire core_append_ready;
    assign append_ready_o=core_append_ready && guard_append;
    combined_token_probe #(.AUTH_BANKS(2)) u_core(.core_clk_i(clk),.app_clk_i(clk),.reset_n_i(runtime_reset_n),.clear_i(clear_i && runtime_reset_n),
        .append_valid_i(append_valid_i && guard_append),.append_ready_o(core_append_ready),.append_token_i(append_token_i),
        .step_valid_i(step_valid_i && guard_step),.step_ready_o(core_step_ready),.token_valid_o(core_token_valid),
        .token_ready_i(token_ready_i && guard_publish && home_publication && !core_fault),.token_o(core_token),.busy_o(core_busy),.model_locked_o(),.fail_closed_o(core_fault),
        .private_model_locked_i(boot_locked_o),.private_endpoint_upstream_fault_i(1'b0),
        .private_endpoint_req_valid_o(core_mem_valid),.private_endpoint_req_ready_i(core_mem_ready),.private_endpoint_req_word_address_o(core_mem_word),
        .private_endpoint_req_write_o(core_mem_write),.private_endpoint_req_write_data_o(core_mem_data),
        .private_endpoint_rsp_valid_i(memory_rsp_valid_i && mem_live),.private_endpoint_rsp_ready_o(),
        .private_endpoint_rsp_data_i(mem_live ? memory_rsp_data_i : 256'd0),.private_endpoint_rsp_error_i(memory_rsp_error_i && mem_live),
        .private_model_slot_i(model_slot),.private_model_nonce_i(model_nonce),.private_session_epoch_i(private_epoch_i),
        .private_digest_read_o(runtime_digest_read),.private_digest_address_o(runtime_digest_address),.private_digest_data_i(digest_data),
        .private_metadata_read_o(runtime_metadata_read),.private_metadata_address_o(runtime_metadata_address),.private_metadata_data_i(metadata_data),
        .private_body_norm_read_o(body_norm_read),.private_head_norm_read_o(head_norm_read),.private_body_norm_address_o(body_norm_address),
        .private_head_norm_address_o(head_norm_address),.private_body_norm_data_i(body_norm_data),.private_head_norm_data_i(head_norm_data));
endmodule
`default_nettype wire
