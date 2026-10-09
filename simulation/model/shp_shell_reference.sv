`default_nettype none
module shp_shell_reference #(parameter integer ADDR_W=19, MAX_NO_PROGRESS_CYCLES=100000000)(
    input wire append_transfer,
    input wire argmax_busy,
    input wire argmax_start_ready,
    input wire argmax_start_valid,
    input wire [11:0] argmax_winner_token,
    input wire child_fault,
    input wire clear_i,
    input wire cleared_prefixes_match,
    input wire clk,
    input wire committed_prefixes_match,
    input wire [11:0] completing_winner,
    input wire compute_active,
    input wire embed_busy,
    input wire embed_done_transfer,
    input wire signed [7:0] embed_result_exponent,
    input wire [7:0] embed_result_index,
    input wire embed_result_last,
    input wire signed [15:0] embed_result_mantissa,
    input wire embed_result_transfer,
    input wire embed_result_valid,
    input wire embed_start_ready,
    input wire embed_start_valid,
    input wire signed [15:0] embedding_read_q,
    input wire signed [15:0] final_norm_read_q,
    input wire head_done_transfer,
    input wire head_last_transfer,
    input wire head_terminals_complete,
    input wire signed [15:0] layer5_read_q,
    input wire layer_done_transfer,
    input wire layer_input_transfer,
    input wire layer_result_transfer,
    input wire layer_start_transfer,
    input wire lock_fault,
    input wire model_lock_i,
    input wire next_prefixes_match,
    input wire private_head_activation_ready_i,
    input wire private_head_activation_valid_o,
    input wire private_head_result_valid_i,
    input wire private_head_start_ready_i,
    input wire private_head_start_valid_o,
    input wire private_layer_busy_i,
    input wire signed [7:0] private_layer_result_exponent_i,
    input wire [7:0] private_layer_result_index_i,
    input wire private_layer_result_last_i,
    input wire signed [15:0] private_layer_result_mantissa_i,
    input wire private_layer_result_valid_i,
    input wire private_protocol_fault,
    input wire public_protocol_fault,
    input wire replay_is_needed,
    input wire rms_busy,
    input wire rms_done_transfer,
    input wire rms_input_ready,
    input wire rms_input_valid,
    input wire signed [7:0] rms_result_exponent,
    input wire [7:0] rms_result_index,
    input wire rms_result_last,
    input wire signed [15:0] rms_result_mantissa,
    input wire rms_result_transfer,
    input wire rms_result_valid,
    input wire rms_start_ready,
    input wire rms_start_valid,
    input wire rst_n,
    input wire simulation_x_fault,
    input wire step_transfer,
    input wire token_transfer,
    input wire upstream_fault_i,
    input wire verified_forward_progress,
    input wire watchdog_fault,
    input wire winner_transfer,
    output wire fault_o,owner_o,
    output wire [4:0] state_o,
    output wire [129:0] data_o
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

    localparam logic [26:0] NO_PROGRESS_LAST =
        27'(MAX_NO_PROGRESS_CYCLES - 1);
    logic [7:0] capture_index_q;
    logic [11:0] committed_count_q;
    logic ddr_owner_q;
    logic signed [7:0] embedding_exponent_q;
    logic fail_q;
    logic signed [7:0] final_norm_exponent_q;
    logic [11:0] generated_token_q;
    logic head_done_seen_q;
    logic last_hidden_valid_q;
    logic signed [7:0] layer5_exponent_q;
    logic [26:0] no_progress_cycles_q;
    logic [11:0] replay_position_q;
    state_t state_q;
    logic [7:0] stream_index_q;
    logic [11:0] tape_count_q;
    logic winner_seen_q;
    logic [11:0] winner_token_q;
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
`ifndef SYNTHESIS
            if (simulation_x_fault) begin
                state_q <= ST_FAIL;
                fail_q <= 1'b1;
            end else
`endif
            if (upstream_fault_i || child_fault || lock_fault ||
                watchdog_fault || public_protocol_fault ||
                private_protocol_fault ||
                ((state_q == ST_IDLE) && model_lock_i &&
                 !committed_prefixes_match)) begin
                state_q <= ST_FAIL;
                fail_q <= 1'b1;
            end else if (clear_i) begin
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
        end
    end
    assign fault_o=fail_q;
    assign state_o=state_q;
    assign owner_o=ddr_owner_q;
    assign data_o={capture_index_q,committed_count_q,embedding_exponent_q,final_norm_exponent_q,generated_token_q,head_done_seen_q,last_hidden_valid_q,layer5_exponent_q,no_progress_cycles_q,replay_position_q,stream_index_q,tape_count_q,winner_seen_q,winner_token_q};
endmodule
