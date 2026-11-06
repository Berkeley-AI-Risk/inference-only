    wire lease_crypto_reset_n_i,lease_crypto_start_i,lease_signature_ready_i;
    wire [127:0] lease_key_id_i=128'hc044bbc6bdd6530b85e435fd6184137a;
    wire [255:0] lease_key_root_i=256'h90c220be722a4b158990b9cff559c0eae3dfd5b45746f8363a1adfe0231556d2;
    wire [7:0] lease_signature_byte_i,lease_message_byte_i;
    (* anyseq *) wire proof_memory_ready,proof_memory_fault,proof_nonce_valid,proof_nonce_fault;
    (* anyseq *) wire [255:0] proof_nonce;
    (* anyseq *) wire proof_request_ready,proof_grant_valid,proof_grant_last;
    (* anyseq *) wire [7:0] proof_grant_byte;
    wire proof_home_grant,proof_home_enabled,proof_home_failed,proof_home_have_root;
    wire [3:0] proof_home_state;
    wire proof_verifier_started,proof_verifier_lease_epoch;
    wire [127:0] proof_verifier_identifier;
    wire [255:0] proof_verifier_root;
    wire [8:0] proof_verifier_length;
    // Readiness may be arbitrarily early/late once admission seals. The
    // independent real guard-cone proof discharges this admission implication.
    wire proof_model_ready=sealed_o && proof_memory_ready;
    home_boot_gate #(.USE_SHARED_VERIFIER(1'b1),
        .DEVICE_ID(128'h395c83e440d5252bfa59f6138e5ed3b8),
        .GEOMETRY(256'h2128664c0025b4ed2ddbd53b2178ea926fe1b3c5e817a2b043a2abc9ee41f078),
        .RESPONSE_LIMIT_CYCLES(100000000),.LEASE_CYCLES(250000000),.RENEW_LEAD_CYCLES(125000000)) u_home (
        .clk(clk),.reset_n(reset_n),.nonce_valid_i(proof_nonce_valid),.nonce_fault_i(proof_nonce_fault),.nonce_i(proof_nonce),
        .admitted_root_valid_i(proof_model_ready),.admitted_root_i(model_commitment_o),
        .model_fault_i(fail_closed_o || proof_memory_fault),
        .request_ready_i(proof_request_ready),.grant_valid_i(proof_grant_valid),.grant_last_i(proof_grant_last),.grant_byte_i(proof_grant_byte),
        .new_lease_o(proof_home_grant),.inference_enabled_o(proof_home_enabled),.failed_o(proof_home_failed),
        .shared_reset_n_o(lease_crypto_reset_n_i),.shared_start_o(lease_crypto_start_i),
        .shared_signature_ready_o(lease_signature_ready_i),.shared_signature_byte_o(lease_signature_byte_i),
        .shared_message_byte_o(lease_message_byte_i),.shared_signature_address_i(lease_signature_address_o),
        .shared_message_address_i(lease_message_address_o),.shared_busy_i(lease_crypto_busy_o),
        .shared_done_i(lease_crypto_done_o),.shared_valid_i(lease_crypto_valid_o),.shared_fault_i(lease_crypto_fault_o),
        .proof_have_root_o(proof_home_have_root),.proof_state_o(proof_home_state));
    always_comb if(reset_n) begin
        assert(state_q==LOAD || state_q==MANIFEST || state_q==ROOT_START || state_q==ROOT_WAIT ||
               state_q==AUTH_ID || state_q==AUTH_CHECK || state_q==AUTH_START || state_q==AUTH_WAIT || state_q==RUN || state_q==FAILED);
        if(fault_q) assert(state_q==FAILED);
        if(!lease_owner && !fail_closed_o) assert(!proof_home_have_root);
        if(!lease_owner) assert(!lease_crypto_done_o && !lease_crypto_valid_o && !lease_crypto_busy_o);
        if(!selected_lms_reset_n) assert(!lms_done && !lms_valid && !proof_verifier_started && !proof_verifier_lease_epoch);
        if(proof_verifier_lease_epoch) assert(lease_owner);
        if(lease_owner && proof_verifier_started) assert(proof_verifier_lease_epoch);
        if(proof_verifier_started && proof_verifier_lease_epoch) begin
            assert(proof_verifier_identifier==lease_key_id_i && proof_verifier_root==lease_key_root_i);
            assert(proof_verifier_length==128);
        end
        if(lease_crypto_valid_o || proof_home_grant) begin
            assert(lease_owner && proof_verifier_started && proof_verifier_lease_epoch);
            assert(proof_verifier_identifier==lease_key_id_i && proof_verifier_root==lease_key_root_i);
        end
        if(proof_home_grant || proof_home_enabled) assert(sealed_o && !fail_closed_o);
    end
    logic boot_handoff_past=0;
    always_ff @(posedge clk) begin
        boot_handoff_past<=1;
        if(boot_handoff_past && reset_n && $past(reset_n) && lease_owner && !$past(lease_owner)) begin
            assert(!lease_crypto_reset_n_i && !selected_lms_reset_n);
            assert(!lms_done && !lms_valid && !proof_verifier_started);
        end
    end
    logic boot_handoff_initial=1;
    always_ff @(posedge clk) boot_handoff_initial<=0;
    always_comb if(boot_handoff_initial) assume(!reset_n);
