// Formal-only SHA compressor boundary: arbitrary replies, no crypto claim.
module board1_sha256_compact_compress (
    input wire clk_i, reset_n_i, start_i,
    input wire [511:0] block_i,
    input wire [255:0] state_i,
    output wire busy_o, done_o,
    output wire [255:0] state_o
);
    (* anyseq *) reg f_busy, f_done;
    (* anyseq *) reg [255:0] f_state;
    assign busy_o = f_busy;
    assign done_o = f_done;
    assign state_o = f_state;
endmodule
