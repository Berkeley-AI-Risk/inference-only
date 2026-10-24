// Explicit proof boundary: arbitrary compressor replies, not a SHA proof.
// No assumptions about busy/done latency or the returned digest.
module board1_sha256_bank_owned_compress #(parameter REGISTER_RESULT=0) (
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
