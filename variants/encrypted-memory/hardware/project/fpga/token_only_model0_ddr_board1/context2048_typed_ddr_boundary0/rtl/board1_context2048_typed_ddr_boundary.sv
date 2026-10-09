// Board1 25 MHz <-> 100 MHz typed DDR capability transport.
//
// Production intent:
//   * source channels are capabilities, not a generic raw-address bus;
//   * every accepted request carries an epoch and receives exactly one typed
//     response/completion through the return FIFO;
//   * the app-domain child independently validates and reconstructs KV
//     addresses, and only that reconstructed address can reach the endpoint;
//   * CLEAR never flushes accepted work.  It changes epoch, blocks admission,
//     and waits for old owners to consume fault-marked responses.
module tang_kv_cipher_typed_boundary #(
    parameter integer FIFO_ADDR_BITS = 2
) (
    input  wire         core_clk_i,
    input  wire         core_reset_n_i,
    input  wire         core_clear_i,
    input  wire         core_upstream_fault_i,

    input  wire         model_req_valid_i,
    output logic        model_req_ready_o,
    input  wire [18:0]  model_req_word_i,
    output logic        model_rsp_valid_o,
    input  wire         model_rsp_ready_i,
    output logic [255:0] model_rsp_data_o,
    output logic        model_rsp_fault_o,

    input  wire         kv_write_req_valid_i,
    output logic        kv_write_req_ready_o,
    input  wire [2:0]   kv_write_req_layer_i,
    input  wire [11:0]  kv_write_req_position_i,
    input  wire [1:0]   kv_write_req_head_i,
    input  wire [3:0]   kv_write_req_row_word_i,
    input  wire [18:0]  kv_write_req_shadow_address_i,
    input  wire [255:0] kv_write_req_data_i,
    output logic        kv_write_cpl_valid_o,
    input  wire         kv_write_cpl_ready_i,
    output logic        kv_write_cpl_fault_o,

    input  wire         kv_read_req_valid_i,
    output logic        kv_read_req_ready_o,
    input  wire [2:0]   kv_read_req_layer_i,
    input  wire [11:0]  kv_read_req_position_i,
    input  wire [1:0]   kv_read_req_head_i,
    input  wire [3:0]   kv_read_req_row_word_i,
    input  wire [18:0]  kv_read_req_shadow_address_i,
    output logic        kv_read_rsp_valid_o,
    input  wire         kv_read_rsp_ready_i,
    output logic [255:0] kv_read_rsp_data_o,
    output logic        kv_read_rsp_fault_o,

    output logic        core_clear_pending_o,
    output logic        core_clear_drained_o,
    output logic        core_busy_o,
    output logic        core_fail_closed_o,

    input  wire         app_clk_i,
    input  wire         app_reset_n_i,
    input  wire         app_model_locked_i,
    input  wire         app_upstream_fault_i,

    output wire         endpoint_req_valid_o,
    input  wire         endpoint_req_ready_i,
    output wire [18:0]  endpoint_req_word_address_o,
    output wire         endpoint_req_write_o,
    output wire [255:0] endpoint_req_write_data_o,
    input  wire         endpoint_rsp_valid_i,
    output wire         endpoint_rsp_ready_o,
    input  wire [255:0] endpoint_rsp_data_i,
    input  wire         endpoint_rsp_error_i,

    output logic        app_busy_o,
    output logic        app_fail_closed_o
);
    localparam integer REQ_WIDTH = 318;
    localparam integer RSP_WIDTH = 260;
    localparam integer OUTSTANDING_WIDTH = FIFO_ADDR_BITS + 1;
    localparam logic [OUTSTANDING_WIDTH-1:0] FIFO_DEPTH_COUNT =
        OUTSTANDING_WIDTH'(1 << FIFO_ADDR_BITS);

    localparam logic [1:0] KIND_MODEL_READ = 2'b00;
    localparam logic [1:0] KIND_KV_WRITE   = 2'b01;
    localparam logic [1:0] KIND_KV_READ    = 2'b10;

    wire combined_async_reset_n = core_reset_n_i && app_reset_n_i;
    (* async_reg = "true", syn_preserve = 1 *)
    logic [2:0] core_release_q;
    (* async_reg = "true", syn_preserve = 1 *)
    logic [2:0] app_release_q;
    wire core_local_reset_n = core_release_q[2];
    wire app_local_reset_n  = app_release_q[2];

    always_ff @(posedge core_clk_i or negedge combined_async_reset_n) begin
        if (!combined_async_reset_n)
            core_release_q <= 3'b000;
        else
            core_release_q <= {core_release_q[1:0], 1'b1};
    end

    always_ff @(posedge app_clk_i or negedge combined_async_reset_n) begin
        if (!combined_async_reset_n)
            app_release_q <= 3'b000;
        else
            app_release_q <= {app_release_q[1:0], 1'b1};
    end

    // The lock is born in the application domain.  Source admission waits for
    // an independently synchronized copy; loss after observation is terminal.
    (* async_reg = "true", syn_preserve = 1 *)
    logic model_lock_core_meta_q;
    (* async_reg = "true", syn_preserve = 1 *)
    logic model_lock_core_sync_q;
    (* async_reg = "true", syn_preserve = 1 *)
    logic app_fault_core_meta_q;
    (* async_reg = "true", syn_preserve = 1 *)
    logic app_fault_core_sync_q;
    (* async_reg = "true", syn_preserve = 1 *)
    logic core_fault_app_meta_q;
    (* async_reg = "true", syn_preserve = 1 *)
    logic core_fault_app_sync_q;

    logic core_fault_q;
    logic app_boundary_fault;
    logic request_fifo_source_fault;
    logic request_fifo_destination_fault;
    logic response_fifo_source_fault;
    logic response_fifo_destination_fault;

    always_ff @(posedge core_clk_i or negedge core_local_reset_n) begin
        if (!core_local_reset_n) begin
            model_lock_core_meta_q <= 1'b0;
            model_lock_core_sync_q <= 1'b0;
            app_fault_core_meta_q  <= 1'b0;
            app_fault_core_sync_q  <= 1'b0;
        end else begin
            model_lock_core_meta_q <= app_model_locked_i;
            model_lock_core_sync_q <= model_lock_core_meta_q;
            app_fault_core_meta_q  <= app_boundary_fault ||
                                      request_fifo_destination_fault ||
                                      response_fifo_source_fault;
            app_fault_core_sync_q  <= app_fault_core_meta_q;
        end
    end

    always_ff @(posedge app_clk_i or negedge app_local_reset_n) begin
        if (!app_local_reset_n) begin
            core_fault_app_meta_q <= 1'b0;
            core_fault_app_sync_q <= 1'b0;
        end else begin
            core_fault_app_meta_q <= core_fault_q ||
                                     request_fifo_source_fault ||
                                     response_fifo_destination_fault;
            core_fault_app_sync_q <= core_fault_app_meta_q;
        end
    end

    // ---------------------------------------------------------------------
    // Source-domain typed admission and epoch ownership.
    // ---------------------------------------------------------------------
    logic core_lock_seen_q;
    logic core_clear_seen_q;
    logic core_clear_pending_q;
    logic core_epoch_q;
    logic [OUTSTANDING_WIDTH-1:0] core_outstanding_q;
    logic core_x_fault;
    logic model_rsp_stalled_q;
    logic [256:0] model_rsp_stalled_payload_q;
    logic kv_write_cpl_stalled_q;
    logic kv_write_cpl_stalled_fault_q;
    logic kv_read_rsp_stalled_q;
    logic [256:0] kv_read_rsp_stalled_payload_q;

    wire model_present = (model_req_valid_i === 1'b1);
    wire kv_write_present = (kv_write_req_valid_i === 1'b1);
    wire kv_read_present = (kv_read_req_valid_i === 1'b1);
    wire request_collision = (model_present && kv_write_present) ||
                             (model_present && kv_read_present) ||
                             (kv_write_present && kv_read_present);
    wire core_clear_active = (core_clear_i === 1'b1);
    wire core_terminal = core_fault_q || app_fault_core_sync_q || core_x_fault;
    wire core_response_abort = core_clear_active || core_clear_pending_q ||
                               core_terminal;
    wire core_capacity_available = core_outstanding_q < FIFO_DEPTH_COUNT;

    logic req_fifo_s_valid;
    wire req_fifo_s_ready;
    logic [REQ_WIDTH-1:0] req_fifo_s_data;
    wire req_fifo_s_full;
    wire req_fifo_s_empty;
    wire req_fifo_m_valid;
    wire req_fifo_m_ready;
    wire [REQ_WIDTH-1:0] req_fifo_m_data;

    wire source_admission_open = core_local_reset_n &&
                                 model_lock_core_sync_q &&
                                 !core_terminal &&
                                 !core_clear_active &&
                                 !core_clear_pending_q &&
                                 core_capacity_available;

    always_comb begin
        model_req_ready_o = source_admission_open && req_fifo_s_ready &&
                            !kv_write_present && !kv_read_present;
        kv_write_req_ready_o = source_admission_open && req_fifo_s_ready &&
                               !model_present && !kv_read_present;
        kv_read_req_ready_o = source_admission_open && req_fifo_s_ready &&
                              !model_present && !kv_write_present;

        req_fifo_s_valid = source_admission_open && !request_collision &&
                           (model_present || kv_write_present ||
                            kv_read_present);
        req_fifo_s_data = {KIND_MODEL_READ, core_epoch_q,
                           model_req_word_i, 3'd0, 12'd0, 2'd0, 4'd0,
                           19'd0, 256'd0};
        if (kv_write_present) begin
            req_fifo_s_data = {KIND_KV_WRITE, core_epoch_q, 19'd0,
                               kv_write_req_layer_i,
                               kv_write_req_position_i,
                               kv_write_req_head_i,
                               kv_write_req_row_word_i,
                               kv_write_req_shadow_address_i,
                               kv_write_req_data_i};
        end else if (kv_read_present) begin
            req_fifo_s_data = {KIND_KV_READ, core_epoch_q, 19'd0,
                               kv_read_req_layer_i,
                               kv_read_req_position_i,
                               kv_read_req_head_i,
                               kv_read_req_row_word_i,
                               kv_read_req_shadow_address_i,
                               256'd0};
        end
    end

    wire request_take = req_fifo_s_valid && req_fifo_s_ready;

`ifndef SYNTHESIS
`ifndef FORMAL
    always_comb begin
        core_x_fault = 1'b0;
        if ((^{core_reset_n_i, core_clear_i,
               core_upstream_fault_i, model_req_valid_i,
               kv_write_req_valid_i, kv_read_req_valid_i,
               model_rsp_ready_i, kv_write_cpl_ready_i,
               kv_read_rsp_ready_i, model_lock_core_sync_q}) === 1'bx) begin
            core_x_fault = 1'b1;
        end
        if (model_present && ((^model_req_word_i) === 1'bx))
            core_x_fault = 1'b1;
        if (kv_write_present &&
            ((^{kv_write_req_layer_i, kv_write_req_position_i,
                kv_write_req_head_i, kv_write_req_row_word_i,
                kv_write_req_shadow_address_i,
                kv_write_req_data_i}) === 1'bx)) begin
            core_x_fault = 1'b1;
        end
        if (kv_read_present &&
            ((^{kv_read_req_layer_i, kv_read_req_position_i,
                kv_read_req_head_i, kv_read_req_row_word_i,
                kv_read_req_shadow_address_i}) === 1'bx)) begin
            core_x_fault = 1'b1;
        end
    end
`else
    always_comb core_x_fault = 1'b0;
`endif
`else
    always_comb core_x_fault = 1'b0;
`endif

    // ---------------------------------------------------------------------
    // Typed response return and source-owner demultiplexing.
    // ---------------------------------------------------------------------
    wire rsp_fifo_s_valid;
    wire rsp_fifo_s_ready;
    wire [RSP_WIDTH-1:0] rsp_fifo_s_data;
    wire rsp_fifo_s_full;
    wire rsp_fifo_s_empty;
    wire rsp_fifo_m_valid;
    logic rsp_fifo_m_ready;
    wire [RSP_WIDTH-1:0] rsp_fifo_m_data;
    wire rsp_fifo_m_empty;

    wire [1:0] rsp_kind = rsp_fifo_m_data[259:258];
    wire rsp_epoch = rsp_fifo_m_data[257];
    wire rsp_stored_fault = rsp_fifo_m_data[256];
    wire [255:0] rsp_stored_data = rsp_fifo_m_data[255:0];
    wire rsp_kind_model = rsp_kind == KIND_MODEL_READ;
    wire rsp_kind_write = rsp_kind == KIND_KV_WRITE;
    wire rsp_kind_read  = rsp_kind == KIND_KV_READ;
    wire rsp_kind_reserved = !(rsp_kind_model || rsp_kind_write ||
                               rsp_kind_read);
    wire rsp_epoch_mismatch = rsp_epoch != core_epoch_q;
    wire rsp_effective_fault = rsp_stored_fault || rsp_epoch_mismatch ||
                               core_terminal || core_clear_active ||
                               core_clear_pending_q;

    always_comb begin
        model_rsp_valid_o    = rsp_fifo_m_valid && rsp_kind_model;
        model_rsp_data_o     = rsp_effective_fault ? 256'd0 : rsp_stored_data;
        model_rsp_fault_o    = model_rsp_valid_o && rsp_effective_fault;
        kv_write_cpl_valid_o = rsp_fifo_m_valid && rsp_kind_write;
        kv_write_cpl_fault_o = kv_write_cpl_valid_o && rsp_effective_fault;
        kv_read_rsp_valid_o  = rsp_fifo_m_valid && rsp_kind_read;
        kv_read_rsp_data_o   = rsp_effective_fault ? 256'd0 : rsp_stored_data;
        kv_read_rsp_fault_o  = kv_read_rsp_valid_o && rsp_effective_fault;

        rsp_fifo_m_ready = 1'b0;
        case (rsp_kind)
            KIND_MODEL_READ: rsp_fifo_m_ready =
                (model_rsp_ready_i === 1'b1);
            KIND_KV_WRITE: rsp_fifo_m_ready =
                (kv_write_cpl_ready_i === 1'b1);
            KIND_KV_READ: rsp_fifo_m_ready =
                (kv_read_rsp_ready_i === 1'b1);
            default: rsp_fifo_m_ready = 1'b1;
        endcase
    end

    wire response_take = rsp_fifo_m_valid && rsp_fifo_m_ready;

    always_ff @(posedge core_clk_i or negedge core_local_reset_n) begin
        if (!core_local_reset_n) begin
            core_fault_q         <= 1'b0;
            core_lock_seen_q     <= 1'b0;
            core_clear_seen_q    <= 1'b0;
            core_clear_pending_q <= 1'b0;
            core_clear_drained_o <= 1'b0;
            core_epoch_q         <= 1'b0;
            core_outstanding_q   <= {OUTSTANDING_WIDTH{1'b0}};
            model_rsp_stalled_q  <= 1'b0;
            model_rsp_stalled_payload_q <= 257'd0;
            kv_write_cpl_stalled_q <= 1'b0;
            kv_write_cpl_stalled_fault_q <= 1'b0;
            kv_read_rsp_stalled_q <= 1'b0;
            kv_read_rsp_stalled_payload_q <= 257'd0;
        end else begin
            core_clear_drained_o <= 1'b0;

            if (model_lock_core_sync_q)
                core_lock_seen_q <= 1'b1;

            if (core_upstream_fault_i || core_x_fault || request_collision ||
                request_fifo_source_fault ||
                response_fifo_destination_fault ||
                app_fault_core_sync_q ||
                (core_lock_seen_q && !model_lock_core_sync_q) ||
                (rsp_fifo_m_valid && rsp_kind_reserved) ||
                (response_take && (core_outstanding_q == 0)) ||
                (rsp_fifo_m_valid && rsp_epoch_mismatch &&
                 !core_clear_pending_q && !core_clear_active)) begin
                core_fault_q <= 1'b1;
            end

            // CLEAR/epoch invalidation and a visible terminal fault are the
            // explicit abort exceptions to outward ready/valid holding.  In
            // ordinary operation each typed response and payload must remain
            // stable until its owner handshakes it.
            if (core_response_abort) begin
                model_rsp_stalled_q    <= 1'b0;
                kv_write_cpl_stalled_q <= 1'b0;
                kv_read_rsp_stalled_q  <= 1'b0;
            end else begin
                if (model_rsp_stalled_q &&
                    (!model_rsp_valid_o ||
                     ({model_rsp_fault_o, model_rsp_data_o} !=
                      model_rsp_stalled_payload_q))) begin
                    core_fault_q <= 1'b1;
                end
                if (kv_write_cpl_stalled_q &&
                    (!kv_write_cpl_valid_o ||
                     (kv_write_cpl_fault_o !=
                      kv_write_cpl_stalled_fault_q))) begin
                    core_fault_q <= 1'b1;
                end
                if (kv_read_rsp_stalled_q &&
                    (!kv_read_rsp_valid_o ||
                     ({kv_read_rsp_fault_o, kv_read_rsp_data_o} !=
                      kv_read_rsp_stalled_payload_q))) begin
                    core_fault_q <= 1'b1;
                end

                model_rsp_stalled_q <= model_rsp_valid_o &&
                                       !model_rsp_ready_i;
                kv_write_cpl_stalled_q <= kv_write_cpl_valid_o &&
                                          !kv_write_cpl_ready_i;
                kv_read_rsp_stalled_q <= kv_read_rsp_valid_o &&
                                         !kv_read_rsp_ready_i;
                if (model_rsp_valid_o && !model_rsp_ready_i)
                    model_rsp_stalled_payload_q <=
                        {model_rsp_fault_o, model_rsp_data_o};
                if (kv_write_cpl_valid_o && !kv_write_cpl_ready_i)
                    kv_write_cpl_stalled_fault_q <=
                        kv_write_cpl_fault_o;
                if (kv_read_rsp_valid_o && !kv_read_rsp_ready_i)
                    kv_read_rsp_stalled_payload_q <=
                        {kv_read_rsp_fault_o, kv_read_rsp_data_o};
            end

            if (core_clear_active) begin
                if (!core_clear_seen_q) begin
                    core_clear_seen_q <= 1'b1;
                    if (!core_clear_pending_q) begin
                        core_epoch_q         <= ~core_epoch_q;
                        core_clear_pending_q <= 1'b1;
                    end
                end
            end else begin
                core_clear_seen_q <= 1'b0;
            end

            case ({request_take, response_take})
                2'b10: core_outstanding_q <= core_outstanding_q + 1'b1;
                2'b01: begin
                    if (core_outstanding_q != 0)
                        core_outstanding_q <= core_outstanding_q - 1'b1;
                end
                default: core_outstanding_q <= core_outstanding_q;
            endcase

            if (core_clear_pending_q &&
                ((core_outstanding_q == 0) ||
                 ((core_outstanding_q == 1) && response_take &&
                  !request_take))) begin
                core_clear_pending_q <= 1'b0;
                core_clear_drained_o <= 1'b1;
            end
        end
    end

    assign core_clear_pending_o = core_clear_pending_q;
    assign core_busy_o = (core_outstanding_q != 0) ||
                         core_clear_pending_q || !req_fifo_s_empty ||
                         !rsp_fifo_m_empty || req_fifo_s_full;
    assign core_fail_closed_o = core_terminal;

    // ---------------------------------------------------------------------
    // Asynchronous typed transport.  Accepted entries are never flushed.
    // ---------------------------------------------------------------------
    board1_async_fifo_gray #(
        .WIDTH(REQ_WIDTH),
        .ADDR_BITS(FIFO_ADDR_BITS),
        .RAM_STYLE("distributed"),
        .DESTINATION_LOOKAHEAD(0)
    ) request_fifo_i (
        .s_clk_i(core_clk_i),
        .s_reset_n_i(core_local_reset_n),
        .s_valid_i(req_fifo_s_valid),
        .s_ready_o(req_fifo_s_ready),
        .s_data_i(req_fifo_s_data),
        .s_abort_i(core_clear_active || core_terminal),
        .s_full_o(req_fifo_s_full),
        .s_empty_o(req_fifo_s_empty),
        .s_protocol_fault_o(request_fifo_source_fault),
        .m_clk_i(app_clk_i),
        .m_reset_n_i(app_local_reset_n),
        .m_valid_o(req_fifo_m_valid),
        .m_ready_i(req_fifo_m_ready),
        .m_data_o(req_fifo_m_data),
        .m_empty_o(),
        .m_protocol_fault_o(request_fifo_destination_fault)
    );

    board1_async_fifo_gray #(
        .WIDTH(RSP_WIDTH),
        .ADDR_BITS(FIFO_ADDR_BITS),
        .RAM_STYLE("distributed")
    ) response_fifo_i (
        .s_clk_i(app_clk_i),
        .s_reset_n_i(app_local_reset_n),
        .s_valid_i(rsp_fifo_s_valid),
        .s_ready_o(rsp_fifo_s_ready),
        .s_data_i(rsp_fifo_s_data),
        .s_abort_i(1'b0),
        .s_full_o(rsp_fifo_s_full),
        .s_empty_o(rsp_fifo_s_empty),
        .s_protocol_fault_o(response_fifo_source_fault),
        .m_clk_i(core_clk_i),
        .m_reset_n_i(core_local_reset_n),
        .m_valid_o(rsp_fifo_m_valid),
        .m_ready_i(rsp_fifo_m_ready),
        .m_data_o(rsp_fifo_m_data),
        .m_empty_o(rsp_fifo_m_empty),
        .m_protocol_fault_o(response_fifo_destination_fault)
    );

    // ---------------------------------------------------------------------
    // App-domain independent reconstruction and capability enforcement.
    // ---------------------------------------------------------------------
    wire [1:0] app_req_kind       = req_fifo_m_data[317:316];
    wire app_req_epoch            = req_fifo_m_data[315];
    wire [18:0] app_req_model     = req_fifo_m_data[314:296];
    wire [2:0] app_req_layer      = req_fifo_m_data[295:293];
    wire [11:0] app_req_position  = req_fifo_m_data[292:281];
    wire [1:0] app_req_head       = req_fifo_m_data[280:279];
    wire [3:0] app_req_row_word   = req_fifo_m_data[278:275];
    wire [18:0] app_req_shadow    = req_fifo_m_data[274:256];
    wire [255:0] app_req_wdata    = req_fifo_m_data[255:0];

    wire app_rsp_valid;
    wire [1:0] app_rsp_kind;
    wire app_rsp_epoch;
    wire [255:0] app_rsp_data;
    wire app_rsp_fault;
    wire app_policy_busy;

    assign rsp_fifo_s_valid = app_rsp_valid;
    assign rsp_fifo_s_data  = {app_rsp_kind, app_rsp_epoch,
                               app_rsp_fault, app_rsp_data};

    tang_kv_cipher_typed_app_boundary app_boundary_i (
        .clk_i(app_clk_i),
        .reset_n_i(app_local_reset_n),
        .model_locked_i(app_model_locked_i),
        .upstream_fault_i(app_upstream_fault_i || core_fault_app_sync_q ||
                          request_fifo_destination_fault ||
                          response_fifo_source_fault),
        .req_valid_i(req_fifo_m_valid),
        .req_ready_o(req_fifo_m_ready),
        .req_kind_i(app_req_kind),
        .req_epoch_i(app_req_epoch),
        .req_model_word_i(app_req_model),
        .req_layer_i(app_req_layer),
        .req_position_i(app_req_position),
        .req_head_i(app_req_head),
        .req_row_word_i(app_req_row_word),
        .req_shadow_address_i(app_req_shadow),
        .req_write_data_i(app_req_wdata),
        .rsp_valid_o(app_rsp_valid),
        .rsp_ready_i(rsp_fifo_s_ready),
        .rsp_kind_o(app_rsp_kind),
        .rsp_epoch_o(app_rsp_epoch),
        .rsp_data_o(app_rsp_data),
        .rsp_fault_o(app_rsp_fault),
        .endpoint_req_valid_o(endpoint_req_valid_o),
        .endpoint_req_ready_i(endpoint_req_ready_i),
        .endpoint_req_word_address_o(endpoint_req_word_address_o),
        .endpoint_req_write_o(endpoint_req_write_o),
        .endpoint_req_write_data_o(endpoint_req_write_data_o),
        .endpoint_rsp_valid_i(endpoint_rsp_valid_i),
        .endpoint_rsp_ready_o(endpoint_rsp_ready_o),
        .endpoint_rsp_data_i(endpoint_rsp_data_i),
        .endpoint_rsp_error_i(endpoint_rsp_error_i),
        .busy_o(app_policy_busy),
        .fail_closed_o(app_boundary_fault)
    );

    assign app_busy_o = app_policy_busy || req_fifo_m_valid || app_rsp_valid ||
                        !rsp_fifo_s_empty || rsp_fifo_s_full;
    assign app_fail_closed_o = app_boundary_fault || core_fault_app_sync_q ||
                               request_fifo_destination_fault ||
                               response_fifo_source_fault;

`ifdef FORMAL
    always_ff @(posedge core_clk_i) begin
        if (core_local_reset_n) begin
            assert(core_outstanding_q <= FIFO_DEPTH_COUNT);
            if (request_take) assert(!request_collision);
            if (model_rsp_valid_o) assert(!kv_write_cpl_valid_o &&
                                          !kv_read_rsp_valid_o);
            if (kv_write_cpl_valid_o) assert(!model_rsp_valid_o &&
                                             !kv_read_rsp_valid_o);
            if (kv_read_rsp_valid_o) assert(!model_rsp_valid_o &&
                                            !kv_write_cpl_valid_o);
        end
    end
`endif
endmodule
