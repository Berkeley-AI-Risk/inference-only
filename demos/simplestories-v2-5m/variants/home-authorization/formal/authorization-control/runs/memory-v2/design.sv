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
    // Universally quantified arbitrary signature byte. The real synchronous
    // 1292-byte RAM is retained; no replacement memory model is assumed.
    (* anyconst *) logic [10:0] spec_watch;
    logic spec_initial=1;
    always_ff @(posedge clk) spec_initial<=0;
    always_comb if(spec_initial) assume(!reset_n);
    logic spec_written;
    logic [7:0] spec_value;
    always_comb assume(spec_watch<1292);
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin spec_written<=0;spec_value<=0;end
        else begin
            if(state_q==SEND && request_ready_i && index_q==127) spec_written<=0;
            if(state_q==RECEIVE && grant_valid_i && grant_ready_o && index_q==spec_watch+128) begin
                spec_written<=1;spec_value<=grant_byte_i;
            end
        end
    end
    always_comb if(reset_n) begin
        assert(state_q==COLLECT || state_q==SEND || state_q==RECEIVE || state_q==ARM ||
               state_q==ARM_WAIT || state_q==START || state_q==VERIFY || state_q==RUN || state_q==FAIL);
        if(fault_q) assert(state_q==FAIL);
        if(state_q==SEND) assert(index_q<=127);
        if(state_q==RECEIVE) begin
            assert(index_q<=1419);
            if(index_q>spec_watch+128) assert(spec_written);
        end
        if(spec_written) assert(signature_mem[spec_watch]==spec_value);
        if(state_q==ARM || state_q==ARM_WAIT || state_q==START || state_q==VERIFY || state_q==RUN)
            assert(spec_written);
        if((state_q==ARM_WAIT || state_q==START || state_q==VERIFY || state_q==RUN) &&
           signature_ready && signature_address==spec_watch)
            assert(shared_signature_byte_o==spec_value);
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
