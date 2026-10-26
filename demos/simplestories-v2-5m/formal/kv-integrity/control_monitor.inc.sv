    // Read-only ghost history. No production state is assigned here.
    reg f_seen, f_previous_fault, f_previous_clear, f_previous_mismatch;
    reg f_verified;
    reg [63:0] f_epoch_before;
    reg f_clear_edge;
    reg [63:0] f_epoch;
    reg [2:0] f_layer;
    reg [6:0] f_page;
    reg [4:0] f_positions;
    reg f_head, f_role;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            f_seen <= 0;
            f_previous_fault <= 0;
            f_previous_clear <= 0;
            f_previous_mismatch <= 0;
            f_verified <= 0;
            f_epoch_before <= 0;
            f_clear_edge <= 0;
            f_epoch <= 0;
            f_layer <= 0;
            f_page <= 0;
            f_positions <= 0;
            f_head <= 0;
            f_role <= 0;
        end else begin
            f_seen <= 1;
            f_epoch_before <= epoch_q;
            f_clear_edge <= clear_i && !clear_seen_q;
            f_previous_fault <= fault_o;
            f_previous_clear <= clear_i;
            f_previous_mismatch <= live && state_q == HDIGEST &&
                !hash_write_q && hash_digest_valid && hash_digest != expected_q;
            if (clear_i || terminal_now || write_fire || (read_fire && rd_legal && !cache_hit))
                f_verified <= 0;
            if (live && state_q == HDIGEST && !hash_write_q &&
                hash_digest_valid && hash_digest == expected_q) begin
                f_verified <= 1;
                f_epoch <= epoch_q;
                f_layer <= layer_q;
                f_page <= page_q;
                f_positions <= positions_q;
                f_head <= group_head_q;
                f_role <= role_q;
            end
        end
    end

    always_comb begin
        if (reset_n) begin
            if (f_seen && f_clear_edge && !(&f_epoch_before))
                assert(epoch_q == f_epoch_before + 64'd1);
            if (f_seen && !f_clear_edge) assert(epoch_q == f_epoch_before);
            if (f_seen && f_clear_edge && (&f_epoch_before)) assert(fault_o);
            assert(clear_seen_q == f_previous_clear);
            assert(state_q <= RRETURN);
            assert(owner_q <= READ_OWNER);
            assert((state_q == IDLE) == (owner_q == NONE));
            if (owner_q != NONE || cache_valid_q) assert(lock_seen_q);
            if (!f_seen) assert(state_q == IDLE && !fault_q && !cache_valid_q);
            if (state_q == WREQ || state_q == WWAIT || state_q == WSTORE ||
                state_q == WRETURN || state_q == TWRITE) assert(owner_q == WRITE_OWNER);
            if (state_q == RREQ || state_q == RWAIT || state_q == RSTORE ||
                state_q == TREAD || state_q == TCAP || state_q == OREAD ||
                state_q == OCAP || state_q == RRETURN) assert(owner_q == READ_OWNER);
            if (state_q == HBEGIN || state_q == HREAD || state_q == HCAP ||
                state_q == HWORD || state_q == HDIGEST)
                assert(owner_q == (hash_write_q ? WRITE_OWNER : READ_OWNER));
            if (state_q == TWRITE) assert(hash_write_q);
            if (f_previous_fault) assert(fault_o);
            if (f_previous_mismatch) assert(fault_o);
            if (fault_o) begin
                assert(!live && !s_wr_ready && !s_rd_ready && !m_wr_valid &&
                       !m_rd_valid && !tag_write && !tag_read);
                assert(s_rd_rsp_data == 0);
                assert(!s_rd_rsp_valid || s_rd_rsp_fault);
                assert(!s_wr_cpl_valid || s_wr_cpl_fault);
            end
            if (clear_i || aborted_q) begin
                assert(!live && !s_wr_ready && !s_rd_ready && !m_wr_valid &&
                       !m_rd_valid && !tag_write && !tag_read);
                assert(s_rd_rsp_data == 0);
            end
            if (!s_rd_rsp_valid) assert(s_rd_rsp_data == 0);
            assert(!(write_fire && read_fire));
            if (f_previous_clear) begin
                assert(!cache_valid_q && !population_q);
                assert(prefix_q[0] == 0 && prefix_q[1] == 0 && prefix_q[2] == 0 &&
                       prefix_q[3] == 0 && prefix_q[4] == 0 && prefix_q[5] == 0);
            end
            if (cache_valid_q) begin
                assert(f_verified);
                assert(cache_epoch_q == f_epoch && cache_layer_q == f_layer &&
                       cache_page_q == f_page && cache_positions_q == f_positions &&
                       cache_head_q == f_head && cache_role_q == f_role);
                assert(cache_epoch_q == epoch_q);
                assert(state_q == IDLE || state_q == OREAD ||
                       state_q == OCAP || state_q == RRETURN);
            end
            if (live && (state_q == OREAD || state_q == OCAP || state_q == RRETURN)) begin
                assert(cache_valid_q);
                assert(layer_q == cache_layer_q && page_q == cache_page_q &&
                       positions_q == cache_positions_q && group_head_q == cache_head_q &&
                       role_q == cache_role_q);
            end
            if (s_rd_rsp_valid && !terminal_now && !aborted_q && !clear_i)
                assert(cache_valid_q && f_verified && owner_q == READ_OWNER);
            if (live && cache_valid_q) assert(state_q != RSTORE);
        end
    end
