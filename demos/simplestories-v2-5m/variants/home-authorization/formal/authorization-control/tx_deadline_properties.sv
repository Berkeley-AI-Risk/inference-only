    assign proof_remaining_o=busy_q ?
        (12'd9-12'(bit_q))*12'(CLKS_PER_BIT)+12'(counter_q)+12'd1 : 12'd0;
    always_comb if(rst_n) begin
        assert(bit_q<=9);
        assert(counter_q<CLKS_PER_BIT);
        if(busy_q) assert(proof_remaining_o>0 && proof_remaining_o<=2170);
    end
