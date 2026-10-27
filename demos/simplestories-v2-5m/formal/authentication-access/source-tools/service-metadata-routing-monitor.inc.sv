    logic [4:0] f_route_metadata_slot_q;
    logic [17:0] f_route_metadata_word_q;
    always_ff @(posedge clk) if(metadata_read) begin
        f_route_metadata_slot_q<=response_write_q;
        f_route_metadata_word_q<=head_word;
    end
    always_ff @(posedge clk) if(reset_n && !fault_o) begin
        if(metadata_valid) begin
            assert(response_count_q!=0);
            assert(6'(5'(f_route_metadata_slot_q-response_read_q))<response_count_q);
            assert(response_fifo[f_route_metadata_slot_q][BANK_W]);
            assert(f_route_words[f_route_metadata_slot_q]==f_route_metadata_word_q);
            assert(f_route_metadata_word_q>=211920 && f_route_metadata_word_q<214248);
        end
        if(6'(5'(5'(0)-response_read_q))<response_count_q && response_fifo[0][BANK_W])
            assert(metadata_valid && f_route_metadata_slot_q==0 && f_route_words[0]==f_route_metadata_word_q);
        if(6'(5'(5'(1)-response_read_q))<response_count_q && response_fifo[1][BANK_W])
            assert(metadata_valid && f_route_metadata_slot_q==1 && f_route_words[1]==f_route_metadata_word_q);
        if(6'(5'(5'(2)-response_read_q))<response_count_q && response_fifo[2][BANK_W])
            assert(metadata_valid && f_route_metadata_slot_q==2 && f_route_words[2]==f_route_metadata_word_q);
        if(6'(5'(5'(3)-response_read_q))<response_count_q && response_fifo[3][BANK_W])
            assert(metadata_valid && f_route_metadata_slot_q==3 && f_route_words[3]==f_route_metadata_word_q);
        if(6'(5'(5'(4)-response_read_q))<response_count_q && response_fifo[4][BANK_W])
            assert(metadata_valid && f_route_metadata_slot_q==4 && f_route_words[4]==f_route_metadata_word_q);
        if(6'(5'(5'(5)-response_read_q))<response_count_q && response_fifo[5][BANK_W])
            assert(metadata_valid && f_route_metadata_slot_q==5 && f_route_words[5]==f_route_metadata_word_q);
        if(6'(5'(5'(6)-response_read_q))<response_count_q && response_fifo[6][BANK_W])
            assert(metadata_valid && f_route_metadata_slot_q==6 && f_route_words[6]==f_route_metadata_word_q);
        if(6'(5'(5'(7)-response_read_q))<response_count_q && response_fifo[7][BANK_W])
            assert(metadata_valid && f_route_metadata_slot_q==7 && f_route_words[7]==f_route_metadata_word_q);
        if(6'(5'(5'(8)-response_read_q))<response_count_q && response_fifo[8][BANK_W])
            assert(metadata_valid && f_route_metadata_slot_q==8 && f_route_words[8]==f_route_metadata_word_q);
        if(6'(5'(5'(9)-response_read_q))<response_count_q && response_fifo[9][BANK_W])
            assert(metadata_valid && f_route_metadata_slot_q==9 && f_route_words[9]==f_route_metadata_word_q);
        if(6'(5'(5'(10)-response_read_q))<response_count_q && response_fifo[10][BANK_W])
            assert(metadata_valid && f_route_metadata_slot_q==10 && f_route_words[10]==f_route_metadata_word_q);
        if(6'(5'(5'(11)-response_read_q))<response_count_q && response_fifo[11][BANK_W])
            assert(metadata_valid && f_route_metadata_slot_q==11 && f_route_words[11]==f_route_metadata_word_q);
        if(6'(5'(5'(12)-response_read_q))<response_count_q && response_fifo[12][BANK_W])
            assert(metadata_valid && f_route_metadata_slot_q==12 && f_route_words[12]==f_route_metadata_word_q);
        if(6'(5'(5'(13)-response_read_q))<response_count_q && response_fifo[13][BANK_W])
            assert(metadata_valid && f_route_metadata_slot_q==13 && f_route_words[13]==f_route_metadata_word_q);
        if(6'(5'(5'(14)-response_read_q))<response_count_q && response_fifo[14][BANK_W])
            assert(metadata_valid && f_route_metadata_slot_q==14 && f_route_words[14]==f_route_metadata_word_q);
        if(6'(5'(5'(15)-response_read_q))<response_count_q && response_fifo[15][BANK_W])
            assert(metadata_valid && f_route_metadata_slot_q==15 && f_route_words[15]==f_route_metadata_word_q);
        if(6'(5'(5'(16)-response_read_q))<response_count_q && response_fifo[16][BANK_W])
            assert(metadata_valid && f_route_metadata_slot_q==16 && f_route_words[16]==f_route_metadata_word_q);
        if(6'(5'(5'(17)-response_read_q))<response_count_q && response_fifo[17][BANK_W])
            assert(metadata_valid && f_route_metadata_slot_q==17 && f_route_words[17]==f_route_metadata_word_q);
        if(6'(5'(5'(18)-response_read_q))<response_count_q && response_fifo[18][BANK_W])
            assert(metadata_valid && f_route_metadata_slot_q==18 && f_route_words[18]==f_route_metadata_word_q);
        if(6'(5'(5'(19)-response_read_q))<response_count_q && response_fifo[19][BANK_W])
            assert(metadata_valid && f_route_metadata_slot_q==19 && f_route_words[19]==f_route_metadata_word_q);
        if(6'(5'(5'(20)-response_read_q))<response_count_q && response_fifo[20][BANK_W])
            assert(metadata_valid && f_route_metadata_slot_q==20 && f_route_words[20]==f_route_metadata_word_q);
        if(6'(5'(5'(21)-response_read_q))<response_count_q && response_fifo[21][BANK_W])
            assert(metadata_valid && f_route_metadata_slot_q==21 && f_route_words[21]==f_route_metadata_word_q);
        if(6'(5'(5'(22)-response_read_q))<response_count_q && response_fifo[22][BANK_W])
            assert(metadata_valid && f_route_metadata_slot_q==22 && f_route_words[22]==f_route_metadata_word_q);
        if(6'(5'(5'(23)-response_read_q))<response_count_q && response_fifo[23][BANK_W])
            assert(metadata_valid && f_route_metadata_slot_q==23 && f_route_words[23]==f_route_metadata_word_q);
        if(6'(5'(5'(24)-response_read_q))<response_count_q && response_fifo[24][BANK_W])
            assert(metadata_valid && f_route_metadata_slot_q==24 && f_route_words[24]==f_route_metadata_word_q);
        if(6'(5'(5'(25)-response_read_q))<response_count_q && response_fifo[25][BANK_W])
            assert(metadata_valid && f_route_metadata_slot_q==25 && f_route_words[25]==f_route_metadata_word_q);
        if(6'(5'(5'(26)-response_read_q))<response_count_q && response_fifo[26][BANK_W])
            assert(metadata_valid && f_route_metadata_slot_q==26 && f_route_words[26]==f_route_metadata_word_q);
        if(6'(5'(5'(27)-response_read_q))<response_count_q && response_fifo[27][BANK_W])
            assert(metadata_valid && f_route_metadata_slot_q==27 && f_route_words[27]==f_route_metadata_word_q);
        if(6'(5'(5'(28)-response_read_q))<response_count_q && response_fifo[28][BANK_W])
            assert(metadata_valid && f_route_metadata_slot_q==28 && f_route_words[28]==f_route_metadata_word_q);
        if(6'(5'(5'(29)-response_read_q))<response_count_q && response_fifo[29][BANK_W])
            assert(metadata_valid && f_route_metadata_slot_q==29 && f_route_words[29]==f_route_metadata_word_q);
        if(6'(5'(5'(30)-response_read_q))<response_count_q && response_fifo[30][BANK_W])
            assert(metadata_valid && f_route_metadata_slot_q==30 && f_route_words[30]==f_route_metadata_word_q);
        if(6'(5'(5'(31)-response_read_q))<response_count_q && response_fifo[31][BANK_W])
            assert(metadata_valid && f_route_metadata_slot_q==31 && f_route_words[31]==f_route_metadata_word_q);
    end
