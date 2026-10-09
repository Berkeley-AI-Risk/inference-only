// Frozen Board1 context-2048 typed DDR application-domain boundary.
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

    localparam logic STATE_IDLE      = 1'b0;
    localparam logic STATE_WAIT_READ = 1'b1;

    logic state_q;
    logic fault_q;
    logic lock_seen_q;
    logic [1:0] read_kind_q;
    logic read_epoch_q;
    logic [3:0] read_row_word_q;
    logic offer_q;
    logic offer_reject_q;
    logic return_is_data_q;
    logic offer_write_q;
    logic offer_poison_q;
    logic [1:0] offer_kind_q;
    logic offer_epoch_q;
    logic [18:0] offer_address_q;
    logic [255:0] offer_write_data_q;
    logic [3:0] offer_row_word_q;
    logic return_valid_q;
    logic [1:0] return_kind_q;
    logic return_epoch_q;
    logic [255:0] return_data_q;
    logic return_fault_q;

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

    always_comb begin
        unexpected_endpoint_response =
            (state_q == STATE_IDLE) && (endpoint_rsp_valid_i === 1'b1);
        request_without_lock = (req_valid_i === 1'b1) &&
                               (model_locked_i !== 1'b1);
        policy_fault_now = (req_valid_i === 1'b1) &&
                           !request_descriptor_legal;
        endpoint_padding_fault_now =
            (state_q == STATE_WAIT_READ) &&
            (endpoint_rsp_valid_i === 1'b1) &&
            (read_kind_q == KIND_KV_READ) &&
            (read_row_word_q == 4'd8) &&
            (endpoint_rsp_data_i[255:16] != 240'd0);
        terminal_fault_now = fault_q || upstream_fault_i ||
                             (lock_seen_q && !model_locked_i) ||
                             unexpected_endpoint_response ||
                             request_without_lock || policy_fault_now ||
                             endpoint_padding_fault_now ||
                             simulation_x_fault;
    end

    // A request acquires a registered offer before reaching the endpoint.
    // reject=1 owns a local fault only and NEVER presents an endpoint command.
    // reject=0 begins presentation immediately after the capture edge; later
    // faults cannot revoke that ordinary ready/valid offer, only poison it.
    always_comb begin
        req_ready_o                    = 1'b0;
        rsp_valid_o                    = return_valid_q;
        rsp_kind_o                     = return_kind_q;
        rsp_epoch_o                    = return_epoch_q;
        rsp_data_o                     = (return_is_data_q && !return_fault_q) ?
                                         return_data_q : 256'd0;
        rsp_fault_o                    = return_fault_q;
        endpoint_req_valid_o           = 1'b0;
        endpoint_req_word_address_o    = 19'd0;
        endpoint_req_write_o           = 1'b0;
        endpoint_req_write_data_o      = 256'd0;
        endpoint_rsp_ready_o           = 1'b0;

        if (state_q == STATE_WAIT_READ) begin
            endpoint_rsp_ready_o = !return_valid_q;
        end else if (offer_q) begin
            if (offer_reject_q) begin
                req_ready_o = 1'b1;
            end else begin
                endpoint_req_valid_o        = 1'b1;
                endpoint_req_word_address_o = offer_address_q;
                endpoint_req_write_o        = offer_write_q;
                endpoint_req_write_data_o   = offer_write_data_q;
                req_ready_o                 = (endpoint_req_ready_i === 1'b1);
            end
            if (unexpected_endpoint_response)
                endpoint_rsp_ready_o = 1'b1;
        end else if (unexpected_endpoint_response) begin
            endpoint_rsp_ready_o = 1'b1;
        end
    end

    assign endpoint_request_handshake = endpoint_req_valid_o &&
                                        (endpoint_req_ready_i === 1'b1);
    assign endpoint_response_handshake =
                                         (endpoint_rsp_valid_i === 1'b1) &&
                                         endpoint_rsp_ready_o;
    assign fail_closed_o = terminal_fault_now;
    assign busy_o = (state_q != STATE_IDLE) || offer_q || req_valid_i ||
                    return_valid_q;

    // Payload registers are private, resetless, and unpublished until their
    // separately reset valid/type/fault state grants use. No legality check
    // drives a 256-bit payload clock enable. Rejected data stays unpublished.
    always_ff @(posedge clk_i) begin
        if (reset_n_i && (state_q == STATE_IDLE) && !offer_q &&
            (req_valid_i === 1'b1) && !return_valid_q)
            offer_write_data_q <= req_write_data_i;
        if (reset_n_i && (state_q == STATE_WAIT_READ) &&
            endpoint_response_handshake)
            return_data_q <= endpoint_rsp_data_i;
    end

    always_ff @(posedge clk_i or negedge reset_n_i) begin
        if (!reset_n_i) begin
            state_q          <= STATE_IDLE;
            fault_q          <= 1'b0;
            lock_seen_q      <= 1'b0;
            read_kind_q      <= KIND_MODEL_READ;
            read_epoch_q     <= 1'b0;
            read_row_word_q  <= 4'd0;
            offer_q          <= 1'b0;
            offer_reject_q   <= 1'b0;
            offer_write_q    <= 1'b0;
            offer_poison_q   <= 1'b0;
            offer_kind_q     <= KIND_MODEL_READ;
            offer_epoch_q    <= 1'b0;
            offer_address_q  <= 19'd0;
            offer_row_word_q <= 4'd0;
            return_valid_q   <= 1'b0;
            return_kind_q    <= KIND_MODEL_READ;
            return_epoch_q   <= 1'b0;
            return_is_data_q <= 1'b0;
            return_fault_q   <= 1'b0;
        end else begin
            if (return_valid_q && (rsp_ready_i === 1'b1))
                return_valid_q <= 1'b0;
            if (model_locked_i)
                lock_seen_q <= 1'b1;
            if (offer_q && terminal_fault_now)
                offer_poison_q <= 1'b1;
            if (upstream_fault_i ||
                (lock_seen_q && !model_locked_i) ||
                unexpected_endpoint_response || request_without_lock ||
                policy_fault_now || simulation_x_fault ||
                endpoint_padding_fault_now ||
                ((state_q == STATE_WAIT_READ) &&
                 (endpoint_rsp_valid_i === 1'b1) &&
                 (endpoint_rsp_error_i !== 1'b0)))
                fault_q <= 1'b1;

            if (state_q == STATE_IDLE) begin
                if (offer_q) begin
                    if (offer_reject_q || endpoint_request_handshake) begin
                        offer_q <= 1'b0;
                        if (offer_reject_q || offer_write_q) begin
                            return_valid_q   <= 1'b1;
                            return_kind_q    <= offer_kind_q;
                            return_epoch_q   <= offer_epoch_q;
                            return_is_data_q <= 1'b0;
                            return_fault_q   <= offer_reject_q ||
                                                terminal_fault_now ||
                                                offer_poison_q;
                        end else begin
                            state_q         <= STATE_WAIT_READ;
                            read_kind_q     <= offer_kind_q;
                            read_epoch_q    <= offer_epoch_q;
                            read_row_word_q <= offer_row_word_q;
                        end
                    end
                end else if ((req_valid_i === 1'b1) && !return_valid_q) begin
                    // This is the only publication decision. The complete
                    // descriptor, lock, endpoint and upstream checks are
                    // evaluated before the offer can become visible.
                    offer_q          <= 1'b1;
                    offer_reject_q   <= terminal_fault_now;
                    offer_poison_q   <= terminal_fault_now;
                    offer_write_q    <= (req_kind_i == KIND_KV_WRITE);
                    offer_kind_q     <= req_kind_i;
                    offer_epoch_q    <= req_epoch_i;
                    offer_address_q  <= (req_kind_i == KIND_MODEL_READ) ?
                                        req_model_word_i : kv_recomputed_address;
                    offer_row_word_q <= req_row_word_i;
                end
            end else if (endpoint_response_handshake) begin
                state_q          <= STATE_IDLE;
                return_valid_q   <= 1'b1;
                return_kind_q    <= read_kind_q;
                return_epoch_q   <= read_epoch_q;
                return_is_data_q <= 1'b1;
                return_fault_q   <= terminal_fault_now || endpoint_rsp_error_i;
            end
        end
    end

`ifdef FORMAL
    always_ff @(posedge clk_i) begin
        if (reset_n_i && endpoint_req_valid_o) begin
            assert(!fail_closed_o || offer_q);
            assert(req_valid_i);
            assert(request_descriptor_legal);
            assert((endpoint_req_word_address_o < MODEL_WORDS) ||
                   ((endpoint_req_word_address_o >= KV_BASE_WORD) &&
                    (endpoint_req_word_address_o < SCRATCH_END_WORD)));
            assert(!((endpoint_req_word_address_o >= MODEL_WORDS) &&
                     (endpoint_req_word_address_o < KV_BASE_WORD)));
            if (endpoint_req_write_o) begin
                assert(req_kind_i == KIND_KV_WRITE);
                assert(endpoint_req_word_address_o == kv_recomputed_address);
                if (req_row_word_i == 4'd8)
                    assert(endpoint_req_write_data_o[255:16] == 240'd0);
            end else begin
                assert((req_kind_i == KIND_MODEL_READ) ||
                       (req_kind_i == KIND_KV_READ));
                if (req_kind_i == KIND_KV_READ)
                    assert(endpoint_req_word_address_o == kv_recomputed_address);
            end
        end
        if ($past(reset_n_i) && $past(fault_q))
            assert(fault_q);
        if (reset_n_i && return_valid_q &&
            (return_kind_q == KIND_KV_READ) &&
            (read_row_word_q == 4'd8) && !return_fault_q)
            assert(return_data_q[255:16] == 240'd0);
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
