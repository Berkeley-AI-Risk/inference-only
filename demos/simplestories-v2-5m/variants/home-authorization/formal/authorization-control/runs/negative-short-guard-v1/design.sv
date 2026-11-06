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
    output wire shared_signature_ready_o,
    input wire [10:0] shared_signature_address_i,
    input wire [7:0] shared_message_address_i,
    input wire shared_busy_i,shared_done_i,shared_valid_i,shared_fault_i
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
                                 lease_age_q<LW'(LEASE_CYCLES-10001);

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

    // This is the selected top-level permit register / mux and selected
    // runtime reset release chain, copied byte-for-byte by the runner.
    wire core_clk=clk, core_reset_n=reset_n;
    wire home_failed=failed_o, home_accepted=new_lease_o;
    wire home_enabled=inference_enabled_o, home_request_valid=request_valid_o;
    (* anyseq, keep *) wire home_transport_fault, home_uart_tx;
    wire token_uart_quiet,token_uart_tx;
    wire uart_tx;
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

    wire app_clk_i=clk, reset_n_i=token_reset_n;
    (* async_reg="true",syn_preserve=1 *) logic [2:0] app_runtime_release_q;
    always_ff @(posedge app_clk_i or negedge reset_n_i) begin
        if(!reset_n_i) app_runtime_release_q<=0;
        else app_runtime_release_q<={app_runtime_release_q[1:0],1'b1};
    end
    wire app_runtime_reset_n=app_runtime_release_q[2];
    (* anyseq, keep *) wire proof_model_valid,proof_kv_valid,proof_write,proof_raw_ready,proof_kv_rsp_ready,proof_rsp_valid,proof_rsp_error;
    (* anyseq, keep *) wire [18:0] proof_model_word,proof_kv_word;
    (* anyseq, keep *) wire [255:0] proof_data,proof_response_data;
    wire proof_raw_valid,proof_model_ready,proof_kv_ready;
    board1_private_shared_ddr_arbiter u_actual_runtime_gate (
        .clk(clk),.reset_n(app_runtime_reset_n),
        .model_locked_i(admitted_root_valid_i),.upstream_fault_i(model_fault_i),
        .model_req_valid_i(proof_model_valid),.model_req_word_i(proof_model_word),
        .model_req_ready_o(proof_model_ready),
        .kv_req_valid_i(proof_kv_valid),.kv_req_word_i(proof_kv_word),
        .kv_req_write_i(proof_write),.kv_req_data_i(proof_data),.kv_req_ready_o(proof_kv_ready),
        .kv_rsp_ready_i(proof_kv_rsp_ready),.raw_req_valid_o(proof_raw_valid),
        .raw_req_ready_i(proof_raw_ready),.raw_rsp_valid_i(proof_rsp_valid),
        .raw_rsp_error_i(proof_rsp_error),.raw_rsp_data_i(proof_response_data));
    always_comb begin
        if(reset_n) begin
            assert(state_q==COLLECT || state_q==SEND || state_q==RECEIVE || state_q==ARM ||
                   state_q==ARM_WAIT || state_q==START || state_q==VERIFY || state_q==RUN || state_q==FAIL);
            if(fault_q) assert(state_q==FAIL);
            if(state_q==SEND || state_q==RECEIVE || state_q==ARM || state_q==ARM_WAIT ||
               state_q==START || state_q==VERIFY || state_q==RUN) assert(have_root_q);
            if(lease_active_q) assert(have_root_q);
            if(token_reset_n) assert(lease_active_q && !failed_o);
            if(app_runtime_reset_n) assert(token_reset_n);
        end
        if(!inference_enabled_o) begin
            assert(!token_reset_n);
            assert(!app_runtime_reset_n);
            assert(!proof_raw_valid && !proof_model_ready && !proof_kv_ready);
            if(!home_mode_q) assert(uart_tx==1'b1);
        end
        if(home_stop_q || home_transport_fault || failed_o) assert(!token_reset_n);
    end

    (* anyseq, keep *) wire proof_serial_rx,proof_command_ready,proof_result_valid;
    (* anyseq, keep *) wire [11:0] proof_result_token;
    wire proof_uart_flight,proof_uart_first,proof_uart_quiet;
    wire [13:0] proof_uart_elapsed,proof_uart_rank;
    token_only_model0_uart_bridge #(.CLKS_PER_BIT(217)) u_actual_token_uart (
        .clk(core_clk),.rst_n(token_reset_n),.transport_pause_i(home_mode_q),
        .publication_allowed_i(publication_allowed_o),.uart_quiet_o(token_uart_quiet),
        .uart_rx_i(proof_serial_rx),.uart_tx_o(token_uart_tx),
        .cmd_ready_i(proof_command_ready),.out_valid_i(proof_result_valid),.out_token_i(proof_result_token),
        .proof_flight_o(proof_uart_flight),.proof_first_o(proof_uart_first),
        .proof_quiet_o(proof_uart_quiet),.proof_elapsed_o(proof_uart_elapsed),.proof_rank_o(proof_uart_rank));
    always_comb begin
        if(proof_uart_first) begin
            assert(publication_allowed_o && inference_enabled_o && !home_mode_q);
            assert(spec_permitted && admitted_root_i==spec_model);
            assert(lease_cycles_remaining_o>20000);
        end
        if(proof_uart_flight) begin
            assert(token_reset_n && inference_enabled_o && spec_permitted);
            assert(!home_mode_q);
            assert(admitted_root_i==spec_model);
            assert(lease_cycles_remaining_o>64'(proof_uart_rank));
            assert(proof_uart_elapsed<=10855);
        end
        if(!inference_enabled_o) begin
            assert(!proof_uart_first && !proof_uart_flight);
            assert(!proof_raw_valid && !proof_model_ready && !proof_kv_ready);
            if(!home_mode_q) assert(uart_tx==1'b1);
        end
    end

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

// PRIVATE application-clock seam. One read-only authenticated-page client
// and the bounded pipelined typed K/V boundary share the Gowin adapter.
// No host address, weight-write, or arithmetic command is added. The parent
// must finish trusted boot before raising model_locked_i, and must stop on
// fault_o. This is not the boot writer or a replacement for typed K/V checks.
//
// Reads return in issue order, at least one clock after acceptance, with no
// backpressure. Every model read reserves return space in the upstream CDC
// bridge before being accepted here. A single K/V transaction owns its own
// held response. Writes complete when the adapter accepts command AND data;
// read-after-write ordering is the controller's contract, not a persistence
// guarantee. CLEAR is intentionally absent: accepted traffic must drain.
module board1_private_shared_ddr_arbiter #(
    parameter integer WATCHDOG_CYCLES = 50000000
) (
    input wire clk, reset_n,
    input wire model_locked_i, upstream_fault_i,
    input wire model_req_valid_i,
    output wire model_req_ready_o,
    input wire [18:0] model_req_word_i,
    output wire model_rsp_valid_o,
    output wire [255:0] model_rsp_data_o,
    output wire model_rsp_error_o,
    input wire kv_req_valid_i,
    output wire kv_req_ready_o,
    input wire [18:0] kv_req_word_i,
    input wire kv_req_write_i,
    input wire [255:0] kv_req_data_i,
    output wire kv_rsp_valid_o,
    input wire kv_rsp_ready_i,
    output wire [255:0] kv_rsp_data_o,
    output wire kv_rsp_error_o,
    output wire raw_req_valid_o,
    input wire raw_req_ready_i,
    output wire [24:0] raw_req_word_o,
    output wire raw_req_write_o,
    output wire [255:0] raw_req_data_o,
    input wire raw_rsp_valid_i,
    input wire [255:0] raw_rsp_data_i,
    input wire raw_rsp_error_i,
    output wire busy_o,
    output logic fault_o
);
    localparam integer WW = $clog2(WATCHDOG_CYCLES + 1);
    localparam [18:0] MODEL_WORDS = 19'd227062;
    localparam [18:0] KV_BASE = 19'd227072;
    localparam [18:0] KV_LIMIT = 19'd448256; // 6 * 2048 * 2 * 9 words
    logic lock_seen_q, prefer_kv_q;
    logic cmd_valid_q, cmd_kv_q, cmd_write_q;
    logic [18:0] cmd_word_q;
    logic [255:0] cmd_data_q;
    // Reserve a response slot at admission, not when DDR returns. This
    // bounded window includes queued commands, raw reads and held responses.
    localparam integer KV_CREDITS = 8;
    logic [3:0] kv_reserved_q, kv_response_count_q;
    logic [2:0] kv_response_head_q, kv_response_tail_q;
    logic [255:0] kv_response_data_q [0:KV_CREDITS-1];
    logic kv_write_owner_q;
    wire kv_busy_q = kv_reserved_q != 0;
    wire kv_response_q = kv_response_count_q != 0;
    wire kv_retire = kv_rsp_valid_o && kv_rsp_ready_i;
    logic [31:0] read_owner_q; // 0=model, 1=K/V
    logic [4:0] read_head_q, read_tail_q;
    logic [5:0] read_count_q;
    // Same-cycle registered projections of the owned read count.
    logic read_nonempty_q, read_space_q;
    logic [WW-1:0] watchdog_q;
    logic x_error;

    wire invalid_request =
        (model_req_valid_i && model_req_word_i >= MODEL_WORDS) ||
        (kv_req_valid_i && (kv_req_word_i < KV_BASE || kv_req_word_i >= KV_LIMIT));
    wire invalid_response = raw_rsp_valid_i &&
        (!read_nonempty_q || raw_rsp_error_i || !model_locked_i);
    wire waiting = cmd_valid_q || read_nonempty_q || (kv_busy_q && !kv_response_q);
    wire timed_out = waiting && watchdog_q == WW'(WATCHDOG_CYCLES - 1);
    wire failure = upstream_fault_i || invalid_request || invalid_response ||
                   (lock_seen_q && !model_locked_i) || timed_out || x_error;
    wire enabled = reset_n && model_locked_i && !fault_o && !failure;
    wire returning = raw_rsp_valid_i && read_nonempty_q && enabled;
    wire returning_kv = returning && read_owner_q[read_head_q];
    wire raw_fire = raw_req_valid_o && raw_req_ready_i;
    wire read_issue = raw_fire && !cmd_write_q;
    wire command_room = !cmd_valid_q || raw_fire;
    // Writes remain exclusive through completion delivery. Consequently a
    // write completion cannot overtake earlier K/V reads in the response FIFO.
    wire kv_capacity = kv_reserved_q < 4'd8 && !kv_write_owner_q &&
                       (!kv_req_write_i || kv_reserved_q == 0);
    wire want_kv = kv_req_valid_i && kv_capacity;
    wire take_kv = want_kv && (!model_req_valid_i || prefer_kv_q);
    wire model_fire = model_req_valid_i && model_req_ready_o;
    wire kv_fire = kv_req_valid_i && kv_req_ready_o;

    // Once captured, the command remains stable across arbitrary raw stalls.
    // A full tag FIFO may hold one additional unissued command in this slot.
    assign raw_req_valid_o = enabled && cmd_valid_q &&
                            (cmd_write_q || read_space_q);
    assign raw_req_word_o = {6'd0,cmd_word_q};
    assign raw_req_write_o = cmd_write_q;
    assign raw_req_data_o = cmd_data_q;
    assign model_req_ready_o = enabled && command_room && !take_kv;
    assign kv_req_ready_o = enabled && command_room && take_kv;
    assign model_rsp_valid_o = returning && !read_owner_q[read_head_q];
    assign model_rsp_data_o = raw_rsp_data_i;
    assign model_rsp_error_o = 1'b0; // Errors close the whole private service.
    // A held owner response must not depend combinationally on the next
    // request or its ready logic. The typed parent poisons a simultaneous
    // terminal event; the sticky fault suppresses subsequent visibility.
    assign kv_rsp_valid_o = kv_response_q && reset_n && !fault_o;
    assign kv_rsp_data_o = kv_response_data_q[kv_response_head_q];
    assign kv_rsp_error_o = 1'b0;
    assign busy_o = cmd_valid_q || read_nonempty_q || kv_busy_q;

    wire command_payload_room = !cmd_valid_q ||
        (raw_req_ready_i && (cmd_write_q || read_space_q));

    // Payload and owner RAM have no reset fanout. Validity/counts guard use.
    always_ff @(posedge clk) begin
        // Capture unpublished command payload using local slot/credit state.
        // A valid unissued read behind a full owner ring MUST keep its address
        // even when raw READY is high. Fault, VALID, ownership and acceptance
        // stay on their original paths; invalid-slot address changes are private.
        if (command_payload_room)
            cmd_word_q <= take_kv ? kv_req_word_i : model_req_word_i;
        // Speculative data capture only: VALID, address, opcode, ownership,
        // authorization and command acceptance remain on the original path.
        // Every accepted write captures the correct data on this edge. A
        // stalled valid command holds it. Read-command data is unused by DDR.
        if (!cmd_valid_q || raw_req_ready_i) cmd_data_q <= kv_req_data_i;
        if (read_issue) read_owner_q[read_tail_q] <= cmd_kv_q;
        if (returning_kv || (raw_fire && cmd_write_q))
            kv_response_data_q[kv_response_tail_q] <= returning_kv ? raw_rsp_data_i : 256'd0;
    end

    always_comb begin
        x_error = 0;
`ifndef SYNTHESIS
`ifndef FORMAL
        x_error = $isunknown(model_locked_i) || $isunknown(upstream_fault_i) ||
            $isunknown(model_req_valid_i) || $isunknown(kv_req_valid_i) ||
            $isunknown(raw_rsp_valid_i) || $isunknown(kv_rsp_ready_i);
        if (model_req_valid_i) x_error = x_error || $isunknown(model_req_word_i);
        if (kv_req_valid_i) x_error = x_error || $isunknown(kv_req_word_i) || $isunknown(kv_req_write_i) ||
            (kv_req_write_i && $isunknown(kv_req_data_i));
        if (raw_rsp_valid_i) x_error = x_error || $isunknown(raw_rsp_data_i) || $isunknown(raw_rsp_error_i);
        // Do not reference raw_req_valid_o here: it depends on x_error.
        if (cmd_valid_q) x_error = x_error || $isunknown(raw_req_ready_i);
`endif
`endif
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            lock_seen_q <= 0; prefer_kv_q <= 1;
            cmd_valid_q <= 0; cmd_kv_q <= 0; cmd_write_q <= 0;
            kv_reserved_q <= 0; kv_response_count_q <= 0;
            kv_response_head_q <= 0; kv_response_tail_q <= 0;
            kv_write_owner_q <= 0;
            read_head_q <= 0; read_tail_q <= 0; read_count_q <= 0;
            watchdog_q <= 0; fault_o <= 0;
        end else begin
            if (model_locked_i) lock_seen_q <= 1;
            if (failure) fault_o <= 1;
            if (!waiting || raw_fire || returning) watchdog_q <= 0;
            else if (!fault_o && !timed_out) watchdog_q <= watchdog_q + 1'b1;
            if (enabled) begin
                if (raw_fire) cmd_valid_q <= 0;
                if (model_fire || kv_fire) begin
                    cmd_valid_q <= 1;
                    cmd_kv_q <= kv_fire;
                    cmd_write_q <= kv_fire && kv_req_write_i;
                    prefer_kv_q <= model_fire;
                end
                if (kv_retire) begin
                    kv_response_head_q <= kv_response_head_q + 3'd1;
                    if (kv_write_owner_q) kv_write_owner_q <= 0;
                end
                if (kv_fire && kv_req_write_i) kv_write_owner_q <= 1;
                case ({kv_fire,kv_retire})
                    2'b10: kv_reserved_q <= kv_reserved_q + 4'd1;
                    2'b01: kv_reserved_q <= kv_reserved_q - 4'd1;
                    default: ;
                endcase
                if (returning_kv || (raw_fire && cmd_write_q))
                    kv_response_tail_q <= kv_response_tail_q + 3'd1;
                case ({returning_kv || (raw_fire && cmd_write_q),kv_retire})
                    2'b10: kv_response_count_q <= kv_response_count_q + 4'd1;
                    2'b01: kv_response_count_q <= kv_response_count_q - 4'd1;
                    default: ;
                endcase
                if (read_issue) read_tail_q <= read_tail_q + 5'd1;
                if (returning) read_head_q <= read_head_q + 5'd1;
                case ({read_issue,returning})
                    2'b10: read_count_q <= read_count_q + 6'd1;
                    2'b01: read_count_q <= read_count_q - 6'd1;
                    default: ;
                endcase
            end
        end
    end
    // These flags describe the CURRENT count, not a delayed observation.
    // A simultaneous issue/return leaves occupancy and both flags unchanged.
    // No additional read credit or permission is created by this lookahead.
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            read_nonempty_q <= 1'b0;
            read_space_q <= 1'b1;
        end else begin
            case ({read_issue, returning})
                2'b10: begin
                    read_nonempty_q <= 1'b1;
                    read_space_q <= (read_count_q != 6'd31);
                end
                2'b01: begin
                    read_nonempty_q <= (read_count_q != 6'd1);
                    read_space_q <= 1'b1;
                end
                default: begin end
            endcase
        end
    end

    initial if (WATCHDOG_CYCLES < 4) $fatal(1,"invalid shared-DDR watchdog");

endmodule

`timescale 1ns/1ps
`default_nettype none

// Private transport adapter for the exact token-only command boundary.
// Request:  A5 opcode token_lo 0000_token_hi crc8
// Response: 5A result token_lo 0000_token_hi crc8
// Opcodes are 00 APPEND, 01 STEP, 02 CLEAR.  Results are 80 APPEND accepted,
// 81 generated token, 82 CLEAR accepted, C0..C2 rejected, or CF malformed.
// No frame can select a model, tensor, address, cache, lane, or arithmetic op.
module token_only_model0_uart_bridge #(
    parameter integer CLKS_PER_BIT = 234
) (
    input  wire        clk,
    input  wire        rst_n,
    input wire transport_pause_i, publication_allowed_i,
    output wire uart_quiet_o,
    input  wire        uart_rx_i,
    output wire        uart_tx_o,

    output wire        clear_command_o,
    output wire        cmd_valid_o,
    input  wire        cmd_ready_i,
    output wire [1:0]  cmd_o,
    output wire [11:0] in_token_o,
    input  wire        out_valid_i,
    output wire        out_ready_o,
    input  wire [11:0] out_token_i,
    output wire proof_flight_o,proof_first_o,proof_quiet_o,
    output wire [13:0] proof_elapsed_o,proof_rank_o
);
    localparam [7:0] REQUEST_MAGIC = 8'ha5;
    localparam [7:0] RESPONSE_MAGIC = 8'h5a;
    localparam [7:0] OP_APPEND = 8'h00;
    localparam [7:0] OP_STEP = 8'h01;
    localparam [7:0] OP_CLEAR = 8'h02;
    localparam [12:0] VOCAB_SIZE = 13'd4019;

    function automatic [7:0] crc8_next(
        input [7:0] crc_in,
        input [7:0] data_in
    );
        integer i;
        reg [7:0] value;
        begin
            value = crc_in ^ data_in;
            for (i = 0; i < 8; i = i + 1)
                value = value[7] ? ((value << 1) ^ 8'h07) : (value << 1);
            crc8_next = value;
        end
    endfunction

    wire [11:0] proof_tx_remaining;
    wire rx_valid;
    wire [7:0] rx_byte;
    wire tx_ready;
    wire tx_valid;
    wire [7:0] tx_byte;

    fixed_uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) receiver (
        .clk(clk), .rst_n(rst_n && !transport_pause_i), .serial_i(uart_rx_i),
        .byte_valid_o(rx_valid), .byte_o(rx_byte)
    );

    fixed_uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) transmitter (
        .clk(clk), .rst_n(rst_n && !transport_pause_i), .byte_valid_i(tx_valid),
        .byte_ready_o(tx_ready), .byte_i(tx_byte), .serial_o(uart_tx_o), .proof_remaining_o(proof_tx_remaining)
    );

    typedef enum logic [2:0] {
        BRIDGE_IDLE,
        BRIDGE_OFFER,
        BRIDGE_WAIT_RESULT,
        BRIDGE_SEND,
        BRIDGE_DRAIN
    } bridge_state_t;
    bridge_state_t state_q;

    logic [2:0] request_index_q;
    logic [7:0] request_crc_q;
    logic [7:0] request_opcode_q;
    logic [7:0] request_token_low_q;
    logic [7:0] request_token_high_q;

    logic [1:0] command_q;
    logic [11:0] command_token_q;
    logic [7:0] response_kind_q;
    logic [11:0] response_token_q;
    logic [7:0] response_crc_q;
    logic [2:0] response_index_q;
    logic clear_pending_q;
    logic recovery_clear_q;

    wire [7:0] response_byte0 = RESPONSE_MAGIC;
    wire [7:0] response_byte1 = response_kind_q;
    wire [7:0] response_byte2 = response_token_q[7:0];
    wire [7:0] response_byte3 = {4'b0000, response_token_q[11:8]};
    wire [7:0] computed_response_crc =
        crc8_next(crc8_next(crc8_next(crc8_next(8'h00,
        response_byte0), response_byte1), response_byte2), response_byte3);
    wire request_unknown;
`ifndef SYNTHESIS
    assign request_unknown = $isunknown({rx_byte, request_crc_q,
                                         request_opcode_q,
                                         request_token_low_q,
                                         request_token_high_q});
`else
    assign request_unknown = 1'b0;
`endif

    assign cmd_valid_o = !transport_pause_i && ((state_q == BRIDGE_OFFER) ||
                         (state_q == BRIDGE_WAIT_RESULT && clear_pending_q));
    assign cmd_o = (state_q == BRIDGE_WAIT_RESULT && clear_pending_q) ?
                   OP_CLEAR[1:0] : command_q;
    assign in_token_o = (state_q == BRIDGE_WAIT_RESULT && clear_pending_q) ?
                        12'b0 : command_token_q;
    assign out_ready_o = !transport_pause_i && publication_allowed_i && (state_q == BRIDGE_WAIT_RESULT);
    assign tx_valid = !transport_pause_i && (state_q == BRIDGE_SEND) && (response_index_q!=0 || publication_allowed_i);
    assign uart_quiet_o = tx_ready && state_q!=BRIDGE_DRAIN &&
        (state_q!=BRIDGE_SEND || (response_index_q==0 && !publication_allowed_i));
    assign tx_byte = (response_index_q == 0) ? response_byte0 :
                     (response_index_q == 1) ? response_byte1 :
                     (response_index_q == 2) ? response_byte2 :
                     (response_index_q == 3) ? response_byte3 :
                                                response_crc_q;

    task automatic prepare_response(
        input [7:0] kind,
        input [11:0] token
    );
        begin
            response_kind_q <= kind;
            response_token_q <= token;
            response_index_q <= 3'b0;
            // This is recomputed in BRIDGE_SEND after kind/token registers
            // have settled; the value here is intentionally overwritten.
            response_crc_q <= 8'b0;
            state_q <= BRIDGE_SEND;
        end
    endtask

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= BRIDGE_IDLE;
            request_index_q <= 3'b0;
            request_crc_q <= 8'b0;
            request_opcode_q <= 8'b0;
            request_token_low_q <= 8'b0;
            request_token_high_q <= 8'b0;
            command_q <= 2'b0;
            command_token_q <= 12'b0;
            response_kind_q <= 8'b0;
            response_token_q <= 12'b0;
            response_crc_q <= 8'b0;
            response_index_q <= 3'b0;
            clear_pending_q <= 1'b0;
            recovery_clear_q <= 1'b0;
        end else if (!transport_pause_i) begin
            if ((state_q == BRIDGE_IDLE ||
                 (state_q == BRIDGE_WAIT_RESULT && !clear_pending_q &&
                  !out_valid_i)) && rx_valid) begin
                case (request_index_q)
                    3'd0: begin
                        if (rx_byte == REQUEST_MAGIC) begin
                            request_crc_q <= crc8_next(8'h00, rx_byte);
                            request_index_q <= 3'd1;
                        end
                    end
                    3'd1: begin
                        request_opcode_q <= rx_byte;
                        request_crc_q <= crc8_next(request_crc_q, rx_byte);
                        request_index_q <= 3'd2;
                    end
                    3'd2: begin
                        request_token_low_q <= rx_byte;
                        request_crc_q <= crc8_next(request_crc_q, rx_byte);
                        request_index_q <= 3'd3;
                    end
                    3'd3: begin
                        request_token_high_q <= rx_byte;
                        request_crc_q <= crc8_next(request_crc_q, rx_byte);
                        request_index_q <= 3'd4;
                    end
                    3'd4: begin
                        request_index_q <= 3'd0;
                        if (state_q == BRIDGE_WAIT_RESULT) begin
                            // CLEAR remains available after a silent model
                            // fault. Other commands cannot overtake STEP.
                            if (!request_unknown &&
                                rx_byte == request_crc_q &&
                                request_opcode_q == OP_CLEAR &&
                                request_token_low_q == 8'b0 &&
                                request_token_high_q == 8'b0)
                                clear_pending_q <= 1'b1;
                        end else if (request_unknown ||
                            rx_byte != request_crc_q ||
                            request_token_high_q[7:4] != 4'b0 ||
                            request_opcode_q > OP_CLEAR) begin
                            prepare_response(8'hcf, 12'b0);
                        end else if (request_opcode_q == OP_APPEND &&
                                     {1'b0, request_token_high_q[3:0],
                                      request_token_low_q} >= VOCAB_SIZE) begin
                            prepare_response(8'hc0, 12'b0);
                        end else if (request_opcode_q != OP_APPEND &&
                                     {request_token_high_q[3:0],
                                      request_token_low_q} != 12'b0) begin
                            prepare_response(8'hc0 | request_opcode_q,
                                             12'b0);
                        end else begin
                            command_q <= request_opcode_q[1:0];
                            command_token_q <= {
                                request_token_high_q[3:0],
                                request_token_low_q
                            };
                            state_q <= BRIDGE_OFFER;
                        end
                    end
                    default: request_index_q <= 3'b0;
                endcase
            end

            case (state_q)
                BRIDGE_OFFER: begin
                    if (cmd_ready_i) begin
                        recovery_clear_q <= 1'b0;
                        if (command_q == OP_CLEAR[1:0])
                            clear_pending_q <= 1'b0;
                        if (command_q == OP_STEP[1:0])
                            state_q <= BRIDGE_WAIT_RESULT;
                        else if (command_q == OP_APPEND[1:0])
                            prepare_response(8'h80, 12'b0);
                        else
                            prepare_response(8'h82, 12'b0);
                    end else if (!recovery_clear_q) begin
                        prepare_response(8'hc0 | {6'b0, command_q}, 12'b0);
                    end
                end
                BRIDGE_WAIT_RESULT: begin
                    if (clear_pending_q && cmd_ready_i) begin
                        clear_pending_q <= 1'b0;
                        prepare_response(8'h82, 12'b0);
                    end else if (out_valid_i && publication_allowed_i) begin
                        prepare_response(8'h81, out_token_i);
                    end
                end
                BRIDGE_SEND: begin
                    // Delay CRC capture until kind/token have settled.
                    if (response_index_q == 0)
                        response_crc_q <= computed_response_crc;
                    if (tx_ready && tx_valid) begin
                        if (response_index_q == 3'd4)
                            state_q <= BRIDGE_DRAIN;
                        else
                            response_index_q <= response_index_q + 1'b1;
                    end
                end
                BRIDGE_DRAIN: begin
                    if (tx_ready) begin
                        if (clear_pending_q) begin
                            command_q <= OP_CLEAR[1:0];
                            command_token_q <= 12'b0;
                            recovery_clear_q <= 1'b1;
                            state_q <= BRIDGE_OFFER;
                        end else begin
                            state_q <= BRIDGE_IDLE;
                        end
                    end
                end
                default: begin end
            endcase
        end
    end
    // Predict exactly the old decoder's next-cycle CLEAR level from the
    // existing bridge transition. This is not a delayed or queued command.
    // The original state machine, CRC, rejection and recovery logic remain.
    (* syn_preserve = 1 *) logic clear_command_q;
    logic clear_command_next;
    wire received_clear_frame = rx_valid && (request_index_q == 3'd4) &&
        !request_unknown && (rx_byte == request_crc_q) &&
        (request_opcode_q == OP_CLEAR) && (request_token_low_q == 8'b0) &&
        (request_token_high_q == 8'b0);
    always_comb begin
        clear_command_next = 1'b0;
        case (state_q)
            BRIDGE_IDLE: begin
                if (received_clear_frame) clear_command_next = 1'b1;
            end
            BRIDGE_OFFER: begin
                if (cmd_ready_i) clear_command_next = 1'b0;
                else if (!recovery_clear_q) clear_command_next = 1'b0;
                else clear_command_next = (command_q == OP_CLEAR[1:0]);
            end
            BRIDGE_WAIT_RESULT: begin
                if (clear_pending_q && cmd_ready_i) clear_command_next = 1'b0;
                else if (out_valid_i) clear_command_next = 1'b0;
                else if (clear_pending_q) clear_command_next = 1'b1;
                else if (received_clear_frame) clear_command_next = 1'b1;
            end
            BRIDGE_DRAIN: begin
                if (tx_ready && clear_pending_q) clear_command_next = 1'b1;
            end
            default: begin end
        endcase
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) clear_command_q <= 1'b0;
        else if (transport_pause_i) clear_command_q <= 1'b0;
        else clear_command_q <= clear_command_next;
    end
    assign clear_command_o = clear_command_q && !transport_pause_i;

    // First byte accepted -> all five 10-bit bytes drain and bridge becomes
    // quiet within 5*(10*217)+4 inter-byte edges+1 bridge edge = 10855 clocks.
    // Reset/pause abort the obligation; the composition separately proves
    // that nonterminal authorization transport cannot pause a partial packet.
    logic spec_flight;
    logic [13:0] spec_elapsed;
    wire spec_first=tx_valid && tx_ready && response_index_q==0;
    wire [13:0] spec_rank=(state_q==BRIDGE_SEND && response_index_q!=0) ?
        (14'd5-14'(response_index_q))*14'd2171+14'(proof_tx_remaining)+14'd1 :
        state_q==BRIDGE_DRAIN ? 14'(proof_tx_remaining)+14'd1 : 14'd0;
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin spec_flight<=0;spec_elapsed<=0;end
        else if(transport_pause_i) begin spec_flight<=0;spec_elapsed<=0;end
        else if(spec_first) begin spec_flight<=1;spec_elapsed<=0;end
        else if(spec_flight) begin
            if(uart_quiet_o) spec_flight<=0;
            else spec_elapsed<=spec_elapsed+1'b1;
        end
    end
    always_comb if(rst_n) begin
        assert(state_q==BRIDGE_IDLE || state_q==BRIDGE_OFFER || state_q==BRIDGE_WAIT_RESULT ||
               state_q==BRIDGE_SEND || state_q==BRIDGE_DRAIN);
        if(state_q==BRIDGE_SEND) assert(response_index_q<=4);
        if(state_q==BRIDGE_DRAIN) assert(response_index_q==4);
    end
    always_comb if(rst_n && !transport_pause_i) begin
        if(spec_flight) begin
            assert(uart_quiet_o || state_q==BRIDGE_DRAIN ||
                   (state_q==BRIDGE_SEND && response_index_q>=1 && response_index_q<=4));
            assert(spec_elapsed+spec_rank==14'd10855);
            assert(spec_elapsed<=10855);
            if(!uart_quiet_o) assert(spec_rank>0);
            if(spec_elapsed==10855) assert(uart_quiet_o);
        end
    end

    // Only frame admission is gated by publication_allowed_i. Subsequent
    // bytes intentionally drain. The chip-level mux separately clamps token
    // serial output as soon as the lease fails/expires.
    always_comb begin
        if(out_ready_o) assert(publication_allowed_i && !transport_pause_i);
        if(tx_valid && tx_ready && response_index_q==0)
            assert(publication_allowed_i && !transport_pause_i);
        if(transport_pause_i) assert(!tx_valid && !out_ready_o && !cmd_valid_o);
        if(uart_quiet_o) begin
            assert(tx_ready);
            assert(state_q!=BRIDGE_DRAIN);
            if(state_q==BRIDGE_SEND) assert(response_index_q==0 && !publication_allowed_i);
        end
        if(!rst_n) assert(!cmd_valid_o && !out_ready_o);
    end
    logic publication_past=0;
    always_ff @(posedge clk) begin
        publication_past<=1;
        if(publication_past && rst_n && $past(rst_n)) begin
            if($past(state_q)==BRIDGE_SEND && $past(response_index_q)==0 &&
               !$past(publication_allowed_i)) assert(response_index_q==0);
        end
    end

 assign proof_flight_o=spec_flight; assign proof_first_o=spec_first; assign proof_quiet_o=uart_quiet_o;
 assign proof_elapsed_o=spec_elapsed; assign proof_rank_o=spec_rank;

endmodule

`default_nettype wire

`timescale 1ns/1ps
`default_nettype none

module fixed_uart_tx #(
    parameter integer CLKS_PER_BIT = 234
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       byte_valid_i,
    output wire       byte_ready_o,
    input  wire [7:0] byte_i,
    output wire       serial_o,
    output wire [11:0] proof_remaining_o
);
    localparam integer COUNTER_BITS = $clog2(CLKS_PER_BIT + 1);
    logic [COUNTER_BITS-1:0] counter_q;
    logic [3:0] bit_q;
    logic [9:0] shift_q;
    logic busy_q;

    initial begin
        if (CLKS_PER_BIT < 4)
            $fatal(1, "CLKS_PER_BIT must be at least four");
    end

    assign byte_ready_o = !busy_q;
    assign serial_o = busy_q ? shift_q[0] : 1'b1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter_q <= '0;
            bit_q <= '0;
            shift_q <= 10'h3ff;
            busy_q <= 1'b0;
        end else if (!busy_q) begin
            if (byte_valid_i) begin
                shift_q <= {1'b1, byte_i, 1'b0};
                counter_q <= COUNTER_BITS'(CLKS_PER_BIT - 1);
                bit_q <= 4'b0;
                busy_q <= 1'b1;
            end
        end else if (counter_q != 0) begin
            counter_q <= counter_q - 1'b1;
        end else if (bit_q == 4'd9) begin
            busy_q <= 1'b0;
        end else begin
            shift_q <= {1'b1, shift_q[9:1]};
            counter_q <= COUNTER_BITS'(CLKS_PER_BIT - 1);
            bit_q <= bit_q + 1'b1;
        end
    end
    assign proof_remaining_o=busy_q ?
        (12'd9-12'(bit_q))*12'(CLKS_PER_BIT)+12'(counter_q)+12'd1 : 12'd0;
    always_comb if(rst_n) begin
        assert(bit_q<=9);
        assert(counter_q<CLKS_PER_BIT);
        if(busy_q) assert(proof_remaining_o>0 && proof_remaining_o<=2170);
    end

endmodule

`default_nettype wire

`timescale 1ns/1ps
`default_nettype none

module fixed_uart_rx #(
    parameter integer CLKS_PER_BIT = 234
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       serial_i,
    output logic      byte_valid_o,
    output logic [7:0] byte_o
);
    localparam integer HALF_BIT = CLKS_PER_BIT / 2;
    localparam integer COUNTER_BITS = $clog2(CLKS_PER_BIT + 1);

    typedef enum logic [1:0] {RX_IDLE, RX_START, RX_DATA, RX_STOP} rx_state_t;
    rx_state_t state_q;
    logic [COUNTER_BITS-1:0] counter_q;
    logic [2:0] bit_q;
    logic [7:0] shift_q;
    (* async_reg = "true", syn_preserve = 1 *) logic serial_meta_q;
    (* async_reg = "true", syn_preserve = 1 *) logic serial_sync_q;

    initial begin
        if (CLKS_PER_BIT < 4)
            $fatal(1, "CLKS_PER_BIT must be at least four");
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= RX_IDLE;
            counter_q <= '0;
            bit_q <= '0;
            shift_q <= '0;
            byte_o <= '0;
            byte_valid_o <= 1'b0;
            serial_meta_q <= 1'b1;
            serial_sync_q <= 1'b1;
        end else begin
            serial_meta_q <= serial_i;
            serial_sync_q <= serial_meta_q;
            byte_valid_o <= 1'b0;
            case (state_q)
                RX_IDLE: begin
                    if (!serial_sync_q) begin
                        counter_q <= COUNTER_BITS'(HALF_BIT - 1);
                        state_q <= RX_START;
                    end
                end
                RX_START: begin
                    if (counter_q != 0) begin
                        counter_q <= counter_q - 1'b1;
                    end else if (!serial_sync_q) begin
                        counter_q <= COUNTER_BITS'(CLKS_PER_BIT - 1);
                        bit_q <= 3'b0;
                        state_q <= RX_DATA;
                    end else begin
                        state_q <= RX_IDLE;
                    end
                end
                RX_DATA: begin
                    if (counter_q != 0) begin
                        counter_q <= counter_q - 1'b1;
                    end else begin
                        shift_q[bit_q] <= serial_sync_q;
                        counter_q <= COUNTER_BITS'(CLKS_PER_BIT - 1);
                        if (bit_q == 3'd7)
                            state_q <= RX_STOP;
                        else
                            bit_q <= bit_q + 1'b1;
                    end
                end
                RX_STOP: begin
                    if (counter_q != 0) begin
                        counter_q <= counter_q - 1'b1;
                    end else begin
                        if (serial_sync_q) begin
                            byte_o <= shift_q;
                            byte_valid_o <= 1'b1;
                        end
                        state_q <= RX_IDLE;
                    end
                end
                default: state_q <= RX_IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire
