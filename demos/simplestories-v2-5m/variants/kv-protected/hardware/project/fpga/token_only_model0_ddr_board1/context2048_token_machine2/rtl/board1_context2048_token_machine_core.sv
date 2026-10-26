`timescale 1ns/1ps
`default_nettype none

// Complete clock-domain core of the deterministic fixed-model token machine.
// The only application operations are APPEND(token), STEP, and CLEAR.  The
// normalized DDR channel below is integration-private and must terminate at
// board1_ddr_preboard_locked_boundary inside the physical product wrapper.
module board1_context2048_token_machine_core #(
    parameter integer ADDR_W = 19,
    parameter integer MODEL_WORDS = 227062,
    parameter integer MAX_NO_PROGRESS_CYCLES = 100_000_000,
    parameter NORM_ROM_FILE = "fpga/token_only_model0_ddr_board1/fixed_vector_rmsnorm0/recorded/norm_rom34.memh"
) (
    input  wire                    clk,
    input  wire                    reset_n,
    input  wire                    clear_i,
    input  wire                    model_locked_i,
    input  wire                    upstream_fail_closed_i,

    input  wire                    append_valid_i,
    output logic                   append_ready_o,
    input  wire [11:0]             append_token_i,
    input  wire                    step_valid_i,
    output logic                   step_ready_o,
    output logic                   token_valid_o,
    input  wire                    token_ready_i,
    output logic [11:0]            token_o,

    output logic                   private_runtime_req_valid_o,
    input  wire                    private_runtime_req_ready_i,
    output logic [ADDR_W-1:0]      private_runtime_req_word_index_o,
    input  wire                    private_runtime_rsp_valid_i,
    output logic                   private_runtime_rsp_ready_o,
    input  wire [255:0]            private_runtime_rsp_data_i,
    input  wire                    private_runtime_rsp_fault_i,

    output logic                   kv_write_req_valid_o,
    input  wire                    kv_write_req_ready_i,
    output logic [2:0]             kv_write_req_layer_o,
    output logic [11:0]            kv_write_req_position_o,
    output logic [1:0]             kv_write_req_head_o,
    output logic [3:0]             kv_write_req_row_word_o,
    output logic [18:0]            kv_write_req_shadow_address_o,
    output logic [255:0]           kv_write_req_data_o,
    input  wire                    kv_write_cpl_valid_i,
    output logic                   kv_write_cpl_ready_o,
    input  wire                    kv_write_cpl_fault_i,
    output logic                   kv_read_req_valid_o,
    input  wire                    kv_read_req_ready_i,
    output logic [2:0]             kv_read_req_layer_o,
    output logic [11:0]            kv_read_req_position_o,
    output logic [1:0]             kv_read_req_head_o,
    output logic [3:0]             kv_read_req_row_word_o,
    output logic [18:0]            kv_read_req_shadow_address_o,
    input  wire                    kv_read_rsp_valid_i,
    output logic                   kv_read_rsp_ready_o,
    input  wire [255:0]            kv_read_rsp_data_i,
    input  wire                    kv_read_rsp_fault_i,
    input  wire                    kv_endpoint_fault_i,

    output logic                   busy_o,
    output logic                   model_locked_o,
    output logic                   fail_closed_o
);
    // The DDR/authentication boundary starts unlocked.  Keep every model
    // arithmetic child in reset until the set-only lock has been stable for
    // two clocks; this prevents idle arithmetic blocks from interpreting the
    // normal boot interval as a lock-loss attack.
    logic [1:0] machine_release_q;
    wire machine_active = machine_release_q[1];
    wire child_reset_n = reset_n && machine_active;

    wire shell_append_ready;
    wire shell_step_ready;
    wire shell_token_valid;
    wire [11:0] shell_token;
    wire shell_busy;
    wire shell_model_locked;
    wire shell_fail;
    wire shell_terminal_latched;

    wire shell_ddr_req_valid;
    wire shell_ddr_req_ready;
    wire [ADDR_W-1:0] shell_ddr_req_index;
    wire shell_ddr_rsp_valid;
    wire shell_ddr_rsp_ready;
    wire [255:0] shell_ddr_rsp_data;
    wire shell_ddr_rsp_fault;

    wire layer_clear;
    wire layer_start_valid;
    wire layer_start_ready;
    wire [10:0] layer_position;
    wire signed [7:0] layer_input_exponent;
    wire layer_input_valid;
    wire layer_input_ready;
    wire [7:0] layer_input_index;
    wire signed [15:0] layer_input_mantissa;
    wire layer_input_last;
    wire layer_result_valid;
    wire layer_result_ready;
    wire [7:0] layer_result_index;
    wire signed [15:0] layer_result_mantissa;
    wire signed [7:0] layer_result_exponent;
    wire layer_result_last;
    wire layer_done_valid;
    wire layer_done_ready;
    wire [71:0] layer_committed_prefixes;
    wire layer_busy;
    wire layer_fail;

    // Private fixed tied-head stream.  The shell derives the sole request
    // after final RMSNorm; the semantic block hardwires it to layer 7/job 7
    // on the same projection array used sequentially by layers 0..5.
    wire head_start_valid;
    wire head_start_ready;
    wire signed [7:0] head_activation_exponent;
    wire head_activation_valid;
    wire head_activation_ready;
    wire [7:0] head_activation_index;
    wire signed [15:0] head_activation_mantissa;
    wire head_activation_last;
    wire head_result_valid;
    wire head_result_ready;
    wire [12:0] head_result_row_index;
    wire signed [49:0] head_result_scaled_raw;
    wire signed [7:0] head_result_source_exponent;
    wire head_result_last;
    wire head_done_valid;
    wire head_done_ready;

    wire layer_ddr_req_valid;
    wire layer_ddr_req_ready;
    wire [ADDR_W-1:0] layer_ddr_req_index;
    wire layer_ddr_rsp_valid;
    wire layer_ddr_rsp_ready;
    wire [255:0] layer_ddr_rsp_data;
    wire layer_ddr_rsp_fault;

    wire arbiter_busy;
    wire arbiter_fail;
    // A terminal global fault is contained here immediately. It need not
    // traverse the arithmetic hierarchy to stop observable work. The original
    // set-only arbiter fault and machine_release_q reset sequence remain.
    // Only the shell's registered sticky bit enters this new root gate.
    // Feeding combinational child fault back into K/V VALID could loop.
    wire root_terminal = upstream_fail_closed_i || arbiter_fail ||
                         (machine_active && shell_terminal_latched);
    wire child_upstream_fault = 1'b0;
    wire child_kv_write_req_valid, child_kv_write_req_ready;
    wire child_kv_write_cpl_valid, child_kv_write_cpl_ready;
    wire child_kv_read_req_valid, child_kv_read_req_ready;
    wire child_kv_read_rsp_valid, child_kv_read_rsp_ready;
    assign kv_write_req_valid_o = !root_terminal && child_kv_write_req_valid;
    assign child_kv_write_req_ready = !root_terminal && kv_write_req_ready_i;
    assign child_kv_write_cpl_valid = !root_terminal && kv_write_cpl_valid_i;
    assign kv_write_cpl_ready_o = root_terminal || child_kv_write_cpl_ready;
    assign kv_read_req_valid_o = !root_terminal && child_kv_read_req_valid;
    assign child_kv_read_req_ready = !root_terminal && kv_read_req_ready_i;
    assign child_kv_read_rsp_valid = !root_terminal && kv_read_rsp_valid_i;
    assign kv_read_rsp_ready_o = root_terminal || child_kv_read_rsp_ready;
    // Only private request/reply handshakes change after terminal closure.
    // Payload fields remain meaningful only with VALID. Replies drain/discard;
    // no new model or typed K/V request is admitted. CLEAR cannot revive a fault.
    wire aggregate_fail = upstream_fail_closed_i || arbiter_fail ||
                          (machine_active && (shell_fail || layer_fail));

    // Only retirements which the fixed owners actually consume may refresh
    // the shell's no-forward-progress interval.  In particular, raw valid,
    // ready alone, request presentation, an unowned model response, a
    // fault-tagged completion/response, and malformed K/V padding do not
    // qualify.  The owner FIFO and typed K/V FSMs make each qualifying pulse
    // consume one outstanding operation and advance a bounded fixed schedule.
    wire owned_model_response_retire = machine_active && model_locked_i &&
        !clear_i && !aggregate_fail && arbiter_busy &&
        private_runtime_rsp_valid_i && private_runtime_rsp_ready_o &&
        !private_runtime_rsp_fault_i;
    wire typed_kv_write_retire = machine_active && model_locked_i &&
        !clear_i && !aggregate_fail && !kv_endpoint_fault_i &&
        kv_write_cpl_valid_i && kv_write_cpl_ready_o &&
        !kv_write_cpl_fault_i;
    wire typed_kv_padding_legal =
        (kv_read_req_row_word_o != 4'd8) ||
        (kv_read_rsp_data_i[255:16] == 240'd0);
    wire typed_kv_read_retire = machine_active && model_locked_i &&
        !clear_i && !aggregate_fail && !kv_endpoint_fault_i &&
        kv_read_rsp_valid_i && kv_read_rsp_ready_o &&
        !kv_read_rsp_fault_i && typed_kv_padding_legal;
    wire verified_private_retire = owned_model_response_retire ||
                                   typed_kv_write_retire ||
                                   typed_kv_read_retire;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            machine_release_q <= 2'b00;
        else if (!model_locked_i || root_terminal)
            machine_release_q <= 2'b00;
        else
            machine_release_q <= {machine_release_q[0], 1'b1};
    end

    board1_context2048_token_shell #(
        .ADDR_W(ADDR_W),
        .MAX_NO_PROGRESS_CYCLES(MAX_NO_PROGRESS_CYCLES),
        .NORM_ROM_FILE(NORM_ROM_FILE)
    ) u_token_shell (
        .clk(clk), .rst_n(child_reset_n),
        .clear_i(clear_i && machine_active),
        .model_lock_i(model_locked_i),
        .upstream_fault_i(child_upstream_fault),
        .private_verified_retire_i(verified_private_retire),
        .append_valid_i(append_valid_i && machine_active),
        .append_ready_o(shell_append_ready),
        .append_token_i(append_token_i),
        .step_valid_i(step_valid_i && machine_active),
        .step_ready_o(shell_step_ready),
        .token_valid_o(shell_token_valid),
        .token_ready_i(token_ready_i && machine_active),
        .token_o(shell_token), .busy_o(shell_busy),
        .model_locked_o(shell_model_locked),
        .fail_closed_o(shell_fail),
        .private_terminal_latched_o(shell_terminal_latched),
        .private_word_req_valid_o(shell_ddr_req_valid),
        .private_word_req_ready_i(shell_ddr_req_ready),
        .private_word_req_index_o(shell_ddr_req_index),
        .private_word_rsp_valid_i(shell_ddr_rsp_valid),
        .private_word_rsp_ready_o(shell_ddr_rsp_ready),
        .private_word_rsp_data_i(shell_ddr_rsp_data),
        .private_word_rsp_fault_i(shell_ddr_rsp_fault),
        .private_layer_clear_o(layer_clear),
        .private_layer_start_valid_o(layer_start_valid),
        .private_layer_start_ready_i(layer_start_ready),
        .private_layer_position_o(layer_position),
        .private_layer_input_exponent_o(layer_input_exponent),
        .private_layer_input_valid_o(layer_input_valid),
        .private_layer_input_ready_i(layer_input_ready),
        .private_layer_input_index_o(layer_input_index),
        .private_layer_input_mantissa_o(layer_input_mantissa),
        .private_layer_input_last_o(layer_input_last),
        .private_layer_result_valid_i(layer_result_valid),
        .private_layer_result_ready_o(layer_result_ready),
        .private_layer_result_index_i(layer_result_index),
        .private_layer_result_mantissa_i(layer_result_mantissa),
        .private_layer_result_exponent_i(layer_result_exponent),
        .private_layer_result_last_i(layer_result_last),
        .private_layer_done_valid_i(layer_done_valid),
        .private_layer_done_ready_o(layer_done_ready),
        .private_layer_committed_prefixes_i(layer_committed_prefixes),
        .private_layer_busy_i(layer_busy),
        .private_layer_fault_i(layer_fail),
        .private_head_start_valid_o(head_start_valid),
        .private_head_start_ready_i(head_start_ready),
        .private_head_activation_exponent_o(head_activation_exponent),
        .private_head_activation_valid_o(head_activation_valid),
        .private_head_activation_ready_i(head_activation_ready),
        .private_head_activation_index_o(head_activation_index),
        .private_head_activation_mantissa_o(head_activation_mantissa),
        .private_head_activation_last_o(head_activation_last),
        .private_head_result_valid_i(head_result_valid),
        .private_head_result_ready_o(head_result_ready),
        .private_head_result_row_index_i(head_result_row_index),
        .private_head_result_scaled_raw_i(head_result_scaled_raw),
        .private_head_result_source_exponent_i(
            head_result_source_exponent),
        .private_head_result_last_i(head_result_last),
        .private_head_done_valid_i(head_done_valid),
        .private_head_done_ready_o(head_done_ready)
    );

    board1_context2048_semantic_layer #(.ADDR_W(ADDR_W)) u_six_layers (
        .clk(clk), .rst_n(child_reset_n), .clear_i(layer_clear),
        .model_lock_i(model_locked_i),
        .upstream_fault_i(child_upstream_fault),
        .private_head_start_valid_i(head_start_valid),
        .private_head_start_ready_o(head_start_ready),
        .private_head_activation_exponent_i(head_activation_exponent),
        .private_head_activation_valid_i(head_activation_valid),
        .private_head_activation_ready_o(head_activation_ready),
        .private_head_activation_index_i(head_activation_index),
        .private_head_activation_mantissa_i(head_activation_mantissa),
        .private_head_activation_last_i(head_activation_last),
        .private_head_result_valid_o(head_result_valid),
        .private_head_result_ready_i(head_result_ready),
        .private_head_result_row_index_o(head_result_row_index),
        .private_head_result_scaled_raw_o(head_result_scaled_raw),
        .private_head_result_source_exponent_o(
            head_result_source_exponent),
        .private_head_result_last_o(head_result_last),
        .private_head_done_valid_o(head_done_valid),
        .private_head_done_ready_i(head_done_ready),
        .start_valid_i(layer_start_valid),
        .start_ready_o(layer_start_ready),
        .fixed_position_i(layer_position),
        .input_exponent_i(layer_input_exponent),
        .input_valid_i(layer_input_valid),
        .input_ready_o(layer_input_ready),
        .input_index_i(layer_input_index),
        .input_mantissa_i(layer_input_mantissa),
        .input_last_i(layer_input_last),
        .result_valid_o(layer_result_valid),
        .result_ready_i(layer_result_ready),
        .result_index_o(layer_result_index),
        .result_mantissa_o(layer_result_mantissa),
        .result_exponent_o(layer_result_exponent),
        .result_last_o(layer_result_last),
        .done_valid_o(layer_done_valid),
        .done_ready_i(layer_done_ready),
        .private_word_req_valid_o(layer_ddr_req_valid),
        .private_word_req_ready_i(layer_ddr_req_ready),
        .private_word_req_index_o(layer_ddr_req_index),
        .private_word_rsp_valid_i(layer_ddr_rsp_valid),
        .private_word_rsp_ready_o(layer_ddr_rsp_ready),
        .private_word_rsp_data_i(layer_ddr_rsp_data),
        .private_word_rsp_fault_i(layer_ddr_rsp_fault),
        .kv_write_req_valid_o(child_kv_write_req_valid),
        .kv_write_req_ready_i(child_kv_write_req_ready),
        .kv_write_req_layer_o(kv_write_req_layer_o),
        .kv_write_req_position_o(kv_write_req_position_o),
        .kv_write_req_head_o(kv_write_req_head_o),
        .kv_write_req_row_word_o(kv_write_req_row_word_o),
        .kv_write_req_shadow_address_o(
            kv_write_req_shadow_address_o),
        .kv_write_req_data_o(kv_write_req_data_o),
        .kv_write_cpl_valid_i(child_kv_write_cpl_valid),
        .kv_write_cpl_ready_o(child_kv_write_cpl_ready),
        .kv_write_cpl_fault_i(kv_write_cpl_fault_i),
        .kv_read_req_valid_o(child_kv_read_req_valid),
        .kv_read_req_ready_i(child_kv_read_req_ready),
        .kv_read_req_layer_o(kv_read_req_layer_o),
        .kv_read_req_position_o(kv_read_req_position_o),
        .kv_read_req_head_o(kv_read_req_head_o),
        .kv_read_req_row_word_o(kv_read_req_row_word_o),
        .kv_read_req_shadow_address_o(kv_read_req_shadow_address_o),
        .kv_read_rsp_valid_i(child_kv_read_rsp_valid),
        .kv_read_rsp_ready_o(child_kv_read_rsp_ready),
        .kv_read_rsp_data_i(kv_read_rsp_data_i),
        .kv_read_rsp_fault_i(kv_read_rsp_fault_i),
        .kv_endpoint_fault_i(kv_endpoint_fault_i),
        .committed_prefixes_o(layer_committed_prefixes),
        .busy_o(layer_busy), .range_fault_o(layer_fail)
    );

    // Registered private model-request and response boundaries, one pair
    // per immutable owner. Neither READY path crosses the owner arbiter.
    // CLEAR is NOT an abort: locally accepted requests still drain to their
    // original child. Terminal child reset can discard these local queues,
    // but never resets the external arbiter's already-issued owner FIFO.
    wire shell_queued_req_valid, shell_queued_req_ready;
    wire [ADDR_W-1:0] shell_queued_req_index;
    wire shell_queued_rsp_valid, shell_queued_rsp_ready, shell_queued_rsp_fault;
    wire [255:0] shell_queued_rsp_data;
    board1_ddr_request_fifo2 #(.ADDR_W(ADDR_W)) u_shell_model_request_queue (
        .clk(clk), .reset_n(child_reset_n), .abort_i(1'b0),
        .in_valid_i(shell_ddr_req_valid), .in_ready_o(shell_ddr_req_ready),
        .in_write_i(1'b0), .in_addr_i(shell_ddr_req_index), .in_data_i(256'd0),
        .out_valid_o(shell_queued_req_valid), .out_ready_i(shell_queued_req_ready && !clear_i),
        .out_write_o(), .out_addr_o(shell_queued_req_index), .out_data_o());
    board1_ddr_request_fifo2 #(.ADDR_W(1)) u_shell_model_response_queue (
        .clk(clk), .reset_n(child_reset_n), .abort_i(1'b0),
        .in_valid_i(shell_queued_rsp_valid), .in_ready_o(shell_queued_rsp_ready),
        .in_write_i(shell_queued_rsp_fault), .in_addr_i(1'b0), .in_data_i(shell_queued_rsp_data),
        .out_valid_o(shell_ddr_rsp_valid), .out_ready_i(shell_ddr_rsp_ready),
        .out_write_o(shell_ddr_rsp_fault), .out_addr_o(), .out_data_o(shell_ddr_rsp_data));

    wire layer_queued_req_valid, layer_queued_req_ready;
    wire [ADDR_W-1:0] layer_queued_req_index;
    wire layer_queued_rsp_valid, layer_queued_rsp_ready, layer_queued_rsp_fault;
    wire [255:0] layer_queued_rsp_data;
    board1_ddr_request_fifo2 #(.ADDR_W(ADDR_W)) u_layer_model_request_queue (
        .clk(clk), .reset_n(child_reset_n), .abort_i(1'b0),
        .in_valid_i(layer_ddr_req_valid), .in_ready_o(layer_ddr_req_ready),
        .in_write_i(1'b0), .in_addr_i(layer_ddr_req_index), .in_data_i(256'd0),
        .out_valid_o(layer_queued_req_valid), .out_ready_i(layer_queued_req_ready && !clear_i),
        .out_write_o(), .out_addr_o(layer_queued_req_index), .out_data_o());
    board1_ddr_request_fifo2 #(.ADDR_W(1)) u_layer_model_response_queue (
        .clk(clk), .reset_n(child_reset_n), .abort_i(1'b0),
        .in_valid_i(layer_queued_rsp_valid), .in_ready_o(layer_queued_rsp_ready),
        .in_write_i(layer_queued_rsp_fault), .in_addr_i(1'b0), .in_data_i(layer_queued_rsp_data),
        .out_valid_o(layer_ddr_rsp_valid), .out_ready_i(layer_ddr_rsp_ready),
        .out_write_o(layer_ddr_rsp_fault), .out_addr_o(), .out_data_o(layer_ddr_rsp_data));

    board1_fixed_private_ddr_arbiter #(
        .ADDR_W(ADDR_W), .MODEL_WORDS(MODEL_WORDS), .OWNER_DEPTH(16)
    ) u_private_ddr_arbiter (
        .clk(clk), .reset_n(reset_n), .model_locked_i(model_locked_i),
        .upstream_fail_closed_i(upstream_fail_closed_i),
        .endpoint_fail_closed_i(shell_fail || layer_fail),
        .shell_req_valid_i(shell_queued_req_valid && !clear_i),
        .shell_req_ready_o(shell_queued_req_ready),
        .shell_req_index_i(shell_queued_req_index),
        .shell_rsp_valid_o(shell_queued_rsp_valid),
        .shell_rsp_ready_i(shell_queued_rsp_ready),
        .shell_rsp_data_o(shell_queued_rsp_data),
        .shell_rsp_fault_o(shell_queued_rsp_fault),
        .layer_req_valid_i(layer_queued_req_valid && !clear_i),
        .layer_req_ready_o(layer_queued_req_ready),
        .layer_req_index_i(layer_queued_req_index),
        .layer_rsp_valid_o(layer_queued_rsp_valid),
        .layer_rsp_ready_i(layer_queued_rsp_ready),
        .layer_rsp_data_o(layer_queued_rsp_data),
        .layer_rsp_fault_o(layer_queued_rsp_fault),
        .private_req_valid_o(private_runtime_req_valid_o),
        .private_req_ready_i(private_runtime_req_ready_i),
        .private_req_index_o(private_runtime_req_word_index_o),
        .private_rsp_valid_i(private_runtime_rsp_valid_i),
        .private_rsp_ready_o(private_runtime_rsp_ready_o),
        .private_rsp_data_i(private_runtime_rsp_data_i),
        .private_rsp_fault_i(private_runtime_rsp_fault_i),
        .busy_o(arbiter_busy), .fail_closed_o(arbiter_fail)
    );

    always_comb begin
        append_ready_o = machine_active && !aggregate_fail &&
                         shell_append_ready;
        step_ready_o = machine_active && !aggregate_fail && shell_step_ready;
        token_valid_o = machine_active && !aggregate_fail &&
                        shell_token_valid;
        token_o = token_valid_o ? shell_token : 12'd0;
        busy_o = machine_active && (shell_busy || layer_busy || arbiter_busy);
        model_locked_o = machine_active && model_locked_i &&
                         shell_model_locked && !aggregate_fail;
        fail_closed_o = aggregate_fail;
    end

`ifdef FORMAL
    logic formal_past_valid;
    always_ff @(posedge clk) begin
        formal_past_valid <= 1'b1;
        if (reset_n) begin
            assert (!(append_ready_o && step_ready_o));
            if (!model_locked_o) begin
                assert (!append_ready_o && !step_ready_o && !token_valid_o);
            end
            if (private_runtime_req_valid_o)
                assert (private_runtime_req_word_index_o < MODEL_WORDS);
            if (verified_private_retire) begin
                assert(machine_active && model_locked_i && !clear_i &&
                       !aggregate_fail);
                assert(owned_model_response_retire ||
                       typed_kv_write_retire || typed_kv_read_retire);
            end
            if (owned_model_response_retire)
                assert(arbiter_busy && private_runtime_rsp_valid_i &&
                       private_runtime_rsp_ready_o &&
                       !private_runtime_rsp_fault_i);
            if (typed_kv_write_retire)
                assert(kv_write_cpl_valid_i && kv_write_cpl_ready_o &&
                       !kv_write_cpl_fault_i);
            if (typed_kv_read_retire)
                assert(kv_read_rsp_valid_i && kv_read_rsp_ready_o &&
                       !kv_read_rsp_fault_i && typed_kv_padding_legal);
            if (formal_past_valid && $past(reset_n) &&
                $past(fail_closed_o))
                assert (fail_closed_o || !model_locked_i);
        end
    end
`endif
endmodule

`default_nettype wire
