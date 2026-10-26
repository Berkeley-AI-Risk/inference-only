    // Accepted internal-write history. This monitor never drives the guard.
    reg f_wr_request, f_wr_stored, f_wr_published, f_wr_digest_seen;
    reg [63:0] f_wr_epoch;
    reg [2:0] f_wr_layer;
    reg [11:0] f_wr_position;
    reg f_wr_head;
    reg [3:0] f_wr_word;
    reg [255:0] f_wr_data, f_wr_digest;
    reg [4:0] f_wr_row_words;
    reg [2:0] f_wr_row_tags;
    reg [3:0] f_wr_tag_chunks;
    wire [4:0] f_wr_ordinal = {1'b0,row_word_q} + (head_q ? 5'd9 : 5'd0);
    wire [4:0] f_wr_next_ordinal = {1'b0,next_word_q} + (next_head_q ? 5'd9 : 5'd0);
    wire f_wr_hash_phase = owner_q == WRITE_OWNER && (state_q == HBEGIN ||
        state_q == HREAD || state_q == HCAP || state_q == HWORD ||
        state_q == HDIGEST || state_q == TWRITE);
    wire f_wr_publish = live && state_q == TWRITE && chunk_q == 7 && group_head_q && role_q;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            f_wr_request <= 0;
            f_wr_stored <= 0;
            f_wr_published <= 0;
            f_wr_digest_seen <= 0;
            f_wr_epoch <= 0;
            f_wr_layer <= 0;
            f_wr_position <= 0;
            f_wr_head <= 0;
            f_wr_word <= 0;
            f_wr_data <= 0;
            f_wr_digest <= 0;
            f_wr_row_words <= 0;
            f_wr_row_tags <= 0;
            f_wr_tag_chunks <= 0;
        end else begin
            if (clear_i || terminal_now) begin
                f_wr_request <= 0;
                f_wr_stored <= 0;
                f_wr_published <= 0;
                f_wr_digest_seen <= 0;
                f_wr_row_words <= 0;
                f_wr_row_tags <= 0;
                f_wr_tag_chunks <= 0;
            end
            if (s_wr_cpl_valid && s_wr_cpl_ready) f_wr_request <= 0;
            if (write_fire && wr_legal) begin
                f_wr_request <= 1;
                f_wr_stored <= 0;
                f_wr_epoch <= epoch_q;
                f_wr_layer <= s_wr_layer;
                f_wr_position <= s_wr_position;
                f_wr_head <= s_wr_head[0];
                f_wr_word <= s_wr_word;
                f_wr_data <= s_wr_data;
                if (!population_q) begin
                    f_wr_row_words <= 0;
                    f_wr_row_tags <= 0;
                    f_wr_published <= 0;
                end
            end
            if (live && state_q == WSTORE && chunk_q == 7) begin
                f_wr_stored <= 1;
                f_wr_row_words <= f_wr_row_words + 1'b1;
            end
            if (live && f_wr_hash_phase && state_q == HBEGIN) f_wr_digest_seen <= 0;
            if (live && state_q == HDIGEST && hash_write_q && hash_digest_valid) begin
                f_wr_digest_seen <= 1;
                f_wr_digest <= hash_digest;
                f_wr_tag_chunks <= 0;
            end
            if (tag_write) begin
                f_wr_tag_chunks <= f_wr_tag_chunks + 1'b1;
                if (chunk_q == 7) f_wr_row_tags <= f_wr_row_tags + 1'b1;
            end
            if (f_wr_publish) f_wr_published <= 1;
        end
    end

    always_comb begin
        if (reset_n) begin
            assert(prefix_q[0] <= 2048 && prefix_q[1] <= 2048 && prefix_q[2] <= 2048 &&
                   prefix_q[3] <= 2048 && prefix_q[4] <= 2048 && prefix_q[5] <= 2048);
            if (population_q) assert(lock_seen_q);
            if (!population_q) assert(next_head_q == 0 && next_word_q == 0);
            if (aborted_q) assert(!population_q && !cache_valid_q);
            if (aborted_q || !lock_seen_q)
                assert(prefix_q[0] == 0 && prefix_q[1] == 0 && prefix_q[2] == 0 &&
                       prefix_q[3] == 0 && prefix_q[4] == 0 && prefix_q[5] == 0);
            if (f_wr_request) assert(owner_q == WRITE_OWNER && lock_seen_q);
            if (live && population_q) begin
                assert(owner_q != READ_OWNER);
                assert(population_layer_q < 6 && population_position_q < 2048);
                assert(next_word_q < 9);
                assert(prefix_q[population_layer_q] == population_position_q + {11'd0,f_wr_published});
                assert(f_wr_row_words <= 18 && f_wr_row_tags <= 4);
                if (state_q == IDLE) begin
                    assert(!f_wr_published && f_wr_row_tags == 0);
                    assert(f_wr_row_words == f_wr_next_ordinal);
                end
            end
            if (live && owner_q == WRITE_OWNER) begin
                assert(f_wr_request && population_q);
                assert(layer_q == f_wr_layer && position_q == f_wr_position &&
                       head_q == f_wr_head && row_word_q == f_wr_word && epoch_q == f_wr_epoch);
                assert(word_q == f_wr_data);
                assert(layer_q == population_layer_q && position_q == population_position_q);
                assert(head_q == next_head_q && row_word_q == next_word_q);
                assert(page_q == position_q[10:4] && positions_q == {1'b0,position_q[3:0]} + 5'd1);
                if (state_q == WREQ || state_q == WWAIT || state_q == WSTORE) begin
                    assert(!f_wr_stored && !f_wr_published && f_wr_row_tags == 0);
                    assert(f_wr_row_words == f_wr_ordinal);
                end else begin
                    assert(f_wr_stored);
                    assert(f_wr_row_words == f_wr_ordinal + 1'b1);
                end
                if (state_q == WRETURN) begin
                    if (head_q && row_word_q == 8) assert(f_wr_published && f_wr_row_tags == 4);
                    else assert(!f_wr_published && f_wr_row_tags == 0);
                end
            end
            if (live && f_wr_hash_phase) begin
                assert(f_wr_stored && head_q && row_word_q == 8 && f_wr_row_words == 18);
                assert(!f_wr_published && f_wr_row_tags == {1'b0,group_head_q,role_q});
                assert(positions_q >= 1 && positions_q <= 16);
                assert(total_slots_q == {positions_q,2'b0} + {2'd0,positions_q});
                assert(hash_slot_q < total_slots_q && hash_position_q < positions_q && hash_group_word_q <= 4);
                assert(hash_slot_q == {1'b0,hash_position_q,2'b0} + {3'd0,hash_position_q} + {4'd0,hash_group_word_q});
                if (state_q == HBEGIN) assert(hash_slot_q == 0 && chunk_q == 0);
                if (state_q == HWORD || state_q == HDIGEST) assert(chunk_q == 0);
                if (state_q == HDIGEST || state_q == TWRITE) assert(hash_slot_q == total_slots_q - 1'b1);
            end
            if (tag_write) begin
                assert(f_wr_digest_seen && digest_q == f_wr_digest);
                assert(f_wr_tag_chunks == {1'b0,chunk_q});
                assert(f_wr_row_tags == {1'b0,group_head_q,role_q});
            end
            if (f_wr_publish) assert(f_wr_row_words == 18 && f_wr_row_tags == 3 && f_wr_tag_chunks == 7);
        end
    end
