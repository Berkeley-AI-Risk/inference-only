`timescale 1ns/1ps
`default_nettype none
// Model-specific renewable home lease. No weight-update delay.
// nonce_* and admitted_root_* are PRIVATE hardware seams, not host inputs.
// The nonce provider must guarantee fresh unpredictable bits and health.
module home_boot_gate #(
    parameter bit USE_SHARED_VERIFIER=1'b0,
    parameter logic [127:0] DEVICE_ID = 128'd0,
    parameter logic [255:0] GEOMETRY = 256'd0,
    parameter logic [127:0] HOME_KEY_ID = 128'd0,
    parameter logic [255:0] HOME_KEY_ROOT = 256'd0,
    parameter longint unsigned RESPONSE_LIMIT_CYCLES = 250000000,
    parameter longint unsigned LEASE_CYCLES = 1500000000,
    parameter longint unsigned RENEW_LEAD_CYCLES = 375000000
) (
    input wire clk, reset_n,
    input wire nonce_valid_i, nonce_fault_i,
    input wire [255:0] nonce_i,
    output wire nonce_request_o,
    input wire admitted_root_valid_i, model_fault_i,
    input wire [255:0] admitted_root_i,
    output wire request_valid_o, request_last_o,
    output wire [7:0] request_byte_o,
    input wire request_ready_i,
    input wire grant_valid_i, grant_last_i,
    input wire [7:0] grant_byte_i,
    output wire grant_ready_o,
    output wire inference_enabled_o, failed_o,
    output wire new_lease_o,
    output wire [63:0] lease_cycles_remaining_o,
    output wire publication_allowed_o,
    // Optional private connection to the boot verifier after admission.
    output wire shared_reset_n_o,shared_start_o,
    output wire [7:0] shared_signature_byte_o,shared_message_byte_o,
    output wire shared_signature_ready_o
);
    localparam logic [127:0] DOMAIN=128'h53415749432d484f4d452d7631000000;
    localparam integer FRAME_BYTES=1420;
    localparam integer TW=(RESPONSE_LIMIT_CYCLES>1)?$clog2(RESPONSE_LIMIT_CYCLES+1):1;
    localparam integer LW=(LEASE_CYCLES>1)?$clog2(LEASE_CYCLES+1):1;
    localparam logic [3:0] COLLECT=0,SEND=1,RECEIVE=2,START=3,VERIFY=4,RUN=5,ARM=6,ARM_WAIT=7,FAIL=15;
    logic [3:0] state_q;
    logic [255:0] nonce_q, root_q;
    logic have_nonce_q, have_root_q, fault_q;
    logic [TW-1:0] age_q;
    logic [LW-1:0] lease_age_q;
    logic lease_active_q, seen_nonce_q;
    logic [255:0] previous_nonce_q;
    logic [10:0] index_q;
    (* ram_style="block" *) logic [7:0] signature_mem [0:1291];
    wire [10:0] signature_address;
    logic [10:0] signature_address_q;
    logic [7:0] signature_byte_q;
    logic signature_read_valid_q;
    wire signature_ready=signature_read_valid_q && signature_address_q==signature_address;
    wire [7:0] message_address;
    wire crypto_done, crypto_valid, crypto_fault, crypto_busy;
    // The inherited verifier is single-use between resets. A new lease must
    // start a fresh verification, never consume the prior lease's verdict.
    logic crypto_reset_release_q;
    always_ff @(posedge clk or negedge reset_n)begin
        if(!reset_n)crypto_reset_release_q<=0;
        else crypto_reset_release_q<=state_q==ARM || state_q==ARM_WAIT || state_q==START || state_q==VERIFY;
    end
    wire crypto_reset_n=reset_n && crypto_reset_release_q;

    // Byte selectors have fixed widths. Reversing the low address bits
    // selects the canonical big-endian byte without wide index arithmetic.
    function automatic [7:0] message_byte(input logic [7:0] address);
        case(address[7:4])
            4'd0: message_byte=DOMAIN[{~address[3:0],3'b000} +:8];
            4'd1: message_byte=DEVICE_ID[{~address[3:0],3'b000} +:8];
            4'd2,4'd3: message_byte=nonce_q[{~address[4:0],3'b000} +:8];
            4'd4,4'd5: message_byte=root_q[{~address[4:0],3'b000} +:8];
            4'd6,4'd7: message_byte=GEOMETRY[{~address[4:0],3'b000} +:8];
            default: message_byte=0;
        endcase
    endfunction

    // Receive/transmit and signature verification are disjoint phases.
    wire [7:0] selected_message_address =
        (state_q==SEND || state_q==RECEIVE) ? index_q[7:0] : message_address;
    wire [7:0] selected_message_byte = message_byte(selected_message_address);

    wire active_window=state_q==SEND || state_q==RECEIVE || state_q==ARM || state_q==ARM_WAIT || state_q==START || state_q==VERIFY;
    wire timed_out=active_window && age_q>=TW'(RESPONSE_LIMIT_CYCLES-1);
    wire root_equal, nonce_equal;
    home_equal256_tree u_root_equal(.a(admitted_root_i),.b(root_q),.equal_o(root_equal));
    home_equal256_tree u_nonce_equal(.a(nonce_i),.b(previous_nonce_q),.equal_o(nonce_equal));
    wire binding_fault=have_root_q && (!admitted_root_valid_i || !root_equal);
    wire expired=lease_active_q && lease_age_q>=LW'(LEASE_CYCLES-1);
    wire fault_now=nonce_fault_i || model_fault_i || binding_fault || timed_out || expired ||
                   (state_q==VERIFY && crypto_fault);
    assign failed_o=fault_q || state_q==FAIL || fault_now;
    assign inference_enabled_o=reset_n && lease_active_q && lease_age_q<LW'(LEASE_CYCLES-1) && !failed_o &&
                               have_root_q && admitted_root_valid_i;
    assign nonce_request_o=state_q==COLLECT && !have_nonce_q && !failed_o;
    assign request_valid_o=state_q==SEND && !failed_o;
    assign request_byte_o=request_valid_o ? selected_message_byte : 8'd0;
    assign request_last_o=request_valid_o && index_q==127;
    assign grant_ready_o=state_q==RECEIVE && !failed_o;
    assign new_lease_o=reset_n && state_q==VERIFY && crypto_done && crypto_valid && !failed_o;
    wire [LW-1:0] remaining_cycles=LW'(LEASE_CYCLES-1)-lease_age_q;
    assign lease_cycles_remaining_o=inference_enabled_o ? 64'(remaining_cycles) : 64'd0;
    // Equivalent to lease_cycles_remaining_o > 20000. inference_enabled_o
    // already requires lease_age_q < LEASE_CYCLES-1, excluding wraparound.
    assign publication_allowed_o=(LEASE_CYCLES>20001) && inference_enabled_o &&
                                 lease_age_q<LW'(LEASE_CYCLES-20001);

    initial begin
        if(RESPONSE_LIMIT_CYCLES<2 || LEASE_CYCLES<=RESPONSE_LIMIT_CYCLES ||
           RENEW_LEAD_CYCLES<=RESPONSE_LIMIT_CYCLES || RENEW_LEAD_CYCLES>=LEASE_CYCLES)
            $fatal(1,"invalid fixed lease timing policy");
    end

    always_ff @(posedge clk) begin
        if(state_q==RECEIVE && grant_valid_i && grant_ready_o && index_q>=128)
            signature_mem[index_q-128]<=grant_byte_i;
        signature_byte_q<=signature_mem[signature_address];
        signature_address_q<=signature_address;
    end
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) signature_read_valid_q<=0;
        else signature_read_valid_q<=1;
    end
    assign shared_reset_n_o=crypto_reset_n;
    assign shared_start_o=state_q==START;
    assign shared_signature_byte_o=signature_byte_q;
    assign shared_signature_ready_o=signature_ready;
    assign shared_message_byte_o=selected_message_byte;
    generate if(USE_SHARED_VERIFIER)begin:g_shared
        assign signature_address=shared_signature_address_i;
        assign message_address=shared_message_address_i;
        assign crypto_busy=shared_busy_i;
        assign crypto_done=shared_done_i;
        assign crypto_valid=shared_valid_i;
        assign crypto_fault=shared_fault_i;
    end else begin:g_dedicated
      su_lms_verify #(.MAX_MESSAGE_BYTES(128)) u_home_signature(
        .clk(clk),.reset_n(crypto_reset_n),.start_i(state_q==START),
        .public_i_i(HOME_KEY_ID),.public_root_i(HOME_KEY_ROOT),.message_length_i(9'd128),
        .signature_address_o(signature_address),.signature_byte_i(signature_byte_q),
        .signature_ready_i(signature_ready),.message_address_o(message_address),
        .message_byte_i(selected_message_byte),
        .busy_o(crypto_busy),.done_o(crypto_done),.valid_o(crypto_valid),.fault_o(crypto_fault));
    end endgenerate

    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            state_q<=COLLECT;nonce_q<=0;root_q<=0;have_nonce_q<=0;have_root_q<=0;
            fault_q<=0;age_q<=0;index_q<=0;lease_active_q<=0;lease_age_q<=0;
            previous_nonce_q<=0;seen_nonce_q<=0;
        end else if(fault_now) begin
            state_q<=FAIL;fault_q<=1;lease_active_q<=0;
        end else begin
            if(active_window) age_q<=age_q+1'b1;
            if(lease_active_q) begin
                if(lease_age_q>=LW'(LEASE_CYCLES-1)) lease_active_q<=0;
                else lease_age_q<=lease_age_q+1'b1;
            end
            case(state_q)
                COLLECT: begin
                    if(nonce_valid_i && nonce_request_o) begin
                        if(nonce_i==0 || (seen_nonce_q && nonce_equal)) begin
                            state_q<=FAIL;fault_q<=1;lease_active_q<=0;
                        end else begin
                            nonce_q<=nonce_i;have_nonce_q<=1;
                            previous_nonce_q<=nonce_i;seen_nonce_q<=1;
                        end
                    end
                    if(admitted_root_valid_i && !have_root_q) begin
                        root_q<=admitted_root_i;have_root_q<=1;
                    end
                    if(have_nonce_q && have_root_q) begin
                        state_q<=SEND;age_q<=0;index_q<=0;
                    end
                end
                SEND: if(request_ready_i) begin
                    if(index_q==127) begin index_q<=0;state_q<=RECEIVE;end
                    else index_q<=index_q+1'b1;
                end
                RECEIVE: if(grant_valid_i) begin
                    if(grant_last_i!=(index_q==11'(FRAME_BYTES-1)) ||
                       (index_q<128 && grant_byte_i!=selected_message_byte)) begin
                        state_q<=FAIL;fault_q<=1;
                    end else if(index_q==11'(FRAME_BYTES-1)) begin state_q<=ARM;end
                    else index_q<=index_q+1'b1;
                end
                ARM: state_q<=ARM_WAIT;
                ARM_WAIT: state_q<=START;
                START: state_q<=VERIFY;
                VERIFY: if(crypto_done) begin
                    if(crypto_valid) begin
                        state_q<=RUN;lease_active_q<=1;lease_age_q<=LW'(age_q)+1'b1;
                    end else begin state_q<=FAIL;fault_q<=1;lease_active_q<=0;end
                end
                RUN: if(lease_age_q>=LW'(LEASE_CYCLES-RENEW_LEAD_CYCLES)) begin
                    state_q<=COLLECT;have_nonce_q<=0;index_q<=0;age_q<=0;
                end
                FAIL: fault_q<=1;
                default: begin state_q<=FAIL;fault_q<=1;end
            endcase
        end
    end
    // Specification history: complete checked transcript and a fresh verifier
    // start must precede every grant. Inputs/verdicts remain unconstrained.
    logic [10:0] spec_received;
    logic [7:0] spec_sent;
    logic spec_frame, spec_started, spec_permitted, spec_header_good;
    logic [255:0] spec_model;
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            spec_received<=0; spec_frame<=0; spec_started<=0;
            spec_sent<=0; spec_header_good<=0;
            spec_permitted<=0; spec_model<=0;
        end else begin
            if(state_q==COLLECT && have_nonce_q && have_root_q) spec_sent<=0;
            if(request_valid_o && request_ready_i) spec_sent<=spec_sent+1'b1;
            if(state_q==SEND && request_ready_i && index_q==127) begin
                spec_received<=0; spec_frame<=0; spec_started<=0;
                spec_header_good<=1;
            end
            if(grant_valid_i && grant_ready_o) begin
                spec_received<=spec_received+1'b1;
                if(index_q<128 && grant_byte_i!=spec_byte) spec_header_good<=0;
                if(grant_last_i==(index_q==1419) &&
                   (index_q>=128 || grant_byte_i==selected_message_byte) && index_q==1419)
                    spec_frame<=1;
            end
            if(shared_start_o) spec_started<=1;
            if(new_lease_o) begin spec_permitted<=1; spec_model<=root_q; end
            if(failed_o) spec_permitted<=0;
        end
    end

    // Independent byte layout: DOMAIN || DEVICE || NONCE || MODEL || GEOMETRY.
    wire [1023:0] spec_message={128'h53415749432d484f4d452d7631000000,
                               DEVICE_ID,nonce_q,root_q,GEOMETRY};
    wire [7:0] spec_byte=selected_message_address[7] ? 8'd0 :
        spec_message[{~selected_message_address[6:0],3'b000} +:8];
    always_comb begin
        assert(selected_message_byte==spec_byte);
        assert(root_equal==(admitted_root_i==root_q));
        assert(nonce_equal==(nonce_i==previous_nonce_q));
        if(reset_n) begin
            if(fault_q) assert(state_q==FAIL);
            if(have_nonce_q) assert(nonce_q!=0 && seen_nonce_q && nonce_q==previous_nonce_q);
            assert(state_q==COLLECT || state_q==SEND || state_q==RECEIVE ||
                   state_q==ARM || state_q==ARM_WAIT || state_q==START ||
                   state_q==VERIFY || state_q==RUN || state_q==FAIL);
            if(state_q==SEND || state_q==RECEIVE || state_q==ARM ||
               state_q==ARM_WAIT || state_q==START || state_q==VERIFY || state_q==RUN)
                assert(have_root_q && have_nonce_q);
            if(state_q==RECEIVE) begin
                assert(spec_header_good);
                assert(index_q==spec_received);
                assert(index_q<=1419);
                assert(spec_sent==128);
            end
            if(state_q==SEND) begin assert(index_q<=127); assert(index_q==spec_sent); end
            if(state_q==ARM || state_q==ARM_WAIT || state_q==START || state_q==VERIFY || state_q==RUN) begin
                assert(spec_frame);
                assert(spec_received==1420);
                assert(spec_header_good && spec_sent==128);
            end
            if(state_q==VERIFY || state_q==RUN) assert(spec_started);
            if(shared_start_o) assert(shared_reset_n_o);
            if(new_lease_o) begin
                assert(spec_frame && spec_started && shared_reset_n_o);
                assert(crypto_done && crypto_valid && !crypto_fault);
                assert(have_root_q && have_nonce_q && nonce_q!=0);
                assert(root_q==admitted_root_i && admitted_root_valid_i);
                assert(age_q<RESPONSE_LIMIT_CYCLES-1);
            end
            if(lease_active_q) begin
                assert(have_root_q);
                if(!failed_o) begin
                    assert(spec_permitted);
                    assert(root_q==spec_model);
                end
                assert(lease_age_q<LEASE_CYCLES);
            end
            if(inference_enabled_o) begin
                assert(spec_permitted && admitted_root_i==spec_model);
                assert(!nonce_fault_i && !model_fault_i && !failed_o);
                assert(lease_cycles_remaining_o>0 && lease_cycles_remaining_o<LEASE_CYCLES);
            end
            if(publication_allowed_o) begin
                assert(inference_enabled_o);
                assert(lease_cycles_remaining_o>20000);
            end
            if(failed_o) assert(!inference_enabled_o && !publication_allowed_o && !new_lease_o);
        end else assert(!inference_enabled_o && !publication_allowed_o && !new_lease_o);
    end

    logic spec_past_valid=0;
    always_ff @(posedge clk) begin
        spec_past_valid<=1;
        if(spec_past_valid && reset_n && $past(reset_n)) begin
            if(shared_start_o) assert($past(shared_reset_n_o));
            if($past(have_root_q)) assert(have_root_q && root_q==$past(root_q));
            if($past(failed_o)) assert(failed_o);
            if($past(nonce_valid_i && nonce_request_o &&
                     (nonce_i==0 || (seen_nonce_q && nonce_equal)))) assert(failed_o);
            if(inference_enabled_o && !$past(inference_enabled_o)) assert($past(new_lease_o));
            if($past(new_lease_o)) assert(lease_age_q==$past(age_q)+1);
            if($past(lease_active_q) && !$past(failed_o) && !$past(new_lease_o))
                assert(lease_age_q==$past(lease_age_q)+1);
            if($past(inference_enabled_o) && inference_enabled_o && !$past(new_lease_o))
                assert(lease_cycles_remaining_o+1==$past(lease_cycles_remaining_o));
        end
    end

    logic spec_consumed, spec_had_grant;
    logic [255:0] spec_last_grant_nonce;
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin spec_consumed<=0;spec_had_grant<=0;spec_last_grant_nonce<=0;end
        else begin
            if(nonce_valid_i && nonce_request_o && !fault_now && nonce_i!=0 &&
               (!seen_nonce_q || !nonce_equal)) spec_consumed<=0;
            if(new_lease_o) begin
                spec_consumed<=1;spec_had_grant<=1;spec_last_grant_nonce<=nonce_q;
            end
        end
    end
    always_comb if(reset_n) begin
        if(spec_had_grant) assert(seen_nonce_q && have_root_q);
        if(spec_consumed) assert(nonce_q==spec_last_grant_nonce && previous_nonce_q==spec_last_grant_nonce);
        if(spec_had_grant && !spec_consumed) assert(have_nonce_q && nonce_q!=spec_last_grant_nonce);
        if(state_q==COLLECT && have_nonce_q) assert(!spec_consumed);
        if(state_q==SEND || state_q==RECEIVE || state_q==ARM || state_q==ARM_WAIT ||
           state_q==START || state_q==VERIFY) assert(!spec_consumed);
        if(state_q==RUN) assert(spec_consumed && spec_had_grant && lease_active_q);
        if(new_lease_o) begin
            assert(!spec_consumed);
            if(spec_had_grant) assert(nonce_q!=spec_last_grant_nonce);
        end
    end
    logic renewal_past=0;
    always_ff @(posedge clk) begin
        renewal_past<=1;
        if(renewal_past && reset_n && $past(reset_n)) begin
            if($past(state_q)==RUN && !$past(fault_now) &&
               $past(lease_age_q)>=LEASE_CYCLES-RENEW_LEAD_CYCLES) begin
                assert(state_q==COLLECT && !have_nonce_q);
                assert(lease_age_q==$past(lease_age_q)+1);
            end
            if($past(failed_o)) assert(!inference_enabled_o && !publication_allowed_o && !new_lease_o);
        end
    end

    // Post-admission shared-verifier selection. The source correspondence audit
    // checks that the published admission mux selects exactly these ports for
    // the lease owner. Boot admission and SHA functional correctness are
    // separate contracts; the real LMS controller and grant RAM are retained.
    wire [10:0] shared_signature_address_i;
    wire [7:0] shared_message_address_i;
    wire shared_busy_i,shared_done_i,shared_valid_i,shared_fault_i;
    (* anyseq *) wire spec_hash_ready,spec_hash_busy,spec_hash_done,spec_hash_fault;
    (* anyseq *) wire [31:0] spec_hash_offset;
    (* anyseq *) wire [255:0] spec_hash_digest;
    wire proof_verifier_started;
    wire [127:0] proof_verifier_identifier;
    wire [255:0] proof_verifier_root;
    wire [8:0] proof_verifier_length;
    su_lms_verify #(.MAX_MESSAGE_BYTES(128),.USE_SHARED_HASH(1'b1)) u_home_verifier (
        .clk(clk),.reset_n(shared_reset_n_o),.start_i(shared_start_o),
        .public_i_i(HOME_KEY_ID),.public_root_i(HOME_KEY_ROOT),.message_length_i(9'd128),
        .signature_address_o(shared_signature_address_i),.signature_byte_i(shared_signature_byte_o),
        .signature_ready_i(shared_signature_ready_o),.message_address_o(shared_message_address_i),
        .message_byte_i(shared_message_byte_o),.busy_o(shared_busy_i),.done_o(shared_done_i),
        .valid_o(shared_valid_i),.fault_o(shared_fault_i),
        .shared_hash_ready_i(shared_reset_n_o && spec_hash_ready),
        .shared_hash_busy_i(shared_reset_n_o && spec_hash_busy),
        .shared_hash_done_i(shared_reset_n_o && spec_hash_done),
        .shared_hash_fault_i(shared_reset_n_o && spec_hash_fault),
        .shared_hash_offset_i(spec_hash_offset),.shared_hash_digest_i(spec_hash_digest),
        .proof_started_o(proof_verifier_started),.proof_identifier_o(proof_verifier_identifier),
        .proof_root_o(proof_verifier_root),.proof_length_o(proof_verifier_length));
    always_comb begin
        if(new_lease_o) begin
            assert(proof_verifier_started && shared_reset_n_o && shared_done_i && shared_valid_i);
            assert(proof_verifier_identifier==HOME_KEY_ID && proof_verifier_root==HOME_KEY_ROOT);
            assert(proof_verifier_length==128);
        end
        if(!shared_reset_n_o) assert(!shared_done_i && !shared_valid_i && !proof_verifier_started);
    end
    logic verifier_join_initial=1;
    always_ff @(posedge clk) verifier_join_initial<=0;
    always_comb if(verifier_join_initial) assume(!reset_n);

endmodule
// Fixed combinational equality tree. Kept boundaries avoid mapping a wide
// comparison into a long carry chain; all 256 bits still participate.
module home_equal256_tree(input wire [255:0] a,b,output wire equal_o);
    wire [127:0] pairs;
    wire [31:0] groups;
    wire [7:0] groups2;
    genvar k;
    generate
        for(k=0;k<128;k=k+1)begin:g_pairs
            wire same /* synthesis syn_keep = 1 */;
            assign same=(a[2*k+:2]==b[2*k+:2]);
            assign pairs[k]=same;
        end
        for(k=0;k<32;k=k+1)begin:g_groups
            wire same /* synthesis syn_keep = 1 */;
            assign same=&pairs[4*k+:4];
            assign groups[k]=same;
        end
        for(k=0;k<8;k=k+1)begin:g_groups2
            wire same /* synthesis syn_keep = 1 */;
            assign same=&groups[4*k+:4];
            assign groups2[k]=same;
        end
    endgenerate
    assign equal_o=&groups2;
endmodule
`default_nettype wire

`timescale 1ns/1ps
`default_nettype none
// RFC 8554 LMS_SHA256_M32_H5 / LMOTS_SHA256_N32_W8 verifier.
// Signature bytes use a PRIVATE ready/data seam for synchronous sealed RAM.
// Message bytes are a private asynchronous small-manifest seam.
// The public key inputs must come from the parent's fixed authority ROM.
// This module contains real SHA computation; there is no external "valid" bit.
module su_lms_verify #(
    parameter integer MAX_MESSAGE_BYTES=256,
    parameter bit USE_SHARED_HASH=1'b0
) (
    input wire clk, reset_n, start_i,
    input wire [127:0] public_i_i,
    input wire [255:0] public_root_i,
    input wire [8:0] message_length_i,
    output logic [10:0] signature_address_o,
    input wire [7:0] signature_byte_i,
    input wire signature_ready_i,
    output logic [7:0] message_address_o,
    input wire [7:0] message_byte_i,
    output wire busy_o,
    output logic done_o, valid_o, fault_o,
    output wire shared_hash_start_o,shared_hash_byte_valid_o,
    output wire [31:0] shared_hash_length_o,
    output wire [7:0] shared_hash_byte_o,
    input wire shared_hash_ready_i,shared_hash_busy_i,shared_hash_done_i,shared_hash_fault_i,
    input wire [31:0] shared_hash_offset_i,
    input wire [255:0] shared_hash_digest_i,
    output wire proof_started_o,
    output wire [127:0] proof_identifier_o,
    output wire [255:0] proof_root_o,
    output wire [8:0] proof_length_o
);
    localparam [4:0] IDLE=0,HEADER=1,CHECK=2,HSTART=3,HWAIT=4,
        COEFFICIENT=5,YLOAD=6,CHAIN=7,SAVE_Z=8,LEAF=9,
        PATH_LOAD=10,PARENT=11,FINISH=12,FAILED=31;
    localparam [2:0] HASH_Q=0,HASH_CHAIN=1,HASH_KEY=2,HASH_LEAF=3,HASH_PARENT=4;
    logic [4:0] state_q,after_hash_q;
    logic [2:0] mode_q;
    logic [127:0] identifier_q;
    logic [255:0] root_q,qhash_q,tmp_q,ots_q,sibling_q;
    (* ram_style="block" *) logic [255:0] z_q [0:33];
    logic [255:0] z_word_q;
    logic [5:0] z_word_index_q;
    logic z_word_valid_q;
    logic [31:0] leaf_q,ots_type_q,lms_type_q,node_q;
    logic [3:0] header_q;
    logic [5:0] element_q,byte_q;
    logic [7:0] iteration_q,coefficient_q;
    logic [15:0] checksum_q;
    logic [2:0] level_q;
    logic [8:0] message_length_q;
    logic [31:0] hash_length;
    wire [31:0] hash_offset;
    logic [7:0] hash_byte;
    wire hash_ready,hash_busy,hash_done,hash_fault;
    wire [255:0] hash_digest;
    wire key_payload=mode_q==HASH_KEY && hash_offset>=22 && hash_offset<1110;
    wire [5:0] key_word_index=6'((hash_offset-22)>>5);
    wire key_ready=!key_payload || (z_word_valid_q && z_word_index_q==key_word_index);
    wire signature_payload=mode_q==HASH_Q && hash_offset>=22 && hash_offset<54;
    wire hash_byte_valid=state_q==HWAIT && key_ready && (!signature_payload || signature_ready_i);
    integer a,k;
    logic [31:0] header_node;
    logic [255:0] left_value,right_value;
    function automatic [7:0] b256(input [255:0] x,input integer n);
        b256=x[255-n*8 -:8];
    endfunction
    function automatic [7:0] b32(input [31:0] x,input integer n);
        b32=x[31-n*8 -:8];
    endfunction
    always_comb begin
        signature_address_o=0;message_address_o=0;
        hash_byte=0;hash_length=0;
        a=int'(hash_offset);k=0;
        header_node=(mode_q==HASH_LEAF) ? node_q :
                    ((mode_q==HASH_PARENT) ? (node_q>>1) : leaf_q);
        left_value=node_q[0] ? sibling_q : tmp_q;
        right_value=node_q[0] ? tmp_q : sibling_q;
        case(mode_q)
            HASH_Q: hash_length=32'd54+32'(message_length_q);
            HASH_CHAIN: hash_length=55;
            HASH_KEY: hash_length=1110;
            HASH_LEAF: hash_length=54;
            HASH_PARENT: hash_length=86;
            default: hash_length=0;
        endcase
        if(a<16) hash_byte=identifier_q[127-a*8 -:8];
        else if(a<20) hash_byte=b32(header_node,a-16);
        else case(mode_q)
            HASH_Q: begin
                if(a<22) hash_byte=8'h81;
                else if(a<54) begin signature_address_o=11'(8+a-22);hash_byte=signature_byte_i;end
                else begin message_address_o=8'(a-54);hash_byte=message_byte_i;end
            end
            HASH_CHAIN: begin
                if(a==20) hash_byte=0;
                else if(a==21) hash_byte={2'd0,element_q};
                else if(a==22) hash_byte=iteration_q;
                else hash_byte=b256(tmp_q,a-23);
            end
            HASH_KEY: begin
                if(a<22) hash_byte=8'h80;
                else begin
                    k=(a-22)/32;
                    if(k<34) hash_byte=b256(z_word_q,(a-22)%32);
                end
            end
            HASH_LEAF: begin
                if(a<22) hash_byte=8'h82;
                else hash_byte=b256(ots_q,a-22);
            end
            HASH_PARENT: begin
                if(a<22) hash_byte=8'h83;
                else if(a<54) hash_byte=b256(left_value,a-22);
                else hash_byte=b256(right_value,a-54);
            end
            default: hash_byte=0;
        endcase
        if(state_q==HEADER) signature_address_o=header_q<8 ? 11'(header_q) : 11'(1120+int'(header_q));
        if(state_q==YLOAD) signature_address_o=11'(40+int'(element_q)*32+int'(byte_q));
        if(state_q==PATH_LOAD) signature_address_o=11'(1132+int'(level_q)*32+int'(byte_q));
    end
    // One synchronous wide read/write RAM. Every row is freshly written by
    // SAVE_Z before HASH_KEY; byte consumption waits for the matching row.
    always_ff @(posedge clk) begin
        if(state_q==SAVE_Z) z_q[element_q]<=tmp_q;
        if(key_payload) z_word_q<=z_q[key_word_index];
    end
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin z_word_valid_q<=0;z_word_index_q<=0;end
        else begin
            z_word_valid_q<=key_payload;
            if(key_payload) z_word_index_q<=key_word_index;
        end
    end
    // Private byte-level service; no host-supplied digest or validity result.
    assign shared_hash_start_o=reset_n && state_q==HSTART;
    assign shared_hash_byte_valid_o=hash_byte_valid;
    assign shared_hash_length_o=hash_length;
    assign shared_hash_byte_o=hash_byte;
    generate if(USE_SHARED_HASH)begin:g_shared_hash
        assign hash_ready=shared_hash_ready_i;
        assign hash_busy=shared_hash_busy_i;
        assign hash_done=shared_hash_done_i;
        assign hash_fault=shared_hash_fault_i;
        assign hash_offset=shared_hash_offset_i;
        assign hash_digest=shared_hash_digest_i;
    end else begin:g_local_hash
    su_sha256 #(.MAX_BYTES(1110)) u_hash(
        .clk(clk),.reset_n(reset_n),.start_i(state_q==HSTART),
        .length_i(hash_length),.byte_valid_i(hash_byte_valid),
        .byte_ready_o(hash_ready),.byte_i(hash_byte),.byte_offset_o(hash_offset),
        .busy_o(hash_busy),.done_o(hash_done),.fault_o(hash_fault),.digest_o(hash_digest));
    end endgenerate
    assign busy_o=state_q!=IDLE && state_q!=FINISH && state_q!=FAILED;
    initial if(MAX_MESSAGE_BYTES<1 || MAX_MESSAGE_BYTES>256) $fatal(1,"unsupported maximum message length");
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            state_q<=IDLE;after_hash_q<=IDLE;mode_q<=HASH_Q;
            identifier_q<=0;root_q<=0;qhash_q<=0;tmp_q<=0;ots_q<=0;sibling_q<=0;
            leaf_q<=0;ots_type_q<=0;lms_type_q<=0;node_q<=0;header_q<=0;
            element_q<=0;byte_q<=0;iteration_q<=0;coefficient_q<=0;
            checksum_q<=0;level_q<=0;message_length_q<=0;done_o<=0;valid_o<=0;fault_o<=0;
        end else if(hash_fault || (start_i && state_q!=IDLE)) begin
            state_q<=FAILED;done_o<=1;valid_o<=0;fault_o<=1;
        end else case(state_q)
            IDLE: if(start_i) begin
                identifier_q<=public_i_i;root_q<=public_root_i;header_q<=0;
                message_length_q<=message_length_i;
                leaf_q<=0;ots_type_q<=0;lms_type_q<=0;
                if(message_length_i==0 || 32'(message_length_i)>MAX_MESSAGE_BYTES) begin
                    state_q<=FAILED;fault_o<=1;done_o<=1;
                end else state_q<=HEADER;
            end
            HEADER: if(signature_ready_i) begin
                if(header_q<4) leaf_q<={leaf_q[23:0],signature_byte_i};
                else if(header_q<8) ots_type_q<={ots_type_q[23:0],signature_byte_i};
                else lms_type_q<={lms_type_q[23:0],signature_byte_i};
                if(header_q==11) state_q<=CHECK;
                else header_q<=header_q+1;
            end
            CHECK: begin
                if(leaf_q>=32 || ots_type_q!=4 || lms_type_q!=5) begin
                    state_q<=FAILED;done_o<=1;fault_o<=1;
                end else begin mode_q<=HASH_Q;after_hash_q<=COEFFICIENT;state_q<=HSTART;end
            end
            HSTART: state_q<=HWAIT;
            HWAIT: if(hash_done) begin
                case(mode_q)
                    HASH_Q: begin
                        qhash_q<=hash_digest;checksum_q<=0;element_q<=0;
                    end
                    HASH_KEY: ots_q<=hash_digest;
                    HASH_CHAIN: begin tmp_q<=hash_digest;iteration_q<=iteration_q+1;end
                    default: tmp_q<=hash_digest;
                endcase
                state_q<=after_hash_q;
            end
            COEFFICIENT: begin
                if(element_q<32) begin
                    checksum_q<=checksum_q+16'(255-int'(b256(qhash_q,int'(element_q))));
                    element_q<=element_q+1;
                end else begin element_q<=0;byte_q<=0;state_q<=YLOAD;end
            end
            YLOAD: if(signature_ready_i) begin
                tmp_q<={tmp_q[247:0],signature_byte_i};
                if(byte_q==31) begin
                    iteration_q<=element_q<32 ? b256(qhash_q,int'(element_q)) :
                        (element_q==32 ? checksum_q[15:8] : checksum_q[7:0]);
                    state_q<=CHAIN;
                end else byte_q<=byte_q+1;
            end
            CHAIN: begin
                if(iteration_q==255) state_q<=SAVE_Z;
                else begin
                    mode_q<=HASH_CHAIN;after_hash_q<=CHAIN;
                    state_q<=HSTART;
                    // Iteration changes only AFTER the corresponding hash.
                end
            end
            SAVE_Z: begin
                if(element_q==33) begin mode_q<=HASH_KEY;after_hash_q<=LEAF;state_q<=HSTART;end
                else begin element_q<=element_q+1;byte_q<=0;state_q<=YLOAD;end
            end
            LEAF: begin
                node_q<=32+leaf_q;mode_q<=HASH_LEAF;after_hash_q<=PATH_LOAD;
                level_q<=0;byte_q<=0;state_q<=HSTART;
            end
            PATH_LOAD: if(signature_ready_i) begin
                sibling_q<={sibling_q[247:0],signature_byte_i};
                if(byte_q==31) begin
                    mode_q<=HASH_PARENT;after_hash_q<=PARENT;state_q<=HSTART;
                end else byte_q<=byte_q+1;
            end
            PARENT: begin
                node_q<=node_q>>1;
                if(level_q==4) begin
                    done_o<=1;valid_o<=tmp_q==root_q;state_q<=FINISH;
                end else begin level_q<=level_q+1;byte_q<=0;state_q<=PATH_LOAD;end
            end
            FINISH: begin end
            FAILED: begin valid_o<=0;fault_o<=1;done_o<=1;end
            default: begin state_q<=FAILED;valid_o<=0;fault_o<=1;done_o<=1;end
        endcase
    end
    // Control provenance of the real LMS verifier, not its cryptographic
    // algorithm: hashes, message bytes and signature bytes are arbitrary.
    logic spec_started;
    logic [127:0] spec_identifier;
    logic [255:0] spec_root;
    logic [8:0] spec_length;
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin spec_started<=0;spec_identifier<=0;spec_root<=0;spec_length<=0;end
        else if(start_i && state_q==IDLE && !hash_fault) begin
            spec_started<=1;spec_identifier<=public_i_i;
            spec_root<=public_root_i;spec_length<=message_length_i;
        end
    end
    always_comb if(reset_n) begin
        assert(state_q==IDLE || state_q==HEADER || state_q==CHECK || state_q==HSTART || state_q==HWAIT ||
               state_q==COEFFICIENT || state_q==YLOAD || state_q==CHAIN || state_q==SAVE_Z ||
               state_q==LEAF || state_q==PATH_LOAD || state_q==PARENT || state_q==FINISH || state_q==FAILED);
        assert(after_hash_q==IDLE || after_hash_q==COEFFICIENT || after_hash_q==CHAIN ||
               after_hash_q==LEAF || after_hash_q==PATH_LOAD || after_hash_q==PARENT);
        if(fault_o) assert(state_q==FAILED);
        if(done_o && !fault_o) assert(state_q==FINISH);
        if(state_q!=IDLE && state_q!=FAILED) assert(spec_started);
        if(spec_started) begin
            assert(identifier_q==spec_identifier && root_q==spec_root && message_length_q==spec_length);
        end
        if(valid_o) assert(done_o && !fault_o && state_q==FINISH && spec_started);
        if(state_q==FAILED) assert(!valid_o && fault_o && done_o);
    end else assert(!valid_o && !done_o);


    assign proof_started_o=spec_started;
    assign proof_identifier_o=spec_identifier;
    assign proof_root_o=spec_root;
    assign proof_length_o=spec_length;
    // These inputs are fixed by the enclosing lease-owner connection. Unlike
    // the reusable standalone verifier lemma, this joined lemma may therefore
    // retain their equality throughout the verifier epoch.
    always_comb if(reset_n && spec_started) begin
        assert(spec_identifier==public_i_i && spec_root==public_root_i && spec_length==message_length_i);
    end

endmodule
`default_nettype wire
