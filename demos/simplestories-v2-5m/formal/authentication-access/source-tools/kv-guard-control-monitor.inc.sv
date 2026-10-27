    // Independent accepted-request, epoch and verification-event observations.
    // The private hash replies are unrestricted in this parent control proof.
    logic [63:0] f_guard_epoch_q;
    logic f_guard_clear_q,f_guard_past_valid=0;
    logic f_guard_checked_q,f_guard_read_complete_q;
    logic [255:0] f_guard_digest_q,f_guard_expected_q,f_guard_write_q;
    logic [63:0] f_guard_checked_epoch_q,f_guard_request_epoch_q;
    logic [2:0] f_guard_checked_layer_q,f_guard_request_layer_q;
    logic [6:0] f_guard_checked_page_q,f_guard_request_page_q,f_guard_request_slot_q;
    logic [4:0] f_guard_checked_positions_q,f_guard_request_positions_q;
    logic f_guard_checked_head_q,f_guard_checked_role_q,f_guard_request_head_q,f_guard_request_role_q;
    wire f_guard_match=live && state_q==HDIGEST && !hash_write_q && hash_digest_valid && hash_digest==expected_q;
    wire f_guard_good_read=s_rd_rsp_valid && !terminal_now && !aborted_q && !clear_i;
    wire f_guard_cached_use=live && owner_q==READ_OWNER && (state_q==OREAD || state_q==OCAP || state_q==RRETURN);
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            f_guard_epoch_q<=0;f_guard_clear_q<=0;
            f_guard_checked_q<=0;f_guard_read_complete_q<=0;
            f_guard_digest_q<=0;f_guard_expected_q<=0;f_guard_write_q<=0;
            f_guard_checked_epoch_q<=0;f_guard_request_epoch_q<=0;
            f_guard_checked_layer_q<=0;f_guard_request_layer_q<=0;
            f_guard_checked_page_q<=0;f_guard_request_page_q<=0;f_guard_request_slot_q<=0;
            f_guard_checked_positions_q<=0;f_guard_request_positions_q<=0;
            f_guard_checked_head_q<=0;f_guard_checked_role_q<=0;
            f_guard_request_head_q<=0;f_guard_request_role_q<=0;
        end else begin
            f_guard_clear_q<=clear_i;
            if(clear_i && !f_guard_clear_q && f_guard_epoch_q!=64'hffffffffffffffff)
                f_guard_epoch_q<=f_guard_epoch_q+64'd1;
            if(clear_i || terminal_now || write_fire || (read_fire && !cache_hit)) f_guard_checked_q<=0;
            else if(f_guard_match) begin
                f_guard_checked_q<=1;f_guard_digest_q<=hash_digest;f_guard_expected_q<=expected_q;
                f_guard_checked_epoch_q<=epoch_q;f_guard_checked_layer_q<=layer_q;
                f_guard_checked_page_q<=page_q;f_guard_checked_positions_q<=positions_q;
                f_guard_checked_head_q<=group_head_q;f_guard_checked_role_q<=role_q;
            end
            if(clear_i || terminal_now || read_fire) f_guard_read_complete_q<=0;
            else if(live && state_q==OCAP && chunk_q==7) f_guard_read_complete_q<=1;
            if(write_fire) f_guard_write_q<=s_wr_data;
            if(read_fire && rd_legal) begin
                f_guard_request_epoch_q<=epoch_q;f_guard_request_layer_q<=s_rd_layer;
                f_guard_request_page_q<=s_rd_position[10:4];f_guard_request_positions_q<=read_positions;
                f_guard_request_head_q<=s_rd_head[0];
                f_guard_request_role_q<=s_rd_word==8 ? read_role : s_rd_word[2];
                f_guard_request_slot_q<=7'(5*int'(s_rd_position[3:0])+(s_rd_word==8 ? 4 : int'(s_rd_word[1:0])));
            end
        end
    end
    always_ff @(posedge clk) begin
        f_guard_past_valid<=1;
        if(reset_n) begin
            assert(state_q<=RRETURN && owner_q<=READ_OWNER);
            assert(layer_q<6 && position_q<2048 && row_word_q<9 && positions_q<=16 && total_slots_q<=80);
            assert(epoch_q==f_guard_epoch_q && clear_seen_q==f_guard_clear_q);
            if(clear_i && !clear_seen_q && &epoch_q) assert(fault_o);
            if(f_guard_past_valid && $past(reset_n) && $past(fault_o)) assert(fault_o);
            if(owner_q!=NONE) assert(lock_seen_q);
            if(!live) assert(!s_wr_ready && !s_rd_ready && !m_wr_valid && !m_rd_valid);
            assert(!(s_wr_ready && s_rd_ready && s_wr_valid && s_rd_valid));
            if(s_wr_cpl_valid) assert(owner_q==WRITE_OWNER && state_q==WRETURN);
            if(s_rd_rsp_valid) assert(owner_q==READ_OWNER && state_q==RRETURN);
            if(!s_rd_rsp_valid || terminal_now || aborted_q || clear_i) assert(s_rd_rsp_data==0);
            assert((owner_q==NONE)==(state_q==IDLE));
            if(state_q==WREQ || state_q==WWAIT || state_q==WSTORE || state_q==WRETURN) assert(owner_q==WRITE_OWNER);
            if(state_q==RREQ || state_q==RWAIT || state_q==RSTORE || state_q==TREAD || state_q==TCAP ||
                    state_q==OREAD || state_q==OCAP || state_q==RRETURN) assert(owner_q==READ_OWNER);
            if(state_q==HBEGIN || state_q==HREAD || state_q==HCAP || state_q==HWORD || state_q==HDIGEST)
                assert(owner_q==(hash_write_q ? WRITE_OWNER : READ_OWNER));
            if(state_q==TWRITE) assert(owner_q==WRITE_OWNER && hash_write_q);
            if(!fault_o && !aborted_q && !clear_i) begin
                if(owner_q!=NONE) assert(positions_q>=1);
                if(owner_q==WRITE_OWNER) assert(word_q==f_guard_write_q);
                if(owner_q==READ_OWNER) begin
                    assert(epoch_q==f_guard_request_epoch_q);
                    assert(layer_q==f_guard_request_layer_q && page_q==f_guard_request_page_q &&
                        group_head_q==f_guard_request_head_q && role_q==f_guard_request_role_q &&
                        positions_q==f_guard_request_positions_q);
                    assert(total_slots_q==7'(5*int'(positions_q)) && target_slot_q==f_guard_request_slot_q && target_slot_q<total_slots_q);
                end
            end
            if(m_wr_valid) begin
                assert(owner_q==WRITE_OWNER && m_wr_layer<6 && m_wr_position<2048 && m_wr_head<2 && m_wr_word<9);
                assert(m_wr_data==f_guard_write_q);
                assert(m_wr_shadow>=227072 && m_wr_shadow<448256);
                assert(m_wr_shadow==19'(227072+((int'(m_wr_layer)*2048+int'(m_wr_position))*2+int'(m_wr_head))*9+int'(m_wr_word)));
            end
            if(m_rd_valid) begin
                assert(owner_q==READ_OWNER && m_rd_layer<6 && m_rd_position<2048 && m_rd_head<2 && m_rd_word<9);
                assert(m_rd_shadow>=227072 && m_rd_shadow<448256);
                assert(m_rd_shadow==19'(227072+((int'(m_rd_layer)*2048+int'(m_rd_position))*2+int'(m_rd_head))*9+int'(m_rd_word)));
            end
            if(!fault_o) begin
                assert(cache_valid_q==f_guard_checked_q);
                if(cache_valid_q) begin
                    assert(cache_epoch_q==epoch_q && cache_epoch_q==f_guard_checked_epoch_q);
                    assert(cache_layer_q==f_guard_checked_layer_q && cache_page_q==f_guard_checked_page_q);
                    assert(cache_head_q==f_guard_checked_head_q && cache_role_q==f_guard_checked_role_q &&
                        cache_positions_q==f_guard_checked_positions_q);
                    assert(f_guard_digest_q==f_guard_expected_q);
                end
                if(f_guard_cached_use || f_guard_good_read) begin
                    assert(cache_valid_q && f_guard_checked_q);
                    assert(cache_epoch_q==f_guard_request_epoch_q && cache_layer_q==f_guard_request_layer_q &&
                        cache_page_q==f_guard_request_page_q && cache_head_q==f_guard_request_head_q &&
                        cache_role_q==f_guard_request_role_q && cache_positions_q==f_guard_request_positions_q);
                    assert(target_slot_q==f_guard_request_slot_q && target_slot_q<total_slots_q && total_slots_q<=80);
                end
                if(f_guard_good_read) assert(f_guard_read_complete_q);
            end
            cover(write_fire && wr_legal);
            cover(s_wr_cpl_valid && !s_wr_cpl_fault && !aborted_q && !clear_i);
        end
    end
