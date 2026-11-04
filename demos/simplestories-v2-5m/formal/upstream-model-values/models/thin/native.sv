`undef FORMAL
module board1_async_fifo_gray #(
    parameter integer WIDTH = 8,
    parameter integer ADDR_BITS = 4,
    /* verilator lint_off UNUSEDPARAM */
    parameter RAM_STYLE = "distributed",
    /* verilator lint_on UNUSEDPARAM */
    parameter integer DESTINATION_LOOKAHEAD = 1,
    // Boot readback alone uses an opposite-edge first return-pointer stage.
    parameter integer SOURCE_NEGEDGE_READ_POINTER_SYNC1 = 0
) (
    input  wire                 s_clk_i,
    input  wire                 s_reset_n_i,
    input  wire                 s_valid_i,
    output wire                 s_ready_o,
    input  wire [WIDTH-1:0]     s_data_i,
    input  wire                 s_abort_i,
    output wire                 s_full_o,
    output wire                 s_empty_o,
    output wire                 s_protocol_fault_o,

    input  wire                 m_clk_i,
    input  wire                 m_reset_n_i,
    output wire                 m_valid_o,
    input  wire                 m_ready_i,
    output wire [WIDTH-1:0]     m_data_o,
    output wire                 m_empty_o,
    output wire                 m_protocol_fault_o,
    output wire f_source_take_o,
    output wire f_destination_take_o,
    output wire [WIDTH-1:0] f_source_payload_o,
    output wire [WIDTH-1:0] f_destination_payload_o,
    output wire [ADDR_BITS:0] f_write_sequence_o,
    output wire [ADDR_BITS:0] f_read_sequence_o,
    output wire [ADDR_BITS:0] f_used_o,
    output wire [ADDR_BITS:0] f_write_sync1_o,f_write_sync2_o,
    output wire [6:0] f_command_read_source_o,
    output wire [6:0] f_command_read_dest_o,
    output wire [6:0] f_command_read_population_o,
    output wire [ADDR_BITS-1:0] f_point_slot_o,
    output wire [ADDR_BITS:0] f_point_source_sequence_o,
    output wire [WIDTH-1:0] f_point_payload_o,
    output wire f_point_written_o,
    output wire [6:0] f_read_head_ordinal_o,
    output wire [6:0] f_read_point_ordinal_o,
    output wire [18:0] f_word_target_o,
    output wire [255:0] f_word_initial_o,
    output wire [255:0] f_word_admitted_o,
    output wire [255:0] f_word_consumed_o,
    output wire [255:0] f_word_head_before_o,
    output wire [255:0] f_word_point_before_o
);
    localparam integer DEPTH = (1 << ADDR_BITS);
    localparam integer PTR_W = ADDR_BITS + 1;
    // Keep the source-contract check exact while preventing synthesis from
    // turning one WIDTH-bit inequality into a serial carry chain.  Each slice
    // owns a sticky mismatch bit; their registered reduction is equivalent to
    // the predecessor's single-cycle sticky fault observation.
    localparam integer STABILITY_SLICE_W = 8;
    localparam integer STABILITY_SLICES =
        (WIDTH + STABILITY_SLICE_W - 1) / STABILITY_SLICE_W;

    (* nomem2reg, ram_style = RAM_STYLE *)
    logic [WIDTH-1:0] memory_q [0:DEPTH-1];

    logic [PTR_W-1:0] write_binary_q;
    // The Gray MSB is mathematically equal to the binary MSB.  Preserve the
    // named Gray owner so synthesis cannot merge it into the binary register
    // and silently leave the CDC constraint one bit short.
    (* keep = "true", syn_preserve = 1 *)
    logic [PTR_W-1:0] write_gray_q;
    logic write_full_q;
    logic [PTR_W-1:0] read_binary_q;
    (* keep = "true", syn_preserve = 1 *)
    logic [PTR_W-1:0] read_gray_q;

    (* async_reg = "true", syn_preserve = 1 *)
    logic [PTR_W-1:0] read_gray_sync1_q;
    (* async_reg = "true", syn_preserve = 1 *)
    logic [PTR_W-1:0] read_gray_sync2_q;
    (* async_reg = "true", syn_preserve = 1 *)
    logic [PTR_W-1:0] write_gray_sync1_q;
    (* async_reg = "true", syn_preserve = 1 *)
    logic [PTR_W-1:0] write_gray_sync2_q;

    (* syn_preserve = 1 *) logic [WIDTH-1:0] m_data_q;
    logic m_valid_q;
    logic source_fault_q;
    (* keep = 1, syn_preserve = 1 *)
    logic [STABILITY_SLICES-1:0] source_payload_fault_q;
    logic destination_fault_q;
    logic source_stalled_q;
    logic [WIDTH-1:0] source_stalled_data_q;

    wire source_push = s_valid_i && s_ready_o;
    wire destination_pop = m_valid_o && m_ready_i;
    wire [PTR_W-1:0] write_binary_next =
        write_binary_q + {{(PTR_W-1){1'b0}}, source_push};
    wire [PTR_W-1:0] write_gray_next =
        (write_binary_next >> 1) ^ write_binary_next;
    wire [PTR_W-1:0] full_compare_gray = {
        ~read_gray_sync2_q[PTR_W-1:PTR_W-2],
        read_gray_sync2_q[PTR_W-3:0]
    };
    // Precompute both full decisions from registered pointers. The late
    // source handshake selects one bit, rather than entering an increment,
    // Gray encoder and full-pointer comparison in series. Ownership,
    // pointer/synchronizer state and every handshake keep their old cycles.
    wire [PTR_W-1:0] write_binary_after_push =
        write_binary_q + {{(PTR_W-1){1'b0}}, 1'b1};
    (* syn_keep = 1 *) wire write_full_after_push =
        (((write_binary_after_push >> 1) ^ write_binary_after_push) == full_compare_gray);
    (* syn_keep = 1 *) wire write_full_without_push =
        (((write_binary_q >> 1) ^ write_binary_q) == full_compare_gray);
    logic write_full_after_transfer;
    always_comb begin
        write_full_after_transfer = source_push ?
            write_full_after_push : write_full_without_push;
        // Preserve the predecessor's exact four-state arithmetic pessimism.
        // This is simulation behavior, not a physical X/Z detector.
        // synthesis translate_off
        if ($isunknown(write_binary_q) || $isunknown(source_push) ||
            $isunknown(full_compare_gray))
            write_full_after_transfer = (write_gray_next == full_compare_gray);
        // synthesis translate_on
    end
    wire [PTR_W-1:0] read_binary_after_pop =
        read_binary_q + {{(PTR_W-1){1'b0}}, 1'b1};
    wire [PTR_W-1:0] read_gray_after_pop =
        (read_binary_after_pop >> 1) ^ read_binary_after_pop;
    wire memory_not_empty = (read_gray_q != write_gray_sync2_q);
    wire next_row_visible =
        (read_gray_after_pop != write_gray_sync2_q);
    wire [ADDR_BITS-1:0] m_binary_next_address =
        (DESTINATION_LOOKAHEAD && destination_pop) ?
        read_binary_after_pop[ADDR_BITS-1:0] :
        read_binary_q[ADDR_BITS-1:0];
    wire destination_prefetch =
        (!m_valid_q && memory_not_empty) ||
        (DESTINATION_LOOKAHEAD && destination_pop && next_row_visible);
    wire source_payload_fault = |source_payload_fault_q;

    assign s_ready_o = !write_full_q && !source_fault_q &&
                       !source_payload_fault;
    assign s_full_o = write_full_q;
    assign s_empty_o = (write_gray_q == read_gray_sync2_q);
    assign s_protocol_fault_o = source_fault_q || source_payload_fault;
    // The asynchronous distributed-memory DO is terminated in a named
    // destination-domain register.  Gray synchronization makes a row visible
    // only after its source write has settled.  Empty->nonempty first captures
    // the current row; valid cannot be consumed until the following edge.  A
    // default transfer prefetches the next row without another owner slot.
    // With lookahead disabled, consume first clears valid; the following
    // edge captures from the registered current pointer, adding one bubble.
    assign m_valid_o = m_valid_q;
    assign m_data_o = m_data_q;
    assign m_empty_o = !m_valid_q && !memory_not_empty;
    assign m_protocol_fault_o = destination_fault_q;

    initial begin
        if (WIDTH < 1 || ADDR_BITS < 2 ||
            (DESTINATION_LOOKAHEAD != 0 && DESTINATION_LOOKAHEAD != 1) ||
            (SOURCE_NEGEDGE_READ_POINTER_SYNC1 != 0 &&
             SOURCE_NEGEDGE_READ_POINTER_SYNC1 != 1))
            $fatal(1, "board1_async_fifo_gray requires WIDTH>=1 ADDR_BITS>=2 lookahead=0|1");
    end

    // Pointer synchronizers.  Reset assertion is asynchronous in each domain;
    // the product wrapper supplies independently synchronized release.
    generate
        if (SOURCE_NEGEDGE_READ_POINTER_SYNC1) begin : g_boot_return_phase
            always_ff @(negedge s_clk_i or negedge s_reset_n_i) begin
                if (!s_reset_n_i)
                    read_gray_sync1_q <= {PTR_W{1'b0}};
                else
                    read_gray_sync1_q <= read_gray_q;
            end
            always_ff @(posedge s_clk_i or negedge s_reset_n_i) begin
                if (!s_reset_n_i)
                    read_gray_sync2_q <= {PTR_W{1'b0}};
                else
                    read_gray_sync2_q <= read_gray_sync1_q;
            end
        end else begin : g_standard_return_phase
    always_ff @(posedge s_clk_i or negedge s_reset_n_i) begin
        if (!s_reset_n_i) begin
            read_gray_sync1_q <= {PTR_W{1'b0}};
            read_gray_sync2_q <= {PTR_W{1'b0}};
        end else begin
            read_gray_sync1_q <= read_gray_q;
            read_gray_sync2_q <= read_gray_sync1_q;
        end
    end
        end
    endgenerate

    always_ff @(posedge m_clk_i or negedge m_reset_n_i) begin
        if (!m_reset_n_i) begin
            write_gray_sync1_q <= {PTR_W{1'b0}};
            write_gray_sync2_q <= {PTR_W{1'b0}};
        end else begin
            write_gray_sync1_q <= write_gray_q;
            write_gray_sync2_q <= write_gray_sync1_q;
        end
    end

    always_ff @(posedge s_clk_i or negedge s_reset_n_i) begin
        if (!s_reset_n_i) begin
            write_binary_q <= {PTR_W{1'b0}};
            write_gray_q <= {PTR_W{1'b0}};
            write_full_q <= 1'b0;
        end else begin
            if (source_push) begin
                memory_q[write_binary_q[ADDR_BITS-1:0]] <= s_data_i;
                write_binary_q <= write_binary_next;
                write_gray_q <= write_gray_next;
            end
            write_full_q <= write_full_after_transfer;
        end
    end

    // The read pointer advances only on a downstream handshake.  The output
    // register is a copy of the row still owned by that pointer, not an extra
    // slot, so WIDTH/DEPTH retain their literal meaning.
    always_ff @(posedge m_clk_i or negedge m_reset_n_i) begin
        if (!m_reset_n_i) begin
            read_binary_q <= {PTR_W{1'b0}};
            read_gray_q <= {PTR_W{1'b0}};
            m_data_q <= {WIDTH{1'b0}};
            m_valid_q <= 1'b0;
        end else begin
            if (destination_prefetch)
                m_data_q <= memory_q[m_binary_next_address];
            if (!m_valid_q) begin
                if (memory_not_empty)
                    m_valid_q <= 1'b1;
            end else if (destination_pop) begin
                read_binary_q <= read_binary_after_pop;
                read_gray_q <= read_gray_after_pop;
                m_valid_q <= DESTINATION_LOOKAHEAD ? next_row_visible : 1'b0;
            end
        end
    end

    // Exact, timing-bounded payload-stability monitor.  All comparisons occur
    // in parallel eight-bit slices and terminate in registers; no digest or
    // probabilistic check substitutes for bitwise equality.
    genvar stability_slice;
    generate
        for (stability_slice = 0;
             stability_slice < STABILITY_SLICES;
             stability_slice = stability_slice + 1) begin :
             g_source_stability_slice
            localparam integer SLICE_LOW =
                stability_slice * STABILITY_SLICE_W;
            localparam integer SLICE_WIDTH =
                ((SLICE_LOW + STABILITY_SLICE_W) <= WIDTH) ?
                STABILITY_SLICE_W : (WIDTH - SLICE_LOW);
            always_ff @(posedge s_clk_i or negedge s_reset_n_i) begin
                if (!s_reset_n_i) begin
                    source_payload_fault_q[stability_slice] <= 1'b0;
                end else if (!s_abort_i && source_stalled_q &&
                    (s_data_i[SLICE_LOW +: SLICE_WIDTH] !=
                     source_stalled_data_q[SLICE_LOW +: SLICE_WIDTH])) begin
                    source_payload_fault_q[stability_slice] <= 1'b1;
                end
            end
        end
    endgenerate

    // A source that raises valid must hold valid and payload until accepted.
    // Dropped valid and four-state violations retain the scalar sticky owner;
    // the exact payload slices above own data-change violations.  Already
    // accepted entries remain drainable from the destination side.
    always_ff @(posedge s_clk_i or negedge s_reset_n_i) begin
        if (!s_reset_n_i) begin
            source_fault_q <= 1'b0;
            source_stalled_q <= 1'b0;
            source_stalled_data_q <= {WIDTH{1'b0}};
        end else begin
            if (s_abort_i) begin
                source_stalled_q <= 1'b0;
            end else begin
                if (source_stalled_q && !s_valid_i)
                    source_fault_q <= 1'b1;
                source_stalled_q <= s_valid_i && !s_ready_o;
                if (s_valid_i && !s_ready_o && !source_stalled_q)
                    source_stalled_data_q <= s_data_i;
            end
`ifndef SYNTHESIS
`ifndef FORMAL
            // Four-state checks are simulation-only.  A two-state formal
            // engine cannot represent X/Z and may otherwise lower
            // $isunknown() to an unconstrained value.
            if ($isunknown(s_abort_i) ||
                (!s_abort_i && ($isunknown(s_valid_i) ||
                 ((s_valid_i === 1'b1) && $isunknown(s_data_i)))))
                source_fault_q <= 1'b1;
`endif
`endif
        end
    end

    always_ff @(posedge m_clk_i or negedge m_reset_n_i) begin
        if (!m_reset_n_i) begin
            destination_fault_q <= 1'b0;
        end else begin
`ifndef SYNTHESIS
`ifndef FORMAL
            if ($isunknown(m_ready_i))
                destination_fault_q <= 1'b1;
`endif
`endif
        end
    end

`ifdef FORMAL
    logic s_formal_past_valid;
    logic m_formal_past_valid;
    always_ff @(posedge s_clk_i) begin
        s_formal_past_valid <= 1'b1;
        if (s_formal_past_valid && s_reset_n_i && $past(s_reset_n_i)) begin
            assert ($onehot0(write_gray_q ^ $past(write_gray_q)));
            if ($past(write_full_q))
                assert (write_binary_q == $past(write_binary_q));
            if ($past(source_fault_q))
                assert (source_fault_q);
            if ($past(source_payload_fault))
                assert (source_payload_fault);
            if ($past(source_stalled_q && !s_abort_i && s_valid_i &&
                      (s_data_i != source_stalled_data_q)))
                assert (source_payload_fault);
            if ($past(source_stalled_q && !s_abort_i && !s_valid_i))
                assert (source_fault_q);
        end
    end
    always_ff @(posedge m_clk_i) begin
        m_formal_past_valid <= 1'b1;
        if (m_formal_past_valid && m_reset_n_i && $past(m_reset_n_i)) begin
            assert ($onehot0(read_gray_q ^ $past(read_gray_q)));
            if ($past(!m_valid_q && memory_not_empty))
                assert (m_valid_q);
            if ($past(m_valid_o && !m_ready_i)) begin
                assert (m_valid_o);
                assert (m_data_o == $past(m_data_o));
            end
            if ($past(destination_fault_q))
                assert (destination_fault_q);
        end
    end
`endif
    assign f_source_take_o=source_push;
    assign f_destination_take_o=destination_pop;
    assign f_source_payload_o=s_data_i;
    assign f_destination_payload_o=m_data_o;
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
    genvar f_monitor_older, f_monitor_newer;
    generate
        for (f_monitor_older=0;f_monitor_older<6;f_monitor_older=f_monitor_older+1) begin: f_old
            for (f_monitor_newer=f_monitor_older+1;f_monitor_newer<6;f_monitor_newer=f_monitor_newer+1) begin: f_new
                wire [PTR_W-1:0] f_monitor_distance = f_order[f_monitor_newer] - f_order[f_monitor_older];
                always_comb assert(f_monitor_distance <= PTR_W'(DEPTH));
            end
        end
    endgenerate
    wire [PTR_W-1:0] f_conservative_used = f_wseq_q - f_order[0];
    wire [PTR_W-1:0] f_chain_step [0:4];
    generate
        for (f_monitor_older=0;f_monitor_older<5;f_monitor_older=f_monitor_older+1) begin: f_chain
            assign f_chain_step[f_monitor_older] = f_order[f_monitor_older+1] - f_order[f_monitor_older];
        end
    endgenerate
    // An extended sum rules out a circular ordering that can satisfy each
    // modular pair bound separately at the exact half-range f_monitor_distance.
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
         begin end 
         begin end 
         begin end 
         begin end 
    end

    wire[6:0]f_command_read_source,f_command_read_dest,f_command_read_population;
    generate if(WIDTH==276 && ADDR_BITS==5)begin:f_read_commands
        reg[6:0]f_read_wseq,f_read_rseq;
        always @(posedge s_clk_i or negedge s_reset_n_i)begin
            if(!s_reset_n_i)f_read_wseq<=0;
            else if(source_push && !s_data_i[WIDTH-1])f_read_wseq<=f_read_wseq+1'b1;
        end
        always @(posedge m_clk_i or negedge m_reset_n_i)begin
            if(!m_reset_n_i)f_read_rseq<=0;
            else if(destination_pop && !m_data_o[WIDTH-1])f_read_rseq<=f_read_rseq+1'b1;
        end
        wire[6:0]f_read_prefix[0:DEPTH];
        assign f_read_prefix[0]=0;
        for(genvar f_read_row=0;f_read_row<DEPTH;f_read_row=f_read_row+1)begin:f_read_count
            wire[ADDR_BITS-1:0]f_offset=ADDR_BITS'(f_read_row)-f_rseq_q[ADDR_BITS-1:0];
            wire f_is_owned_read=({1'b0,f_offset}<f_used) && !memory_q[f_read_row][WIDTH-1];
            assign f_read_prefix[f_read_row+1]=f_read_prefix[f_read_row]+{6'd0,f_is_owned_read};
        end
        assign f_command_read_source=f_read_wseq;
        assign f_command_read_dest=f_read_rseq;
        assign f_command_read_population=f_read_prefix[DEPTH];
        always @*begin
            assert((f_read_wseq-f_read_rseq)==f_read_prefix[DEPTH]);
            assert(f_read_prefix[DEPTH]<={1'b0,f_used});
            if(m_valid_o)assert(m_data_o[WIDTH-1]==memory_q[read_binary_q[ADDR_BITS-1:0]][WIDTH-1]);
            if(m_valid_o && !m_data_o[WIDTH-1])assert(f_read_prefix[DEPTH]!=0);
        end
    end else begin
        assign f_command_read_source=0;
        assign f_command_read_dest=0;
        assign f_command_read_population=0;
    end endgenerate
    always @*assert(f_used<=PTR_W'(DEPTH));

    assign f_write_sequence_o=f_wseq_q;
    assign f_read_sequence_o=f_rseq_q;
    assign f_used_o=f_used;
    assign f_write_sync1_o=f_order[4];
    assign f_write_sync2_o=f_order[3];
    assign f_command_read_source_o=f_command_read_source;
    assign f_command_read_dest_o=f_command_read_dest;
    assign f_command_read_population_o=f_command_read_population;

    reg[PTR_W-1:0]f_point_source_sequence;
    always @(posedge s_clk_i)begin
        if(s_reset_n_i && source_push && f_wseq_q[ADDR_BITS-1:0]==f_slot)
            f_point_source_sequence<=f_wseq_q;
    end
    always @*begin
        if(f_slot_owned)assert(f_point_source_sequence==f_rseq_q+{1'b0,f_slot_offset});
        if(m_valid_o && read_binary_q[ADDR_BITS-1:0]==f_slot)
            assert(f_point_source_sequence==f_rseq_q);
        if(source_push && write_binary_q[ADDR_BITS-1:0]==f_slot)assert(!f_slot_owned);
    end

    assign f_point_slot_o=f_slot;
    assign f_point_source_sequence_o=f_point_source_sequence;
    assign f_point_payload_o=f_last_payload_q;
    assign f_point_written_o=f_slot_written_q;
    wire[6:0]f_read_head_ordinal,f_read_point_ordinal;

    generate if(WIDTH==276 && ADDR_BITS==5)begin:f_read_ordinals
        reg[6:0]f_before_read_sequence[0:DEPTH-1];

        assign f_read_head_ordinal=f_before_read_sequence[read_binary_q[ADDR_BITS-1:0]];
        assign f_read_point_ordinal=f_before_read_sequence[f_slot];

        always @(posedge s_clk_i)begin
            if(s_reset_n_i && source_push)
                f_before_read_sequence[write_binary_q[ADDR_BITS-1:0]]<=f_command_read_source;
        end
        for(genvar f_rank_j=0;f_rank_j<DEPTH;f_rank_j=f_rank_j+1)begin:f_rows
            wire[ADDR_BITS-1:0]f_offset=ADDR_BITS'(f_rank_j)-f_rseq_q[ADDR_BITS-1:0];
            wire[PTR_W-1:0]f_distance={1'b0,f_offset};
            wire[6:0]f_after=f_before_read_sequence[f_rank_j]+{6'd0,!memory_q[f_rank_j][WIDTH-1]};
            always @*if(f_distance<f_used)begin
                if((f_distance+PTR_W'(1))<f_used)
                    assert(f_before_read_sequence[(f_rank_j+1)%DEPTH]==f_after);
                else assert(f_command_read_source==f_after);
            end
        end
        always @*begin
            if(f_used!=0)assert(f_before_read_sequence[read_binary_q[ADDR_BITS-1:0]]==f_command_read_dest);
            if(f_used==0)assert(f_command_read_source==f_command_read_dest);
            assert(f_used<=PTR_W'(DEPTH));
            if(source_push)assert(f_used<PTR_W'(DEPTH));
            if(destination_pop)assert(f_used!=0);
            if(m_valid_o)assert(m_data_o[WIDTH-1]==memory_q[read_binary_q[ADDR_BITS-1:0]][WIDTH-1]);
        end
    end else begin
        assign f_read_head_ordinal=0;
        assign f_read_point_ordinal=0;
    end endgenerate

    assign f_read_head_ordinal_o=f_read_head_ordinal;
    assign f_read_point_ordinal_o=f_read_point_ordinal;

    wire[18:0]f_word_target_view;
    wire[255:0]f_word_initial_view,f_word_admitted_view,f_word_consumed_view;
    wire[255:0]f_word_head_before_view,f_word_point_before_view;

    generate if(WIDTH==276 && ADDR_BITS==5)begin:f_word_history

    // These histories never drive native logic. The arbitrary initial word
    // represents retained digital memory contents, not a zero/erasure promise.
    (* anyconst *) reg[18:0]f_word_address;
    (* anyconst *) reg[255:0]f_word_initial;
    reg[255:0]f_word_admitted,f_word_consumed;
    reg[255:0]f_word_before[0:DEPTH-1];
    wire f_word_source_write=s_data_i[275] && s_data_i[274:256]==f_word_address;
    wire f_word_destination_write=m_data_o[275] && m_data_o[274:256]==f_word_address;
    always @(posedge s_clk_i or negedge s_reset_n_i)begin
        if(!s_reset_n_i)f_word_admitted<=f_word_initial;
        else if(source_push && f_word_source_write)f_word_admitted<=s_data_i[255:0];
    end
    always @(posedge s_clk_i)if(source_push)
        f_word_before[write_binary_q[ADDR_BITS-1:0]]<=f_word_admitted;
    always @(posedge m_clk_i or negedge m_reset_n_i)begin
        if(!m_reset_n_i)f_word_consumed<=f_word_initial;
        else if(destination_pop && f_word_destination_write)f_word_consumed<=m_data_o[255:0];
    end
    // Every occupied command links the value before it to the value after
    // it. The chain spans the actual queue, including wrap and simultaneous
    // independent-clock edges; it is not an equal-reply input condition.
    for(genvar f_word_row=0;f_word_row<DEPTH;f_word_row=f_word_row+1)begin:f_word_chain
        wire[ADDR_BITS-1:0]f_offset=ADDR_BITS'(f_word_row)-f_rseq_q[ADDR_BITS-1:0];
        wire[ADDR_BITS-1:0]f_next=ADDR_BITS'(f_word_row+1);
        wire[WIDTH-1:0]f_command=memory_q[f_word_row];
        wire[255:0]f_after=f_command[275] && f_command[274:256]==f_word_address ?
            f_command[255:0] : f_word_before[f_word_row];
        always @*if({1'b0,f_offset}<f_used)
            assert((({1'b0,f_offset}+PTR_W'(1))==f_used ?
                f_word_admitted : f_word_before[f_next])==f_after);
    end
    always @*begin
        assert(f_used<=PTR_W'(DEPTH));
        if(f_used==0)assert(f_word_consumed==f_word_admitted);
        else assert(f_word_consumed==f_word_before[f_rseq_q[ADDR_BITS-1:0]]);
        if(m_valid_o)assert(m_data_o==memory_q[read_binary_q[ADDR_BITS-1:0]]);
    end
    always @(posedge m_clk_i)begin
        cover(destination_pop && !m_data_o[275] && m_data_o[274:256]==f_word_address);
        cover(m_valid_o && !m_ready_i && f_word_admitted!=f_word_consumed);
    end

        assign f_word_target_view=f_word_address;
        assign f_word_initial_view=f_word_initial;
        assign f_word_admitted_view=f_word_admitted;
        assign f_word_consumed_view=f_word_consumed;
        assign f_word_head_before_view=f_word_before[read_binary_q[ADDR_BITS-1:0]];
        assign f_word_point_before_view=f_word_before[f_slot];

    end else begin
        assign f_word_target_view=0;
        assign f_word_initial_view=0;
        assign f_word_admitted_view=0;
        assign f_word_consumed_view=0;
        assign f_word_head_before_view=0;
        assign f_word_point_before_view=0;
    end endgenerate

    assign f_word_target_o=f_word_target_view;
    assign f_word_initial_o=f_word_initial_view;
    assign f_word_admitted_o=f_word_admitted_view;
    assign f_word_consumed_o=f_word_consumed_view;
    assign f_word_head_before_o=f_word_head_before_view;
    assign f_word_point_before_o=f_word_point_before_view;
endmodule

module board1_thin_ddr_app_transport (
    input wire core_clk_i, core_reset_n_i, app_clk_i, app_reset_n_i,
    input wire core_stop_i,
    output wire core_fault_o, core_controller_good_o,
    input wire [2:0] core_cmd_i,
    input wire core_cmd_en_i,
    input wire [28:0] core_addr_i,
    input wire [255:0] core_wr_data_i,
    input wire core_wr_en_i, core_wr_end_i,
    input wire [31:0] core_wr_mask_i,
    input wire core_burst_i, core_self_refresh_i, core_refresh_i,
    output wire core_cmd_ready_o, core_wr_ready_o,
    output wire [255:0] core_rd_data_o,
    output wire core_rd_valid_o, core_rd_end_o,
    input wire controller_pll_lock_i, controller_calibrated_i,
    input wire app_cmd_ready_i, app_wr_ready_i,
    output wire [2:0] app_cmd_o,
    output wire app_cmd_en_o,
    output wire [28:0] app_addr_o,
    output wire [255:0] app_wr_data_o,
    output wire app_wr_en_o, app_wr_end_o,
    output wire [31:0] app_wr_mask_o,
    input wire [255:0] app_rd_data_i,
    input wire app_rd_valid_i, app_rd_end_i,
    output wire app_burst_o, app_self_refresh_o, app_refresh_o
);
    localparam integer MAX_READS = 32;
    localparam integer COMMAND_W = 276; // write + 19-bit word + 256-bit data
    wire common_reset_n = core_reset_n_i && app_reset_n_i;
    (* async_reg="true", syn_preserve=1 *) logic [2:0] core_release_q, app_release_q;
    always_ff @(posedge core_clk_i or negedge common_reset_n) begin
        if (!common_reset_n) core_release_q <= 0;
        else core_release_q <= {core_release_q[1:0],1'b1};
    end
    always_ff @(posedge app_clk_i or negedge common_reset_n) begin
        if (!common_reset_n) app_release_q <= 0;
        else app_release_q <= {app_release_q[1:0],1'b1};
    end
    wire core_reset_n = core_release_q[2];
    wire app_reset_n = app_release_q[2];

    logic core_fault_q, app_fault_q, app_good_q, app_seen_q;
    (* async_reg="true", syn_preserve=1 *) logic [1:0] good_core_q, fault_core_q;
    logic [5:0] reserved_q, physical_reads_q;
    wire controller_good = controller_pll_lock_i && controller_calibrated_i;
    wire request_s_ready, request_s_fault, request_m_fault, request_m_valid, physical_ready;
    wire [COMMAND_W-1:0] request_m_data;
    wire response_s_ready, response_s_fault, response_m_fault, response_m_valid;
    wire [256:0] response_m_data;

    assign core_fault_o = core_fault_q || fault_core_q[1];
    assign core_controller_good_o = core_reset_n && good_core_q[1] && !core_fault_o;
    // Reserve a response slot BEFORE admission. Writes share the conservative
    // cap, so no combinational command/VALID dependence enters READY.
    wire core_ready = core_controller_good_o && !core_stop_i &&
                      request_s_ready && (reserved_q < 6'(MAX_READS));
    assign core_cmd_ready_o = core_ready;
    assign core_wr_ready_o = core_ready;
    wire core_write = core_cmd_i == 3'd0;
    wire core_read = core_cmd_i == 3'd1;
    wire core_bad = core_burst_i || core_self_refresh_i || core_refresh_i ||
        (core_cmd_en_i && (!core_ready || (!core_write && !core_read) ||
            core_addr_i[28:22] != 0 || core_addr_i[2:0] != 0 ||
            core_addr_i[21:3] >= 19'd448256 ||
            (core_write && (!core_wr_en_i || !core_wr_end_i || core_wr_mask_i != 0)) ||
            (core_read && (core_wr_en_i || core_wr_end_i)))) ||
        (core_wr_en_i && (!core_cmd_en_i || !core_write));
    wire enqueue = core_cmd_en_i && core_ready && !core_bad;

    board1_async_fifo_gray #(.WIDTH(COMMAND_W), .ADDR_BITS(5),
        .RAM_STYLE("block")) u_commands (
        .s_clk_i(core_clk_i), .s_reset_n_i(core_reset_n),
        .s_valid_i(enqueue), .s_ready_o(request_s_ready),
        .s_data_i({core_write,core_addr_i[21:3],core_wr_data_i}), .s_abort_i(1'b0),
        .s_full_o(), .s_empty_o(), .s_protocol_fault_o(request_s_fault),
        .m_clk_i(app_clk_i), .m_reset_n_i(app_reset_n),
        .m_valid_o(request_m_valid), .m_ready_i(physical_ready),
        .m_data_o(request_m_data), .m_empty_o(), .m_protocol_fault_o(request_m_fault),
        .f_source_take_o(f_cs_take),
        .f_destination_take_o(f_cd_take),
        .f_source_payload_o(f_cs_data),
        .f_destination_payload_o(f_cd_data)
    ,
        .f_write_sequence_o(f_command_source),
        .f_read_sequence_o(f_command_dest),
        .f_used_o(f_command_used),
        .f_command_read_source_o(f_command_read_source),
        .f_command_read_dest_o(f_command_read_dest),
        .f_command_read_population_o(f_command_read_population)
    ,
        .f_point_slot_o(f_command_point_slot),
        .f_point_source_sequence_o(f_command_point_sequence),
        .f_point_payload_o(f_command_point_payload),
        .f_point_written_o(f_command_point_written)
    ,
        .f_read_head_ordinal_o(f_command_head_read_ordinal),
        .f_read_point_ordinal_o(f_command_point_read_ordinal)
    ,
        .f_word_target_o(f_word_target),
        .f_word_initial_o(f_word_initial),
        .f_word_admitted_o(f_word_admitted),
        .f_word_consumed_o(f_word_consumed),
        .f_word_head_before_o(f_word_head_before),
        .f_word_point_before_o(f_word_point_before)
    );

    wire physical_write = request_m_data[275];
    assign physical_ready = app_reset_n && app_good_q && controller_good &&
        !app_fault_q && app_cmd_ready_i && (!physical_write || app_wr_ready_i);
    wire issue = request_m_valid && physical_ready;
    wire issue_read = issue && !physical_write;
    // All payloads originate in the destination FIFO register; no upstream
    // address-policy/owner/reset reduction is in the physical command cone.
    assign app_cmd_o = physical_write ? 3'd0 : 3'd1;
    assign app_addr_o = {7'd0,request_m_data[274:256],3'b000};
    assign app_wr_data_o = request_m_data[255:0];
    assign app_cmd_en_o = issue;
    assign app_wr_en_o = issue && physical_write;
    assign app_wr_end_o = app_wr_en_o;
    assign app_wr_mask_o = 32'd0;
    assign app_burst_o = 1'b0;
    assign app_self_refresh_o = 1'b0;
    assign app_refresh_o = 1'b0;

    wire owned_return = app_rd_valid_i && physical_reads_q != 0;
    wire capture_return = app_reset_n && owned_return && response_s_ready;
    board1_async_fifo_gray #(.WIDTH(257), .ADDR_BITS(6),
        .RAM_STYLE("block")) u_returns (
        .s_clk_i(app_clk_i), .s_reset_n_i(app_reset_n),
        .s_valid_i(capture_return), .s_ready_o(response_s_ready),
        .s_data_i({app_rd_end_i,app_rd_data_i}), .s_abort_i(1'b0),
        .s_full_o(), .s_empty_o(), .s_protocol_fault_o(response_s_fault),
        .m_clk_i(core_clk_i), .m_reset_n_i(core_reset_n),
        .m_valid_o(response_m_valid), .m_ready_i(1'b1),
        .m_data_o(response_m_data), .m_empty_o(), .m_protocol_fault_o(response_m_fault),
        .f_source_take_o(f_rs_take),
        .f_destination_take_o(f_rd_take),
        .f_source_payload_o(f_rs_data),
        .f_destination_payload_o(f_rd_data)
    ,
        .f_write_sequence_o(f_return_source),
        .f_read_sequence_o(f_return_dest),
        .f_used_o(f_return_used),
        .f_write_sync1_o(f_return_sync1_sequence),
        .f_write_sync2_o(f_return_sync2_sequence),
        .f_command_read_source_o(f_unused_return_read_source),
        .f_command_read_dest_o(f_unused_return_read_dest),
        .f_command_read_population_o(f_unused_return_read_population)
    ,
        .f_point_slot_o(f_return_point_slot),
        .f_point_source_sequence_o(f_return_point_sequence),
        .f_point_payload_o(f_return_point_payload),
        .f_point_written_o(f_return_point_written)
    ,
        .f_read_head_ordinal_o(f_unused_return_head_read_ordinal),
        .f_read_point_ordinal_o(f_unused_return_point_read_ordinal)
    ,
        .f_word_target_o(f_unused_return_word_target),
        .f_word_initial_o(f_unused_return_word_initial),
        .f_word_admitted_o(f_unused_return_word_admitted),
        .f_word_consumed_o(f_unused_return_word_consumed),
        .f_word_head_before_o(f_unused_return_word_head_before),
        .f_word_point_before_o(f_unused_return_word_point_before)
    );
    assign core_rd_valid_o = core_reset_n && response_m_valid;
    assign core_rd_data_o = response_m_data[255:0];
    assign core_rd_end_o = response_m_data[256];

    always_ff @(posedge core_clk_i or negedge core_reset_n) begin
        if (!core_reset_n) begin
            good_core_q <= 0; fault_core_q <= 0;
            core_fault_q <= 0; reserved_q <= 0;
        end else begin
            good_core_q <= {good_core_q[0],app_good_q};
            fault_core_q <= {fault_core_q[0],app_fault_q};
            if (core_bad || request_s_fault || response_m_fault ||
                (core_rd_valid_o && reserved_q == 0)) core_fault_q <= 1;
            case ({enqueue && core_read,core_rd_valid_o})
                2'b10: reserved_q <= reserved_q + 6'd1;
                2'b01: if (reserved_q != 0) reserved_q <= reserved_q - 6'd1;
                default: ;
            endcase
        end
    end
    always_ff @(posedge app_clk_i or negedge app_reset_n) begin
        if (!app_reset_n) begin
            app_good_q <= 0; app_seen_q <= 0; app_fault_q <= 0;
            physical_reads_q <= 0;
        end else begin
            app_good_q <= controller_good;
            if (controller_good) app_seen_q <= 1;
            if ((app_seen_q && !controller_good) || request_m_fault || response_s_fault ||
                (app_rd_valid_i && (!owned_return || !response_s_ready ||
                    !app_rd_end_i || !controller_good)) ||
                (issue_read && physical_reads_q == 6'(MAX_READS) && !owned_return))
                app_fault_q <= 1;
            case ({issue_read,owned_return})
                2'b10: physical_reads_q <= physical_reads_q + 6'd1;
                2'b01: physical_reads_q <= physical_reads_q - 6'd1;
                default: ;
            endcase
        end
    end
`ifdef FORMAL
    always_ff @(posedge core_clk_i) if (core_reset_n) begin
        assert (reserved_q <= MAX_READS);
        assert (!core_stop_i || !enqueue);
        if (core_rd_valid_o) assert (reserved_q != 0);
    end
    always_ff @(posedge app_clk_i) if (app_reset_n) begin
        assert (physical_reads_q <= MAX_READS);
        if (app_cmd_en_o) assert (app_cmd_ready_i);
        if (app_wr_en_o) assert (app_cmd_en_o && app_wr_ready_i && app_wr_end_o);
    end
`endif

    wire f_cs_take,f_cd_take,f_rs_take,f_rd_take;
    wire[275:0]f_cs_data,f_cd_data;
    wire[256:0]f_rs_data,f_rd_data;

    always @*begin
        assert(f_cs_take==enqueue);
        assert(f_cs_data=={core_write,core_addr_i[21:3],core_wr_data_i});
        assert(f_cd_take==app_cmd_en_o);
        if(app_cmd_en_o)assert({app_cmd_o==3'd0,app_addr_o[21:3],app_wr_data_o}==f_cd_data);
        if(app_cmd_en_o)assert(app_addr_o[28:22]==0 && app_addr_o[2:0]==0);
        assert(app_wr_en_o==(app_cmd_en_o && app_cmd_o==3'd0));
        assert(app_wr_end_o==app_wr_en_o);
        if(core_stop_i)assert(!f_cs_take);
        assert(f_rs_take==capture_return);
        assert(f_rs_data=={app_rd_end_i,app_rd_data_i});
        if(core_reset_n)assert(f_rd_take==core_rd_valid_o);
        if(core_rd_valid_o)assert({core_rd_end_o,core_rd_data_o}==f_rd_data);
        if(!core_reset_n)assert(!core_rd_valid_o);
        if(app_fault_q || !controller_good)assert(!f_cd_take);
        assert(app_wr_mask_o==0 && !app_burst_o && !app_self_refresh_o && !app_refresh_o);
    end
    always @(posedge core_clk_i)begin
        cover(enqueue && core_write);
        cover(core_rd_valid_o);
    end
    always @(posedge app_clk_i)begin
        cover(app_cmd_en_o && app_cmd_o==0);
        cover(app_cmd_en_o && app_cmd_o==1);
        cover(capture_return);
    end


    wire[5:0]f_command_source,f_command_dest,f_command_used;
    wire[6:0]f_command_read_source,f_command_read_dest,f_command_read_population;
    wire[6:0]f_return_source,f_return_dest,f_return_used;
    wire[6:0]f_unused_return_read_source,f_unused_return_read_dest,f_unused_return_read_population;

    reg[6:0]f_owned_return_sequence,f_lost_return_count;
    reg f_lost_return_seen;
    wire f_owned_return_event=app_reset_n && owned_return;
    wire f_lost_return_event=f_owned_return_event && !capture_return;
    always @(posedge app_clk_i or negedge app_reset_n)begin
        if(!app_reset_n)begin
            f_owned_return_sequence<=0;f_lost_return_count<=0;f_lost_return_seen<=0;
        end else begin
            if(owned_return)f_owned_return_sequence<=f_owned_return_sequence+1'b1;
            if(f_lost_return_event)begin
                f_lost_return_count<=f_lost_return_count+1'b1;f_lost_return_seen<=1;
            end
        end
    end
    wire[6:0]f_queued_read_count=f_command_read_source-f_command_read_dest;
    wire[6:0]f_issued_read_debt=f_command_read_dest-f_owned_return_sequence;
    wire[6:0]f_core_read_debt=f_command_read_source-f_return_dest;
    wire[6:0]f_uncaptured_return_debt=f_owned_return_sequence-f_return_source;
    wire[8:0]f_total_read_debt={2'd0,f_queued_read_count}+{3'd0,physical_reads_q}+
        {2'd0,f_return_used}+{2'd0,f_lost_return_count};
    always @*begin
        assert(core_release_q==0 || core_release_q==1 || core_release_q==3 || core_release_q==7);
        assert(app_release_q==0 || app_release_q==1 || app_release_q==3 || app_release_q==7);
        assert(f_queued_read_count==f_command_read_population);
        assert(f_queued_read_count<=32);
        assert(f_issued_read_debt=={1'b0,physical_reads_q});
        assert(f_core_read_debt=={1'b0,reserved_q});
        assert(f_uncaptured_return_debt==f_lost_return_count);
        assert(f_total_read_debt=={3'd0,reserved_q});
        assert(f_total_read_debt<=32);
        assert(reserved_q<=32 && physical_reads_q<=32 && f_return_used<=32 && f_lost_return_count<=32);
        if(core_rd_valid_o)assert(reserved_q!=0);
        if(f_lost_return_count!=0)assert(f_lost_return_seen);
        if(f_lost_return_seen)assert(app_fault_q);
        if(core_fault_o)assert(!enqueue && !core_ready);
        if(app_fault_q)assert(!issue);
        if(core_ready)assert(core_reset_n && app_reset_n);
        if(good_core_q!=0)assert(app_reset_n);
        if(!core_reset_n || !app_reset_n)assert(f_total_read_debt==0);
    end
    always @(posedge core_clk_i)cover(core_rd_valid_o && core_stop_i);
    always @(posedge app_clk_i)cover(f_owned_return_event && !app_rd_end_i);


    wire[4:0]f_command_point_slot;
    wire[5:0]f_command_point_sequence,f_return_point_slot;
    wire[6:0]f_return_point_sequence;
    wire[275:0]f_command_point_payload;
    wire[256:0]f_return_point_payload;
    wire f_command_point_written,f_return_point_written;

    always @*begin
        if(issue && f_command_dest[4:0]==f_command_point_slot)begin
            assert(f_command_point_written);
            assert(f_command_point_sequence==f_command_dest);
            assert({(app_cmd_o==3'b000),app_addr_o[21:3],app_wr_data_o}==f_command_point_payload);
        end
        if(core_rd_valid_o && f_return_dest[5:0]==f_return_point_slot)begin
            assert(f_return_point_written);
            assert(f_return_point_sequence==f_return_dest);
            assert({core_rd_end_o,core_rd_data_o}==f_return_point_payload);
        end
        if(!app_fault_q)assert(f_return_source==f_owned_return_sequence);
    end


    wire[6:0]f_command_head_read_ordinal,f_command_point_read_ordinal;
    wire[6:0]f_unused_return_head_read_ordinal,f_unused_return_point_read_ordinal;

    always @*begin
        if(issue)assert(f_command_head_read_ordinal==f_command_read_dest);
        if(issue && f_command_dest[4:0]==f_command_point_slot)
            assert(f_command_point_read_ordinal==f_command_read_dest);
    end


    wire[18:0]f_word_target,f_unused_return_word_target;
    wire[255:0]f_word_initial,f_word_admitted,f_word_consumed;
    wire[255:0]f_word_head_before,f_word_point_before;
    wire[255:0]f_unused_return_word_initial,f_unused_return_word_admitted,f_unused_return_word_consumed;
    wire[255:0]f_unused_return_word_head_before,f_unused_return_word_point_before;

    // Independent histories use actual core/physical fields, not FIFO data or
    // desired future replies. The shared arbitrary seed is an initial word.
    reg[255:0]f_actual_admission_word,f_actual_physical_word,f_point_admission_word;
    wire f_actual_admission_write=enqueue && core_write && core_addr_i[21:3]==f_word_target;
    wire f_actual_physical_write=app_wr_en_o && app_addr_o=={7'd0,f_word_target,3'd0};
    always @(posedge core_clk_i or negedge core_reset_n)begin
        if(!core_reset_n)f_actual_admission_word<=f_word_initial;
        else if(f_actual_admission_write)f_actual_admission_word<=core_wr_data_i;
    end
    always @(posedge app_clk_i or negedge app_reset_n)begin
        if(!app_reset_n)f_actual_physical_word<=f_word_initial;
        else if(f_actual_physical_write)f_actual_physical_word<=app_wr_data_o;
    end
    always @(posedge core_clk_i)begin
        if(enqueue && f_command_source[4:0]==f_command_point_slot)
            f_point_admission_word<=f_actual_admission_word;
    end
    always @*begin
        assert(f_actual_admission_word==f_word_admitted);
        assert(f_actual_physical_word==f_word_consumed);
        if(f_command_point_written)assert(f_point_admission_word==f_word_point_before);
    end

    always @*begin
        if(issue)assert(f_word_head_before==f_word_consumed);
        if(issue && f_command_dest[4:0]==f_command_point_slot)begin
            assert(f_word_head_before==f_word_point_before);
            assert(f_actual_physical_word==f_point_admission_word);
        end
    end


    // The low five bits of the arbitrary return-FIFO point cover every
    // snapshot slot. This observer cannot influence a native input or state.
    wire[4:0]f_record_slot=f_return_point_slot[4:0];
    wire[6:0]f_issued_not_retired=f_command_read_dest-f_return_dest;
    wire[4:0]f_record_offset=f_record_slot-f_return_dest[4:0];
    wire f_record_live={2'd0,f_record_offset}<f_issued_not_retired;
    wire f_record_issue=app_cmd_en_o && app_cmd_ready_i && app_cmd_o==3'b001;
    reg f_record_seen;
    reg[6:0]f_record_sequence;
    reg[18:0]f_record_address;
    reg[255:0]f_record_word;
    always @(posedge app_clk_i or negedge app_reset_n)begin
        if(!app_reset_n)f_record_seen<=0;
        else if(f_record_issue && f_command_read_dest[4:0]==f_record_slot)begin
            f_record_seen<=1;
            f_record_sequence<=f_command_read_dest;
            f_record_address<=app_addr_o[21:3];
            f_record_word<=f_actual_physical_word;
        end
    end
    always @*begin
        assert(f_issued_not_retired<=32);
        if(f_record_issue)assert(f_issued_not_retired<32);
        if(core_rd_valid_o)assert(f_issued_not_retired!=0);
        if(f_record_live)assert(f_record_seen);
        if(f_record_live)assert(f_record_sequence==f_return_dest+{2'd0,f_record_offset});
        if(f_record_issue && f_command_read_dest[4:0]==f_record_slot)assert(!f_record_live);
    end
    always @(posedge core_clk_i)cover(core_rd_valid_o && f_record_live && f_record_address==f_word_target && f_record_word!=0);


    // External digital DDR boundary: ordered, full-beat responses to actual
    // previously accepted physical reads. Only healthy pre-fault beats are constrained; all post-fault/lost-controller responses are unrestricted. No future-health or latency/liveness promise.
    // J and V are independent physical-interface event histories.
    reg[6:0]f_vendor_issued,f_vendor_returned;
    always @(posedge app_clk_i or negedge app_reset_n)begin
        if(!app_reset_n)begin f_vendor_issued<=0;f_vendor_returned<=0;end
        else begin
            if(app_cmd_en_o && app_cmd_ready_i && app_cmd_o==3'b001)
                f_vendor_issued<=f_vendor_issued+1'b1;
            if(app_rd_valid_i)f_vendor_returned<=f_vendor_returned+1'b1;
        end
    end
    wire[6:0]f_vendor_pending=f_vendor_issued-f_vendor_returned;
    always @(posedge app_clk_i) if(app_reset_n && app_rd_valid_i && controller_good && !app_fault_q)begin
        assume(f_vendor_pending!=0);
        assume(app_rd_end_i);
        // Projection of an ordered word memory onto one arbitrary tracked
        // address and outstanding-read slot. The snapshot producer is proved
        // separately and cannot be overwritten before actual core retirement.
        if(f_vendor_returned[4:0]==f_record_slot && f_record_address==f_word_target)
            assume(app_rd_data_i==f_record_word);
    end


    wire[5:0]f_return_point_offset=f_return_point_slot-f_return_dest[5:0];
    wire f_return_point_live={1'b0,f_return_point_offset}<f_return_used;
    always @*begin
        assert(f_vendor_issued==f_command_read_dest);
        if(!app_fault_q)begin
            assert(f_vendor_returned==f_owned_return_sequence);
            assert(f_vendor_pending=={1'b0,physical_reads_q});
            assert(f_vendor_pending<=32);
        end
        if(!f_return_point_poison_q && f_return_point_live)begin
            assert(f_record_live);
            assert(f_record_sequence==f_return_point_sequence);
            assert(f_return_point_payload[256]);
            if(f_record_address==f_word_target)
                assert(f_return_point_payload=={1'b1,f_record_word});
        end
        if(!app_fault_q && core_rd_valid_o && f_return_dest[5:0]==f_return_point_slot)begin
            assert(f_record_live);
            assert(f_record_sequence==f_return_dest);
            if(f_record_address==f_word_target)assert(core_rd_data_o==f_record_word);
            assert(core_rd_end_o);
        end
    end
    always @(posedge core_clk_i)cover(!app_fault_q && core_rd_valid_o &&
        f_return_dest[5:0]==f_return_point_slot && f_record_address==f_word_target &&
        f_record_word!=0 && core_stop_i);

    // Nondriving history of the arbitrary return slot's last native capture.
    (* keep *) logic f_return_point_poison_q;
    always_ff @(posedge app_clk_i or negedge app_reset_n) begin
        if(!app_reset_n) f_return_point_poison_q<=0;
        else if(f_rs_take && f_return_source[5:0]==f_return_point_slot)
            f_return_point_poison_q<=app_fault_q || !controller_good;
    end

    // Raw interface ownership is observed on the same edge as its contract.
    always @(posedge app_clk_i) begin
        if(app_reset_n && app_rd_valid_i && controller_good && !app_fault_q) begin
            assert(owned_return); // sampled native return owner
            if(f_vendor_returned[4:0]==f_record_slot) begin
                assert(f_record_live);
                assert(f_record_sequence==f_vendor_returned);
            end
        end
    end

    wire[6:0] f_poison_offset=f_return_point_sequence-f_return_dest;
    wire[6:0] f_return_sync1_sequence,f_return_sync2_sequence;
    wire[6:0] f_return_sync1_used=f_return_sync1_sequence-f_return_dest;
    wire[6:0] f_return_sync2_used=f_return_sync2_sequence-f_return_dest;
    always @* begin
        if(f_return_point_poison_q) assert(app_fault_q);
        if(f_return_point_poison_q && f_return_point_live) begin
            if(f_poison_offset<f_return_sync1_used) assert(fault_core_q[0]);
            if(f_poison_offset<f_return_sync2_used) assert(fault_core_q[1]);
        end
        if(core_rd_valid_o && f_return_dest[5:0]==f_return_point_slot && f_return_point_poison_q)
            assert(core_fault_o);
        // The actual parent's success boundary, without a private app-fault premise.
        if(core_rd_valid_o && !core_fault_o && f_return_dest[5:0]==f_return_point_slot) begin
            assert(!f_return_point_poison_q);
            assert(f_record_live);
            assert(f_record_sequence==f_return_dest);
            if(f_record_address==f_word_target) assert(core_rd_data_o==f_record_word);
            assert(core_rd_end_o);
        end
    end

    // The same arbitrary read-ordinal slot as the physical snapshot observer.
    // These fields are produced only by ACTUAL accepted core READ commands.
    (* keep *) reg f_src_seen;
    (* keep *) reg[6:0]f_src_sequence;
    (* keep *) reg[18:0]f_src_address;
    (* keep *) reg[255:0]f_src_word;
    wire f_src_capture=enqueue && !core_write &&
        f_command_read_source[4:0]==f_record_slot;
    always @(posedge core_clk_i or negedge core_reset_n)begin
        if(!core_reset_n)f_src_seen<=0;
        else if(f_src_capture)begin
            f_src_seen<=1;
            f_src_sequence<=f_command_read_source;
            f_src_address<=core_addr_i[21:3];
            f_src_word<=f_actual_admission_word;
        end
    end

endmodule
