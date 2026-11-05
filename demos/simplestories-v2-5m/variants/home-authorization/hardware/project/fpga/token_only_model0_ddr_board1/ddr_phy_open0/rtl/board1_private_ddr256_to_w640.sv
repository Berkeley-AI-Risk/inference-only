`timescale 1ns/1ps
`default_nettype none

// Private, fixed-ratio stream adapter for Board1's existing exact 64-lane
// engine: 64 signed 10-bit weights form one 640-bit engine beat, while the
// normalized DDR application port returns 256-bit words.
//
// Two 640-bit beats are exactly five consecutive 256-bit DDR words.  This
// adapter preserves bit order with no padding and, when both sides are ready,
// accepts all five words and emits both beats in the same five clocks.  It has
// no address, write, job, matrix, tensor, or public command interface.  The
// fixed sequencer must provide an aligned, contiguous private response stream;
// public APPEND/STEP/CLEAR cannot reach this block.
module board1_private_ddr256_to_w640 (
    input  wire         clk,
    input  wire         reset_n,

    input  wire         ddr_word_valid,
    output logic        ddr_word_ready,
    input  wire [255:0] ddr_word_data,

    output logic        weight_valid,
    input  wire         weight_ready,
    output logic [639:0] weight_data,

    // Private diagnostic/status bit.  A fixed image region may begin only at
    // this five-word boundary.  It is not a reset or public control input.
    output wire         pair_boundary
);
    localparam logic [2:0] P_EVEN_WORD0 = 3'd0;
    localparam logic [2:0] P_EVEN_WORD1 = 3'd1;
    localparam logic [2:0] P_EVEN_WORD2 = 3'd2;
    localparam logic [2:0] P_ODD_WORD1  = 3'd3;
    localparam logic [2:0] P_ODD_WORD2  = 3'd4;

    logic [2:0] phase;
    logic [255:0] low_word;
    logic [255:0] middle_word;
    logic [127:0] shared_half_word;

    wire input_transfer = ddr_word_valid && ddr_word_ready;

    assign pair_boundary = (phase == P_EVEN_WORD0);

    always_comb begin
        ddr_word_ready = 1'b0;
        weight_valid = 1'b0;
        weight_data = {640{1'b0}};

        case (phase)
            P_EVEN_WORD0,
            P_EVEN_WORD1,
            P_ODD_WORD1: begin
                ddr_word_ready = 1'b1;
            end

            P_EVEN_WORD2: begin
                // Earliest stream bit remains bit zero of the engine beat.
                weight_data = {ddr_word_data[127:0], middle_word, low_word};
                weight_valid = ddr_word_valid;
                ddr_word_ready = weight_ready;
            end

            P_ODD_WORD2: begin
                weight_data = {ddr_word_data, middle_word, shared_half_word};
                weight_valid = ddr_word_valid;
                ddr_word_ready = weight_ready;
            end

            default: begin
            end
        endcase
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            phase <= P_EVEN_WORD0;
            low_word <= {256{1'b0}};
            middle_word <= {256{1'b0}};
            shared_half_word <= {128{1'b0}};
        end else if (input_transfer) begin
            case (phase)
                P_EVEN_WORD0: begin
                    low_word <= ddr_word_data;
                    phase <= P_EVEN_WORD1;
                end
                P_EVEN_WORD1: begin
                    middle_word <= ddr_word_data;
                    phase <= P_EVEN_WORD2;
                end
                P_EVEN_WORD2: begin
                    shared_half_word <= ddr_word_data[255:128];
                    phase <= P_ODD_WORD1;
                end
                P_ODD_WORD1: begin
                    middle_word <= ddr_word_data;
                    phase <= P_ODD_WORD2;
                end
                P_ODD_WORD2: begin
                    phase <= P_EVEN_WORD0;
                end
                default: begin
                    phase <= P_EVEN_WORD0;
                end
            endcase
        end
    end

`ifdef FORMAL
    always_ff @(posedge clk) begin
        if (reset_n) begin
            assert (phase <= P_ODD_WORD2);
            if (weight_valid)
                assert ((phase == P_EVEN_WORD2) || (phase == P_ODD_WORD2));
            if (weight_valid && !weight_ready) begin
                assert (!ddr_word_ready);
                assert (!input_transfer);
            end
        end
    end
`endif
endmodule

`default_nettype wire
