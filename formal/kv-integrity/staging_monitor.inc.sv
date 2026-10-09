    // One arbitrary constant address covers every 32-bit staging-RAM word.
    // Out-of-range observer addresses are not assumed away; claims are guarded.
    (* anyconst *) reg [9:0] f_stage_address;
    wire [6:0] f_stage_slot = f_stage_address[9:3];
    wire [2:0] f_stage_chunk = f_stage_address[2:0];
    wire f_stage_miss = read_fire && rd_legal && !cache_hit;
    wire f_stage_fill = state_q == RREQ || state_q == RWAIT || state_q == RSTORE;
    wire f_stage_hash = owner_q == READ_OWNER && (state_q == HBEGIN ||
        state_q == HREAD || state_q == HCAP || state_q == HWORD || state_q == HDIGEST);
    wire f_stage_read = live && ((state_q == HREAD && !hash_write_q) || state_q == OREAD);
    wire f_stage_write = live && state_q == RSTORE;
    reg f_stage_active, f_stage_written, f_stage_hashed;
    reg f_stage_read_seen, f_stage_read_target;
    reg [6:0] f_stage_total;
    reg [31:0] f_stage_value, f_stage_hash_value;
    reg f_stage_request;
    reg [63:0] f_stage_request_epoch;
    reg [2:0] f_stage_request_layer;
    reg [11:0] f_stage_request_position;
    reg f_stage_request_head;
    reg [3:0] f_stage_request_word;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            f_stage_active <= 0;
            f_stage_written <= 0;
            f_stage_hashed <= 0;
            f_stage_read_seen <= 0;
            f_stage_read_target <= 0;
            f_stage_total <= 0;
            f_stage_value <= 0;
            f_stage_hash_value <= 0;
            f_stage_request <= 0;
            f_stage_request_epoch <= 0;
            f_stage_request_layer <= 0;
            f_stage_request_position <= 0;
            f_stage_request_head <= 0;
            f_stage_request_word <= 0;
        end else begin
            if (clear_i || terminal_now || (s_rd_rsp_valid && s_rd_rsp_ready))
                f_stage_request <= 0;
            if (read_fire && rd_legal) begin
                f_stage_request <= 1;
                f_stage_request_epoch <= epoch_q;
                f_stage_request_layer <= s_rd_layer;
                f_stage_request_position <= s_rd_position;
                f_stage_request_head <= s_rd_head[0];
                f_stage_request_word <= s_rd_word;
            end
            if (clear_i || terminal_now || write_fire || f_stage_miss) begin
                f_stage_active <= f_stage_miss;
                f_stage_written <= 0;
                f_stage_hashed <= 0;
                f_stage_read_seen <= 0;
                f_stage_read_target <= 0;
            end
            if (f_stage_miss)
                f_stage_total <= {read_positions,2'b0} + {2'd0,read_positions};
            if (f_stage_write && stage_address == f_stage_address) begin
                f_stage_written <= 1;
                f_stage_value <= word_q[chunk_q*32 +:32];
            end
            if (f_stage_read) begin
                f_stage_read_seen <= 1;
                f_stage_read_target <= stage_address == f_stage_address;
            end
            if (live && f_stage_hash && state_q == HWORD && hash_word_ready &&
                hash_slot_q == f_stage_slot) begin
                f_stage_hashed <= 1;
                f_stage_hash_value <= assembly_q[f_stage_chunk*32 +:32];
            end
        end
    end

    always_comb begin
        if (reset_n) begin
            if (f_stage_active) assert(lock_seen_q);
            if (aborted_q) assert(!cache_valid_q && !f_stage_active);
            if (f_stage_request) assert(owner_q == READ_OWNER && lock_seen_q);
            if (live && owner_q == READ_OWNER) begin
                assert(f_stage_request);
                assert(f_stage_request_layer < 6 && f_stage_request_position < 2048 &&
                       f_stage_request_word < 9);
                assert(layer_q == f_stage_request_layer && page_q == f_stage_request_position[10:4] &&
                       group_head_q == f_stage_request_head && epoch_q == f_stage_request_epoch);
                assert(target_slot_q == role_slot(f_stage_request_position[3:0], f_stage_request_word));
                if (f_stage_request_word != 8) assert(role_q == f_stage_request_word[2]);
            end
            if (rd_legal) begin
                assert(read_positions >= 1 && read_positions <= 16);
                assert({1'b0,s_rd_position[3:0]} < read_positions);
            end
            if (live && owner_q == READ_OWNER) assert(f_stage_active);
            if (live && cache_valid_q) assert(f_stage_active);
            if (f_stage_active && f_stage_written && f_stage_address < 640)
                assert(stage_memory[f_stage_address] == f_stage_value);
            if (live && f_stage_active) begin
                assert(f_stage_total >= 5 && f_stage_total <= 80);
                assert(total_slots_q == f_stage_total);
                assert(total_slots_q == {positions_q,2'b0} + {2'd0,positions_q});
                assert(positions_q >= 1 && positions_q <= 16);
                assert(target_slot_q < total_slots_q);
                assert(f_stage_fill || state_q == TREAD || state_q == TCAP ||
                       f_stage_hash || state_q == OREAD || state_q == OCAP ||
                       state_q == RRETURN || state_q == IDLE);
                if (state_q == IDLE) assert(cache_valid_q);
                if (cache_valid_q) assert(cache_positions_q == positions_q);
                if (f_stage_written) assert(f_stage_slot < f_stage_total);
                if (f_stage_hashed) begin
                    assert(f_stage_written && !f_stage_fill);
                    assert(f_stage_hash_value == f_stage_value);
                end
                if (f_stage_fill) begin
                    assert(scan_slot_q < total_slots_q);
                    if (state_q != RSTORE) assert(chunk_q == 0);
                    assert(f_stage_written == (f_stage_address < {scan_slot_q,chunk_q}));
                    assert(!f_stage_hashed && !f_stage_read_seen);
                end else if (f_stage_slot < f_stage_total) assert(f_stage_written);
                if (state_q == TREAD || state_q == TCAP)
                    assert(!f_stage_hashed && !f_stage_read_seen);
                if (f_stage_hash) begin
                    assert(!hash_write_q && hash_slot_q < total_slots_q);
                    if (state_q == HBEGIN) assert(hash_slot_q == 0 && chunk_q == 0);
                    if (state_q == HWORD || state_q == HDIGEST) assert(chunk_q == 0);
                    if (state_q == HDIGEST) begin
                        assert(hash_slot_q == total_slots_q - 1'b1);
                        if (f_stage_slot < f_stage_total) assert(f_stage_hashed);
                    end else assert(f_stage_hashed == (f_stage_slot < hash_slot_q));
                end
                if (cache_valid_q && f_stage_slot < f_stage_total) assert(f_stage_hashed);
                if (f_stage_read) begin
                    assert(stage_address < 640 && stage_slot < total_slots_q);
                    assert(!f_stage_write);
                    if (stage_address == f_stage_address) assert(f_stage_written);
                end
                if (f_stage_read_seen && f_stage_read_target)
                    assert(f_stage_written && stage_data_q == f_stage_value);
                if ((f_stage_hash && state_q == HCAP) || state_q == OCAP)
                    assert(f_stage_read_seen &&
                           f_stage_read_target == (stage_address == f_stage_address));
                if (f_stage_hash && (state_q == HREAD || state_q == HCAP) &&
                    f_stage_slot == hash_slot_q && f_stage_chunk < chunk_q)
                    assert(assembly_q[f_stage_chunk*32 +:32] == f_stage_value);
                if (f_stage_hash && state_q == HWORD && f_stage_slot == hash_slot_q)
                    assert(f_stage_written && assembly_q[f_stage_chunk*32 +:32] == f_stage_value);
                if ((state_q == OREAD || state_q == OCAP) &&
                    f_stage_slot == target_slot_q && f_stage_chunk < chunk_q)
                    assert(assembly_q[f_stage_chunk*32 +:32] == f_stage_value);
                if (state_q == RRETURN && f_stage_slot == target_slot_q) begin
                    assert(f_stage_hashed && f_stage_written);
                    assert(s_rd_rsp_data[f_stage_chunk*32 +:32] == f_stage_hash_value);
                end
            end
        end
    end
