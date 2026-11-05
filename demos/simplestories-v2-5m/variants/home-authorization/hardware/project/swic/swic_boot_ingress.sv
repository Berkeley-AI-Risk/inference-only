`timescale 1ns/1ps
`default_nettype none
// Core-clock owner of the admission-slot parser and little-endian image packer.
// Erased slot padding is checked; it is never sent as extra manifest traffic.
module swic_boot_ingress #(parameter bit SHARE_VERIFIER=1'b0,parameter bit SHARE_NONCE_HASH=1'b0,parameter bit SHARE_LMS_HASH=1'b0)(
    input wire clk,reset_n,
    input wire byte_valid_i,byte_model_i,byte_last_i,
    input wire [7:0] byte_i,
    output wire byte_ready_o,
    output wire allow_model_o,progress_o,
    output wire [255:0] loader_data_o,
    output wire loader_valid_o,
    input wire loader_ready_i,
    output logic loader_done_o,
    output wire [255:0] image_sha_o,
    output wire [255:0] model_commitment_o,
    output wire fault_o,
    input wire digest_read_i,
    input wire [13:0] digest_address_i,
    output wire [31:0] digest_data_o,
    input wire metadata_read_i,
    input wire [11:0] metadata_address_i,
    output wire [191:0] metadata_data_o,
    input wire lease_crypto_reset_n_i,lease_crypto_start_i,
    input wire [127:0] lease_key_id_i,
    input wire [255:0] lease_key_root_i,
    input wire [7:0] lease_signature_byte_i,lease_message_byte_i,
    input wire lease_signature_ready_i,
    output wire [10:0] lease_signature_address_o,
    output wire [7:0] lease_message_address_o,
    output wire lease_crypto_busy_o,lease_crypto_done_o,lease_crypto_valid_o,lease_crypto_fault_o,
    input wire nonce_hash_start_i,nonce_hash_byte_valid_i,
    input wire [7:0] nonce_hash_byte_i,
    output wire nonce_hash_available_o,nonce_hash_done_o,nonce_hash_fault_o,
    output wire [31:0] nonce_hash_offset_o,
    output wire [255:0] nonce_hash_digest_o
);
    logic [18:0] slot_bytes_q;
    logic [17:0] frame_bytes_q;
    logic [31:0] signers_q;
    logic [22:0] image_bytes_q;
    logic [4:0] byte_q;
    logic [255:0] pack_q,loader_q;
    logic loader_valid_q,local_fault_q,slot_done_q;
    wire admitted,admission_fault,admission_ready;
    wire frame_phase=!slot_done_q && slot_bytes_q<19'(frame_bytes_q);
    wire transfer=byte_valid_i && byte_ready_o;
    wire loader_fire=loader_valid_o && loader_ready_i;
    assign fault_o=local_fault_q || admission_fault;
    assign byte_ready_o=!fault_o && !loader_done_o &&
        (slot_done_q ? (allow_model_o && !loader_valid_q) : (!frame_phase || admission_ready));
    assign allow_model_o=slot_done_q && admitted && !fault_o;
    assign loader_data_o=loader_q;
    assign loader_valid_o=loader_valid_q && !fault_o;
    assign progress_o=transfer || loader_fire;
    swic_boot_admission #(.SHARE_VERIFIER(SHARE_VERIFIER),.SHARE_NONCE_HASH(SHARE_NONCE_HASH),.SHARE_LMS_HASH(SHARE_LMS_HASH))u_admission(
        .clk(clk),.reset_n(reset_n),
        .boot_valid_i(byte_valid_i && !byte_model_i && frame_phase && !fault_o),
        .boot_ready_o(admission_ready),.boot_byte_i(byte_i),
        .boot_last_i(slot_bytes_q==19'(frame_bytes_q)-1),
        .sealed_o(admitted),.fail_closed_o(admission_fault),.expected_image_sha_o(image_sha_o),.model_commitment_o(model_commitment_o),
        .digest_read_i(digest_read_i),.digest_address_i(digest_address_i),.digest_data_o(digest_data_o),
        .metadata_read_i(metadata_read_i),.metadata_address_i(metadata_address_i),.metadata_data_o(metadata_data_o),
        .lease_crypto_reset_n_i(lease_crypto_reset_n_i),.lease_crypto_start_i(lease_crypto_start_i),
        .lease_key_id_i(lease_key_id_i),.lease_key_root_i(lease_key_root_i),
        .lease_signature_byte_i(lease_signature_byte_i),.lease_message_byte_i(lease_message_byte_i),
        .lease_signature_ready_i(lease_signature_ready_i),.lease_signature_address_o(lease_signature_address_o),
        .lease_message_address_o(lease_message_address_o),.lease_crypto_busy_o(lease_crypto_busy_o),
        .lease_crypto_done_o(lease_crypto_done_o),.lease_crypto_valid_o(lease_crypto_valid_o),.lease_crypto_fault_o(lease_crypto_fault_o),
        .nonce_hash_start_i(nonce_hash_start_i),.nonce_hash_byte_valid_i(nonce_hash_byte_valid_i),.nonce_hash_byte_i(nonce_hash_byte_i),
        .nonce_hash_available_o(nonce_hash_available_o),.nonce_hash_done_o(nonce_hash_done_o),.nonce_hash_fault_o(nonce_hash_fault_o),
        .nonce_hash_offset_o(nonce_hash_offset_o),.nonce_hash_digest_o(nonce_hash_digest_o));
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            slot_bytes_q<=0;frame_bytes_q<=18'd116692;signers_q<=0;image_bytes_q<=0;
            byte_q<=0;pack_q<=0;loader_q<=0;loader_valid_q<=0;local_fault_q<=0;
            slot_done_q<=0;loader_done_o<=0;
        end else if(fault_o) begin local_fault_q<=1;loader_valid_q<=0;end
        else begin
            if(loader_fire) begin
                loader_valid_q<=0;
                if(image_bytes_q==23'd7265984) loader_done_o<=1;
            end
            if(transfer) begin
                if(!slot_done_q) begin
                    if(byte_model_i || byte_last_i!=(slot_bytes_q==19'd262143) ||
                       (!frame_phase && byte_i!=8'hff)) local_fault_q<=1;
                    slot_bytes_q<=slot_bytes_q+1;
                    if(slot_bytes_q>=128 && slot_bytes_q<132) begin
                        signers_q<={signers_q[23:0],byte_i};
                        if(slot_bytes_q==131) begin
                            if({signers_q[23:0],byte_i}<2 || {signers_q[23:0],byte_i}>3) local_fault_q<=1;
                            else frame_bytes_q<=18'(112804+int'({signers_q[23:0],byte_i})*1296);
                        end
                    end
                    if(slot_bytes_q==19'd262143) slot_done_q<=1;
                end else begin
                    if(!byte_model_i || byte_last_i!=(image_bytes_q==23'd7265983) ||
                       image_bytes_q>=23'd7265984) local_fault_q<=1;
                    image_bytes_q<=image_bytes_q+1;
                    if(byte_q==31) begin
                        loader_q<={byte_i,pack_q[247:0]};loader_valid_q<=1;byte_q<=0;
                    end else begin pack_q[int'(byte_q)*8 +:8]<=byte_i;byte_q<=byte_q+1;end
                end
            end
        end
    end
endmodule
`default_nettype wire
