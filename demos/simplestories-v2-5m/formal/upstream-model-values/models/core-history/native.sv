module board1_model_core_read_history (
 input wire core_clk_i,core_reset_n_i,core_req_valid_i,core_req_ready_o,core_rsp_valid_o,
 input wire[18:0]core_req_word_i,output wire[18:0]history_probe_o
);
 (* anyconst *)reg[5:0]f_slot;
 (* keep *)reg[7:0]f_A,f_D;
 (* keep *)reg[18:0]f_addresses[0:127];
 reg f_req_seen;reg[7:0]f_req_seq;reg[18:0]f_req_word;
 wire core_delivery=core_rsp_valid_o;
 wire f_source=core_reset_n_i && core_req_valid_i && core_req_ready_o;
 wire f_delivery=core_reset_n_i && core_delivery;
    always @(posedge core_clk_i)if(f_source)f_addresses[f_A[6:0]]<=core_req_word_i;
    always @(posedge core_clk_i or negedge core_reset_n_i)begin
        if(!core_reset_n_i)begin f_A<=0;f_D<=0;f_req_seen<=0;end
        else begin
            if(f_source)begin
                f_A<=f_A+1'b1;
                if(f_A[5:0]==f_slot)begin f_req_seen<=1;f_req_seq<=f_A;f_req_word<=core_req_word_i;end
            end
            if(f_delivery)f_D<=f_D+1'b1;
        end
    end
    assign history_probe_o=f_addresses[f_D[6:0]];
endmodule
