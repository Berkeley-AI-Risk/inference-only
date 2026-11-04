`undef FORMAL
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
    // Reserve a response slot at admission, not when DDR returns. This
    // bounded window includes queued commands, raw reads and held responses.
    localparam integer KV_CREDITS = 8;
    logic [3:0] kv_reserved_q, kv_response_count_q;
    logic [2:0] kv_response_head_q, kv_response_tail_q;
    logic [255:0] kv_response_data_q [0:KV_CREDITS-1];
    logic kv_write_owner_q;
    wire kv_busy_q = kv_reserved_q != 0;
    wire kv_response_q = kv_response_count_q != 0;
    wire kv_retire = kv_rsp_valid_o && kv_rsp_ready_i;
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
    // Writes remain exclusive through completion delivery. Consequently a
    // write completion cannot overtake earlier K/V reads in the response FIFO.
    wire kv_capacity = kv_reserved_q < 4'd8 && !kv_write_owner_q &&
                       (!kv_req_write_i || kv_reserved_q == 0);
    wire want_kv = kv_req_valid_i && kv_capacity;
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
    assign kv_rsp_data_o = kv_response_data_q[kv_response_head_q];
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
        if (returning_kv || (raw_fire && cmd_write_q))
            kv_response_data_q[kv_response_tail_q] <= returning_kv ? raw_rsp_data_i : 256'd0;
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
            kv_reserved_q <= 0; kv_response_count_q <= 0;
            kv_response_head_q <= 0; kv_response_tail_q <= 0;
            kv_write_owner_q <= 0;
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
                if (kv_retire) begin
                    kv_response_head_q <= kv_response_head_q + 3'd1;
                    if (kv_write_owner_q) kv_write_owner_q <= 0;
                end
                if (kv_fire && kv_req_write_i) kv_write_owner_q <= 1;
                case ({kv_fire,kv_retire})
                    2'b10: kv_reserved_q <= kv_reserved_q + 4'd1;
                    2'b01: kv_reserved_q <= kv_reserved_q - 4'd1;
                    default: ;
                endcase
                if (returning_kv || (raw_fire && cmd_write_q))
                    kv_response_tail_q <= kv_response_tail_q + 3'd1;
                case ({returning_kv || (raw_fire && cmd_write_q),kv_retire})
                    2'b10: kv_response_count_q <= kv_response_count_q + 4'd1;
                    2'b01: kv_response_count_q <= kv_response_count_q - 4'd1;
                    default: ;
                endcase
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
        assert (kv_reserved_q <= KV_CREDITS);
        assert (kv_response_count_q <= kv_reserved_q);
        assert (!(returning_kv && raw_fire && cmd_write_q));
        if (returning_kv) assert (kv_busy_q && !kv_write_owner_q);
        if (fault_o) assert (!raw_req_valid_o && !model_rsp_valid_o && !kv_rsp_valid_o);
    end
`endif
endmodule
