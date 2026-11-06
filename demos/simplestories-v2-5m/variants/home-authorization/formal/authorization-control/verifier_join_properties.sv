    // Post-admission shared-verifier selection. The source correspondence audit
    // checks that the published admission mux selects exactly these ports for
    // the lease owner. Boot admission and SHA functional correctness are
    // separate contracts; the real LMS controller and grant RAM are retained.
    wire [10:0] shared_signature_address_i;
    wire [7:0] shared_message_address_i;
    wire shared_busy_i,shared_done_i,shared_valid_i,shared_fault_i;
    (* anyseq *) wire spec_hash_ready,spec_hash_busy,spec_hash_done,spec_hash_fault;
    (* anyseq *) wire [31:0] spec_hash_offset;
    (* anyseq *) wire [255:0] spec_hash_digest;
    wire proof_verifier_started;
    wire [127:0] proof_verifier_identifier;
    wire [255:0] proof_verifier_root;
    wire [8:0] proof_verifier_length;
    su_lms_verify #(.MAX_MESSAGE_BYTES(128),.USE_SHARED_HASH(1'b1)) u_home_verifier (
        .clk(clk),.reset_n(shared_reset_n_o),.start_i(shared_start_o),
        .public_i_i(HOME_KEY_ID),.public_root_i(HOME_KEY_ROOT),.message_length_i(9'd128),
        .signature_address_o(shared_signature_address_i),.signature_byte_i(shared_signature_byte_o),
        .signature_ready_i(shared_signature_ready_o),.message_address_o(shared_message_address_i),
        .message_byte_i(shared_message_byte_o),.busy_o(shared_busy_i),.done_o(shared_done_i),
        .valid_o(shared_valid_i),.fault_o(shared_fault_i),
        .shared_hash_ready_i(shared_reset_n_o && spec_hash_ready),
        .shared_hash_busy_i(shared_reset_n_o && spec_hash_busy),
        .shared_hash_done_i(shared_reset_n_o && spec_hash_done),
        .shared_hash_fault_i(shared_reset_n_o && spec_hash_fault),
        .shared_hash_offset_i(spec_hash_offset),.shared_hash_digest_i(spec_hash_digest),
        .proof_started_o(proof_verifier_started),.proof_identifier_o(proof_verifier_identifier),
        .proof_root_o(proof_verifier_root),.proof_length_o(proof_verifier_length));
    always_comb begin
        if(new_lease_o) begin
            assert(proof_verifier_started && shared_reset_n_o && shared_done_i && shared_valid_i);
            assert(proof_verifier_identifier==HOME_KEY_ID && proof_verifier_root==HOME_KEY_ROOT);
            assert(proof_verifier_length==128);
        end
        if(!shared_reset_n_o) assert(!shared_done_i && !shared_valid_i && !proof_verifier_started);
    end
    logic verifier_join_initial=1;
    always_ff @(posedge clk) verifier_join_initial<=0;
    always_comb if(verifier_join_initial) assume(!reset_n);
