    // These phase inputs observe parent histories only; no native FIFO logic
    // consumes them. The first READ ticket uses the real extra wrap bit.
    generate if (WIDTH == 276 && ADDR_BITS == 5) begin: f_epoch_commands
        logic f_cut_valid_q;
        logic [PTR_W-1:0] f_cut_seq_q;
        always_ff @(posedge s_clk_i or negedge s_reset_n_i) begin
            if (!s_reset_n_i) begin
                f_cut_valid_q <= 0;
                f_cut_seq_q <= 0;
            end else if (source_push && !s_data_i[275] && !f_cut_valid_q) begin
                f_cut_valid_q <= 1;
                f_cut_seq_q <= f_wseq_q;
            end
        end
        function automatic f_non_kv_write(input [275:0] payload);
            f_non_kv_write = payload[275] &&
                (payload[274:256] < 19'd227072 || payload[274:256] >= 19'd__KV_LIMIT__);
        endfunction
        wire [PTR_W-1:0] f_cut_distance = f_cut_seq_q - f_rseq_q;
        always_comb begin
            if (f_cut_valid_q) assert(f_source_read_seen_i);
            if (f_physical_read_seen_i) assert(f_cut_valid_q);
            if (f_cut_valid_q && !f_physical_read_seen_i) begin
                assert(f_cut_distance < f_used);
                assert(!memory_q[f_cut_seq_q[ADDR_BITS-1:0]][275]);
            end
            if (m_valid_o) begin
                assert(f_used != 0);
                assert(m_data_o[275] == memory_q[f_rseq_q[ADDR_BITS-1:0]][275]);
                assert(f_non_kv_write(m_data_o) == f_non_kv_write(memory_q[f_rseq_q[ADDR_BITS-1:0]]));
                if (f_physical_read_seen_i) assert(!f_non_kv_write(m_data_o));
                if (f_cut_valid_q && !f_physical_read_seen_i && f_cut_distance == 0) assert(!m_data_o[275]);
            end
        end
        for (genvar row=0;row<DEPTH;row=row+1) begin: f_epoch_row
            wire [ADDR_BITS-1:0] offset = ADDR_BITS'(row) - f_rseq_q[ADDR_BITS-1:0];
            always_comb if ({1'b0,offset} < f_used)
                assert((!f_cut_valid_q || (!f_physical_read_seen_i && {1'b0,offset} < f_cut_distance)) ?
                    memory_q[row][275] : !f_non_kv_write(memory_q[row]));
        end
    end else if (WIDTH == 257 && ADDR_BITS == 6) begin: f_epoch_returns
        always_comb begin
            if (f_used != 0) assert(f_physical_read_seen_i);
            if (m_valid_o) assert(f_physical_read_seen_i);
        end
    end endgenerate
