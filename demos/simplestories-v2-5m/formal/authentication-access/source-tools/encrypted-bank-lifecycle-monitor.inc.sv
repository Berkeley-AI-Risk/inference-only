    // This observer input is wired only to the actual containing service's
    // !fault_o. It controls no native decision; a terminal shared fault closes
    // every externally usable service response for the rest of this epoch.
    (* anyconst *) logic [6:0] f_life_address;
    logic f_life_epoch_q,f_life_written_q,f_life_plain_q,f_life_hashed_q;
    logic [255:0] f_life_word_q,f_life_expected_q;
    logic [10:0] f_life_page_q;
    logic [6:0] f_life_calls_q,f_life_returns_q;
    logic f_life_checked_q,f_life_equal_q;
    logic f_life_read_seen_q,f_life_read_target_q;
    logic [255:0] f_life_read_value_q;
    logic f_life_consumer_pending_q;
    logic [6:0] f_life_consumer_address_q;
    wire [6:0] f_life_write_address=state_q==CR_STORE ? crypto_word_q : fill_count_q[6:0];
    wire f_life_call=hash_request_valid_o && hash_request_ready_i;
    wire f_life_crypto=state_q==CR_READ || state_q==CR_LOW || state_q==CR_WAITL ||
        state_q==CR_HIGH || state_q==CR_WAITH || state_q==CR_STORE;
    wire f_life_prepare=state_q==READ0 || state_q==READ1 || state_q==CAP1 || state_q==LAUNCH;
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            f_life_epoch_q<=0;f_life_written_q<=0;f_life_plain_q<=0;f_life_hashed_q<=0;
            f_life_word_q<=0;f_life_expected_q<=0;f_life_page_q<=0;
            f_life_calls_q<=0;f_life_returns_q<=0;f_life_checked_q<=0;f_life_equal_q<=0;
            f_life_read_seen_q<=0;f_life_read_target_q<=0;f_life_read_value_q<=0;
            f_life_consumer_pending_q<=0;f_life_consumer_address_q<=0;
        end else begin
            if(begin_fire) begin
                f_life_epoch_q<=1;f_life_written_q<=0;f_life_plain_q<=0;f_life_hashed_q<=0;
                f_life_expected_q<=expected_digest_i;f_life_page_q<=begin_page_i;
                f_life_calls_q<=0;f_life_returns_q<=0;f_life_checked_q<=0;f_life_equal_q<=0;
            end else begin
                if(f_life_call) begin
                    f_life_calls_q<=f_life_calls_q+7'd1;
                    if(block_q<64 && f_life_address[6:1]==block_q[5:0]) f_life_hashed_q<=1;
                end
                if(sha_done) begin
                    f_life_returns_q<=f_life_returns_q+7'd1;
                    if(block_q==64) begin f_life_checked_q<=1;f_life_equal_q<=sha_state==expected_q;end
                end
            end
            if(memory_write && f_life_write_address==f_life_address) begin
                f_life_written_q<=1;f_life_word_q<=memory_write_data;
                if(state_q==CR_STORE || state_q==ZERO) f_life_plain_q<=1;
            end
            if(memory_read) begin
                f_life_read_seen_q<=1;f_life_read_target_q<=memory_read_address==f_life_address;
                f_life_read_value_q<=f_life_word_q;
            end
            if(read_fire && !read_error) f_life_consumer_address_q<=read_word_i;
            if(fault_o || protocol_error || digest_error || cancel_read_i || begin_fire)
                f_life_consumer_pending_q<=0;
            else if(!response_valid_q || response_ready_i)
                f_life_consumer_pending_q<=read_fire && !read_error;
        end
    end
    always_ff @(posedge clk) if(reset_n && f_service_active_i && !fault_o) begin
        assert(f_life_calls_q<=65 && f_life_returns_q<=65 && f_life_returns_q<=f_life_calls_q);
        assert(f_life_calls_q==f_life_returns_q || f_life_calls_q==f_life_returns_q+7'd1);
        assert(f_hash_owned_q==(f_life_calls_q!=f_life_returns_q));
        assert(f_hash_owned_q==hash_pending_i);
        assert(block_q==(f_life_returns_q<65 ? f_life_returns_q : 7'd64));
        assert(response_valid_q==f_life_consumer_pending_q);
        if(response_valid_q) begin
            assert(verified_o && f_life_consumer_address_q<valid_words_q);
            if(f_life_consumer_address_q==f_life_address)
                assert(f_life_read_seen_q && f_life_read_target_q && f_life_read_value_q==f_life_word_q && read_data_q==f_life_word_q);
        end
        assert(!f_life_plain_q || f_life_written_q);
        if(f_life_hashed_q) assert(f_life_plain_q && f_life_written_q);
        if(state_q==PAIR_READY) assert(f_life_calls_q<64);
        if(state_q==READ0 || state_q==READ1 || state_q==CAP1) assert(block_q<64);
        if(assigned_o) begin
            assert(f_life_epoch_q && page_o==f_life_page_q && expected_q==f_life_expected_q && page_o<PAGES);
            assert(valid_words_q==(page_o==PAGES-1 ? 118 : 128));
            assert(f_life_hashed_q==({1'b0,f_life_address[6:1]}<f_life_calls_q));
            if(state_q==FILL) begin
                assert(fill_count_q<valid_words_q);
                assert(f_life_written_q==({1'b0,f_life_address}<fill_count_q));
            end else if(!all_plaintext_q && state_q!=ZERO) begin
                assert(fill_count_q==valid_words_q);
                assert(f_life_written_q==({1'b0,f_life_address}<valid_words_q));
            end
            if(!all_plaintext_q) begin
                assert({1'b0,crypto_word_q}<=valid_words_q);
                assert({1'b0,crypto_word_q}>={f_life_calls_q,1'b0});
                if(state_q==ZERO) begin
                    assert(valid_words_q==118 && crypto_word_q==118 && f_life_calls_q==58);
                    assert(fill_count_q>=118 && fill_count_q<128);
                    assert(f_life_plain_q==({1'b0,f_life_address}<fill_count_q));
                    assert(f_life_written_q==({1'b0,f_life_address}<fill_count_q));
                end else assert(f_life_plain_q==(f_life_address<crypto_word_q));
                if(state_q==FILL) assert(crypto_word_q==0 && f_life_calls_q==0 && f_life_returns_q==0);
                if(f_life_crypto) begin
                    assert({1'b0,crypto_word_q}<valid_words_q);
                    assert({1'b0,crypto_word_q[6:1]}==f_life_calls_q);
                end
                if(state_q==PAIR_READY || f_life_prepare) begin
                    assert({1'b0,crypto_word_q}<valid_words_q);
                    assert({1'b0,crypto_word_q}=={f_life_calls_q,1'b0}+8'd2);
                end
            end else begin
                assert((state_q>=READ0 && state_q<=READY) || state_q==PAIR_READY);
                assert(fill_count_q==128);
                assert(f_life_plain_q);
            end
        end
        if(state_q==HASH) assert(all_plaintext_q);
        if(f_life_prepare) assert(f_life_calls_q==f_life_returns_q && f_life_calls_q==block_q);
        if(state_q==COMPARE || verified_o) begin
            assert(all_plaintext_q && f_life_calls_q==65 && f_life_returns_q==65 && f_life_checked_q);
            assert((&digest_match_q)==f_life_equal_q);
        end
        if(verified_o) assert(f_life_equal_q && f_life_plain_q && f_life_hashed_q);
        if(f_life_written_q) assert(memory_q[f_life_address]==f_life_word_q);
        if(f_life_hashed_q && !begin_fire) assert(!(memory_write && f_life_write_address==f_life_address));
        if(assigned_o && f_life_plain_q && {1'b0,f_life_address}>=valid_words_q) assert(f_life_word_q==0);
        if(memory_read) begin
            assert(!memory_write);
            if(memory_read_address==f_life_address) assert(f_life_written_q);
        end
        if(f_life_read_seen_q && f_life_read_target_q) assert(read_data_q==f_life_read_value_q);
        if(state_q==READ1 && f_life_address=={block_q[5:0],1'b0})
            assert(f_life_read_seen_q && f_life_read_target_q && f_life_plain_q && f_life_read_value_q==f_life_word_q);
        if(state_q==CAP1 && f_life_address=={block_q[5:0],1'b1})
            assert(f_life_read_seen_q && f_life_read_target_q && f_life_plain_q && f_life_read_value_q==f_life_word_q);
        if((state_q==CAP1 || state_q==LAUNCH) && block_q<64 && f_life_address[6:1]==block_q[5:0] && !f_life_address[0])
            assert(f_life_plain_q && sha_block_q[511:256]==bytes_big_endian(f_life_word_q));
        if(state_q==LAUNCH && block_q<64 && f_life_address[6:1]==block_q[5:0] && f_life_address[0])
            assert(f_life_plain_q && sha_block_q[255:0]==bytes_big_endian(f_life_word_q));
        if(state_q==LAUNCH && block_q==64) assert(all_plaintext_q && sha_block_q==PADDING);
        if(!verified_o) assert(!read_ready_o && !response_valid_o);
        if(!response_valid_o) assert(response_data_o==0);
        if(cancel_read_i) assert(!read_ready_o && !response_valid_o);
        if(response_valid_o) begin
            assert(verified_o && f_life_consumer_pending_q && f_life_consumer_address_q<valid_words_q);
            if(f_life_consumer_address_q==f_life_address)
                assert(f_life_read_target_q && f_life_read_value_q==f_life_word_q && response_data_o==f_life_word_q);
        end
    end
