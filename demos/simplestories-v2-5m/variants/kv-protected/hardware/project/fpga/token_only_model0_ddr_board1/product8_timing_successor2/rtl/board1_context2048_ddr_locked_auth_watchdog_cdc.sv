`timescale 1ns/1ps
`default_nettype none

// Product4's sole physical DDR/authentication composition. The complete
// ordered model readback crosses app100 -> trusted25 for one fixed digest.
// After LOCK the only runtime seam is the sealed 19-bit typed endpoint.
module board1_context2048_ddr_locked_auth_watchdog_cdc_quarantined_payload #(
    parameter integer WATCHDOG_CYCLES = 100_000_000
) (
    input  wire         trusted_clk_i,
    input  wire         trusted_reset_n_i,
    input  wire         app_clk_i,
    input  wire         app_reset_n_i,
    input  wire         private_fixed_source_ready_i,
    input  wire         private_boot_progress_i,
    input  wire         private_loader_done_i,
    input  wire [255:0] private_loader_data_i,
    input  wire         private_loader_valid_i,
    output wire         private_loader_ready_o,

    input  wire         private_runtime_req_valid_i,
    output wire         private_runtime_req_ready_o,
    input  wire [18:0]  private_runtime_req_word_address_i,
    input  wire         private_runtime_req_write_i,
    input  wire [255:0] private_runtime_req_write_data_i,
    output wire [255:0] private_runtime_rsp_data_o,
    output wire         private_runtime_rsp_valid_o,
    input  wire         private_runtime_rsp_ready_i,
    output wire         private_runtime_rsp_error_o,
    input  wire         private_runtime_endpoint_fail_closed_i,

    input  wire         controller_pll_lock_i,
    input  wire         controller_init_calib_complete_i,
    input  wire         app_cmd_ready_i,
    output wire [2:0]   app_cmd_o,
    output wire         app_cmd_en_o,
    output wire [28:0]  app_addr_o,
    input  wire         app_wr_data_ready_i,
    output wire [255:0] app_wr_data_o,
    output wire         app_wr_data_en_o,
    output wire         app_wr_data_end_o,
    output wire [31:0]  app_wr_data_mask_o,
    input  wire [255:0] app_rd_data_i,
    input  wire         app_rd_data_valid_i,
    input  wire         app_rd_data_end_i,
    output wire         app_burst_o,
    output wire         app_self_refresh_req_o,
    output wire         app_refresh_req_o,
    output wire         model_locked_o,
    output wire         fail_closed_o,
    output wire         watchdog_fault_o
);
    localparam integer MODEL_WORDS = 227062;
    localparam integer WATCHDOG_W = $clog2(WATCHDOG_CYCLES + 1);
    localparam logic [WATCHDOG_W-1:0] WATCHDOG_LAST =
        WATCHDOG_W'(WATCHDOG_CYCLES - 1);

    wire common_async_reset_n = trusted_reset_n_i && app_reset_n_i;
    /* verilator lint_off SYNCASYNCNET */
    (* async_reg = "true", syn_preserve = 1 *) logic [2:0] app_release_q;
    (* async_reg = "true", syn_preserve = 1 *) logic [2:0] trusted_release_q;
    /* verilator lint_on SYNCASYNCNET */
    always_ff @(posedge app_clk_i or negedge common_async_reset_n) begin
        if (!common_async_reset_n)
            app_release_q <= 3'b000;
        else
            app_release_q <= {app_release_q[1:0], 1'b1};
    end
    always_ff @(posedge trusted_clk_i or negedge common_async_reset_n) begin
        if (!common_async_reset_n)
            trusted_release_q <= 3'b000;
        else
            trusted_release_q <= {trusted_release_q[1:0], 1'b1};
    end
    wire app_domain_reset_n = app_release_q[2];
    wire trusted_domain_reset_n = trusted_release_q[2];

    logic app_fault_q;
    logic watchdog_fault_q;
    wire [WATCHDOG_W-1:0] watchdog_count_q;
    wire watchdog_at_limit;
    logic calibration_seen_q;
    logic fixed_source_seen_q;
    logic loader_done_seen_q;
    logic digest_done_seen_q;
    logic [17:0] loader_count_q;
    logic loader_final_seen_q;
    logic loader_protocol_fault_q;
    logic runtime_read_outstanding_q;

    wire boundary_loader_ready;
    wire [255:0] boundary_readback_data;
    wire boundary_readback_valid;
    wire boundary_readback_last;
    wire boundary_runtime_req_ready;
    wire [255:0] boundary_runtime_rsp_data;
    wire boundary_runtime_rsp_valid;
    wire boundary_runtime_rsp_error;
    wire [2:0] boundary_app_cmd;
    wire boundary_app_cmd_en;
    wire [28:0] boundary_app_addr;
    wire [255:0] boundary_app_wr_data;
    wire boundary_app_wr_data_en;
    wire boundary_app_wr_data_end;
    wire [31:0] boundary_app_wr_data_mask;
    wire boundary_app_burst;
    wire boundary_app_self_refresh_req;
    wire boundary_app_refresh_req;
    wire boundary_model_locked;
    wire boundary_fail_closed;
    wire boundary_raw_response_protocol_fault_now;

    wire readback_fifo_s_ready;
    wire readback_fifo_s_full;
    wire readback_fifo_s_empty;
    wire readback_fifo_s_fault;
    wire [256:0] readback_fifo_m_data;
    wire readback_fifo_m_valid;
    wire readback_fifo_m_ready;
    wire readback_fifo_m_empty;
    wire readback_fifo_m_fault;
    wire auth_readback_ready;
    wire auth_digest_done;
    wire auth_digest_ok;
    wire auth_fail_closed;

    logic digest_success_trusted_q;
    logic digest_failure_trusted_q;
    (* async_reg = "true", syn_preserve = 1 *) logic digest_success_sync1_q;
    (* async_reg = "true", syn_preserve = 1 *) logic digest_success_sync2_q;
    (* async_reg = "true", syn_preserve = 1 *) logic digest_failure_sync1_q;
    (* async_reg = "true", syn_preserve = 1 *) logic digest_failure_sync2_q;

    wire digest_success_app = digest_success_sync2_q &&
                              !digest_failure_sync2_q;
    wire digest_failure_app = digest_failure_sync2_q;
    wire digest_done_app = digest_success_app || digest_failure_app;
    wire digest_ok_app = digest_success_app;
    wire endpoint_fail =
        private_runtime_endpoint_fail_closed_i === 1'b1;
    wire request_gate_open = !app_fault_q && !endpoint_fail;
    wire fixed_source_release =
        (private_fixed_source_ready_i === 1'b1) && request_gate_open;
    // This mirrors the frozen adapter's calibration-seen/controller-good
    // contract using the already-owned Product4 calibration_seen_q.  Unlike a
    // blanket !controller-good startup test, it becomes terminal only after a
    // good controller has once been observed.
    wire controller_known_good_now =
        (controller_pll_lock_i === 1'b1) &&
        (controller_init_calib_complete_i === 1'b1);
    wire controller_protocol_fault_now = calibration_seen_q &&
                                         !controller_known_good_now;

    wire loader_accept = private_loader_valid_i && boundary_loader_ready &&
                         request_gate_open;
    wire loader_accept_final = loader_accept &&
                               loader_count_q == 18'd227061;
    wire loader_count_overflow = loader_accept &&
                                 loader_count_q >= 18'd227062;
    wire loader_done_legal_now = loader_final_seen_q || loader_accept_final;
    wire loader_contract_violation_now =
        ((private_loader_valid_i === 1'b1) &&
         (private_fixed_source_ready_i !== 1'b1)) ||
        ((private_loader_done_i === 1'b1) && !loader_done_legal_now) ||
        (loader_final_seen_q && !loader_done_seen_q &&
         (private_loader_done_i !== 1'b1)) ||
        (loader_final_seen_q && (private_loader_valid_i === 1'b1)) ||
        (loader_done_seen_q && (private_loader_done_i !== 1'b1)) ||
        (fixed_source_seen_q && !loader_done_seen_q &&
         (private_fixed_source_ready_i !== 1'b1)) ||
        loader_count_overflow;

    wire runtime_request_accept = private_runtime_req_valid_i &&
                                  boundary_runtime_req_ready &&
                                  request_gate_open;
    wire runtime_read_accept = runtime_request_accept &&
                               (private_runtime_req_write_i === 1'b0);
    wire runtime_response_consume = boundary_runtime_rsp_valid &&
                                    private_runtime_rsp_ready_i;
    wire runtime_protocol_fault =
        (runtime_read_accept && runtime_read_outstanding_q &&
         !runtime_response_consume) ||
        (runtime_response_consume && !runtime_read_outstanding_q &&
         !runtime_read_accept);

    wire readback_fifo_push = boundary_readback_valid &&
                              readback_fifo_s_ready && request_gate_open;
    wire calibration_progress = !calibration_seen_q &&
        (controller_pll_lock_i === 1'b1) &&
        (controller_init_calib_complete_i === 1'b1);
    wire fixed_source_progress = !fixed_source_seen_q &&
        (private_fixed_source_ready_i === 1'b1);
    wire loader_done_progress = !loader_done_seen_q &&
        (private_loader_done_i === 1'b1);
    wire digest_progress = !digest_done_seen_q && digest_done_app;
    wire boot_progress = calibration_progress || fixed_source_progress ||
        ((private_boot_progress_i === 1'b1) && !loader_done_seen_q) ||
        loader_accept || loader_done_progress || readback_fifo_push ||
        digest_progress || boundary_model_locked;
    wire runtime_wait = boundary_model_locked &&
        !boundary_runtime_rsp_valid &&
        (runtime_read_outstanding_q ||
         (private_runtime_req_valid_i && !boundary_runtime_req_ready));
    wire watchdog_active = !boundary_model_locked || runtime_wait;
    wire watchdog_progress = boundary_model_locked ?
        (runtime_request_accept || runtime_response_consume ||
         boundary_runtime_rsp_valid) : boot_progress;
    wire watchdog_trip = watchdog_active && !watchdog_progress &&
                         watchdog_at_limit;
    board1_watchdog_counter_exact #(.CYCLES(WATCHDOG_CYCLES))
    u_watchdog_count (
        .clk_i(app_clk_i), .reset_n_i(app_domain_reset_n),
        .clear_i(app_fault_q || !watchdog_active || watchdog_progress),
        .count_o(watchdog_count_q), .at_limit_o(watchdog_at_limit)
    );

`ifndef SYNTHESIS
    logic simulation_x_fault;
    always_comb begin
        simulation_x_fault = $isunknown(private_fixed_source_ready_i) ||
            $isunknown(private_boot_progress_i) ||
            $isunknown(private_loader_done_i) ||
            $isunknown(private_loader_valid_i) ||
            $isunknown(private_runtime_req_valid_i) ||
            $isunknown(private_runtime_rsp_ready_i) ||
            $isunknown(private_runtime_endpoint_fail_closed_i) ||
            $isunknown(controller_pll_lock_i) ||
            $isunknown(controller_init_calib_complete_i) ||
            $isunknown(app_cmd_ready_i) ||
            $isunknown(app_wr_data_ready_i) ||
            $isunknown(app_rd_data_valid_i) ||
            $isunknown(app_rd_data_end_i) ||
            $isunknown(digest_success_sync2_q) ||
            $isunknown(digest_failure_sync2_q) ||
            $isunknown(readback_fifo_s_fault);
        if (private_loader_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                                 $isunknown(private_loader_data_i);
        if (private_runtime_req_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                $isunknown(private_runtime_req_word_address_i) ||
                $isunknown(private_runtime_req_write_i) ||
                ((private_runtime_req_write_i === 1'b1) &&
                 $isunknown(private_runtime_req_write_data_i));
        if (app_rd_data_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                                 $isunknown(app_rd_data_i);
    end
`else
    wire simulation_x_fault = 1'b0;
`endif

    // Terminal state visible to the typed endpoint is owned by app_fault_q.
    // Current-cycle terms may only remove final physical enables before that
    // registered owner captures them; keeping them out of this mux prevents a
    // combinational fault/ready/lock loop through the accepted typed boundary.
    // endpoint_fail is already registered in the app domain.
    wire output_fail = !app_domain_reset_n || app_fault_q || endpoint_fail;
    // Current-cycle internal faults may not be fed into model_locked_o or the
    // typed ready path (that would recreate a combinational fault loop), but
    // they can and do suppress the final physical controller enables.  Their
    // sticky public/private failure state is captured by app_fault_q at the
    // same edge.
    wire physical_suppress_now = output_fail || boundary_fail_closed ||
        boundary_raw_response_protocol_fault_now ||
        controller_protocol_fault_now || loader_contract_violation_now ||
        readback_fifo_s_fault || digest_failure_app ||
        loader_protocol_fault_q || runtime_protocol_fault || watchdog_trip ||
        simulation_x_fault;

    initial begin
        if (WATCHDOG_CYCLES < 256 || WATCHDOG_CYCLES > 1_000_000_000 ||
            MODEL_WORDS != 227062)
            $fatal(1, "Product4 watchdog/image policy differs");
    end

    always_ff @(posedge trusted_clk_i or negedge trusted_domain_reset_n) begin
        if (!trusted_domain_reset_n) begin
            digest_success_trusted_q <= 1'b0;
            digest_failure_trusted_q <= 1'b0;
        end else begin
            if (auth_digest_done && auth_digest_ok && !auth_fail_closed &&
                !readback_fifo_m_fault)
                digest_success_trusted_q <= 1'b1;
            if (auth_fail_closed || readback_fifo_m_fault ||
                (auth_digest_done && !auth_digest_ok)) begin
                digest_failure_trusted_q <= 1'b1;
                digest_success_trusted_q <= 1'b0;
            end
        end
    end

    always_ff @(posedge app_clk_i or negedge app_domain_reset_n) begin
        if (!app_domain_reset_n) begin
            digest_success_sync1_q <= 1'b0;
            digest_success_sync2_q <= 1'b0;
            digest_failure_sync1_q <= 1'b0;
            digest_failure_sync2_q <= 1'b0;
        end else begin
            digest_success_sync1_q <= digest_success_trusted_q;
            digest_success_sync2_q <= digest_success_sync1_q;
            digest_failure_sync1_q <= digest_failure_trusted_q;
            digest_failure_sync2_q <= digest_failure_sync1_q;
        end
    end

    always_ff @(posedge app_clk_i or negedge app_domain_reset_n) begin
        if (!app_domain_reset_n) begin
            app_fault_q <= 1'b0;
            watchdog_fault_q <= 1'b0;
            calibration_seen_q <= 1'b0;
            fixed_source_seen_q <= 1'b0;
            loader_done_seen_q <= 1'b0;
            digest_done_seen_q <= 1'b0;
            loader_count_q <= 18'd0;
            loader_final_seen_q <= 1'b0;
            loader_protocol_fault_q <= 1'b0;
            runtime_read_outstanding_q <= 1'b0;
        end else begin
            if (endpoint_fail || boundary_fail_closed ||
                readback_fifo_s_fault || digest_failure_app ||
                controller_protocol_fault_now ||
                loader_contract_violation_now || runtime_protocol_fault ||
                watchdog_trip || simulation_x_fault)
                app_fault_q <= 1'b1;
            if (loader_contract_violation_now)
                loader_protocol_fault_q <= 1'b1;
            if (watchdog_trip)
                watchdog_fault_q <= 1'b1;
            if (calibration_progress)
                calibration_seen_q <= 1'b1;
            if (fixed_source_progress)
                fixed_source_seen_q <= 1'b1;
            if (private_loader_done_i === 1'b1)
                loader_done_seen_q <= 1'b1;
            if (digest_done_app)
                digest_done_seen_q <= 1'b1;
            if (loader_accept) begin
                loader_count_q <= loader_count_q + 1'b1;
                if (loader_accept_final)
                    loader_final_seen_q <= 1'b1;
            end
            case ({runtime_read_accept, runtime_response_consume})
                2'b10: runtime_read_outstanding_q <= 1'b1;
                2'b01: runtime_read_outstanding_q <= 1'b0;
                default: begin
                end
            endcase
        end
    end

    board1_async_fifo_gray #(
        .WIDTH(257), .ADDR_BITS(2), .RAM_STYLE("distributed")
    ) u_readback_cdc (
        .s_clk_i(app_clk_i), .s_reset_n_i(app_domain_reset_n),
        .s_valid_i(boundary_readback_valid && request_gate_open),
        .s_ready_o(readback_fifo_s_ready),
        .s_data_i({boundary_readback_last, boundary_readback_data}),
        .s_abort_i(app_fault_q), .s_full_o(readback_fifo_s_full),
        .s_empty_o(readback_fifo_s_empty),
        .s_protocol_fault_o(readback_fifo_s_fault),
        .m_clk_i(trusted_clk_i), .m_reset_n_i(trusted_domain_reset_n),
        .m_valid_o(readback_fifo_m_valid),
        .m_ready_i(readback_fifo_m_ready),
        .m_data_o(readback_fifo_m_data),
        .m_empty_o(readback_fifo_m_empty),
        .m_protocol_fault_o(readback_fifo_m_fault)
    );

    assign readback_fifo_m_ready = auth_readback_ready &&
                                   !digest_failure_trusted_q;
    board1_context2048_semantic_image_auth_compact u_sole_readback_auth (
        .trusted_clk_i(trusted_clk_i),
        .trusted_reset_n_i(trusted_domain_reset_n),
        .readback_word_data_i(readback_fifo_m_data[255:0]),
        .readback_word_valid_i(readback_fifo_m_valid &&
                               !digest_failure_trusted_q),
        .readback_word_last_i(readback_fifo_m_data[256]),
        .readback_word_ready_o(auth_readback_ready),
        .digest_done_o(auth_digest_done), .digest_ok_o(auth_digest_ok),
        .fail_closed_o(auth_fail_closed)
    );

    board1_context2048_ddr_preboard_locked_boundary u_locked_boundary (
        .app_clk_i(app_clk_i), .app_reset_n_i(app_domain_reset_n),
        // Controller loss is captured by app_fault_q at this edge. Its raw
        // current-cycle form remains only in physical_suppress_now below, so
        // no controller-good combinational cone enters the accepted typed
        // boundary while the final DDR action enables remain fail-closed.
        .private_upstream_fault_i(app_fault_q || endpoint_fail),
        .private_fixed_source_done_i(fixed_source_release),
        .private_fixed_source_ok_i(fixed_source_release),
        .private_loader_data_i(private_loader_data_i),
        .private_loader_valid_i(private_loader_valid_i &&
                                request_gate_open),
        .private_loader_ready_o(boundary_loader_ready),
        .private_readback_word_data_o(boundary_readback_data),
        .private_readback_word_valid_o(boundary_readback_valid),
        .private_readback_word_last_o(boundary_readback_last),
        .private_readback_word_ready_i(readback_fifo_s_ready &&
                                       request_gate_open),
        .private_readback_digest_done_i(digest_done_app),
        .private_readback_digest_ok_i(digest_ok_app),
        .private_runtime_req_valid_i(private_runtime_req_valid_i &&
                                     request_gate_open),
        .private_runtime_req_ready_o(boundary_runtime_req_ready),
        .private_runtime_req_word_address_i(
            private_runtime_req_word_address_i),
        .private_runtime_req_write_i(private_runtime_req_write_i),
        .private_runtime_req_write_data_i(
            private_runtime_req_write_data_i),
        .private_runtime_rsp_data_o(boundary_runtime_rsp_data),
        .private_runtime_rsp_valid_o(boundary_runtime_rsp_valid),
        .private_runtime_rsp_ready_i(private_runtime_rsp_ready_i),
        .private_runtime_rsp_error_o(boundary_runtime_rsp_error),
        .controller_pll_lock_i(controller_pll_lock_i),
        .controller_init_calib_complete_i(
            controller_init_calib_complete_i),
        .app_cmd_ready_i(app_cmd_ready_i), .app_cmd_o(boundary_app_cmd),
        .app_cmd_en_o(boundary_app_cmd_en),
        .app_addr_o(boundary_app_addr),
        .app_wr_data_ready_i(app_wr_data_ready_i),
        .app_wr_data_o(boundary_app_wr_data),
        .app_wr_data_en_o(boundary_app_wr_data_en),
        .app_wr_data_end_o(boundary_app_wr_data_end),
        .app_wr_data_mask_o(boundary_app_wr_data_mask),
        .app_rd_data_i(app_rd_data_i),
        .app_rd_data_valid_i(app_rd_data_valid_i),
        .app_rd_data_end_i(app_rd_data_end_i),
        .app_burst_o(boundary_app_burst),
        .app_self_refresh_req_o(boundary_app_self_refresh_req),
        .app_refresh_req_o(boundary_app_refresh_req),
        .model_locked_o(boundary_model_locked),
        .fail_closed_o(boundary_fail_closed),
        .raw_response_protocol_fault_now_o(
            boundary_raw_response_protocol_fault_now)
    );

    assign private_loader_ready_o = boundary_loader_ready && !output_fail;
    assign private_runtime_req_ready_o = boundary_runtime_req_ready &&
                                         !output_fail;
    // Variant-specific private quarantine seam: only typed-return run4 may
    // consume this output. Data can be arbitrary on invalid/error responses;
    // scalar metadata owns validation and a registered scrub precedes use.
    assign private_runtime_rsp_data_o = boundary_runtime_rsp_data;
    // A response belonging to an already accepted read remains drainable on
    // terminal failure. This is the sole exception to command suppression.
    assign private_runtime_rsp_valid_o = boundary_runtime_rsp_valid;
    assign private_runtime_rsp_error_o = boundary_runtime_rsp_valid &&
        (boundary_runtime_rsp_error || output_fail);

    // The controller samples command/address only with app_cmd_en and samples
    // write payload/mask only with app_wr_data_en.  Therefore fail closed at
    // the physical action points rather than broadcasting one fault net into
    // 320 don't-care data bits.  This preserves same-cycle suppression while
    // removing the routed controller-good/address-to-wide-data critical path.
    assign app_cmd_o = boundary_app_cmd;
    assign app_cmd_en_o = boundary_app_cmd_en && !physical_suppress_now;
    assign app_addr_o = boundary_app_addr;
    assign app_wr_data_o = boundary_app_wr_data;
    assign app_wr_data_en_o = boundary_app_wr_data_en &&
                              !physical_suppress_now;
    assign app_wr_data_end_o = boundary_app_wr_data_end &&
                               !physical_suppress_now;
    assign app_wr_data_mask_o = boundary_app_wr_data_mask;
    assign app_burst_o = boundary_app_burst && !physical_suppress_now;
    assign app_self_refresh_req_o = boundary_app_self_refresh_req &&
                                    !physical_suppress_now;
    assign app_refresh_req_o = boundary_app_refresh_req &&
                               !physical_suppress_now;
    assign model_locked_o = boundary_model_locked && !output_fail;
    assign fail_closed_o = output_fail;
    assign watchdog_fault_o = watchdog_fault_q || watchdog_trip;

    wire _unused_fifo_status = readback_fifo_s_full ||
        readback_fifo_s_empty || readback_fifo_m_empty;

`ifdef FORMAL
    logic formal_app_past_valid_q;
    always_ff @(posedge app_clk_i) begin
        formal_app_past_valid_q <= 1'b1;
        if (app_domain_reset_n) begin
            assert (loader_count_q <= 18'd227062);
            if (model_locked_o)
                assert (loader_count_q == 18'd227062 &&
                        digest_success_app);
            if (app_wr_data_en_o && model_locked_o)
                assert (app_addr_o >= 29'h01bb800 &&
                        app_addr_o < 29'h036b800);
            if (formal_app_past_valid_q &&
                $past(app_domain_reset_n) && $past(app_fault_q))
                assert (app_fault_q);
            if (physical_suppress_now) begin
                assert (!app_cmd_en_o && !app_wr_data_en_o &&
                        !app_wr_data_end_o && !app_burst_o &&
                        !app_self_refresh_req_o && !app_refresh_req_o);
            end
            if (controller_protocol_fault_now) begin
                assert (!app_cmd_en_o && !app_wr_data_en_o &&
                        !app_wr_data_end_o && !app_burst_o &&
                        !app_self_refresh_req_o && !app_refresh_req_o);
            end
            if (formal_app_past_valid_q &&
                $past(app_domain_reset_n) &&
                $past(controller_protocol_fault_now))
                assert(app_fault_q);
        end
    end
`endif
endmodule

// Private exact replacement for the original saturating watchdog counter.
// A registered low-byte carry removes the low->high full-width carry path.
// The registered limit predicate replaces a wide comparison on the counter
// enable/trip fanout. Both predicates describe the *current* count exactly;
// there is no delayed progress, deadline, fault, or reset observation.
module board1_watchdog_counter_exact #(
    parameter integer CYCLES = 100_000_000,
    parameter integer WIDTH = $clog2(CYCLES + 1)
) (
    input wire clk_i,
    input wire reset_n_i,
    input wire clear_i,
    output logic [WIDTH-1:0] count_o,
    output logic at_limit_o
);
    localparam logic [WIDTH-1:0] LAST = WIDTH'(CYCLES - 1);
    localparam logic [WIDTH-1:0] BEFORE_LAST = WIDTH'(CYCLES - 2);
    (* syn_preserve = 1 *) logic low_carry_q;
    initial begin
        if (CYCLES < 256 || CYCLES > 1_000_000_000 ||
            WIDTH != $clog2(CYCLES + 1) || WIDTH <= 8)
            $fatal(1, "private exact watchdog geometry differs");
    end
    always_ff @(posedge clk_i or negedge reset_n_i) begin
        if (!reset_n_i) begin
            count_o <= '0;
            at_limit_o <= 1'b0;
            low_carry_q <= 1'b0;
        end else if (clear_i) begin
            count_o <= '0;
            at_limit_o <= 1'b0;
            low_carry_q <= 1'b0;
        end else if (!at_limit_o) begin
            count_o[7:0] <= count_o[7:0] + 8'd1;
            count_o[WIDTH-1:8] <= count_o[WIDTH-1:8] +
                                    {{(WIDTH-9){1'b0}}, low_carry_q};
            low_carry_q <= count_o[7:0] == 8'hfe;
            at_limit_o <= count_o == BEFORE_LAST;
        end
    end
`ifdef FORMAL
    always_ff @(posedge clk_i) begin
        if (reset_n_i) begin
            assert (count_o <= LAST);
            assert (at_limit_o == (count_o == LAST));
            assert (low_carry_q == (&count_o[7:0]));
        end
    end
`endif
endmodule

`default_nettype wire
