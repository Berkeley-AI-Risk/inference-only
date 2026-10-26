    // Actual write-hash identity and word count, observed without input cuts.
    always_comb begin
        if (reset_n && live && f_wr_hash_phase && state_q != HBEGIN) begin
            assert(f_hash_header == f_hash_expected_live);
            if (state_q == TWRITE) begin
                assert(f_hash_state == 0);
                assert(f_hash_words == total_slots_q);
            end else begin
                assert(f_hash_state != 0 && f_hash_state != 10);
                if (state_q == HDIGEST) assert(f_hash_words == total_slots_q);
                else assert(f_hash_words == hash_slot_q);
            end
        end
    end
