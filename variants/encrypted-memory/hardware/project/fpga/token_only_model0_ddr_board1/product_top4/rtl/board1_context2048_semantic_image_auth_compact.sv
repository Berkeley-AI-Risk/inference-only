`timescale 1ns/1ps
`default_nettype none

// Sole product authorization engine: fixed-length, fixed-digest SHA-256 over
// the complete ordered DDR readback stream.  It has no start/length/digest
// selector and does not expose the computed digest outside this private seam.
module tang_confidential_ciphertext_image_auth (
    input  wire         trusted_clk_i,
    input  wire         trusted_reset_n_i,
    input  wire [255:0] readback_word_data_i,
    input  wire         readback_word_valid_i,
    input  wire         readback_word_last_i,
    output wire         readback_word_ready_o,
    output wire         digest_done_o,
    output wire         digest_ok_o,
    output wire         fail_closed_o
);
    localparam logic [17:0] MODEL_WORDS = 18'd227062;
    localparam logic [17:0] MODEL_LAST_WORD = 18'd227061;
    localparam logic [63:0] IMAGE_BITS = 64'h000000000376f600;
    localparam logic [255:0] EXPECTED_SHA256 =
        256'h88da38f3eb64bacc21aa472666b0cc8ea1e516cb04c80e0678f768425e6390eb;

    typedef enum logic [2:0] {
        ST_INIT      = 3'd0,
        ST_WORDS     = 3'd1,
        ST_PADDING   = 3'd2,
        ST_WAIT_HASH = 3'd3,
        ST_DONE      = 3'd4,
        ST_FAIL      = 3'd7
    } state_t;

    state_t state_q;
    logic [17:0] words_accepted_q;
    logic [255:0] word_buffer_q;
    logic word_buffer_valid_q;
    logic word_buffer_final_q;
    logic [4:0] word_byte_q;
    logic [5:0] padding_byte_q;
    logic done_q;
    logic ok_q;
    logic fail_q;

    wire sha_begin = state_q == ST_INIT && !fail_q;
    wire sha_byte_valid =
        (state_q == ST_WORDS && word_buffer_valid_q) ||
        state_q == ST_PADDING;
    logic [7:0] sha_byte_data;
    wire sha_byte_last = state_q == ST_PADDING &&
                         padding_byte_q == 6'd63;
    wire sha_byte_ready;
    wire sha_digest_valid;
    wire [255:0] sha_digest;
    wire sha_fault;

    always_comb begin
        if (state_q == ST_WORDS)
            sha_byte_data = word_buffer_q[word_byte_q*8 +: 8];
        else if (padding_byte_q == 6'd0)
            sha_byte_data = 8'h80;
        else if (padding_byte_q < 6'd56)
            sha_byte_data = 8'h00;
        else
            sha_byte_data =
                IMAGE_BITS[63 - (padding_byte_q-56)*8 -: 8];
    end

    board1_sha256_compact_padded_stream u_sole_compact_sha (
        .clk_i(trusted_clk_i), .reset_n_i(trusted_reset_n_i),
        .begin_i(sha_begin), .byte_valid_i(sha_byte_valid),
        .byte_ready_o(sha_byte_ready), .byte_data_i(sha_byte_data),
        .byte_last_i(sha_byte_last), .digest_valid_o(sha_digest_valid),
        .digest_o(sha_digest), .fault_o(sha_fault)
    );

    wire word_transfer = readback_word_valid_i && readback_word_ready_o;
    wire byte_transfer = sha_byte_valid && sha_byte_ready;
    wire expected_last = words_accepted_q == MODEL_LAST_WORD;
    wire last_protocol_fault = word_transfer &&
                               readback_word_last_i != expected_last;
    wire extra_word_fault = readback_word_valid_i &&
        (state_q != ST_WORDS || words_accepted_q == MODEL_WORDS);

`ifndef SYNTHESIS
    logic simulation_x_fault;
    always_comb begin
        simulation_x_fault = $isunknown(readback_word_valid_i) ||
            $isunknown(sha_fault) || $isunknown(sha_digest_valid);
        if (readback_word_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                $isunknown(readback_word_data_i) ||
                $isunknown(readback_word_last_i);
        if (sha_digest_valid === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                $isunknown(sha_digest);
    end
`else
    wire simulation_x_fault = 1'b0;
`endif

    assign readback_word_ready_o = state_q == ST_WORDS &&
        !word_buffer_valid_q && words_accepted_q < MODEL_WORDS && !fail_q;
    assign digest_done_o = done_q;
    assign digest_ok_o = done_q && ok_q && !fail_q;
    assign fail_closed_o = fail_q;

    initial begin
        if (MODEL_WORDS != 227062 || MODEL_LAST_WORD != 227061 ||
            IMAGE_BITS != 64'h000000000376f600 ||
            EXPECTED_SHA256 !=
            256'h88da38f3eb64bacc21aa472666b0cc8ea1e516cb04c80e0678f768425e6390eb)
            $fatal(1, "fixed compact readback authentication policy differs");
    end

    always_ff @(posedge trusted_clk_i or negedge trusted_reset_n_i) begin
        if (!trusted_reset_n_i) begin
            state_q <= ST_INIT;
            words_accepted_q <= 18'd0;
            word_buffer_q <= 256'd0;
            word_buffer_valid_q <= 1'b0;
            word_buffer_final_q <= 1'b0;
            word_byte_q <= 5'd0;
            padding_byte_q <= 6'd0;
            done_q <= 1'b0;
            ok_q <= 1'b0;
            fail_q <= 1'b0;
        end else if (simulation_x_fault || sha_fault ||
                     last_protocol_fault || extra_word_fault) begin
            state_q <= ST_FAIL;
            word_buffer_valid_q <= 1'b0;
            done_q <= 1'b1;
            ok_q <= 1'b0;
            fail_q <= 1'b1;
        end else begin
            case (state_q)
                ST_INIT: state_q <= ST_WORDS;
                ST_WORDS: begin
                    if (word_transfer) begin
                        word_buffer_q <= readback_word_data_i;
                        word_buffer_valid_q <= 1'b1;
                        word_buffer_final_q <= expected_last;
                        word_byte_q <= 5'd0;
                        words_accepted_q <= words_accepted_q + 1'b1;
                    end
                    if (byte_transfer) begin
                        if (word_byte_q == 5'd31) begin
                            word_buffer_valid_q <= 1'b0;
                            word_byte_q <= 5'd0;
                            if (word_buffer_final_q) begin
                                padding_byte_q <= 6'd0;
                                state_q <= ST_PADDING;
                            end
                        end else begin
                            word_byte_q <= word_byte_q + 1'b1;
                        end
                    end
                end
                ST_PADDING: if (byte_transfer) begin
                    if (padding_byte_q == 6'd63)
                        state_q <= ST_WAIT_HASH;
                    else
                        padding_byte_q <= padding_byte_q + 1'b1;
                end
                ST_WAIT_HASH: if (sha_digest_valid) begin
                    done_q <= 1'b1;
                    if (sha_digest == EXPECTED_SHA256) begin
                        ok_q <= 1'b1;
                        state_q <= ST_DONE;
                    end else begin
                        ok_q <= 1'b0;
                        fail_q <= 1'b1;
                        state_q <= ST_FAIL;
                    end
                end
                ST_DONE: state_q <= ST_DONE;
                default: begin
                    state_q <= ST_FAIL;
                    word_buffer_valid_q <= 1'b0;
                    done_q <= 1'b1;
                    ok_q <= 1'b0;
                    fail_q <= 1'b1;
                end
            endcase
        end
    end

`ifdef FORMAL
    logic formal_past_valid;
    always_ff @(posedge trusted_clk_i) begin
        formal_past_valid <= 1'b1;
        if (trusted_reset_n_i) begin
            assert (words_accepted_q <= MODEL_WORDS);
            if (digest_ok_o)
                assert (digest_done_o && !fail_closed_o &&
                        words_accepted_q == MODEL_WORDS);
            if (fail_closed_o)
                assert (digest_done_o && !digest_ok_o);
            if (formal_past_valid && $past(trusted_reset_n_i) &&
                $past(fail_q))
                assert (fail_q);
        end
    end
`endif
endmodule

`default_nettype wire
