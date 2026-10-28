    reg f_operands_owned,f_product_owned,f_tail_owned,f_first_seen;
    reg [4:0] f_age;
    reg [15:0] f_acc_mask;
    reg f_metadata_owned,f_read_target,f_dot_read_target;
    reg [23:0] f_metadata_shadow,f_read_shadow;
    reg [34:0] f_dot_shadow,f_dot_read_shadow;
    assign f_acc_owned_o=&f_acc_mask;
    assign f_first_seen_o=f_first_seen;
    assign f_busy_o=slice_busy_q;
    assign f_drained_o=!slice_busy_q && !op_valid_q && !product_valid_q;
    assign f_slice_o=slice_q;
    always @(posedge clk)begin
        if(!reset_n || kill_i || begin_i)begin
            f_operands_owned<=0;f_product_owned<=0;f_tail_owned<=0;f_first_seen<=0;
            f_age<=0;f_acc_mask<=0;f_metadata_owned<=0;f_read_target<=0;f_dot_read_target<=0;
        end else begin
            if(accept_i)begin
                f_tail_owned<=1;f_first_seen<=1;
                if(!f_first_seen)f_age<=0;
            end
            if(f_first_seen && f_age<31)f_age<=f_age+1'b1;
            if(issue)f_operands_owned<=accept_i || f_tail_owned;
            if(op_valid_q)f_product_owned<=f_operands_owned;
            if(product_valid_q && !read_i)begin
                f_acc_mask[product_group_q]<=f_product_owned &&
                    (product_first_q || f_acc_mask[product_group_q]);
                if(product_group_q==f_observed_lane_i)
                    f_dot_shadow<=g_lane[0].next_sum[34:0];
            end
            if(metadata_write_i && metadata_lane_i==f_observed_lane_i)begin
                f_metadata_owned<=1;f_metadata_shadow<={metadata_multiplier_i,metadata_exponent_i};end
            if(read_i)begin
                f_read_target<=(read_lane_i==f_observed_lane_i)&&f_metadata_owned;
                f_read_shadow<=f_metadata_shadow;
                f_dot_read_target<=(read_lane_i==f_observed_lane_i)&&f_acc_mask[f_observed_lane_i];
                f_dot_read_shadow<=f_dot_shadow;
            end
        end
    end
    always @*if(reset_n && !kill_i && !begin_i)begin
        if(accept_i)begin
            assert(!slice_busy_q);
            if(!f_first_seen)assert(first_i);
        end
        if(slice_busy_q)assert(f_tail_owned);
        if(f_parent_drain_i)assert(!accept_i);
        if((slice_busy_q && beat_last_q) || (op_valid_q && op_last_q) ||
           (product_valid_q && product_last_q))assert(f_parent_drain_i);
        if(op_valid_q && op_group_q==15)assert(!slice_busy_q);
        if(product_valid_q && product_last_q && product_group_q==15)begin
            assert(!slice_busy_q);assert(!op_valid_q);
        end
        if(op_valid_q)assert(f_operands_owned);
        if(product_valid_q)begin
            assert(f_product_owned);
            if(!product_first_q)assert(f_acc_mask[product_group_q]);
        end
        if(f_first_seen)begin
            if(f_age<15)begin
                assert(slice_busy_q);assert(beat_first_q);
                assert({1'b0,slice_q}==f_age+1'b1);
            end
            if(f_age<=15)begin
                assert(op_valid_q);assert(op_first_q);
                assert({1'b0,op_group_q}==f_age);
            end
            if(f_age>=1 && f_age<=16)begin
                assert(product_valid_q);assert(product_first_q);
                assert({1'b0,product_group_q}==f_age-1'b1);
            end
            if(f_age>=17)assert(&f_acc_mask);
            else if(f_age<=1)assert(f_acc_mask==0);
            else assert(f_acc_mask==((17'b1<<(f_age-1'b1))-1'b1));
        end else begin
            assert(!slice_busy_q);assert(!op_valid_q);assert(!product_valid_q);assert(f_acc_mask==0);
        end
        if(done_o)begin
            assert(&f_acc_mask);assert(!slice_busy_q);assert(!op_valid_q);assert(!product_valid_q);
        end
        if(read_i)begin
            assert(&f_acc_mask);assert(!slice_busy_q);assert(!op_valid_q);assert(!product_valid_q);
        end
        if(f_acc_mask[f_observed_lane_i])assert(g_lane[0].accumulator_q[f_observed_lane_i]==f_dot_shadow);
        if(f_metadata_owned)assert({multiplier_q[f_observed_lane_i],exponent_q[f_observed_lane_i]}==f_metadata_shadow);
        if(f_read_target)assert({multiplier_o,exponent_o}==f_read_shadow);
        if(f_dot_read_target)assert(dot_o==f_dot_read_shadow);
    end
