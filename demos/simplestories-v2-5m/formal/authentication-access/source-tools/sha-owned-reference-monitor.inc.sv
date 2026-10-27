    __REFERENCE_FUNCTIONS__
    logic [31:0] f_ring_q [0:15];
    logic [3:0] f_head_q;
    logic [255:0] f_work_q, f_chain_q;
    logic f_busy_q, f_done_q;
    logic [5:0] f_round_q;
    logic [6:0] f_age_q;
    wire [3:0] f_p1=f_head_q+4'd1;
    wire [3:0] f_p2=f_head_q+4'd2;
    wire [3:0] f_p9=f_head_q+4'd9;
    wire [3:0] f_p10=f_head_q+4'd10;
    wire [3:0] f_p14=f_head_q+4'd14;
    wire [3:0] f_p15=f_head_q+4'd15;
    wire [31:0] f_new0=f_s1(f_ring_q[f_p14])+f_ring_q[f_p9]+
        f_s0(f_ring_q[f_p1])+f_ring_q[f_head_q];
    wire [31:0] f_new1=f_s1(f_ring_q[f_p15])+f_ring_q[f_p10]+
        f_s0(f_ring_q[f_p2])+f_ring_q[f_p1];
    wire [255:0] f_round1=f_round(f_work_q,f_ring_q[f_head_q],f_k(f_round_q));
    wire [255:0] f_round2=f_round(f_round1,f_ring_q[f_p1],f_k(f_round_q+6'd1));
    integer f_i;
    always_ff @(posedge clk_i or negedge reset_n_i) begin
        if(!reset_n_i) begin
            f_head_q<=0; f_work_q<=0; f_chain_q<=0;
            f_busy_q<=0; f_done_q<=0; f_round_q<=0; f_age_q<=0;
            for(f_i=0;f_i<16;f_i=f_i+1) f_ring_q[f_i]<=0;
        end else begin
            f_done_q<=0;
            if(start_i && !f_busy_q) begin
                f_head_q<=0; f_work_q<=state_i; f_chain_q<=state_i;
                f_busy_q<=1; f_round_q<=0; f_age_q<=0;
                for(f_i=0;f_i<16;f_i=f_i+1)
                    f_ring_q[f_i]<=block_i[511-f_i*32 -: 32];
            end else if(f_busy_q) begin
                f_ring_q[f_head_q]<=f_new0;
                f_ring_q[f_p1]<=f_new1;
                f_head_q<=f_head_q+4'd2;
                f_work_q<=f_round2;
                f_age_q<=f_age_q+7'd2;
                if(f_round_q==62) begin f_done_q<=1;f_busy_q<=0;end
                else f_round_q<=f_round_q+6'd2;
            end
        end
    end
    generate for(genvar j=0;j<16;j=j+1) begin: f_schedule_relation
        wire [3:0] slot=f_head_q+4'(j);
        always_ff @(posedge clk_i) if(reset_n_i)
            assert(schedule_q[j]==f_ring_q[slot]);
    end endgenerate
    always_ff @(posedge clk_i) if(reset_n_i) begin
        assert(busy_o==f_busy_q);
        assert(done_o==f_done_q);
        assert(round_q==f_round_q);
        assert({a_q,b_q,c_q,d_q,e_q,f_q,g_q,h_q}==f_work_q);
        assert(f_age_q<=64 && !f_age_q[0]);
        assert(f_head_q==f_age_q[3:0]);
        if(f_busy_q) assert(f_age_q=={1'b0,f_round_q});
        if(f_done_q) begin
            assert(f_age_q==64 && !f_busy_q);
            // The native REGISTER_RESULT=0 interface uses the live chaining
            // input for feed-forward. No arbitrary-changing-input digest
            // contract is claimed for this private bank-owned interface.
            assert(state_o==f_feedforward(state_i,f_work_q));
            if(state_i==f_chain_q)
                assert(state_o==f_feedforward(f_chain_q,f_work_q));
        end
        assert(a_r2==f_round2[255:224]);
        assert(e_r2==f_round2[127:96]);
        assert(schedule_next0==f_new0);
        assert(schedule_next1==f_new1);
        cover(done_o);
    end
