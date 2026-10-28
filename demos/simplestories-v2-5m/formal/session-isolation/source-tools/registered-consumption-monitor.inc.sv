    reg f_ws_read_live,f_out_read_live,f_query_read_live,f_acc_read_live;
    reg [12:0] f_ws_read_tag;
    reg [7:0] f_out_read_tag;
    reg [4:0] f_query_read_tag,f_acc_read_tag;
    reg [7:0] f_aligned_owned;
    reg f_capture_owned;
    reg f_norm_captured;
    reg f_past_valid=0;
    wire f_new_start=start_valid_i && start_ready_o;
    wire f_ws_consume=((state_q==ST_NORM_CAPTURE || state_q==ST_NORM_SELECT) && !normalize_output_q) ||
        state_q==ST_SCORE_NORM_FIND || state_q==ST_SCORE_NORM_WRITE || state_q==ST_SCORE_MAX ||
        state_q==ST_EXP || state_q==ST_PROBABILITY_REQUEST || state_q==ST_VALUE_ACCUMULATE;
    wire f_out_consume=((state_q==ST_NORM_CAPTURE || state_q==ST_NORM_SELECT) && normalize_output_q) ||
        state_q==ST_OUTPUT_NORM_FIND || state_q==ST_OUTPUT_NORM_WRITE || state_q==ST_RESULT_CAPTURE;
    always @(posedge clk)begin
        f_past_valid<=1;
        if(!rst_n || clear_i || !interface_live || f_new_start)begin
            f_ws_read_live<=0;f_out_read_live<=0;f_query_read_live<=0;f_acc_read_live<=0;
            f_aligned_owned<=0;f_capture_owned<=0;f_norm_captured<=0;
        end else begin
            if(workspace_bram_read_enable)begin
                f_ws_read_live<=1;f_ws_read_tag<=workspace_bram_read_address;
            end
            if(workspace_bram_write_enable ||
               (state_q==ST_NORM_SELECT && !normalize_output_q) || state_q==ST_SCORE_MAX ||
               ((state_q==ST_SCORE_NORM_FIND || state_q==ST_SCORE_NORM_WRITE || state_q==ST_EXP) &&
                 shift_request_valid && shift_request_ready) ||
               (state_q==ST_PROBABILITY_REQUEST && div_request_valid && div_request_ready) ||
               (state_q==ST_VALUE_ACCUMULATE && coordinate_q==56))f_ws_read_live<=0;
            if(output_bram_read_enable)begin
                f_out_read_live<=1;f_out_read_tag<=output_bram_read_address;
            end
            if(output_bram_write_enable || (state_q==ST_NORM_SELECT && normalize_output_q) ||
               ((state_q==ST_OUTPUT_NORM_FIND || state_q==ST_OUTPUT_NORM_WRITE) &&
                 shift_request_valid && shift_request_ready) || state_q==ST_RESULT_CAPTURE)
                f_out_read_live<=0;
            if(query_bram_read_enable)begin
                f_query_read_live<=1;f_query_read_tag<=query_bram_read_address;
            end
            if(query_bram_write_enable)f_query_read_live<=0;
            if(accumulator_read_enable)begin
                f_acc_read_live<=1;f_acc_read_tag<=accumulator_read_address;
            end else if(accumulator_write_enable && f_acc_read_live &&
                accumulator_current_address==f_acc_read_tag)f_acc_read_live<=0;
            if(state_q==ST_VALUE_WAIT && cache_response_known_handshake)f_aligned_owned<=0;
            if(state_q==ST_ALIGN8_WAIT && align8_response_valid && !align8_response_fault)
                f_aligned_owned[coordinate_q[5:3]]<=1;
            if(cache_wait_state && cache_response_known_handshake)f_capture_owned<=1;
            if(state_q==ST_NORM_CAPTURE)f_norm_captured<=1;
            if(state_q==ST_NORM_SELECT)f_norm_captured<=0;
        end
        if(f_past_valid && rst_n && interface_live)begin
            if(f_ws_consume)begin
                assert(f_ws_read_live);
                assert(f_ws_read_tag=={attention_head_q,
                    (state_q==ST_VALUE_ACCUMULATE ? scan_position_q:element_q)});
            end
            if(f_out_consume)begin
                assert(f_out_read_live);
                assert(f_out_read_tag==(state_q==ST_RESULT_CAPTURE ?
                    {result_beat_q,coordinate_q}:element_q[7:0]));
            end
            if(state_q==ST_SCORE_QUERY_USE)begin
                assert(f_query_read_live);
                assert(f_query_read_tag=={attention_head_q,coordinate_q[5:3]});
                assert(coordinate_q[2:0]==0);
            end
            if(state_q==ST_SCORE_ACCUMULATE)assert(coordinate_q==0);
            if(accumulator_consume)begin
                assert(f_acc_read_live);assert(f_acc_read_tag==accumulator_current_address);
            end
            if(state_q==ST_VALUE_ALIGN || state_q==ST_ALIGN8_WAIT)begin
                assert(f_aligned_owned==((9'b1<<coordinate_q[5:3])-1'b1));
            end
            if(state_q==ST_VALUE_ACCUMULATE)assert(&f_aligned_owned);
            if(state_q==ST_SCORE_ACCUMULATE || state_q==ST_SCORE_QUERY_USE ||
               state_q==ST_VALUE_ALIGN || state_q==ST_ALIGN8_WAIT)assert(f_capture_owned);
            if(state_q==ST_NORM_SELECT)assert(f_norm_captured);
        end
        cover(f_past_valid && rst_n && clear_i);
    end
