`timescale 1ns/1ps
`default_nettype none

// Immutable six-layer semantic schedule below the token-only machine.
//
// The stage descriptor is integration-private.  There is deliberately no
// product-visible layer, job, address, operation, dimension, or payload seam.
// The only descriptor accepted from above is the current token position; the
// six layer numbers and every transformer operation are generated here.
module board1_context2048_semantic_sequence (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    clear_i,
    input  wire                    model_lock_i,
    input  wire                    upstream_fault_i,

    input  wire                    start_valid_i,
    output logic                   start_ready_o,
    input  wire [10:0]             fixed_position_i,
    input  wire signed [7:0]       input_exponent_i,

    input  wire                    input_valid_i,
    output logic                   input_ready_o,
    input  wire [7:0]              input_index_i,
    input  wire signed [15:0]      input_mantissa_i,
    input  wire                    input_last_i,
    output logic                   private_ingress_write_o,

    // Fixed internal stage request.  These signals must remain below the
    // immutable semantic integration boundary.
    output logic                   private_stage_valid_o,
    input  wire                    private_stage_ready_i,
    output logic [4:0]             private_stage_o,
    output logic [2:0]             private_layer_o,
    output logic [10:0]            private_position_o,
    output logic signed [7:0]      private_input_exponent_o,
    input  wire                    private_stage_done_i,
    input  wire                    private_stage_fault_i,

    // The datapath supplies the already-computed final hidden vector through
    // a derived index.  There is no arbitrary read-address input.
    output logic [7:0]             private_result_index_o,
    input  wire signed [15:0]      private_result_mantissa_i,
    input  wire signed [7:0]       private_result_exponent_i,

    output logic                   result_valid_o,
    input  wire                    result_ready_i,
    output logic [7:0]             result_index_o,
    output logic signed [15:0]     result_mantissa_o,
    output logic signed [7:0]      result_exponent_o,
    output logic                   result_last_o,
    output logic                   done_valid_o,
    input  wire                    done_ready_i,

    input  wire [71:0]             committed_prefixes_i,
    output logic                   busy_o,
    output logic                   range_fault_o
);
    // Exact Board0/W10-A16-KV16-BFP-v5 order.  Projection stage names imply
    // projection postscale followed by whole-vector BFP normalization.
    localparam logic [4:0] STAGE_INPUT_RMS = 5'd0;
    localparam logic [4:0] STAGE_RESIDUAL_2 = 5'd15;
    localparam logic [4:0] STAGE_KV_COMMIT  = 5'd16;

    typedef enum logic [2:0] {
        S_IDLE        = 3'd0,
        S_INGRESS     = 3'd1,
        S_STAGE_START = 3'd2,
        S_STAGE_WAIT  = 3'd3,
        S_RESULT      = 3'd4,
        S_DONE        = 3'd5,
        S_RESULT_REQ  = 3'd6,
        S_FAULT       = 3'd7
    } state_t;

    state_t state_q;
    logic [2:0] layer_q;
    logic [4:0] stage_q;
    logic [10:0] position_q;
    logic signed [7:0] input_exponent_q;
    logic [7:0] stream_index_q;
    logic signed [7:0] result_exponent_q;
    logic fault_q;
    logic lock_seen_q;
    logic protocol_fault;
    logic prefixes_match;
`ifndef SYNTHESIS
    logic simulation_x_fault;
`endif

    integer prefix_index;
    always @* begin
        prefixes_match = 1'b1;
        for (prefix_index = 0; prefix_index < 6;
             prefix_index = prefix_index + 1)
            if (committed_prefixes_i[prefix_index*12 +: 12] !=
                {1'b0, fixed_position_i})
                prefixes_match = 1'b0;
    end

    wire start_fire = start_valid_i && start_ready_o;
    wire input_fire = input_valid_i && input_ready_o;
    wire stage_start_fire = private_stage_valid_o && private_stage_ready_i;
    wire result_fire = result_valid_o && result_ready_i;
    wire done_fire = done_valid_o && done_ready_i;
    wire input_legal = (input_index_i == stream_index_q) &&
        (input_last_i == (stream_index_q == 8'd255)) &&
        (input_mantissa_i != 16'sh8000);

    always @* begin
        protocol_fault = upstream_fault_i || private_stage_fault_i ||
            (lock_seen_q && !model_lock_i) ||
            (private_stage_done_i && (state_q != S_STAGE_WAIT));
    end

`ifndef SYNTHESIS
    always @* begin
        simulation_x_fault = $isunknown(clear_i) ||
            $isunknown(model_lock_i) || $isunknown(upstream_fault_i) ||
            $isunknown(start_valid_i) ||
            $isunknown(private_stage_ready_i) ||
            $isunknown(private_stage_done_i) ||
            $isunknown(private_stage_fault_i) ||
            $isunknown(result_ready_i) || $isunknown(done_ready_i) ||
            $isunknown(committed_prefixes_i);
        if (start_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                $isunknown(fixed_position_i) ||
                $isunknown(input_exponent_i);
        if (state_q == S_INGRESS) begin
            simulation_x_fault = simulation_x_fault ||
                $isunknown(input_valid_i);
            if (input_valid_i === 1'b1)
                simulation_x_fault = simulation_x_fault ||
                    $isunknown(input_index_i) ||
                    $isunknown(input_mantissa_i) ||
                    $isunknown(input_last_i);
        end
        if (state_q == S_RESULT)
            simulation_x_fault = simulation_x_fault ||
                $isunknown(private_result_mantissa_i) ||
                $isunknown(private_result_exponent_i);
    end
`endif

    always @* begin
        start_ready_o = rst_n && !clear_i && (state_q == S_IDLE) &&
            model_lock_i && !fault_q && !upstream_fault_i;
        input_ready_o = rst_n && !clear_i && (state_q == S_INGRESS) &&
            !fault_q;
        private_ingress_write_o = input_fire && input_legal && !fault_q;

        private_stage_valid_o = rst_n && !clear_i &&
            (state_q == S_STAGE_START) && !fault_q;
        private_stage_o = stage_q;
        private_layer_o = layer_q;
        private_position_o = position_q;
        private_input_exponent_o = input_exponent_q;

        private_result_index_o = stream_index_q;
        result_valid_o = rst_n && !clear_i && (state_q == S_RESULT) &&
            !fault_q;
        result_index_o = stream_index_q;
        result_mantissa_o = result_valid_o ? private_result_mantissa_i :
                                             16'sd0;
        result_exponent_o = result_valid_o ? result_exponent_q : 8'sd0;
        result_last_o = result_valid_o && (stream_index_q == 8'd255);
        done_valid_o = rst_n && !clear_i && (state_q == S_DONE) && !fault_q;
        busy_o = (state_q != S_IDLE) && (state_q != S_FAULT);
        range_fault_o = fault_q;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= S_IDLE;
            layer_q <= 3'd0;
            stage_q <= STAGE_INPUT_RMS;
            position_q <= 11'd0;
            input_exponent_q <= 8'sd0;
            stream_index_q <= 8'd0;
            result_exponent_q <= 8'sd0;
            fault_q <= 1'b0;
            lock_seen_q <= 1'b0;
        end else begin
            if (model_lock_i)
                lock_seen_q <= 1'b1;

            if (protocol_fault
`ifndef SYNTHESIS
                || simulation_x_fault
`endif
            ) begin
                fault_q <= 1'b1;
                state_q <= S_FAULT;
            end else if (clear_i) begin
                // CLEAR aborts transaction state.  It never clears a sticky
                // semantic/model-integrity fault; only reset does that.
                if (fault_q)
                    state_q <= S_FAULT;
                else
                    state_q <= S_IDLE;
                layer_q <= 3'd0;
                stage_q <= STAGE_INPUT_RMS;
                position_q <= 11'd0;
                input_exponent_q <= 8'sd0;
                stream_index_q <= 8'd0;
                result_exponent_q <= 8'sd0;
            end else if (fault_q) begin
                state_q <= S_FAULT;
            end else begin
                case (state_q)
                    S_IDLE: begin
                        if (start_fire) begin
                            if (!prefixes_match ||
                                (input_exponent_i < -8'sd32) ||
                                (input_exponent_i > 8'sd31)) begin
                                fault_q <= 1'b1;
                                state_q <= S_FAULT;
                            end else begin
                                position_q <= fixed_position_i;
                                input_exponent_q <= input_exponent_i;
                                layer_q <= 3'd0;
                                stage_q <= STAGE_INPUT_RMS;
                                stream_index_q <= 8'd0;
                                state_q <= S_INGRESS;
                            end
                        end
                    end

                    S_INGRESS: begin
                        if (input_fire) begin
                            if (!input_legal) begin
                                fault_q <= 1'b1;
                                state_q <= S_FAULT;
                            end else if (stream_index_q == 8'd255) begin
                                stream_index_q <= 8'd0;
                                state_q <= S_STAGE_START;
                            end else begin
                                stream_index_q <= stream_index_q + 1'b1;
                            end
                        end
                    end

                    S_STAGE_START: begin
                        if (stage_start_fire)
                            state_q <= S_STAGE_WAIT;
                    end

                    S_STAGE_WAIT: begin
                        if (private_stage_done_i) begin
                            if (stage_q < STAGE_RESIDUAL_2) begin
                                stage_q <= stage_q + 1'b1;
                                state_q <= S_STAGE_START;
                            end else if (stage_q == STAGE_RESIDUAL_2) begin
                                if (layer_q == 3'd5) begin
                                    stream_index_q <= 8'd0;
                                    result_exponent_q <=
                                        private_result_exponent_i;
                                    state_q <= S_RESULT_REQ;
                                end else begin
                                    stage_q <= STAGE_KV_COMMIT;
                                    state_q <= S_STAGE_START;
                                end
                            end else if (stage_q == STAGE_KV_COMMIT) begin
                                if (layer_q == 3'd5) begin
                                    state_q <= S_DONE;
                                end else begin
                                    layer_q <= layer_q + 1'b1;
                                    stage_q <= STAGE_INPUT_RMS;
                                    state_q <= S_STAGE_START;
                                end
                            end else begin
                                fault_q <= 1'b1;
                                state_q <= S_FAULT;
                            end
                        end
                    end

                    S_RESULT_REQ: begin
                        // The hidden state is a private synchronous BSRAM.
                        // Hold its derived coordinate for one full cycle
                        // before presenting the corresponding result beat.
                        state_q <= S_RESULT;
                    end

                    S_RESULT: begin
                        if (private_result_exponent_i != result_exponent_q ||
                            (private_result_mantissa_i == 16'sh8000)) begin
                            fault_q <= 1'b1;
                            state_q <= S_FAULT;
                        end else if (result_fire) begin
                            if (stream_index_q == 8'd255) begin
                                stream_index_q <= 8'd0;
                                stage_q <= STAGE_KV_COMMIT;
                                state_q <= S_STAGE_START;
                            end else begin
                                stream_index_q <= stream_index_q + 1'b1;
                                state_q <= S_RESULT_REQ;
                            end
                        end
                    end

                    S_DONE: begin
                        if (done_fire)
                            state_q <= S_IDLE;
                    end

                    default: begin
                        fault_q <= 1'b1;
                        state_q <= S_FAULT;
                    end
                endcase
            end
        end
    end

endmodule

`default_nettype wire
