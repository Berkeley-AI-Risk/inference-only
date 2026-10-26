    // Read-only history of accepted inputs and completed compressor calls.
    // Arbitrary byte observer proves byte ordering for all 32 byte positions.
    (* anyconst *) reg [4:0] f_byte;
    reg f_active, f_previous_fault, f_previous_illegal;
    reg f_header_done, f_padding_done, f_low_valid, f_high_valid;
    reg [63:0] f_epoch;
    reg [2:0] f_layer;
    reg [6:0] f_page;
    reg f_head, f_role;
    reg [4:0] f_positions;
    reg [6:0] f_total, f_words, f_hashed_words, f_low_index;
    reg [255:0] f_low, f_high, f_chain;
    wire f_shape = layer_i < 6 && positions_i >= 1 && positions_i <= 16;
    wire f_waiting = state_q == HWAIT || state_q == DWAIT || state_q == PWAIT;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            f_active <= 0;
            f_previous_fault <= 0;
            f_previous_illegal <= 0;
            f_header_done <= 0;
            f_padding_done <= 0;
            f_low_valid <= 0;
            f_high_valid <= 0;
            f_epoch <= 0;
            f_layer <= 0;
            f_page <= 0;
            f_head <= 0;
            f_role <= 0;
            f_positions <= 0;
            f_total <= 0;
            f_words <= 0;
            f_hashed_words <= 0;
            f_low_index <= 0;
            f_low <= 0;
            f_high <= 0;
            f_chain <= 256'h6a09e667bb67ae853c6ef372a54ff53a510e527f9b05688c1f83d9ab5be0cd19;
        end else begin
            f_previous_fault <= fault_o;
            f_previous_illegal <= begin_fire && !f_shape;
            if (clear_i && state_q != FAULT) begin
                f_active <= 0;
                f_header_done <= 0;
                f_padding_done <= 0;
                f_low_valid <= 0;
                f_high_valid <= 0;
                f_total <= 0;
                f_words <= 0;
                f_hashed_words <= 0;
                f_chain <= 256'h6a09e667bb67ae853c6ef372a54ff53a510e527f9b05688c1f83d9ab5be0cd19;
            end else if (!clear_i && state_q != FAULT) begin
                if (digest_valid_o && digest_ready_i) f_active <= 0;
                if (begin_fire && f_shape) begin
                    f_active <= 1;
                    f_epoch <= epoch_i;
                    f_layer <= layer_i;
                    f_page <= page_i;
                    f_head <= head_i;
                    f_role <= role_i;
                    f_positions <= positions_i;
                    f_total <= {positions_i,2'b0} + {2'd0,positions_i};
                    f_words <= 0;
                    f_hashed_words <= 0;
                    f_header_done <= 0;
                    f_padding_done <= 0;
                    f_low_valid <= 0;
                    f_high_valid <= 0;
                    f_chain <= 256'h6a09e667bb67ae853c6ef372a54ff53a510e527f9b05688c1f83d9ab5be0cd19;
                end
                if (word_fire) begin
                    f_words <= f_words + 1'b1;
                    if (state_q == LOW) begin
                        f_low <= word_i;
                        f_low_index <= f_words;
                        f_low_valid <= 1;
                        f_high_valid <= 0;
                    end else begin
                        f_high <= word_i;
                        f_high_valid <= 1;
                    end
                end
                if (f_waiting && sha_done) f_chain <= sha_state;
                if (state_q == HWAIT && sha_done) f_header_done <= 1;
                if (state_q == DWAIT && sha_done) begin
                    f_hashed_words <= f_words;
                    if (final_data_block_q) f_padding_done <= 1;
                end
                if (state_q == PWAIT && sha_done) f_padding_done <= 1;
            end
        end
    end

    always_comb begin
        if (reset_n) begin
            assert(state_q <= FAULT);
            if (f_previous_fault || f_previous_illegal) assert(fault_o);
            if (fault_o || clear_i)
                assert(!begin_ready_o && !word_ready_o && !digest_valid_o && !sha_start);
            if (!digest_valid_o) assert(digest_o == 0);
            assert(hash_q == f_chain);
            assert(words_q == f_words && total_words_q == f_total);
            if (state_q != IDLE && state_q != FAULT) assert(f_active);
            if (f_active) begin
                assert(state_q != IDLE && state_q != FAULT);
                assert(f_layer < 6 && f_positions >= 1 && f_positions <= 16);
                assert(f_total == {f_positions,2'b0} + {2'd0,f_positions});
                assert(f_words <= f_total && f_hashed_words <= f_words);
                assert(header_q[511:384] == 128'h494f2d4b562d524f4c452d7632000000);
                assert(header_q[383:320] == f_epoch);
                assert(header_q[319:288] == {29'd0,f_layer});
                assert(header_q[287:256] == {25'd0,f_page});
                assert(header_q[255:224] == {31'd0,f_head});
                assert(header_q[223:192] == {31'd0,f_role});
                assert(header_q[191:160] == {27'd0,f_positions});
                assert(header_q[159:128] == 32'd16 && header_q[127:96] == 32'd32 && header_q[95:0] == 0);
                assert(length_bits_q == 64'd512 + {49'd0,f_positions,10'd0} + {51'd0,f_positions,8'd0});
                if (state_q == HSTART || state_q == HWAIT) begin
                    assert(!f_header_done && !f_padding_done && f_words == 0 && f_hashed_words == 0 &&
                           !final_data_block_q && !f_low_valid && !f_high_valid);
                    assert(hash_q == 256'h6a09e667bb67ae853c6ef372a54ff53a510e527f9b05688c1f83d9ab5be0cd19);
                end else assert(f_header_done);
                if (state_q == HSTART) assert(sha_block == header_q);
                if (state_q == LOW || state_q == HIGH) begin
                    assert(f_words < f_total && !f_padding_done && !final_data_block_q);
                    assert(f_words[0] == (state_q == HIGH));
                end
                if (state_q == LOW) assert(f_hashed_words == f_words);
                if (state_q == HIGH) begin
                    assert({1'b0,f_hashed_words} + 8'd1 == {1'b0,f_words});
                    assert(f_low_valid && !f_high_valid && f_low_index + 1'b1 == f_words);
                    assert(block_q[511-f_byte*8 -:8] == f_low[f_byte*8 +:8]);
                end
                if (state_q == DSTART || state_q == DWAIT) begin
                    assert(!f_padding_done && f_low_valid && !f_low_index[0]);
                    assert(final_data_block_q == (f_words[0] && f_words == f_total));
                    assert(block_q[511-f_byte*8 -:8] == f_low[f_byte*8 +:8]);
                    if (final_data_block_q) begin
                        assert({1'b0,f_hashed_words} + 8'd1 == {1'b0,f_words});
                        assert(f_low_index + 1'b1 == f_words && !f_high_valid);
                        assert(block_q[255:0] == {1'b1,191'd0,length_bits_q});
                    end else begin
                        assert({1'b0,f_hashed_words} + 8'd2 == {1'b0,f_words});
                        assert(f_low_index + 7'd2 == f_words && f_high_valid && !f_words[0]);
                        assert(block_q[255-f_byte*8 -:8] == f_high[f_byte*8 +:8]);
                    end
                end
                if (state_q == DSTART) assert(sha_block == block_q);
                if (state_q == PSTART || state_q == PWAIT) begin
                    assert(!f_words[0] && !f_padding_done && !final_data_block_q);
                    assert(f_hashed_words == f_words && f_words == f_total);
                end
                if (state_q == PSTART) assert(sha_block == {1'b1,447'd0,length_bits_q});
                if (state_q == RESULT)
                    assert(f_padding_done && f_hashed_words == f_total && f_words == f_total);
                if (digest_valid_o) assert(digest_o == f_chain);
            end
        end
    end
