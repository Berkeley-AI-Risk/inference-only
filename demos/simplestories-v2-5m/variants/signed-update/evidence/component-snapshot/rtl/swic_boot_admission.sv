`timescale 1ns/1ps
`default_nettype none
// PRIVATE, boot-only admission. Frame = canonical manifest || signer count ||
// sorted (key ID || fixed LMS signature) records || image SHA || page table ||
// projection metadata. Weights travel through the separate DDR loader.
// No delay, lifetime cap, antirollback state or caller-supplied trust anchors.
module swic_boot_admission (
    input wire clk,reset_n,
    input wire boot_valid_i,
    output wire boot_ready_o,
    input wire [7:0] boot_byte_i,
    input wire boot_last_i,
    output wire sealed_o,
    output wire fail_closed_o,
    output wire [255:0] expected_image_sha_o,
    input wire digest_read_i,
    input wire [13:0] digest_address_i,
    output wire [31:0] digest_data_o,
    input wire metadata_read_i,
    input wire [11:0] metadata_address_i,
    output wire [191:0] metadata_data_o
);
    `include "su_policy.svh"
    localparam integer PAGES=1774,DIGEST_WORDS=14192,METADATA_WORDS=2328;
    localparam integer DIGEST_BYTES=56768,METADATA_BYTES=55872;
    localparam integer SIGNATURE_BYTES=1292,RECORD_BYTES=1296;
    localparam integer PAYLOAD_BYTES=112672,ROOT_BYTES=112688;
    localparam [3:0] LOAD=0,MANIFEST=1,ROOT_START=2,ROOT_WAIT=3,
        AUTH_ID=4,AUTH_CHECK=5,AUTH_START=6,AUTH_WAIT=7,RUN=8,FAILED=15;
    logic [3:0] state_q;
    logic fault_q;
    logic [17:0] received_q,signature_end_q,frame_end_q;
    logic [31:0] signer_count_q,key_id_q,previous_key_q;
    logic [1:0] slot_q,id_byte_q,key_q;
    logic [6:0] manifest_index_q;
    logic [255:0] image_sha_q,signed_root_q;
    logic [31:0] load_word_q,digest_read_q;
    logic [191:0] load_metadata_q,metadata_read_q;
    logic [4:0] metadata_byte_q;
    logic [11:0] metadata_word_q;
    (* ram_style="distributed" *) logic [7:0] manifest_q [0:127];
    (* ram_style="block" *) logic [7:0] signature_q [0:3887];
    (* ram_style="block" *) logic [31:0] digest_q [0:DIGEST_WORDS-1];
    (* ram_style="block" *) logic [191:0] metadata_q [0:METADATA_WORDS-1];
    wire boot_fire=boot_valid_i && boot_ready_o;
    wire [17:0] payload_offset=received_q-signature_end_q;
    wire [17:0] table_offset=payload_offset-18'd32;
    wire root_done,root_fault,root_busy,root_ready;
    wire [255:0] root_digest;
    wire [31:0] root_offset;
    logic [31:0] root_fetched_offset_q;
    logic root_fetched_q;
    logic [7:0] root_byte;
    logic [13:0] root_digest_address;
    logic [11:0] root_metadata_address;
    integer a;
    wire lms_reset_n=reset_n && (state_q==AUTH_START || state_q==AUTH_WAIT);
    wire [10:0] lms_signature_address;
    wire [7:0] lms_message_address;
    wire lms_busy,lms_done,lms_valid,lms_fault;
    wire [11:0] signature_index=12'(int'(slot_q)*RECORD_BYTES+4+int'(lms_signature_address));
    wire [11:0] key_index=12'(int'(slot_q)*RECORD_BYTES+int'(id_byte_q));
    wire [127:0] geometry_fields={32'd7265984,32'd1774,32'd55872,32'd0};
    logic manifest_match;
`ifndef SYNTHESIS
    logic input_x_fault;
    always_comb begin
        input_x_fault=$isunknown(boot_valid_i) || $isunknown(digest_read_i) || $isunknown(metadata_read_i);
        if(boot_valid_i) input_x_fault=input_x_fault || $isunknown(boot_byte_i) || $isunknown(boot_last_i);
        if(digest_read_i) input_x_fault=input_x_fault || $isunknown(digest_address_i);
        if(metadata_read_i) input_x_fault=input_x_fault || $isunknown(metadata_address_i);
    end
`else
    wire input_x_fault=1'b0;
`endif
    always_comb begin
        manifest_match=1;
        if(manifest_index_q<16)
            manifest_match=manifest_q[manifest_index_q]==SU_DOMAIN[127-int'(manifest_index_q)*8 -:8];
        else if(manifest_index_q<48)
            manifest_match=manifest_q[manifest_index_q]==SU_GEOMETRY[255-(int'(manifest_index_q)-16)*8 -:8];
        else if(manifest_index_q<64)
            manifest_match=manifest_q[manifest_index_q]==geometry_fields[127-(int'(manifest_index_q)-48)*8 -:8];
        else if(manifest_index_q>=104)
            manifest_match=manifest_q[manifest_index_q]==0;
    end
    always_comb begin
        a=int'(root_offset);
        root_byte=0;root_digest_address=0;root_metadata_address=0;
        if(a<16) root_byte=SU_ROOT_DOMAIN[127-a*8 -:8];
        else if(a<48) root_byte=image_sha_q[255-(a-16)*8 -:8];
        else if(a<48+DIGEST_BYTES) begin
            root_digest_address=14'((a-48)/4);
            root_byte=digest_read_q[31-((a-48)%4)*8 -:8];
        end else if(a<ROOT_BYTES) begin
            root_metadata_address=12'((a-48-DIGEST_BYTES)/24);
            root_byte=metadata_read_q[191-((a-48-DIGEST_BYTES)%24)*8 -:8];
        end
    end
    // One synchronous read port per RAM, shared between root verification
    // and runtime. No payload RAM reset and no write path after LOAD.
    always_ff @(posedge clk) begin
        if(boot_fire && state_q==LOAD) begin
            if(received_q<128) manifest_q[received_q[6:0]]<=boot_byte_i;
            else if(received_q>=132 && received_q<signature_end_q)
                signature_q[12'(received_q-132)]<=boot_byte_i;
            else if(received_q>=signature_end_q && received_q>=132) begin
                if(payload_offset>=32 && 32'(payload_offset)<32+DIGEST_BYTES && table_offset[1:0]==3)
                    digest_q[table_offset[15:2]]<={load_word_q[23:0],boot_byte_i};
                if(32'(payload_offset)>=32+DIGEST_BYTES && metadata_byte_q==23)
                    metadata_q[metadata_word_q]<={load_metadata_q[183:0],boot_byte_i};
            end
        end
        if(state_q==ROOT_WAIT) begin
            digest_read_q<=digest_q[root_digest_address];
            metadata_read_q<=metadata_q[root_metadata_address];
        end else if(sealed_o) begin
            if(digest_read_i && 32'(digest_address_i)<DIGEST_WORDS) digest_read_q<=digest_q[digest_address_i];
            if(metadata_read_i && 32'(metadata_address_i)<METADATA_WORDS) metadata_read_q<=metadata_q[metadata_address_i];
        end
    end
    su_sha256 #(.MAX_BYTES(ROOT_BYTES)) u_root(
        .clk(clk),.reset_n(reset_n),.start_i(state_q==ROOT_START),.length_i(32'(ROOT_BYTES)),
        .byte_valid_i(state_q==ROOT_WAIT && root_fetched_q && root_fetched_offset_q==root_offset),
        .byte_ready_o(root_ready),.byte_i(root_byte),.byte_offset_o(root_offset),
        .busy_o(root_busy),.done_o(root_done),.fault_o(root_fault),.digest_o(root_digest));
    su_lms_verify #(.MAX_MESSAGE_BYTES(128)) u_lms(
        .clk(clk),.reset_n(lms_reset_n),.start_i(state_q==AUTH_START),
        .public_i_i(su_authority_identifier(key_q)),.public_root_i(su_authority_root(key_q)),
        .message_length_i(9'd128),.signature_address_o(lms_signature_address),
        .signature_byte_i(signature_q[signature_index]),.message_address_o(lms_message_address),
        .message_byte_i(manifest_q[lms_message_address[6:0]]),
        .busy_o(lms_busy),.done_o(lms_done),.valid_o(lms_valid),.fault_o(lms_fault));
    assign boot_ready_o=state_q==LOAD && !fault_q;
    assign sealed_o=state_q==RUN && !fail_closed_o;
    assign fail_closed_o=fault_q || root_fault || (state_q==AUTH_WAIT && lms_fault);
    assign expected_image_sha_o=sealed_o ? image_sha_q : 256'd0;
    assign digest_data_o=sealed_o ? digest_read_q : 32'd0;
    assign metadata_data_o=sealed_o ? metadata_read_q : 192'd0;
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            state_q<=LOAD;fault_q<=0;received_q<=0;signature_end_q<=0;frame_end_q<=0;
            signer_count_q<=0;key_id_q<=0;previous_key_q<=0;slot_q<=0;id_byte_q<=0;key_q<=0;
            manifest_index_q<=0;image_sha_q<=0;signed_root_q<=0;load_word_q<=0;
            load_metadata_q<=0;metadata_byte_q<=0;metadata_word_q<=0;
            root_fetched_q<=0;root_fetched_offset_q<=0;
        end else begin
            root_fetched_q<=state_q==ROOT_WAIT;
            root_fetched_offset_q<=root_offset;
            if(input_x_fault || fail_closed_o || (boot_valid_i && state_q!=LOAD) ||
               (sealed_o && ((digest_read_i && 32'(digest_address_i)>=DIGEST_WORDS) ||
                             (metadata_read_i && 32'(metadata_address_i)>=METADATA_WORDS)))) begin
                state_q<=FAILED;fault_q<=1;
            end else case(state_q)
                LOAD: if(boot_fire) begin
                    received_q<=received_q+1;
                    if(boot_last_i != (received_q>=132 && received_q==frame_end_q-1)) begin
                        state_q<=FAILED;fault_q<=1;
                    end else if(received_q>=128 && received_q<132) begin
                        signer_count_q<={signer_count_q[23:0],boot_byte_i};
                        if(received_q==131) begin
                            if({signer_count_q[23:0],boot_byte_i}<2 || {signer_count_q[23:0],boot_byte_i}>3) begin
                                state_q<=FAILED;fault_q<=1;
                            end else begin
                                signature_end_q<=18'(132+int'({signer_count_q[23:0],boot_byte_i})*RECORD_BYTES);
                                frame_end_q<=18'(132+int'({signer_count_q[23:0],boot_byte_i})*RECORD_BYTES+PAYLOAD_BYTES);
                            end
                        end
                    end else if(received_q>=signature_end_q && received_q>=132) begin
                        if(payload_offset<32) image_sha_q<={image_sha_q[247:0],boot_byte_i};
                        else if(32'(payload_offset)<32+DIGEST_BYTES) load_word_q<={load_word_q[23:0],boot_byte_i};
                        else begin
                            load_metadata_q<={load_metadata_q[183:0],boot_byte_i};
                            if(metadata_byte_q==23) begin metadata_byte_q<=0;metadata_word_q<=metadata_word_q+1;end
                            else metadata_byte_q<=metadata_byte_q+1;
                        end
                        if(received_q==frame_end_q-1) begin manifest_index_q<=0;state_q<=MANIFEST;end
                    end
                end
                MANIFEST: begin
                    if(!manifest_match) begin state_q<=FAILED;fault_q<=1;end
                    else begin
                        if(manifest_index_q>=72 && manifest_index_q<104)
                            signed_root_q<={signed_root_q[247:0],manifest_q[manifest_index_q]};
                        if(manifest_index_q==127) state_q<=ROOT_START;
                        else manifest_index_q<=manifest_index_q+1;
                    end
                end
                ROOT_START: state_q<=ROOT_WAIT;
                ROOT_WAIT: if(root_done) begin
                    if(root_digest!=signed_root_q) begin state_q<=FAILED;fault_q<=1;end
                    else begin slot_q<=0;id_byte_q<=0;key_id_q<=0;state_q<=AUTH_ID;end
                end
                AUTH_ID: begin
                    key_id_q<={key_id_q[23:0],signature_q[key_index]};
                    if(id_byte_q==3) state_q<=AUTH_CHECK;
                    else id_byte_q<=id_byte_q+1;
                end
                AUTH_CHECK: begin
                    if(key_id_q>=3 || (slot_q!=0 && key_id_q<=previous_key_q)) begin
                        state_q<=FAILED;fault_q<=1;
                    end else begin key_q<=key_id_q[1:0];state_q<=AUTH_START;end
                end
                AUTH_START: state_q<=AUTH_WAIT;
                AUTH_WAIT: if(lms_done) begin
                    if(!lms_valid || lms_fault) begin state_q<=FAILED;fault_q<=1;end
                    else if(32'(slot_q)+1==signer_count_q) state_q<=RUN;
                    else begin
                        previous_key_q<=key_id_q;slot_q<=slot_q+1;
                        id_byte_q<=0;key_id_q<=0;state_q<=AUTH_ID;
                    end
                end
                RUN: begin end
                FAILED: fault_q<=1;
                default: begin state_q<=FAILED;fault_q<=1;end
            endcase
        end
    end
endmodule
`default_nettype wire
