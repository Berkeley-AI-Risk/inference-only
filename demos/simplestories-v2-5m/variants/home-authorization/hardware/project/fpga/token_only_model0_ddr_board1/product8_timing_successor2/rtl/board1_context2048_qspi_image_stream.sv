`timescale 1ns/1ps
`default_nettype none

// Fixed, private, read-only semantic-image transport.  It performs exactly
// one legacy 0x03 read of [0x801000,0xEEEEC0), packs consecutive bytes into
// 227,062 little-endian 256-bit loader words, and has no content-auth claim.
// Product authorization occurs only after complete DDR readback SHA-256.
module board1_context2048_qspi_image_stream #(
    parameter integer SLOW_WATCHDOG_CYCLES = 25_000_000
) (
    input  wire         trusted_clk_i,
    input  wire         trusted_reset_n_i,
    input  wire         app_clk_i,
    input  wire         app_reset_n_i,

    output wire         fixed_source_ready_o,
    output wire         boot_progress_o,
    output wire [255:0] loader_data_o,
    output wire         loader_valid_o,
    input  wire         loader_ready_i,
    output wire         loader_done_o,
    output wire         fail_closed_o,

    output wire         qspi_cs_n_o,
    output wire         qspi_sck_o,
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [3:0]   qspi_dq_i,
    /* verilator lint_on UNUSEDSIGNAL */
    output wire [3:0]   qspi_dq_o,
    output wire [3:0]   qspi_dq_oe_o
);
    localparam logic [23:0] IMAGE_BASE = 24'h801000;
    localparam logic [23:0] IMAGE_BYTES = 24'd7265984;
    localparam logic [17:0] IMAGE_WORDS = 18'd227062;
    localparam logic [17:0] IMAGE_LAST_WORD = IMAGE_WORDS - 1'b1;
    localparam integer WATCHDOG_W = $clog2(SLOW_WATCHDOG_CYCLES + 1);
    localparam logic [WATCHDOG_W-1:0] WATCHDOG_LAST =
        WATCHDOG_W'(SLOW_WATCHDOG_CYCLES - 1);

    typedef enum logic [2:0] {
        ST_WAIT_APP = 3'd0,
        ST_START    = 3'd1,
        ST_STREAM   = 3'd2,
        ST_DONE     = 3'd3,
        ST_FAIL     = 3'd7
    } state_t;

    state_t state_q;
    logic [4:0] byte_q;
    logic [17:0] word_q;
    logic [247:0] word_buffer_q;
    logic qspi_start_q;
    logic source_ready_slow_q;
    logic progress_toggle_slow_q;
    logic slow_fault_q;
    logic [WATCHDOG_W-1:0] watchdog_q;

    wire qspi_busy;
    wire qspi_fault;
    wire qspi_data_valid;
    wire qspi_data_ready;
    wire [7:0] qspi_data;
    wire qspi_data_last;
    wire qspi_transfer = qspi_data_valid && qspi_data_ready;

    wire fifo_write_ready;
    wire fifo_write_valid = state_q == ST_STREAM && qspi_data_valid &&
                            byte_q == 5'd31;
    wire [255:0] fifo_write_data = {qspi_data, word_buffer_q};
    wire [255:0] fifo_read_data;
    wire fifo_read_valid;
    wire fifo_read_ready;
    wire fifo_write_transfer = fifo_write_valid && fifo_write_ready;
    // Registered, non-fallthrough application-domain owner.  QSPI supplies a
    // 256-bit word only once per many trusted clocks, so the deliberate
    // one-cycle refill bubble has no throughput cost.  More importantly,
    // loader_ready_i (which includes DDR calibration/policy) can no longer
    // select the asynchronous FIFO RAM address in the same 100 MHz cycle.
    (* keep = "true", syn_preserve = 1 *) logic loader_skid_valid_q;
    (* syn_preserve = 1 *) logic [255:0] loader_skid_data_q;

    (* async_reg = "true", syn_preserve = 1 *) logic app_up_slow_sync1_q;
    (* async_reg = "true", syn_preserve = 1 *) logic app_up_slow_sync2_q;
    (* async_reg = "true", syn_preserve = 1 *) logic app_fault_slow_sync1_q;
    (* async_reg = "true", syn_preserve = 1 *) logic app_fault_slow_sync2_q;
    (* async_reg = "true", syn_preserve = 1 *) logic source_ready_sync1_q;
    (* async_reg = "true", syn_preserve = 1 *) logic source_ready_sync2_q;
    (* async_reg = "true", syn_preserve = 1 *) logic progress_sync1_q;
    (* async_reg = "true", syn_preserve = 1 *) logic progress_sync2_q;
    (* async_reg = "true", syn_preserve = 1 *) logic slow_fault_sync1_q;
    (* async_reg = "true", syn_preserve = 1 *) logic slow_fault_sync2_q;
    logic progress_seen_q;
    logic app_fault_q;
    logic app_started_q;
    logic [17:0] app_word_q;
    logic loader_done_q;

    wire slow_progress = qspi_start_q || qspi_transfer || fifo_write_transfer;
    wire watchdog_active = state_q != ST_DONE && state_q != ST_FAIL;
    wire watchdog_trip = watchdog_active && !slow_progress &&
                         watchdog_q == WATCHDOG_LAST;
    wire qspi_idle_protocol_fault = state_q == ST_STREAM &&
        !qspi_busy && !qspi_start_q && !qspi_data_valid;
    wire internal_reset_n = trusted_reset_n_i && !slow_fault_q &&
                            !app_fault_slow_sync2_q;

`ifndef SYNTHESIS
    logic slow_x_fault;
    logic app_x_fault;
    always_comb begin
        slow_x_fault = $isunknown(qspi_busy) || $isunknown(qspi_fault) ||
                       $isunknown(qspi_data_valid) ||
                       $isunknown(fifo_write_ready);
        if (qspi_data_valid === 1'b1)
            slow_x_fault = slow_x_fault || $isunknown(qspi_data) ||
                           $isunknown(qspi_data_last);
        app_x_fault = $isunknown(loader_ready_i) ||
                      $isunknown(fifo_read_valid) ||
                      $isunknown(loader_skid_valid_q) ||
                      $isunknown(source_ready_sync2_q) ||
                      $isunknown(slow_fault_sync2_q);
        if (fifo_read_valid === 1'b1)
            app_x_fault = app_x_fault || $isunknown(fifo_read_data);
        if (loader_skid_valid_q === 1'b1)
            app_x_fault = app_x_fault || $isunknown(loader_skid_data_q);
    end
`else
    wire slow_x_fault = 1'b0;
    wire app_x_fault = 1'b0;
`endif

    wire immediate_fail = app_fault_q || slow_fault_sync2_q || app_x_fault;
    wire fifo_read_transfer = fifo_read_valid && fifo_read_ready;
    wire loader_transfer = loader_skid_valid_q &&
                           (loader_ready_i === 1'b1) &&
                           source_ready_sync2_q &&
                           !immediate_fail && !loader_done_q;

    assign qspi_data_ready = (state_q == ST_STREAM) &&
        ((byte_q != 5'd31) || fifo_write_ready);

    board1_context2048_qspi_read03_master u_fixed_read (
        .clk_i(trusted_clk_i),
        .reset_n_i(internal_reset_n),
        .start_i(qspi_start_q),
        .busy_o(qspi_busy),
        .fault_o(qspi_fault),
        .data_valid_o(qspi_data_valid),
        .data_ready_i(qspi_data_ready),
        .data_o(qspi_data),
        .data_last_o(qspi_data_last),
        .qspi_cs_n_o(qspi_cs_n_o),
        .qspi_sck_o(qspi_sck_o),
        .qspi_dq1_i(qspi_dq_i[1]),
        .qspi_dq_o(qspi_dq_o),
        .qspi_dq_oe_o(qspi_dq_oe_o)
    );

    board1_qspi_async_word_fifo4 u_loader_cdc (
        .write_clk_i(trusted_clk_i),
        .write_reset_n_i(trusted_reset_n_i),
        .write_data_i(fifo_write_data),
        .write_valid_i(fifo_write_valid && !slow_fault_q),
        .write_ready_o(fifo_write_ready),
        .read_clk_i(app_clk_i),
        .read_reset_n_i(app_reset_n_i),
        .read_data_o(fifo_read_data),
        .read_valid_o(fifo_read_valid),
        .read_ready_i(fifo_read_ready)
    );

    always_ff @(posedge trusted_clk_i or negedge app_reset_n_i) begin
        if (!app_reset_n_i) begin
            app_up_slow_sync1_q <= 1'b0;
            app_up_slow_sync2_q <= 1'b0;
        end else begin
            app_up_slow_sync1_q <= 1'b1;
            app_up_slow_sync2_q <= app_up_slow_sync1_q;
        end
    end

    always_ff @(posedge trusted_clk_i or negedge trusted_reset_n_i) begin
        if (!trusted_reset_n_i) begin
            state_q <= ST_WAIT_APP;
            byte_q <= 5'd0;
            word_q <= 18'd0;
            word_buffer_q <= 248'd0;
            qspi_start_q <= 1'b0;
            source_ready_slow_q <= 1'b0;
            progress_toggle_slow_q <= 1'b0;
            slow_fault_q <= 1'b0;
            watchdog_q <= '0;
            app_fault_slow_sync1_q <= 1'b0;
            app_fault_slow_sync2_q <= 1'b0;
        end else begin
            qspi_start_q <= 1'b0;
            app_fault_slow_sync1_q <= app_fault_q;
            app_fault_slow_sync2_q <= app_fault_slow_sync1_q;
            if (!watchdog_active || slow_progress)
                watchdog_q <= '0;
            else if (watchdog_q != WATCHDOG_LAST)
                watchdog_q <= watchdog_q + 1'b1;

            if (qspi_fault || qspi_idle_protocol_fault || watchdog_trip ||
                slow_x_fault || app_fault_slow_sync2_q ||
                ((state_q != ST_WAIT_APP) && !app_up_slow_sync2_q)) begin
                state_q <= ST_FAIL;
                source_ready_slow_q <= 1'b0;
                slow_fault_q <= 1'b1;
            end else begin
                case (state_q)
                    ST_WAIT_APP: if (app_up_slow_sync2_q)
                        state_q <= ST_START;
                    ST_START: begin
                        byte_q <= 5'd0;
                        word_q <= 18'd0;
                        word_buffer_q <= 248'd0;
                        source_ready_slow_q <= 1'b1;
                        qspi_start_q <= 1'b1;
                        state_q <= ST_STREAM;
                    end
                    ST_STREAM: if (qspi_transfer) begin
                        progress_toggle_slow_q <= ~progress_toggle_slow_q;
                        if (qspi_data_last !=
                            ((word_q == IMAGE_LAST_WORD) &&
                             (byte_q == 5'd31))) begin
                            state_q <= ST_FAIL;
                            source_ready_slow_q <= 1'b0;
                            slow_fault_q <= 1'b1;
                        end else if (byte_q == 5'd31) begin
                            byte_q <= 5'd0;
                            word_buffer_q <= 248'd0;
                            if (qspi_data_last)
                                state_q <= ST_DONE;
                            else
                                word_q <= word_q + 1'b1;
                        end else begin
                            word_buffer_q[byte_q*8 +: 8] <= qspi_data;
                            byte_q <= byte_q + 1'b1;
                        end
                    end
                    ST_DONE: state_q <= ST_DONE;
                    default: begin
                        state_q <= ST_FAIL;
                        source_ready_slow_q <= 1'b0;
                        slow_fault_q <= 1'b1;
                    end
                endcase
            end
        end
    end

    // Related trusted/app clocks: keep all first status stages off the
    // trusted rising edge. Second-stage/status consumers still use posedge.
    always_ff @(negedge app_clk_i or negedge app_reset_n_i) begin
        if (!app_reset_n_i) begin
            source_ready_sync1_q <= 1'b0;
            progress_sync1_q <= 1'b0;
            slow_fault_sync1_q <= 1'b0;
        end else begin
            source_ready_sync1_q <= source_ready_slow_q;
            progress_sync1_q <= progress_toggle_slow_q;
            slow_fault_sync1_q <= slow_fault_q;
        end
    end

    always_ff @(posedge app_clk_i or negedge app_reset_n_i) begin
        if (!app_reset_n_i) begin
            source_ready_sync2_q <= 1'b0;
            progress_sync2_q <= 1'b0;
            progress_seen_q <= 1'b0;
            slow_fault_sync2_q <= 1'b0;
            app_fault_q <= 1'b0;
            app_started_q <= 1'b0;
            app_word_q <= 18'd0;
            loader_done_q <= 1'b0;
            loader_skid_valid_q <= 1'b0;
            loader_skid_data_q <= 256'd0;
        end else begin
            source_ready_sync2_q <= source_ready_sync1_q;
            progress_sync2_q <= progress_sync1_q;
            progress_seen_q <= progress_sync2_q;
            slow_fault_sync2_q <= slow_fault_sync1_q;
            if (source_ready_sync2_q)
                app_started_q <= 1'b1;
            // A unilateral trusted-domain reset or disappearance after boot
            // has started is terminal.  Correlated reset clears app_started_q
            // and permits a clean restart of the entire product.
            if (slow_fault_sync2_q || app_x_fault ||
                (app_started_q && !source_ready_sync2_q && !loader_done_q))
                app_fault_q <= 1'b1;
            // The FIFO owns data until this register accepts it.  The skid
            // register then owns the word until the fixed loader accepts it;
            // there is no combinational ready path across both interfaces.
            if (immediate_fail || loader_done_q) begin
                loader_skid_valid_q <= 1'b0;
            end else begin
                if (loader_transfer)
                    loader_skid_valid_q <= 1'b0;
                if (fifo_read_transfer) begin
                    loader_skid_valid_q <= 1'b1;
                    loader_skid_data_q <= fifo_read_data;
                end
            end
            if (loader_transfer) begin
                if (app_word_q == IMAGE_LAST_WORD)
                    loader_done_q <= 1'b1;
                else
                    app_word_q <= app_word_q + 1'b1;
            end
        end
    end

    // Non-fallthrough is intentional: ready depends only on the registered
    // slot owner and local terminal status, never on loader_ready_i.
    assign fifo_read_ready = !loader_skid_valid_q &&
                             source_ready_sync2_q &&
                             !immediate_fail && !loader_done_q;
    assign fixed_source_ready_o = source_ready_sync2_q && !immediate_fail;
    assign boot_progress_o = (progress_sync2_q ^ progress_seen_q) &&
                             !immediate_fail;
    assign loader_data_o = loader_skid_data_q;
    assign loader_valid_o = loader_skid_valid_q && source_ready_sync2_q &&
                            !immediate_fail && !loader_done_q;
    assign loader_done_o = loader_done_q && !immediate_fail;
    assign fail_closed_o = immediate_fail;

    initial begin
        if (SLOW_WATCHDOG_CYCLES < 256 ||
            SLOW_WATCHDOG_CYCLES > 500_000_000 ||
            IMAGE_BASE != 24'h801000 || IMAGE_BYTES != 24'd7265984 ||
            IMAGE_WORDS != 18'd227062 ||
            IMAGE_BASE + IMAGE_BYTES != 24'd15658688)
            $fatal(1, "fixed QSPI image-stream policy differs");
    end

`ifdef FORMAL
    logic formal_app_past_valid_q;
    always_ff @(posedge trusted_clk_i) begin
        if (trusted_reset_n_i) begin
            assert (word_q <= IMAGE_LAST_WORD);
            if (slow_fault_q)
                assert (state_q == ST_FAIL);
        end
    end
    always_ff @(posedge app_clk_i) begin
        if (!app_reset_n_i) begin
            formal_app_past_valid_q <= 1'b0;
        end else begin
            formal_app_past_valid_q <= 1'b1;
            if (fail_closed_o) begin
                assert (!fixed_source_ready_o && !loader_valid_o &&
                        !loader_done_o && !boot_progress_o);
            end
            if (loader_done_o)
                assert (!loader_valid_o);
            assert (!(fifo_read_ready && loader_skid_valid_q));
            if (formal_app_past_valid_q &&
                $past(loader_valid_o && !loader_ready_i) &&
                !immediate_fail) begin
                assert (loader_valid_o);
                assert (loader_data_o == $past(loader_data_o));
            end
        end
    end
`endif
endmodule

`default_nettype wire
