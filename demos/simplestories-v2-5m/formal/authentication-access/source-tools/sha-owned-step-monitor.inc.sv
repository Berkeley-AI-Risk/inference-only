    // Refinement abstraction: the eight current working words, the sixteen
    // schedule words W[t]..W[t+15], and the current round. The initial-state
    // and per-transition assertions below implement FIPS 180-4 §6.2.2, with
    // two specified SHA rounds per actual source clock. No DUT state is cut.
    __REFERENCE_FUNCTIONS__
    wire [255:0] f_work={a_q,b_q,c_q,d_q,e_q,f_q,g_q,h_q};
    wire [511:0] f_schedule;
    generate for(genvar j=0;j<16;j=j+1) begin: f_schedule_view
        assign f_schedule[511-j*32 -: 32]=schedule_q[j];
    end endgenerate
    wire [31:0] f_new0=f_s1(schedule_q[14])+schedule_q[9]+
        f_s0(schedule_q[1])+schedule_q[0];
    wire [31:0] f_new1=f_s1(schedule_q[15])+schedule_q[10]+
        f_s0(schedule_q[2])+schedule_q[1];
    wire [255:0] f_step1=f_round(f_work,schedule_q[0],f_k(round_q));
    wire [255:0] f_step2=f_round(f_step1,schedule_q[1],f_k(round_q+6'd1));
    wire [511:0] f_next_schedule={f_schedule[447:0],f_new0,f_new1};
    logic f_past_valid=0;
    logic [6:0] f_age_q;
    logic [255:0] f_accepted_chain_q;
    always_ff @(posedge clk_i or negedge reset_n_i) begin
        if(!reset_n_i) begin f_age_q<=0;f_accepted_chain_q<=0;end
        else if(start_i && !busy_o) begin f_age_q<=0;f_accepted_chain_q<=state_i;end
        else if(busy_o) f_age_q<=f_age_q+7'd2;
    end
    // Split the complete 256-bit working-state transition into its eight
    // 32-bit conjuncts. The conjunction is the same FIPS transition property.
    generate for(genvar lane=0;lane<8;lane=lane+1) begin: f_work_step
        always_ff @(posedge clk_i) if(reset_n_i && f_past_valid &&
            $past(reset_n_i) && $past(busy_o))
            assert(f_work[lane*32 +: 32]==$past(f_step2[lane*32 +: 32]));
    end endgenerate
    always_ff @(posedge clk_i) begin
        f_past_valid<=1;
        if(reset_n_i) begin
            assert(round_q<=62 && !round_q[0]);
            assert(!(busy_o && done_o));
            assert(f_age_q<=64 && !f_age_q[0]);
            if(busy_o) assert(f_age_q=={1'b0,round_q});
            if(done_o) begin
                assert(f_age_q==64);
                // Exact private interface contract: feed-forward uses live
                // state_i. Parent preservation of the accepted chain is a
                // separate obligation; it is not assumed in this proof.
                assert(state_o==f_feedforward(state_i,f_work));
                if(state_i==f_accepted_chain_q)
                    assert(state_o==f_feedforward(f_accepted_chain_q,f_work));
            end
            if(f_past_valid) begin
                if(!$past(reset_n_i)) begin
                    assert(!busy_o && !done_o && round_q==0 && f_age_q==0);
                    assert(f_work==0 && f_schedule==0);
                end else if($past(start_i && !busy_o)) begin
                    assert(busy_o && !done_o && round_q==0 && f_age_q==0);
                    assert(f_work==$past(state_i));
                    assert(f_schedule==$past(block_i));
                end else if($past(busy_o)) begin
                    // Full working-state equality is checked per word above.
                    assert(f_schedule==$past(f_next_schedule));
                    if($past(round_q)==62)
                        assert(!busy_o && done_o && round_q==62 && f_age_q==64);
                    else
                        assert(busy_o && !done_o && round_q==$past(round_q)+6'd2);
                end else begin
                    assert(!busy_o && !done_o);
                    assert(f_work==$past(f_work) && f_schedule==$past(f_schedule));
                    assert(round_q==$past(round_q) && f_age_q==$past(f_age_q));
                end
            end
            cover(done_o);
        end
    end
