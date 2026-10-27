    logic [BANKS-1:0] f_parent_bank_pending_q;
    logic [17:0] f_parent_bank_word_q [0:BANKS-1];
    logic [4:0] f_parent_bank_slot_q [0:BANKS-1];
    generate for(genvar f_b=0;f_b<BANKS;f_b=f_b+1) begin: f_consumer_bank
        // Identical recurrence to the independently proved bank reference.
        // Actual child port wiring is checked by the composition audit.
        always_ff @(posedge clk or negedge reset_n) begin
            if(!reset_n) begin
                f_parent_bank_pending_q[f_b]<=0;
                f_parent_bank_word_q[f_b]<=0;f_parent_bank_slot_q[f_b]<=0;
            end else if(cancel_i) f_parent_bank_pending_q[f_b]<=0;
            else if(bank_read_valid[f_b] && bank_read_ready[f_b]) begin
                f_parent_bank_pending_q[f_b]<=1;
                f_parent_bank_word_q[f_b]<=head_word;
                f_parent_bank_slot_q[f_b]<=response_write_q;
            end else if(bank_response_valid[f_b] && bank_response_ready[f_b])
                f_parent_bank_pending_q[f_b]<=0;
        end
        always_ff @(posedge clk) if(reset_n && enabled && !cancel_i) begin
            // These are child guarantees with separate native RTL proofs,
            // not promises about the caller, DDR data or payload arithmetic.
            assume(bank_response_valid[f_b]==f_parent_bank_pending_q[f_b]);
            if(bank_read_ready[f_b]) assume(!f_parent_bank_pending_q[f_b] || bank_response_ready[f_b]);
        end
        always_ff @(posedge clk) if(reset_n && !fault_o) begin
            if(f_parent_bank_pending_q[f_b]) begin
                assert(response_count_q!=0);
                assert(6'(5'(f_parent_bank_slot_q[f_b]-response_read_q))<response_count_q);
                assert(!response_fifo[f_parent_bank_slot_q[f_b]][BANK_W]);
                assert(response_fifo[f_parent_bank_slot_q[f_b]][BANK_W-1:0]==BANK_W'(f_b));
                assert(f_route_words[f_parent_bank_slot_q[f_b]]==f_parent_bank_word_q[f_b]);
                assert(f_parent_bank_word_q[f_b]<IMAGE_WORDS);
            end
        end
    end endgenerate
    always_ff @(posedge clk) if(reset_n && !fault_o) begin
        if(6'(5'(5'(0)-response_read_q))<response_count_q && !response_fifo[0][BANK_W]) begin
            assert(f_parent_bank_pending_q[response_fifo[0][BANK_W-1:0]]);
            assert(f_parent_bank_slot_q[response_fifo[0][BANK_W-1:0]]==0 && f_route_words[0]==f_parent_bank_word_q[response_fifo[0][BANK_W-1:0]]);
        end
        if(6'(5'(5'(1)-response_read_q))<response_count_q && !response_fifo[1][BANK_W]) begin
            assert(f_parent_bank_pending_q[response_fifo[1][BANK_W-1:0]]);
            assert(f_parent_bank_slot_q[response_fifo[1][BANK_W-1:0]]==1 && f_route_words[1]==f_parent_bank_word_q[response_fifo[1][BANK_W-1:0]]);
        end
        if(6'(5'(5'(2)-response_read_q))<response_count_q && !response_fifo[2][BANK_W]) begin
            assert(f_parent_bank_pending_q[response_fifo[2][BANK_W-1:0]]);
            assert(f_parent_bank_slot_q[response_fifo[2][BANK_W-1:0]]==2 && f_route_words[2]==f_parent_bank_word_q[response_fifo[2][BANK_W-1:0]]);
        end
        if(6'(5'(5'(3)-response_read_q))<response_count_q && !response_fifo[3][BANK_W]) begin
            assert(f_parent_bank_pending_q[response_fifo[3][BANK_W-1:0]]);
            assert(f_parent_bank_slot_q[response_fifo[3][BANK_W-1:0]]==3 && f_route_words[3]==f_parent_bank_word_q[response_fifo[3][BANK_W-1:0]]);
        end
        if(6'(5'(5'(4)-response_read_q))<response_count_q && !response_fifo[4][BANK_W]) begin
            assert(f_parent_bank_pending_q[response_fifo[4][BANK_W-1:0]]);
            assert(f_parent_bank_slot_q[response_fifo[4][BANK_W-1:0]]==4 && f_route_words[4]==f_parent_bank_word_q[response_fifo[4][BANK_W-1:0]]);
        end
        if(6'(5'(5'(5)-response_read_q))<response_count_q && !response_fifo[5][BANK_W]) begin
            assert(f_parent_bank_pending_q[response_fifo[5][BANK_W-1:0]]);
            assert(f_parent_bank_slot_q[response_fifo[5][BANK_W-1:0]]==5 && f_route_words[5]==f_parent_bank_word_q[response_fifo[5][BANK_W-1:0]]);
        end
        if(6'(5'(5'(6)-response_read_q))<response_count_q && !response_fifo[6][BANK_W]) begin
            assert(f_parent_bank_pending_q[response_fifo[6][BANK_W-1:0]]);
            assert(f_parent_bank_slot_q[response_fifo[6][BANK_W-1:0]]==6 && f_route_words[6]==f_parent_bank_word_q[response_fifo[6][BANK_W-1:0]]);
        end
        if(6'(5'(5'(7)-response_read_q))<response_count_q && !response_fifo[7][BANK_W]) begin
            assert(f_parent_bank_pending_q[response_fifo[7][BANK_W-1:0]]);
            assert(f_parent_bank_slot_q[response_fifo[7][BANK_W-1:0]]==7 && f_route_words[7]==f_parent_bank_word_q[response_fifo[7][BANK_W-1:0]]);
        end
        if(6'(5'(5'(8)-response_read_q))<response_count_q && !response_fifo[8][BANK_W]) begin
            assert(f_parent_bank_pending_q[response_fifo[8][BANK_W-1:0]]);
            assert(f_parent_bank_slot_q[response_fifo[8][BANK_W-1:0]]==8 && f_route_words[8]==f_parent_bank_word_q[response_fifo[8][BANK_W-1:0]]);
        end
        if(6'(5'(5'(9)-response_read_q))<response_count_q && !response_fifo[9][BANK_W]) begin
            assert(f_parent_bank_pending_q[response_fifo[9][BANK_W-1:0]]);
            assert(f_parent_bank_slot_q[response_fifo[9][BANK_W-1:0]]==9 && f_route_words[9]==f_parent_bank_word_q[response_fifo[9][BANK_W-1:0]]);
        end
        if(6'(5'(5'(10)-response_read_q))<response_count_q && !response_fifo[10][BANK_W]) begin
            assert(f_parent_bank_pending_q[response_fifo[10][BANK_W-1:0]]);
            assert(f_parent_bank_slot_q[response_fifo[10][BANK_W-1:0]]==10 && f_route_words[10]==f_parent_bank_word_q[response_fifo[10][BANK_W-1:0]]);
        end
        if(6'(5'(5'(11)-response_read_q))<response_count_q && !response_fifo[11][BANK_W]) begin
            assert(f_parent_bank_pending_q[response_fifo[11][BANK_W-1:0]]);
            assert(f_parent_bank_slot_q[response_fifo[11][BANK_W-1:0]]==11 && f_route_words[11]==f_parent_bank_word_q[response_fifo[11][BANK_W-1:0]]);
        end
        if(6'(5'(5'(12)-response_read_q))<response_count_q && !response_fifo[12][BANK_W]) begin
            assert(f_parent_bank_pending_q[response_fifo[12][BANK_W-1:0]]);
            assert(f_parent_bank_slot_q[response_fifo[12][BANK_W-1:0]]==12 && f_route_words[12]==f_parent_bank_word_q[response_fifo[12][BANK_W-1:0]]);
        end
        if(6'(5'(5'(13)-response_read_q))<response_count_q && !response_fifo[13][BANK_W]) begin
            assert(f_parent_bank_pending_q[response_fifo[13][BANK_W-1:0]]);
            assert(f_parent_bank_slot_q[response_fifo[13][BANK_W-1:0]]==13 && f_route_words[13]==f_parent_bank_word_q[response_fifo[13][BANK_W-1:0]]);
        end
        if(6'(5'(5'(14)-response_read_q))<response_count_q && !response_fifo[14][BANK_W]) begin
            assert(f_parent_bank_pending_q[response_fifo[14][BANK_W-1:0]]);
            assert(f_parent_bank_slot_q[response_fifo[14][BANK_W-1:0]]==14 && f_route_words[14]==f_parent_bank_word_q[response_fifo[14][BANK_W-1:0]]);
        end
        if(6'(5'(5'(15)-response_read_q))<response_count_q && !response_fifo[15][BANK_W]) begin
            assert(f_parent_bank_pending_q[response_fifo[15][BANK_W-1:0]]);
            assert(f_parent_bank_slot_q[response_fifo[15][BANK_W-1:0]]==15 && f_route_words[15]==f_parent_bank_word_q[response_fifo[15][BANK_W-1:0]]);
        end
        if(6'(5'(5'(16)-response_read_q))<response_count_q && !response_fifo[16][BANK_W]) begin
            assert(f_parent_bank_pending_q[response_fifo[16][BANK_W-1:0]]);
            assert(f_parent_bank_slot_q[response_fifo[16][BANK_W-1:0]]==16 && f_route_words[16]==f_parent_bank_word_q[response_fifo[16][BANK_W-1:0]]);
        end
        if(6'(5'(5'(17)-response_read_q))<response_count_q && !response_fifo[17][BANK_W]) begin
            assert(f_parent_bank_pending_q[response_fifo[17][BANK_W-1:0]]);
            assert(f_parent_bank_slot_q[response_fifo[17][BANK_W-1:0]]==17 && f_route_words[17]==f_parent_bank_word_q[response_fifo[17][BANK_W-1:0]]);
        end
        if(6'(5'(5'(18)-response_read_q))<response_count_q && !response_fifo[18][BANK_W]) begin
            assert(f_parent_bank_pending_q[response_fifo[18][BANK_W-1:0]]);
            assert(f_parent_bank_slot_q[response_fifo[18][BANK_W-1:0]]==18 && f_route_words[18]==f_parent_bank_word_q[response_fifo[18][BANK_W-1:0]]);
        end
        if(6'(5'(5'(19)-response_read_q))<response_count_q && !response_fifo[19][BANK_W]) begin
            assert(f_parent_bank_pending_q[response_fifo[19][BANK_W-1:0]]);
            assert(f_parent_bank_slot_q[response_fifo[19][BANK_W-1:0]]==19 && f_route_words[19]==f_parent_bank_word_q[response_fifo[19][BANK_W-1:0]]);
        end
        if(6'(5'(5'(20)-response_read_q))<response_count_q && !response_fifo[20][BANK_W]) begin
            assert(f_parent_bank_pending_q[response_fifo[20][BANK_W-1:0]]);
            assert(f_parent_bank_slot_q[response_fifo[20][BANK_W-1:0]]==20 && f_route_words[20]==f_parent_bank_word_q[response_fifo[20][BANK_W-1:0]]);
        end
        if(6'(5'(5'(21)-response_read_q))<response_count_q && !response_fifo[21][BANK_W]) begin
            assert(f_parent_bank_pending_q[response_fifo[21][BANK_W-1:0]]);
            assert(f_parent_bank_slot_q[response_fifo[21][BANK_W-1:0]]==21 && f_route_words[21]==f_parent_bank_word_q[response_fifo[21][BANK_W-1:0]]);
        end
        if(6'(5'(5'(22)-response_read_q))<response_count_q && !response_fifo[22][BANK_W]) begin
            assert(f_parent_bank_pending_q[response_fifo[22][BANK_W-1:0]]);
            assert(f_parent_bank_slot_q[response_fifo[22][BANK_W-1:0]]==22 && f_route_words[22]==f_parent_bank_word_q[response_fifo[22][BANK_W-1:0]]);
        end
        if(6'(5'(5'(23)-response_read_q))<response_count_q && !response_fifo[23][BANK_W]) begin
            assert(f_parent_bank_pending_q[response_fifo[23][BANK_W-1:0]]);
            assert(f_parent_bank_slot_q[response_fifo[23][BANK_W-1:0]]==23 && f_route_words[23]==f_parent_bank_word_q[response_fifo[23][BANK_W-1:0]]);
        end
        if(6'(5'(5'(24)-response_read_q))<response_count_q && !response_fifo[24][BANK_W]) begin
            assert(f_parent_bank_pending_q[response_fifo[24][BANK_W-1:0]]);
            assert(f_parent_bank_slot_q[response_fifo[24][BANK_W-1:0]]==24 && f_route_words[24]==f_parent_bank_word_q[response_fifo[24][BANK_W-1:0]]);
        end
        if(6'(5'(5'(25)-response_read_q))<response_count_q && !response_fifo[25][BANK_W]) begin
            assert(f_parent_bank_pending_q[response_fifo[25][BANK_W-1:0]]);
            assert(f_parent_bank_slot_q[response_fifo[25][BANK_W-1:0]]==25 && f_route_words[25]==f_parent_bank_word_q[response_fifo[25][BANK_W-1:0]]);
        end
        if(6'(5'(5'(26)-response_read_q))<response_count_q && !response_fifo[26][BANK_W]) begin
            assert(f_parent_bank_pending_q[response_fifo[26][BANK_W-1:0]]);
            assert(f_parent_bank_slot_q[response_fifo[26][BANK_W-1:0]]==26 && f_route_words[26]==f_parent_bank_word_q[response_fifo[26][BANK_W-1:0]]);
        end
        if(6'(5'(5'(27)-response_read_q))<response_count_q && !response_fifo[27][BANK_W]) begin
            assert(f_parent_bank_pending_q[response_fifo[27][BANK_W-1:0]]);
            assert(f_parent_bank_slot_q[response_fifo[27][BANK_W-1:0]]==27 && f_route_words[27]==f_parent_bank_word_q[response_fifo[27][BANK_W-1:0]]);
        end
        if(6'(5'(5'(28)-response_read_q))<response_count_q && !response_fifo[28][BANK_W]) begin
            assert(f_parent_bank_pending_q[response_fifo[28][BANK_W-1:0]]);
            assert(f_parent_bank_slot_q[response_fifo[28][BANK_W-1:0]]==28 && f_route_words[28]==f_parent_bank_word_q[response_fifo[28][BANK_W-1:0]]);
        end
        if(6'(5'(5'(29)-response_read_q))<response_count_q && !response_fifo[29][BANK_W]) begin
            assert(f_parent_bank_pending_q[response_fifo[29][BANK_W-1:0]]);
            assert(f_parent_bank_slot_q[response_fifo[29][BANK_W-1:0]]==29 && f_route_words[29]==f_parent_bank_word_q[response_fifo[29][BANK_W-1:0]]);
        end
        if(6'(5'(5'(30)-response_read_q))<response_count_q && !response_fifo[30][BANK_W]) begin
            assert(f_parent_bank_pending_q[response_fifo[30][BANK_W-1:0]]);
            assert(f_parent_bank_slot_q[response_fifo[30][BANK_W-1:0]]==30 && f_route_words[30]==f_parent_bank_word_q[response_fifo[30][BANK_W-1:0]]);
        end
        if(6'(5'(5'(31)-response_read_q))<response_count_q && !response_fifo[31][BANK_W]) begin
            assert(f_parent_bank_pending_q[response_fifo[31][BANK_W-1:0]]);
            assert(f_parent_bank_slot_q[response_fifo[31][BANK_W-1:0]]==31 && f_route_words[31]==f_parent_bank_word_q[response_fifo[31][BANK_W-1:0]]);
        end
        if(response_valid_o && !response_source[BANK_W]) begin
            assert(f_parent_bank_pending_q[response_bank]);
            assert(f_route_words[response_read_q]==f_parent_bank_word_q[response_bank]);
            assert(response_data_o==bank_response_data[response_bank]);
        end
        cover(response_valid_o && !response_source[BANK_W]);
    end
