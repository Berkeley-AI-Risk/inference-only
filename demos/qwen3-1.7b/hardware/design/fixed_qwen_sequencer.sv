// Fixed Qwen3-1.7B token controller and operation sequencer.
//
// The cmd/response ports are the intended application boundary. The op/core
// ports are PRIVATE integration ports: they must never be host-mapped. This
// module does not implement the numerical engine, authenticated memory, or the
// AWS shell. Unit tests use a mock engine and do not establish full inference.
//
// OP contract: one request at a time; completion is accepted only after request
// acceptance. All tensor routing/dimensions follow opcode/layer below. No
// programmable operation, tensor address, or arithmetic operand enters cmd.
// core_abort stays high until every old operation/memory response is drained
// or cancelled and all K/V validity is reset (core_quiescent). Merely being
// idle is NOT sufficient to assert core_quiescent during abort.
module fixed_qwen_sequencer #(
    parameter integer CAPACITY = 32768
) (
    input  wire clk,
    input  wire rst_n,
    input  wire model_ready,
    input  wire cmd_valid,input wire cmd_clear_valid,
    output wire cmd_ready,
    input  wire [7:0] cmd_opcode, // 1 APPEND, 2 STEP, 3 CLEAR; all others rejected
    input  wire [31:0] cmd_token, // Must be zero for STEP/CLEAR
    output wire response_valid,
    input  wire response_ready,
    output reg [3:0] response_status,
    output reg [31:0] response_token, // Only a successful STEP returns a token
    output wire busy,

    output wire op_valid,
    input  wire op_ready,
    output reg [4:0] op_code,
    output reg [4:0] op_layer,
    output wire [14:0] op_position,
    output wire [17:0] op_token, // Embedding lookup only; internal token RAM
    input  wire core_done,
    input  wire core_error,
    input  wire [31:0] core_next_token, // Used only for the fixed ARGMAX operation
    output wire core_abort,
    input  wire core_quiescent
);
    localparam [7:0] APPEND=1, STEP=2, CLEAR=3;
    localparam [3:0] OK=0, BAD_COMMAND=1, BAD_TOKEN=2, EMPTY=3,
                     FULL=4, NOT_READY=5, EXECUTION_FAULT=6;
    // For each token: EMBED; 28 repetitions of INPUT_NORM..MLP_RESIDUAL.
    // Only the final pending token needs FINAL_NORM, HEAD, ARGMAX.
    localparam [4:0] EMBED=0, INPUT_NORM=1, MLP_RESIDUAL=20,
                     FINAL_NORM=21, ARGMAX=23;
    localparam [2:0] IDLE=0, FETCH=1, ISSUE=2, WAIT_DONE=3, ABORTING=4;
    localparam [15:0] LIMIT = 16'(CAPACITY);
    reg [2:0] state;
    reg [15:0] tape_count, processed_count;
    reg [17:0] tape_read;
    (* ram_style = "block" *) reg [17:0] tape [0:CAPACITY-1];
    reg reply_pending, clear_reply, faulted;
    wire valid_clear = cmd_opcode == CLEAR && cmd_token == 0;
    wire clear_accept = rst_n && cmd_clear_valid && cmd_ready;
    wire command_accept = cmd_valid && cmd_ready;
    wire append_accept = command_accept && !valid_clear && cmd_opcode == APPEND
                          && !faulted && cmd_token < 32'd151936 && tape_count < LIMIT;
    wire generated_accept = state == WAIT_DONE && op_code == ARGMAX && core_done
                            && !core_error && model_ready && core_next_token < 32'd151936
                            && !clear_accept;

    initial begin
        if (CAPACITY < 2 || CAPACITY > 32768)
            $fatal(1, "Invalid fixed Qwen context capacity");
    end

    assign cmd_ready = rst_n && ((valid_clear && state != ABORTING)
                         || (state == IDLE && !reply_pending));
    // An accepted CLEAR invalidates even a queued, unread response. A stale
    // STEP result must not be consumed in the same cycle as that CLEAR.
    assign response_valid = rst_n && reply_pending && !clear_accept;
    assign busy = state != IDLE;
    assign op_valid = rst_n && state == ISSUE && !clear_accept && model_ready;
    assign op_position = processed_count[14:0];
    assign op_token = tape_read;
    // CLEAR immediately suppresses responses and new operation requests
    // above, and wins the state/tape update below. Cancel PRIVATE execution
    // from the resulting ABORTING register, not from the 40-bit command
    // decode. A coincident old private completion cannot update the tape or
    // become a response. Do not acknowledge CLEAR until core_quiescent.
    assign core_abort = !rst_n || state == ABORTING;

    // Single synchronous read / single write. Reset invalidates counts instead
    // of resetting the RAM array, allowing actual block RAM inference.
    always @(posedge clk) begin
        if (rst_n) begin
            tape_read <= tape[processed_count[14:0]];
            if (append_accept)
                tape[tape_count[14:0]] <= cmd_token[17:0];
            else if (generated_accept)
                tape[tape_count[14:0]] <= core_next_token[17:0];
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= ABORTING;
            tape_count <= 0;
            processed_count <= 0;
            op_code <= EMBED;
            op_layer <= 0;
            reply_pending <= 0;
            response_status <= OK;
            response_token <= 0;
            clear_reply <= 0;
            faulted <= 0;
        end else if (clear_accept) begin
            state <= ABORTING;
            tape_count <= 0;
            processed_count <= 0;
            op_code <= EMBED;
            op_layer <= 0;
            reply_pending <= 0;
            response_status <= OK;
            response_token <= 0;
            clear_reply <= 1;
            faulted <= 0;
        end else begin
            if (response_valid && response_ready)
                reply_pending <= 0;
            if (state == ABORTING) begin
                if (core_quiescent) begin
                    state <= IDLE;
                    reply_pending <= clear_reply;
                    clear_reply <= 0;
                end
            end else if (state != IDLE && !model_ready) begin
                // No further arithmetic after model-integrity failure. The
                // pending operation must be flushed before acknowledging it.
                state <= ABORTING;
                clear_reply <= 1;
                response_status <= EXECUTION_FAULT;
                response_token <= 0;
                faulted <= 1;
            end else if (state == IDLE && command_accept) begin
                response_status <= OK;
                response_token <= 0;
                reply_pending <= 1;
                if (faulted) begin
                    response_status <= EXECUTION_FAULT;
                end else if (cmd_opcode == APPEND) begin
                    if (cmd_token >= 32'd151936)
                        response_status <= BAD_TOKEN;
                    else if (tape_count == LIMIT)
                        response_status <= FULL;
                    else
                        tape_count <= tape_count+1'b1;
                end else if (cmd_opcode == STEP && cmd_token == 0) begin
                    if (!model_ready)
                        response_status <= NOT_READY;
                    else if (tape_count == 0)
                        response_status <= EMPTY;
                    else if (tape_count == LIMIT)
                        response_status <= FULL;
                    else begin
                        state <= FETCH;
                        op_code <= EMBED;
                        op_layer <= 0;
                        reply_pending <= 0;
                    end
                end else begin
                    response_status <= BAD_COMMAND;
                end
            end else if (state == FETCH) begin
                state <= ISSUE;
            end else if (state == ISSUE && op_ready) begin
                state <= WAIT_DONE;
            end else if (state == WAIT_DONE && core_done) begin
                if (core_error || (op_code == ARGMAX && core_next_token >= 32'd151936)) begin
                    state <= ABORTING;
                    clear_reply <= 1;
                    response_status <= EXECUTION_FAULT;
                    response_token <= 0;
                    faulted <= 1;
                end else if (op_code == ARGMAX) begin
                    state <= IDLE;
                    processed_count <= tape_count;
                    tape_count <= tape_count+1'b1;
                    reply_pending <= 1;
                    response_status <= OK;
                    response_token <= core_next_token;
                end else if (op_code == MLP_RESIDUAL) begin
                    if (op_layer < 27) begin
                        op_layer <= op_layer+1'b1;
                        op_code <= INPUT_NORM;
                        state <= ISSUE;
                    end else if (processed_count+1'b1 < tape_count) begin
                        processed_count <= processed_count+1'b1;
                        op_layer <= 0;
                        op_code <= EMBED;
                        state <= FETCH;
                    end else begin
                        op_code <= FINAL_NORM;
                        state <= ISSUE;
                    end
                end else begin
                    op_code <= op_code+1'b1;
                    state <= ISSUE;
                end
            end
        end
    end
endmodule
