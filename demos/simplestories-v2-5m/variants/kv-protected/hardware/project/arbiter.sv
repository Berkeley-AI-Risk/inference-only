`timescale 1ns/1ps
`default_nettype none

// PRIVATE application-clock seam. One read-only authenticated-page client
// and the existing typed K/V boundary share the normalized Gowin adapter.
// No host address, weight-write, or arithmetic command is added. The parent
// must finish trusted boot before raising model_locked_i, and must stop on
// fault_o. This is not the boot writer or a replacement for typed K/V checks.
//
// Reads return in issue order, at least one clock after acceptance, with no
// backpressure. Every model read reserves return space in the upstream CDC
// bridge before being accepted here. A single K/V transaction owns its own
// held response. Writes complete when the adapter accepts command AND data;
// read-after-write ordering is the controller's contract, not a persistence
// guarantee. CLEAR is intentionally absent: accepted traffic must drain.
module board1_private_shared_ddr_arbiter #(
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
    output logic fault_o
);
    localparam integer WW = $clog2(WATCHDOG_CYCLES + 1);
    localparam [18:0] MODEL_WORDS = 19'd227062;
    localparam [18:0] KV_BASE = 19'd227072;
    localparam [18:0] KV_LIMIT = 19'd448256; // 6 * 2048 * 2 * 9 words
    logic lock_seen_q, prefer_kv_q;
    logic cmd_valid_q, cmd_kv_q, cmd_write_q;
    logic [18:0] cmd_word_q;
    logic [255:0] cmd_data_q;
    logic kv_busy_q, kv_response_q;
    logic [255:0] kv_data_q;
    logic [31:0] read_owner_q; // 0=model, 1=K/V
    logic [4:0] read_head_q, read_tail_q;
    logic [5:0] read_count_q;
    // Same-cycle registered projections of the owned read count.
    logic read_nonempty_q, read_space_q;
    logic [WW-1:0] watchdog_q;
    logic x_error;

    wire invalid_request =
        (model_req_valid_i && model_req_word_i >= MODEL_WORDS) ||
        (kv_req_valid_i && (kv_req_word_i < KV_BASE || kv_req_word_i >= KV_LIMIT));
    wire invalid_response = raw_rsp_valid_i &&
        (!read_nonempty_q || raw_rsp_error_i || !model_locked_i);
    wire waiting = cmd_valid_q || read_nonempty_q || (kv_busy_q && !kv_response_q);
    wire timed_out = waiting && watchdog_q == WW'(WATCHDOG_CYCLES - 1);
    wire failure = upstream_fault_i || invalid_request || invalid_response ||
                   (lock_seen_q && !model_locked_i) || timed_out || x_error;
    wire enabled = reset_n && model_locked_i && !fault_o && !failure;
    wire returning = raw_rsp_valid_i && read_nonempty_q && enabled;
    wire returning_kv = returning && read_owner_q[read_head_q];
    wire raw_fire = raw_req_valid_o && raw_req_ready_i;
    wire read_issue = raw_fire && !cmd_write_q;
    wire command_room = !cmd_valid_q || raw_fire;
    wire want_kv = kv_req_valid_i && !kv_busy_q;
    wire take_kv = want_kv && (!model_req_valid_i || prefer_kv_q);
    wire model_fire = model_req_valid_i && model_req_ready_o;
    wire kv_fire = kv_req_valid_i && kv_req_ready_o;

    // Once captured, the command remains stable across arbitrary raw stalls.
    // A full tag FIFO may hold one additional unissued command in this slot.
    assign raw_req_valid_o = enabled && cmd_valid_q &&
                            (cmd_write_q || read_space_q);
    assign raw_req_word_o = {6'd0,cmd_word_q};
    assign raw_req_write_o = cmd_write_q;
    assign raw_req_data_o = cmd_data_q;
    assign model_req_ready_o = enabled && command_room && !take_kv;
    assign kv_req_ready_o = enabled && command_room && take_kv;
    assign model_rsp_valid_o = returning && !read_owner_q[read_head_q];
    assign model_rsp_data_o = raw_rsp_data_i;
    assign model_rsp_error_o = 1'b0; // Errors close the whole private service.
    // A held owner response must not depend combinationally on the next
    // request or its ready logic. The typed parent poisons a simultaneous
    // terminal event; the sticky fault suppresses subsequent visibility.
    assign kv_rsp_valid_o = kv_response_q && reset_n && !fault_o;
    assign kv_rsp_data_o = kv_data_q;
    assign kv_rsp_error_o = 1'b0;
    assign busy_o = cmd_valid_q || read_nonempty_q || kv_busy_q;

    wire command_payload_room = !cmd_valid_q ||
        (raw_req_ready_i && (cmd_write_q || read_space_q));

    // Payload and owner RAM have no reset fanout. Validity/counts guard use.
    always_ff @(posedge clk) begin
        // Capture unpublished command payload using local slot/credit state.
        // A valid unissued read behind a full owner ring MUST keep its address
        // even when raw READY is high. Fault, VALID, ownership and acceptance
        // stay on their original paths; invalid-slot address changes are private.
        if (command_payload_room)
            cmd_word_q <= take_kv ? kv_req_word_i : model_req_word_i;
        // Speculative data capture only: VALID, address, opcode, ownership,
        // authorization and command acceptance remain on the original path.
        // Every accepted write captures the correct data on this edge. A
        // stalled valid command holds it. Read-command data is unused by DDR.
        if (!cmd_valid_q || raw_req_ready_i) cmd_data_q <= kv_req_data_i;
        if (read_issue) read_owner_q[read_tail_q] <= cmd_kv_q;
        if (returning_kv) kv_data_q <= raw_rsp_data_i;
        else if (raw_fire && cmd_write_q) kv_data_q <= 256'd0;
    end

    always_comb begin
        x_error = 0;
`ifndef SYNTHESIS
`ifndef FORMAL
        x_error = $isunknown(model_locked_i) || $isunknown(upstream_fault_i) ||
            $isunknown(model_req_valid_i) || $isunknown(kv_req_valid_i) ||
            $isunknown(raw_rsp_valid_i) || $isunknown(kv_rsp_ready_i);
        if (model_req_valid_i) x_error = x_error || $isunknown(model_req_word_i);
        if (kv_req_valid_i) x_error = x_error || $isunknown(kv_req_word_i) || $isunknown(kv_req_write_i) ||
            (kv_req_write_i && $isunknown(kv_req_data_i));
        if (raw_rsp_valid_i) x_error = x_error || $isunknown(raw_rsp_data_i) || $isunknown(raw_rsp_error_i);
        // Do not reference raw_req_valid_o here: it depends on x_error.
        if (cmd_valid_q) x_error = x_error || $isunknown(raw_req_ready_i);
`endif
`endif
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            lock_seen_q <= 0; prefer_kv_q <= 1;
            cmd_valid_q <= 0; cmd_kv_q <= 0; cmd_write_q <= 0;
            kv_busy_q <= 0; kv_response_q <= 0;
            read_head_q <= 0; read_tail_q <= 0; read_count_q <= 0;
            watchdog_q <= 0; fault_o <= 0;
        end else begin
            if (model_locked_i) lock_seen_q <= 1;
            if (failure) fault_o <= 1;
            if (!waiting || raw_fire || returning) watchdog_q <= 0;
            else if (!fault_o && !timed_out) watchdog_q <= watchdog_q + 1'b1;
            if (enabled) begin
                if (raw_fire) cmd_valid_q <= 0;
                if (model_fire || kv_fire) begin
                    cmd_valid_q <= 1;
                    cmd_kv_q <= kv_fire;
                    cmd_write_q <= kv_fire && kv_req_write_i;
                    prefer_kv_q <= model_fire;
                end
                if (kv_response_q && kv_rsp_ready_i) begin
                    kv_response_q <= 0;
                    kv_busy_q <= 0;
                end
                if (kv_fire) kv_busy_q <= 1;
                if (returning_kv || (raw_fire && cmd_write_q)) kv_response_q <= 1;
                if (read_issue) read_tail_q <= read_tail_q + 5'd1;
                if (returning) read_head_q <= read_head_q + 5'd1;
                case ({read_issue,returning})
                    2'b10: read_count_q <= read_count_q + 6'd1;
                    2'b01: read_count_q <= read_count_q - 6'd1;
                    default: ;
                endcase
            end
        end
    end
    // These flags describe the CURRENT count, not a delayed observation.
    // A simultaneous issue/return leaves occupancy and both flags unchanged.
    // No additional read credit or permission is created by this lookahead.
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            read_nonempty_q <= 1'b0;
            read_space_q <= 1'b1;
        end else begin
            case ({read_issue, returning})
                2'b10: begin
                    read_nonempty_q <= 1'b1;
                    read_space_q <= (read_count_q != 6'd31);
                end
                2'b01: begin
                    read_nonempty_q <= (read_count_q != 6'd1);
                    read_space_q <= 1'b1;
                end
                default: begin end
            endcase
        end
    end

    initial if (WATCHDOG_CYCLES < 4) $fatal(1,"invalid shared-DDR watchdog");

`ifdef FORMAL
    always_ff @(posedge clk) if (reset_n) begin
        assert (read_count_q <= 32);
        assert (!(model_fire && kv_fire));
        if (raw_req_valid_o) begin
            if (raw_req_write_o) assert (cmd_kv_q && cmd_word_q >= KV_BASE && cmd_word_q < KV_LIMIT);
            if (!cmd_kv_q) assert (!raw_req_write_o && cmd_word_q < MODEL_WORDS);
        end
        if (kv_rsp_valid_o) assert (kv_busy_q);
        if (returning_kv) assert (kv_busy_q && !kv_response_q);
        if (fault_o) assert (!raw_req_valid_o && !model_rsp_valid_o && !kv_rsp_valid_o);
    end
`endif
endmodule
`default_nettype wire

`timescale 1ns/1ps
`default_nettype none

// Private app-clock admission and return boundaries around the unchanged
// fixed-region owner arbiter. No clock crossing, new host port, model write,
// command type or read credit is introduced. CLEAR intentionally has no port:
// all accepted work keeps its owner until completion or the common reset.
// The model CDC reserves its existing 32 return credits at FRONT admission,
// and returns them only on core delivery, including every new pipeline slot.
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
    logic stop_q, lock_seen_q, kv_owner_q;
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
    assign kv_req_ready_o = admit_enabled && !kv_owner_q && kv_queue_ready;
    board1_ddr_request_fifo2 #(.ADDR_W(19)) u_model_admission (
        .clk(clk), .reset_n(reset_n), .abort_i(1'b0),
        .in_valid_i(model_req_valid_i && admit_enabled), .in_ready_o(model_queue_ready),
        .in_write_i(1'b0), .in_addr_i(model_req_word_i), .in_data_i(256'd0),
        .out_valid_o(model_queue_valid), .out_ready_i(model_backend_ready && !fault_o),
        .out_write_o(), .out_addr_o(model_queue_word), .out_data_o());
    board1_ddr_request_fifo2 #(.ADDR_W(19)) u_kv_admission (
        .clk(clk), .reset_n(reset_n), .abort_i(1'b0),
        .in_valid_i(kv_req_valid_i && admit_enabled && !kv_owner_q), .in_ready_o(kv_queue_ready),
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
    assign backend_kv_ready = !kv_return_valid_q && reset_n && !fault_o;
    assign kv_rsp_valid_o = kv_return_valid_q && reset_n && !fault_o;
    assign kv_rsp_data_o = kv_return_data_q;
    assign kv_rsp_error_o = kv_return_error_q;
    assign busy_o = backend_busy || model_queue_valid || kv_queue_valid ||
                    model_return_valid_q || kv_return_valid_q || kv_owner_q;
    always_ff @(posedge clk) begin
        model_return_data_q <= backend_model_data;
        if (!kv_return_valid_q) kv_return_data_q <= backend_kv_data;
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
            stop_q <= 1'b0; lock_seen_q <= 1'b0; kv_owner_q <= 1'b0;
            model_return_valid_q <= 1'b0; model_return_error_q <= 1'b0;
            kv_return_valid_q <= 1'b0; kv_return_error_q <= 1'b0;
        end else begin
            if (model_locked_i) lock_seen_q <= 1'b1;
            if (upstream_fault_i || backend_fault || frontend_fault) stop_q <= 1'b1;
            if (kv_admit) kv_owner_q <= 1'b1;
            if (kv_retire) kv_owner_q <= 1'b0;
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
        assert (!(kv_admit && kv_owner_q));
        if (kv_rsp_valid_o) assert (kv_owner_q);
        if (backend_kv_valid) assert (kv_owner_q);
        if (fault_o) assert (!model_req_ready_o && !kv_req_ready_o &&
                            !model_rsp_valid_o && !kv_rsp_valid_o && !raw_req_valid_o);
        if (upstream_fault_i) assert (!raw_req_valid_o);
    end
`endif
endmodule
`default_nettype wire
