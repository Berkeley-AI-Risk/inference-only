`default_nettype none
// Abstract flow contract, not a SHA implementation or cryptographic theorem.
module su_sha256 #(
    parameter bit USE_SHARED_COMPRESSOR=0,
    parameter integer MAX_BYTES=4096
)(
    input wire clk,reset_n,start_i,
    input wire [31:0] length_i,
    input wire byte_valid_i,
    output wire byte_ready_o,
    input wire [7:0] byte_i,
    output wire [31:0] byte_offset_o,
    output wire busy_o,
    output logic done_o,
    output wire fault_o,
    output logic [255:0] digest_o,
    output wire shared_request_o,
    output wire [511:0] shared_block_o,
    output wire [255:0] shared_state_o,
    input wire shared_accept_i,shared_done_i,
    input wire [255:0] shared_digest_i
);
    logic busy_q;
    logic [12:0] count_q;
    (* anyseq *) wire ready_choice,finish_choice;
    (* anyseq *) wire [255:0] digest_choice;
    assign byte_ready_o=busy_q && count_q<13'(MAX_BYTES) && ready_choice;
    assign byte_offset_o={19'd0,count_q};
    assign busy_o=busy_q;
    assign fault_o=0;
    assign shared_request_o=0;
    assign shared_block_o=0;
    assign shared_state_o=0;
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin busy_q<=0;count_q<=0;done_o<=0;digest_o<=0;end
        else begin
            done_o<=0;
            if(start_i) begin busy_q<=1;count_q<=0;end
            else if(busy_q) begin
                if(byte_valid_i && byte_ready_o) count_q<=count_q+1;
                if(count_q==13'(MAX_BYTES) && finish_choice) begin
                    busy_q<=0;done_o<=1;digest_o<=digest_choice;
                end
            end
        end
    end
endmodule

module board1_sha256_compact_compress(
    input wire clk_i,reset_n_i,start_i,
    input wire [511:0] block_i,
    input wire [255:0] state_i,
    output logic busy_o,done_o,
    output wire [255:0] state_o
);
    (* anyseq *) wire finish;
    (* anyseq *) wire [255:0] result;
    assign state_o=result;
    always_ff @(posedge clk_i or negedge reset_n_i) begin
        if(!reset_n_i) begin busy_o<=0;done_o<=0;end
        else begin
            done_o<=0;
            if(start_i && !busy_o) busy_o<=1;
            else if(busy_o && finish) begin busy_o<=0;done_o<=1;end
        end
    end
endmodule
`default_nettype wire
