`timescale 1ns/1ps
`default_nettype none

// Correctness-first typed external-DDR K/V cache controller for the fixed
// context-2048 successor.  A semantic row is always one KV head:
//   64 signed-int16 K + 64 signed-int16 V + signed-int8 K/V exponents
//   = 2064 bits, packed into nine 256-bit words with 240 fixed zero bits.
// Two separately addressed head rows are staged together and become visible
// only after all eighteen typed writes complete and an exact atomic commit.
// No caller supplies a physical address, direction, or generic write enable.
// Unlike atomic_kv0's same-clock row-adapter seam, this connected successor
// terminates directly on the frozen typed DDR capability boundary: writes and
// reads retain layer/position/head/row-word descriptors, and the boundary
// independently reconstructs and checks the shadow address.
module board1_context2048_atomic_kv_typed (
    input  wire                     clk,
    input  wire                     reset_n,
    input  wire                     clear_i,
    input  wire                     model_locked_i,
    input  wire                     upstream_fault_i,
    input  wire                     endpoint_fault_i,

    // Fixed population role.  Coordinates 0..63 populate head 0 and
    // coordinates 64..127 populate head 1.
    input  wire                     stage_begin_valid_i,
    output logic                    stage_begin_ready_o,
    input  wire  [2:0]              stage_layer_i,
    input  wire  [11:0]             stage_position_i,
    input  wire  signed [15:0]      stage_key_exponents_i,
    input  wire  signed [15:0]      stage_value_exponents_i,
    input  wire                     stage_payload_valid_i,
    output logic                    stage_payload_ready_o,
    input  wire  [6:0]              stage_coordinate_i,
    input  wire  signed [15:0]      stage_key_i,
    input  wire  signed [15:0]      stage_value_i,
    input  wire                     stage_last_i,
    output logic                    pending_complete_o,

    // Exact descriptor commit.  Publication is a metadata operation: both
    // head rows have already reached DDR before this can become ready.
    input  wire                     commit_valid_i,
    output logic                    commit_ready_o,
    input  wire  [2:0]              commit_layer_i,
    input  wire  [11:0]             commit_position_i,

    // Fixed attention role.  Request kind is semantic, never a DDR direction:
    // 00 full K/V, 01 K only, 10 V only, 11 reserved/fault.
    input  wire                     attention_req_valid_i,
    output logic                    attention_req_ready_o,
    input  wire  [1:0]              attention_req_kind_i,
    input  wire  [2:0]              attention_layer_i,
    input  wire  [11:0]             attention_position_i,
    input  wire  [1:0]              attention_kv_head_i,
    output logic                    attention_rsp_valid_o,
    input  wire                     attention_rsp_ready_i,
    output logic [1:0]              attention_rsp_kind_o,
    output logic [1023:0]           attention_rsp_key_vector_o,
    output logic signed [7:0]       attention_rsp_key_exponent_o,
    output logic [1023:0]           attention_rsp_value_vector_o,
    output logic signed [7:0]       attention_rsp_value_exponent_o,
    output logic                    attention_rsp_fault_o,
    output logic                    attention_rsp_from_pending_o,

    // Integration-private typed DDR capabilities.  Direction is fixed by
    // which channel is asserted, not supplied as data by the semantic caller.
    output logic                    kv_write_req_valid_o,
    input  wire                     kv_write_req_ready_i,
    output logic [2:0]              kv_write_req_layer_o,
    output logic [11:0]             kv_write_req_position_o,
    output logic [1:0]              kv_write_req_head_o,
    output logic [3:0]              kv_write_req_row_word_o,
    output logic [18:0]             kv_write_req_shadow_address_o,
    output logic [255:0]            kv_write_req_data_o,
    input  wire                     kv_write_cpl_valid_i,
    output logic                    kv_write_cpl_ready_o,
    input  wire                     kv_write_cpl_fault_i,

    output logic                    kv_read_req_valid_o,
    input  wire                     kv_read_req_ready_i,
    output logic [2:0]              kv_read_req_layer_o,
    output logic [11:0]             kv_read_req_position_o,
    output logic [1:0]              kv_read_req_head_o,
    output logic [3:0]              kv_read_req_row_word_o,
    output logic [18:0]             kv_read_req_shadow_address_o,
    input  wire                     kv_read_rsp_valid_i,
    output logic                    kv_read_rsp_ready_o,
    input  wire  [255:0]            kv_read_rsp_data_i,
    input  wire                     kv_read_rsp_fault_i,

    output logic [71:0]             committed_prefixes_o,
    output logic                    busy_o,
    output logic                    fail_closed_o
);
    localparam logic [1:0] REQ_FULL_KV = 2'b00;
    localparam logic [1:0] REQ_KEY_ONLY = 2'b01;
    localparam logic [1:0] REQ_VALUE_ONLY = 2'b10;

    localparam logic [3:0] ST_IDLE       = 4'd0;
    localparam logic [3:0] ST_STAGE      = 4'd1;
    localparam logic [3:0] ST_WRITE_REQ  = 4'd2;
    localparam logic [3:0] ST_WRITE_WAIT = 4'd3;
    localparam logic [3:0] ST_PENDING    = 4'd4;
    localparam logic [3:0] ST_READ_REQ   = 4'd5;
    localparam logic [3:0] ST_READ_WAIT  = 4'd6;
    localparam logic [3:0] ST_RESPONSE   = 4'd7;

    logic [3:0] state_q;
    logic [11:0] committed_prefix_q [0:5];
    logic [2:0] pending_layer_q;
    logic [11:0] pending_position_q;
    logic signed [15:0] pending_key_exponents_q;
    logic signed [15:0] pending_value_exponents_q;
    logic [6:0] expected_coordinate_q;
    logic pending_persisted_q;

    // Payload registers deliberately have no reset.  Resettable reachability
    // metadata is cleared before any row can be observed, and a legal stage
    // overwrites every coordinate before publication.
    logic [1023:0] staged_key_head0_q;
    logic [1023:0] staged_key_head1_q;
    logic [1023:0] staged_value_head0_q;
    logic [1023:0] staged_value_head1_q;
    logic [2063:0] head0_row;
    logic [2063:0] head1_row;

    logic write_head_q;
    logic [3:0] write_word_q;
    logic write_aborted_q;
    logic [1:0] response_kind_q;
    logic response_head_q;
    logic [11:0] response_position_q;
    logic response_fault_q;
    logic response_from_pending_q;
    logic [3:0] read_word_q;
    logic read_aborted_q;
    logic [2063:0] assembled_row_q;

    logic lock_seen_q;
    logic fault_q;
    // A ready/valid source may legally retain valid through the edge that
    // accepts it.  These bits suppress re-interpretation against the newly
    // advanced phase until the source has withdrawn valid at least once.
    logic stage_begin_consumed_q;
    logic stage_payload_consumed_q;
    logic commit_consumed_q;
    logic attention_req_consumed_q;

    logic write_mapper_command_valid;
    logic [18:0] write_mapper_word_address;
    logic write_mapper_direction;
    logic write_mapper_reject;
    logic read_mapper_command_valid;
    logic [18:0] read_mapper_word_address;
    logic read_mapper_direction;
    logic read_mapper_reject;

    logic stage_begin_legal;
    logic stage_payload_legal;
    logic commit_legal;
    logic attention_request_legal;
    logic attention_request_committed;
    logic attention_request_pending;
    logic attention_kind_legal;
    logic unexpected_typed_completion;
    logic typed_mapper_fault;
    logic typed_padding_fault;
    logic protocol_fault_now;
    logic terminal_fault_event;
    logic terminal_fault_now;
    logic accept_window;
    logic live;

`ifndef SYNTHESIS
    logic simulation_x_fault;
`else
    wire simulation_x_fault = 1'b0;
`endif

    // Compare the six fixed prefix registers in parallel, then select
    // one bit. The layer selector no longer precedes a 12-bit comparison.
    // No prefix, bound, authorization, fault, port or cycle is changed.
    (* syn_keep = 1 *) wire [5:0] attention_prefix_lt;
    for (genvar prefix_layer = 0; prefix_layer < 6; prefix_layer++) begin : g_prefix_compare
        assign attention_prefix_lt[prefix_layer] =
            attention_position_i < committed_prefix_q[prefix_layer];
    end

    integer reset_layer;

    // Response ownership, kind, fault and valid are still resettable. DDR
    // payload is overwritten, chunk by chunk, before its selected kind can
    // become visible. The unrequested half of a K-only/V-only row is masked
    // at the existing output boundary. CLEAR/fault revoke response ownership;
    // stale bits are not a readable memory capability.
    // Pending rows already reside in the immutable-for-this-response staged
    // registers. Select them at the output instead of copying 2,064 bits into
    // the DDR assembly register and adding a second wide write source.
    wire [2063:0] selected_response_row = response_from_pending_q ?
        (response_head_q ? head1_row : head0_row) : assembled_row_q;
    always_ff @(posedge clk) begin
        if (reset_n && state_q == ST_READ_WAIT &&
            kv_read_rsp_valid_i && kv_read_rsp_ready_o &&
            !read_aborted_q && !terminal_fault_event && !kv_read_rsp_fault_i) begin
            case (read_word_q)
                4'd0: assembled_row_q[255:0] <= kv_read_rsp_data_i;
                4'd1: assembled_row_q[511:256] <= kv_read_rsp_data_i;
                4'd2: assembled_row_q[767:512] <= kv_read_rsp_data_i;
                4'd3: assembled_row_q[1023:768] <= kv_read_rsp_data_i;
                4'd4: assembled_row_q[1279:1024] <= kv_read_rsp_data_i;
                4'd5: assembled_row_q[1535:1280] <= kv_read_rsp_data_i;
                4'd6: assembled_row_q[1791:1536] <= kv_read_rsp_data_i;
                4'd7: assembled_row_q[2047:1792] <= kv_read_rsp_data_i;
                4'd8: assembled_row_q[2063:2048] <= kv_read_rsp_data_i[15:0];
                default: begin end
            endcase
        end
    end

    function automatic logic [255:0] row_word(
        input logic [2063:0] row,
        input logic [3:0] word_index
    );
        begin
            case (word_index)
                4'd0: row_word = row[255:0];
                4'd1: row_word = row[511:256];
                4'd2: row_word = row[767:512];
                4'd3: row_word = row[1023:768];
                4'd4: row_word = row[1279:1024];
                4'd5: row_word = row[1535:1280];
                4'd6: row_word = row[1791:1536];
                4'd7: row_word = row[2047:1792];
                4'd8: row_word = {240'd0, row[2063:2048]};
                default: row_word = 256'd0;
            endcase
        end
    endfunction

    always_comb begin
        head0_row = {
            pending_value_exponents_q[7:0],
            pending_key_exponents_q[7:0],
            staged_value_head0_q,
            staged_key_head0_q
        };
        head1_row = {
            pending_value_exponents_q[15:8],
            pending_key_exponents_q[15:8],
            staged_value_head1_q,
            staged_key_head1_q
        };

        stage_begin_legal = (stage_layer_i < 3'd6) &&
            (stage_position_i < 12'd2048) &&
            (stage_position_i == committed_prefix_q[stage_layer_i]) &&
            (committed_prefix_q[stage_layer_i] < 12'd2048) &&
            ($signed(stage_key_exponents_i[7:0]) >= -8'sd32) &&
            ($signed(stage_key_exponents_i[7:0]) <= 8'sd31) &&
            ($signed(stage_key_exponents_i[15:8]) >= -8'sd32) &&
            ($signed(stage_key_exponents_i[15:8]) <= 8'sd31) &&
            ($signed(stage_value_exponents_i[7:0]) >= -8'sd32) &&
            ($signed(stage_value_exponents_i[7:0]) <= 8'sd31) &&
            ($signed(stage_value_exponents_i[15:8]) >= -8'sd32) &&
            ($signed(stage_value_exponents_i[15:8]) <= 8'sd31);

        stage_payload_legal =
            (stage_coordinate_i == expected_coordinate_q) &&
            (stage_last_i == (expected_coordinate_q == 7'd127)) &&
            (stage_key_i != 16'sh8000) &&
            (stage_value_i != 16'sh8000);

        commit_legal = (commit_layer_i < 3'd6) &&
            pending_persisted_q &&
            (commit_layer_i == pending_layer_q) &&
            (commit_position_i == pending_position_q) &&
            (commit_position_i == committed_prefix_q[commit_layer_i]) &&
            (committed_prefix_q[commit_layer_i] < 12'd2048);

        attention_kind_legal = (attention_req_kind_i == REQ_FULL_KV) ||
            (attention_req_kind_i == REQ_KEY_ONLY) ||
            (attention_req_kind_i == REQ_VALUE_ONLY);
        attention_request_committed = 1'b0;
        if (attention_layer_i < 3'd6)
            attention_request_committed =
                attention_prefix_lt[attention_layer_i];
        attention_request_pending = pending_persisted_q &&
            (attention_layer_i == pending_layer_q) &&
            (attention_position_i == pending_position_q);
        attention_request_legal = pending_persisted_q &&
            (attention_layer_i == pending_layer_q) &&
            (attention_position_i < 12'd2048) &&
            (attention_kv_head_i < 2'd2) && attention_kind_legal &&
            (attention_request_committed ^ attention_request_pending);

        // Ready is based on the pre-protocol-fault window so an illegal typed
        // descriptor can be accepted and deterministically converted into a
        // terminal fault (and, for attention, one owned fault response)
        // without a combinational ready/fault loop.
        accept_window = reset_n && model_locked_i && !clear_i && !fault_q &&
            !upstream_fault_i && !endpoint_fault_i &&
            !(lock_seen_q && !model_locked_i) && !simulation_x_fault;
        stage_begin_ready_o = accept_window &&
                              (state_q == ST_IDLE) &&
                              !attention_req_valid_i &&
                              !stage_begin_consumed_q;
        stage_payload_ready_o = accept_window &&
                                (state_q == ST_STAGE) &&
                                !stage_payload_consumed_q;
        commit_ready_o = accept_window &&
                         (state_q == ST_PENDING) &&
                         !attention_req_valid_i && !commit_consumed_q;
        attention_req_ready_o = accept_window &&
                                (state_q == ST_PENDING) &&
                                !commit_valid_i &&
                                !attention_req_consumed_q;

        protocol_fault_now = 1'b0;
        if (reset_n && model_locked_i && !clear_i && !fault_q) begin
            if (stage_begin_valid_i && !stage_begin_consumed_q &&
                !(accept_window && (state_q == ST_IDLE) &&
                  !attention_req_valid_i))
                protocol_fault_now = 1'b1;
            if (stage_payload_valid_i && !stage_payload_consumed_q &&
                !(accept_window && (state_q == ST_STAGE)))
                protocol_fault_now = 1'b1;
            if (commit_valid_i && !commit_consumed_q &&
                !(accept_window && (state_q == ST_PENDING) &&
                  !attention_req_valid_i))
                protocol_fault_now = 1'b1;
            if (attention_req_valid_i && !attention_req_consumed_q &&
                !(accept_window && (state_q == ST_PENDING) &&
                  !commit_valid_i))
                protocol_fault_now = 1'b1;
            if (stage_begin_valid_i && !stage_begin_consumed_q &&
                accept_window &&
                (state_q == ST_IDLE) && !attention_req_valid_i &&
                !stage_begin_legal)
                protocol_fault_now = 1'b1;
            if (stage_payload_valid_i && !stage_payload_consumed_q &&
                accept_window &&
                (state_q == ST_STAGE) &&
                !stage_payload_legal)
                protocol_fault_now = 1'b1;
            if (commit_valid_i && !commit_consumed_q && accept_window &&
                (state_q == ST_PENDING) && !attention_req_valid_i &&
                !commit_legal)
                protocol_fault_now = 1'b1;
            if (attention_req_valid_i && !attention_req_consumed_q &&
                accept_window &&
                (state_q == ST_PENDING) && !commit_valid_i &&
                !attention_request_legal)
                protocol_fault_now = 1'b1;
        end

        unexpected_typed_completion =
            (kv_write_cpl_valid_i && (state_q != ST_WRITE_WAIT)) ||
            (kv_read_rsp_valid_i && (state_q != ST_READ_WAIT));
        typed_mapper_fault =
            ((state_q == ST_WRITE_REQ) &&
             (!write_mapper_command_valid || !write_mapper_direction ||
              write_mapper_reject)) ||
            ((state_q == ST_READ_REQ) &&
             (!read_mapper_command_valid || read_mapper_direction ||
              read_mapper_reject));
        typed_padding_fault = kv_read_rsp_valid_i &&
            (state_q == ST_READ_WAIT) && (read_word_q == 4'd8) &&
            (kv_read_rsp_data_i[255:16] != 240'd0);

        terminal_fault_event = upstream_fault_i || endpoint_fault_i ||
            (lock_seen_q && !model_locked_i) || protocol_fault_now ||
            simulation_x_fault || unexpected_typed_completion ||
            typed_mapper_fault || typed_padding_fault;
        terminal_fault_now = fault_q || terminal_fault_event;
        live = accept_window && !protocol_fault_now;

        pending_complete_o = live && pending_persisted_q &&
                             (state_q == ST_PENDING ||
                              state_q == ST_READ_REQ ||
                              state_q == ST_READ_WAIT ||
                              state_q == ST_RESPONSE);
        attention_rsp_valid_o = reset_n && (state_q == ST_RESPONSE);
        attention_rsp_kind_o = response_kind_q;
        attention_rsp_fault_o = attention_rsp_valid_o &&
            (response_fault_q || terminal_fault_now || clear_i);
        attention_rsp_from_pending_o = attention_rsp_valid_o &&
            !attention_rsp_fault_o && response_from_pending_q;
        attention_rsp_key_vector_o = 1024'd0;
        attention_rsp_key_exponent_o = 8'sd0;
        attention_rsp_value_vector_o = 1024'd0;
        attention_rsp_value_exponent_o = 8'sd0;
        if (attention_rsp_valid_o && !attention_rsp_fault_o) begin
            if (response_kind_q != REQ_VALUE_ONLY) begin
                attention_rsp_key_vector_o = selected_response_row[1023:0];
                attention_rsp_key_exponent_o =
                    $signed(selected_response_row[2055:2048]);
            end
            if (response_kind_q != REQ_KEY_ONLY) begin
                attention_rsp_value_vector_o =
                    selected_response_row[2047:1024];
                attention_rsp_value_exponent_o =
                    $signed(selected_response_row[2063:2056]);
            end
        end

        committed_prefixes_o = {
            committed_prefix_q[5], committed_prefix_q[4],
            committed_prefix_q[3], committed_prefix_q[2],
            committed_prefix_q[1], committed_prefix_q[0]
        };
        busy_o = reset_n && (state_q != ST_IDLE);
`ifndef SYNTHESIS
        // A four-state-unknown reset is neither an asserted reset nor a safe
        // operating state.  Report it as closed in simulation; an exact zero
        // remains the sole state that suppresses the fault indication.
        fail_closed_o = (reset_n === 1'b0) ? 1'b0 : terminal_fault_now;
`else
        fail_closed_o = reset_n && terminal_fault_now;
`endif
    end

`ifndef SYNTHESIS
    always_comb begin
        simulation_x_fault = $isunknown(reset_n) || $isunknown(clear_i) ||
            $isunknown(model_locked_i) || $isunknown(upstream_fault_i) ||
            $isunknown(endpoint_fault_i) ||
            $isunknown(stage_begin_valid_i) ||
            $isunknown(stage_payload_valid_i) ||
            $isunknown(commit_valid_i) ||
            $isunknown(attention_req_valid_i) ||
            $isunknown(attention_rsp_ready_i) ||
            $isunknown(kv_write_req_ready_i) ||
            $isunknown(kv_write_cpl_valid_i) ||
            $isunknown(kv_write_cpl_fault_i) ||
            $isunknown(kv_read_req_ready_i) ||
            $isunknown(kv_read_rsp_valid_i) ||
            $isunknown(kv_read_rsp_fault_i) ||
            $isunknown(state_q) || $isunknown(fault_q) ||
            $isunknown(stage_begin_consumed_q) ||
            $isunknown(stage_payload_consumed_q) ||
            $isunknown(commit_consumed_q) ||
            $isunknown(attention_req_consumed_q);
        if (stage_begin_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                $isunknown(stage_layer_i) ||
                $isunknown(stage_position_i) ||
                $isunknown(stage_key_exponents_i) ||
                $isunknown(stage_value_exponents_i);
        if (stage_payload_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                $isunknown(stage_coordinate_i) ||
                $isunknown(stage_key_i) || $isunknown(stage_value_i) ||
                $isunknown(stage_last_i);
        if (commit_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                $isunknown(commit_layer_i) ||
                $isunknown(commit_position_i);
        if (attention_req_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                $isunknown(attention_req_kind_i) ||
                $isunknown(attention_layer_i) ||
                $isunknown(attention_position_i) ||
                $isunknown(attention_kv_head_i);
        if (kv_read_rsp_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                $isunknown(kv_read_rsp_data_i);
    end
`endif

    // The semantic controller provides only typed coordinates.  This local
    // mapper creates the shadow; the 100 MHz boundary recomputes the address
    // from the descriptors and rejects any mismatch before DDR sees it.
    board1_context2048_typed_address_mapper u_write_shadow_mapper (
        .request_valid_i(state_q == ST_WRITE_REQ),
        .request_class_i(2'b01), .request_direction_i(1'b1),
        .model_word_index_i(19'd0), .layer_i(pending_layer_q),
        .position_i(pending_position_q),
        .kv_head_i({1'b0, write_head_q}), .row_word_i(write_word_q),
        .private_command_valid_o(write_mapper_command_valid),
        .private_word_address_o(write_mapper_word_address),
        .private_write_o(write_mapper_direction),
        .request_reject_o(write_mapper_reject)
    );

    board1_context2048_typed_address_mapper u_read_shadow_mapper (
        .request_valid_i(state_q == ST_READ_REQ),
        .request_class_i(2'b01), .request_direction_i(1'b0),
        .model_word_index_i(19'd0), .layer_i(pending_layer_q),
        .position_i(response_position_q),
        .kv_head_i({1'b0, response_head_q}), .row_word_i(read_word_q),
        .private_command_valid_o(read_mapper_command_valid),
        .private_word_address_o(read_mapper_word_address),
        .private_write_o(read_mapper_direction),
        .request_reject_o(read_mapper_reject)
    );

    always_comb begin
        kv_write_req_valid_o = live && (state_q == ST_WRITE_REQ) &&
                               write_mapper_command_valid &&
                               write_mapper_direction &&
                               !write_mapper_reject;
        kv_write_req_layer_o = pending_layer_q;
        kv_write_req_position_o = pending_position_q;
        kv_write_req_head_o = {1'b0, write_head_q};
        kv_write_req_row_word_o = write_word_q;
        kv_write_req_shadow_address_o = kv_write_req_valid_o ?
            write_mapper_word_address : 19'd0;
        kv_write_req_data_o = kv_write_req_valid_o ?
            row_word(write_head_q ? head1_row : head0_row, write_word_q) :
            256'd0;
        kv_write_cpl_ready_o = reset_n && (state_q == ST_WRITE_WAIT);

        kv_read_req_valid_o = live && (state_q == ST_READ_REQ) &&
                              read_mapper_command_valid &&
                              !read_mapper_direction &&
                              !read_mapper_reject;
        kv_read_req_layer_o = pending_layer_q;
        kv_read_req_position_o = response_position_q;
        kv_read_req_head_o = {1'b0, response_head_q};
        kv_read_req_row_word_o = read_word_q;
        kv_read_req_shadow_address_o = kv_read_req_valid_o ?
            read_mapper_word_address : 19'd0;
        kv_read_rsp_ready_o = reset_n && (state_q == ST_READ_WAIT);
    end

    // Each coordinate has a fixed local write enable and a fixed slice.
    // This is the same 128-coordinate protocol and storage as the predecessor;
    // no variable-index wide-vector insertion network is required.
    for (genvar coordinate = 0; coordinate < 64; coordinate++) begin : g_stage
        always_ff @(posedge clk) begin
            if (stage_payload_valid_i && stage_payload_ready_o &&
                stage_payload_legal && expected_coordinate_q == 7'(coordinate)) begin
                staged_key_head0_q[coordinate*16 +: 16] <= stage_key_i;
                staged_value_head0_q[coordinate*16 +: 16] <= stage_value_i;
            end
            if (stage_payload_valid_i && stage_payload_ready_o &&
                stage_payload_legal && expected_coordinate_q == 7'(coordinate+64)) begin
                staged_key_head1_q[coordinate*16 +: 16] <= stage_key_i;
                staged_value_head1_q[coordinate*16 +: 16] <= stage_value_i;
            end
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state_q <= ST_IDLE;
            for (reset_layer = 0; reset_layer < 6;
                 reset_layer = reset_layer + 1)
                committed_prefix_q[reset_layer] <= 12'd0;
            pending_layer_q <= 3'd0;
            pending_position_q <= 12'd0;
            pending_key_exponents_q <= 16'sd0;
            pending_value_exponents_q <= 16'sd0;
            expected_coordinate_q <= 7'd0;
            pending_persisted_q <= 1'b0;
            write_head_q <= 1'b0;
            write_word_q <= 4'd0;
            write_aborted_q <= 1'b0;
            response_kind_q <= REQ_FULL_KV;
            response_head_q <= 1'b0;
            response_position_q <= 12'd0;
            response_fault_q <= 1'b0;
            response_from_pending_q <= 1'b0;
            read_word_q <= 4'd0;
            read_aborted_q <= 1'b0;
            lock_seen_q <= 1'b0;
            fault_q <= 1'b0;
            stage_begin_consumed_q <= 1'b0;
            stage_payload_consumed_q <= 1'b0;
            commit_consumed_q <= 1'b0;
            attention_req_consumed_q <= 1'b0;
        end else begin
            if (!stage_begin_valid_i)
                stage_begin_consumed_q <= 1'b0;
            else if (stage_begin_ready_o)
                stage_begin_consumed_q <= 1'b1;
            if (!stage_payload_valid_i)
                stage_payload_consumed_q <= 1'b0;
            else if (stage_payload_ready_o)
                stage_payload_consumed_q <= 1'b1;
            if (!commit_valid_i)
                commit_consumed_q <= 1'b0;
            else if (commit_ready_o)
                commit_consumed_q <= 1'b1;
            if (!attention_req_valid_i)
                attention_req_consumed_q <= 1'b0;
            else if (attention_req_ready_o)
                attention_req_consumed_q <= 1'b1;

            if (model_locked_i)
                lock_seen_q <= 1'b1;
            if (terminal_fault_event)
                fault_q <= 1'b1;

            if (clear_i) begin
                for (reset_layer = 0; reset_layer < 6;
                     reset_layer = reset_layer + 1)
                    committed_prefix_q[reset_layer] <= 12'd0;
                pending_persisted_q <= 1'b0;
                pending_layer_q <= 3'd0;
                pending_position_q <= 12'd0;
                expected_coordinate_q <= 7'd0;
            end

            case (state_q)
                ST_IDLE: begin
                    write_aborted_q <= 1'b0;
                    read_aborted_q <= 1'b0;
                    response_fault_q <= 1'b0;
                    response_from_pending_q <= 1'b0;
                    if (!clear_i && !terminal_fault_event &&
                        stage_begin_valid_i && stage_begin_ready_o &&
                        stage_begin_legal) begin
                        pending_layer_q <= stage_layer_i;
                        pending_position_q <= stage_position_i;
                        pending_key_exponents_q <= stage_key_exponents_i;
                        pending_value_exponents_q <=
                            stage_value_exponents_i;
                        expected_coordinate_q <= 7'd0;
                        state_q <= ST_STAGE;
                    end
                end

                ST_STAGE: begin
                    if (clear_i || terminal_fault_event) begin
                        state_q <= ST_IDLE;
                    end else if (stage_payload_valid_i &&
                                 stage_payload_ready_o &&
                                 stage_payload_legal) begin
                        if (expected_coordinate_q == 7'd127) begin
                            write_head_q <= 1'b0;
                            write_word_q <= 4'd0;
                            write_aborted_q <= 1'b0;
                            state_q <= ST_WRITE_REQ;
                        end else begin
                            expected_coordinate_q <=
                                expected_coordinate_q + 1'b1;
                        end
                    end
                end

                ST_WRITE_REQ: begin
                    if (clear_i || terminal_fault_event) begin
                        state_q <= ST_IDLE;
                    end else if (kv_write_req_valid_o &&
                                 kv_write_req_ready_i) begin
                        state_q <= ST_WRITE_WAIT;
                    end
                end

                ST_WRITE_WAIT: begin
                    if (clear_i)
                        write_aborted_q <= 1'b1;
                    if (kv_write_cpl_valid_i &&
                        kv_write_cpl_ready_o) begin
                        if (clear_i || write_aborted_q || terminal_fault_event ||
                            kv_write_cpl_fault_i) begin
                            if (!write_aborted_q &&
                                kv_write_cpl_fault_i)
                                fault_q <= 1'b1;
                            state_q <= ST_IDLE;
                        end else if (write_head_q &&
                                     (write_word_q == 4'd8)) begin
                            pending_persisted_q <= 1'b1;
                            state_q <= ST_PENDING;
                        end else begin
                            if (write_word_q == 4'd8) begin
                                write_head_q <= 1'b1;
                                write_word_q <= 4'd0;
                            end else begin
                                write_word_q <= write_word_q + 1'b1;
                            end
                            state_q <= ST_WRITE_REQ;
                        end
                    end
                end

                ST_PENDING: begin
                    if (clear_i) begin
                        state_q <= ST_IDLE;
                    end else if (terminal_fault_event) begin
                        if (attention_req_valid_i &&
                            attention_req_ready_o) begin
                            response_kind_q <= attention_req_kind_i;
                            response_head_q <= 1'b0;
                            response_position_q <= 12'd0;
                            response_fault_q <= 1'b1;
                            response_from_pending_q <= 1'b0;
                            state_q <= ST_RESPONSE;
                        end else begin
                            state_q <= ST_IDLE;
                        end
                    end else if (commit_valid_i && commit_ready_o &&
                                 commit_legal) begin
                        committed_prefix_q[commit_layer_i] <=
                            committed_prefix_q[commit_layer_i] + 1'b1;
                        pending_persisted_q <= 1'b0;
                        pending_layer_q <= 3'd0;
                        pending_position_q <= 12'd0;
                        state_q <= ST_IDLE;
                    end else if (attention_req_valid_i &&
                                 attention_req_ready_o &&
                                 attention_request_legal) begin
                        response_kind_q <= attention_req_kind_i;
                        response_head_q <= attention_kv_head_i[0];
                        response_position_q <= attention_position_i;
                        response_fault_q <= 1'b0;
                        read_aborted_q <= 1'b0;
                        if (attention_request_pending) begin
                            response_from_pending_q <= 1'b1;
                            state_q <= ST_RESPONSE;
                        end else begin
                            response_from_pending_q <= 1'b0;
                            if (attention_req_kind_i == REQ_VALUE_ONLY)
                                read_word_q <= 4'd4;
                            else
                                read_word_q <= 4'd0;
                            state_q <= ST_READ_REQ;
                        end
                    end
                end

                ST_READ_REQ: begin
                    if (clear_i || terminal_fault_event) begin
                        response_fault_q <= 1'b1;
                        response_from_pending_q <= 1'b0;
                        state_q <= ST_RESPONSE;
                    end else if (kv_read_req_valid_o &&
                                 kv_read_req_ready_i) begin
                        state_q <= ST_READ_WAIT;
                    end
                end

                ST_READ_WAIT: begin
                    if (clear_i)
                        read_aborted_q <= 1'b1;
                    if (kv_read_rsp_valid_i &&
                        kv_read_rsp_ready_o) begin
                        if (clear_i || read_aborted_q || terminal_fault_event ||
                            kv_read_rsp_fault_i) begin
                            response_fault_q <= 1'b1;
                            response_from_pending_q <= 1'b0;
                            if (!read_aborted_q &&
                                kv_read_rsp_fault_i)
                                fault_q <= 1'b1;
                            state_q <= ST_RESPONSE;
                        end else begin
                            if (read_word_q == 4'd8) begin
                                state_q <= ST_RESPONSE;
                            end else if ((response_kind_q == REQ_KEY_ONLY) &&
                                         (read_word_q == 4'd3)) begin
                                read_word_q <= 4'd8;
                                state_q <= ST_READ_REQ;
                            end else begin
                                read_word_q <= read_word_q + 1'b1;
                                state_q <= ST_READ_REQ;
                            end
                        end
                    end
                end

                ST_RESPONSE: begin
                    if (clear_i || terminal_fault_event) begin
                        response_fault_q <= 1'b1;
                        response_from_pending_q <= 1'b0;
                    end
                    if (attention_rsp_valid_o &&
                        attention_rsp_ready_i) begin
                        response_fault_q <= 1'b0;
                        response_from_pending_q <= 1'b0;
                        if (clear_i)
                            state_q <= ST_IDLE;
                        else if (pending_persisted_q &&
                            !terminal_fault_now)
                            state_q <= ST_PENDING;
                        else
                            state_q <= ST_IDLE;
                    end
                end

                default: begin
                    state_q <= ST_IDLE;
                    pending_persisted_q <= 1'b0;
                    response_fault_q <= 1'b1;
                    fault_q <= 1'b1;
                end
            endcase
        end
    end

`ifdef FORMAL
    logic formal_past_valid;
    always_ff @(posedge clk) begin
        formal_past_valid <= 1'b1;
        if (reset_n) begin
            assert (write_word_q <= 4'd8);
            assert (read_word_q <= 4'd8);
            assert (pending_position_q < 12'd2048 ||
                    !pending_persisted_q);
            if (kv_write_req_valid_o) begin
                assert (kv_write_req_shadow_address_o >= 19'd227072);
                assert (kv_write_req_shadow_address_o < 19'd448256);
            end
            if (kv_read_req_valid_o) begin
                assert (kv_read_req_shadow_address_o >= 19'd227072);
                assert (kv_read_req_shadow_address_o < 19'd448256);
            end
            if (kv_write_req_valid_o &&
                (write_word_q == 4'd8))
                assert (kv_write_req_data_o[255:16] == 240'd0);
            if (pending_complete_o)
                assert (pending_persisted_q);
            if (attention_rsp_fault_o) begin
                assert (attention_rsp_key_vector_o == 1024'd0);
                assert (attention_rsp_value_vector_o == 1024'd0);
            end
            if (fault_q) begin
                assert (!stage_begin_ready_o);
                assert (!stage_payload_ready_o);
                assert (!commit_ready_o);
                assert (!attention_req_ready_o);
            end
            if (formal_past_valid && $past(reset_n)) begin
                if ($past(fault_q))
                    assert (fault_q);
                if ($past(attention_rsp_valid_o &&
                          !attention_rsp_ready_i && !clear_i &&
                          !terminal_fault_event))
                    assert (attention_rsp_valid_o);
                if ($past(clear_i))
                    assert (committed_prefixes_o == 72'd0);
            end
        end
    end
`endif
endmodule

`default_nettype wire
