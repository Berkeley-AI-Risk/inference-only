`timescale 1ns/1ps
`default_nettype none
// RFC 8554 LMS_SHA256_M32_H5 / LMOTS_SHA256_N32_W8 verifier.
// Signature bytes use a PRIVATE ready/data seam for synchronous sealed RAM.
// Message bytes are a private asynchronous small-manifest seam.
// The public key inputs must come from the parent's fixed authority ROM.
// This module contains real SHA computation; there is no external "valid" bit.
module su_lms_verify #(
    parameter integer MAX_MESSAGE_BYTES=256,
    parameter bit USE_SHARED_HASH=1'b0
) (
    input wire clk, reset_n, start_i,
    input wire [127:0] public_i_i,
    input wire [255:0] public_root_i,
    input wire [8:0] message_length_i,
    output logic [10:0] signature_address_o,
    input wire [7:0] signature_byte_i,
    input wire signature_ready_i,
    output logic [7:0] message_address_o,
    input wire [7:0] message_byte_i,
    output wire busy_o,
    output logic done_o, valid_o, fault_o,
    output wire shared_hash_start_o,shared_hash_byte_valid_o,
    output wire [31:0] shared_hash_length_o,
    output wire [7:0] shared_hash_byte_o,
    input wire shared_hash_ready_i,shared_hash_busy_i,shared_hash_done_i,shared_hash_fault_i,
    input wire [31:0] shared_hash_offset_i,
    input wire [255:0] shared_hash_digest_i
);
    localparam [4:0] IDLE=0,HEADER=1,CHECK=2,HSTART=3,HWAIT=4,
        COEFFICIENT=5,YLOAD=6,CHAIN=7,SAVE_Z=8,LEAF=9,
        PATH_LOAD=10,PARENT=11,FINISH=12,FAILED=31;
    localparam [2:0] HASH_Q=0,HASH_CHAIN=1,HASH_KEY=2,HASH_LEAF=3,HASH_PARENT=4;
    logic [4:0] state_q,after_hash_q;
    logic [2:0] mode_q;
    logic [127:0] identifier_q;
    logic [255:0] root_q,qhash_q,tmp_q,ots_q,sibling_q;
    (* ram_style="block" *) logic [255:0] z_q [0:33];
    logic [255:0] z_word_q;
    logic [5:0] z_word_index_q;
    logic z_word_valid_q;
    logic [31:0] leaf_q,ots_type_q,lms_type_q,node_q;
    logic [3:0] header_q;
    logic [5:0] element_q,byte_q;
    logic [7:0] iteration_q,coefficient_q;
    logic [15:0] checksum_q;
    logic [2:0] level_q;
    logic [8:0] message_length_q;
    logic [31:0] hash_length;
    wire [31:0] hash_offset;
    logic [7:0] hash_byte;
    wire hash_ready,hash_busy,hash_done,hash_fault;
    wire [255:0] hash_digest;
    wire key_payload=mode_q==HASH_KEY && hash_offset>=22 && hash_offset<1110;
    wire [5:0] key_word_index=6'((hash_offset-22)>>5);
    wire key_ready=!key_payload || (z_word_valid_q && z_word_index_q==key_word_index);
    wire signature_payload=mode_q==HASH_Q && hash_offset>=22 && hash_offset<54;
    wire hash_byte_valid=state_q==HWAIT && key_ready && (!signature_payload || signature_ready_i);
    integer a,k;
    logic [31:0] header_node;
    logic [255:0] left_value,right_value;
    function automatic [7:0] b256(input [255:0] x,input integer n);
        b256=x[255-n*8 -:8];
    endfunction
    function automatic [7:0] b32(input [31:0] x,input integer n);
        b32=x[31-n*8 -:8];
    endfunction
    always_comb begin
        signature_address_o=0;message_address_o=0;
        hash_byte=0;hash_length=0;
        a=int'(hash_offset);k=0;
        header_node=(mode_q==HASH_LEAF) ? node_q :
                    ((mode_q==HASH_PARENT) ? (node_q>>1) : leaf_q);
        left_value=node_q[0] ? sibling_q : tmp_q;
        right_value=node_q[0] ? tmp_q : sibling_q;
        case(mode_q)
            HASH_Q: hash_length=32'd54+32'(message_length_q);
            HASH_CHAIN: hash_length=55;
            HASH_KEY: hash_length=1110;
            HASH_LEAF: hash_length=54;
            HASH_PARENT: hash_length=86;
            default: hash_length=0;
        endcase
        if(a<16) hash_byte=identifier_q[127-a*8 -:8];
        else if(a<20) hash_byte=b32(header_node,a-16);
        else case(mode_q)
            HASH_Q: begin
                if(a<22) hash_byte=8'h81;
                else if(a<54) begin signature_address_o=11'(8+a-22);hash_byte=signature_byte_i;end
                else begin message_address_o=8'(a-54);hash_byte=message_byte_i;end
            end
            HASH_CHAIN: begin
                if(a==20) hash_byte=0;
                else if(a==21) hash_byte={2'd0,element_q};
                else if(a==22) hash_byte=iteration_q;
                else hash_byte=b256(tmp_q,a-23);
            end
            HASH_KEY: begin
                if(a<22) hash_byte=8'h80;
                else begin
                    k=(a-22)/32;
                    if(k<34) hash_byte=b256(z_word_q,(a-22)%32);
                end
            end
            HASH_LEAF: begin
                if(a<22) hash_byte=8'h82;
                else hash_byte=b256(ots_q,a-22);
            end
            HASH_PARENT: begin
                if(a<22) hash_byte=8'h83;
                else if(a<54) hash_byte=b256(left_value,a-22);
                else hash_byte=b256(right_value,a-54);
            end
            default: hash_byte=0;
        endcase
        if(state_q==HEADER) signature_address_o=header_q<8 ? 11'(header_q) : 11'(1120+int'(header_q));
        if(state_q==YLOAD) signature_address_o=11'(40+int'(element_q)*32+int'(byte_q));
        if(state_q==PATH_LOAD) signature_address_o=11'(1132+int'(level_q)*32+int'(byte_q));
    end
    // One synchronous wide read/write RAM. Every row is freshly written by
    // SAVE_Z before HASH_KEY; byte consumption waits for the matching row.
    always_ff @(posedge clk) begin
        if(state_q==SAVE_Z) z_q[element_q]<=tmp_q;
        if(key_payload) z_word_q<=z_q[key_word_index];
    end
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin z_word_valid_q<=0;z_word_index_q<=0;end
        else begin
            z_word_valid_q<=key_payload;
            if(key_payload) z_word_index_q<=key_word_index;
        end
    end
    // Private byte-level service; no host-supplied digest or validity result.
    assign shared_hash_start_o=reset_n && state_q==HSTART;
    assign shared_hash_byte_valid_o=hash_byte_valid;
    assign shared_hash_length_o=hash_length;
    assign shared_hash_byte_o=hash_byte;
    generate if(USE_SHARED_HASH)begin:g_shared_hash
        assign hash_ready=shared_hash_ready_i;
        assign hash_busy=shared_hash_busy_i;
        assign hash_done=shared_hash_done_i;
        assign hash_fault=shared_hash_fault_i;
        assign hash_offset=shared_hash_offset_i;
        assign hash_digest=shared_hash_digest_i;
    end else begin:g_local_hash
    su_sha256 #(.MAX_BYTES(1110)) u_hash(
        .clk(clk),.reset_n(reset_n),.start_i(state_q==HSTART),
        .length_i(hash_length),.byte_valid_i(hash_byte_valid),
        .byte_ready_o(hash_ready),.byte_i(hash_byte),.byte_offset_o(hash_offset),
        .busy_o(hash_busy),.done_o(hash_done),.fault_o(hash_fault),.digest_o(hash_digest));
    end endgenerate
    assign busy_o=state_q!=IDLE && state_q!=FINISH && state_q!=FAILED;
    initial if(MAX_MESSAGE_BYTES<1 || MAX_MESSAGE_BYTES>256) $fatal(1,"unsupported maximum message length");
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            state_q<=IDLE;after_hash_q<=IDLE;mode_q<=HASH_Q;
            identifier_q<=0;root_q<=0;qhash_q<=0;tmp_q<=0;ots_q<=0;sibling_q<=0;
            leaf_q<=0;ots_type_q<=0;lms_type_q<=0;node_q<=0;header_q<=0;
            element_q<=0;byte_q<=0;iteration_q<=0;coefficient_q<=0;
            checksum_q<=0;level_q<=0;message_length_q<=0;done_o<=0;valid_o<=0;fault_o<=0;
        end else if(hash_fault || (start_i && state_q!=IDLE)) begin
            state_q<=FAILED;done_o<=1;valid_o<=0;fault_o<=1;
        end else case(state_q)
            IDLE: if(start_i) begin
                identifier_q<=public_i_i;root_q<=public_root_i;header_q<=0;
                message_length_q<=message_length_i;
                leaf_q<=0;ots_type_q<=0;lms_type_q<=0;
                if(message_length_i==0 || 32'(message_length_i)>MAX_MESSAGE_BYTES) begin
                    state_q<=FAILED;fault_o<=1;done_o<=1;
                end else state_q<=HEADER;
            end
            HEADER: if(signature_ready_i) begin
                if(header_q<4) leaf_q<={leaf_q[23:0],signature_byte_i};
                else if(header_q<8) ots_type_q<={ots_type_q[23:0],signature_byte_i};
                else lms_type_q<={lms_type_q[23:0],signature_byte_i};
                if(header_q==11) state_q<=CHECK;
                else header_q<=header_q+1;
            end
            CHECK: begin
                if(leaf_q>=32 || ots_type_q!=4 || lms_type_q!=5) begin
                    state_q<=FAILED;done_o<=1;fault_o<=1;
                end else begin mode_q<=HASH_Q;after_hash_q<=COEFFICIENT;state_q<=HSTART;end
            end
            HSTART: state_q<=HWAIT;
            HWAIT: if(hash_done) begin
                case(mode_q)
                    HASH_Q: begin
                        qhash_q<=hash_digest;checksum_q<=0;element_q<=0;
                    end
                    HASH_KEY: ots_q<=hash_digest;
                    HASH_CHAIN: begin tmp_q<=hash_digest;iteration_q<=iteration_q+1;end
                    default: tmp_q<=hash_digest;
                endcase
                state_q<=after_hash_q;
            end
            COEFFICIENT: begin
                if(element_q<32) begin
                    checksum_q<=checksum_q+16'(255-int'(b256(qhash_q,int'(element_q))));
                    element_q<=element_q+1;
                end else begin element_q<=0;byte_q<=0;state_q<=YLOAD;end
            end
            YLOAD: if(signature_ready_i) begin
                tmp_q<={tmp_q[247:0],signature_byte_i};
                if(byte_q==31) begin
                    iteration_q<=element_q<32 ? b256(qhash_q,int'(element_q)) :
                        (element_q==32 ? checksum_q[15:8] : checksum_q[7:0]);
                    state_q<=CHAIN;
                end else byte_q<=byte_q+1;
            end
            CHAIN: begin
                if(iteration_q==255) state_q<=SAVE_Z;
                else begin
                    mode_q<=HASH_CHAIN;after_hash_q<=CHAIN;
                    state_q<=HSTART;
                    // Iteration changes only AFTER the corresponding hash.
                end
            end
            SAVE_Z: begin
                if(element_q==33) begin mode_q<=HASH_KEY;after_hash_q<=LEAF;state_q<=HSTART;end
                else begin element_q<=element_q+1;byte_q<=0;state_q<=YLOAD;end
            end
            LEAF: begin
                node_q<=32+leaf_q;mode_q<=HASH_LEAF;after_hash_q<=PATH_LOAD;
                level_q<=0;byte_q<=0;state_q<=HSTART;
            end
            PATH_LOAD: if(signature_ready_i) begin
                sibling_q<={sibling_q[247:0],signature_byte_i};
                if(byte_q==31) begin
                    mode_q<=HASH_PARENT;after_hash_q<=PARENT;state_q<=HSTART;
                end else byte_q<=byte_q+1;
            end
            PARENT: begin
                node_q<=node_q>>1;
                if(level_q==4) begin
                    done_o<=1;valid_o<=tmp_q==root_q;state_q<=FINISH;
                end else begin level_q<=level_q+1;byte_q<=0;state_q<=PATH_LOAD;end
            end
            FINISH: begin end
            FAILED: begin valid_o<=0;fault_o<=1;done_o<=1;end
            default: begin state_q<=FAILED;valid_o<=0;fault_o<=1;done_o<=1;end
        endcase
    end
endmodule
`default_nettype wire
