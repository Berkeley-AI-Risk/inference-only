    // FIPS step refinement for the actual private resetless-payload engine.
    // Payload is loaded before BUSY; no initial RAM/register value is assumed.
    __REFERENCE_FUNCTIONS__
    wire [255:0] f_work={a_q,b_q,c_q,d_q,e_q,f_q,g_q,h_q};
    wire [511:0] f_schedule;
    generate for(genvar j=0;j<16;j=j+1) begin: f_schedule_view
        assign f_schedule[511-j*32 -: 32]=schedule_q[j];
    end endgenerate
    wire [31:0] f_new=f_s1(schedule_q[14])+schedule_q[9]+f_s0(schedule_q[1])+schedule_q[0];
    wire [255:0] f_step=f_round(f_work,schedule_q[0],f_k(round_q));
    wire [511:0] f_next_schedule={f_schedule[479:0],f_new};
    logic f_past_valid=0;
    logic f_loaded_q;
    logic [6:0] f_age_q;
    always_ff @(posedge clk_i or negedge reset_n_i) begin
        if(!reset_n_i) begin f_age_q<=0;f_loaded_q<=0;end
        else if(start_i && !busy_o) begin f_age_q<=0;f_loaded_q<=1;end
        else if(busy_o) f_age_q<=f_age_q+7'd1;
    end
    always_ff @(posedge clk_i) begin
        f_past_valid<=1;
        if(reset_n_i) begin
            assert(!(busy_o && done_o));
            assert(f_age_q<=64);
            if(busy_o || done_o) assert(f_loaded_q);
            if(busy_o) assert(f_age_q=={1'b0,round_q});
            if(done_o) begin
                assert(f_age_q==64 && round_q==63);
                assert(state_o==f_feedforward(state_i,f_work));
            end
            if(f_past_valid) begin
                if(!$past(reset_n_i)) begin
                    assert(!busy_o && !done_o && round_q==0 && !f_loaded_q && f_age_q==0);
                end else if($past(start_i && !busy_o)) begin
                    assert(busy_o && !done_o && round_q==0 && f_age_q==0 && f_loaded_q);
                    assert(f_work==$past(state_i));
                    assert(f_schedule==$past(block_i));
                end else if($past(busy_o)) begin
                    assert(f_work==$past(f_step));
                    assert(f_schedule==$past(f_next_schedule));
                    if($past(round_q)==63) assert(!busy_o && done_o && f_age_q==64);
                    else assert(busy_o && !done_o && round_q==$past(round_q)+6'd1);
                end else begin
                    assert(!busy_o && !done_o);
                    assert(f_work==$past(f_work) && f_schedule==$past(f_schedule));
                    assert(round_q==$past(round_q) && f_age_q==$past(f_age_q));
                end
            end
            cover(done_o);
        end
    end
