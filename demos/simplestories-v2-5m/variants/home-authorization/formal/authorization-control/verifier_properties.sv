    // Control provenance of the real LMS verifier, not its cryptographic
    // algorithm: hashes, message bytes and signature bytes are arbitrary.
    logic spec_started;
    logic [127:0] spec_identifier;
    logic [255:0] spec_root;
    logic [8:0] spec_length;
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin spec_started<=0;spec_identifier<=0;spec_root<=0;spec_length<=0;end
        else if(start_i && state_q==IDLE && !hash_fault) begin
            spec_started<=1;spec_identifier<=public_i_i;
            spec_root<=public_root_i;spec_length<=message_length_i;
        end
    end
    always_comb if(reset_n) begin
        assert(state_q==IDLE || state_q==HEADER || state_q==CHECK || state_q==HSTART || state_q==HWAIT ||
               state_q==COEFFICIENT || state_q==YLOAD || state_q==CHAIN || state_q==SAVE_Z ||
               state_q==LEAF || state_q==PATH_LOAD || state_q==PARENT || state_q==FINISH || state_q==FAILED);
        assert(after_hash_q==IDLE || after_hash_q==COEFFICIENT || after_hash_q==CHAIN ||
               after_hash_q==LEAF || after_hash_q==PATH_LOAD || after_hash_q==PARENT);
        if(fault_o) assert(state_q==FAILED);
        if(done_o && !fault_o) assert(state_q==FINISH);
        if(state_q!=IDLE && state_q!=FAILED) assert(spec_started);
        if(spec_started) begin
            assert(identifier_q==spec_identifier && root_q==spec_root && message_length_q==spec_length);
        end
        if(valid_o) assert(done_o && !fault_o && state_q==FINISH && spec_started);
        if(state_q==FAILED) assert(!valid_o && fault_o && done_o);
    end else assert(!valid_o && !done_o);
