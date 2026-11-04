`undef FORMAL
module board1_ddr_request_fifo2 #(
    parameter integer ADDR_W = 25
) (
    output wire [1:0] f_qcount_o,
    output wire f_qr_o,
    output wire f_qw_o,
    output wire [ADDR_W-1:0] f_q0_o,
    output wire [ADDR_W-1:0] f_q1_o,
    input  wire               clk,
    input  wire               reset_n,
    input  wire               abort_i,
    input  wire               in_valid_i,
    output wire               in_ready_o,
    input  wire               in_write_i,
    input  wire [ADDR_W-1:0]  in_addr_i,
    input  wire [255:0]       in_data_i,
    output wire               out_valid_o,
    input  wire               out_ready_i,
    output wire               out_write_o,
    output wire [ADDR_W-1:0]  out_addr_o,
    output wire [255:0]       out_data_o
);
    logic write_q [0:1];
    logic [ADDR_W-1:0] addr_q [0:1];
    logic [255:0] data_q [0:1];
    logic wr_ptr_q;
    logic rd_ptr_q;
    logic [1:0] count_q;

    wire push = in_valid_i && in_ready_o;
    wire pop = out_valid_o && out_ready_i;

    assign in_ready_o = (count_q != 2) && !abort_i;
    assign out_valid_o = (count_q != 0) && !abort_i;
    assign out_write_o = write_q[rd_ptr_q];
    assign out_addr_o = addr_q[rd_ptr_q];
    assign out_data_o = data_q[rd_ptr_q];

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            wr_ptr_q <= 1'b0;
            rd_ptr_q <= 1'b0;
            count_q <= 2'd0;
        end else if (abort_i) begin
            wr_ptr_q <= 1'b0;
            rd_ptr_q <= 1'b0;
            count_q <= 2'd0;
        end else begin
            case ({push, pop})
                2'b10: count_q <= count_q + 2'd1;
                2'b01: count_q <= count_q - 2'd1;
                default: begin
                end
            endcase
            if (push) begin
                write_q[wr_ptr_q] <= in_write_i;
                addr_q[wr_ptr_q] <= in_addr_i;
                data_q[wr_ptr_q] <= in_data_i;
                wr_ptr_q <= wr_ptr_q + 1'b1;
            end
            if (pop)
                rd_ptr_q <= rd_ptr_q + 1'b1;
        end
    end

`ifdef FORMAL
    always_ff @(posedge clk) begin
        if (reset_n) begin
            assert (count_q <= 2);
            if (abort_i)
                assert (!in_ready_o && !out_valid_o);
        end
    end
`endif
    assign f_qcount_o=count_q;
    assign f_qr_o=rd_ptr_q;
    assign f_qw_o=wr_ptr_q;
    assign f_q0_o=addr_q[0];
    assign f_q1_o=addr_q[1];
endmodule
module board1_private_shared_ddr_arbiter #(
    parameter integer WATCHDOG_CYCLES = 50000000
) (
    output wire [5:0] f_count_o,
    output wire [4:0] f_head_o,
    output wire [4:0] f_tail_o,
    output wire [31:0] f_owners_o,
    output wire f_nonempty_o,
    output wire f_space_o,
    output wire f_cmd_o,
    output wire f_cmdkv_o,
    output wire f_cmdwrite_o,
    output wire [18:0] f_word_o,
    output wire f_take_o,
    output wire f_issue_o,
    output wire f_return_o,
    output wire f_lock_o,
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
    assign f_count_o=read_count_q;
    assign f_head_o=read_head_q;
    assign f_tail_o=read_tail_q;
    assign f_owners_o=read_owner_q;
    assign f_nonempty_o=read_nonempty_q;
    assign f_space_o=read_space_q;
    assign f_cmd_o=cmd_valid_q;
    assign f_cmdkv_o=cmd_kv_q;
    assign f_cmdwrite_o=cmd_write_q;
    assign f_word_o=cmd_word_q;
    assign f_take_o=model_fire;
    assign f_issue_o=read_issue;
    assign f_return_o=returning;
    assign f_lock_o=lock_seen_q;
endmodule
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
    wire [1:0] f_qcount;
    wire f_qr;
    wire f_qw;
    wire [18:0] f_q0;
    wire [18:0] f_q1;
    wire [5:0] f_count;
    wire [4:0] f_head;
    wire [4:0] f_tail;
    wire [31:0] f_owners;
    wire f_nonempty;
    wire f_space;
    wire f_cmd;
    wire f_cmdkv;
    wire f_cmdwrite;
    wire [18:0] f_word;
    wire f_take;
    wire f_issue;
    wire f_return;
    wire f_lock;
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
        .f_qcount_o(f_qcount),
        .f_qr_o(f_qr),
        .f_qw_o(f_qw),
        .f_q0_o(f_q0),
        .f_q1_o(f_q1),

        .clk(clk), .reset_n(reset_n), .abort_i(1'b0),
        .in_valid_i(model_req_valid_i && admit_enabled), .in_ready_o(model_queue_ready),
        .in_write_i(1'b0), .in_addr_i(model_req_word_i), .in_data_i(256'd0),
        .out_valid_o(model_queue_valid), .out_ready_i(model_backend_ready && !fault_o),
        .out_write_o(), .out_addr_o(model_queue_word), .out_data_o());
    board1_ddr_request_fifo2 #(.ADDR_W(19)) u_kv_admission (
        .f_qcount_o(),
        .f_qr_o(),
        .f_qw_o(),
        .f_q0_o(),
        .f_q1_o(),

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
        .f_count_o(f_count),
        .f_head_o(f_head),
        .f_tail_o(f_tail),
        .f_owners_o(f_owners),
        .f_nonempty_o(f_nonempty),
        .f_space_o(f_space),
        .f_cmd_o(f_cmd),
        .f_cmdkv_o(f_cmdkv),
        .f_cmdwrite_o(f_cmdwrite),
        .f_word_o(f_word),
        .f_take_o(f_take),
        .f_issue_o(f_issue),
        .f_return_o(f_return),
        .f_lock_o(f_lock),

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
    (* anyconst *) reg [18:0] f_target;
    (* anyconst *) reg [255:0] f_model_word;
    (* anyconst *) reg [4:0] f_slot;
    reg [6:0] f_A,f_Q,f_I,f_R,f_D,f_J,f_Z;
    reg [18:0] f_addresses[0:63];
    reg [6:0] f_rank[0:31];
    reg f_record_seen,f_record_kv;
    reg [6:0] f_record_sequence,f_record_model;
    reg [18:0] f_record_address;
    reg f_front_watch;
    reg [6:0] f_point_sequence;
    reg [18:0] f_point_address;
    reg [255:0] f_point_word;
    wire f_raw_fire=raw_req_valid_o && raw_req_ready_i;
    wire f_model_issue=f_issue && !f_cmdkv;
    wire [6:0] f_pending=f_A-f_D;
    wire [6:0] f_debt=f_J-f_Z;
    wire [4:0] f_offset=f_slot-f_Z[4:0];
    wire f_live={2'd0,f_offset}<f_debt;
    wire f_alive=reset_n && !fault_o;
    wire[6:0]f_record_age=f_A-f_record_model;
    always @(posedge clk) begin
        if(model_admit)f_addresses[f_A[5:0]]<=model_req_word_i;
        if(f_issue)begin
            f_rank[f_tail]<=f_I;
            if(f_J[4:0]==f_slot)begin
                f_record_seen<=1;f_record_sequence<=f_J;
                f_record_model<=f_I;f_record_kv<=f_cmdkv;
                f_record_address<=raw_req_word_o[18:0];
            end
        end
        if(backend_model_valid && f_head==f_slot)begin
            f_point_sequence<=f_R;f_point_address<=f_record_address;
            f_point_word<=raw_rsp_data_i;
        end
    end
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            f_A<=0;f_Q<=0;f_I<=0;f_R<=0;f_D<=0;f_J<=0;f_Z<=0;f_front_watch<=0;
        end else begin
            if(model_admit)f_A<=f_A+1'b1;
            if(f_take)f_Q<=f_Q+1'b1;
            if(f_model_issue)f_I<=f_I+1'b1;
            if(backend_model_valid)f_R<=f_R+1'b1;
            if(model_rsp_valid_o)f_D<=f_D+1'b1;
            if(f_issue)f_J<=f_J+1'b1;
            if(raw_rsp_valid_i)f_Z<=f_Z+1'b1;
            f_front_watch<=backend_model_valid && f_head==f_slot;
        end
    end
    // Conditional normalized lower producer, to be discharged by the native
    // adapter/handoff and physical-transport composition. Model memory is M;
    // K/V replies are unrestricted and cannot acquire model ownership.
    always @(posedge clk) if(reset_n && raw_rsp_valid_i && !raw_rsp_error_i) begin
        assume(f_debt!=0);
        if(f_Z[4:0]==f_slot && f_record_address==f_target && f_target<19'd227062)
            assume(raw_rsp_data_i==f_model_word);
    end
    always @*if(f_alive)begin
        if(f_cmd || f_count!=0 || f_pending!=0)assert(f_lock);
        assert(f_count<=32);
        assert(f_nonempty==(f_count!=0));assert(f_space==(f_count<32));
        assert(f_head==f_Z[4:0]);assert(f_tail==f_J[4:0]);
        assert(f_debt=={1'b0,f_count});
        assert(f_A-f_Q=={5'd0,f_qcount});assert(f_qcount<=2);
        assert(f_qr==f_Q[0]);assert(f_qw==f_A[0]);
        assert(f_Q-f_I=={6'd0,(f_cmd && !f_cmdkv)});
        assert(f_R-f_D=={6'd0,model_return_valid_q});
        assert(f_I-f_R<={1'b0,f_count});assert(f_pending<=36);
        if(f_qcount!=0)begin
            assert((f_qr ? f_q1:f_q0)==f_addresses[f_Q[5:0]]);
        end
        if(f_qcount==2)assert((f_qr ? f_q0:f_q1)==f_addresses[(f_Q+7'd1)&7'd63]);
        if(f_cmd && !f_cmdkv)begin
            assert(!f_cmdwrite);
            assert(f_word==f_addresses[f_I[5:0]]);
            assert(f_word<19'd227062);
        end
        if(f_count!=0) assert(f_rank[f_head]==f_R);
        else assert(f_I==f_R);
        if(f_live)begin
            assert(f_record_seen);
            assert(f_record_sequence==f_Z+{2'd0,f_offset});
            assert(f_record_kv==f_owners[f_slot]);
            assert(f_record_model==f_rank[f_slot]);
            if(!f_record_kv)begin
                assert(f_record_address==f_addresses[f_record_model[5:0]]);
                assert(f_record_address<19'd227062);
                assert(f_record_age<=7'd35 && f_record_age!=0);
            end
        end
        if(f_issue && f_J[4:0]==f_slot)assert(!f_live || raw_rsp_valid_i);
        if(f_front_watch)begin
            assert(model_return_valid_q);
            assert(f_point_sequence==f_D);
            assert(f_point_address==f_addresses[f_D[5:0]]);
            assert(f_point_address<19'd227062);
            assert(model_rsp_data_o==f_point_word);
            if(f_point_address==f_target && f_target<19'd227062)assert(f_point_word==f_model_word);
        end
        if(model_rsp_valid_o)assert(f_pending!=0 && !model_rsp_error_o);
    end
    for(genvar j=0;j<32;j=j+1)begin:f_rows
        wire[4:0]f_off=5'(j)-f_head;
        wire[5:0]f_left=f_count-{1'b0,f_off};
        wire[6:0]f_after=f_rank[j]+{6'd0,!f_owners[j]};
        always @*if(f_alive && {1'b0,f_off}<f_count)begin
            if(f_left>1)assert(f_rank[(j+1)%32]==f_after);
            else assert(f_I==f_after);
            assert(f_I-f_rank[j]<={1'b0,f_left});
            if(!f_owners[j])assert(f_I-f_rank[j]!=0);
        end
    end
    always @(posedge clk)if(f_alive && raw_rsp_valid_i && !raw_rsp_error_i && f_Z[4:0]==f_slot)begin
        assert(f_live);assert(f_record_sequence==f_Z);
        if(backend_model_valid)begin
            assert(!f_record_kv);assert(f_record_model==f_R);
            assert(f_record_address==f_addresses[f_R[5:0]]);
        end
    end

    // Native response VALID has one register stage. Capture the actual raw
    // owner-ring slot at that same backend model-return event, independently
    // of the arbitrary watched slot. No circuit input or producer is driven.
    (* keep *) reg[4:0]f_model_return_origin_slot;
    always @(posedge clk)if(backend_model_valid)
        f_model_return_origin_slot<=f_head;

endmodule
