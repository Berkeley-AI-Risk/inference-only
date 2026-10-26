    // An arbitrary *observer* slot, not a replacement for any hardware value.
    // Every actual RAM bit and arithmetic child remains in the transition
    // system. The slot is constant along a trace and never drives the DUT.
    // Proving this for its unconstrained value covers all 2,049 physical slots.
    (* anyconst *) reg [11:0] f_tape_slot;
    wire f_slot_live = f_tape_slot < tape_count_q;
    wire [11:0] f_slot_observed = token_tape_q[f_tape_slot];
    reg f_slot_written;
    reg f_slot_is_result;
    reg [11:0] f_slot_expected;
    reg f_read_is_selected;
    reg [11:0] f_read_expected;

    // This independent one-slot transaction history records only logical
    // APPEND/result commitments. In particular, a raw RAM write coincident
    // with CLEAR is not a write in the new logical epoch. Physical memories
    // and tape_read_q are deliberately NOT reset or constrained by this proof.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            f_slot_written <= 0;
            f_slot_is_result <= 0;
            f_slot_expected <= 0;
            f_read_is_selected <= 0;
            f_read_expected <= 0;
        end else if (clear_i) begin
            f_slot_written <= 0;
            f_slot_is_result <= 0;
            f_slot_expected <= 0;
            f_read_is_selected <= 0;
            f_read_expected <= 0;
        end else begin
            if (f_tape_slot == tape_count_q) begin
                if (f_add_append) begin
                    f_slot_written <= 1;
                    f_slot_is_result <= 0;
                    f_slot_expected <= append_token_i;
                end else if (f_store_result) begin
                    f_slot_written <= 1;
                    f_slot_is_result <= 1;
                    f_slot_expected <= completing_winner;
                end
            end
            if (state_q == ST_TAPE_READ) begin
                f_read_is_selected <= replay_position_q == f_tape_slot;
                f_read_expected <= f_slot_expected;
            end
        end
    end

    always_comb begin
        if (rst_n) begin
            if (!f_seen_edge)
                assert(!f_slot_written && !f_slot_is_result && !f_read_is_selected);
            if (f_slot_live) begin
                assert(f_slot_written);
                assert(f_slot_observed == f_slot_expected);
                if (!fail_q) assert(f_slot_expected < 12'd4019);
            end
            if (f_read_is_selected) begin
                assert(f_slot_written);
                assert(tape_read_q == f_read_expected);
            end
            if (state_q == ST_EMBED_START && replay_position_q == f_tape_slot) begin
                assert(f_slot_live && f_slot_written);
                assert(f_read_is_selected);
                assert(tape_read_q == f_slot_expected);
            end
            if (state_q == ST_TOKEN_HOLD && f_tape_slot == tape_count_q - 12'd1) begin
                assert(f_slot_live && f_slot_written && f_slot_is_result);
                assert(f_slot_expected == generated_token_q);
            end
            if (token_valid_o && f_tape_slot == tape_count_q - 12'd1)
                assert(f_slot_observed == token_o);
            if (f_seen_edge && f_previous_clear)
                assert(!f_slot_written && !f_slot_is_result && !f_read_is_selected);
        end
    end
