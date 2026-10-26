`timescale 1ns/1ps
`default_nettype none

// Correctness-first typed external-DDR K/V cache controller for the fixed
// context-2048 successor. Semantic replies select one 64-coordinate KV head.
// Physical row0 holds128 K coordinates and the two K exponent bytes;
// physical row1 holds128 V coordinates and the two V exponent bytes.
// Each physical row is2064 bits in nine256-bit words, with240 zero padding
// bits in metadata word8. The typed physical row selector remains bounded0/1.
// Both kind rows are staged together and become visible
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
    localparam logic [3:0] ST_CACHE_READ = 4'd8;
    localparam logic [3:0] ST_WRITE_PREFETCH_A = 4'd9;
    localparam logic [3:0] ST_WRITE_PREFETCH_B = 4'd10;
    localparam logic [3:0] ST_WRITE_PACK = 4'd11;
    localparam logic [3:0] ST_WRITE_META = 4'd12;
    localparam logic [3:0] ST_PENDING_READ = 4'd13;

    logic [3:0] state_q;
    logic [11:0] committed_prefix_q [0:5];
    logic [2:0] pending_layer_q;
    logic [11:0] pending_position_q;
    logic signed [15:0] pending_key_exponents_q;
    logic signed [15:0] pending_value_exponents_q;
    logic [6:0] expected_coordinate_q;
    logic pending_persisted_q;

    // Isolated storage prototype: pending pairs occupy slots8..23 of the
    // same eight32-bit synchronous1R/1W banks whose historical rows use0..7.
    // Payload/offer bits are unreset; owned state and full128-coordinate staging
    // must precede persistence/publication. No old cache theorem is inherited.
    logic [255:0] write_offer_q;
    logic [3:0] pending_issued_q;
    logic [2:0] pending_returned_q;
    logic pending_read_pending_q;

    logic write_head_q;
    logic [3:0] write_word_q;
    logic write_aborted_q;
    logic [1:0] response_kind_q;
    logic response_head_q;
    logic [2:0] response_layer_q;
    logic [11:0] response_position_q;
    logic response_fault_q;
    logic response_from_pending_q;
    logic [3:0] read_word_q, read_return_word_q;
    logic [3:0] read_outstanding_q;
    logic read_issue_done_q;
    wire read_collect_state = state_q == ST_READ_REQ || state_q == ST_READ_WAIT;
    wire read_issue = kv_read_req_valid_o && kv_read_req_ready_i;
    wire read_retire = kv_read_rsp_valid_i && kv_read_rsp_ready_o;
    wire [4:0] read_outstanding_next = {1'b0,read_outstanding_q} +
        (read_issue ? 5'd1 : 5'd0) - (read_retire ? 5'd1 : 5'd0);
    logic read_aborted_q;
    logic [2063:0] assembled_row_q;
    logic read_physical_kind_q;
    logic read_epoch_q;
    logic [8:0] read_received_mask_q;

    // One complete committed kind row, shared by the two semantic KV heads.
    // Only validity/ownership resets. Payload RAM and its read register retain
    // arbitrary old bits until a complete owned fill permits publication.
    wire [255:0] cache_read_data_q;
    logic [15:0] cache_metadata_q;
    logic cache_valid_q, cache_kind_q, cache_tag_epoch_q;
    logic [2:0] cache_layer_q;
    logic [11:0] cache_position_q;
    logic cache_epoch_q, cache_clear_seen_q;
    logic [2:0] cache_issued_q, cache_returned_q;
    logic cache_read_pending_q;
    logic cache_copy_kind_q;

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
    wire read_abort_now = clear_i || terminal_fault_now ||
        (kv_read_rsp_valid_i && kv_read_rsp_fault_i);
    wire requested_physical_kind = attention_req_kind_i == REQ_VALUE_ONLY;
    wire cache_request_match = cache_valid_q &&
        attention_req_kind_i != REQ_FULL_KV &&
        cache_kind_q == requested_physical_kind &&
        cache_layer_q == attention_layer_i &&
        cache_position_q == attention_position_i &&
        cache_tag_epoch_q == cache_epoch_q;
    wire cache_response_match = cache_valid_q &&
        cache_kind_q == cache_copy_kind_q &&
        cache_layer_q == response_layer_q &&
        cache_position_q == response_position_q &&
        cache_tag_epoch_q == cache_epoch_q;
    wire cache_read_enable = reset_n && state_q == ST_CACHE_READ &&
        !read_abort_now && cache_response_match && cache_issued_q < 3'd4;
    wire [2:0] cache_read_address = {response_head_q,cache_issued_q[1:0]};
    wire healthy_fill_return = reset_n && read_collect_state && read_retire &&
        !read_aborted_q && !read_abort_now && read_epoch_q == cache_epoch_q;
    wire [8:0] read_received_mask_next = read_received_mask_q |
        (healthy_fill_return ? (9'b1 << read_return_word_q) : 9'd0);

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
    wire [2063:0] selected_response_row = assembled_row_q;
    wire pending_read_enable = reset_n && state_q == ST_PENDING_READ &&
        !read_abort_now && pending_persisted_q && pending_issued_q < 4'd8;
    wire write_prefetch_enable = reset_n && !clear_i && !terminal_fault_now &&
        (state_q == ST_WRITE_PREFETCH_A || state_q == ST_WRITE_PREFETCH_B);
    wire store_read_enable = cache_read_enable || pending_read_enable || write_prefetch_enable;
    wire [4:0] store_read_address = cache_read_enable ? {2'b00,cache_read_address} :
        pending_read_enable ? (5'd8 + {1'b0,response_head_q,pending_issued_q[2:0]}) :
        (5'd8 + {write_word_q,1'b0} + (state_q == ST_WRITE_PREFETCH_B ? 5'd1 : 5'd0));
    for (genvar bank = 0; bank < 8; bank++) begin : g_pair_bank
        (* ram_style = "block", syn_ramstyle = "block_ram" *) logic [31:0] words [0:31];
        logic [31:0] read_data_q;
        logic bank_wr_enable;
        logic [4:0] bank_wr_addr;
        logic [31:0] bank_wr_data;
        always_comb begin
            bank_wr_enable = 1'b0;
            bank_wr_addr = 5'd0;
            bank_wr_data = 32'd0;
            if (stage_payload_valid_i && stage_payload_ready_o && stage_payload_legal && expected_coordinate_q[2:0] == 3'(bank)) begin
                bank_wr_enable = 1'b1;
                bank_wr_addr = 5'd8 + {1'b0,expected_coordinate_q[6:3]};
                bank_wr_data = {stage_value_i,stage_key_i};
            end else if (healthy_fill_return && read_return_word_q < 8) begin
                bank_wr_enable = 1'b1;
                bank_wr_addr = {2'b00,read_return_word_q[2:0]};
                bank_wr_data = kv_read_rsp_data_i[bank*32 +: 32];
            end
        end
        always_ff @(posedge clk) begin
            if (bank_wr_enable) words[bank_wr_addr] <= bank_wr_data;
            if (store_read_enable) read_data_q <= words[store_read_address];
        end
        assign cache_read_data_q[bank*32 +: 32] = read_data_q;
    end
    always_ff @(posedge clk) begin
        if (healthy_fill_return && read_return_word_q == 8)
            cache_metadata_q <= kv_read_rsp_data_i[15:0];
        // Two pending pair words become one immutable256-bit K/V write offer.
        if (reset_n && !clear_i && !terminal_fault_now) begin
            if (state_q == ST_WRITE_PREFETCH_B)
                for (integer lane = 0; lane < 8; lane++)
                    write_offer_q[lane*16 +: 16] <= cache_read_data_q[lane*32 + (write_head_q ? 16 : 0) +: 16];
            if (state_q == ST_WRITE_PACK)
                for (integer lane = 0; lane < 8; lane++)
                    write_offer_q[128+lane*16 +: 16] <= cache_read_data_q[lane*32 + (write_head_q ? 16 : 0) +: 16];
            if (state_q == ST_WRITE_META)
                write_offer_q <= {240'd0,write_head_q ? pending_value_exponents_q : pending_key_exponents_q};
        end
        if (reset_n && state_q == ST_PENDING_READ && pending_read_pending_q &&
            !read_abort_now && pending_persisted_q) begin
            for (integer lane = 0; lane < 8; lane++) begin
                assembled_row_q[(pending_returned_q*8+lane)*16 +: 16] <= cache_read_data_q[lane*32 +: 16];
                assembled_row_q[1024+(pending_returned_q*8+lane)*16 +: 16] <= cache_read_data_q[lane*32+16 +: 16];
            end
            if (pending_returned_q == 7) begin
                assembled_row_q[2055:2048] <= pending_key_exponents_q[response_head_q*8 +: 8];
                assembled_row_q[2063:2056] <= pending_value_exponents_q[response_head_q*8 +: 8];
            end
        end
        // Both misses and hits use the same synchronous RAM-copy path. The
        // existing semantic buffer has one payload source instead of a second
        // 1024-bit raw-return/cache mux network.
        if (reset_n && state_q == ST_CACHE_READ && cache_read_pending_q &&
            !read_abort_now && cache_response_match) begin
            case (cache_returned_q[1:0])
                0: if (!cache_copy_kind_q) assembled_row_q[255:0] <= cache_read_data_q;
                   else assembled_row_q[1279:1024] <= cache_read_data_q;
                1: if (!cache_copy_kind_q) assembled_row_q[511:256] <= cache_read_data_q;
                   else assembled_row_q[1535:1280] <= cache_read_data_q;
                2: if (!cache_copy_kind_q) assembled_row_q[767:512] <= cache_read_data_q;
                   else assembled_row_q[1791:1536] <= cache_read_data_q;
                3: if (!cache_copy_kind_q) assembled_row_q[1023:768] <= cache_read_data_q;
                   else assembled_row_q[2047:1792] <= cache_read_data_q;
            endcase
            if (cache_returned_q == 3) begin
                if (!cache_copy_kind_q)
                    assembled_row_q[2055:2048] <= cache_metadata_q[response_head_q*8 +: 8];
                else
                    assembled_row_q[2063:2056] <= cache_metadata_q[response_head_q*8 +: 8];
            end
        end
    end

    always_comb begin
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
            (kv_read_rsp_valid_i && (!read_collect_state || read_outstanding_q == 0));
        typed_mapper_fault =
            ((state_q == ST_WRITE_REQ) &&
             (!write_mapper_command_valid || !write_mapper_direction ||
              write_mapper_reject)) ||
            ((state_q == ST_READ_REQ) &&
             (!read_mapper_command_valid || read_mapper_direction ||
              read_mapper_reject));
        typed_padding_fault = kv_read_rsp_valid_i &&
            read_collect_state && (read_return_word_q == 4'd8) &&
            ((kv_read_rsp_data_i[255:16] != 240'd0) ||
             ($signed(kv_read_rsp_data_i[7:0]) < -8'sd32) ||
             ($signed(kv_read_rsp_data_i[7:0]) > 8'sd31) ||
             ($signed(kv_read_rsp_data_i[15:8]) < -8'sd32) ||
             ($signed(kv_read_rsp_data_i[15:8]) > 8'sd31));

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
                              state_q == ST_CACHE_READ ||
                              state_q == ST_PENDING_READ ||
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
        .model_word_index_i(19'd0), .layer_i(response_layer_q),
        .position_i(response_position_q),
        .kv_head_i({1'b0, read_physical_kind_q}), .row_word_i(read_word_q),
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
            write_offer_q :
            256'd0;
        kv_write_cpl_ready_o = reset_n && (state_q == ST_WRITE_WAIT);

        kv_read_req_valid_o = live && (state_q == ST_READ_REQ) &&
                              !read_aborted_q && !read_abort_now &&
                              read_outstanding_q < 4'd8 &&
                              read_mapper_command_valid &&
                              !read_mapper_direction &&
                              !read_mapper_reject;
        kv_read_req_layer_o = response_layer_q;
        kv_read_req_position_o = response_position_q;
        kv_read_req_head_o = {1'b0, read_physical_kind_q};
        kv_read_req_row_word_o = read_word_q;
        kv_read_req_shadow_address_o = kv_read_req_valid_o ?
            read_mapper_word_address : 19'd0;
        kv_read_rsp_ready_o = reset_n && read_collect_state && read_outstanding_q != 0;
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state_q <= ST_IDLE;
            pending_issued_q <= 0; pending_returned_q <= 0; pending_read_pending_q <= 0;
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
            response_layer_q <= 3'd0;
            response_position_q <= 12'd0;
            response_fault_q <= 1'b0;
            response_from_pending_q <= 1'b0;
            read_word_q <= 4'd0;
            read_return_word_q <= 4'd0;
            read_outstanding_q <= 4'd0;
            read_issue_done_q <= 1'b0;
            read_aborted_q <= 1'b0;
            read_physical_kind_q <= 1'b0;
            read_epoch_q <= 1'b0;
            read_received_mask_q <= 9'd0;
            cache_valid_q <= 1'b0;
            cache_kind_q <= 1'b0;
            cache_layer_q <= 3'd0;
            cache_position_q <= 12'd0;
            cache_tag_epoch_q <= 1'b0;
            cache_epoch_q <= 1'b0;
            cache_clear_seen_q <= 1'b0;
            cache_issued_q <= 3'd0;
            cache_returned_q <= 3'd0;
            cache_read_pending_q <= 1'b0;
            cache_copy_kind_q <= 1'b0;
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

            if (!clear_i) cache_clear_seen_q <= 1'b0;
            else if (!cache_clear_seen_q) begin
                cache_clear_seen_q <= 1'b1;
                cache_epoch_q <= ~cache_epoch_q;
            end
            if (clear_i || terminal_fault_now || !model_locked_i ||
                (stage_begin_valid_i && stage_begin_ready_o) ||
                (commit_valid_i && commit_ready_o))
                cache_valid_q <= 1'b0;

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
                            state_q <= ST_WRITE_PREFETCH_A;
                        end else begin
                            expected_coordinate_q <=
                                expected_coordinate_q + 1'b1;
                        end
                    end
                end

                ST_WRITE_PREFETCH_A, ST_WRITE_PREFETCH_B, ST_WRITE_PACK, ST_WRITE_META: begin
                    if (clear_i || terminal_fault_event) state_q <= ST_IDLE;
                    else case (state_q)
                        ST_WRITE_PREFETCH_A: state_q <= ST_WRITE_PREFETCH_B;
                        ST_WRITE_PREFETCH_B: state_q <= ST_WRITE_PACK;
                        default: state_q <= ST_WRITE_REQ;
                    endcase
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
                            state_q <= (write_word_q == 7) ? ST_WRITE_META : ST_WRITE_PREFETCH_A;
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
                            response_layer_q <= 3'd0;
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
                        response_layer_q <= attention_layer_i;
                        response_position_q <= attention_position_i;
                        response_fault_q <= 1'b0;
                        read_aborted_q <= 1'b0;
                        if (attention_request_pending) begin
                            response_from_pending_q <= 1'b1;
                            pending_issued_q <= 0; pending_returned_q <= 0; pending_read_pending_q <= 0;
                            state_q <= ST_PENDING_READ;
                        end else if (cache_request_match) begin
                            response_from_pending_q <= 1'b0;
                            cache_issued_q <= 3'd0;
                            cache_returned_q <= 3'd0;
                            cache_read_pending_q <= 1'b0;
                            cache_copy_kind_q <= requested_physical_kind;
                            state_q <= ST_CACHE_READ;
                        end else begin
                            response_from_pending_q <= 1'b0;
                            cache_valid_q <= 1'b0;
                            read_physical_kind_q <= requested_physical_kind;
                            read_epoch_q <= cache_epoch_q;
                            read_received_mask_q <= 9'd0;
                            read_word_q <= 4'd0;
                            read_return_word_q <= 4'd0;
                            read_outstanding_q <= 0;
                            read_issue_done_q <= 0;
                            state_q <= ST_READ_REQ;
                        end
                    end
                end

                ST_READ_REQ, ST_READ_WAIT: begin
                    // Responses retain their old owners across CLEAR. Stop
                    // issuing immediately, but never publish the semantic
                    // fault completion until every accepted word has drained.
                    read_outstanding_q <= read_outstanding_next[3:0];
                    read_received_mask_q <= read_received_mask_next;
                    if (read_abort_now || read_aborted_q) begin
                        read_aborted_q <= 1'b1;
                        response_fault_q <= 1'b1;
                        response_from_pending_q <= 1'b0;
                        if (read_retire && kv_read_rsp_fault_i &&
                            !clear_i && !read_aborted_q)
                            fault_q <= 1'b1;
                        if (read_outstanding_next == 0)
                            state_q <= ST_RESPONSE;
                        else state_q <= ST_READ_WAIT;
                    end else begin
                        if (read_issue) begin
                            if (read_word_q == 4'd8) begin
                                read_issue_done_q <= 1'b1;
                                state_q <= ST_READ_WAIT;
                            end else read_word_q <= read_word_q + 1'b1;
                        end
                        if (read_retire) begin
                            if (read_return_word_q != 4'd8)
                                read_return_word_q <= read_return_word_q + 1'b1;
                        end
                        if ((read_issue_done_q || (read_issue && read_word_q == 4'd8)) &&
                            read_outstanding_next == 0) begin
                            if (read_received_mask_next != 9'h1ff ||
                                read_epoch_q != cache_epoch_q) begin
                                cache_valid_q <= 1'b0;
                                response_fault_q <= 1'b1;
                                fault_q <= 1'b1;
                                state_q <= ST_RESPONSE;
                            end else begin
                                cache_valid_q <= 1'b1;
                                cache_kind_q <= read_physical_kind_q;
                                cache_layer_q <= response_layer_q;
                                cache_position_q <= response_position_q;
                                cache_tag_epoch_q <= read_epoch_q;
                                cache_copy_kind_q <= read_physical_kind_q;
                                cache_issued_q <= 3'd0;
                                cache_returned_q <= 3'd0;
                                cache_read_pending_q <= 1'b0;
                                state_q <= ST_CACHE_READ;
                            end
                        end
                    end
                end

                ST_PENDING_READ: begin
                    if (read_abort_now || !pending_persisted_q) begin
                        pending_read_pending_q <= 0;
                        response_fault_q <= 1;
                        response_from_pending_q <= 0;
                        if (!read_abort_now) fault_q <= 1;
                        state_q <= ST_RESPONSE;
                    end else begin
                        pending_read_pending_q <= pending_read_enable;
                        if (pending_read_enable) pending_issued_q <= pending_issued_q + 1'b1;
                        if (pending_read_pending_q) begin
                            pending_returned_q <= pending_returned_q + 1'b1;
                            if (pending_returned_q == 7) begin
                                pending_read_pending_q <= 0;
                                state_q <= ST_RESPONSE;
                            end
                        end
                    end
                end

                ST_CACHE_READ: begin
                    if (read_abort_now || !cache_response_match) begin
                        cache_read_pending_q <= 1'b0;
                        cache_valid_q <= 1'b0;
                        response_fault_q <= 1'b1;
                        response_from_pending_q <= 1'b0;
                        if (!read_abort_now) fault_q <= 1'b1;
                        state_q <= ST_RESPONSE;
                    end else begin
                        cache_read_pending_q <= cache_read_enable;
                        if (cache_read_enable) cache_issued_q <= cache_issued_q + 1'b1;
                        if (cache_read_pending_q) begin
                            cache_returned_q <= cache_returned_q + 1'b1;
                            if (cache_returned_q == 3'd3) begin
                                cache_read_pending_q <= 1'b0;
                                if (response_kind_q == REQ_FULL_KV && !cache_copy_kind_q) begin
                                    // The selected K half is now captured.
                                    // Fetch/capture V before the single FULL
                                    // semantic completion becomes visible.
                                    read_physical_kind_q <= 1'b1;
                                    read_word_q <= 4'd0;
                                    read_return_word_q <= 4'd0;
                                    read_received_mask_q <= 9'd0;
                                    read_issue_done_q <= 1'b0;
                                    cache_valid_q <= 1'b0;
                                    state_q <= ST_READ_REQ;
                                end else state_q <= ST_RESPONSE;
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
                    cache_valid_q <= 1'b0;
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
            assert (read_return_word_q <= 4'd8);
            assert (read_outstanding_q <= 8);
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
