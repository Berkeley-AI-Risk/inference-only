    // A reference transaction descriptor retains the requested word; native
    // response FIFO retains only its bank/metadata selector. No feedback.
    logic [17:0] f_route_words [0:31];
    always_ff @(posedge clk) if(read_fire) f_route_words[response_write_q]<=head_word;
    always_ff @(posedge clk) if(reset_n && !fault_o) begin
        assert(request_count_q<=64);
        assert(response_count_q<=32);
        assert(request_write_q==request_read_q+request_count_q[5:0]);
        assert(response_write_q==response_read_q+response_count_q[4:0]);
        if(head_valid_q) begin
            assert(request_count_q!=0);
            assert(head_word==request_fifo[request_read_q]);
            assert(head_word<IMAGE_WORDS);
        end
        if(read_fire) assert(enabled && !cancel_i && head_valid_q && request_count_q!=0 && response_count_q<32);
        if(metadata_read) assert(metadata_head && metadata_ready && bank_read_valid==0);
        if(|bank_read_valid) begin
            assert(!metadata_head && head_valid_q && enabled && !cancel_i && response_count_q<32);
            assert(bank_read_valid==(BANKS'(1)<<head_bank));
            assert(bank_verified[head_bank] && bank_page[head_bank]==head_page);
        end
        if(response_valid_o) begin
            assert(enabled && !cancel_i && response_count_q!=0);
            assert(response_data_o==(response_source[BANK_W] ? metadata_data : bank_response_data[response_bank]));
            assert(response_source[BANK_W] ? metadata_valid : bank_response_valid[response_bank]);
        end else assert(response_data_o==0);
        if(cancel_i || !enabled) assert(!request_ready_o && !response_valid_o && bank_read_valid==0 && bank_response_ready==0);
        if(|bank_response_ready) begin
            assert(response_count_q!=0 && !response_source[BANK_W] && response_ready_i);
            assert(bank_response_ready==(BANKS'(1)<<response_bank));
        end
        if(metadata_response_ready) assert(response_count_q!=0 && response_source[BANK_W] && response_ready_i);
        if(7'(6'(6'(0)-request_read_q))<request_count_q) assert(request_fifo[0]<IMAGE_WORDS);
        if(7'(6'(6'(1)-request_read_q))<request_count_q) assert(request_fifo[1]<IMAGE_WORDS);
        if(7'(6'(6'(2)-request_read_q))<request_count_q) assert(request_fifo[2]<IMAGE_WORDS);
        if(7'(6'(6'(3)-request_read_q))<request_count_q) assert(request_fifo[3]<IMAGE_WORDS);
        if(7'(6'(6'(4)-request_read_q))<request_count_q) assert(request_fifo[4]<IMAGE_WORDS);
        if(7'(6'(6'(5)-request_read_q))<request_count_q) assert(request_fifo[5]<IMAGE_WORDS);
        if(7'(6'(6'(6)-request_read_q))<request_count_q) assert(request_fifo[6]<IMAGE_WORDS);
        if(7'(6'(6'(7)-request_read_q))<request_count_q) assert(request_fifo[7]<IMAGE_WORDS);
        if(7'(6'(6'(8)-request_read_q))<request_count_q) assert(request_fifo[8]<IMAGE_WORDS);
        if(7'(6'(6'(9)-request_read_q))<request_count_q) assert(request_fifo[9]<IMAGE_WORDS);
        if(7'(6'(6'(10)-request_read_q))<request_count_q) assert(request_fifo[10]<IMAGE_WORDS);
        if(7'(6'(6'(11)-request_read_q))<request_count_q) assert(request_fifo[11]<IMAGE_WORDS);
        if(7'(6'(6'(12)-request_read_q))<request_count_q) assert(request_fifo[12]<IMAGE_WORDS);
        if(7'(6'(6'(13)-request_read_q))<request_count_q) assert(request_fifo[13]<IMAGE_WORDS);
        if(7'(6'(6'(14)-request_read_q))<request_count_q) assert(request_fifo[14]<IMAGE_WORDS);
        if(7'(6'(6'(15)-request_read_q))<request_count_q) assert(request_fifo[15]<IMAGE_WORDS);
        if(7'(6'(6'(16)-request_read_q))<request_count_q) assert(request_fifo[16]<IMAGE_WORDS);
        if(7'(6'(6'(17)-request_read_q))<request_count_q) assert(request_fifo[17]<IMAGE_WORDS);
        if(7'(6'(6'(18)-request_read_q))<request_count_q) assert(request_fifo[18]<IMAGE_WORDS);
        if(7'(6'(6'(19)-request_read_q))<request_count_q) assert(request_fifo[19]<IMAGE_WORDS);
        if(7'(6'(6'(20)-request_read_q))<request_count_q) assert(request_fifo[20]<IMAGE_WORDS);
        if(7'(6'(6'(21)-request_read_q))<request_count_q) assert(request_fifo[21]<IMAGE_WORDS);
        if(7'(6'(6'(22)-request_read_q))<request_count_q) assert(request_fifo[22]<IMAGE_WORDS);
        if(7'(6'(6'(23)-request_read_q))<request_count_q) assert(request_fifo[23]<IMAGE_WORDS);
        if(7'(6'(6'(24)-request_read_q))<request_count_q) assert(request_fifo[24]<IMAGE_WORDS);
        if(7'(6'(6'(25)-request_read_q))<request_count_q) assert(request_fifo[25]<IMAGE_WORDS);
        if(7'(6'(6'(26)-request_read_q))<request_count_q) assert(request_fifo[26]<IMAGE_WORDS);
        if(7'(6'(6'(27)-request_read_q))<request_count_q) assert(request_fifo[27]<IMAGE_WORDS);
        if(7'(6'(6'(28)-request_read_q))<request_count_q) assert(request_fifo[28]<IMAGE_WORDS);
        if(7'(6'(6'(29)-request_read_q))<request_count_q) assert(request_fifo[29]<IMAGE_WORDS);
        if(7'(6'(6'(30)-request_read_q))<request_count_q) assert(request_fifo[30]<IMAGE_WORDS);
        if(7'(6'(6'(31)-request_read_q))<request_count_q) assert(request_fifo[31]<IMAGE_WORDS);
        if(7'(6'(6'(32)-request_read_q))<request_count_q) assert(request_fifo[32]<IMAGE_WORDS);
        if(7'(6'(6'(33)-request_read_q))<request_count_q) assert(request_fifo[33]<IMAGE_WORDS);
        if(7'(6'(6'(34)-request_read_q))<request_count_q) assert(request_fifo[34]<IMAGE_WORDS);
        if(7'(6'(6'(35)-request_read_q))<request_count_q) assert(request_fifo[35]<IMAGE_WORDS);
        if(7'(6'(6'(36)-request_read_q))<request_count_q) assert(request_fifo[36]<IMAGE_WORDS);
        if(7'(6'(6'(37)-request_read_q))<request_count_q) assert(request_fifo[37]<IMAGE_WORDS);
        if(7'(6'(6'(38)-request_read_q))<request_count_q) assert(request_fifo[38]<IMAGE_WORDS);
        if(7'(6'(6'(39)-request_read_q))<request_count_q) assert(request_fifo[39]<IMAGE_WORDS);
        if(7'(6'(6'(40)-request_read_q))<request_count_q) assert(request_fifo[40]<IMAGE_WORDS);
        if(7'(6'(6'(41)-request_read_q))<request_count_q) assert(request_fifo[41]<IMAGE_WORDS);
        if(7'(6'(6'(42)-request_read_q))<request_count_q) assert(request_fifo[42]<IMAGE_WORDS);
        if(7'(6'(6'(43)-request_read_q))<request_count_q) assert(request_fifo[43]<IMAGE_WORDS);
        if(7'(6'(6'(44)-request_read_q))<request_count_q) assert(request_fifo[44]<IMAGE_WORDS);
        if(7'(6'(6'(45)-request_read_q))<request_count_q) assert(request_fifo[45]<IMAGE_WORDS);
        if(7'(6'(6'(46)-request_read_q))<request_count_q) assert(request_fifo[46]<IMAGE_WORDS);
        if(7'(6'(6'(47)-request_read_q))<request_count_q) assert(request_fifo[47]<IMAGE_WORDS);
        if(7'(6'(6'(48)-request_read_q))<request_count_q) assert(request_fifo[48]<IMAGE_WORDS);
        if(7'(6'(6'(49)-request_read_q))<request_count_q) assert(request_fifo[49]<IMAGE_WORDS);
        if(7'(6'(6'(50)-request_read_q))<request_count_q) assert(request_fifo[50]<IMAGE_WORDS);
        if(7'(6'(6'(51)-request_read_q))<request_count_q) assert(request_fifo[51]<IMAGE_WORDS);
        if(7'(6'(6'(52)-request_read_q))<request_count_q) assert(request_fifo[52]<IMAGE_WORDS);
        if(7'(6'(6'(53)-request_read_q))<request_count_q) assert(request_fifo[53]<IMAGE_WORDS);
        if(7'(6'(6'(54)-request_read_q))<request_count_q) assert(request_fifo[54]<IMAGE_WORDS);
        if(7'(6'(6'(55)-request_read_q))<request_count_q) assert(request_fifo[55]<IMAGE_WORDS);
        if(7'(6'(6'(56)-request_read_q))<request_count_q) assert(request_fifo[56]<IMAGE_WORDS);
        if(7'(6'(6'(57)-request_read_q))<request_count_q) assert(request_fifo[57]<IMAGE_WORDS);
        if(7'(6'(6'(58)-request_read_q))<request_count_q) assert(request_fifo[58]<IMAGE_WORDS);
        if(7'(6'(6'(59)-request_read_q))<request_count_q) assert(request_fifo[59]<IMAGE_WORDS);
        if(7'(6'(6'(60)-request_read_q))<request_count_q) assert(request_fifo[60]<IMAGE_WORDS);
        if(7'(6'(6'(61)-request_read_q))<request_count_q) assert(request_fifo[61]<IMAGE_WORDS);
        if(7'(6'(6'(62)-request_read_q))<request_count_q) assert(request_fifo[62]<IMAGE_WORDS);
        if(7'(6'(6'(63)-request_read_q))<request_count_q) assert(request_fifo[63]<IMAGE_WORDS);
        if(6'(5'(5'(0)-response_read_q))<response_count_q) begin
            assert(f_route_words[0]<IMAGE_WORDS);
            assert(response_fifo[0][BANK_W]==(f_route_words[0]>=211920 && f_route_words[0]<214248));
            assert(response_fifo[0][BANK_W-1:0]==f_route_words[0][7 +: BANK_W]);
        end
        if(6'(5'(5'(1)-response_read_q))<response_count_q) begin
            assert(f_route_words[1]<IMAGE_WORDS);
            assert(response_fifo[1][BANK_W]==(f_route_words[1]>=211920 && f_route_words[1]<214248));
            assert(response_fifo[1][BANK_W-1:0]==f_route_words[1][7 +: BANK_W]);
        end
        if(6'(5'(5'(2)-response_read_q))<response_count_q) begin
            assert(f_route_words[2]<IMAGE_WORDS);
            assert(response_fifo[2][BANK_W]==(f_route_words[2]>=211920 && f_route_words[2]<214248));
            assert(response_fifo[2][BANK_W-1:0]==f_route_words[2][7 +: BANK_W]);
        end
        if(6'(5'(5'(3)-response_read_q))<response_count_q) begin
            assert(f_route_words[3]<IMAGE_WORDS);
            assert(response_fifo[3][BANK_W]==(f_route_words[3]>=211920 && f_route_words[3]<214248));
            assert(response_fifo[3][BANK_W-1:0]==f_route_words[3][7 +: BANK_W]);
        end
        if(6'(5'(5'(4)-response_read_q))<response_count_q) begin
            assert(f_route_words[4]<IMAGE_WORDS);
            assert(response_fifo[4][BANK_W]==(f_route_words[4]>=211920 && f_route_words[4]<214248));
            assert(response_fifo[4][BANK_W-1:0]==f_route_words[4][7 +: BANK_W]);
        end
        if(6'(5'(5'(5)-response_read_q))<response_count_q) begin
            assert(f_route_words[5]<IMAGE_WORDS);
            assert(response_fifo[5][BANK_W]==(f_route_words[5]>=211920 && f_route_words[5]<214248));
            assert(response_fifo[5][BANK_W-1:0]==f_route_words[5][7 +: BANK_W]);
        end
        if(6'(5'(5'(6)-response_read_q))<response_count_q) begin
            assert(f_route_words[6]<IMAGE_WORDS);
            assert(response_fifo[6][BANK_W]==(f_route_words[6]>=211920 && f_route_words[6]<214248));
            assert(response_fifo[6][BANK_W-1:0]==f_route_words[6][7 +: BANK_W]);
        end
        if(6'(5'(5'(7)-response_read_q))<response_count_q) begin
            assert(f_route_words[7]<IMAGE_WORDS);
            assert(response_fifo[7][BANK_W]==(f_route_words[7]>=211920 && f_route_words[7]<214248));
            assert(response_fifo[7][BANK_W-1:0]==f_route_words[7][7 +: BANK_W]);
        end
        if(6'(5'(5'(8)-response_read_q))<response_count_q) begin
            assert(f_route_words[8]<IMAGE_WORDS);
            assert(response_fifo[8][BANK_W]==(f_route_words[8]>=211920 && f_route_words[8]<214248));
            assert(response_fifo[8][BANK_W-1:0]==f_route_words[8][7 +: BANK_W]);
        end
        if(6'(5'(5'(9)-response_read_q))<response_count_q) begin
            assert(f_route_words[9]<IMAGE_WORDS);
            assert(response_fifo[9][BANK_W]==(f_route_words[9]>=211920 && f_route_words[9]<214248));
            assert(response_fifo[9][BANK_W-1:0]==f_route_words[9][7 +: BANK_W]);
        end
        if(6'(5'(5'(10)-response_read_q))<response_count_q) begin
            assert(f_route_words[10]<IMAGE_WORDS);
            assert(response_fifo[10][BANK_W]==(f_route_words[10]>=211920 && f_route_words[10]<214248));
            assert(response_fifo[10][BANK_W-1:0]==f_route_words[10][7 +: BANK_W]);
        end
        if(6'(5'(5'(11)-response_read_q))<response_count_q) begin
            assert(f_route_words[11]<IMAGE_WORDS);
            assert(response_fifo[11][BANK_W]==(f_route_words[11]>=211920 && f_route_words[11]<214248));
            assert(response_fifo[11][BANK_W-1:0]==f_route_words[11][7 +: BANK_W]);
        end
        if(6'(5'(5'(12)-response_read_q))<response_count_q) begin
            assert(f_route_words[12]<IMAGE_WORDS);
            assert(response_fifo[12][BANK_W]==(f_route_words[12]>=211920 && f_route_words[12]<214248));
            assert(response_fifo[12][BANK_W-1:0]==f_route_words[12][7 +: BANK_W]);
        end
        if(6'(5'(5'(13)-response_read_q))<response_count_q) begin
            assert(f_route_words[13]<IMAGE_WORDS);
            assert(response_fifo[13][BANK_W]==(f_route_words[13]>=211920 && f_route_words[13]<214248));
            assert(response_fifo[13][BANK_W-1:0]==f_route_words[13][7 +: BANK_W]);
        end
        if(6'(5'(5'(14)-response_read_q))<response_count_q) begin
            assert(f_route_words[14]<IMAGE_WORDS);
            assert(response_fifo[14][BANK_W]==(f_route_words[14]>=211920 && f_route_words[14]<214248));
            assert(response_fifo[14][BANK_W-1:0]==f_route_words[14][7 +: BANK_W]);
        end
        if(6'(5'(5'(15)-response_read_q))<response_count_q) begin
            assert(f_route_words[15]<IMAGE_WORDS);
            assert(response_fifo[15][BANK_W]==(f_route_words[15]>=211920 && f_route_words[15]<214248));
            assert(response_fifo[15][BANK_W-1:0]==f_route_words[15][7 +: BANK_W]);
        end
        if(6'(5'(5'(16)-response_read_q))<response_count_q) begin
            assert(f_route_words[16]<IMAGE_WORDS);
            assert(response_fifo[16][BANK_W]==(f_route_words[16]>=211920 && f_route_words[16]<214248));
            assert(response_fifo[16][BANK_W-1:0]==f_route_words[16][7 +: BANK_W]);
        end
        if(6'(5'(5'(17)-response_read_q))<response_count_q) begin
            assert(f_route_words[17]<IMAGE_WORDS);
            assert(response_fifo[17][BANK_W]==(f_route_words[17]>=211920 && f_route_words[17]<214248));
            assert(response_fifo[17][BANK_W-1:0]==f_route_words[17][7 +: BANK_W]);
        end
        if(6'(5'(5'(18)-response_read_q))<response_count_q) begin
            assert(f_route_words[18]<IMAGE_WORDS);
            assert(response_fifo[18][BANK_W]==(f_route_words[18]>=211920 && f_route_words[18]<214248));
            assert(response_fifo[18][BANK_W-1:0]==f_route_words[18][7 +: BANK_W]);
        end
        if(6'(5'(5'(19)-response_read_q))<response_count_q) begin
            assert(f_route_words[19]<IMAGE_WORDS);
            assert(response_fifo[19][BANK_W]==(f_route_words[19]>=211920 && f_route_words[19]<214248));
            assert(response_fifo[19][BANK_W-1:0]==f_route_words[19][7 +: BANK_W]);
        end
        if(6'(5'(5'(20)-response_read_q))<response_count_q) begin
            assert(f_route_words[20]<IMAGE_WORDS);
            assert(response_fifo[20][BANK_W]==(f_route_words[20]>=211920 && f_route_words[20]<214248));
            assert(response_fifo[20][BANK_W-1:0]==f_route_words[20][7 +: BANK_W]);
        end
        if(6'(5'(5'(21)-response_read_q))<response_count_q) begin
            assert(f_route_words[21]<IMAGE_WORDS);
            assert(response_fifo[21][BANK_W]==(f_route_words[21]>=211920 && f_route_words[21]<214248));
            assert(response_fifo[21][BANK_W-1:0]==f_route_words[21][7 +: BANK_W]);
        end
        if(6'(5'(5'(22)-response_read_q))<response_count_q) begin
            assert(f_route_words[22]<IMAGE_WORDS);
            assert(response_fifo[22][BANK_W]==(f_route_words[22]>=211920 && f_route_words[22]<214248));
            assert(response_fifo[22][BANK_W-1:0]==f_route_words[22][7 +: BANK_W]);
        end
        if(6'(5'(5'(23)-response_read_q))<response_count_q) begin
            assert(f_route_words[23]<IMAGE_WORDS);
            assert(response_fifo[23][BANK_W]==(f_route_words[23]>=211920 && f_route_words[23]<214248));
            assert(response_fifo[23][BANK_W-1:0]==f_route_words[23][7 +: BANK_W]);
        end
        if(6'(5'(5'(24)-response_read_q))<response_count_q) begin
            assert(f_route_words[24]<IMAGE_WORDS);
            assert(response_fifo[24][BANK_W]==(f_route_words[24]>=211920 && f_route_words[24]<214248));
            assert(response_fifo[24][BANK_W-1:0]==f_route_words[24][7 +: BANK_W]);
        end
        if(6'(5'(5'(25)-response_read_q))<response_count_q) begin
            assert(f_route_words[25]<IMAGE_WORDS);
            assert(response_fifo[25][BANK_W]==(f_route_words[25]>=211920 && f_route_words[25]<214248));
            assert(response_fifo[25][BANK_W-1:0]==f_route_words[25][7 +: BANK_W]);
        end
        if(6'(5'(5'(26)-response_read_q))<response_count_q) begin
            assert(f_route_words[26]<IMAGE_WORDS);
            assert(response_fifo[26][BANK_W]==(f_route_words[26]>=211920 && f_route_words[26]<214248));
            assert(response_fifo[26][BANK_W-1:0]==f_route_words[26][7 +: BANK_W]);
        end
        if(6'(5'(5'(27)-response_read_q))<response_count_q) begin
            assert(f_route_words[27]<IMAGE_WORDS);
            assert(response_fifo[27][BANK_W]==(f_route_words[27]>=211920 && f_route_words[27]<214248));
            assert(response_fifo[27][BANK_W-1:0]==f_route_words[27][7 +: BANK_W]);
        end
        if(6'(5'(5'(28)-response_read_q))<response_count_q) begin
            assert(f_route_words[28]<IMAGE_WORDS);
            assert(response_fifo[28][BANK_W]==(f_route_words[28]>=211920 && f_route_words[28]<214248));
            assert(response_fifo[28][BANK_W-1:0]==f_route_words[28][7 +: BANK_W]);
        end
        if(6'(5'(5'(29)-response_read_q))<response_count_q) begin
            assert(f_route_words[29]<IMAGE_WORDS);
            assert(response_fifo[29][BANK_W]==(f_route_words[29]>=211920 && f_route_words[29]<214248));
            assert(response_fifo[29][BANK_W-1:0]==f_route_words[29][7 +: BANK_W]);
        end
        if(6'(5'(5'(30)-response_read_q))<response_count_q) begin
            assert(f_route_words[30]<IMAGE_WORDS);
            assert(response_fifo[30][BANK_W]==(f_route_words[30]>=211920 && f_route_words[30]<214248));
            assert(response_fifo[30][BANK_W-1:0]==f_route_words[30][7 +: BANK_W]);
        end
        if(6'(5'(5'(31)-response_read_q))<response_count_q) begin
            assert(f_route_words[31]<IMAGE_WORDS);
            assert(response_fifo[31][BANK_W]==(f_route_words[31]>=211920 && f_route_words[31]<214248));
            assert(response_fifo[31][BANK_W-1:0]==f_route_words[31][7 +: BANK_W]);
        end
        cover(response_valid_o && response_source[BANK_W]);
    end
