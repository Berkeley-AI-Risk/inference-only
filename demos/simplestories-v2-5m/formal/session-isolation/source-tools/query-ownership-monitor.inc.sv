    // One symbolic address represents every one of the 256 scalar query words.
    (* anyconst *) reg [7:0] f_query_address;
    reg f_query_written;
    reg f_query_staging_owned;
    reg f_query_upload_complete;
    reg f_past_valid=0;
    wire f_new_start=start_valid_i && start_ready_o;
    wire f_query_upload=(state_q==ST_QUERY_LOAD || state_q==ST_QUERY_STORE);
    wire f_query_late=state_q!=ST_IDLE && state_q!=ST_QUERY_LOAD &&
        state_q!=ST_QUERY_STORE && state_q!=ST_FAULT && state_q!=ST_CLEAR_DRAIN;
    always @(posedge clk) begin
        f_past_valid<=1;
        if(!rst_n || clear_i || !interface_live || f_new_start) begin
            f_query_written<=0;
            f_query_staging_owned<=0;
            f_query_upload_complete<=0;
        end else begin
            if(query_bram_write_enable && query_bram_write_address==f_query_address)
                f_query_written<=1;
            if(state_q==ST_QUERY_LOAD && query_valid_i && query_ready_o &&
               query_vector_legal_comb && query_last_i==(query_beat_q==3))
                f_query_staging_owned<=1;
            if(query_bram_write_enable && coordinate_q==63)f_query_staging_owned<=0;
            if(query_bram_write_enable && query_bram_write_address==255)
                f_query_upload_complete<=1;
        end
        if(f_past_valid && rst_n && interface_live) begin
            assert(state_q<=ST_ACCUMULATOR_READ);
            if(state_q==ST_QUERY_STORE)assert(f_query_staging_owned);
            if(f_query_upload && f_query_address < {query_beat_q,6'd0})
                assert(f_query_written);
            if(state_q==ST_QUERY_STORE && f_query_address < {query_beat_q,coordinate_q})
                assert(f_query_written);
            if(f_query_late)begin
                assert(f_query_upload_complete);
                assert(f_query_written);
            end
            if(query_bram_read_enable)begin
                assert(f_query_upload_complete);
                assert(f_query_written);
            end
            if(query_bram_write_enable)begin
                assert(state_q==ST_QUERY_STORE);
                assert(f_query_staging_owned);
            end
        end
        cover(f_past_valid && interface_live && state_q==ST_QUERY_STORE &&
              coordinate_q==2 && query_beat_q==0);
    end
