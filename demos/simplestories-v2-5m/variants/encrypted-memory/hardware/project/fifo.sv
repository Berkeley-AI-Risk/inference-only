`timescale 1ns/1ps
`default_nettype none

// Reusable one-way asynchronous ready/valid FIFO.  Only Gray-coded pointers
// cross clock domains; payload storage is written in the source domain and
// sampled in the destination domain after the synchronized write pointer has
// made the entry visible.  DEPTH is exactly 2**ADDR_BITS.
module board1_async_fifo_gray #(
    parameter integer WIDTH = 8,
    parameter integer ADDR_BITS = 4,
    /* verilator lint_off UNUSEDPARAM */
    parameter RAM_STYLE = "distributed",
    /* verilator lint_on UNUSEDPARAM */
    parameter integer DESTINATION_LOOKAHEAD = 1
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
    output wire                 m_protocol_fault_o
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
            (DESTINATION_LOOKAHEAD != 0 && DESTINATION_LOOKAHEAD != 1))
            $fatal(1, "board1_async_fifo_gray requires WIDTH>=1 ADDR_BITS>=2 lookahead=0|1");
    end

    // Pointer synchronizers.  Reset assertion is asynchronous in each domain;
    // the product wrapper supplies independently synchronized release.
    always_ff @(posedge s_clk_i or negedge s_reset_n_i) begin
        if (!s_reset_n_i) begin
            read_gray_sync1_q <= {PTR_W{1'b0}};
            read_gray_sync2_q <= {PTR_W{1'b0}};
        end else begin
            read_gray_sync1_q <= read_gray_q;
            read_gray_sync2_q <= read_gray_sync1_q;
        end
    end

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
endmodule

`default_nettype wire

`timescale 1ns/1ps
`default_nettype none

// Reusable one-way asynchronous ready/valid FIFO.  Only Gray-coded pointers
// cross clock domains; payload storage is written in the source domain and
// sampled in the destination domain after the synchronized write pointer has
// made the entry visible.  DEPTH is exactly 2**ADDR_BITS.
module board1_async_fifo_gray_block #(
    parameter integer WIDTH = 8,
    parameter integer ADDR_BITS = 4,
    /* verilator lint_off UNUSEDPARAM */
    parameter RAM_STYLE = "distributed",
    /* verilator lint_on UNUSEDPARAM */
    parameter integer DESTINATION_LOOKAHEAD = 1
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
    output wire                 m_protocol_fault_o
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

    logic [WIDTH-1:0] memory_q [0:DEPTH-1] /* synthesis syn_ramstyle = "block_ram" */;

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

    logic [WIDTH-1:0] m_data_q;
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
            (DESTINATION_LOOKAHEAD != 0 && DESTINATION_LOOKAHEAD != 1))
            $fatal(1, "board1_async_fifo_gray requires WIDTH>=1 ADDR_BITS>=2 lookahead=0|1");
    end

    // Pointer synchronizers.  Reset assertion is asynchronous in each domain;
    // the product wrapper supplies independently synchronized release.
    always_ff @(posedge s_clk_i or negedge s_reset_n_i) begin
        if (!s_reset_n_i) begin
            read_gray_sync1_q <= {PTR_W{1'b0}};
            read_gray_sync2_q <= {PTR_W{1'b0}};
        end else begin
            read_gray_sync1_q <= read_gray_q;
            read_gray_sync2_q <= read_gray_sync1_q;
        end
    end

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
endmodule

`default_nettype wire
