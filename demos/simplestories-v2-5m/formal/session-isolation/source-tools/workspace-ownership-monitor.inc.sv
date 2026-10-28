    (* anyconst *) reg [12:0] f_workspace_address;
    reg [2:0] f_workspace_phase;
    reg f_past_valid=0;
    wire f_new_start=start_valid_i && start_ready_o;
    wire [1:0] f_target_head=f_workspace_address[12:11];
    wire [10:0] f_target_position=f_workspace_address[10:0];
    wire f_target_in_context=f_target_position<=position_q;
    wire [12:0] f_target_rank=__RAW_SCORE_PAIR_MAJOR__ ?
        {f_target_head[1],f_target_position,f_target_head[0]} : {f_target_position,f_target_head};
    wire [12:0] f_score_rank=__RAW_SCORE_PAIR_MAJOR__ ?
        {attention_head_q[1],scan_position_q,attention_head_q[0]} : {scan_position_q,attention_head_q};
    wire f_raw_pass=state_q==ST_SCORE_REQUEST || state_q==ST_SCORE_WAIT ||
        state_q==ST_SCORE_ACCUMULATE || state_q==ST_SCORE_QUERY_USE;
    reg [5:0] f_effective_state;
    always @* begin
        f_effective_state=state_q;
        if(state_q==ST_WORKSPACE_READ)f_effective_state=workspace_read_return_q;
        if(state_q==ST_SHIFT_WAIT)begin
            case(shift_client_q)
                SHIFT_CLIENT_SCORE_NORM_FIND:f_effective_state=ST_SCORE_NORM_FIND;
                SHIFT_CLIENT_SCORE_NORM_WRITE:f_effective_state=ST_SCORE_NORM_WRITE;
                SHIFT_CLIENT_EXP:f_effective_state=ST_EXP;
                default:f_effective_state=state_q;
            endcase
        end
    end
    wire f_raw_normalize=(f_effective_state==ST_NORM_CAPTURE ||
        f_effective_state==ST_NORM_SELECT) && !normalize_output_q;
    wire f_normalize_find=f_effective_state==ST_SCORE_NORM_FIND || f_raw_normalize;
    wire f_normalize_write=f_effective_state==ST_SCORE_NORM_WRITE;
    wire f_max_pass=f_effective_state==ST_SCORE_MAX;
    wire f_exp_pass=f_effective_state==ST_EXP || f_effective_state==ST_EXP_LUT_REQUEST ||
        f_effective_state==ST_EXP_WAIT;
    wire f_probability_pass=f_effective_state==ST_PROBABILITY_REQUEST ||
        f_effective_state==ST_PROBABILITY_WAIT;
    wire f_softmax_pass=f_normalize_find || f_normalize_write || f_max_pass ||
        f_exp_pass || f_probability_pass;
    wire f_value_pass=state_q==ST_VALUE_ZERO || state_q==ST_VALUE_REQUEST ||
        state_q==ST_VALUE_WAIT || state_q==ST_VALUE_ALIGN || state_q==ST_ALIGN8_WAIT ||
        f_effective_state==ST_VALUE_ACCUMULATE || state_q==ST_ACCUMULATOR_READ ||
        state_q==ST_VALUE_DIV_REQUEST || state_q==ST_VALUE_DIV_WAIT ||
        state_q==ST_NEXT_HEAD;
    wire f_after_softmax=f_value_pass || state_q==ST_OUTPUT_READ ||
        state_q==ST_OUTPUT_NORM_FIND || state_q==ST_OUTPUT_NORM_WRITE ||
        ((state_q==ST_NORM_CAPTURE || state_q==ST_NORM_SELECT) && normalize_output_q) ||
        (state_q==ST_SHIFT_WAIT && (shift_client_q==SHIFT_CLIENT_OUTPUT_NORM_FIND ||
                                 shift_client_q==SHIFT_CLIENT_OUTPUT_NORM_WRITE)) ||
        state_q==ST_RESULT_READ || state_q==ST_RESULT_CAPTURE ||
        state_q==ST_RESULT || state_q==ST_DONE;
    always @(posedge clk) begin
        f_past_valid<=1;
        if(!rst_n || clear_i || !interface_live || f_new_start)f_workspace_phase<=0;
        else if(workspace_bram_write_enable && workspace_bram_write_address==f_workspace_address)begin
            case(state_q)
                ST_SCORE_QUERY_USE:f_workspace_phase<=1;
                ST_SHIFT_WAIT:f_workspace_phase<=2;
                ST_EXP_WAIT:f_workspace_phase<=3;
                ST_PROBABILITY_WAIT:f_workspace_phase<=4;
                default:f_workspace_phase<=0;
            endcase
        end
        if(f_past_valid && rst_n && interface_live)begin
            assert(state_q<=ST_ACCUMULATOR_READ);
            assert(state_q!=ST_VALUE_EXP_REQUEST && state_q!=ST_VALUE_EXP_WAIT &&
                   state_q!=ST_VALUE_EXP_SCAN && state_q!=ST_EXP8_WAIT);
            assert(f_workspace_phase<=4);
            if(f_softmax_pass || f_value_pass)assert(!normalize_output_q);
            if(state_q==ST_OUTPUT_READ || state_q==ST_OUTPUT_NORM_FIND ||
               state_q==ST_OUTPUT_NORM_WRITE ||
               ((state_q==ST_NORM_CAPTURE || state_q==ST_NORM_SELECT) && normalize_output_q) ||
               (state_q==ST_SHIFT_WAIT && (shift_client_q==SHIFT_CLIENT_OUTPUT_NORM_FIND ||
                                          shift_client_q==SHIFT_CLIENT_OUTPUT_NORM_WRITE)))begin
                assert(normalize_output_q);
                assert(element_q<=255);
            end
            if(state_q==ST_WORKSPACE_READ)begin
                assert(workspace_read_return_q==ST_NORM_CAPTURE ||
                    workspace_read_return_q==ST_SCORE_NORM_FIND ||
                    workspace_read_return_q==ST_SCORE_NORM_WRITE ||
                    workspace_read_return_q==ST_SCORE_MAX ||
                    workspace_read_return_q==ST_EXP ||
                    workspace_read_return_q==ST_PROBABILITY_REQUEST ||
                    workspace_read_return_q==ST_VALUE_ACCUMULATE);
                assert(!normalize_output_q);
            end
            if(state_q==ST_OUTPUT_READ)begin
                assert(output_read_return_q==ST_NORM_CAPTURE ||
                    output_read_return_q==ST_OUTPUT_NORM_FIND ||
                    output_read_return_q==ST_OUTPUT_NORM_WRITE);
                assert(normalize_output_q);
            end
            if(f_raw_pass || f_softmax_pass || f_after_softmax)
                assert(scan_position_q<=position_q);
            if(f_raw_pass)begin
                assert(scan_position_q<=position_q);
                if(f_target_in_context && f_target_rank<f_score_rank)assert(f_workspace_phase==1);
            end
            if(f_softmax_pass)begin
                assert(!normalize_output_q);
                assert(element_q<=position_q);
                if(f_target_in_context)begin
                    if(f_target_head<attention_head_q)assert(f_workspace_phase==4);
                    if(f_target_head>attention_head_q)assert(f_workspace_phase==1);
                    if(f_target_head==attention_head_q)begin
                        if(f_normalize_find)assert(f_workspace_phase==1);
                        if(f_normalize_write)assert(f_workspace_phase==
                            ((f_target_position<element_q)?2:1));
                        if(f_max_pass)assert(f_workspace_phase==2);
                        if(f_exp_pass)assert(f_workspace_phase==
                            ((f_target_position<element_q)?3:2));
                        if(f_probability_pass)assert(f_workspace_phase==
                            ((f_target_position<element_q)?4:3));
                    end
                end
            end
            if(f_after_softmax && f_target_in_context)assert(f_workspace_phase==4);
            if(workspace_bram_read_enable)begin
                assert(!workspace_bram_write_enable);
                assert(workspace_bram_read_address[10:0]<=position_q);
                if(workspace_bram_read_address==f_workspace_address)assert(f_workspace_phase!=0);
            end
            if(workspace_bram_write_enable)begin
                assert(workspace_bram_write_address[10:0]<=position_q);
                assert(state_q==ST_SCORE_QUERY_USE || state_q==ST_SHIFT_WAIT ||
                       state_q==ST_EXP_WAIT || state_q==ST_PROBABILITY_WAIT);
            end
        end
        cover(f_past_valid && rst_n && clear_i);
    end
