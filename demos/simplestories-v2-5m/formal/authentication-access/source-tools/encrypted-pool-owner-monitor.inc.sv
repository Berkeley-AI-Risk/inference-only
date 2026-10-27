    generate for(genvar f_e=0;f_e<2;f_e=f_e+1) begin: f_engine_owner
        always_ff @(posedge clk) if(reset_n && enabled) begin
            assert(owner_valid_q[f_e]==(engine_busy[f_e] || engine_done[f_e]));
            if(owner_valid_q[f_e]) assert(owner_q[f_e][0]==1'(f_e) && pending_q[owner_q[f_e]]);
            if(grant_valid[f_e]) assert(!owner_valid_q[f_e] &&
                request_ready_o[grant_bank[f_e]] && request_valid_i[grant_bank[f_e]] && grant_bank[f_e][0]==1'(f_e));
            if(engine_done[f_e]) assert(response_valid_o[owner_q[f_e]] &&
                response_state_o[int'(owner_q[f_e])*256 +: 256]==engine_result[f_e]);
        end
    end endgenerate
    generate for(genvar f_b=0;f_b<BANKS;f_b=f_b+1) begin: f_bank_owner
        always_ff @(posedge clk) if(reset_n && enabled)
            assert(pending_q[f_b]==(owner_valid_q[f_b%2] && owner_q[f_b%2]==BANK_W'(f_b)));
    end endgenerate
