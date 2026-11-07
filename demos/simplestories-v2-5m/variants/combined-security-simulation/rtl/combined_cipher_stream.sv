`timescale 1ns/1ps
`default_nettype none
// Complete image stream, fixed absolute counter order, private test-vault key.
// Both real inherited AES-256 engines retain every round; only one is live.
module combined_cipher_stream(
    input wire clk,reset_n,enabled_i,model_slot_i,
    input wire [95:0] model_nonce_i,
    input wire cipher_valid_i,
    output wire cipher_ready_o,
    input wire [255:0] cipher_word_i,
    output wire plain_valid_o,
    input wire plain_ready_i,
    output wire [255:0] plain_word_o,
    output logic fault_o
);
    localparam [2:0] INPUT=0,LOW=1,WAIT_LOW=2,HIGH=3,WAIT_HIGH=4,HOLD=5,DONE=6;
    logic [2:0] state_q;
    logic [17:0] word_q;
    logic [255:0] cipher_q,plain_q;
    logic [95:0] nonce_q;
    logic slot_q;
    wire aes_ready,aes_busy,aes_done;
    wire [127:0] aes_result;
    wire start=(state_q==LOW || state_q==HIGH) && enabled_i && !fault_o;
    wire [31:0] counter={13'd0,word_q,state_q==HIGH};
    function automatic [127:0] memory_order(input [127:0] block);
        for(integer b=0;b<16;b=b+1) memory_order[b*8+:8]=block[127-b*8-:8];
    endfunction
    combined_weight_aes u_aes(.clk(clk),.reset_n(reset_n),.model_slot_i(slot_q),
        .abort_i(fault_o),.start_i(start),.block_i({nonce_q,counter}),
        .ready_o(aes_ready),.busy_o(aes_busy),.done_o(aes_done),.block_o(aes_result));
    assign cipher_ready_o=reset_n && enabled_i && !fault_o && state_q==INPUT;
    assign plain_valid_o=reset_n && enabled_i && !fault_o && state_q==HOLD;
    assign plain_word_o=plain_valid_o ? plain_q : 256'd0;
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin state_q<=INPUT;word_q<=0;cipher_q<=0;plain_q<=0;nonce_q<=0;slot_q<=0;fault_o<=0;end
        else if(fault_o || (aes_done && state_q!=WAIT_LOW && state_q!=WAIT_HIGH)) fault_o<=1;
        else case(state_q)
            INPUT: if(cipher_valid_i && cipher_ready_o) begin
                cipher_q<=cipher_word_i;nonce_q<=model_nonce_i;slot_q<=model_slot_i;state_q<=LOW;
            end
            LOW: if(aes_ready) state_q<=WAIT_LOW;
            WAIT_LOW: if(aes_done) begin plain_q[127:0]<=cipher_q[127:0]^memory_order(aes_result);state_q<=HIGH;end
            HIGH: if(aes_ready) state_q<=WAIT_HIGH;
            WAIT_HIGH: if(aes_done) begin plain_q[255:128]<=cipher_q[255:128]^memory_order(aes_result);state_q<=HOLD;end
            HOLD: if(plain_valid_o && plain_ready_i) begin
                plain_q<=0;cipher_q<=0;
                if(word_q==18'd227061) state_q<=DONE;
                else begin word_q<=word_q+1'b1;state_q<=INPUT;end
            end
            DONE: begin end
            default: fault_o<=1;
        endcase
    end
endmodule
`default_nettype wire
