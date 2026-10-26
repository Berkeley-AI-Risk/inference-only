// Optional isolated-guard boundary for run_control.py without --compose-hash.
// The documented full replay does NOT elaborate this module: it retains the
// real page-hash controller and abstracts only its SHA compressor instead.
// Every reply here is arbitrary; this does not prove page-hash or SHA behavior.
module kv_page_hash (
    input wire clk, reset_n, clear_i,
    input wire begin_valid_i,
    output wire begin_ready_o,
    input wire [63:0] epoch_i,
    input wire [2:0] layer_i,
    input wire [6:0] page_i,
    input wire head_i, role_i,
    input wire [4:0] positions_i,
    input wire word_valid_i,
    output wire word_ready_o,
    input wire [255:0] word_i,
    output wire digest_valid_o,
    input wire digest_ready_i,
    output wire [255:0] digest_o,
    output wire fault_o
);
    (* anyseq *) reg f_begin_ready, f_word_ready, f_digest_valid, f_fault;
    (* anyseq *) reg [255:0] f_digest;
    assign begin_ready_o = f_begin_ready;
    assign word_ready_o = f_word_ready;
    assign digest_valid_o = f_digest_valid;
    assign digest_o = f_digest;
    assign fault_o = f_fault;
endmodule
