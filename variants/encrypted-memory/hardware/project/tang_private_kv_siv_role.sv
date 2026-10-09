`define SYNTHESIS 1
`timescale 1ns/1ps
`default_nettype none

// PRIVATE fixed-format K/V role codec, not a user crypto/memory interface.
// RFC5297 sections2.3--2.7: https://www.rfc-editor.org/rfc/rfc5297.html
// Input/output: five 256-bit words, bytes least-significant first per word.
// Seal:130 meaningful plaintext bytes +30 zeros ->130 ciphertext bytes,
// 16-byte SIV,14 zeros. Open:inverse, with NO output until full SIV equality.
// Caller must retain current-epoch/prefix/plaintext-SHA freshness enforcement.
// Abort revokes this component's ownership; it does NOT drain external DDR.
// Keys are immutable elaboration values, public in all current fixtures.
module tang_private_kv_siv_role #(
    parameter bit KEY_IS_PROVISIONED=0,
    parameter [255:0] MAC_KEY=256'd0,
    parameter [255:0] CTR_KEY=256'd0
) (
    input wire clk,reset_n,abort_i,model_locked_i,upstream_fault_i,
    input wire request_valid_i,
    output wire request_ready_o,
    input wire open_i,
    input wire [63:0] epoch_i,
    input wire [2:0] layer_i,
    input wire [11:0] position_i,
    input wire [1:0] head_i,role_i,
    input wire input_valid_i,
    output wire input_ready_o,
    input wire [255:0] input_data_i,
    output wire output_valid_o,
    input wire output_ready_i,
    output logic [255:0] output_data_o,
    output wire busy_o,fault_o
);
    localparam [127:0] DOMAIN=128'h494f2d4b562d524f4c452d5349563100;
    localparam [255:0] MODEL_ID=256'hcad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0;
    localparam [4:0] PRE_L=0,WAIT_L=1,PRE_D=2,WAIT_D=3,PRE_DOMAIN=4,WAIT_DOMAIN=5,
        PRE_MODEL0=6,WAIT_MODEL0=7,PRE_MODEL1=8,WAIT_MODEL1=9,IDLE=10,LOAD=11,
        DESCRIPTOR=12,WAIT_DESCRIPTOR=13,CTR=14,WAIT_CTR=15,MAC=16,WAIT_MAC=17,
        HOLD=18,FAILED=19;
    logic [4:0] state_q;
    logic fault_q,lock_seen_q,prefix_ready_q,open_q;
    logic [127:0] subkey1_q,subkey2_q,prefix_q,descriptor_q,d_q,chain_q,tag_q;
    logic [127:0] data_q [0:8];
    logic [3:0] block_q;
    logic [2:0] word_q;
    logic [6:0] aes_wait_q;
    wire aes_ready,aes_busy,aes_done;
    wire [127:0] aes_result;
    logic aes_start,aes_slot;
    logic [127:0] aes_block;
    wire aes_wait_state=state_q==WAIT_L || state_q==WAIT_D || state_q==WAIT_DOMAIN ||
        state_q==WAIT_MODEL0 || state_q==WAIT_MODEL1 || state_q==WAIT_DESCRIPTOR ||
        state_q==WAIT_CTR || state_q==WAIT_MAC;
    assign fault_o=fault_q || !KEY_IS_PROVISIONED || upstream_fault_i ||
        (lock_seen_q && !model_locked_i);
    wire enabled=reset_n && !abort_i && !fault_o;
    wire protocol_error=(aes_done && !aes_wait_state) || (aes_wait_state && aes_wait_q==7'd63);
    // Suppress component transfers on the detection edge, before fault_q
    // latches. Do not feed this signal back to AES abort combinationally.
    wire io_enabled=enabled && !protocol_error;
    assign request_ready_o=io_enabled && prefix_ready_q && model_locked_i && state_q==IDLE;
    assign input_ready_o=io_enabled && state_q==LOAD;
    assign output_valid_o=io_enabled && state_q==HOLD;
    assign busy_o=reset_n && !fault_o && state_q!=IDLE;
    wire request_fire=request_valid_i && request_ready_o;
    wire input_fire=input_valid_i && input_ready_o;
    wire invalid_coordinates=layer_i>=6 || position_i>=2048 || head_i>=2 || role_i>=2;
    wire invalid_tail=open_q ? (|input_data_i[255:144]) : (|input_data_i[255:16]);

    function automatic [127:0] dbl(input [127:0] x);
        dbl={x[126:0],1'b0} ^ (x[127] ? 128'h87 : 128'd0);
    endfunction
    function automatic [127:0] reverse_bytes(input [127:0] x);
        for(integer b=0;b<16;b=b+1) reverse_bytes[b*8 +: 8]=x[127-b*8 -: 8];
    endfunction
    // Fixed130-byte xorend spans the last14 bytes of block7 and first2
    // bytes of block8. CMAC padding/subkey2 apply AFTER this xorend.
    logic [127:0] mac_piece;
    wire [127:0] tail_little=reverse_bytes(data_q[8]);
    always_comb begin
        mac_piece=data_q[block_q];
        if(block_q==7) mac_piece=data_q[7] ^ {16'd0,d_q[127:16]};
        if(block_q==8) mac_piece={data_q[8][127:112]^d_q[15:0],8'h80,104'd0} ^ subkey2_q;
        aes_start=0;aes_slot=0;aes_block=0;
        case(state_q)
            PRE_L: aes_block=0;
            PRE_D: aes_block=subkey1_q;
            PRE_DOMAIN: aes_block=DOMAIN ^ subkey1_q;
            PRE_MODEL0: aes_block=MODEL_ID[255:128];
            PRE_MODEL1: aes_block=chain_q ^ MODEL_ID[127:0] ^ subkey1_q;
            DESCRIPTOR: aes_block=descriptor_q ^ subkey1_q;
            MAC: aes_block=chain_q ^ mac_piece;
            CTR: begin
                aes_slot=1;
                // Only nine blocks; clearing bits31/63 prevents carries
                // through the mask positions during this bounded increment.
                aes_block=(tag_q & 128'hffffffffffffffff7fffffff7fffffff)+{124'd0,block_q};
            end
            default: ;
        endcase
        if(io_enabled && aes_ready && (state_q==PRE_L || state_q==PRE_D || state_q==PRE_DOMAIN ||
                state_q==PRE_MODEL0 || state_q==PRE_MODEL1 || state_q==DESCRIPTOR ||
                state_q==CTR || state_q==MAC)) aes_start=1;
        output_data_o=0;
        if(output_valid_o) begin
            if(word_q<4) output_data_o={reverse_bytes(data_q[2*int'(word_q)+1]),reverse_bytes(data_q[2*int'(word_q)])};
            else begin
                output_data_o[15:0]=tail_little[15:0];
                if(!open_q) output_data_o[143:16]=reverse_bytes(tag_q);
            end
        end
    end
    tang_private_aes256_fixed2 #(.KEY_IS_PROVISIONED(KEY_IS_PROVISIONED),.KEY0(MAC_KEY),.KEY1(CTR_KEY)) u_aes (
        .clk(clk),.reset_n(reset_n),.abort_i(abort_i || fault_o),.start_i(aes_start),
        .key_slot_i(aes_slot),.block_i(aes_block),.ready_o(aes_ready),.busy_o(aes_busy),
        .done_o(aes_done),.block_o(aes_result));

`ifndef SYNTHESIS
    wire x_error=$isunknown({abort_i,model_locked_i,upstream_fault_i,request_valid_i,input_valid_i,output_ready_i}) ||
        (request_fire && $isunknown({open_i,epoch_i,layer_i,position_i,head_i,role_i})) ||
        (input_fire && $isunknown(input_data_i)) ||
        (aes_done && aes_wait_state && $isunknown(aes_result));
`endif
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            state_q<=PRE_L;fault_q<=0;lock_seen_q<=0;prefix_ready_q<=0;open_q<=0;
            subkey1_q<=0;subkey2_q<=0;prefix_q<=0;descriptor_q<=0;d_q<=0;chain_q<=0;tag_q<=0;
            block_q<=0;word_q<=0;aes_wait_q<=0;
        end else if(fault_o || (enabled && protocol_error)
`ifndef SYNTHESIS
                || (enabled && x_error)
`endif
        ) begin
            fault_q<=1;state_q<=FAILED;word_q<=0;block_q<=0;
            descriptor_q<=0;d_q<=0;chain_q<=0;tag_q<=0;aes_wait_q<=0;
        end else if(abort_i) begin
            state_q<=prefix_ready_q ? IDLE : PRE_L;word_q<=0;block_q<=0;open_q<=0;
            descriptor_q<=0;d_q<=0;chain_q<=0;tag_q<=0;aes_wait_q<=0;
        end else begin
            if(model_locked_i) lock_seen_q<=1;
            if(aes_wait_state) aes_wait_q<=aes_wait_q+7'd1;else aes_wait_q<=0;
            case(state_q)
                PRE_L: if(aes_start) state_q<=WAIT_L;
                WAIT_L: if(aes_done) begin subkey1_q<=dbl(aes_result);subkey2_q<=dbl(dbl(aes_result));state_q<=PRE_D;end
                PRE_D: if(aes_start) state_q<=WAIT_D;
                WAIT_D: if(aes_done) begin prefix_q<=aes_result;state_q<=PRE_DOMAIN;end
                PRE_DOMAIN: if(aes_start) state_q<=WAIT_DOMAIN;
                WAIT_DOMAIN: if(aes_done) begin prefix_q<=dbl(prefix_q)^aes_result;state_q<=PRE_MODEL0;end
                PRE_MODEL0: if(aes_start) state_q<=WAIT_MODEL0;
                WAIT_MODEL0: if(aes_done) begin chain_q<=aes_result;state_q<=PRE_MODEL1;end
                PRE_MODEL1: if(aes_start) state_q<=WAIT_MODEL1;
                WAIT_MODEL1: if(aes_done) begin prefix_q<=dbl(prefix_q)^aes_result;prefix_ready_q<=1;state_q<=IDLE;end
                IDLE: if(request_fire) begin
                    if(invalid_coordinates) begin fault_q<=1;state_q<=FAILED;end
                    else begin
                        descriptor_q<={epoch_i,5'd0,layer_i,6'd0,head_i,6'd0,role_i,8'd0,4'd0,position_i,16'd130};
                        open_q<=open_i;word_q<=0;block_q<=0;chain_q<=0;d_q<=0;tag_q<=0;state_q<=LOAD;
                    end
                end
                LOAD: if(input_fire) begin
                    if(word_q<4) begin
                        data_q[2*int'(word_q)]<=reverse_bytes(input_data_i[127:0]);
                        data_q[2*int'(word_q)+1]<=reverse_bytes(input_data_i[255:128]);
                        word_q<=word_q+3'd1;
                    end else if(invalid_tail) begin fault_q<=1;state_q<=FAILED;end
                    else begin
                        data_q[8]<=reverse_bytes({112'd0,input_data_i[15:0]});
                        if(open_q) tag_q<=reverse_bytes(input_data_i[143:16]);
                        word_q<=0;block_q<=0;state_q<=DESCRIPTOR;
                    end
                end
                DESCRIPTOR: if(aes_start) state_q<=WAIT_DESCRIPTOR;
                WAIT_DESCRIPTOR: if(aes_done) begin
                    d_q<=dbl(prefix_q)^aes_result;chain_q<=0;block_q<=0;state_q<=open_q ? CTR : MAC;
                end
                CTR: if(aes_start) state_q<=WAIT_CTR;
                WAIT_CTR: if(aes_done) begin
                    if(block_q<8) data_q[block_q]<=data_q[block_q]^aes_result;
                    else data_q[8]<={data_q[8][127:112]^aes_result[127:112],112'd0};
                    if(block_q==8) begin block_q<=0;chain_q<=0;state_q<=open_q ? MAC : HOLD;end
                    else begin block_q<=block_q+4'd1;state_q<=CTR;end
                end
                MAC: if(aes_start) state_q<=WAIT_MAC;
                WAIT_MAC: if(aes_done) begin
                    chain_q<=aes_result;
                    if(block_q==8) begin
                        block_q<=0;
                        if(open_q) begin
                            // Case inequality also rejects unknown simulation
                            // values. It is ordinary full equality for binary
                            // hardware values, not a physical fault detector.
                            if(aes_result!==tag_q) begin fault_q<=1;state_q<=FAILED;end
                            else state_q<=HOLD;
                        end else begin tag_q<=aes_result;state_q<=CTR;end
                    end else begin block_q<=block_q+4'd1;state_q<=MAC;end
                end
                HOLD: if(output_ready_i) begin
                    if(word_q==4) begin state_q<=IDLE;word_q<=0;tag_q<=0;end
                    else word_q<=word_q+3'd1;
                end
                default: begin fault_q<=1;state_q<=FAILED;end
            endcase
        end
    end
endmodule
`default_nettype wire
