`timescale 1ns/1ps
`default_nettype none

// Context-2,048 production-successor shell.  The public tape has 2,049
// physical slots: 2,048 model-input positions plus one final generated-token
// slot.  APPEND is legal only below 2,048, while STEP is legal at lengths
// 1..2,048 inclusive.  Thus a STEP at length 2,048 evaluates position 2,047
// and stores the result in physical slot 2,048.  The caller still sees only
// APPEND, STEP, and CLEAR; every wider position/count signal stays private.
module board1_context2048_token_shell #(
    parameter integer ADDR_W = 25,
    parameter integer METADATA_BASE_WORD = 211920,
    // This is deliberately a no-forward-progress interval, not a cumulative
    // STEP budget.  A legal 2,048-token replay has quadratic causal-attention
    // work and therefore must not consume one global fixed cycle allowance.
    parameter integer MAX_NO_PROGRESS_CYCLES = 100_000_000,
    parameter NORM_ROM_FILE = "fpga/token_only_model0_ddr_board1/fixed_vector_rmsnorm0/recorded/norm_rom34.memh"
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    clear_i,
    input  wire                    model_lock_i,
    input  wire                    upstream_fault_i,
    // One-cycle core-qualified retirement pulse.  It is asserted only for a
    // consumed, owned, nonfaulted post-lock model response or a consumed,
    // nonfaulted typed K/V completion/response.  Raw endpoint activity never
    // reaches this seam.
    input  wire                    private_verified_retire_i,

    input  wire                    append_valid_i,
    output logic                   append_ready_o,
    input  wire [11:0]             append_token_i,
    input  wire                    step_valid_i,
    output logic                   step_ready_o,

    output logic                   token_valid_o,
    input  wire                    token_ready_i,
    output logic [11:0]            token_o,
    output logic                   busy_o,
    output logic                   model_locked_o,
    output logic                   fail_closed_o,
    // Internal only: the owning core must bind terminal containment.
    output wire                    private_terminal_latched_o,

    // Sole private authenticated-image read channel.  This fork owns only
    // embedding traffic; the shared semantic/head service owns head traffic.
    output logic                   private_word_req_valid_o,
    input  wire                    private_word_req_ready_i,
    output logic [ADDR_W-1:0]      private_word_req_index_o,
    input  wire                    private_word_rsp_valid_i,
    output logic                   private_word_rsp_ready_o,
    input  wire [255:0]            private_word_rsp_data_i,
    input  wire                    private_word_rsp_fault_i,

    // Private atomic six-layer service.  One accepted request consumes one
    // exact embedding vector and commits one position through layers 0..5.
    output logic                   private_layer_clear_o,
    output logic                   private_layer_start_valid_o,
    input  wire                    private_layer_start_ready_i,
    output logic [10:0]            private_layer_position_o,
    output logic signed [7:0]      private_layer_input_exponent_o,
    output logic                   private_layer_input_valid_o,
    input  wire                    private_layer_input_ready_i,
    output logic [7:0]             private_layer_input_index_o,
    output logic signed [15:0]     private_layer_input_mantissa_o,
    output logic                   private_layer_input_last_o,
    input  wire                    private_layer_result_valid_i,
    output logic                   private_layer_result_ready_o,
    input  wire [7:0]              private_layer_result_index_i,
    input  wire signed [15:0]      private_layer_result_mantissa_i,
    input  wire signed [7:0]       private_layer_result_exponent_i,
    input  wire                    private_layer_result_last_i,
    input  wire                    private_layer_done_valid_i,
    output logic                   private_layer_done_ready_o,
    input  wire [71:0]             private_layer_committed_prefixes_i,
    input  wire                    private_layer_busy_i,
    input  wire                    private_layer_fault_i,

    // Private fixed tied-head seam.  The service is immutably layer 7/job 7;
    // this shell supplies exactly 256 normalized activations and consumes the
    // ordered 4,019-row raw/exponent stream.  Its busy/fault/clear contract is
    // covered by private_layer_busy_i/private_layer_fault_i and the common
    // private_layer_clear_o above.
    output logic                   private_head_start_valid_o,
    input  wire                    private_head_start_ready_i,
    output logic signed [7:0]      private_head_activation_exponent_o,
    output logic                   private_head_activation_valid_o,
    input  wire                    private_head_activation_ready_i,
    output logic [7:0]             private_head_activation_index_o,
    output logic signed [15:0]     private_head_activation_mantissa_o,
    output logic                   private_head_activation_last_o,
    input  wire                    private_head_result_valid_i,
    output logic                   private_head_result_ready_o,
    input  wire [12:0]             private_head_result_row_index_i,
    input  wire signed [49:0]      private_head_result_scaled_raw_i,
    input  wire signed [7:0]       private_head_result_source_exponent_i,
    input  wire                    private_head_result_last_i,
    input  wire                    private_head_done_valid_i,
    output logic                   private_head_done_ready_o
);
    localparam logic [11:0] VOCABULARY_SIZE = 12'd4019;
    localparam logic [11:0] MODEL_CONTEXT = 12'd2048;
    localparam logic [11:0] TAPE_CAPACITY = 12'd2049;

    typedef enum logic [4:0] {
        ST_IDLE              = 5'd0,
        ST_TAPE_READ         = 5'd1,
        ST_EMBED_START       = 5'd2,
        ST_EMBED_CAPTURE     = 5'd3,
        ST_EMBED_DONE        = 5'd4,
        ST_LAYER_START       = 5'd5,
        ST_LAYER_INPUT_READ  = 5'd6,
        ST_LAYER_INPUT_SEND  = 5'd7,
        ST_LAYER_RESULT      = 5'd8,
        ST_LAYER_DONE        = 5'd9,
        ST_LAYER_COMMIT      = 5'd10,
        ST_RMS_START         = 5'd11,
        ST_RMS_INPUT_READ    = 5'd12,
        ST_RMS_INPUT_SEND    = 5'd13,
        ST_RMS_RESULT        = 5'd14,
        ST_RMS_DONE          = 5'd15,
        ST_HEAD_START        = 5'd16,
        ST_ARGMAX_START      = 5'd17,
        ST_HEAD_INPUT_READ   = 5'd18,
        ST_HEAD_INPUT_SEND   = 5'd19,
        ST_HEAD_SCAN         = 5'd20,
        ST_HEAD_TERMINALS    = 5'd21,
        ST_TOKEN_HOLD        = 5'd22,
        ST_CLEAR_DRAIN       = 5'd23,
        ST_FAIL              = 5'd31
    } state_t;

    localparam logic DDR_OWNER_NONE  = 1'b0;
    localparam logic DDR_OWNER_EMBED = 1'b1;

    state_t state_q;
    logic ddr_owner_q;
    logic fail_q;
    assign private_terminal_latched_o = fail_q;
    // 100,000,000 needs 27 bits.  Keep the production counter explicitly
    // 27-bit and saturating so neither context length nor quadratic work can
    // cause wraparound.  Low-limit tests override only the comparison value.
    logic [26:0] no_progress_cycles_q;
    localparam logic [26:0] NO_PROGRESS_LAST =
        27'(MAX_NO_PROGRESS_CYCLES - 1);

    // Preserve the independently justified local child watchdogs.  They
    // guard one embedding/RMS invocation; they are not aliases of the shell's
    // orchestration-progress policy.
    localparam integer EMBED_MAX_COMPUTE_CYCLES = 4_000_000;
    localparam integer RMS_MAX_COMPUTE_CYCLES = 2_000_000;

    initial begin
        if ((MAX_NO_PROGRESS_CYCLES < 4) ||
            (MAX_NO_PROGRESS_CYCLES > 134_217_728))
            $fatal(1, "no-progress watchdog must fit exactly 27 bits");
    end

    logic [11:0] tape_count_q;
    logic [11:0] committed_count_q;
    logic [11:0] replay_position_q;
    logic [11:0] tape_read_q;
    logic [11:0] generated_token_q;
    logic last_hidden_valid_q;

    (* ram_style = "block", syn_ramstyle = "block_ram" *)
        logic [11:0] token_tape_q [0:2048];
    (* ram_style = "block" *) logic signed [15:0]
        embedding_mem_q [0:255];
    (* ram_style = "block" *) logic signed [15:0]
        layer5_mem_q [0:255];
    (* ram_style = "block" *) logic signed [15:0]
        final_norm_mem_q [0:255];

    logic signed [15:0] embedding_read_q;
    logic signed [15:0] layer5_read_q;
    logic signed [15:0] final_norm_read_q;
    logic signed [7:0] embedding_exponent_q;
    logic signed [7:0] layer5_exponent_q;
    logic signed [7:0] final_norm_exponent_q;
    logic [7:0] capture_index_q;
    logic [7:0] stream_index_q;

    logic head_done_seen_q;
    logic winner_seen_q;
    logic [11:0] winner_token_q;

    function automatic prefixes_equal(
        input logic [71:0] prefixes,
        input logic [11:0] expected
    );
        integer layer_index;
        begin
            prefixes_equal = 1'b1;
            for (layer_index = 0; layer_index < 6;
                 layer_index = layer_index + 1)
                if (prefixes[layer_index*12 +: 12] != expected)
                    prefixes_equal = 1'b0;
        end
    endfunction

    wire committed_prefixes_match = prefixes_equal(
        private_layer_committed_prefixes_i, committed_count_q);
    wire next_prefixes_match = prefixes_equal(
        private_layer_committed_prefixes_i,
        replay_position_q + 12'd1);
    wire cleared_prefixes_match = prefixes_equal(
        private_layer_committed_prefixes_i, 12'd0);

    wire append_token_legal = append_token_i < VOCABULARY_SIZE;
    wire append_transfer = append_valid_i && append_ready_o;
    wire step_transfer = step_valid_i && step_ready_o;
    wire token_transfer = token_valid_o && token_ready_i;
    wire replay_is_needed = committed_count_q < tape_count_q;
    wire replay_state_available = replay_is_needed || last_hidden_valid_q;

    // Fixed embedding child.
    logic embed_start_valid;
    wire embed_start_ready;
    wire embed_req_valid;
    logic embed_req_ready;
    wire [ADDR_W-1:0] embed_req_index;
    logic embed_rsp_valid;
    wire embed_rsp_ready;
    wire embed_result_valid;
    logic embed_result_ready;
    wire [7:0] embed_result_index;
    wire signed [15:0] embed_result_mantissa;
    wire signed [7:0] embed_result_exponent;
    wire embed_result_last;
    wire embed_done_valid;
    logic embed_done_ready;
    wire embed_busy;
    wire embed_fault;

    board1_fixed_embedding_lookup #(
        .ADDR_W(ADDR_W), .METADATA_BASE_WORD(METADATA_BASE_WORD),
        .MAX_COMPUTE_CYCLES(EMBED_MAX_COMPUTE_CYCLES)
    ) u_fixed_embedding (
        .clk(clk), .rst_n(rst_n), .clear_i(clear_i),
        .model_lock_i(model_lock_i),
        .upstream_fault_i(upstream_fault_i),
        .start_valid_i(embed_start_valid), .start_ready_o(embed_start_ready),
        .fixed_token_i(tape_read_q),
        .private_word_req_valid_o(embed_req_valid),
        .private_word_req_ready_i(embed_req_ready),
        .private_word_req_index_o(embed_req_index),
        .private_word_rsp_valid_i(embed_rsp_valid),
        .private_word_rsp_ready_o(embed_rsp_ready),
        .private_word_rsp_data_i(private_word_rsp_data_i),
        .private_word_rsp_fault_i(private_word_rsp_fault_i),
        .result_valid_o(embed_result_valid),
        .result_ready_i(embed_result_ready),
        .result_index_o(embed_result_index),
        .result_mantissa_o(embed_result_mantissa),
        .result_exponent_o(embed_result_exponent),
        .result_last_o(embed_result_last),
        .done_valid_o(embed_done_valid), .done_ready_i(embed_done_ready),
        .busy_o(embed_busy), .fail_closed_o(embed_fault)
    );

    // Frozen exact final RMSNorm (selector 12 is internally derived from
    // layer 5 / final kind).  Its norm weights are an immutable local ROM.
    logic rms_start_valid;
    wire rms_start_ready;
    logic rms_input_valid;
    wire rms_input_ready;
    wire rms_result_valid;
    logic rms_result_ready;
    wire [7:0] rms_result_index;
    wire signed [15:0] rms_result_mantissa;
    wire signed [7:0] rms_result_exponent;
    wire rms_result_last;
    wire rms_done_valid;
    logic rms_done_ready;
    wire rms_busy;
    wire rms_fault;

    board1_fixed_vector_rmsnorm_service #(
        .MAX_COMPUTE_CYCLES(RMS_MAX_COMPUTE_CYCLES),
        .NORM_ROM_FILE(NORM_ROM_FILE)
    ) u_final_rmsnorm (
        .clk(clk), .rst_n(rst_n), .clear_i(clear_i),
        .model_lock_i(model_lock_i),
        .upstream_fault_i(upstream_fault_i),
        .start_valid_i(rms_start_valid), .start_ready_o(rms_start_ready),
        .fixed_layer_i(3'd5), .fixed_norm_kind_i(2'd2),
        .input_exponent_i(layer5_exponent_q),
        .input_valid_i(rms_input_valid), .input_ready_o(rms_input_ready),
        .input_row_index_i(stream_index_q),
        .input_mantissa_i(layer5_read_q),
        .input_last_i(stream_index_q == 8'd255),
        .result_valid_o(rms_result_valid),
        .result_ready_i(rms_result_ready),
        .result_row_index_o(rms_result_index),
        .result_mantissa_o(rms_result_mantissa),
        .result_exponent_o(rms_result_exponent),
        .result_last_o(rms_result_last),
        .done_valid_o(rms_done_valid), .done_ready_i(rms_done_ready),
        .busy_o(rms_busy), .range_fault_o(rms_fault)
    );

    // Frozen exact exponent-aware argmax.  Strict replacement preserves the
    // smallest token identifier on an exact tie.
    logic argmax_start_valid;
    wire argmax_start_ready;
    wire argmax_row_ready;
    wire argmax_winner_valid;
    logic argmax_winner_ready;
    wire [11:0] argmax_winner_token;
    wire signed [49:0] argmax_winner_scaled;
    wire signed [7:0] argmax_winner_exponent;
    wire argmax_busy;
    wire argmax_fault;

    board1_fixed_head_argmax u_exact_argmax (
        .clk(clk), .reset_n(rst_n), .clear_i(clear_i),
        .model_locked_i(model_lock_i),
        .upstream_fail_closed_i(upstream_fault_i),
        .start_valid_i(argmax_start_valid),
        .start_ready_o(argmax_start_ready),
        .row_valid_i((state_q == ST_HEAD_SCAN) &&
                     private_head_result_valid_i),
        .row_ready_o(argmax_row_ready),
        .row_index_i(private_head_result_row_index_i),
        .row_scaled_raw_i(private_head_result_scaled_raw_i),
        .row_source_exponent_i(private_head_result_source_exponent_i),
        .row_last_i(private_head_result_last_i),
        .winner_valid_o(argmax_winner_valid),
        .winner_ready_i(argmax_winner_ready),
        .winner_token_id_o(argmax_winner_token),
        .winner_scaled_raw_o(argmax_winner_scaled),
        .winner_source_exponent_o(argmax_winner_exponent),
        .busy_o(argmax_busy), .fail_closed_o(argmax_fault)
    );

    wire embed_start_transfer = embed_start_valid && embed_start_ready;
    wire embed_result_transfer = embed_result_valid && embed_result_ready;
    wire embed_done_transfer = embed_done_valid && embed_done_ready;
    wire layer_start_transfer = private_layer_start_valid_o &&
                                private_layer_start_ready_i;
    wire layer_input_transfer = private_layer_input_valid_o &&
                                private_layer_input_ready_i;
    wire layer_result_transfer = private_layer_result_valid_i &&
                                 private_layer_result_ready_o;
    wire layer_done_transfer = private_layer_done_valid_i &&
                               private_layer_done_ready_o;
    wire rms_result_transfer = rms_result_valid && rms_result_ready;
    wire rms_done_transfer = rms_done_valid && rms_done_ready;
    wire rms_start_transfer = rms_start_valid && rms_start_ready;
    wire rms_input_transfer = rms_input_valid && rms_input_ready;
    wire head_start_transfer = private_head_start_valid_o &&
                               private_head_start_ready_i;
    wire argmax_start_transfer = argmax_start_valid && argmax_start_ready;
    wire head_input_transfer = private_head_activation_valid_o &&
                               private_head_activation_ready_i;
    wire head_result_transfer = private_head_result_valid_i &&
                                private_head_result_ready_o;
    wire head_last_transfer = head_result_transfer &&
                              private_head_result_last_i;
    wire head_done_transfer = private_head_done_valid_i &&
                              private_head_done_ready_o;
    wire winner_transfer = argmax_winner_valid && argmax_winner_ready;
    wire head_terminals_complete =
        (head_done_seen_q || head_done_transfer) &&
        (winner_seen_q || winner_transfer);
    wire [11:0] completing_winner = winner_seen_q ? winner_token_q :
                                                        argmax_winner_token;
    wire generated_commit = (state_q == ST_HEAD_TERMINALS) &&
                            head_terminals_complete &&
                            (completing_winner < VOCABULARY_SIZE) &&
                            (tape_count_q < TAPE_CAPACITY);

    // A local pulse qualifies only a transfer which the immutable shell FSM
    // is presently consuming.  Descriptor/range failures take terminal-fault
    // priority on the same edge and cannot be repeated as progress.  The
    // external pulse is already ownership/fault qualified by the core.
    wire legal_embed_result_retire = embed_result_transfer &&
        (embed_result_index == capture_index_q) &&
        (embed_result_last == (capture_index_q == 8'd255)) &&
        (embed_result_mantissa != -16'sd32768) &&
        ((capture_index_q == 8'd0) ||
         (embed_result_exponent == embedding_exponent_q));
    wire legal_layer_input_retire = layer_input_transfer &&
                                    (embedding_read_q != -16'sd32768);
    wire legal_layer_result_retire = layer_result_transfer &&
        (private_layer_result_index_i == capture_index_q) &&
        (private_layer_result_last_i == (capture_index_q == 8'd255)) &&
        (private_layer_result_mantissa_i != -16'sd32768) &&
        ((capture_index_q == 8'd0) ||
         (private_layer_result_exponent_i == layer5_exponent_q));
    wire semantic_commit_retire = (state_q == ST_LAYER_COMMIT) &&
                                  !private_layer_busy_i &&
                                  next_prefixes_match;
    wire legal_rms_input_retire = rms_input_transfer &&
                                  (layer5_read_q != -16'sd32768);
    wire legal_rms_result_retire = rms_result_transfer &&
        (rms_result_index == capture_index_q) &&
        (rms_result_last == (capture_index_q == 8'd255)) &&
        (rms_result_mantissa != -16'sd32768) &&
        ((capture_index_q == 8'd0) ||
         (rms_result_exponent == final_norm_exponent_q));
    wire legal_head_input_retire = head_input_transfer &&
                                   (final_norm_read_q != -16'sd32768);
    wire verified_forward_progress = private_verified_retire_i ||
        embed_start_transfer || legal_embed_result_retire ||
        embed_done_transfer || layer_start_transfer ||
        legal_layer_input_retire || legal_layer_result_retire ||
        layer_done_transfer || semantic_commit_retire ||
        rms_start_transfer || legal_rms_input_retire ||
        legal_rms_result_retire || rms_done_transfer ||
        head_start_transfer || argmax_start_transfer ||
        legal_head_input_retire || head_result_transfer ||
        head_done_transfer || winner_transfer || generated_commit;

    wire compute_active = (state_q != ST_IDLE) &&
                          (state_q != ST_TOKEN_HOLD) &&
                          (state_q != ST_CLEAR_DRAIN) &&
                          (state_q != ST_FAIL);
    wire child_fault = embed_fault || rms_fault || argmax_fault ||
                       private_layer_fault_i;
    wire lock_fault = (state_q != ST_IDLE) &&
                      (state_q != ST_CLEAR_DRAIN) && !model_lock_i;
    wire watchdog_fault = compute_active && !verified_forward_progress &&
                          (no_progress_cycles_q == NO_PROGRESS_LAST);
    wire public_protocol_fault = !clear_i &&
        ((append_valid_i && step_valid_i) ||
         (append_valid_i && !append_token_legal));
    wire private_protocol_fault = !clear_i &&
        (((private_word_rsp_valid_i === 1'b1) &&
          (ddr_owner_q == DDR_OWNER_NONE)) ||
         ((private_layer_result_valid_i === 1'b1) &&
          (state_q != ST_LAYER_RESULT)) ||
         ((private_layer_done_valid_i === 1'b1) &&
          (state_q != ST_LAYER_DONE)) ||
         ((private_head_result_valid_i === 1'b1) &&
          (state_q != ST_HEAD_SCAN) &&
          (state_q != ST_HEAD_TERMINALS)) ||
         ((private_head_done_valid_i === 1'b1) &&
          (state_q != ST_HEAD_SCAN) &&
          (state_q != ST_HEAD_TERMINALS)) ||
         ((argmax_winner_valid === 1'b1) &&
          (state_q != ST_HEAD_TERMINALS)));

    // Public and private ready/valid policy.  DDR ownership is embedding-only;
    // all fixed-head DDR traffic remains inside the shared semantic service.
    always_comb begin
        append_ready_o = (state_q == ST_IDLE) && model_lock_i &&
                         !upstream_fault_i && !fail_q && !child_fault &&
                         !step_valid_i && !clear_i &&
                         (tape_count_q < MODEL_CONTEXT) &&
                         committed_prefixes_match;
        step_ready_o = (state_q == ST_IDLE) && model_lock_i &&
                       !upstream_fault_i && !fail_q && !child_fault &&
                       !append_valid_i && !clear_i &&
                       (tape_count_q != 12'd0) &&
                       (tape_count_q <= MODEL_CONTEXT) &&
                       committed_prefixes_match && replay_state_available;
        token_valid_o = (state_q == ST_TOKEN_HOLD) && model_lock_i &&
                        !upstream_fault_i && !fail_q && !child_fault &&
                        !clear_i;
        token_o = token_valid_o ? generated_token_q : 12'd0;
        busy_o = (state_q != ST_IDLE) && (state_q != ST_FAIL);
        model_locked_o = model_lock_i;
        fail_closed_o = fail_q || child_fault || upstream_fault_i ||
                        (state_q == ST_FAIL);

        embed_start_valid = (state_q == ST_EMBED_START) &&
                            !fail_closed_o && !clear_i;
        embed_result_ready = (state_q == ST_EMBED_CAPTURE) &&
                             !fail_closed_o && !clear_i;
        embed_done_ready = (state_q == ST_EMBED_DONE) &&
                           !fail_closed_o && !clear_i;

        // Terminal closure belongs to the owning core, not a broadcast
        // through every arithmetic child. Ordinary CLEAR is unchanged.
        private_layer_clear_o = clear_i;
        private_layer_start_valid_o = (state_q == ST_LAYER_START) &&
                                      !fail_closed_o && !clear_i;
        private_layer_position_o = replay_position_q[10:0];
        private_layer_input_exponent_o = embedding_exponent_q;
        private_layer_input_valid_o = (state_q == ST_LAYER_INPUT_SEND) &&
                                      !fail_closed_o && !clear_i;
        private_layer_input_index_o = stream_index_q;
        private_layer_input_mantissa_o = embedding_read_q;
        private_layer_input_last_o = (stream_index_q == 8'd255);
        private_layer_result_ready_o = (state_q == ST_LAYER_RESULT) &&
                                       !fail_closed_o && !clear_i;
        private_layer_done_ready_o = (state_q == ST_LAYER_DONE) &&
                                     !fail_closed_o && !clear_i;

        rms_start_valid = (state_q == ST_RMS_START) &&
                          !fail_closed_o && !clear_i;
        rms_input_valid = (state_q == ST_RMS_INPUT_SEND) &&
                          !fail_closed_o && !clear_i;
        rms_result_ready = (state_q == ST_RMS_RESULT) &&
                           !fail_closed_o && !clear_i;
        rms_done_ready = (state_q == ST_RMS_DONE) &&
                         !fail_closed_o && !clear_i;

        private_head_start_valid_o = (state_q == ST_HEAD_START) &&
                                     !fail_closed_o && !clear_i;
        private_head_activation_exponent_o = final_norm_exponent_q;
        argmax_start_valid = (state_q == ST_ARGMAX_START) &&
                             !fail_closed_o && !clear_i;
        private_head_activation_valid_o =
            (state_q == ST_HEAD_INPUT_SEND) &&
            !fail_closed_o && !clear_i;
        private_head_activation_index_o = stream_index_q;
        private_head_activation_mantissa_o = final_norm_read_q;
        private_head_activation_last_o = (stream_index_q == 8'd255);
        private_head_result_ready_o = (state_q == ST_HEAD_SCAN) &&
                                      argmax_row_ready &&
                                      !fail_closed_o && !clear_i;
        private_head_done_ready_o = ((state_q == ST_HEAD_SCAN) ||
                                     (state_q == ST_HEAD_TERMINALS)) &&
                                    !head_done_seen_q &&
                                    !fail_closed_o && !clear_i;
        argmax_winner_ready = (state_q == ST_HEAD_TERMINALS) &&
                              !winner_seen_q && !fail_closed_o && !clear_i;

        private_word_req_valid_o = 1'b0;
        private_word_req_index_o = {ADDR_W{1'b0}};
        private_word_rsp_ready_o = 1'b0;
        embed_req_ready = 1'b0;
        embed_rsp_valid = 1'b0;
        if (ddr_owner_q == DDR_OWNER_EMBED) begin
            private_word_req_valid_o = embed_req_valid;
            private_word_req_index_o = embed_req_index;
            embed_req_ready = private_word_req_ready_i;
            embed_rsp_valid = private_word_rsp_valid_i;
            private_word_rsp_ready_o = embed_rsp_ready;
        end
    end

    // Transaction RAM writes and synchronous reads are intentionally outside
    // reset logic so Gowin can infer block RAM rather than resettable flops.
    always_ff @(posedge clk) begin
        if (append_transfer)
            token_tape_q[tape_count_q] <= append_token_i;
        else if (generated_commit)
            token_tape_q[tape_count_q] <= completing_winner;

        if (state_q == ST_TAPE_READ)
            tape_read_q <= token_tape_q[replay_position_q];

        if (embed_result_transfer)
            embedding_mem_q[embed_result_index] <= embed_result_mantissa;
        if (state_q == ST_LAYER_INPUT_READ)
            embedding_read_q <= embedding_mem_q[stream_index_q];

        if (layer_result_transfer)
            layer5_mem_q[private_layer_result_index_i] <=
                private_layer_result_mantissa_i;
        if (state_q == ST_RMS_INPUT_READ)
            layer5_read_q <= layer5_mem_q[stream_index_q];

        if (rms_result_transfer)
            final_norm_mem_q[rms_result_index] <= rms_result_mantissa;
        if (state_q == ST_HEAD_INPUT_READ)
            final_norm_read_q <= final_norm_mem_q[stream_index_q];
    end

`ifndef SYNTHESIS
    logic simulation_x_fault;
    always_comb begin
        simulation_x_fault = $isunknown(rst_n) || $isunknown(clear_i) ||
            $isunknown(model_lock_i) || $isunknown(upstream_fault_i) ||
            $isunknown(private_verified_retire_i) ||
            $isunknown(append_valid_i) || $isunknown(step_valid_i) ||
            $isunknown(token_ready_i) ||
            $isunknown(private_word_req_ready_i) ||
            $isunknown(private_word_rsp_valid_i) ||
            $isunknown(private_word_rsp_fault_i) ||
            $isunknown(private_layer_start_ready_i) ||
            $isunknown(private_layer_input_ready_i) ||
            $isunknown(private_layer_result_valid_i) ||
            $isunknown(private_layer_done_valid_i) ||
            $isunknown(private_layer_committed_prefixes_i) ||
            $isunknown(private_layer_busy_i) ||
            $isunknown(private_layer_fault_i) ||
            $isunknown(private_head_start_ready_i) ||
            $isunknown(private_head_activation_ready_i) ||
            $isunknown(private_head_result_valid_i) ||
            $isunknown(private_head_done_valid_i) ||
            $isunknown(state_q) || $isunknown(ddr_owner_q) ||
            $isunknown(fail_q);
        if (append_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                                 $isunknown(append_token_i);
        if (private_word_rsp_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                                 $isunknown(private_word_rsp_data_i);
        if (private_layer_result_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                $isunknown(private_layer_result_index_i) ||
                $isunknown(private_layer_result_mantissa_i) ||
                $isunknown(private_layer_result_exponent_i) ||
                $isunknown(private_layer_result_last_i);
        if (private_head_result_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                $isunknown(private_head_result_row_index_i) ||
                $isunknown(private_head_result_scaled_raw_i) ||
                $isunknown(private_head_result_source_exponent_i) ||
                $isunknown(private_head_result_last_i);
    end
`endif

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= ST_IDLE;
            ddr_owner_q <= DDR_OWNER_NONE;
            fail_q <= 1'b0;
            no_progress_cycles_q <= 27'd0;
            tape_count_q <= 12'd0;
            committed_count_q <= 12'd0;
            replay_position_q <= 12'd0;
            generated_token_q <= 12'd0;
            last_hidden_valid_q <= 1'b0;
            embedding_exponent_q <= 8'sd0;
            layer5_exponent_q <= 8'sd0;
            final_norm_exponent_q <= 8'sd0;
            capture_index_q <= 8'd0;
            stream_index_q <= 8'd0;
            head_done_seen_q <= 1'b0;
            winner_seen_q <= 1'b0;
            winner_token_q <= 12'd0;
        end else begin
            if (clear_i) begin
                // CLEAR erases the public tape and invalidates the shared
                // semantic/head service.  Accepted embedding work remains
                // owned through drain; all semantic/head drain is represented
                // by private_layer_busy_i.
                state_q <= ST_CLEAR_DRAIN;
                no_progress_cycles_q <= 27'd0;
                tape_count_q <= 12'd0;
                committed_count_q <= 12'd0;
                replay_position_q <= 12'd0;
                generated_token_q <= 12'd0;
                last_hidden_valid_q <= 1'b0;
                capture_index_q <= 8'd0;
                stream_index_q <= 8'd0;
                head_done_seen_q <= 1'b0;
                winner_seen_q <= 1'b0;
            end else if (fail_q) begin
                state_q <= ST_FAIL;
                fail_q <= 1'b1;
            end else begin
                if (!compute_active || verified_forward_progress)
                    no_progress_cycles_q <= 27'd0;
                else if (no_progress_cycles_q != NO_PROGRESS_LAST)
                    no_progress_cycles_q <= no_progress_cycles_q + 1'b1;

                case (state_q)
                    ST_IDLE: begin
                        if (ddr_owner_q != DDR_OWNER_NONE) begin
                            state_q <= ST_FAIL;
                            fail_q <= 1'b1;
                        end else if (append_transfer) begin
                            tape_count_q <= tape_count_q + 12'd1;
                        end else if (step_transfer) begin
                            replay_position_q <= committed_count_q;
                            capture_index_q <= 8'd0;
                            stream_index_q <= 8'd0;
                            head_done_seen_q <= 1'b0;
                            winner_seen_q <= 1'b0;
                            if (replay_is_needed)
                                state_q <= ST_TAPE_READ;
                            else
                                state_q <= ST_RMS_START;
                        end
                    end

                    ST_TAPE_READ: begin
                        state_q <= ST_EMBED_START;
                    end

                    ST_EMBED_START: begin
                        if (embed_start_valid && embed_start_ready) begin
                            ddr_owner_q <= DDR_OWNER_EMBED;
                            capture_index_q <= 8'd0;
                            state_q <= ST_EMBED_CAPTURE;
                        end
                    end

                    ST_EMBED_CAPTURE: begin
                        if (embed_result_valid &&
                            ((embed_result_index != capture_index_q) ||
                             (embed_result_last !=
                              (capture_index_q == 8'd255)) ||
                             (embed_result_mantissa == -16'sd32768) ||
                             ((capture_index_q != 8'd0) &&
                              (embed_result_exponent !=
                               embedding_exponent_q)))) begin
                            state_q <= ST_FAIL;
                            fail_q <= 1'b1;
                        end else if (embed_result_transfer) begin
                            if (capture_index_q == 8'd0)
                                embedding_exponent_q <=
                                    embed_result_exponent;
                            if (capture_index_q == 8'd255) begin
                                capture_index_q <= 8'd0;
                                state_q <= ST_EMBED_DONE;
                            end else begin
                                capture_index_q <= capture_index_q + 1'b1;
                            end
                        end
                    end

                    ST_EMBED_DONE: begin
                        if (embed_done_transfer) begin
                            ddr_owner_q <= DDR_OWNER_NONE;
                            state_q <= ST_LAYER_START;
                        end
                    end

                    ST_LAYER_START: begin
                        if (layer_start_transfer) begin
                            stream_index_q <= 8'd0;
                            state_q <= ST_LAYER_INPUT_READ;
                        end
                    end

                    ST_LAYER_INPUT_READ: begin
                        state_q <= ST_LAYER_INPUT_SEND;
                    end

                    ST_LAYER_INPUT_SEND: begin
                        if (layer_input_transfer) begin
                            if (embedding_read_q == -16'sd32768) begin
                                state_q <= ST_FAIL;
                                fail_q <= 1'b1;
                            end else if (stream_index_q == 8'd255) begin
                                stream_index_q <= 8'd0;
                                capture_index_q <= 8'd0;
                                state_q <= ST_LAYER_RESULT;
                            end else begin
                                stream_index_q <= stream_index_q + 1'b1;
                                state_q <= ST_LAYER_INPUT_READ;
                            end
                        end
                    end

                    ST_LAYER_RESULT: begin
                        if (private_layer_result_valid_i &&
                            ((private_layer_result_index_i !=
                              capture_index_q) ||
                             (private_layer_result_last_i !=
                              (capture_index_q == 8'd255)) ||
                             (private_layer_result_mantissa_i ==
                              -16'sd32768) ||
                             ((capture_index_q != 8'd0) &&
                              (private_layer_result_exponent_i !=
                               layer5_exponent_q)))) begin
                            state_q <= ST_FAIL;
                            fail_q <= 1'b1;
                        end else if (layer_result_transfer) begin
                            if (capture_index_q == 8'd0)
                                layer5_exponent_q <=
                                    private_layer_result_exponent_i;
                            if (capture_index_q == 8'd255) begin
                                capture_index_q <= 8'd0;
                                state_q <= ST_LAYER_DONE;
                            end else begin
                                capture_index_q <= capture_index_q + 1'b1;
                            end
                        end
                    end

                    ST_LAYER_DONE: begin
                        if (layer_done_transfer)
                            state_q <= ST_LAYER_COMMIT;
                    end

                    ST_LAYER_COMMIT: begin
                        if (private_layer_busy_i) begin
                            state_q <= ST_LAYER_COMMIT;
                        end else if (!next_prefixes_match) begin
                            state_q <= ST_FAIL;
                            fail_q <= 1'b1;
                        end else begin
                            committed_count_q <= replay_position_q + 12'd1;
                            last_hidden_valid_q <= 1'b1;
                            if ((replay_position_q + 12'd1) < tape_count_q) begin
                                replay_position_q <= replay_position_q + 12'd1;
                                state_q <= ST_TAPE_READ;
                            end else begin
                                state_q <= ST_RMS_START;
                            end
                        end
                    end

                    ST_RMS_START: begin
                        if (!last_hidden_valid_q) begin
                            state_q <= ST_FAIL;
                            fail_q <= 1'b1;
                        end else if (rms_start_valid && rms_start_ready) begin
                            stream_index_q <= 8'd0;
                            state_q <= ST_RMS_INPUT_READ;
                        end
                    end

                    ST_RMS_INPUT_READ: begin
                        state_q <= ST_RMS_INPUT_SEND;
                    end

                    ST_RMS_INPUT_SEND: begin
                        if (rms_input_valid && rms_input_ready) begin
                            if (layer5_read_q == -16'sd32768) begin
                                state_q <= ST_FAIL;
                                fail_q <= 1'b1;
                            end else if (stream_index_q == 8'd255) begin
                                stream_index_q <= 8'd0;
                                capture_index_q <= 8'd0;
                                state_q <= ST_RMS_RESULT;
                            end else begin
                                stream_index_q <= stream_index_q + 1'b1;
                                state_q <= ST_RMS_INPUT_READ;
                            end
                        end
                    end

                    ST_RMS_RESULT: begin
                        if (rms_result_valid &&
                            ((rms_result_index != capture_index_q) ||
                             (rms_result_last !=
                              (capture_index_q == 8'd255)) ||
                             (rms_result_mantissa == -16'sd32768) ||
                             ((capture_index_q != 8'd0) &&
                              (rms_result_exponent !=
                               final_norm_exponent_q)))) begin
                            state_q <= ST_FAIL;
                            fail_q <= 1'b1;
                        end else if (rms_result_transfer) begin
                            if (capture_index_q == 8'd0)
                                final_norm_exponent_q <= rms_result_exponent;
                            if (capture_index_q == 8'd255) begin
                                capture_index_q <= 8'd0;
                                state_q <= ST_RMS_DONE;
                            end else begin
                                capture_index_q <= capture_index_q + 1'b1;
                            end
                        end
                    end

                    ST_RMS_DONE: begin
                        if (rms_done_transfer)
                            state_q <= ST_HEAD_START;
                    end

                    ST_HEAD_START: begin
                        if (private_head_start_valid_o &&
                            private_head_start_ready_i)
                            state_q <= ST_ARGMAX_START;
                    end

                    ST_ARGMAX_START: begin
                        if (argmax_start_valid && argmax_start_ready) begin
                            stream_index_q <= 8'd0;
                            head_done_seen_q <= 1'b0;
                            winner_seen_q <= 1'b0;
                            state_q <= ST_HEAD_INPUT_READ;
                        end
                    end

                    ST_HEAD_INPUT_READ: begin
                        state_q <= ST_HEAD_INPUT_SEND;
                    end

                    ST_HEAD_INPUT_SEND: begin
                        if (private_head_activation_valid_o &&
                            private_head_activation_ready_i) begin
                            if (final_norm_read_q == -16'sd32768) begin
                                state_q <= ST_FAIL;
                                fail_q <= 1'b1;
                            end else if (stream_index_q == 8'd255) begin
                                stream_index_q <= 8'd0;
                                state_q <= ST_HEAD_SCAN;
                            end else begin
                                stream_index_q <= stream_index_q + 1'b1;
                                state_q <= ST_HEAD_INPUT_READ;
                            end
                        end
                    end

                    ST_HEAD_SCAN: begin
                        if (head_done_transfer && !head_last_transfer) begin
                            state_q <= ST_FAIL;
                            fail_q <= 1'b1;
                        end else begin
                            if (head_done_transfer)
                                head_done_seen_q <= 1'b1;
                            if (head_last_transfer)
                                state_q <= ST_HEAD_TERMINALS;
                        end
                    end

                    ST_HEAD_TERMINALS: begin
                        if (private_head_result_valid_i) begin
                            state_q <= ST_FAIL;
                            fail_q <= 1'b1;
                        end else begin
                            if (head_done_transfer)
                                head_done_seen_q <= 1'b1;
                            if (winner_transfer) begin
                                winner_seen_q <= 1'b1;
                                winner_token_q <= argmax_winner_token;
                            end
                            if (head_terminals_complete) begin
                                if ((completing_winner >= VOCABULARY_SIZE) ||
                                    (tape_count_q >= TAPE_CAPACITY)) begin
                                    state_q <= ST_FAIL;
                                    fail_q <= 1'b1;
                                end else begin
                                    generated_token_q <= completing_winner;
                                    tape_count_q <= tape_count_q + 12'd1;
                                    head_done_seen_q <= 1'b0;
                                    winner_seen_q <= 1'b0;
                                    state_q <= ST_TOKEN_HOLD;
                                end
                            end
                        end
                    end

                    ST_TOKEN_HOLD: begin
                        if (token_transfer)
                            state_q <= ST_IDLE;
                    end

                    ST_CLEAR_DRAIN: begin
                        if ((ddr_owner_q == DDR_OWNER_EMBED) && !embed_busy)
                            ddr_owner_q <= DDR_OWNER_NONE;
                        if (!embed_busy && !rms_busy && !argmax_busy &&
                            !private_layer_busy_i) begin
                            if (!cleared_prefixes_match) begin
                                state_q <= ST_FAIL;
                                fail_q <= 1'b1;
                            end else begin
                                ddr_owner_q <= DDR_OWNER_NONE;
                                state_q <= ST_IDLE;
                            end
                        end
                    end

                    default: begin
                        state_q <= ST_FAIL;
                        fail_q <= 1'b1;
                    end
                endcase
            end
            if (upstream_fault_i || child_fault || lock_fault ||
                watchdog_fault || public_protocol_fault ||
                private_protocol_fault ||
                ((state_q == ST_IDLE) && model_lock_i &&
                 !committed_prefixes_match)) begin
                state_q <= ST_FAIL;
                fail_q <= 1'b1;
                ddr_owner_q <= ddr_owner_q;
            end
`ifndef SYNTHESIS
            if (simulation_x_fault) begin
                state_q <= ST_FAIL;
                fail_q <= 1'b1;
                ddr_owner_q <= ddr_owner_q;
            end
`endif
        end
    end

`ifdef FORMAL
    always_ff @(posedge clk) begin
        if (rst_n && !$past(clear_i)) begin
            if ($past(fail_q)) assert(fail_q);
            if ($past(token_valid_o) && !$past(token_ready_i)) begin
                assert(token_valid_o);
                assert(token_o == $past(token_o));
            end
            assert(tape_count_q <= TAPE_CAPACITY);
            assert(committed_count_q <= tape_count_q);
            assert(no_progress_cycles_q <= NO_PROGRESS_LAST);
            if (verified_forward_progress)
                assert(!watchdog_fault);
            if (append_ready_o || step_ready_o || token_valid_o)
                assert(model_lock_i && !fail_closed_o);
            if (private_word_req_valid_o)
                assert(ddr_owner_q == DDR_OWNER_EMBED);
            if (private_layer_start_valid_o)
                assert(private_layer_position_o < 11'd2048);
            if (private_layer_input_valid_o) begin
                assert(private_layer_input_mantissa_o != -16'sd32768);
                assert(private_layer_input_last_o ==
                       (private_layer_input_index_o == 8'd255));
            end
            if (private_head_activation_valid_o) begin
                assert(private_head_activation_mantissa_o != -16'sd32768);
                assert(private_head_activation_last_o ==
                       (private_head_activation_index_o == 8'd255));
            end
        end
        if (rst_n && clear_i) begin
            assert(!append_ready_o && !step_ready_o && !token_valid_o);
            assert(private_layer_clear_o);
        end
    end
`endif

    // Exact winning carrier remains structurally consumed without becoming a
    // public diagnostic/logit operation.
    wire _unused_winner_carrier = ^{argmax_winner_scaled,
                                     argmax_winner_exponent};
endmodule

`default_nettype wire
