    // One arbitrary logical location observes the unchanged full partial RAM.
    // Invalid layer/word selectors are not assumed away; claims are guarded.
    (* anyconst *) reg [14:0] f_partial_select;
    wire [2:0] f_partial_layer = f_partial_select[14:12];
    wire [3:0] f_partial_position = f_partial_select[11:8];
    wire f_partial_head = f_partial_select[7];
    wire [3:0] f_partial_word = f_partial_select[6:3];
    wire [2:0] f_partial_chunk = f_partial_select[2:0];
    wire f_partial_shape = f_partial_layer < 6 && f_partial_word < 9;
    wire [8:0] f_partial_slot = partial_slot_for(f_partial_position,f_partial_head,f_partial_word);
    wire [13:0] f_partial_address = layer_base(f_partial_layer) + {2'd0,f_partial_slot,f_partial_chunk};
    wire [4:0] f_partial_ordinal = {1'b0,f_partial_word} + (f_partial_head ? 5'd9 : 5'd0);
    wire f_partial_population = population_q && population_layer_q == f_partial_layer;
    wire [11:0] f_partial_prefix = prefix_q[f_partial_layer];
    wire f_partial_current = f_partial_population || f_partial_prefix != 0;
    wire [11:0] f_partial_latest = f_partial_population ? population_position_q : f_partial_prefix - 1'b1;
    wire f_partial_required = f_partial_current &&
        (f_partial_position < f_partial_latest[3:0] ||
         (f_partial_position == f_partial_latest[3:0] &&
          (!f_partial_population || f_partial_ordinal < f_wr_row_words ||
           (f_partial_ordinal == f_wr_row_words && owner_q == WRITE_OWNER &&
            layer_q == f_partial_layer && state_q == WSTORE && f_partial_chunk < chunk_q))));
    wire f_partial_request_match = f_partial_shape && layer_q == f_partial_layer &&
        position_q[3:0] == f_partial_position && head_q == f_partial_head && row_word_q == f_partial_word;
    wire f_partial_hash_match = f_partial_shape && layer_q == f_partial_layer &&
        hash_position_q == f_partial_position && group_head_q == f_partial_head &&
        role_word(role_q,hash_group_word_q) == f_partial_word;
    wire f_partial_read = live && state_q == HREAD && hash_write_q;
    reg f_partial_received, f_partial_stored, f_partial_read_seen, f_partial_read_target;
    reg [31:0] f_partial_value;
    reg [63:0] f_partial_epoch;
    reg [6:0] f_partial_page;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            f_partial_received <= 0;
            f_partial_stored <= 0;
            f_partial_read_seen <= 0;
            f_partial_read_target <= 0;
            f_partial_value <= 0;
            f_partial_epoch <= 0;
            f_partial_page <= 0;
        end else begin
            if (clear_i || terminal_now || (write_fire && wr_legal && !population_q &&
                s_wr_layer == f_partial_layer && s_wr_position[3:0] == 0)) begin
                f_partial_received <= 0;
                f_partial_stored <= 0;
            end
            if (write_fire && wr_legal && f_partial_shape && s_wr_layer == f_partial_layer &&
                s_wr_position[3:0] == f_partial_position && s_wr_head == {1'b0,f_partial_head} &&
                s_wr_word == f_partial_word) begin
                f_partial_received <= 1;
                f_partial_stored <= 0;
                f_partial_value <= s_wr_data[f_partial_chunk*32 +:32];
                f_partial_epoch <= epoch_q;
                f_partial_page <= s_wr_position[10:4];
            end
            if (live && state_q == WSTORE && partial_address == f_partial_address && f_partial_shape)
                f_partial_stored <= 1;
            if (clear_i || terminal_now || write_fire || (live && f_wr_hash_phase && state_q == HBEGIN)) begin
                f_partial_read_seen <= 0;
                f_partial_read_target <= 0;
            end
            if (f_partial_read) begin
                f_partial_read_seen <= 1;
                f_partial_read_target <= partial_address == f_partial_address;
            end
        end
    end

    always_comb begin
        if (reset_n) begin
            if (f_partial_received) assert(lock_seen_q);
            if (f_partial_stored) assert(f_partial_received && f_partial_shape);
            if (aborted_q) assert(!f_partial_received && !f_partial_stored && !f_partial_read_seen);
            if (f_partial_read_seen) assert(lock_seen_q);
            if (f_partial_stored) assert(partial_memory[f_partial_address] == f_partial_value);
            if (live && f_partial_shape) begin
                assert(f_partial_stored == f_partial_required);
                if (f_partial_received) begin
                    assert(f_partial_current && f_partial_epoch == epoch_q);
                    assert(f_partial_page == f_partial_latest[10:4]);
                end
                if (owner_q == WRITE_OWNER && f_partial_request_match) begin
                    assert(f_partial_received && f_partial_page == page_q);
                    assert(f_partial_value == f_wr_data[f_partial_chunk*32 +:32]);
                end
                if (state_q == WSTORE) begin
                    assert(partial_address < 13824);
                    assert((partial_address == f_partial_address) ==
                           (f_partial_request_match && chunk_q == f_partial_chunk));
                end
                if (f_partial_read) begin
                    assert(partial_address < 13824);
                    assert((partial_address == f_partial_address) ==
                           (f_partial_hash_match && chunk_q == f_partial_chunk));
                end
                if (f_wr_hash_phase && f_partial_hash_match) begin
                    assert(f_partial_stored && f_partial_received);
                    assert(f_partial_page == page_q && f_partial_epoch == epoch_q);
                    if ((state_q == HREAD || state_q == HCAP) && f_partial_chunk < chunk_q)
                        assert(assembly_q[f_partial_chunk*32 +:32] == f_partial_value);
                    if (state_q == HWORD) assert(assembly_q[f_partial_chunk*32 +:32] == f_partial_value);
                end
                if (f_partial_read_seen && f_partial_read_target)
                    assert(f_partial_stored && partial_data_q == f_partial_value);
                if (f_wr_hash_phase && state_q == HCAP)
                    assert(f_partial_read_seen && f_partial_read_target == (partial_address == f_partial_address));
            end
        end
    end
