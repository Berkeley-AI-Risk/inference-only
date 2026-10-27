    // One BEGIN per hard-reset epoch is the sole client premise. The actual
    // image-auth caller proves it separately; byte data and stalls stay free.
    logic f_begin_seen_q;
    logic [5:0] f_index_q;
    logic [503:0] f_bytes_q;
    logic [511:0] f_expected_block_q;
    logic [255:0] f_chain_q, f_expected_chain_q;
    logic f_pending_q, f_last_q, f_end_seen_q;
    wire f_legal_begin=begin_i && (state_q==ST_IDLE || state_q==ST_DONE);
    wire f_byte=byte_valid_i && byte_ready_o && !begin_i && !compressor_protocol_fault;
    always_ff @(posedge clk_i or negedge reset_n_i) begin
        if(!reset_n_i) begin
            f_begin_seen_q<=0;f_index_q<=0;f_bytes_q<=0;
            f_expected_block_q<=0;f_chain_q<=INITIAL_HASH;f_expected_chain_q<=INITIAL_HASH;
            f_pending_q<=0;f_last_q<=0;f_end_seen_q<=0;
        end else begin
            if(begin_i) f_begin_seen_q<=1;
            if(f_legal_begin) begin
                f_index_q<=0;f_bytes_q<=0;f_chain_q<=INITIAL_HASH;
                f_pending_q<=0;f_end_seen_q<=0;
            end else begin
                if(f_byte) begin
                    f_bytes_q<={f_bytes_q[495:0],byte_data_i};
                    if(!(byte_last_i && f_index_q!=63)) begin
                        if(f_index_q==63) begin
                            f_expected_block_q<={f_bytes_q,byte_data_i};
                            f_expected_chain_q<=f_chain_q;
                            f_pending_q<=1;f_last_q<=byte_last_i;f_index_q<=0;
                        end else f_index_q<=f_index_q+6'd1;
                    end
                end
                if(state_q==ST_WAIT && compress_done && !begin_i && !compressor_protocol_fault) begin
                    f_chain_q<=compress_result;f_pending_q<=0;
                    if(f_last_q) f_end_seen_q<=1;
                end
            end
        end
    end
    always_ff @(posedge clk_i) if(reset_n_i) begin
        assume(!begin_i || !f_begin_seen_q);
        assert(f_begin_seen_q==(state_q!=ST_IDLE));
        assert(hash_state_q==f_chain_q);
        assert(block_buffer_q==f_bytes_q);
        assert(byte_index_q==f_index_q);
        assert(!(compress_busy && compress_done));
        if(compress_busy || compress_done)
            assert(state_q==ST_WAIT || (state_q==ST_DONE && fault_o));
        if(state_q==ST_WAIT) assert(compress_start_q || compress_busy || compress_done);
        if(fault_o) assert(state_q==ST_DONE && !byte_ready_o && !digest_valid_o);
        if(state_q==ST_IDLE) assert(!f_begin_seen_q && !f_pending_q && !compress_start_q);
        if(state_q==ST_COLLECT) assert(f_begin_seen_q && !fault_o && !f_pending_q && !compress_start_q);
        if(state_q==ST_WAIT) begin
            assert(f_begin_seen_q && f_pending_q && !fault_o && f_index_q==0);
            assert(pending_last_q==f_last_q);
            assert(compress_block_q==f_expected_block_q);
            assert(compress_state_q==f_expected_chain_q);
            assert(compress_state_q==hash_state_q);
            assert(!byte_ready_o);
        end
        if(compress_start_q) begin
            assert(state_q==ST_WAIT && !compress_busy && !compress_done);
            assert(f_pending_q && compress_block_q==f_expected_block_q && compress_state_q==f_expected_chain_q);
        end
        if(digest_valid_o) begin
            assert(state_q==ST_DONE && !fault_o && f_end_seen_q && !f_pending_q);
            assert(digest_o==hash_state_q && digest_o==f_chain_q);
        end
        cover(compress_start_q);
        cover(digest_valid_o);
    end
