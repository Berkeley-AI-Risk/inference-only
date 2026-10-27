    // Read-only histories of accepted input and actual SHA-byte transfers.
    // Native state/dimensions and the complete SHA child remain unchanged.
    logic [18:0] f_words_q;
    logic [23:0] f_payload_bytes_q;
    logic [6:0] f_padding_bytes_q;
    logic [255:0] f_captured_word_q;
    logic [4:0] f_byte_q;
    logic f_digest_match_seen_q;
    logic f_begin_seen_q;
    wire [23:0] f_pending_bytes = word_buffer_valid_q ?
        24'd32 - {19'd0,word_byte_q} : 24'd0;
    wire [23:0] f_received_bytes = {1'b0,f_words_q,5'd0};
    wire [7:0] f_expected_pad = f_padding_bytes_q==0 ? 8'h80 :
        (f_padding_bytes_q<56 ? 8'h00 :
        (f_padding_bytes_q==56 ? 8'h00 :
        (f_padding_bytes_q==57 ? 8'h00 :
        (f_padding_bytes_q==58 ? 8'h00 :
        (f_padding_bytes_q==59 ? 8'h00 :
        (f_padding_bytes_q==60 ? 8'h03 :
        (f_padding_bytes_q==61 ? 8'h76 :
        (f_padding_bytes_q==62 ? 8'hf6 : 8'h00))))))));
    always_ff @(posedge trusted_clk_i or negedge trusted_reset_n_i) begin
        if(!trusted_reset_n_i) begin
            f_words_q<=0;
            f_payload_bytes_q<=0;
            f_padding_bytes_q<=0;
            f_captured_word_q<=0;
            f_byte_q<=0;
            f_digest_match_seen_q<=0;
            f_begin_seen_q<=0;
        end else begin
            if(sha_begin) f_begin_seen_q<=1;
            if(word_transfer) begin
                f_words_q<=f_words_q+19'd1;
                f_captured_word_q<=readback_word_data_i;
                f_byte_q<=0;
            end
            if(byte_transfer && state_q==ST_WORDS) begin
                f_payload_bytes_q<=f_payload_bytes_q+24'd1;
                f_byte_q<=f_byte_q+5'd1;
            end
            if(byte_transfer && state_q==ST_PADDING)
                f_padding_bytes_q<=f_padding_bytes_q+7'd1;
            if(sha_digest_valid && sha_digest==
                256'hcad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0 &&
                f_payload_bytes_q==24'd7265984 && f_padding_bytes_q==7'd64 &&
                !sha_fault && !last_protocol_fault && !extra_word_fault)
                f_digest_match_seen_q<=1;
        end
    end

    logic f_past_valid=0;
    always_ff @(posedge trusted_clk_i) begin
        f_past_valid<=1;
        if(trusted_reset_n_i) begin
            assert(state_q==ST_INIT || state_q==ST_WORDS || state_q==ST_PADDING ||
                state_q==ST_WAIT_HASH || state_q==ST_DONE || state_q==ST_FAIL);
            assert(words_accepted_q<=18'd227062);
            assert(f_begin_seen_q==(state_q!=ST_INIT));
            if(sha_begin) assert(!f_begin_seen_q);
            assert(fail_q==(state_q==ST_FAIL));
            assert(done_q==(state_q==ST_DONE || state_q==ST_FAIL));
            assert(ok_q==(state_q==ST_DONE));
            assert(!fail_q || !word_buffer_valid_q);
            assert(f_payload_bytes_q<=24'd7265984);
            assert(f_padding_bytes_q<=7'd64);
            assert(digest_ok_o==(done_q && ok_q && !fail_q));
            assert(!digest_ok_o || f_digest_match_seen_q);
            assert(!digest_ok_o || (f_words_q==19'd227062 &&
                f_payload_bytes_q==24'd7265984 && f_padding_bytes_q==7'd64));
            assert(!fail_closed_o || (digest_done_o && !digest_ok_o));
            assert(!word_transfer || (!word_buffer_valid_q && state_q==ST_WORDS));
            assert(!sha_begin || state_q==ST_INIT);
            assert(!sha_byte_last || (state_q==ST_PADDING && f_padding_bytes_q==63));
            if(!fail_q) begin
                // A malformed LAST may handshake and immediately cause failure;
                // that rejected word is not committed to the production count.
                assert(f_words_q=={1'b0,words_accepted_q});
                assert((state_q==ST_FAIL)==1'b0);
                assert((state_q==ST_DONE)==digest_ok_o);
                if(state_q==ST_INIT) begin
                    assert(f_words_q==0 && f_payload_bytes_q==0 && f_padding_bytes_q==0);
                end
                if(state_q==ST_WORDS) begin
                    assert(f_payload_bytes_q+f_pending_bytes==f_received_bytes);
                    assert(f_padding_bytes_q==0);
                    assert(!word_buffer_valid_q || word_buffer_q==f_captured_word_q);
                    assert(!word_buffer_valid_q || word_byte_q==f_byte_q);
                    assert(!word_buffer_valid_q || (word_buffer_final_q==(f_words_q==227062)));
                    assert(!byte_transfer || (f_payload_bytes_q<7265984 &&
                        sha_byte_data==f_captured_word_q[f_byte_q*8 +: 8] && !sha_byte_last));
                end
                if(state_q==ST_PADDING || state_q==ST_WAIT_HASH || state_q==ST_DONE) begin
                    assert(f_words_q==227062 && f_payload_bytes_q==7265984);
                    assert(!word_buffer_valid_q);
                end
                if(state_q==ST_PADDING) begin
                    assert(f_padding_bytes_q=={1'b0,padding_byte_q});
                    assert(f_padding_bytes_q<64);
                    assert(!byte_transfer || sha_byte_data==f_expected_pad);
                end
                if(state_q==ST_WAIT_HASH || state_q==ST_DONE)
                    assert(f_padding_bytes_q==64);
            end
            if(f_past_valid && $past(trusted_reset_n_i)) begin
                if($past(fail_q)) assert(fail_q);
                if($past(digest_ok_o) && !fail_q) assert(digest_ok_o);
            end
            cover(word_transfer);
            cover(byte_transfer && state_q==ST_WORDS);
            cover(fail_closed_o);
        end
    end
