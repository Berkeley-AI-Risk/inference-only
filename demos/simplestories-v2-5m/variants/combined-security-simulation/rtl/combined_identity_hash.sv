`timescale 1ns/1ps
`default_nettype none
// This context commitment is the root field of the unchanged home protocol.
// It cryptographically binds the admitted model, private key domain and epoch.
module combined_identity_hash(
    input wire clk,reset_n,enable_i,
    input wire [255:0] model_root_i,
    input wire [31:0] epoch_i,key_domain_i,
    output wire valid_o,
    output logic [255:0] digest_o,
    output wire fault_o
);
    localparam [127:0] DOMAIN=128'h53415749432d434f4d424f2d76310000;
    logic started_q,valid_q,local_fault_q;
    logic [255:0] root_q;
    logic [31:0] epoch_q,key_q;
    wire [447:0] message={DOMAIN,root_q,epoch_q,key_q};
    wire [31:0] offset;
    wire ready,busy,done,sha_fault;
    wire [255:0] digest;
    wire start=enable_i && !started_q;
    wire [7:0] byte_value=offset<56 ? message[447-int'(offset)*8-:8] : 8'd0;
    assign valid_o=valid_q && !fault_o;
    assign fault_o=local_fault_q || sha_fault;
    su_sha256 #(.MAX_BYTES(56)) u_sha(.clk(clk),.reset_n(reset_n),.start_i(start),.length_i(32'd56),
        .byte_valid_i(started_q && !valid_q && offset<56 && !fault_o),.byte_ready_o(ready),
        .byte_i(byte_value),.byte_offset_o(offset),.busy_o(busy),.done_o(done),.fault_o(sha_fault),.digest_o(digest),
        .shared_request_o(),.shared_block_o(),.shared_state_o(),.shared_accept_i(1'b0),.shared_done_i(1'b0),.shared_digest_i(256'd0));
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin started_q<=0;valid_q<=0;local_fault_q<=0;root_q<=0;epoch_q<=0;key_q<=0;digest_o<=0;end
        else begin
            if(start) begin
                started_q<=1;root_q<=model_root_i;epoch_q<=epoch_i;key_q<=key_domain_i;
                if(epoch_i==0 || key_domain_i==0) local_fault_q<=1;
            end
            if(started_q && (!enable_i || model_root_i!=root_q || epoch_i!=epoch_q || key_domain_i!=key_q)) local_fault_q<=1;
            if(done) begin digest_o<=digest;valid_q<=1;end
        end
    end
endmodule
`default_nettype wire
