`timescale 1ns/1ps
`default_nettype none

// Private, typed address policy for the 2,048-token Board1 successor.
//
// This is not a host-facing memory port.  Upstream fixed-function control may
// request either an immutable model read or a K/V access described by semantic
// fields.  Only this block derives the private DDR word address and write bit.
module board1_context2048_typed_address_mapper (
    input  wire         request_valid_i,
    input  wire  [1:0]  request_class_i,
    input  wire         request_direction_i,
    input  wire  [18:0] model_word_index_i,
    input  wire  [2:0]  layer_i,
    input  wire  [11:0] position_i,
    input  wire  [1:0]  kv_head_i,
    input  wire  [3:0]  row_word_i,

    output logic        private_command_valid_o,
    output logic [18:0] private_word_address_o,
    output logic        private_write_o,
    output logic        request_reject_o
);
    localparam logic [1:0] REQUEST_MODEL = 2'b00;
    localparam logic [1:0] REQUEST_KV    = 2'b01;

    localparam logic [18:0] MODEL_WORDS = 19'd227062;
    localparam logic [18:0] KV_BASE = 19'd227072;
    localparam logic [2:0]  LAYER_COUNT = 3'd6;
    localparam logic [11:0] CONTEXT_LIMIT = 12'd2048;
    localparam logic [1:0]  KV_HEAD_COUNT = 2'd2;
    localparam logic [3:0]  ROW_WORD_COUNT = 4'd9;

    logic [13:0] layer_position;
    logic [14:0] encoded_row;
    logic [18:0] encoded_word_offset;

    // The valid-domain arithmetic is entirely fixed:
    // row = ((layer * 2048 + position) * 2 + kv_head).
    always_comb begin
        layer_position = {layer_i, position_i[10:0]};
        encoded_row = {layer_position, 1'b0} +
                      {{13{1'b0}}, kv_head_i};
        encoded_word_offset = {1'b0, encoded_row, 3'b000} +
                              {4'b0000, encoded_row} +
                              {{15{1'b0}}, row_word_i};

        private_command_valid_o = 1'b0;
        private_word_address_o = 19'd0;
        private_write_o = 1'b0;
        request_reject_o = 1'b0;

        // Explicit case defaults make every X/Z control encoding fail closed
        // in four-state simulation while remaining ordinary synthesizable
        // combinational logic.
        case (request_valid_i)
            1'b0: begin
                // Idle: typed fields are ignored.
            end
            1'b1: begin
                request_reject_o = 1'b1;
                case (request_class_i)
                    REQUEST_MODEL: begin
                        // There is deliberately no legal model-write form.
                        if ((request_direction_i == 1'b0) &&
                            (model_word_index_i < MODEL_WORDS)) begin
                            private_command_valid_o = 1'b1;
                            private_word_address_o = model_word_index_i;
                            private_write_o = 1'b0;
                            request_reject_o = 1'b0;
                        end
                    end
                    REQUEST_KV: begin
                        // Both K/V reads and K/V writes are legal, but an
                        // unknown direction is not allowed to propagate.
                        case (request_direction_i)
                            1'b0, 1'b1: begin
                                if ((layer_i < LAYER_COUNT) &&
                                    (position_i < CONTEXT_LIMIT) &&
                                    (kv_head_i < KV_HEAD_COUNT) &&
                                    (row_word_i < ROW_WORD_COUNT)) begin
                                    private_command_valid_o = 1'b1;
                                    private_word_address_o =
                                        KV_BASE + encoded_word_offset;
                                    private_write_o = request_direction_i;
                                    request_reject_o = 1'b0;
                                end
                            end
                            default: begin
                                // Fail closed on X/Z direction.
                            end
                        endcase
                    end
                    default: begin
                        // Two reserved request classes remain inert.
                    end
                endcase
            end
            default: begin
                // X/Z request-valid is rejected, never issued.
                request_reject_o = 1'b1;
            end
        endcase
    end
endmodule

`default_nettype wire
