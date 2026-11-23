`timescale 1ns/1ps
`default_nettype none
// One common-reset owner for encrypted-image loading, ordered readback and
// runtime DDR. Boot readback never bypasses the real decrypt/scan pipeline.
// The physical transport keeps the ordered writes ahead of the first read.
module combined_board_memory #(
    parameter integer IMAGE_WORDS=227062
)(
    input wire clk,reset_n,upstream_fault_i,boot_locked_i,
    input wire loader_valid_i,loader_done_i,
    input wire [255:0] loader_data_i,
    output wire loader_ready_o,
    output wire cipher_valid_o,
    output wire [255:0] cipher_data_o,
    input wire cipher_ready_i,
    input wire runtime_req_valid_i,runtime_req_write_i,
    input wire [18:0] runtime_req_word_i,
    input wire [255:0] runtime_req_data_i,
    output wire runtime_req_ready_o,runtime_rsp_valid_o,runtime_rsp_error_o,
    output wire [255:0] runtime_rsp_data_o,
    output wire phy_req_valid_o,phy_req_write_o,
    output wire [18:0] phy_req_word_o,
    output wire [255:0] phy_req_data_o,
    input wire phy_req_ready_i,phy_rsp_valid_i,phy_rsp_error_i,
    input wire [255:0] phy_rsp_data_i,
    output wire fault_o,readback_done_o
);
    localparam [2:0] LOAD=0,WAIT_SOURCE=1,READ_ISSUE=2,READ_WAIT=3,
        READ_HOLD=4,WAIT_LOCK=5,RUNTIME=6,FAILED=7;
    logic [2:0] state_q;
    logic [17:0] index_q;
    logic [255:0] return_q;
    logic fault_q;
    wire runtime=state_q==RUNTIME;
    wire bad_return=phy_rsp_valid_i && state_q!=READ_WAIT && !runtime;
    wire error_return=phy_rsp_valid_i && phy_rsp_error_i;
    wire live=reset_n && !fault_q && !upstream_fault_i && !bad_return && !error_return;
    assign fault_o=fault_q || upstream_fault_i || bad_return || error_return;
    assign loader_ready_o=live && state_q==LOAD && phy_req_ready_i;
    assign cipher_valid_o=live && state_q==READ_HOLD;
    assign cipher_data_o=cipher_valid_o ? return_q : 256'd0;
    assign runtime_req_ready_o=live && runtime && phy_req_ready_i;
    assign runtime_rsp_valid_o=reset_n && runtime && phy_rsp_valid_i;
    assign runtime_rsp_error_o=runtime_rsp_valid_o && (phy_rsp_error_i || fault_o);
    assign runtime_rsp_data_o=runtime_rsp_valid_o ? phy_rsp_data_i : 256'd0;
    assign phy_req_valid_o=live && ((state_q==LOAD && loader_valid_i) ||
        state_q==READ_ISSUE || (runtime && runtime_req_valid_i));
    assign phy_req_write_o=state_q==LOAD || (runtime && runtime_req_write_i);
    assign phy_req_word_o=runtime ? runtime_req_word_i : {1'b0,index_q};
    assign phy_req_data_o=runtime ? runtime_req_data_i : loader_data_i;
    assign readback_done_o=state_q==WAIT_LOCK || runtime;
    initial begin
        if(IMAGE_WORDS<1 || IMAGE_WORDS>227062) $fatal(1,"Invalid fixed image extent");
    end
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin state_q<=LOAD;index_q<=0;return_q<=0;fault_q<=0;end
        else if(fault_o) begin fault_q<=1;state_q<=FAILED;end
        else case(state_q)
            LOAD: begin
                if(loader_done_i) begin fault_q<=1;state_q<=FAILED;end
                else if(loader_valid_i && loader_ready_o) begin
                    if(index_q==18'(IMAGE_WORDS-1)) begin index_q<=0;state_q<=WAIT_SOURCE;end
                    else index_q<=index_q+1'b1;
                end
            end
            WAIT_SOURCE: begin
                if(loader_valid_i) begin fault_q<=1;state_q<=FAILED;end
                else if(loader_done_i) state_q<=READ_ISSUE;
            end
            READ_ISSUE: if(phy_req_valid_o && phy_req_ready_i) state_q<=READ_WAIT;
            READ_WAIT: if(phy_rsp_valid_i) begin return_q<=phy_rsp_data_i;state_q<=READ_HOLD;end
            READ_HOLD: if(cipher_valid_o && cipher_ready_i) begin
                if(index_q==18'(IMAGE_WORDS-1)) state_q<=WAIT_LOCK;
                else begin index_q<=index_q+1'b1;state_q<=READ_ISSUE;end
            end
            WAIT_LOCK: if(boot_locked_i) state_q<=RUNTIME;
            RUNTIME: if(!boot_locked_i) begin fault_q<=1;state_q<=FAILED;end
            default: begin fault_q<=1;state_q<=FAILED;end
        endcase
    end
endmodule
`default_nettype wire
