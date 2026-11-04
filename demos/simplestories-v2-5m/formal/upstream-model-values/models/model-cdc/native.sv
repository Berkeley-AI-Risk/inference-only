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
    input wire [ADDR_BITS-1:0] f_observe_slot_i,
    output wire [ADDR_BITS:0] f_read_sync2_o,f_read_sync1_o,
    output wire f_native_full_o,f_stalled_o,
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
    wire [ADDR_BITS-1:0] f_slot=f_observe_slot_i;
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
    assign f_read_sync2_o=f_order[0];
    assign f_read_sync1_o=f_order[1];
    assign f_native_full_o=write_full_q;
    assign f_stalled_o=source_stalled_q;
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
module board1_private_model_ddr_cdc (
    input wire core_clk_i, core_reset_n_i, core_upstream_fault_i,
    input wire core_req_valid_i,
    output wire core_req_ready_o,
    input wire [18:0] core_req_word_i,
    output wire core_rsp_valid_o,
    output wire [255:0] core_rsp_data_o,
    output wire core_rsp_error_o,
    output wire core_fault_o,
    input wire app_clk_i, app_reset_n_i, app_upstream_fault_i,
    output wire app_req_valid_o,
    input wire app_req_ready_i,
    output wire [18:0] app_req_word_o,
    input wire app_rsp_valid_i,
    input wire [255:0] app_rsp_data_i,
    input wire app_rsp_error_i,
    output wire app_fault_o
);
    wire f_req_s;
    wire f_req_d;
    wire [6:0] f_req_wseq;
    wire [6:0] f_req_rseq;
    wire [6:0] f_req_used;
    wire [6:0] f_req_ws2;
    wire [6:0] f_req_rs2;
    wire [6:0] f_req_point_seq;
    wire [18:0] f_req_point_data;
    wire f_req_point_seen;
    wire [6:0] f_req_ws1;
    wire [6:0] f_req_rs1;
    wire f_req_full;
    wire f_req_stalled;
    wire f_rsp_s;
    wire f_rsp_d;
    wire [6:0] f_rsp_wseq;
    wire [6:0] f_rsp_rseq;
    wire [6:0] f_rsp_used;
    wire [6:0] f_rsp_ws2;
    wire [6:0] f_rsp_rs2;
    wire [6:0] f_rsp_point_seq;
    wire [256:0] f_rsp_point_data;
    wire f_rsp_point_seen;
    wire [6:0] f_rsp_ws1;
    wire [6:0] f_rsp_rs1;
    wire f_rsp_full;
    wire f_rsp_stalled;
    wire f_credit_s;
    wire f_credit_d;
    wire [6:0] f_credit_wseq;
    wire [6:0] f_credit_rseq;
    wire [6:0] f_credit_used;
    wire [6:0] f_credit_ws2;
    wire [6:0] f_credit_rs2;
    wire [6:0] f_credit_point_seq;
    wire [0:0] f_credit_point_data;
    wire f_credit_point_seen;
    wire [6:0] f_credit_ws1;
    wire [6:0] f_credit_rs1;
    wire f_credit_full;
    wire f_credit_stalled;
    wire req_s_ready,req_m_valid,req_m_ready,req_s_fault,req_m_fault;
    wire rsp_s_ready,rsp_m_valid,rsp_m_ready,rsp_s_fault,rsp_m_fault;
    wire credit_s_ready,credit_m_valid,credit_m_ready,credit_s_fault,credit_m_fault;
    wire [256:0] response_payload;
    logic core_fault_q,app_fault_q;
    (* async_reg="true",syn_preserve=1 *) logic app_fault_meta_q,app_fault_sync_q;
    (* async_reg="true",syn_preserve=1 *) logic core_fault_meta_q,core_fault_sync_q;
    logic [5:0] reserved_q,inflight_q;
    wire core_dead=core_fault_q || app_fault_sync_q || core_upstream_fault_i;
    wire app_dead=app_fault_q || core_fault_sync_q || app_upstream_fault_i;
    wire request_fire=app_req_valid_o && app_req_ready_i;
    wire credit_fire=credit_m_valid && credit_m_ready;
    wire legal_return=app_rsp_valid_i && inflight_q!=0 && !app_dead;
    wire core_delivery=rsp_m_valid && rsp_m_ready;

    assign core_req_ready_o=req_s_ready && !core_dead;
    assign app_req_valid_o=req_m_valid && reserved_q<32 && !app_dead;
    assign req_m_ready=app_req_ready_i && reserved_q<32 && !app_dead;
    assign rsp_m_ready=credit_s_ready && !core_dead;
    assign core_rsp_valid_o=core_delivery;
    assign core_rsp_data_o=response_payload[255:0];
    assign core_rsp_error_o=response_payload[256];
    assign credit_m_ready=reserved_q!=0 && !app_dead;
    assign core_fault_o=core_dead;
    assign app_fault_o=app_dead;

    // Reserve/return credits and all fault gates are unchanged. The request
    // pointer selects its owned row from registered state; downstream readiness
    // no longer selects a different distributed-memory address in this cycle.
    // A consumed request leaves one app-cycle bubble, never an extra owner slot.
    board1_async_fifo_gray #(.WIDTH(19),.ADDR_BITS(6),
        .DESTINATION_LOOKAHEAD(0)) u_requests (
        .f_observe_slot_i(f_slot),
        .f_source_take_o(f_req_s),
        .f_destination_take_o(f_req_d),
        .f_write_sequence_o(f_req_wseq),
        .f_read_sequence_o(f_req_rseq),
        .f_used_o(f_req_used),
        .f_write_sync2_o(f_req_ws2),
        .f_read_sync2_o(f_req_rs2),
        .f_point_source_sequence_o(f_req_point_seq),
        .f_point_payload_o(f_req_point_data),
        .f_point_written_o(f_req_point_seen),
        .f_write_sync1_o(f_req_ws1),
        .f_read_sync1_o(f_req_rs1),
        .f_native_full_o(f_req_full),
        .f_stalled_o(f_req_stalled),

        .s_clk_i(core_clk_i),.s_reset_n_i(core_reset_n_i),
        .s_valid_i(core_req_valid_i && !core_dead),.s_ready_o(req_s_ready),.s_data_i(core_req_word_i),
        .s_abort_i(core_dead),.s_full_o(),.s_empty_o(),.s_protocol_fault_o(req_s_fault),
        .m_clk_i(app_clk_i),.m_reset_n_i(app_reset_n_i),.m_valid_o(req_m_valid),
        .m_ready_i(req_m_ready),.m_data_o(app_req_word_o),.m_empty_o(),.m_protocol_fault_o(req_m_fault));
    board1_async_fifo_gray #(.WIDTH(257),.ADDR_BITS(6)) u_responses (
        .f_observe_slot_i(f_slot),
        .f_source_take_o(f_rsp_s),
        .f_destination_take_o(f_rsp_d),
        .f_write_sequence_o(f_rsp_wseq),
        .f_read_sequence_o(f_rsp_rseq),
        .f_used_o(f_rsp_used),
        .f_write_sync2_o(f_rsp_ws2),
        .f_read_sync2_o(f_rsp_rs2),
        .f_point_source_sequence_o(f_rsp_point_seq),
        .f_point_payload_o(f_rsp_point_data),
        .f_point_written_o(f_rsp_point_seen),
        .f_write_sync1_o(f_rsp_ws1),
        .f_read_sync1_o(f_rsp_rs1),
        .f_native_full_o(f_rsp_full),
        .f_stalled_o(f_rsp_stalled),

        .s_clk_i(app_clk_i),.s_reset_n_i(app_reset_n_i),
        .s_valid_i(legal_return),.s_ready_o(rsp_s_ready),.s_data_i({app_rsp_error_i,app_rsp_data_i}),
        .s_abort_i(app_dead),.s_full_o(),.s_empty_o(),.s_protocol_fault_o(rsp_s_fault),
        .m_clk_i(core_clk_i),.m_reset_n_i(core_reset_n_i),.m_valid_o(rsp_m_valid),
        .m_ready_i(rsp_m_ready),.m_data_o(response_payload),.m_empty_o(),.m_protocol_fault_o(rsp_m_fault));
    board1_async_fifo_gray #(.WIDTH(1),.ADDR_BITS(6)) u_credits (
        .f_observe_slot_i(f_slot),
        .f_source_take_o(f_credit_s),
        .f_destination_take_o(f_credit_d),
        .f_write_sequence_o(f_credit_wseq),
        .f_read_sequence_o(f_credit_rseq),
        .f_used_o(f_credit_used),
        .f_write_sync2_o(f_credit_ws2),
        .f_read_sync2_o(f_credit_rs2),
        .f_point_source_sequence_o(f_credit_point_seq),
        .f_point_payload_o(f_credit_point_data),
        .f_point_written_o(f_credit_point_seen),
        .f_write_sync1_o(f_credit_ws1),
        .f_read_sync1_o(f_credit_rs1),
        .f_native_full_o(f_credit_full),
        .f_stalled_o(f_credit_stalled),

        .s_clk_i(core_clk_i),.s_reset_n_i(core_reset_n_i),
        .s_valid_i(core_delivery),.s_ready_o(credit_s_ready),.s_data_i(1'b1),
        .s_abort_i(core_dead),.s_full_o(),.s_empty_o(),.s_protocol_fault_o(credit_s_fault),
        .m_clk_i(app_clk_i),.m_reset_n_i(app_reset_n_i),.m_valid_o(credit_m_valid),
        .m_ready_i(credit_m_ready),.m_data_o(),.m_empty_o(),.m_protocol_fault_o(credit_m_fault));

    always_ff @(posedge core_clk_i or negedge core_reset_n_i) begin
        if(!core_reset_n_i) begin
            app_fault_meta_q<=0;app_fault_sync_q<=0;core_fault_q<=0;
        end else begin
            app_fault_meta_q<=app_fault_o;app_fault_sync_q<=app_fault_meta_q;
            if(core_upstream_fault_i || app_fault_sync_q || req_s_fault || rsp_m_fault || credit_s_fault)
                core_fault_q<=1;
        end
    end
    always_ff @(posedge app_clk_i or negedge app_reset_n_i) begin
        if(!app_reset_n_i) begin
            core_fault_meta_q<=0;core_fault_sync_q<=0;app_fault_q<=0;reserved_q<=0;inflight_q<=0;
        end else begin
            core_fault_meta_q<=core_fault_o;core_fault_sync_q<=core_fault_meta_q;
            if(app_upstream_fault_i || core_fault_sync_q || req_m_fault || rsp_s_fault || credit_m_fault ||
               (app_rsp_valid_i && (inflight_q==0 || !rsp_s_ready || app_rsp_error_i)) ||
               (credit_m_valid && reserved_q==0)) app_fault_q<=1;
            if(!app_dead) case({request_fire,credit_fire})
                2'b10:reserved_q<=reserved_q+6'd1;
                2'b01:reserved_q<=reserved_q-6'd1;
                default: ;
            endcase
            if(!app_dead) case({request_fire,legal_return})
                2'b10:inflight_q<=inflight_q+6'd1;
                2'b01:inflight_q<=inflight_q-6'd1;
                default: ;
            endcase
        end
    end
`ifdef FORMAL
    always_ff @(posedge app_clk_i) if(app_reset_n_i) begin
        assert(reserved_q<=32);
        assert(inflight_q<=reserved_q);
        if(legal_return) assert(rsp_s_ready);
        if(app_fault_o) assert(!app_req_valid_o);
    end
    always_ff @(posedge core_clk_i) if(core_reset_n_i && core_fault_o)
        assert(!core_req_ready_o && !core_rsp_valid_o);
`endif
    (* anyconst *) reg[5:0]f_slot;
    (* anyconst *) reg[18:0]f_target;
    (* anyconst *) reg[255:0]f_model_word;
    reg[7:0]f_A,f_I,f_R,f_D,f_C;
    reg[18:0]f_addresses[0:127];
    reg f_req_seen,f_app_seen;
    reg[7:0]f_req_seq,f_app_seq,f_rsp_seq;
    reg[18:0]f_req_word,f_app_word;
    reg[256:0]f_rsp_payload;
    wire f_source=core_reset_n_i && core_req_valid_i && core_req_ready_o;
    wire f_issue=app_reset_n_i && request_fire;
    wire f_capture=app_reset_n_i && legal_return;
    wire f_delivery=core_reset_n_i && core_delivery;
    wire[7:0]f_queued=f_A-f_I;
    wire[7:0]f_waiting=f_I-f_R;
    wire[7:0]f_buffered=f_R-f_D;
    wire[7:0]f_credited=f_D-f_C;
    wire[7:0]f_reserved=f_I-f_C;
    wire[7:0]f_app_pending=f_I-f_D;
    wire[7:0]f_pending=f_A-f_D;
    wire[5:0]f_req_offset=f_slot-f_I[5:0];
    wire[5:0]f_rsp_offset=f_slot-f_D[5:0];
    wire f_req_live={2'd0,f_req_offset}<f_queued;
    wire f_app_live={2'd0,f_rsp_offset}<f_app_pending;
    wire f_rsp_live={2'd0,f_rsp_offset}<f_buffered;
    wire[7:0]f_req_age=f_A-f_req_seq;
    wire[7:0]f_app_age=f_A-f_app_seq;
    always @(posedge core_clk_i)if(f_source)f_addresses[f_A[6:0]]<=core_req_word_i;
    always @(posedge core_clk_i or negedge core_reset_n_i)begin
        if(!core_reset_n_i)begin f_A<=0;f_D<=0;f_req_seen<=0;end
        else begin
            if(f_source)begin
                f_A<=f_A+1'b1;
                if(f_A[5:0]==f_slot)begin f_req_seen<=1;f_req_seq<=f_A;f_req_word<=core_req_word_i;end
            end
            if(f_delivery)f_D<=f_D+1'b1;
        end
    end
    always @(posedge app_clk_i or negedge app_reset_n_i)begin
        if(!app_reset_n_i)begin f_I<=0;f_R<=0;f_C<=0;f_app_seen<=0;end
        else begin
            if(f_issue)begin
                f_I<=f_I+1'b1;
                if(f_I[5:0]==f_slot)begin f_app_seen<=1;f_app_seq<=f_I;f_app_word<=app_req_word_o;end
            end
            if(f_capture)begin
                f_R<=f_R+1'b1;
                if(f_R[5:0]==f_slot)begin f_rsp_seq<=f_R;f_rsp_payload<={app_rsp_error_i,app_rsp_data_i};end
            end
            if(credit_fire)f_C<=f_C+1'b1;
        end
    end
    // Normalized shared service contract. The accepted app request's ACTUAL
    // address is recorded above. Request-FIFO provenance must link it to the
    // core source; it is not assumed to be the desired source address.
    always @(posedge app_clk_i)if(app_reset_n_i && legal_return && !app_rsp_error_i)begin
        assume(f_waiting!=0);
        if(f_R[5:0]==f_slot && f_app_word==f_target)assume(app_rsp_data_i==f_model_word);
    end
    always @*begin
        assert(f_req_wseq==f_A[6:0]);assert(f_req_rseq==f_I[6:0]);
        assert(f_rsp_wseq==f_R[6:0]);assert(f_rsp_rseq==f_D[6:0]);
        assert(f_credit_wseq==f_D[6:0]);assert(f_credit_rseq==f_C[6:0]);
        assert(f_queued=={1'b0,f_req_used});assert(f_queued<=8'd64);
        assert(f_buffered=={1'b0,f_rsp_used});assert(f_buffered<=8'd32);
        assert(f_credited=={1'b0,f_credit_used});assert(f_credited<=8'd32);
        assert(f_reserved=={2'd0,reserved_q});assert(f_reserved<=8'd32);
        assert(f_waiting=={2'd0,inflight_q});assert(f_waiting<=f_reserved);
        assert(f_app_pending<=8'd32);assert(f_pending<=8'd96);
        assert(f_rsp_rs2==f_credit_ws2);
        assert(f_rsp_rs1==f_credit_ws1);
        assert(!f_rsp_full && !rsp_s_fault && !f_rsp_stalled);
        assert(!credit_s_fault && !f_credit_stalled);
        if(legal_return)assert(rsp_s_ready);
        assert(f_req_point_seen==f_req_seen);
        if(f_req_seen)begin
            assert(f_req_seq[5:0]==f_slot);
            assert(f_req_point_seq==f_req_seq[6:0]);assert(f_req_point_data==f_req_word);
            assert(f_req_age!=0 && f_req_age<=8'd64);
            assert(f_req_word==f_addresses[f_req_seq[6:0]]);
        end
        if(f_req_live)begin assert(f_req_seen);assert(f_req_seq==f_I+{2'd0,f_req_offset});end
        if(f_issue && f_I[5:0]==f_slot)begin
            assert(f_req_seq==f_I);assert(app_req_word_o==f_req_word);
            assert(app_req_word_o==f_addresses[f_I[6:0]]);
        end
        if(f_app_live)begin
            assert(f_app_seq[5:0]==f_slot);
            assert(f_app_seen);assert(f_app_seq==f_D+{2'd0,f_rsp_offset});
            assert(f_app_word==f_addresses[f_app_seq[6:0]]);
            assert(f_app_age!=0 && f_app_age<=8'd96);
        end
        if(f_rsp_live)begin
            assert(f_app_live);assert(f_rsp_seq==f_app_seq);
            assert(f_rsp_point_seq==f_rsp_seq[6:0]);assert(f_rsp_point_data==f_rsp_payload);
            if(!f_rsp_payload[256] && f_app_word==f_target)assert(f_rsp_payload[255:0]==f_model_word);
        end
        if(f_delivery && f_D[5:0]==f_slot)begin
            assert(f_rsp_live);assert(f_app_seq==f_D);
            assert(core_rsp_data_o==f_rsp_payload[255:0]);assert(core_rsp_error_o==f_rsp_payload[256]);
            if(!core_rsp_error_o && f_app_word==f_target)assert(core_rsp_data_o==f_model_word);
        end
    end
    always @(posedge app_clk_i)if(f_capture && f_R[5:0]==f_slot)begin
        assert(f_app_live);assert(f_app_seq==f_R);
    end

endmodule
module board1_current_model_path(
    input wire core_clk_i,reset_n_i,core_fault_to_boundary_q,
    input wire private_raw_req_valid_o, input wire[18:0]private_raw_req_word_o,
    output wire private_raw_req_ready_i,private_raw_rsp_valid_i,private_raw_rsp_error_i,
    output wire[255:0]private_raw_rsp_data_i,
    input wire private_endpoint_upstream_fault_i,shared_app_fault,model_app_req_ready,
    output wire model_app_req_valid,output wire[18:0]model_app_req_word,
    input wire model_app_rsp_valid,model_app_rsp_error,input wire[255:0]model_app_rsp_data,
    output wire model_cdc_core_fault,model_cdc_app_fault);
    wire app_clk_i=core_clk_i;
    (* async_reg="true",syn_preserve=1 *) logic [2:0] app_runtime_release_q;
    always_ff @(posedge app_clk_i or negedge reset_n_i) begin
        if(!reset_n_i) app_runtime_release_q<=0;
        else app_runtime_release_q<={app_runtime_release_q[1:0],1'b1};
    end
    wire app_runtime_reset_n=app_runtime_release_q[2];
    board1_private_model_ddr_cdc u_model_cdc (
        .core_clk_i(core_clk_i),.core_reset_n_i(reset_n_i),.core_upstream_fault_i(core_fault_to_boundary_q),
        .core_req_valid_i(private_raw_req_valid_o),.core_req_ready_o(private_raw_req_ready_i),
        .core_req_word_i(private_raw_req_word_o),.core_rsp_valid_o(private_raw_rsp_valid_i),
        .core_rsp_data_o(private_raw_rsp_data_i),.core_rsp_error_o(private_raw_rsp_error_i),
        .core_fault_o(model_cdc_core_fault),.app_clk_i(app_clk_i),.app_reset_n_i(app_runtime_reset_n),
        .app_upstream_fault_i(private_endpoint_upstream_fault_i || shared_app_fault),
        .app_req_valid_o(model_app_req_valid),.app_req_ready_i(model_app_req_ready),
        .app_req_word_o(model_app_req_word),.app_rsp_valid_i(model_app_rsp_valid),
        .app_rsp_data_i(model_app_rsp_data),.app_rsp_error_i(model_app_rsp_error),.app_fault_o(model_cdc_app_fault));
    always @*assert(app_runtime_release_q==0 || app_runtime_release_q==1 || app_runtime_release_q==3 || app_runtime_release_q==7);
endmodule
