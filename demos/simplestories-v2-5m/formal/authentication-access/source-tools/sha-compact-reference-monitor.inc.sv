    // Independent circular schedule and packed working-state specification.
    // The DUT shifts sixteen words physically; this observer changes one ring
    // slot and advances a four-bit pointer. No observer drives native logic.
    // At round t, ring[(head+j) mod 16] denotes W[t+j]. The overwritten slot
    // receives W[t+16]=sigma1(W[t+14])+W[t+9]+sigma0(W[t+1])+W[t].
    // Working-state equations and final additions are FIPS 180-4 §6.2.2.
    __REFERENCE_K_FUNCTION__
    function automatic [31:0] f_s0(input [31:0] x);
        f_s0={x[6:0],x[31:7]} ^ {x[17:0],x[31:18]} ^ {3'd0,x[31:3]};
    endfunction
    function automatic [31:0] f_s1(input [31:0] x);
        f_s1={x[16:0],x[31:17]} ^ {x[18:0],x[31:19]} ^ {10'd0,x[31:10]};
    endfunction
    function automatic [31:0] f_S0(input [31:0] x);
        f_S0={x[1:0],x[31:2]} ^ {x[12:0],x[31:13]} ^ {x[21:0],x[31:22]};
    endfunction
    function automatic [31:0] f_S1(input [31:0] x);
        f_S1={x[5:0],x[31:6]} ^ {x[10:0],x[31:11]} ^ {x[24:0],x[31:25]};
    endfunction
    function automatic [255:0] f_round(input [255:0] v,
        input [31:0] w, input [31:0] k);
        reg [31:0] a,b,c,d,e,f,g,h,t1,t2;
        begin
            {a,b,c,d,e,f,g,h}=v;
            t1=h+f_S1(e)+((e & f) ^ (~e & g))+k+w;
            t2=f_S0(a)+((a & b) ^ (a & c) ^ (b & c));
            f_round={32'(t1+t2),a,b,c,32'(d+t1),e,f,g};
        end
    endfunction
    function automatic [255:0] f_feedforward(input [255:0] chain,
        input [255:0] work);
        integer n;
        for(n=0;n<8;n=n+1)
            f_feedforward[n*32 +: 32]=chain[n*32 +: 32]+work[n*32 +: 32];
    endfunction
    logic [31:0] f_ring_q [0:15];
    logic [3:0] f_head_q;
    logic [255:0] f_work_q, f_chain_q, f_result_q;
    logic f_busy_q, f_done_q;
    logic [5:0] f_round_q;
    logic [6:0] f_age_q;
    wire [3:0] f_p14=f_head_q+4'd14;
    wire [3:0] f_p9=f_head_q+4'd9;
    wire [3:0] f_p1=f_head_q+4'd1;
    wire [31:0] f_new_word=f_s1(f_ring_q[f_p14])+f_ring_q[f_p9]+
        f_s0(f_ring_q[f_p1])+f_ring_q[f_head_q];
    wire [255:0] f_next_work=f_round(f_work_q,f_ring_q[f_head_q],f_k(f_round_q));
    integer f_i;
    always_ff @(posedge clk_i or negedge reset_n_i) begin
        if(!reset_n_i) begin
            f_head_q<=0; f_work_q<=0; f_chain_q<=0; f_result_q<=0;
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
                f_ring_q[f_head_q]<=f_new_word;
                f_head_q<=f_head_q+4'd1;
                f_work_q<=f_next_work;
                f_age_q<=f_age_q+7'd1;
                if(f_round_q==63) begin
                    f_result_q<=f_feedforward(f_chain_q,f_next_work);
                    f_done_q<=1;
                    f_busy_q<=0;
                end else f_round_q<=f_round_q+6'd1;
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
        assert(initial_state_q==f_chain_q);
        assert(state_o==f_result_q);
        // Combinational correspondences are proved as invariants as well;
        // they expose the local arithmetic obligation to the induction engine.
        assert(next_a==f_next_work[255:224]);
        assert(next_e==f_next_work[127:96]);
        assert(schedule_next==f_new_word);
        assert(f_age_q<=64);
        assert(f_head_q==f_age_q[3:0]);
        if(f_busy_q) assert(f_age_q=={1'b0,f_round_q});
        if(f_done_q) assert(f_age_q==64 && !f_busy_q);
        cover(done_o);
    end
