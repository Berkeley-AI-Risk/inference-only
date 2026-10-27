        // These are the exact native local buses connected to u_sha's
        // block_i/state_i ports, checked against the requested/owning bank.
        always_ff @(posedge clk) if(reset_n && enabled) begin
            if(owner_valid_q[g])
                assert(states[int'(active_slot)*256 +: 256]==request_state_i[int'(owner_q[g])*256 +: 256]);
            if(grant_valid[g]) begin
                assert(states[int'(active_slot)*256 +: 256]==request_state_i[int'(grant_bank[g])*256 +: 256]);
                assert(blocks[int'(active_slot)*512 +: 512]==request_block_i[int'(grant_bank[g])*512 +: 512]);
            end
        end
