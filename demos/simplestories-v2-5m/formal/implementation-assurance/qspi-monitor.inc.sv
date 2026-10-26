    // Independent observation of the actual SPI pin edges and header bits.
    logic f_sck_previous_q;
    logic [5:0] f_header_edges_q;
    logic f_history_valid_q;
    always_ff @(posedge clk_i or negedge reset_n_i) begin
        if (!reset_n_i) begin
            f_sck_previous_q <= 0;
            f_header_edges_q <= 0;
            f_history_valid_q <= 0;
        end else begin
            f_sck_previous_q <= qspi_sck_o;
            f_history_valid_q <= 1;
            if (qspi_cs_n_o) f_header_edges_q <= 0;
            else if (qspi_sck_o && !f_sck_previous_q && qspi_dq_oe_o[0])
                f_header_edges_q <= f_header_edges_q + 1'b1;
        end
    end
    wire f_header_rise = !qspi_cs_n_o && qspi_sck_o &&
        !f_sck_previous_q && qspi_dq_oe_o[0];
    wire [31:0] f_expected_header = 32'h03801000;
    wire [31:0] f_expected_shift = f_expected_header << (6'd32-send_bits_left_q);
    always_ff @(posedge clk_i) if (reset_n_i) begin
        assert(state_q == ST_IDLE || state_q == ST_SEND || state_q == ST_DATA ||
            state_q == ST_TURN || state_q == ST_FAULT); // S01
        assert(f_header_edges_q <= 32); // S02
        if (state_q == ST_SEND) begin
            assert(send_bits_left_q >= 1 && send_bits_left_q <= 32); // S03
            assert(!qspi_cs_n_o && busy_o && qspi_dq_oe_o == 4'b1101); // S04
            assert(transmit_shift_q == f_expected_shift[30:0]); // S05: shift support
            assert(qspi_dq_o[0] == ((f_expected_header >> (send_bits_left_q-1)) & 1)); // S06
            assert(send_bits_left_q == 6'd32-f_header_edges_q+
                (phase_high_q ? 6'd1 : 6'd0)-(f_header_rise ? 6'd1 : 6'd0)); // S07
            assert(qspi_sck_o == phase_high_q); // S08
            assert(bytes_remaining_q == 24'd7265984); // S24: header preserves full read length
        end
        if (f_header_rise) begin
            assert(f_header_edges_q < 32); // S09
            assert(qspi_dq_o[0] == ((f_expected_header >> (31-f_header_edges_q)) & 1)); // S10: fixed opcode + address on pins
        end
        if (state_q == ST_DATA || state_q == ST_TURN) begin
            assert(f_header_edges_q == 32); // S11: complete header before data
            assert(!qspi_cs_n_o && qspi_dq_oe_o == 4'b1100); // S12: MOSI released
            assert(bytes_remaining_q >= 1 && bytes_remaining_q <= 24'd7265984); // S13
        end
        if (!qspi_cs_n_o) begin
            assert(qspi_dq_o[3:2] == 2'b11 && qspi_dq_oe_o[3:2] == 2'b11); // S14
            assert(!qspi_dq_oe_o[1]); // S15: no MISO drive
        end
        if (fault_o) assert(qspi_cs_n_o && !busy_o && qspi_dq_oe_o == 0); // S16
        assert(fault_o == (state_q == ST_FAULT)); // S21: reachable fault-state relation
        if (state_q == ST_TURN)
            assert(data_last_o == (bytes_remaining_q == 1)); // S22: accepted byte ownership
        if (state_q == ST_IDLE)
            assert(qspi_cs_n_o && !busy_o && qspi_dq_oe_o == 0); // S23: transaction boundary
        if (data_valid_o) assert(state_q == ST_DATA && data_last_o == (bytes_remaining_q == 1)); // S17
        if (f_history_valid_q && $past(reset_n_i)) begin
            if ($past(fault_o)) assert(fault_o); // S18
            if ($past(start_i && state_q != ST_IDLE)) assert(fault_o); // S19
            if ($past(data_valid_o && !data_ready_i) && !$past(start_i))
                assert(data_valid_o && data_o == $past(data_o) && data_last_o == $past(data_last_o)); // S20
        end
    end
    always_ff @(posedge clk_i) if (reset_n_i) begin
        cover(state_q == ST_DATA && f_header_edges_q == 32);
        cover(data_valid_o && data_ready_i && f_header_edges_q == 32);
    end
