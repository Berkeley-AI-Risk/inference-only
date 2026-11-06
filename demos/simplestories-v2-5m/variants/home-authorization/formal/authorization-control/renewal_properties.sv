    logic spec_consumed, spec_had_grant;
    logic [255:0] spec_last_grant_nonce;
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin spec_consumed<=0;spec_had_grant<=0;spec_last_grant_nonce<=0;end
        else begin
            if(nonce_valid_i && nonce_request_o && !fault_now && nonce_i!=0 &&
               (!seen_nonce_q || !nonce_equal)) spec_consumed<=0;
            if(new_lease_o) begin
                spec_consumed<=1;spec_had_grant<=1;spec_last_grant_nonce<=nonce_q;
            end
        end
    end
    always_comb if(reset_n) begin
        if(spec_had_grant) assert(seen_nonce_q && have_root_q);
        if(spec_consumed) assert(nonce_q==spec_last_grant_nonce && previous_nonce_q==spec_last_grant_nonce);
        if(spec_had_grant && !spec_consumed) assert(have_nonce_q && nonce_q!=spec_last_grant_nonce);
        if(state_q==COLLECT && have_nonce_q) assert(!spec_consumed);
        if(state_q==SEND || state_q==RECEIVE || state_q==ARM || state_q==ARM_WAIT ||
           state_q==START || state_q==VERIFY) assert(!spec_consumed);
        if(state_q==RUN) assert(spec_consumed && spec_had_grant && lease_active_q);
        if(new_lease_o) begin
            assert(!spec_consumed);
            if(spec_had_grant) assert(nonce_q!=spec_last_grant_nonce);
        end
    end
    logic renewal_past=0;
    always_ff @(posedge clk) begin
        renewal_past<=1;
        if(renewal_past && reset_n && $past(reset_n)) begin
            if($past(state_q)==RUN && !$past(fault_now) &&
               $past(lease_age_q)>=LEASE_CYCLES-RENEW_LEAD_CYCLES) begin
                assert(state_q==COLLECT && !have_nonce_q);
                assert(lease_age_q==$past(lease_age_q)+1);
            end
            if($past(failed_o)) assert(!inference_enabled_o && !publication_allowed_o && !new_lease_o);
        end
    end
