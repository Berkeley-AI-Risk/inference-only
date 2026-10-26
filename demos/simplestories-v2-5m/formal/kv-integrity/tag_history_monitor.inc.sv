    // One arbitrary tag chunk; observation ports are added inside each real
    // tag bank, without changing its existing read or write ports.
    (* anyconst *) reg [14:0] f_tag_select;
    wire [2:0] f_tag_layer = f_tag_select[14:12];
    wire [6:0] f_tag_page = f_tag_select[11:5];
    wire f_tag_head = f_tag_select[4];
    wire f_tag_role = f_tag_select[3];
    wire [2:0] f_tag_chunk = f_tag_select[2:0];
    wire [11:0] f_tag_address = f_tag_select[11:0];
    wire f_tag_shape = f_tag_layer < 6;
    wire [2:0] f_tag_ordinal = {1'b0,f_tag_head,f_tag_role};
    wire f_tag_identity = layer_q == f_tag_layer && page_q == f_tag_page &&
        group_head_q == f_tag_head && role_q == f_tag_role;
    wire f_tag_population = population_q && population_layer_q == f_tag_layer &&
        population_position_q[10:4] == f_tag_page;
    wire [11:0] f_tag_prefix = prefix_q[f_tag_layer];
    wire [11:0] f_tag_page_base = {1'b0,f_tag_page,4'd0};
    wire [11:0] f_tag_remaining = f_tag_prefix - f_tag_page_base;
    wire [4:0] f_tag_published_positions = f_tag_prefix <= f_tag_page_base ? 5'd0 :
        (f_tag_remaining >= 16 ? 5'd16 : f_tag_remaining[4:0]);
    wire [4:0] f_tag_current_positions = f_tag_population ?
        {1'b0,population_position_q[3:0]} + 5'd1 : f_tag_published_positions;
    wire f_tag_required = f_tag_population ?
        (f_tag_ordinal < f_wr_row_tags || (f_tag_ordinal == f_wr_row_tags &&
         owner_q == WRITE_OWNER && state_q == TWRITE && f_tag_chunk < chunk_q)) :
        f_tag_published_positions != 0;
    wire [11:0] f_tag_active_remaining = prefix_q[layer_q] - {1'b0,page_q,4'd0};
    reg f_tag_seen, f_tag_stored, f_tag_read_seen, f_tag_read_target, f_tag_expected_complete;
    reg [31:0] f_tag_value;
    reg [63:0] f_tag_epoch;
    reg [4:0] f_tag_positions;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            f_tag_seen <= 0;
            f_tag_stored <= 0;
            f_tag_read_seen <= 0;
            f_tag_read_target <= 0;
            f_tag_expected_complete <= 0;
            f_tag_value <= 0;
            f_tag_epoch <= 0;
            f_tag_positions <= 0;
        end else begin
            if (clear_i || terminal_now || (write_fire && wr_legal && !population_q &&
                s_wr_layer == f_tag_layer && s_wr_position[10:4] == f_tag_page)) begin
                f_tag_seen <= 0;
                f_tag_stored <= 0;
            end
            if (live && state_q == HDIGEST && hash_write_q && hash_digest_valid &&
                f_tag_shape && f_tag_identity) begin
                f_tag_seen <= 1;
                f_tag_stored <= 0;
                f_tag_value <= hash_digest[f_tag_chunk*32 +:32];
                f_tag_epoch <= epoch_q;
                f_tag_positions <= positions_q;
            end
            if (tag_write && f_tag_shape && f_tag_identity && chunk_q == f_tag_chunk)
                f_tag_stored <= 1;
            if (clear_i || terminal_now || write_fire || (read_fire && rd_legal && !cache_hit)) begin
                f_tag_read_seen <= 0;
                f_tag_read_target <= 0;
                f_tag_expected_complete <= 0;
            end
            if (tag_read) begin
                f_tag_read_seen <= 1;
                f_tag_read_target <= f_tag_identity && chunk_q == f_tag_chunk;
            end
            if (live && state_q == TCAP && chunk_q == 7) f_tag_expected_complete <= 1;
        end
    end

    always_comb begin
        if (reset_n) begin
            if (f_tag_seen || f_tag_read_seen || f_tag_expected_complete) assert(lock_seen_q);
            if (f_tag_read_seen || f_tag_expected_complete) assert(!population_q && owner_q != WRITE_OWNER);
            if (f_tag_stored) assert(f_tag_seen && f_tag_shape);
            if (f_tag_stored) begin
                if (f_tag_layer == 0) assert(f_tag_memory[0] == f_tag_value);
                if (f_tag_layer == 1) assert(f_tag_memory[1] == f_tag_value);
                if (f_tag_layer == 2) assert(f_tag_memory[2] == f_tag_value);
                if (f_tag_layer == 3) assert(f_tag_memory[3] == f_tag_value);
                if (f_tag_layer == 4) assert(f_tag_memory[4] == f_tag_value);
                if (f_tag_layer == 5) assert(f_tag_memory[5] == f_tag_value);
            end
            if (aborted_q) assert(!f_tag_seen && !f_tag_stored && !f_tag_read_seen && !f_tag_expected_complete);
            if (live && owner_q == READ_OWNER) begin
                assert(layer_q < 6 && {1'b0,page_q,4'd0} < prefix_q[layer_q]);
                assert(positions_q == (f_tag_active_remaining >= 16 ? 5'd16 : f_tag_active_remaining[4:0]));
                if (state_q == HBEGIN || state_q == HREAD || state_q == HCAP || state_q == HWORD ||
                    state_q == HDIGEST || state_q == OREAD || state_q == OCAP || state_q == RRETURN)
                    assert(f_tag_expected_complete);
            end
            if (live && cache_valid_q) begin
                assert(f_tag_expected_complete);
                assert(layer_q == cache_layer_q && page_q == cache_page_q && positions_q == cache_positions_q &&
                       group_head_q == cache_head_q && role_q == cache_role_q);
            end
            if (live && f_tag_shape) begin
                assert(f_tag_stored == f_tag_required);
                if (f_tag_seen) begin
                    assert(f_tag_positions == f_tag_current_positions && f_tag_positions != 0);
                    assert(f_tag_epoch == epoch_q);
                end
                if (tag_write && f_tag_identity) begin
                    assert(f_tag_seen && f_tag_positions == positions_q);
                    assert(digest_q[f_tag_chunk*32 +:32] == f_tag_value);
                end
                if (owner_q == READ_OWNER && f_tag_identity) begin
                    assert(f_tag_stored && f_tag_epoch == epoch_q && f_tag_positions == positions_q);
                    if ((state_q == TREAD || state_q == TCAP) && f_tag_chunk < chunk_q)
                        assert(expected_q[f_tag_chunk*32 +:32] == f_tag_value);
                end
                if (f_tag_expected_complete && f_tag_identity)
                    assert(expected_q[f_tag_chunk*32 +:32] == f_tag_value && f_tag_stored);
                if (f_tag_read_seen && f_tag_read_target)
                    assert(f_tag_stored && tag_data[f_tag_layer] == f_tag_value);
                if (state_q == TCAP)
                    assert(f_tag_read_seen && f_tag_read_target == (f_tag_identity && chunk_q == f_tag_chunk));
            end
        end
    end
