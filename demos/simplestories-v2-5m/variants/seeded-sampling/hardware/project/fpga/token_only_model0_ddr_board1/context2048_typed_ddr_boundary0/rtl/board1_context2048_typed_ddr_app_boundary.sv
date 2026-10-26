`timescale 1ns/1ps
`default_nettype none
// Draft pipelined Board1 context-2048 typed DDR application boundary.
//
// This module is deliberately independent of the 25 MHz source-side address
// mapper. A parallel arithmetic certificate proves that the proposed
// shadow equals the independently specified coordinate-derived address.
// Only a certified proposal can become a new private endpoint offer.
module board1_context2048_typed_ddr_app_boundary (
    input  wire         clk_i,
    input  wire         reset_n_i,
    input  wire         model_locked_i,
    input  wire         upstream_fault_i,

    input  wire         req_valid_i,
    output logic        req_ready_o,
    input  wire [1:0]   req_kind_i,
    input  wire         req_epoch_i,
    input  wire [18:0]  req_model_word_i,
    input  wire [2:0]   req_layer_i,
    input  wire [11:0]  req_position_i,
    input  wire [1:0]   req_head_i,
    input  wire [3:0]   req_row_word_i,
    input  wire [18:0]  req_shadow_address_i,
    input  wire [255:0] req_write_data_i,

    output logic        rsp_valid_o,
    input  wire         rsp_ready_i,
    output logic [1:0]  rsp_kind_o,
    output logic        rsp_epoch_o,
    output logic [255:0] rsp_data_o,
    output logic        rsp_fault_o,

    output logic        endpoint_req_valid_o,
    input  wire         endpoint_req_ready_i,
    output logic [18:0] endpoint_req_word_address_o,
    output logic        endpoint_req_write_o,
    output logic [255:0] endpoint_req_write_data_o,

    input  wire         endpoint_rsp_valid_i,
    output logic        endpoint_rsp_ready_o,
    input  wire [255:0] endpoint_rsp_data_i,
    input  wire         endpoint_rsp_error_i,

    output logic        busy_o,
    output logic        fail_closed_o
);
    localparam logic [1:0] KIND_MODEL_READ = 2'b00;
    localparam logic [1:0] KIND_KV_WRITE   = 2'b01;
    localparam logic [1:0] KIND_KV_READ    = 2'b10;

    localparam logic [18:0] MODEL_WORDS       = 19'd227062;
    localparam logic [18:0] KV_BASE_WORD      = 19'd227072;
    localparam logic [18:0] SCRATCH_END_WORD  = 19'd448256;

    logic fault_q, lock_seen_q;
    logic offer_q, offer_write_q, offer_poison_q;
    logic [18:0] offer_address_q;
    logic [255:0] offer_write_data_q;

    logic [13:0] kv_layer_position;
    logic [14:0] kv_row;
    // The parallel certificate independently validates the exact
    // coordinate-derived address before any new endpoint offer.
    logic [18:0] kv_recomputed_address;
    wire kv_address_matches;
    board1_fixed_kv_shadow_match u_fixed_address (
        .row_i(kv_row), .word_i(req_row_word_i),
        .shadow_i(req_shadow_address_i), .matches_o(kv_address_matches)
    );
    always_comb begin
        kv_recomputed_address = req_shadow_address_i;
        // Preserve inactive and X/Z payload behavior in simulation.
        // synthesis translate_off
        if ($isunknown({kv_row, req_row_word_i, req_shadow_address_i}))
            kv_recomputed_address = 19'd227072 +
                (({4'd0, kv_row} * 19'd9) + {15'd0, req_row_word_i});
        // synthesis translate_on
    end
    logic kv_fields_in_range;
    logic kv_recomputed_in_range;
    logic model_descriptor_legal;
    logic kv_write_descriptor_legal;
    logic kv_read_descriptor_legal;
    logic request_descriptor_legal;
    logic request_is_write;
    logic request_is_read;
    logic simulation_x_fault;
    logic unexpected_endpoint_response;
    logic request_without_lock;
    logic policy_fault_now;
    logic endpoint_padding_fault_now;
    logic terminal_fault_now;
    logic endpoint_request_handshake;
    logic endpoint_response_handshake;

    // Deliberately recomputed from typed coordinates in this clock domain.
    // Position bit 11 is rejected below and is not allowed to alias.
    always_comb begin
        kv_layer_position      = ({11'd0, req_layer_i} << 11) +
                                 {3'd0, req_position_i[10:0]};
        kv_row                 = (kv_layer_position << 1) +
                                 {13'd0, req_head_i[0]};
    end

    always_comb begin
        kv_fields_in_range = (req_layer_i < 3'd6) &&
                             (req_position_i < 12'd2048) &&
                             (req_head_i < 2'd2) &&
                             (req_row_word_i < 4'd9);
        kv_recomputed_in_range = (kv_recomputed_address >= KV_BASE_WORD) &&
                                 (kv_recomputed_address < SCRATCH_END_WORD);

        model_descriptor_legal =
            (req_kind_i == KIND_MODEL_READ) &&
            (req_model_word_i < MODEL_WORDS) &&
            (req_layer_i == 3'd0) &&
            (req_position_i == 12'd0) &&
            (req_head_i == 2'd0) &&
            (req_row_word_i == 4'd0) &&
            (req_shadow_address_i == 19'd0) &&
            (req_write_data_i == 256'd0);

        kv_write_descriptor_legal =
            (req_kind_i == KIND_KV_WRITE) &&
            (req_model_word_i == 19'd0) &&
            kv_fields_in_range &&
            kv_recomputed_in_range &&
            kv_address_matches &&
            ((req_row_word_i != 4'd8) ||
             (req_write_data_i[255:16] == 240'd0));

        kv_read_descriptor_legal =
            (req_kind_i == KIND_KV_READ) &&
            (req_model_word_i == 19'd0) &&
            kv_fields_in_range &&
            kv_recomputed_in_range &&
            kv_address_matches &&
            (req_write_data_i == 256'd0);

        request_descriptor_legal = model_descriptor_legal ||
                                   kv_write_descriptor_legal ||
                                   kv_read_descriptor_legal;
        request_is_write = kv_write_descriptor_legal;
        request_is_read  = model_descriptor_legal || kv_read_descriptor_legal;
    end

`ifndef SYNTHESIS
`ifndef FORMAL
    always_comb begin
        simulation_x_fault = 1'b0;
        if ((^{reset_n_i, model_locked_i, upstream_fault_i,
               req_valid_i, rsp_ready_i, endpoint_req_ready_i,
               endpoint_rsp_valid_i}) === 1'bx) begin
            simulation_x_fault = 1'b1;
        end
        if ((req_valid_i === 1'b1) &&
            ((^{req_kind_i, req_epoch_i, req_model_word_i,
                req_layer_i, req_position_i, req_head_i,
                req_row_word_i, req_shadow_address_i,
                req_write_data_i}) === 1'bx)) begin
            simulation_x_fault = 1'b1;
        end
        if ((endpoint_rsp_valid_i === 1'b1) &&
            ((^{endpoint_rsp_data_i, endpoint_rsp_error_i}) === 1'bx)) begin
            simulation_x_fault = 1'b1;
        end
    end
`else
    always_comb simulation_x_fault = 1'b0;
`endif
`else
    always_comb simulation_x_fault = 1'b0;
`endif

    // Eight end-to-end reserved slots. A slot is allocated BEFORE a request
    // can reach the endpoint and released only when its typed return leaves.
    // Thus endpoint returns never depend on downstream return FIFO readiness.
    localparam integer CREDITS = 8;
    logic [3:0] reserved_q, unissued_q, read_count_q;
    logic [2:0] head_q, tail_q, issue_q, read_head_q, read_tail_q;
    logic [1:0] slot_kind_q [0:CREDITS-1];
    logic slot_epoch_q [0:CREDITS-1];
    logic [3:0] slot_word_q [0:CREDITS-1];
    logic [18:0] slot_address_q [0:CREDITS-1];
    logic [255:0] slot_data_q [0:CREDITS-1];
    logic slot_reject_q [0:CREDITS-1];
    logic slot_done_q [0:CREDITS-1];
    logic slot_fault_q [0:CREDITS-1];
    logic [2:0] read_slot_q [0:CREDITS-1];
    logic [2:0] offer_slot_q;
    wire [2:0] response_slot = read_slot_q[read_head_q];
    wire request_take = req_valid_i && req_ready_o;
    wire response_take = rsp_valid_o && rsp_ready_i;
    wire owned_return = endpoint_response_handshake && read_count_q != 0;
    wire read_issue = endpoint_request_handshake && !offer_write_q;
    wire reject_issue = !offer_q && unissued_q != 0 &&
        (slot_reject_q[issue_q] || terminal_fault_now);
    wire issue_advance = reject_issue || endpoint_request_handshake;
    integer reset_slot;

    always_comb begin
        unexpected_endpoint_response = endpoint_rsp_valid_i && read_count_q == 0;
        request_without_lock = req_valid_i && !model_locked_i;
        policy_fault_now = req_valid_i && !request_descriptor_legal;
        endpoint_padding_fault_now = endpoint_rsp_valid_i && read_count_q != 0 &&
            slot_kind_q[response_slot] == KIND_KV_READ &&
            slot_word_q[response_slot] == 4'd8 &&
            endpoint_rsp_data_i[255:16] != 0;
        terminal_fault_now = fault_q || upstream_fault_i ||
            (lock_seen_q && !model_locked_i) || unexpected_endpoint_response ||
            request_without_lock || policy_fault_now || endpoint_padding_fault_now ||
            simulation_x_fault || (endpoint_rsp_valid_i && endpoint_rsp_error_i);

        // Even a terminal/rejected descriptor owns a fault response. Accepted
        // FIFO work drains through these slots instead of being flushed.
        req_ready_o = reset_n_i && reserved_q < 4'd8;
        rsp_valid_o = reset_n_i && reserved_q != 0 && slot_done_q[head_q];
        rsp_kind_o = slot_kind_q[head_q];
        rsp_epoch_o = slot_epoch_q[head_q];
        rsp_fault_o = slot_fault_q[head_q] || terminal_fault_now;
        rsp_data_o = !rsp_fault_o && rsp_kind_o != KIND_KV_WRITE ?
                     slot_data_q[head_q] : 256'd0;

        // Once published, an unaccepted endpoint offer remains stable even
        // after CLEAR (which is an epoch change upstream) or a terminal event.
        // Later faults poison its eventual response; they cannot revoke VALID.
        endpoint_req_valid_o = reset_n_i && offer_q;
        endpoint_req_word_address_o = offer_address_q;
        endpoint_req_write_o = offer_write_q;
        endpoint_req_write_data_o = offer_write_data_q;
        endpoint_rsp_ready_o = reset_n_i; // Every owned return has reserved storage.
    end
    assign endpoint_request_handshake = endpoint_req_valid_o && endpoint_req_ready_i;
    assign endpoint_response_handshake = endpoint_rsp_valid_i && endpoint_rsp_ready_o;
    assign fail_closed_o = reset_n_i && terminal_fault_now;
    assign busy_o = reserved_q != 0 || offer_q || req_valid_i || read_count_q != 0;

    // Payload is resetless. The reservation/done bits are the only authority
    // to expose it; every healthy completion writes data before publication.
    always_ff @(posedge clk_i) begin
        if (request_take) begin
            slot_address_q[tail_q] <= req_kind_i == KIND_MODEL_READ ?
                                     req_model_word_i : kv_recomputed_address;
            slot_data_q[tail_q] <= req_write_data_i;
        end
        if (!offer_q && unissued_q != 0 && !reject_issue) begin
            offer_address_q <= slot_address_q[issue_q];
            offer_write_data_q <= slot_data_q[issue_q];
        end
        if (owned_return) slot_data_q[response_slot] <= endpoint_rsp_data_i;
        if (read_issue) read_slot_q[read_tail_q] <= offer_slot_q;
    end

    always_ff @(posedge clk_i or negedge reset_n_i) begin
        if (!reset_n_i) begin
            fault_q <= 0; lock_seen_q <= 0;
            reserved_q <= 0; unissued_q <= 0; read_count_q <= 0;
            head_q <= 0; tail_q <= 0; issue_q <= 0;
            read_head_q <= 0; read_tail_q <= 0;
            offer_q <= 0; offer_poison_q <= 0; offer_write_q <= 0;
            offer_slot_q <= 0;
            for (reset_slot=0; reset_slot<CREDITS; reset_slot=reset_slot+1) begin
                slot_done_q[reset_slot] <= 0;
                slot_fault_q[reset_slot] <= 0;
                slot_reject_q[reset_slot] <= 0;
                slot_kind_q[reset_slot] <= KIND_MODEL_READ;
                slot_epoch_q[reset_slot] <= 0;
                slot_word_q[reset_slot] <= 0;
            end
        end else begin
            if (model_locked_i) lock_seen_q <= 1;
            if (terminal_fault_now) fault_q <= 1;
            case ({request_take,response_take})
                2'b10: reserved_q <= reserved_q + 4'd1;
                2'b01: reserved_q <= reserved_q - 4'd1;
                default: ;
            endcase
            case ({request_take,issue_advance})
                2'b10: unissued_q <= unissued_q + 4'd1;
                2'b01: unissued_q <= unissued_q - 4'd1;
                default: ;
            endcase
            if (request_take) begin
                slot_kind_q[tail_q] <= req_kind_i;
                slot_epoch_q[tail_q] <= req_epoch_i;
                slot_word_q[tail_q] <= req_row_word_i;
                slot_reject_q[tail_q] <= terminal_fault_now;
                slot_fault_q[tail_q] <= terminal_fault_now;
                slot_done_q[tail_q] <= 0;
                tail_q <= tail_q + 3'd1;
            end
            if (response_take) begin
                slot_done_q[head_q] <= 0;
                head_q <= head_q + 3'd1;
            end
            if (reject_issue) begin
                slot_done_q[issue_q] <= 1;
                slot_fault_q[issue_q] <= 1;
            end
            if (issue_advance) issue_q <= issue_q + 3'd1;
            if (!offer_q && unissued_q != 0 && !reject_issue) begin
                offer_q <= 1;
                offer_slot_q <= issue_q;
                offer_write_q <= slot_kind_q[issue_q] == KIND_KV_WRITE;
                offer_poison_q <= 0;
            end
            if (offer_q && terminal_fault_now) offer_poison_q <= 1;
            if (endpoint_request_handshake) begin
                offer_q <= 0;
                if (offer_write_q) begin
                    slot_done_q[offer_slot_q] <= 1;
                    slot_fault_q[offer_slot_q] <= terminal_fault_now || offer_poison_q;
                end
            end
            if (read_issue) read_tail_q <= read_tail_q + 3'd1;
            if (owned_return) begin
                slot_done_q[response_slot] <= 1;
                slot_fault_q[response_slot] <= terminal_fault_now || endpoint_rsp_error_i;
                read_head_q <= read_head_q + 3'd1;
            end
            case ({read_issue,owned_return})
                2'b10: read_count_q <= read_count_q + 4'd1;
                2'b01: read_count_q <= read_count_q - 4'd1;
                default: ;
            endcase
        end
    end
`ifdef FORMAL
    always_ff @(posedge clk_i) if (reset_n_i) begin
        assert(reserved_q <= CREDITS);
        assert(unissued_q <= reserved_q);
        assert(read_count_q <= reserved_q);
        if (endpoint_req_valid_o) begin
            assert(!slot_reject_q[offer_slot_q]);
            assert(endpoint_req_word_address_o < MODEL_WORDS ||
                  (endpoint_req_word_address_o >= KV_BASE_WORD && endpoint_req_word_address_o < SCRATCH_END_WORD));
            if (endpoint_req_write_o && slot_word_q[offer_slot_q] == 8)
                assert(endpoint_req_write_data_o[255:16] == 0);
        end
        if (rsp_valid_o && rsp_kind_o == KIND_KV_READ &&
            slot_word_q[head_q] == 8 && !rsp_fault_o)
            assert(rsp_data_o[255:16] == 0);
        if ($past(reset_n_i) && $past(fault_q)) assert(fault_q);
    end
`endif
endmodule

`timescale 1ns/1ps
`default_nettype none
// Fixed private K/V address geometry, not an exposed arithmetic service.
// address = 227072 + 9*row + word. Since the base's low four bits are zero,
// base+word is concatenation even for invalid word values 9..15. Compress the
// three remaining operands without carry propagation, then add once.
module board1_fixed_kv_word_address (
    input wire [14:0] row_i,
    input wire [3:0] word_i,
    output logic [18:0] address_o
);
    localparam [18:0] BASE = 19'd227072;
    wire [18:0] a = {1'b0, row_i, 3'b000};
    wire [18:0] b = {4'b0000, row_i};
    wire [18:0] c = {BASE[18:4], word_i};
    (* syn_keep = 1 *) wire [18:0] sum_bits = a ^ b ^ c;
    (* syn_keep = 1 *) wire [18:0] carry_bits = ((a & b) | (a & c) | (b & c)) << 1;
    always_comb begin
        address_o = sum_bits + carry_bits;
        // Preserve the predecessor's arithmetic-X propagation in simulation,
        // including -DSYNTHESIS simulation. This is not hardware X detection.
        // synthesis translate_off
        if ($isunknown(row_i) || $isunknown(word_i))
            address_o = BASE + ((row_i * 19'd9) + {15'd0, word_i});
        // synthesis translate_on
    end
endmodule
`default_nettype wire

`timescale 1ns/1ps
`default_nettype none

// Exact parallel certificate of shadow == (227072 + 9*row + word) mod 2^19.
// This is a private fixed-address validator, not programmable arithmetic.
module board1_fixed_kv_shadow_match (
    input wire [14:0] row_i,
    input wire [3:0] word_i,
    input wire [18:0] shadow_i,
    output logic matches_o
);
    localparam [18:0] BASE = 19'd227072;
    wire [18:0] a = {1'b0, row_i, 3'b000};
    wire [18:0] b = {4'b0000, row_i};
    wire [18:0] c = {BASE[18:4], word_i};
    wire [18:0] u = a ^ b ^ c;
    wire [18:0] v = ((a & b) | (a & c) | (b & c)) << 1;
    wire [18:0] propagate = u ^ v;
    // If the proposed sum is correct, its bits reveal every carry-in.
    wire [18:0] proposed_carry = shadow_i ^ propagate;
    // Check each revealed carry against its predecessor column locally.
    wire [18:0] generated_carry = (u & v) | (propagate & ~shadow_i);
    always_comb begin
        matches_o = !proposed_carry[0] &&
                    (proposed_carry[18:1] == generated_carry[17:0]);
        // Binary hardware has no X/Z. Preserve the predecessor's equality
        // semantics in ordinary AND -DSYNTHESIS four-state simulation.
        // synthesis translate_off
        if ($isunknown({row_i, word_i, shadow_i}))
            matches_o = (shadow_i ==
                (BASE + (({4'd0, row_i} * 19'd9) + {15'd0, word_i})));
        // synthesis translate_on
    end
endmodule
`default_nettype wire
