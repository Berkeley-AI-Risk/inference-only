    // Specification history: complete checked transcript and a fresh verifier
    // start must precede every grant. Inputs/verdicts remain unconstrained.
    logic [10:0] spec_received;
    logic [7:0] spec_sent;
    logic spec_frame, spec_started, spec_permitted, spec_header_good;
    logic [255:0] spec_model;
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            spec_received<=0; spec_frame<=0; spec_started<=0;
            spec_sent<=0; spec_header_good<=0;
            spec_permitted<=0; spec_model<=0;
        end else begin
            if(state_q==COLLECT && have_nonce_q && have_root_q) spec_sent<=0;
            if(request_valid_o && request_ready_i) spec_sent<=spec_sent+1'b1;
            if(state_q==SEND && request_ready_i && index_q==127) begin
                spec_received<=0; spec_frame<=0; spec_started<=0;
                spec_header_good<=1;
            end
            if(grant_valid_i && grant_ready_o) begin
                spec_received<=spec_received+1'b1;
                if(index_q<128 && grant_byte_i!=spec_byte) spec_header_good<=0;
                if(grant_last_i==(index_q==1419) &&
                   (index_q>=128 || grant_byte_i==selected_message_byte) && index_q==1419)
                    spec_frame<=1;
            end
            if(shared_start_o) spec_started<=1;
            if(new_lease_o) begin spec_permitted<=1; spec_model<=root_q; end
            if(failed_o) spec_permitted<=0;
        end
    end

    // Independent byte layout: DOMAIN || DEVICE || NONCE || MODEL || GEOMETRY.
    wire [1023:0] spec_message={128'h53415749432d484f4d452d7631000000,
                               DEVICE_ID,nonce_q,root_q,GEOMETRY};
    wire [7:0] spec_byte=selected_message_address[7] ? 8'd0 :
        spec_message[{~selected_message_address[6:0],3'b000} +:8];
    always_comb begin
        assert(selected_message_byte==spec_byte);
        assert(root_equal==(admitted_root_i==root_q));
        assert(nonce_equal==(nonce_i==previous_nonce_q));
        if(reset_n) begin
            if(fault_q) assert(state_q==FAIL);
            if(have_nonce_q) assert(nonce_q!=0 && seen_nonce_q && nonce_q==previous_nonce_q);
            assert(state_q==COLLECT || state_q==SEND || state_q==RECEIVE ||
                   state_q==ARM || state_q==ARM_WAIT || state_q==START ||
                   state_q==VERIFY || state_q==RUN || state_q==FAIL);
            if(state_q==SEND || state_q==RECEIVE || state_q==ARM ||
               state_q==ARM_WAIT || state_q==START || state_q==VERIFY || state_q==RUN)
                assert(have_root_q && have_nonce_q);
            if(state_q==RECEIVE) begin
                assert(spec_header_good);
                assert(index_q==spec_received);
                assert(index_q<=1419);
                assert(spec_sent==128);
            end
            if(state_q==SEND) begin assert(index_q<=127); assert(index_q==spec_sent); end
            if(state_q==ARM || state_q==ARM_WAIT || state_q==START || state_q==VERIFY || state_q==RUN) begin
                assert(spec_frame);
                assert(spec_received==1420);
                assert(spec_header_good && spec_sent==128);
            end
            if(state_q==VERIFY || state_q==RUN) assert(spec_started);
            if(shared_start_o) assert(shared_reset_n_o);
            if(new_lease_o) begin
                assert(spec_frame && spec_started && shared_reset_n_o);
                assert(crypto_done && crypto_valid && !crypto_fault);
                assert(have_root_q && have_nonce_q && nonce_q!=0);
                assert(root_q==admitted_root_i && admitted_root_valid_i);
                assert(age_q<RESPONSE_LIMIT_CYCLES-1);
            end
            if(lease_active_q) begin
                assert(have_root_q);
                if(!failed_o) begin
                    assert(spec_permitted);
                    assert(root_q==spec_model);
                end
                assert(lease_age_q<LEASE_CYCLES);
            end
            if(inference_enabled_o) begin
                assert(spec_permitted && admitted_root_i==spec_model);
                assert(!nonce_fault_i && !model_fault_i && !failed_o);
                assert(lease_cycles_remaining_o>0 && lease_cycles_remaining_o<LEASE_CYCLES);
            end
            if(publication_allowed_o) begin
                assert(inference_enabled_o);
                assert(lease_cycles_remaining_o>20000);
            end
            if(failed_o) assert(!inference_enabled_o && !publication_allowed_o && !new_lease_o);
        end else assert(!inference_enabled_o && !publication_allowed_o && !new_lease_o);
    end

    logic spec_past_valid=0;
    always_ff @(posedge clk) begin
        spec_past_valid<=1;
        if(spec_past_valid && reset_n && $past(reset_n)) begin
            if(shared_start_o) assert($past(shared_reset_n_o));
            if($past(have_root_q)) assert(have_root_q && root_q==$past(root_q));
            if($past(failed_o)) assert(failed_o);
            if($past(nonce_valid_i && nonce_request_o &&
                     (nonce_i==0 || (seen_nonce_q && nonce_equal)))) assert(failed_o);
            if(inference_enabled_o && !$past(inference_enabled_o)) assert($past(new_lease_o));
            if($past(new_lease_o)) assert(lease_age_q==$past(age_q)+1);
            if($past(lease_active_q) && !$past(failed_o) && !$past(new_lease_o))
                assert(lease_age_q==$past(lease_age_q)+1);
            if($past(inference_enabled_o) && inference_enabled_o && !$past(new_lease_o))
                assert(lease_cycles_remaining_o+1==$past(lease_cycles_remaining_o));
        end
    end
