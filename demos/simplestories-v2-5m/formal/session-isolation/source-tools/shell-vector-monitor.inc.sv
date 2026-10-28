    (* anyconst *) reg [7:0] f_vector_word;
    reg f_embedding_owned,f_layer_owned,f_norm_owned;
    reg [15:0] f_embedding_shadow,f_layer_shadow,f_norm_shadow;
    reg f_embedding_read_target,f_layer_read_target,f_norm_read_target;
    reg [15:0] f_embedding_read_shadow,f_layer_read_shadow,f_norm_read_shadow;
    reg f_embedding_read_live,f_layer_read_live,f_norm_read_live;
    reg [7:0] f_embedding_read_tag,f_layer_read_tag,f_norm_read_tag;
    always @(posedge clk)begin
        if(!rst_n || clear_i)begin
            f_embedding_owned<=0;f_layer_owned<=0;f_norm_owned<=0;
            f_embedding_read_target<=0;f_layer_read_target<=0;f_norm_read_target<=0;
            f_embedding_read_live<=0;f_layer_read_live<=0;f_norm_read_live<=0;
        end else begin
            if(embed_start_transfer)begin f_embedding_owned<=0;f_embedding_read_target<=0;f_embedding_read_live<=0;end
            if(layer_start_transfer)begin f_layer_owned<=0;f_layer_read_target<=0;f_layer_read_live<=0;end
            if(rms_start_transfer)begin f_norm_owned<=0;f_norm_read_target<=0;f_norm_read_live<=0;end
            if(embed_result_transfer && embed_result_index==f_vector_word)begin
                f_embedding_owned<=1;f_embedding_shadow<=embed_result_mantissa;
            end
            if(layer_result_transfer && private_layer_result_index_i==f_vector_word)begin
                f_layer_owned<=1;f_layer_shadow<=private_layer_result_mantissa_i;
            end
            if(rms_result_transfer && rms_result_index==f_vector_word)begin
                f_norm_owned<=1;f_norm_shadow<=rms_result_mantissa;
            end
            if(state_q==ST_LAYER_INPUT_READ)begin
                f_embedding_read_live<=1;f_embedding_read_tag<=stream_index_q;
                f_embedding_read_target<=(stream_index_q==f_vector_word)&&f_embedding_owned;
                f_embedding_read_shadow<=f_embedding_shadow;
            end
            if(state_q==ST_RMS_INPUT_READ)begin
                f_layer_read_live<=1;f_layer_read_tag<=stream_index_q;
                f_layer_read_target<=(stream_index_q==f_vector_word)&&f_layer_owned;
                f_layer_read_shadow<=f_layer_shadow;
            end
            if(state_q==ST_HEAD_INPUT_READ)begin
                f_norm_read_live<=1;f_norm_read_tag<=stream_index_q;
                f_norm_read_target<=(stream_index_q==f_vector_word)&&f_norm_owned;
                f_norm_read_shadow<=f_norm_shadow;
            end
        end
    end
    always @*if(rst_n && !clear_i)begin
        if(f_embedding_owned)assert(embedding_mem_q[f_vector_word]==f_embedding_shadow);
        if(f_layer_owned)assert(layer5_mem_q[f_vector_word]==f_layer_shadow);
        if(f_norm_owned)assert(final_norm_mem_q[f_vector_word]==f_norm_shadow);
        if(f_embedding_read_target)assert(embedding_read_q==f_embedding_read_shadow);
        if(f_layer_read_target)assert(layer5_read_q==f_layer_read_shadow);
        if(f_norm_read_target)assert(final_norm_read_q==f_norm_read_shadow);
        if(!fail_q)begin
            if(state_q==ST_EMBED_CAPTURE && f_vector_word<capture_index_q)assert(f_embedding_owned);
            if(state_q>=ST_EMBED_DONE && state_q<=ST_TOKEN_HOLD)assert(f_embedding_owned);
            if(state_q==ST_LAYER_RESULT && f_vector_word<capture_index_q)assert(f_layer_owned);
            if(state_q>=ST_LAYER_DONE && state_q<=ST_TOKEN_HOLD)assert(f_layer_owned);
            if(state_q==ST_RMS_RESULT && f_vector_word<capture_index_q)assert(f_norm_owned);
            if(state_q>=ST_RMS_DONE && state_q<=ST_TOKEN_HOLD)assert(f_norm_owned);
            if(state_q==ST_LAYER_INPUT_SEND)begin
                assert(f_embedding_read_live);assert(f_embedding_read_tag==stream_index_q);
            end
            if(state_q==ST_RMS_INPUT_SEND)begin
                assert(f_layer_read_live);assert(f_layer_read_tag==stream_index_q);
            end
            if(state_q==ST_HEAD_INPUT_SEND)begin
                assert(f_norm_read_live);assert(f_norm_read_tag==stream_index_q);
            end
        end
        cover(append_transfer && tape_count_q==1);
    end
