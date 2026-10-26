    // Read-only taps from the actual page-hash registers. These assertions
    // connect the two local theorems; matching component names is not enough.
    wire [511:0] f_hash_expected_live = {128'h494f2d4b562d524f4c452d7632000000,epoch_q,
        29'd0,layer_q,25'd0,page_q,31'd0,group_head_q,31'd0,role_q,
        27'd0,positions_q,32'd16,32'd32,96'd0};
    wire [511:0] f_hash_expected_cache = {128'h494f2d4b562d524f4c452d7632000000,cache_epoch_q,
        29'd0,cache_layer_q,25'd0,cache_page_q,31'd0,cache_head_q,31'd0,cache_role_q,
        27'd0,cache_positions_q,32'd16,32'd32,96'd0};
    always_comb begin
        if (reset_n) begin
            if (live && f_stage_hash && state_q != HBEGIN) begin
                assert(f_hash_header == f_hash_expected_live);
                assert(f_hash_state != 0 && f_hash_state != 10);
                if (state_q == HDIGEST) assert(f_hash_words == total_slots_q);
                else assert(f_hash_words == hash_slot_q);
            end
            if (live && cache_valid_q) begin
                assert(f_hash_header == f_hash_expected_cache);
                assert(f_hash_words == total_slots_q);
                assert(f_hash_state == 0);
            end
        end
    end
