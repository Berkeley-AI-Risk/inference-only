    logic spec_initial=1;
    always_ff @(posedge clk) spec_initial<=0;
    always_comb if(spec_initial) assume(!reset_n);
    logic spec_pending;
    logic [1:0] spec_owner;
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin spec_pending<=0;spec_owner<=0;end
        else begin
            if(accept0_o || accept1_o || accept2_o) begin
                spec_pending<=1;
                if(accept0_o) spec_owner<=0;
                else if(accept1_o) spec_owner<=1;
                else spec_owner<=2;
            end
            if(done && spec_pending) spec_pending<=0;
        end
    end
    always_comb if(reset_n) begin
        assert(!(accept0_o && accept1_o));
        assert(!(accept0_o && accept2_o));
        assert(!(accept1_o && accept2_o));
        assert(!(done0_o && done1_o));
        assert(!(done0_o && done2_o));
        assert(!(done1_o && done2_o));
        assert(occupied_q==spec_pending);
        if(occupied_q) begin assert(owner_q==spec_owner);assert(owner_q<3);end
        if(accept0_o) assert(request0_i && !spec_pending);
        if(accept1_o) assert(request1_i && !spec_pending);
        if(accept2_o) assert(request2_i && !spec_pending);
        if(done0_o) assert(spec_pending && spec_owner==0 && done);
        if(done1_o) assert(spec_pending && spec_owner==1 && done);
        if(done2_o) assert(spec_pending && spec_owner==2 && done);
        if((busy || done) && !fault_q) assert(spec_pending);
    end
