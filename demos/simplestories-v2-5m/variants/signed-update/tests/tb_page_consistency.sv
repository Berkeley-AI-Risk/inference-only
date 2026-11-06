`timescale 1ns/1ps
module tb_page_consistency #(
    parameter integer IMAGE_BYTES=8203,
    parameter integer PAGE_BYTES=4096,
    parameter integer SUFFIX_AT=4064
);
    localparam integer PAGES=(IMAGE_BYTES+PAGE_BYTES-1)/PAGE_BYTES;
    reg clk=0;always #5 clk=~clk;
    reg reset_n=0,start=0,active=0,suffix_started=0;
    integer index=0,cycles=0,digest_reads=0,accepts0=0,accepts1=0,accepts2=0;
    reg [7:0] bytes[0:IMAGE_BYTES-1];
    reg [31:0] digests[0:PAGES*8-1];
    reg [255:0] expected[0:1];
    reg [31:0] digest_data=0;
    reg image_ok=0,suffix_ok=0;
    wire pr,ir,lr,pv,pf,ifault,lf,ib,idone,lb,ldone,dr;
    wire [13:0] da;
    wire [255:0] ih,lh,compressed;
    wire [31:0] io,lo;
    wire [2:0] request,accept,done;
    wire [511:0] blocks[0:2];
    wire [255:0] chains[0:2];
    wire mux_fault;
    wire in_suffix=index>=SUFFIX_AT;
    wire send=active && index<IMAGE_BYTES && cycles%23!=0 && cycles%29!=0;
    wire [7:0] data=index<IMAGE_BYTES ? bytes[index] : 8'd0;
    wire last=index==IMAGE_BYTES-1;
    wire fire=send && pr && ir && (!in_suffix || lr);
    wire suffix_start=active && index==SUFFIX_AT && !suffix_started;
    su_page_table_check #(.USE_SHARED_COMPRESSOR(1'b1),.IMAGE_BYTES(IMAGE_BYTES),.PAGE_BYTES(PAGE_BYTES)) u_pages(
        .clk(clk),.reset_n(reset_n),.start_i(start),
        .readback_valid_i(send && ir && (!in_suffix || lr)),.readback_last_i(last),.readback_byte_i(data),
        .readback_ready_o(pr),.digest_read_o(dr),.digest_address_o(da),.digest_data_i(digest_data),
        .verified_o(pv),.fault_o(pf),.shared_request_o(request[0]),.shared_block_o(blocks[0]),.shared_state_o(chains[0]),
        .shared_accept_i(accept[0]),.shared_done_i(done[0]),.shared_digest_i(compressed));
    su_sha256 #(.USE_SHARED_COMPRESSOR(1'b1),.MAX_BYTES(IMAGE_BYTES)) u_image(
        .clk(clk),.reset_n(reset_n),.start_i(start),.length_i(32'(IMAGE_BYTES)),
        .byte_valid_i(send && pr && (!in_suffix || lr)),.byte_ready_o(ir),.byte_i(data),.byte_offset_o(io),
        .busy_o(ib),.done_o(idone),.fault_o(ifault),.digest_o(ih),
        .shared_request_o(request[1]),.shared_block_o(blocks[1]),.shared_state_o(chains[1]),
        .shared_accept_i(accept[1]),.shared_done_i(done[1]),.shared_digest_i(compressed));
    su_sha256 #(.USE_SHARED_COMPRESSOR(1'b1),.MAX_BYTES(IMAGE_BYTES)) u_suffix(
        .clk(clk),.reset_n(reset_n),.start_i(suffix_start),.length_i(32'(IMAGE_BYTES-SUFFIX_AT)),
        .byte_valid_i(send && in_suffix && pr && ir),.byte_ready_o(lr),.byte_i(data),.byte_offset_o(lo),
        .busy_o(lb),.done_o(ldone),.fault_o(lf),.digest_o(lh),
        .shared_request_o(request[2]),.shared_block_o(blocks[2]),.shared_state_o(chains[2]),
        .shared_accept_i(accept[2]),.shared_done_i(done[2]),.shared_digest_i(compressed));
    swic_boot_compressor_mux3 u_mux(
        .clk(clk),.reset_n(reset_n),.request0_i(request[0]),.request1_i(request[1]),.request2_i(request[2]),
        .block0_i(blocks[0]),.block1_i(blocks[1]),.block2_i(blocks[2]),
        .state0_i(chains[0]),.state1_i(chains[1]),.state2_i(chains[2]),
        .accept0_o(accept[0]),.accept1_o(accept[1]),.accept2_o(accept[2]),
        .done0_o(done[0]),.done1_o(done[1]),.done2_o(done[2]),.digest_o(compressed),.fault_o(mux_fault));
    always @(posedge clk) begin
        if(dr) begin
            if(32'(da)>=PAGES*8) $fatal(1,"digest address out of range");
            digest_data<=digests[int'(da)];
        end
        if(!reset_n) begin
            digest_reads<=0;image_ok<=0;suffix_ok<=0;
            accepts0<=0;accepts1<=0;accepts2<=0;
        end else begin
            if(pf || ifault || lf || mux_fault) $fatal(1,"ordinary fixture raised fault index=%0d page=%0d state=%0d",index,u_pages.page_q,u_pages.state_q);
            if(dr) begin
                if(32'(da)!=digest_reads) $fatal(1,"page digest order mismatch");
                digest_reads<=digest_reads+1;
            end
            if(accept[0]) accepts0<=accepts0+1;
            if(accept[1]) accepts1<=accepts1+1;
            if(accept[2]) accepts2<=accepts2+1;
            if(idone) begin
                if(ih!==expected[0]) $fatal(1,"whole stream SHA mismatch");
                image_ok<=1;
            end
            if(ldone) begin
                if(lh!==expected[1]) $fatal(1,"suffix stream SHA mismatch");
                suffix_ok<=1;
            end
            if(pv && index!=IMAGE_BYTES) $fatal(1,"page verification before complete input");
        end
    end
    task initialize;
        begin
            reset_n=0;start=0;active=0;suffix_started=0;index=0;cycles=0;
            repeat(4) @(negedge clk);
            if(pv || pr || dr || |accept || |done) $fatal(1,"reset did not close outputs");
            reset_n=1;start=1;
            @(negedge clk);start=0;active=1;
        end
    endtask
    task advance;
        reg taken,starting_suffix;
        begin
            @(posedge clk);taken=fire;starting_suffix=suffix_start;
            @(negedge clk);
            if(taken) index=index+1;
            if(starting_suffix) suffix_started=1;
            cycles=cycles+1;
        end
    endtask
    initial begin
        string fixtures;
        if(!$value$plusargs("FIXTURES=%s",fixtures)) $fatal(1,"missing fixtures");
        $readmemh({fixtures,"/image.hex"},bytes);
        $readmemh({fixtures,"/digests.hex"},digests);
        $readmemh({fixtures,"/expected.hex"},expected);
        initialize();
        while(index<31 && cycles<10000) advance();
        if(index!=31) $fatal(1,"reset rehearsal did not make progress");
        initialize();
        while((index<IMAGE_BYTES || !pv || !image_ok || !suffix_ok) && cycles<IMAGE_BYTES*8+100000) advance();
        active=0;
        if(index!=IMAGE_BYTES || !pv || !image_ok || !suffix_ok) $fatal(1,"ordinary fixture did not complete index=%0d cycles=%0d",index,cycles);
        if(digest_reads!=PAGES*8 || accepts0!=PAGES*((PAGE_BYTES+72)/64) || accepts1==0 || accepts2==0)
            $fatal(1,"coverage/count mismatch");
        repeat(20) @(negedge clk);
        if(!pv) $fatal(1,"verification was not retained");
        $display("PASS page consistency bytes=%0d pages=%0d tail=%0d cycles=%0d digest_reads=%0d compressor_blocks=%0d,%0d,%0d",
                 IMAGE_BYTES,PAGES,IMAGE_BYTES-(PAGES-1)*PAGE_BYTES,cycles,digest_reads,accepts0,accepts1,accepts2);
        reset_n=0;@(negedge clk);
        if(pv || pr || dr) $fatal(1,"reset retained completed verification");
        $display("PASS reset clears completed verification");
        $finish;
    end
endmodule
