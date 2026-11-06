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
    // This is the selected top-level permit register / mux and selected
    // runtime reset release chain, copied byte-for-byte by the runner.
    wire core_clk=clk, core_reset_n=reset_n;
    wire home_failed=failed_o, home_accepted=new_lease_o;
    wire home_enabled=inference_enabled_o, home_request_valid=request_valid_o;
    (* anyseq *) wire home_transport_fault, token_uart_quiet, home_uart_tx, token_uart_tx;
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
    wire token_reset_n=1'b1;
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
    (* anyseq *) wire proof_model_valid,proof_kv_valid,proof_write,proof_ready,proof_rsp_valid,proof_rsp_error;
    (* anyseq *) wire [18:0] proof_model_word,proof_kv_word;
    (* anyseq *) wire [255:0] proof_data;
    wire proof_raw_valid,proof_model_ready,proof_kv_ready;
    board1_private_shared_ddr_arbiter u_actual_runtime_gate (
        .clk(clk),.reset_n(app_runtime_reset_n),
        .model_locked_i(admitted_root_valid_i),.upstream_fault_i(model_fault_i),
        .model_req_valid_i(proof_model_valid),.model_req_word_i(proof_model_word),
        .model_req_ready_o(proof_model_ready),
        .kv_req_valid_i(proof_kv_valid),.kv_req_word_i(proof_kv_word),
        .kv_req_write_i(proof_write),.kv_req_data_i(proof_data),.kv_req_ready_o(proof_kv_ready),
        .kv_rsp_ready_i(proof_ready),.raw_req_valid_o(proof_raw_valid),
        .raw_req_ready_i(proof_ready),.raw_rsp_valid_i(proof_rsp_valid),
        .raw_rsp_error_i(proof_rsp_error),.raw_rsp_data_i(proof_data));
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
