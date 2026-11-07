`timescale 1ns/1ps
`default_nettype none
module combined_boot_scan(
    input wire clk,reset_n,start_i,source_fault_i,
    input wire [255:0] expected_image_sha_i,
    input wire word_valid_i,
    output wire word_ready_o,
    input wire [255:0] word_data_i,
    output wire boot_locked_o,fault_o,
    output wire digest_read_o,
    output wire [13:0] digest_address_o,
    input wire [31:0] digest_data_i,
    output wire metadata_read_o,
    output wire [11:0] metadata_address_o,
    input wire [191:0] metadata_data_i,
    input wire body_norm_read_i,head_norm_read_i,
    input wire [11:0] body_norm_address_i,head_norm_address_i,
    output wire [33:0] body_norm_data_o,head_norm_data_o
);
    localparam [3:0] WAIT_ADMIT=0,READ_START=1,READ_ISSUE=2,READ_BYTES=3,READ_FINISH=4,LOCKED=8,FAILED=15;
    localparam integer LUT_FIRST_WORD=214261,LUT_BYTES=409632;
    localparam [255:0] LUT_SHA=256'hfea751d73eb4fd28f160a4dcc4b8d1fa39c125cb05d10393ac45ad4e3e1bb76b;
    logic [3:0] state_q;
    logic [17:0] word_q;
    logic [4:0] byte_q;
    logic [255:0] readback_q;
    logic local_fault_q,lut_ok_q;
    logic metadata_primed_q;
    wire image_ready,image_verified,image_fault;
    wire lut_ready,lut_busy,lut_done,lut_fault;
    wire [31:0] lut_offset;
    wire [255:0] lut_digest;
    wire in_lut=word_q>=18'(LUT_FIRST_WORD);
    wire byte_valid=state_q==READ_BYTES;
    wire [7:0] readback_byte=readback_q[int'(byte_q)*8 +:8];
    wire page_ready,page_verified,page_fault;
    wire byte_fire=byte_valid && image_ready && page_ready && (!in_lut || lut_ready);
    wire last_byte=word_q==18'd227061 && byte_q==31;
    wire norm_ready,norm_loaded,norm_fault;
    wire req_fire=word_valid_i && word_ready_o;
    wire norm_word=req_fire;
    wire [255:0] rsp_data=word_data_i;
    logic [255:0] expanded_metadata;
    always_comb begin
        for(integer m=0;m<8;m=m+1) expanded_metadata[m*32+:32]={8'd0,metadata_data_i[m*24+:24]};
    end
    assign metadata_read_o=state_q==READ_ISSUE && word_q>=211920 && word_q<214248;
    assign metadata_address_o=12'(word_q-211920);
    assign fault_o=local_fault_q || source_fault_i || image_fault || lut_fault || norm_fault || compressor_mux_fault || page_fault;
    assign word_ready_o=state_q==READ_ISSUE && norm_ready && !fault_o &&
        (!(word_q>=211920 && word_q<214248) || metadata_primed_q);
    assign boot_locked_o=state_q==LOCKED && image_verified && page_verified && lut_ok_q && norm_loaded && !fault_o;
    wire image_compress_request,lut_compress_request,page_compress_request;
    wire image_compress_accept,lut_compress_accept,page_compress_accept;
    wire image_compress_done,lut_compress_done,page_compress_done;
    wire [511:0] image_compress_block,lut_compress_block,page_compress_block;
    wire [255:0] image_compress_state,lut_compress_state,page_compress_state,compress_digest;
    wire compressor_mux_fault;
    swic_boot_compressor_mux3 u_boot_compressor(
        .clk(clk),.reset_n(reset_n),
        .request0_i(image_compress_request),.request1_i(lut_compress_request),.request2_i(page_compress_request),
        .block0_i(image_compress_block),.block1_i(lut_compress_block),.block2_i(page_compress_block),
        .state0_i(image_compress_state),.state1_i(lut_compress_state),.state2_i(page_compress_state),
        .accept0_o(image_compress_accept),.accept1_o(lut_compress_accept),.accept2_o(page_compress_accept),
        .done0_o(image_compress_done),.done1_o(lut_compress_done),.done2_o(page_compress_done),
        .digest_o(compress_digest),.fault_o(compressor_mux_fault));
    su_image_check #(.USE_SHARED_COMPRESSOR(1'b1)) u_image(
        .clk(clk),.reset_n(reset_n),.start_i(state_q==READ_START),.expected_sha_i(expected_image_sha_i),
        .readback_valid_i(byte_valid && page_ready && (!in_lut || lut_ready)),.readback_ready_o(image_ready),
        .readback_byte_i(readback_byte),.readback_last_i(last_byte),.verified_o(image_verified),.fault_o(image_fault),
        .shared_request_o(image_compress_request),.shared_block_o(image_compress_block),.shared_state_o(image_compress_state),
        .shared_accept_i(image_compress_accept),.shared_done_i(image_compress_done),.shared_digest_i(compress_digest));
    su_sha256 #(.MAX_BYTES(LUT_BYTES),.USE_SHARED_COMPRESSOR(1'b1)) u_fixed_luts(
        .clk(clk),.reset_n(reset_n),.start_i(state_q==READ_ISSUE && word_q==18'(LUT_FIRST_WORD) && req_fire),
        .length_i(32'(LUT_BYTES)),.byte_valid_i(byte_valid && in_lut && image_ready && page_ready),
        .byte_ready_o(lut_ready),.byte_i(readback_byte),.byte_offset_o(lut_offset),
        .busy_o(lut_busy),.done_o(lut_done),.fault_o(lut_fault),.digest_o(lut_digest),
        .shared_request_o(lut_compress_request),.shared_block_o(lut_compress_block),.shared_state_o(lut_compress_state),
        .shared_accept_i(lut_compress_accept),.shared_done_i(lut_compress_done),.shared_digest_i(compress_digest));
    su_page_table_check #(.USE_SHARED_COMPRESSOR(1'b1)) u_pages(
        .clk(clk),.reset_n(reset_n),.start_i(state_q==READ_START),
        .readback_valid_i(byte_valid && image_ready && (!in_lut || lut_ready)),
        .readback_ready_o(page_ready),.readback_byte_i(readback_byte),.readback_last_i(last_byte),
        .digest_read_o(digest_read_o),.digest_address_o(digest_address_o),.digest_data_i(digest_data_i),
        .verified_o(page_verified),.fault_o(page_fault),
        .shared_request_o(page_compress_request),.shared_block_o(page_compress_block),.shared_state_o(page_compress_state),
        .shared_accept_i(page_compress_accept),.shared_done_i(page_compress_done),.shared_digest_i(compress_digest));
    swic_norm_store u_norms(
        .clk(clk),.reset_n(reset_n),.word_valid_i(norm_word),.word_ready_o(norm_ready),
        .word_index_i(word_q),.word_data_i(rsp_data),.loaded_o(norm_loaded),.fault_o(norm_fault),
        .model_locked_i(boot_locked_o),.body_read_i(body_norm_read_i),.head_read_i(head_norm_read_i),
        .body_address_i(body_norm_address_i),.head_address_i(head_norm_address_i),
        .body_data_o(body_norm_data_o),.head_data_o(head_norm_data_o));
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) metadata_primed_q<=0;
        else metadata_primed_q<=state_q==READ_ISSUE;
    end
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin state_q<=WAIT_ADMIT;word_q<=0;byte_q<=0;readback_q<=0;local_fault_q<=0;lut_ok_q<=0;end
        else begin
            if(lut_done) begin
                if(lut_digest==LUT_SHA) lut_ok_q<=1;
                else local_fault_q<=1;
            end
            if(fault_o || (start_i && state_q!=WAIT_ADMIT)) begin state_q<=FAILED;local_fault_q<=1;end
            else case(state_q)
                WAIT_ADMIT: if(start_i) state_q<=READ_START;
                READ_START: state_q<=READ_ISSUE;
                READ_ISSUE: if(req_fire) begin
                    if(word_q>=211920 && word_q<214248 && word_data_i!=expanded_metadata) begin
                        state_q<=FAILED;local_fault_q<=1;
                    end else begin readback_q<=word_data_i;byte_q<=0;state_q<=READ_BYTES;end
                end
                READ_BYTES: if(byte_fire) begin
                    if(byte_q==31) begin
                        if(word_q==18'd227061) state_q<=READ_FINISH;
                        else begin word_q<=word_q+1;state_q<=READ_ISSUE;end
                    end else byte_q<=byte_q+1;
                end
                READ_FINISH: if(image_verified && page_verified && lut_ok_q && norm_loaded) state_q<=LOCKED;
                LOCKED: begin end
                FAILED: local_fault_q<=1;
                default: begin state_q<=FAILED;local_fault_q<=1;end
            endcase
        end
    end
endmodule
`default_nettype wire
