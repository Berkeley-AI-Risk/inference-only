    // Independent observational sequence counters. They never drive RTL.
    logic [PTR_W-1:0] f_wseq_q, f_rseq_q;
    (* anyconst *) logic [ADDR_BITS-1:0] f_slot;
    logic [WIDTH-1:0] f_last_payload_q;
    logic f_slot_written_q;
    always_ff @(posedge s_clk_i or negedge s_reset_n_i) begin
        if (!s_reset_n_i) begin
            f_wseq_q <= 0;
            f_slot_written_q <= 0;
        end else if (s_valid_i && s_ready_o) begin
            f_wseq_q <= f_wseq_q + 1'b1;
            if (f_wseq_q[ADDR_BITS-1:0] == f_slot) begin
                f_last_payload_q <= s_data_i;
                f_slot_written_q <= 1;
            end
        end
    end
    always_ff @(posedge m_clk_i or negedge m_reset_n_i) begin
        if (!m_reset_n_i) f_rseq_q <= 0;
        else if (m_valid_o && m_ready_i) f_rseq_q <= f_rseq_q + 1'b1;
    end

    function automatic [PTR_W-1:0] f_ungray(input [PTR_W-1:0] gray);
        integer bit_number;
        begin
            f_ungray[PTR_W-1] = gray[PTR_W-1];
            for (bit_number=PTR_W-2; bit_number>=0; bit_number=bit_number-1)
                f_ungray[bit_number] = f_ungray[bit_number+1] ^ gray[bit_number];
        end
    endfunction
    wire [PTR_W-1:0] f_order [0:5];
    assign f_order[0] = f_ungray(read_gray_sync2_q);
    assign f_order[1] = f_ungray(read_gray_sync1_q);
    assign f_order[2] = f_rseq_q;
    assign f_order[3] = f_ungray(write_gray_sync2_q);
    assign f_order[4] = f_ungray(write_gray_sync1_q);
    assign f_order[5] = f_wseq_q;
    // Modular distances use the actual extra wrap bit. Every ordered pair
    // stays within the literal capacity: no wrap/reuse or reduced geometry.
    genvar older, newer;
    generate
        for (older=0;older<6;older=older+1) begin: f_old
            for (newer=older+1;newer<6;newer=newer+1) begin: f_new
                wire [PTR_W-1:0] distance = f_order[newer] - f_order[older];
                always_comb assert(distance <= PTR_W'(DEPTH));
            end
        end
    endgenerate
    wire [PTR_W-1:0] f_conservative_used = f_wseq_q - f_order[0];
    wire [PTR_W-1:0] f_chain_step [0:4];
    generate
        for (older=0;older<5;older=older+1) begin: f_chain
            assign f_chain_step[older] = f_order[older+1] - f_order[older];
        end
    endgenerate
    // An extended sum rules out a circular ordering that can satisfy each
    // modular pair bound separately at the exact half-range distance.
    wire [PTR_W+2:0] f_chain_span =
        {3'b0,f_chain_step[0]} + {3'b0,f_chain_step[1]} +
        {3'b0,f_chain_step[2]} + {3'b0,f_chain_step[3]} +
        {3'b0,f_chain_step[4]};
    wire [PTR_W-1:0] f_used = f_wseq_q - f_rseq_q;
    wire [ADDR_BITS-1:0] f_slot_offset = f_slot - f_rseq_q[ADDR_BITS-1:0];
    wire f_slot_owned = {1'b0,f_slot_offset} < f_used;
    // These invariants also hold during staggered reset release. Keeping
    // them active there prevents unconstrained induction states from hiding
    // behind a stopped destination clock or a not-yet-released source.
    always_comb begin
        assert(write_binary_q == f_wseq_q); // F01 independent accepted-input count
        assert(read_binary_q == f_rseq_q); // F02 independent consumed-output count
        assert(write_gray_q == ((f_wseq_q >> 1) ^ f_wseq_q)); // F03
        assert(read_gray_q == ((f_rseq_q >> 1) ^ f_rseq_q)); // F04
        assert(f_chain_span <= (PTR_W+3)'(DEPTH)); // F10 coherent ordering, not a modular circle
        if (!write_full_q) assert(f_conservative_used < PTR_W'(DEPTH)); // F05
        if (m_valid_o) assert(f_order[3] != f_rseq_q); // F06 no invented output
        if (f_slot_written_q) assert(memory_q[f_slot] == f_last_payload_q); // F07
        if (f_slot_owned) assert(f_slot_written_q); // F11 occupied slot has input history
        if (m_valid_o && f_rseq_q[ADDR_BITS-1:0] == f_slot) begin
            assert(f_slot_written_q); // F08 output has an accepted source owner
            assert(m_data_o == f_last_payload_q); // F09 all payload bits preserved
        end
        cover(m_valid_o && m_ready_i && f_rseq_q[ADDR_BITS-1:0] == f_slot);
        cover(write_full_q && f_conservative_used == PTR_W'(DEPTH));
        cover(m_valid_o && !m_ready_i);
        cover(f_wseq_q[PTR_W-1] && f_rseq_q[PTR_W-1] && m_valid_o);
    end
