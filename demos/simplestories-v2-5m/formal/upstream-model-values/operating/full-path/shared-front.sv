`undef FORMAL
module board1_private_shared_ddr_transaction_boundary #(
    parameter integer WATCHDOG_CYCLES = 50000000
) (
    input wire clk, reset_n,
    input wire model_locked_i, upstream_fault_i,
    input wire model_req_valid_i,
    output wire model_req_ready_o,
    input wire [18:0] model_req_word_i,
    output wire model_rsp_valid_o,
    output wire [255:0] model_rsp_data_o,
    output wire model_rsp_error_o,
    input wire kv_req_valid_i,
    output wire kv_req_ready_o,
    input wire [18:0] kv_req_word_i,
    input wire kv_req_write_i,
    input wire [255:0] kv_req_data_i,
    output wire kv_rsp_valid_o,
    input wire kv_rsp_ready_i,
    output wire [255:0] kv_rsp_data_o,
    output wire kv_rsp_error_o,
    output wire raw_req_valid_o,
    input wire raw_req_ready_i,
    output wire [24:0] raw_req_word_o,
    output wire raw_req_write_o,
    output wire [255:0] raw_req_data_o,
    input wire raw_rsp_valid_i,
    input wire [255:0] raw_rsp_data_i,
    input wire raw_rsp_error_i,
    output wire busy_o,
    output wire fault_o
);
    wire model_queue_ready, model_queue_valid, model_backend_ready;
    wire [18:0] model_queue_word;
    wire kv_queue_ready, kv_queue_valid, kv_backend_ready, kv_queue_write;
    wire [18:0] kv_queue_word;
    wire [255:0] kv_queue_data;
    wire backend_model_valid, backend_model_error;
    wire [255:0] backend_model_data;
    wire backend_kv_valid, backend_kv_ready, backend_kv_error;
    wire [255:0] backend_kv_data;
    wire backend_busy, backend_fault;
    logic stop_q, lock_seen_q;
    logic [3:0] kv_owner_q;
    logic kv_write_owner_q;
    logic model_return_valid_q, model_return_error_q;
    logic [255:0] model_return_data_q;
    logic kv_return_valid_q, kv_return_error_q;
    logic [255:0] kv_return_data_q;
    logic frontend_x_fault;

    wire invalid_front_request =
        (model_req_valid_i && model_req_word_i >= 19'd227062) ||
        (kv_req_valid_i && (kv_req_word_i < 19'd227072 || kv_req_word_i >= 19'd448256));
    wire frontend_fault = invalid_front_request || frontend_x_fault ||
                          (lock_seen_q && !model_locked_i);
    assign fault_o = stop_q || backend_fault;
    wire admit_enabled = reset_n && model_locked_i && !fault_o;
    wire model_admit = model_req_valid_i && model_req_ready_o;
    wire kv_admit = kv_req_valid_i && kv_req_ready_o;
    wire kv_retire = kv_rsp_valid_o && kv_rsp_ready_i;

    // Source READY depends on registered local occupancy/ownership, not
    // backend validation, raw READY, or a newly arriving memory response.
    assign model_req_ready_o = admit_enabled && model_queue_ready;
    // Backend retirement into this boundary's held return register is not
    // delivery to the typed owner. Keep writes exclusive across BOTH levels,
    // including an arbitrarily stalled write completion at this output.
    wire kv_front_capacity = kv_owner_q < 4'd8 && !kv_write_owner_q &&
                             (!kv_req_write_i || kv_owner_q == 0);
    assign kv_req_ready_o = admit_enabled && kv_front_capacity && kv_queue_ready;
    board1_ddr_request_fifo2 #(.ADDR_W(19)) u_model_admission (
        .clk(clk), .reset_n(reset_n), .abort_i(1'b0),
        .in_valid_i(model_req_valid_i && admit_enabled), .in_ready_o(model_queue_ready),
        .in_write_i(1'b0), .in_addr_i(model_req_word_i), .in_data_i(256'd0),
        .out_valid_o(model_queue_valid), .out_ready_i(model_backend_ready && !fault_o),
        .out_write_o(), .out_addr_o(model_queue_word), .out_data_o());
    board1_ddr_request_fifo2 #(.ADDR_W(19)) u_kv_admission (
        .clk(clk), .reset_n(reset_n), .abort_i(1'b0),
        .in_valid_i(kv_req_valid_i && admit_enabled && kv_front_capacity), .in_ready_o(kv_queue_ready),
        .in_write_i(kv_req_write_i), .in_addr_i(kv_req_word_i), .in_data_i(kv_req_data_i),
        .out_valid_o(kv_queue_valid), .out_ready_i(kv_backend_ready && !fault_o),
        .out_write_o(kv_queue_write), .out_addr_o(kv_queue_word), .out_data_o(kv_queue_data));

    // The original backend retains all fixed-region, ownership, raw response,
    // lock-loss, error and watchdog checks. A new bad front offer is latched
    // into stop_q on its capture edge; it cannot issue from the queued stage.
    // Already owned healthy traffic may drain on that detection edge. A known
    // external terminal fault still blocks raw requests in the same cycle.
    board1_private_shared_ddr_arbiter #(.WATCHDOG_CYCLES(WATCHDOG_CYCLES)) u_backend (
        .clk(clk), .reset_n(reset_n), .model_locked_i(model_locked_i),
        .upstream_fault_i(upstream_fault_i || stop_q),
        .model_req_valid_i(model_queue_valid && !fault_o), .model_req_ready_o(model_backend_ready),
        .model_req_word_i(model_queue_word), .model_rsp_valid_o(backend_model_valid),
        .model_rsp_data_o(backend_model_data), .model_rsp_error_o(backend_model_error),
        .kv_req_valid_i(kv_queue_valid && !fault_o), .kv_req_ready_o(kv_backend_ready),
        .kv_req_word_i(kv_queue_word), .kv_req_write_i(kv_queue_write), .kv_req_data_i(kv_queue_data),
        .kv_rsp_valid_o(backend_kv_valid), .kv_rsp_ready_i(backend_kv_ready),
        .kv_rsp_data_o(backend_kv_data), .kv_rsp_error_o(backend_kv_error),
        .raw_req_valid_o(raw_req_valid_o), .raw_req_ready_i(raw_req_ready_i),
        .raw_req_word_o(raw_req_word_o), .raw_req_write_o(raw_req_write_o), .raw_req_data_o(raw_req_data_o),
        .raw_rsp_valid_i(raw_rsp_valid_i), .raw_rsp_data_i(raw_rsp_data_i),
        .raw_rsp_error_i(raw_rsp_error_i), .busy_o(backend_busy), .fault_o(backend_fault));

    // Model responses have reserved capacity and no backpressure. This
    // one-cycle, one-word-per-cycle stage carries VALID/error/data together.
    // Capturing unpublished data unconditionally avoids a 256-load validation
    // enable. No credit is released until the unchanged CDC delivers to core.
    assign model_rsp_valid_o = model_return_valid_q && reset_n && !fault_o;
    assign model_rsp_data_o = model_return_data_q;
    assign model_rsp_error_o = model_return_error_q;
    assign backend_kv_ready = (!kv_return_valid_q || kv_rsp_ready_i) && reset_n && !fault_o;
    assign kv_rsp_valid_o = kv_return_valid_q && reset_n && !fault_o;
    assign kv_rsp_data_o = kv_return_data_q;
    assign kv_rsp_error_o = kv_return_error_q;
    assign busy_o = backend_busy || model_queue_valid || kv_queue_valid ||
                    model_return_valid_q || kv_return_valid_q || kv_owner_q != 0;
    always_ff @(posedge clk) begin
        model_return_data_q <= backend_model_data;
        if (backend_kv_ready) kv_return_data_q <= backend_kv_data;
    end

    always_comb begin
        frontend_x_fault = 1'b0;
`ifndef SYNTHESIS
`ifndef FORMAL
        frontend_x_fault = $isunknown(model_locked_i) || $isunknown(upstream_fault_i) ||
            $isunknown(model_req_valid_i) || $isunknown(kv_req_valid_i) || $isunknown(kv_rsp_ready_i);
        if (model_req_valid_i) frontend_x_fault = frontend_x_fault || $isunknown(model_req_word_i);
        if (kv_req_valid_i) frontend_x_fault = frontend_x_fault || $isunknown(kv_req_word_i) ||
            $isunknown(kv_req_write_i) || (kv_req_write_i && $isunknown(kv_req_data_i));
`endif
`endif
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            stop_q <= 1'b0; lock_seen_q <= 1'b0; kv_owner_q <= 4'd0;
            kv_write_owner_q <= 1'b0;
            model_return_valid_q <= 1'b0; model_return_error_q <= 1'b0;
            kv_return_valid_q <= 1'b0; kv_return_error_q <= 1'b0;
        end else begin
            if (model_locked_i) lock_seen_q <= 1'b1;
            if (upstream_fault_i || backend_fault || frontend_fault) stop_q <= 1'b1;
            if (kv_admit && kv_req_write_i) kv_write_owner_q <= 1'b1;
            if (kv_retire && kv_write_owner_q) kv_write_owner_q <= 1'b0;
            case ({kv_admit,kv_retire})
                2'b10: kv_owner_q <= kv_owner_q + 4'd1;
                2'b01: kv_owner_q <= kv_owner_q - 4'd1;
                default: ;
            endcase
            model_return_valid_q <= backend_model_valid && !fault_o;
            model_return_error_q <= backend_model_error;
            if (kv_retire) kv_return_valid_q <= 1'b0;
            if (backend_kv_valid && backend_kv_ready) begin
                kv_return_valid_q <= 1'b1;
                kv_return_error_q <= backend_kv_error;
            end
        end
    end
`ifdef FORMAL
    always_ff @(posedge clk) if (reset_n) begin
        assert (kv_owner_q <= 8);
        if (kv_write_owner_q) begin
            assert(kv_owner_q == 1);
            assert(!kv_req_ready_o);
        end
        if (kv_rsp_valid_o) assert (kv_owner_q);
        if (backend_kv_valid) assert (kv_owner_q);
        if (fault_o) assert (!model_req_ready_o && !kv_req_ready_o &&
                            !model_rsp_valid_o && !kv_rsp_valid_o && !raw_req_valid_o);
        if (upstream_fault_i) assert (!raw_req_valid_o);
    end
`endif
endmodule
