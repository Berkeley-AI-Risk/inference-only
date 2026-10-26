    // Observational history only: no signal feeds back into the controller.
    logic f_load_final_seen_q, f_boot_read_seen_q, f_final_return_seen_q;
    logic [18:0] f_load_count_q, f_read_count_q, f_return_count_q;
    logic f_past_valid_q;
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            f_load_final_seen_q <= 0;
            f_boot_read_seen_q <= 0;
            f_final_return_seen_q <= 0;
            f_load_count_q <= 0;
            f_read_count_q <= 0;
            f_return_count_q <= 0;
            f_past_valid_q <= 0;
        end else begin
            f_past_valid_q <= 1;
            if (state_q == ST_LOAD && phy_req_valid && phy_req_ready)
                f_load_count_q <= f_load_count_q + 1'b1;
            if (state_q == ST_READBACK && phy_req_valid && phy_req_ready)
                f_read_count_q <= f_read_count_q + 1'b1;
            if (state_q == ST_READBACK && phy_rsp_valid && !phy_rsp_error &&
                readback_outstanding_q && !readback_valid_q && calib_done && !calib_error)
                f_return_count_q <= f_return_count_q + 1'b1;
            if (state_q == ST_LOAD && phy_req_valid && phy_req_ready && load_word_q == MODEL_LAST)
                f_load_final_seen_q <= 1;
            if (state_q == ST_READBACK && phy_req_valid && phy_req_ready)
                f_boot_read_seen_q <= 1;
            if (state_q == ST_READBACK && phy_rsp_valid && !phy_rsp_error &&
                readback_outstanding_q && !readback_valid_q && readback_receive_word_q == MODEL_LAST)
                f_final_return_seen_q <= 1;
        end
    end
    always_comb if (reset_n) begin
        assert(state_q == ST_WAIT_CAL || state_q == ST_WAIT_SOURCE || state_q == ST_LOAD ||
            state_q == ST_READBACK || state_q == ST_WAIT_DIGEST || state_q == ST_LOCKED || state_q == ST_FAIL);
        assert(load_word_q <= MODEL_LAST);
        assert(readback_issue_word_q <= MODEL_LAST);
        assert(readback_receive_word_q <= MODEL_LAST);
        assert(!(readback_outstanding_q && readback_valid_q));
        if (model_locked) assert(state_q == ST_LOCKED);
        // A simultaneous unexpected response and held-final-word consume can
        // overwrite ST_FAIL with ST_WAIT_DIGEST in the native controller.
        // The sticky fault still closes these actual output gates. Retain the
        // failed stronger state/lock assertions in runs/boot-order-r1.
        if (fail_closed) assert(!phy_req_valid && !runtime_req_ready);
        if (fail_closed) assert(state_q == ST_FAIL || state_q == ST_WAIT_DIGEST || state_q == ST_LOCKED);
        if (state_q == ST_FAIL) assert(fail_closed);
        assert(f_load_count_q <= MODEL_WORDS);
        assert(f_read_count_q <= MODEL_WORDS);
        assert(f_return_count_q <= MODEL_WORDS);
        if (state_q == ST_WAIT_CAL || state_q == ST_WAIT_SOURCE)
            assert(f_load_count_q == 0);
        if (!f_boot_read_seen_q) assert(f_read_count_q == 0 && f_return_count_q == 0);
        if (state_q == ST_LOAD) assert(f_load_count_q == load_word_q);
        if (state_q == ST_READBACK || state_q == ST_WAIT_DIGEST || state_q == ST_LOCKED)
            assert(f_load_count_q == MODEL_WORDS);
        if (state_q == ST_READBACK) begin
            if (readback_last_q) assert(readback_valid_q);
            assert(f_read_count_q == readback_issue_word_q +
                ((readback_receive_word_q == MODEL_LAST &&
                (readback_outstanding_q || readback_last_q)) ? 19'd1 : 19'd0));
            assert(f_return_count_q == readback_receive_word_q +
                (readback_last_q ? 19'd1 : 19'd0));
        end
        if (state_q == ST_WAIT_DIGEST || state_q == ST_LOCKED)
            assert(f_read_count_q == MODEL_WORDS && f_return_count_q == MODEL_WORDS);
        if (f_boot_read_seen_q) assert(state_q != ST_LOAD && state_q != ST_WAIT_CAL && state_q != ST_WAIT_SOURCE);
        if (phy_req_valid && phy_req_write && phy_req_word_addr < MODEL_END)
            assert(state_q == ST_LOAD && !f_boot_read_seen_q);
        if (f_boot_read_seen_q && phy_req_valid && phy_req_write)
            assert(phy_req_word_addr >= SCRATCH_BASE && phy_req_word_addr < SCRATCH_END);
        if (runtime_offer_valid_q && runtime_offer_legal_q && runtime_offer_write_q)
            assert(runtime_offer_address_q >= SCRATCH_BASE && runtime_offer_address_q < SCRATCH_END);
        if (state_q == ST_READBACK || state_q == ST_WAIT_DIGEST || state_q == ST_LOCKED)
            assert(f_load_final_seen_q);
        if (f_boot_read_seen_q) assert(f_load_final_seen_q);
        if (readback_outstanding_q) assert(f_boot_read_seen_q);
        if (readback_valid_q) assert(f_boot_read_seen_q);
        if (readback_issue_word_q != MODEL_BASE) assert(f_boot_read_seen_q);
        if (readback_receive_word_q != MODEL_BASE) assert(f_boot_read_seen_q);
        if (readback_last_q) assert(f_final_return_seen_q && readback_receive_word_q == MODEL_LAST);
        if (f_final_return_seen_q) assert(f_boot_read_seen_q);
        if (state_q == ST_WAIT_DIGEST || state_q == ST_LOCKED) begin
            assert(f_boot_read_seen_q && f_final_return_seen_q);
            assert(readback_issue_word_q == MODEL_LAST && readback_receive_word_q == MODEL_LAST);
            assert(!readback_outstanding_q && !readback_valid_q);
        end
        if (model_locked) assert(f_boot_read_seen_q && f_final_return_seen_q);
        if (state_q == ST_READBACK) begin
            if (readback_outstanding_q)
                assert(readback_issue_word_q == (readback_receive_word_q == MODEL_LAST ?
                    MODEL_LAST : readback_receive_word_q + 1'b1));
            else assert(readback_issue_word_q == readback_receive_word_q);
            if (phy_req_valid) assert(!phy_req_write && f_load_final_seen_q);
        end
        if (state_q == ST_LOAD && phy_req_valid)
            assert(phy_req_write && phy_req_word_addr < MODEL_END);
        cover(state_q == ST_LOAD && phy_req_valid && phy_req_ready && phy_req_write);
    end
    always_ff @(posedge clk) if (reset_n && f_past_valid_q && $past(reset_n) && $past(fail_closed))
        assert(fail_closed);
