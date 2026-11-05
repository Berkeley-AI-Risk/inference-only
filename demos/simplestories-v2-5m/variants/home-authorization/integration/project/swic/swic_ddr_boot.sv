`timescale 1ns/1ps
`default_nettype none
// Serial boot owner at the native Gowin application seam. Every image word is
// written, read back, and hashed. Norm extraction and fixed-function LUT
// authentication consume that exact readback, before one-way runtime handoff.
module swic_ddr_boot(
    input wire clk,reset_n,
    input wire admitted_i,source_fault_i,progress_i,loader_done_i,loader_valid_i,
    input wire [255:0] loader_data_i,expected_image_sha_i,
    output wire loader_ready_o,
    output wire boot_locked_o,fault_o,
    output wire metadata_read_o,
    output wire [11:0] metadata_address_o,
    input wire [191:0] metadata_data_i,
    input wire body_norm_read_i,head_norm_read_i,
    input wire [11:0] body_norm_address_i,head_norm_address_i,
    output wire [33:0] body_norm_data_o,head_norm_data_o,
    input wire controller_good_i,
    input wire app_cmd_ready_i,app_data_ready_i,
    output wire [2:0] app_cmd_o,
    output wire app_cmd_en_o,
    output wire [28:0] app_addr_o,
    output wire [255:0] app_data_o,
    output wire app_data_en_o,app_data_end_o,
    output wire [31:0] app_mask_o,
    input wire [255:0] app_read_data_i,
    input wire app_read_valid_i,app_read_end_i
);
    localparam [3:0] WAIT_ADMIT=0,WRITE=1,DRAIN=2,READ_START=3,
        READ_ISSUE=4,READ_WAIT=5,READ_BYTES=6,READ_FINISH=7,LOCKED=8,FAILED=15;
    localparam integer LUT_FIRST_WORD=214261,LUT_BYTES=409632;
    localparam [255:0] LUT_SHA=256'hfea751d73eb4fd28f160a4dcc4b8d1fa39c125cb05d10393ac45ad4e3e1bb76b;
    logic [3:0] state_q;
    logic [17:0] word_q;
    logic [4:0] byte_q;
    logic [255:0] readback_q;
    logic local_fault_q,lut_ok_q;
    logic [25:0] watchdog_q;
    wire adapter_ready,adapter_fault,adapter_error,adapter_calib;
    wire rsp_valid,rsp_error;
    wire [255:0] rsp_data;
    wire req_valid=(state_q==WRITE && loader_valid_i) || (state_q==READ_ISSUE && norm_ready);
    wire req_write=state_q==WRITE;
    wire req_fire=req_valid && adapter_ready;
    wire image_ready,image_verified,image_fault;
    wire lut_ready,lut_busy,lut_done,lut_fault;
    wire [31:0] lut_offset;
    wire [255:0] lut_digest;
    wire in_lut=word_q>=18'(LUT_FIRST_WORD);
    wire byte_valid=state_q==READ_BYTES;
    wire [7:0] readback_byte=readback_q[int'(byte_q)*8 +:8];
    wire byte_fire=byte_valid && image_ready && (!in_lut || lut_ready);
    wire last_byte=word_q==18'd227061 && byte_q==31;
    wire norm_ready,norm_loaded,norm_fault;
    wire norm_word=state_q==READ_WAIT && rsp_valid && !rsp_error;
    logic [255:0] expanded_metadata;
    always_comb begin
        for(integer m=0;m<8;m=m+1)
            expanded_metadata[m*32 +:32]={8'd0,metadata_data_i[m*24 +:24]};
    end
    assign metadata_read_o=state_q==READ_ISSUE && word_q>=211920 && word_q<214248;
    assign metadata_address_o=12'(word_q-211920);
    assign fault_o=local_fault_q || source_fault_i || adapter_fault || image_fault || lut_fault || norm_fault;
    assign loader_ready_o=state_q==WRITE && admitted_i && adapter_ready && !fault_o;
    assign boot_locked_o=state_q==LOCKED && admitted_i && image_verified && lut_ok_q && norm_loaded && !fault_o;
    board1_gowin_ddr3_app_adapter #(.ADDR_W(19),.MAX_OUTSTANDING_READS(1)) u_boot_adapter(
        .clk(clk),.reset_n(reset_n),.phy_req_valid_i(req_valid && !fault_o),.phy_req_ready_o(adapter_ready),
        .phy_req_write_i(req_write),.phy_req_word_addr_i({1'b0,word_q}),.phy_req_wdata_i(loader_data_i),
        .phy_rsp_valid_o(rsp_valid),.phy_rsp_data_o(rsp_data),.phy_rsp_error_o(rsp_error),
        .controller_pll_lock_i(controller_good_i),.controller_init_calib_complete_i(controller_good_i),
        .calib_done_o(adapter_calib),.calib_error_o(adapter_error),.protocol_fault_o(adapter_fault),
        .app_cmd_ready_i(app_cmd_ready_i),.app_cmd_o(app_cmd_o),.app_cmd_en_o(app_cmd_en_o),.app_addr_o(app_addr_o),
        .app_wr_data_ready_i(app_data_ready_i),.app_wr_data_o(app_data_o),.app_wr_data_en_o(app_data_en_o),
        .app_wr_data_end_o(app_data_end_o),.app_wr_data_mask_o(app_mask_o),
        .app_rd_data_i(app_read_data_i),.app_rd_data_valid_i(app_read_valid_i),.app_rd_data_end_i(app_read_end_i),
        .app_burst_o(),.app_self_refresh_req_o(),.app_refresh_req_o());
    su_image_check u_image(
        .clk(clk),.reset_n(reset_n),.start_i(state_q==READ_START),.expected_sha_i(expected_image_sha_i),
        .readback_valid_i(byte_valid && (!in_lut || lut_ready)),.readback_ready_o(image_ready),
        .readback_byte_i(readback_byte),.readback_last_i(last_byte),.verified_o(image_verified),.fault_o(image_fault));
    su_sha256 #(.MAX_BYTES(LUT_BYTES)) u_fixed_luts(
        .clk(clk),.reset_n(reset_n),.start_i(state_q==READ_ISSUE && word_q==18'(LUT_FIRST_WORD) && req_fire),
        .length_i(32'(LUT_BYTES)),.byte_valid_i(byte_valid && in_lut && image_ready),
        .byte_ready_o(lut_ready),.byte_i(readback_byte),.byte_offset_o(lut_offset),
        .busy_o(lut_busy),.done_o(lut_done),.fault_o(lut_fault),.digest_o(lut_digest));
    swic_norm_store u_norms(
        .clk(clk),.reset_n(reset_n),.word_valid_i(norm_word),.word_ready_o(norm_ready),
        .word_index_i(word_q),.word_data_i(rsp_data),.loaded_o(norm_loaded),.fault_o(norm_fault),
        .model_locked_i(boot_locked_o),.body_read_i(body_norm_read_i),.head_read_i(head_norm_read_i),
        .body_address_i(body_norm_address_i),.head_address_i(head_norm_address_i),
        .body_data_o(body_norm_data_o),.head_data_o(head_norm_data_o));
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin state_q<=WAIT_ADMIT;word_q<=0;byte_q<=0;readback_q<=0;local_fault_q<=0;lut_ok_q<=0;watchdog_q<=0;end
        else begin
            if(progress_i || req_fire || rsp_valid || byte_fire) watchdog_q<=0;
            else if(state_q!=LOCKED && state_q!=FAILED) watchdog_q<=watchdog_q+1;
            if(lut_done) begin
                if(lut_digest==LUT_SHA) lut_ok_q<=1;
                else local_fault_q<=1;
            end
            if(fault_o || (rsp_valid && (state_q!=READ_WAIT || rsp_error)) ||
               (watchdog_q==26'd49999999 && !(progress_i || req_fire || rsp_valid || byte_fire))) begin
                state_q<=FAILED;local_fault_q<=1;
            end else case(state_q)
                WAIT_ADMIT: if(admitted_i && adapter_calib) begin word_q<=0;state_q<=WRITE;end
                WRITE: if(req_fire) begin
                    if(word_q==18'd227061) state_q<=DRAIN;
                    else word_q<=word_q+1;
                end
                DRAIN: if(loader_done_i) begin word_q<=0;state_q<=READ_START;end
                READ_START: state_q<=READ_ISSUE;
                READ_ISSUE: if(req_fire) state_q<=READ_WAIT;
                READ_WAIT: if(rsp_valid) begin
                    if(word_q>=211920 && word_q<214248 && rsp_data!=expanded_metadata) begin
                        state_q<=FAILED;local_fault_q<=1;
                    end else begin readback_q<=rsp_data;byte_q<=0;state_q<=READ_BYTES;end
                end
                READ_BYTES: if(byte_fire) begin
                    if(byte_q==31) begin
                        if(word_q==18'd227061) state_q<=READ_FINISH;
                        else begin word_q<=word_q+1;state_q<=READ_ISSUE;end
                    end else byte_q<=byte_q+1;
                end
                READ_FINISH: if(image_verified && lut_ok_q && norm_loaded) state_q<=LOCKED;
                LOCKED: begin end
                FAILED: local_fault_q<=1;
                default: begin state_q<=FAILED;local_fault_q<=1;end
            endcase
        end
    end
endmodule
`default_nettype wire
