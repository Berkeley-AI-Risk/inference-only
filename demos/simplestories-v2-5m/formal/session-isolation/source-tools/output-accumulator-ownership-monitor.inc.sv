    (* anyconst *) reg [7:0] f_output_address;
    (* anyconst *) reg [4:0] f_accumulator_address;
    (* anyconst *) reg [5:0] f_result_lane;
    reg [1:0] f_output_phase;
    reg f_accumulator_owned,f_result_owned;
    reg f_past_valid=0;
    wire f_new_start=start_valid_i && start_ready_o;
    wire [7:0] f_output_cursor={attention_head_q,coordinate_q};
    wire f_div_pass=state_q==ST_ACCUMULATOR_READ || state_q==ST_VALUE_DIV_REQUEST ||
        state_q==ST_VALUE_DIV_WAIT;
    wire f_output_find=state_q==ST_OUTPUT_NORM_FIND ||
        ((state_q==ST_NORM_CAPTURE || state_q==ST_NORM_SELECT) && normalize_output_q) ||
        (state_q==ST_OUTPUT_READ && output_read_return_q!=ST_OUTPUT_NORM_WRITE) ||
        (state_q==ST_SHIFT_WAIT && shift_client_q==SHIFT_CLIENT_OUTPUT_NORM_FIND);
    wire f_output_write=state_q==ST_OUTPUT_NORM_WRITE ||
        (state_q==ST_OUTPUT_READ && output_read_return_q==ST_OUTPUT_NORM_WRITE) ||
        (state_q==ST_SHIFT_WAIT && shift_client_q==SHIFT_CLIENT_OUTPUT_NORM_WRITE);
    wire f_result_pass=state_q==ST_RESULT_READ || state_q==ST_RESULT_CAPTURE ||
        state_q==ST_RESULT || state_q==ST_DONE;
    wire f_accumulator_active=state_q==ST_VALUE_REQUEST || state_q==ST_VALUE_WAIT ||
        state_q==ST_VALUE_ALIGN || state_q==ST_ALIGN8_WAIT || state_q==ST_VALUE_ACCUMULATE ||
        (state_q==ST_WORKSPACE_READ && workspace_read_return_q==ST_VALUE_ACCUMULATE) ||
        f_div_pass || state_q==ST_NEXT_HEAD || f_output_find || f_output_write || f_result_pass;
    always @(posedge clk) begin
        f_past_valid<=1;
        if(!rst_n || clear_i || !interface_live || f_new_start)begin
            f_output_phase<=0;f_result_owned<=0;
        end else begin
            if(output_bram_write_enable && output_bram_write_address==f_output_address)
                f_output_phase<=output_bram_write_raw?1:2;
            if(state_q==ST_RESULT_CAPTURE && coordinate_q==f_result_lane)
                f_result_owned<=1;
            if(state_q==ST_RESULT && result_valid_o && result_ready_i && result_beat_q!=3)
                f_result_owned<=0;
        end
        if(!rst_n || clear_i || upstream_fault_i || range_fault_o || !model_lock_i || f_new_start)
            f_accumulator_owned<=0;
        else if(accumulator_write_enable && state_q==ST_VALUE_ZERO &&
                accumulator_current_address==f_accumulator_address)f_accumulator_owned<=1;
        if(f_past_valid && rst_n && interface_live)begin
            assert(state_q<=ST_ACCUMULATOR_READ);
            assert(state_q!=ST_VALUE_EXP_REQUEST && state_q!=ST_VALUE_EXP_WAIT &&
                   state_q!=ST_VALUE_EXP_SCAN && state_q!=ST_EXP8_WAIT);
            assert(f_output_phase<=2);
            assert(f_accumulator_owned==accumulator_initialized_groups_q[f_accumulator_address]);
            if(f_div_pass && f_output_address<f_output_cursor)assert(f_output_phase==1);
            if(state_q==ST_NEXT_HEAD && f_output_address<=f_output_cursor)assert(f_output_phase==1);
            if(state_q==ST_NEXT_HEAD)assert(coordinate_q==63);
            if(f_output_find)assert(f_output_phase==1);
            if(f_output_write)assert(f_output_phase==((f_output_address<element_q)?2:1));
            if(f_result_pass)assert(f_output_phase==2);
            if(f_output_find || f_output_write)begin
                assert(normalize_output_q);assert(element_q<=255);
            end
            if(state_q==ST_OUTPUT_READ)assert(output_read_return_q==ST_NORM_CAPTURE ||
                output_read_return_q==ST_OUTPUT_NORM_FIND || output_read_return_q==ST_OUTPUT_NORM_WRITE);
            if(state_q==ST_WORKSPACE_READ)assert(workspace_read_return_q==ST_NORM_CAPTURE ||
                workspace_read_return_q==ST_SCORE_NORM_FIND || workspace_read_return_q==ST_SCORE_NORM_WRITE ||
                workspace_read_return_q==ST_SCORE_MAX || workspace_read_return_q==ST_EXP ||
                workspace_read_return_q==ST_PROBABILITY_REQUEST || workspace_read_return_q==ST_VALUE_ACCUMULATE);
            if(state_q==ST_WORKSPACE_READ || state_q==ST_SCORE_NORM_FIND ||
               state_q==ST_SCORE_NORM_WRITE || state_q==ST_SCORE_MAX || state_q==ST_EXP ||
               state_q==ST_PROBABILITY_REQUEST || state_q==ST_PROBABILITY_WAIT ||
               state_q==ST_EXP_LUT_REQUEST || state_q==ST_EXP_WAIT ||
               (state_q==ST_SHIFT_WAIT && (shift_client_q==SHIFT_CLIENT_SCORE_NORM_FIND ||
                   shift_client_q==SHIFT_CLIENT_SCORE_NORM_WRITE || shift_client_q==SHIFT_CLIENT_EXP)))
                assert(!normalize_output_q);
            if(output_bram_read_enable && output_bram_read_address==f_output_address)
                assert(f_output_phase!=0);
            if(output_bram_read_enable)assert(!output_bram_write_enable);
            if(f_accumulator_active)assert(&accumulator_initialized_groups_q);
            if(state_q==ST_VALUE_ZERO || state_q==ST_VALUE_REQUEST || state_q==ST_VALUE_WAIT ||
               state_q==ST_VALUE_ALIGN || state_q==ST_ALIGN8_WAIT || state_q==ST_VALUE_ACCUMULATE ||
               f_div_pass || state_q==ST_NEXT_HEAD)assert(!normalize_output_q);
            if(accumulator_read_enable && accumulator_read_address==f_accumulator_address)
                assert(f_accumulator_owned);
            if(accumulator_consume)begin
                assert(accumulator_read_valid);
                assert(accumulator_read_tag==accumulator_current_address);
                assert(f_accumulator_owned);
            end
            if(accumulator_read_enable && accumulator_write_enable)
                assert(accumulator_read_address!=accumulator_current_address);
            if(state_q==ST_VALUE_ZERO || state_q==ST_VALUE_ACCUMULATE ||
               state_q==ST_VALUE_ALIGN || state_q==ST_ALIGN8_WAIT)assert(coordinate_q[2:0]==0);
            if((state_q==ST_RESULT_READ || state_q==ST_RESULT_CAPTURE) && f_result_lane<coordinate_q)
                assert(f_result_owned);
            if(state_q==ST_RESULT)assert(f_result_owned);
        end
        cover(f_past_valid && rst_n && clear_i);
    end
