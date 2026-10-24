    // Read-only verification state; no connections to production inputs.
    // One arbitrary constant address represents every word of the real RAM.
    (* anyconst *) reg [6:0] f_address;
    reg f_seen, f_previous_fault, f_epoch, f_written;
    reg f_checked, f_digest_equal, f_read_seen, f_read_target;
    reg f_consumer_pending;
    reg [6:0] f_consumer_address;
    reg [255:0] f_expected, f_word;
    reg [10:0] f_page;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            f_seen <= 0;
            f_previous_fault <= 0;
            f_epoch <= 0;
            f_written <= 0;
            f_checked <= 0;
            f_digest_equal <= 0;
            f_read_seen <= 0;
            f_read_target <= 0;
            f_consumer_pending <= 0;
            f_consumer_address <= 0;
            f_expected <= 0;
            f_word <= 0;
            f_page <= 0;
        end else begin
            f_seen <= 1;
            f_previous_fault <= fault_o;
            if (begin_fire) begin
                f_epoch <= 1;
                f_written <= 0;
                f_checked <= 0;
                f_digest_equal <= 0;
                f_read_seen <= 0;
                f_expected <= expected_digest_i;
                f_page <= begin_page_i;
            end
            if (memory_write && fill_count_q[6:0] == f_address) begin
                f_written <= 1;
                f_word <= memory_write_data;
            end
            if (state_q == HASH && sha_done && block_q == 64) begin
                f_checked <= 1;
                f_digest_equal <= sha_state == expected_q;
            end
            if (memory_read) begin
                f_read_seen <= 1;
                f_read_target <= memory_read_address == f_address;
            end
            if (read_fire && !read_error) f_consumer_address <= read_word_i;
            if (fault_o || protocol_error || digest_error || cancel_read_i || begin_fire)
                f_consumer_pending <= 0;
            else if (!response_valid_q || response_ready_i)
                f_consumer_pending <= read_fire && !read_error;
        end
    end

    always_comb begin
        if (reset_n) begin
            assert(state_q <= READY || state_q == FAILED);
            assert(fault_o == (state_q == FAILED));
            if (!f_seen) assert(state_q == EMPTY && !response_valid_q);
            if (f_previous_fault) assert(fault_o);
            if (fault_o)
                assert(!assigned_o && !verified_o && !read_ready_o &&
                       !response_valid_o && !begin_ready_o && !fill_ready_o);
            if (!verified_o) assert(!read_ready_o && !response_valid_o);
            if (!response_valid_o) assert(response_data_o == 0);
            if (cancel_read_i) assert(!response_valid_o && !read_ready_o);
            if (begin_fire) assert(!memory_read && !memory_write && !response_valid_q);
            if (assigned_o) begin
                assert(f_epoch && page_o == f_page && expected_q == f_expected);
                assert(page_o < PAGES);
                assert(valid_words_q == (page_o == PAGES-1 ? 118 : 128));
            end
            if (state_q == FILL || state_q == ZERO)
                assert(block_q == 0 && !f_read_seen && !f_checked);
            if (state_q == FILL) begin
                assert(fill_count_q < valid_words_q);
                assert(f_written == ({1'b0, f_address} < fill_count_q));
            end
            if (state_q == ZERO) begin
                assert(valid_words_q == 118 && fill_count_q >= 118 && fill_count_q < 128);
                assert(f_written == ({1'b0, f_address} < fill_count_q));
            end
            if (hash_active || verified_o) begin
                assert(fill_count_q == 128 && f_written);
                assert(!memory_write);
                assert(block_q <= 64);
            end
            if (state_q == READ0 || state_q == READ1 || state_q == CAP1)
                assert(block_q < 64);
            if (f_written) assert(memory_q[f_address] == f_word);
            if (state_q == COMPARE || verified_o) begin
                assert(block_q == 64 && f_checked);
                assert((&digest_match_q) == f_digest_equal);
            end
            if (verified_o) assert(f_checked && f_digest_equal);
            if (memory_read) assert(f_epoch && f_written && !memory_write);
            if (f_read_seen && f_read_target && (hash_active || verified_o))
                assert(read_data_q == f_word);
            if (state_q == READ1)
                assert(f_read_seen && f_read_target == (f_address == {block_q[5:0], 1'b0}));
            if (state_q == CAP1)
                assert(f_read_seen && f_read_target == (f_address == {block_q[5:0], 1'b1}));
            // The compressor captures the entire block on LAUNCH. During
            // HASH this private buffer is intentionally reused for the next
            // block; require that block's preparation separately below.
            if ((state_q == CAP1 || state_q == LAUNCH) &&
                block_q < 64 && f_address[6:1] == block_q[5:0] && !f_address[0])
                assert(sha_block_q[511:256] == bytes_big_endian(f_word));
            if (state_q == LAUNCH && block_q < 64 &&
                f_address[6:1] == block_q[5:0] && f_address[0])
                assert(sha_block_q[255:0] == bytes_big_endian(f_word));
            if ((state_q == LAUNCH || state_q == HASH) && block_q == 64)
                assert(sha_block_q == PADDING);
            if (state_q == HASH) begin
                assert(block_q < 63 ? (prefetch_q >= 1 && prefetch_q <= 4) : prefetch_q == 0);
                if (prefetch_q == 2)
                    assert(f_read_seen && f_read_target == (f_address == {next_block, 1'b0}));
                if (prefetch_q >= 3)
                    assert(f_read_seen && f_read_target == (f_address == {next_block, 1'b1}));
                if (prefetch_q >= 3 && f_address == {next_block, 1'b0})
                    assert(sha_block_q[511:256] == bytes_big_endian(f_word));
                if (prefetch_q == 4 && f_address == {next_block, 1'b1})
                    assert(sha_block_q[255:0] == bytes_big_endian(f_word));
            end
            assert(response_valid_q == f_consumer_pending);
            if (response_valid_q) begin
                assert(verified_o);
                assert(f_consumer_pending && f_read_seen && f_consumer_address < valid_words_q);
                assert(f_read_target == (f_consumer_address == f_address));
                if (response_valid_o && f_consumer_address == f_address) assert(response_data_o == f_word);
            end
        end
    end
