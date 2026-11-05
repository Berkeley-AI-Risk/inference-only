`timescale 1ns/1ps
module tb_home_tang;
    reg clk50=0;always #10 clk50=~clk50;
    reg button=1,rx=1;wire tx;
    tri [3:0] flash_dq;wire flash_cs,flash_sck;
    wire [14:0] da;wire [2:0] db;
    wire dc,dr,dcas,dw,dck,dckn,dcke,dodt,dreset;
    wire [3:0] dm;tri [31:0] dq;tri [3:0] dqs,dqsn;
    wire nv,nr,nonce_fault,model_ready,raw_enable;
    wire [255:0]nonce,nonce_hash_digest;
    wire nonce_hash_start,nonce_hash_byte_valid,nonce_hash_available,nonce_hash_done,nonce_hash_fault;
    wire [7:0]nonce_hash_byte;
    wire [31:0]nonce_hash_offset;
    reg [7:0]raw_byte=0;
    `include "home_fixtures.svh"
    board1_home_auth_core #(.SHARE_NONCE_HASH(1'b1),.SHARE_LMS_HASH(1'b1),.HOME_RESPONSE_CYCLES(8000000),.HOME_LEASE_CYCLES(20000000),
      .HOME_RENEW_CYCLES(12000000)) dut(
      .private_nonce_valid_i(nv),.private_nonce_fault_i(nonce_fault),.private_nonce_i(nonce),.private_nonce_request_o(nr),
      .private_model_ready_o(model_ready),
      .private_nonce_hash_start_i(nonce_hash_start),.private_nonce_hash_byte_valid_i(nonce_hash_byte_valid),
      .private_nonce_hash_byte_i(nonce_hash_byte),.private_nonce_hash_available_o(nonce_hash_available),
      .private_nonce_hash_done_o(nonce_hash_done),.private_nonce_hash_fault_o(nonce_hash_fault),
      .private_nonce_hash_offset_o(nonce_hash_offset),.private_nonce_hash_digest_o(nonce_hash_digest),
      .clk_50mhz(clk50),.reset_button(button),.uart_rx(rx),.uart_tx(tx),
      .flash_dq(flash_dq),.flash_csn(flash_cs),.flash_sclk(flash_sck),
      .ddr_addr(da),.ddr_bank(db),.ddr_cs(dc),.ddr_ras(dr),.ddr_cas(dcas),.ddr_we(dw),
      .ddr_ck(dck),.ddr_ck_n(dckn),.ddr_cke(dcke),.ddr_odt(dodt),.ddr_reset_n(dreset),
      .ddr_dm(dm),.ddr_dq(dq),.ddr_dqs(dqs),.ddr_dqs_n(dqsn));
    nonce_frontend #(.USE_SHARED_HASH(1'b1))front(
      .clk(dut.core_clk),.reset_n(dut.core_reset_n),.request_i(nr&&model_ready),
      .entropy_enable_o(raw_enable),.entropy_valid_i(raw_enable),.entropy_byte_i(raw_byte),
      .nonce_valid_o(nv),.nonce_o(nonce),.fault_o(nonce_fault),
      .shared_hash_start_o(nonce_hash_start),.shared_hash_byte_valid_o(nonce_hash_byte_valid),
      .shared_hash_byte_o(nonce_hash_byte),.shared_hash_available_i(nonce_hash_available),
      .shared_hash_done_i(nonce_hash_done),.shared_hash_fault_i(nonce_hash_fault),
      .shared_hash_offset_i(nonce_hash_offset),.shared_hash_digest_i(nonce_hash_digest));
    integer scenario,nonce_count=0,raw_index=0;
    always @(negedge dut.core_clk) begin
        if(!dut.core_reset_n)begin raw_index=0;nonce_count=0;raw_byte=0;end
        else begin
            if(!raw_enable)raw_index=0;
            else if(front.state_q==2)begin
                raw_byte=nonce_count==0?8'(13*raw_index+7):8'(29*raw_index+11);
                raw_index=raw_index+1;
            end
            if(nv&&nr)nonce_count=nonce_count+1;
        end
    end
    reg [7:0] replies[0:8191];integer reply_bytes=0,read_cursor=0;
    initial begin
        $display("START integrated home authorization simulation");$fflush();
        wait(dut.core_reset_n);repeat(5)@(negedge dut.core_clk);
        forever begin
            wait(tx==0);repeat(325)@(negedge dut.core_clk);
            for(integer b=0;b<8;b=b+1) begin
                replies[reply_bytes][b]=tx;repeat(217)@(negedge dut.core_clk);
            end
            if(tx!=1)$fatal(1,"UART stop bit");
            reply_bytes=reply_bytes+1;
        end
    end
    function automatic [7:0] crc(input [7:0] c,input [7:0] d);
        reg [7:0] v;begin v=c^d;for(integer i=0;i<8;i=i+1)v=v[7]?(v<<1)^8'h07:v<<1;crc=v;end
    endfunction
    task send_byte(input [7:0] v);
        begin
            rx=0;repeat(217)@(negedge dut.core_clk);
            for(integer i=0;i<8;i=i+1)begin rx=v[i];repeat(217)@(negedge dut.core_clk);end
            rx=1;repeat(217)@(negedge dut.core_clk);
        end
    endtask
    task send_command(input [7:0] op,input [11:0] tok);
        reg [7:0] c;
        begin
            c=crc(crc(crc(crc(0,8'ha5),op),tok[7:0]),{4'd0,tok[11:8]});
            send_byte(8'ha5);send_byte(op);send_byte(tok[7:0]);send_byte({4'd0,tok[11:8]});send_byte(c);
        end
    endtask
    string homefix,fixtures;
    reg [7:0] expected[0:127],grant[0:1419];
    integer home_count=0;
    task service_home;
        string name,path;
        begin
            wait(reply_bytes>=read_cursor+129);
            name=home_count==0 ? "a1":"a2";
            path=$sformatf("%s/request-%s.hex",homefix,name);$readmemh(path,expected);
            for(integer i=0;i<128;i=i+1)
                if(replies[read_cursor+1+i]!==expected[i])$fatal(1,"home request mismatch %0d",i);
            read_cursor=read_cursor+129;
            if(scenario==1 && home_count==0)name="wrong-model";
            path=$sformatf("%s/grant-%s.hex",homefix,name);$readmemh(path,grant);
            if(scenario==3 && home_count>0)grant[1419]=grant[1419]^8'h01;
            if(!(scenario==2 && home_count>0))begin
                for(integer i=0;i<1420;i=i+1)send_byte(grant[i]);
            end
            home_count=home_count+1;
            $display("PASS home UART turn=%0d scenario=%0d",home_count,scenario);$fflush();
        end
    endtask
    task expect_reply(input [7:0] status,input integer tok);
        integer ticks,actual;reg [7:0] c;bit done;
        begin
            ticks=0;done=0;
            while(!done && ticks<25000000)begin
                if(reply_bytes>read_cursor)begin
                    if(replies[read_cursor]==8'ha6)service_home();
                    else if(replies[read_cursor]==8'h5a)begin
                        wait(reply_bytes>=read_cursor+5);c=0;
                        for(integer i=0;i<4;i=i+1)c=crc(c,replies[read_cursor+i]);
                        actual={replies[read_cursor+3],replies[read_cursor+2]};
                        if(replies[read_cursor+1]!=status || actual!=tok || replies[read_cursor+4]!=c)
                            $fatal(1,"token/status mismatch got=%0d status=%x expected=%0d",actual,replies[read_cursor+1],tok);
                        read_cursor=read_cursor+5;done=1;
                    end else $fatal(1,"unknown UART response prefix %x",replies[read_cursor]);
                end
                @(negedge dut.core_clk);ticks=ticks+1;
                if(dut.home_failed || dut.memory_fault)$fatal(1,
                    "fault awaiting token: home=%b memory=%b remaining=%0d home_turns=%0d nonce_count=%0d",
                    dut.home_failed,dut.memory_fault,dut.home_remaining,home_count,nonce_count);
            end
            if(!done)$fatal(1,"missing token reply");
            $display("PASS token UART status=%x token=%0d",status,tok);$fflush();
        end
    endtask
    integer ticks,before_count;bit observed_bad_signature=0;
    initial begin
        if(!$value$plusargs("SCENARIO=%d",scenario))scenario=0;
        if(!$value$plusargs("HOMEFIX=%s",homefix))$fatal(1,"HOMEFIX missing");
        if(!$value$plusargs("FIXTURES=%s",fixtures))$fatal(1,"FIXTURES missing");
        repeat(10)@(negedge clk50);button=0;
        wait(dut.core_reset_n);ticks=0;
        $display("RESET RELEASED time=%0t",$time);$fflush();
        while(!dut.model_locked && !dut.memory_fault && ticks<800000000)begin
            @(negedge dut.core_clk);ticks=ticks+1;
            if(ticks%50000000==0)begin $display("BOOT cycles=%0d",ticks);$fflush();end
            if(dut.home_enabled)$fatal(1,"authorized before model boot");
        end
        if(!dut.model_locked)$fatal(1,"model boot failed");
        $display("MODEL LOCKED cycles=%0d",ticks);$fflush();
        if(dut.model_commitment!==MODEL_A)$fatal(1,"wrong authenticated model commitment");
        wait(reply_bytes>read_cursor);
        if(replies[read_cursor]!=8'ha6)$fatal(1,"missing initial home request");
        service_home();
        if(scenario==1)begin
            ticks=0;while(!dut.home_failed && ticks<1000000)begin @(negedge dut.core_clk);ticks=ticks+1;end
            if(!dut.home_failed || dut.home_enabled || dut.token_reset_n)$fatal(1,"wrong model enabled inference");
            $display("PASS integrated wrong-model authorization rejection");$finish;
        end
        wait(dut.home_enabled);repeat(10)@(negedge dut.core_clk);
        send_command(2,0);expect_reply(8'h82,0);
        send_command(0,1);expect_reply(8'h80,0);
        if(scenario==0)begin
            while(dut.home_remaining>13000000)@(negedge dut.core_clk);
            send_command(1,0);expect_reply(8'h81,108);
            send_command(1,0);expect_reply(8'h81,32);
            if(home_count<2)$fatal(1,"renewal was not exercised");
            $display("PASS integrated renewal preserves context and exact [108,32] tokens");$finish;
        end else if(scenario==3)begin
            wait(reply_bytes>read_cursor);
            if(replies[read_cursor]!=8'ha6)$fatal(1,"missing renewal request");
            service_home();
            ticks=0;
            while(!dut.home_failed && ticks<8000000)begin
                @(negedge dut.core_clk);ticks=ticks+1;
                if(dut.lease_crypto_done && !dut.lease_crypto_valid)observed_bad_signature=1;
            end
            if(!observed_bad_signature || !dut.home_failed || dut.home_enabled || dut.token_reset_n)
                $fatal(1,"shared verifier reused a prior verdict or failed to reject bad signature");
            before_count=reply_bytes;repeat(200000)@(negedge dut.core_clk);
            if(tx!==1'b1 || reply_bytes!=before_count || dut.request_valid)$fatal(1,"output after bad signature");
            $display("PASS integrated shared verifier rejects corrupt renewal after valid lease");$finish;
        end else begin
            // A long prefill is deliberately active when the lease expires.
            for(integer j=0;j<63;j=j+1)begin send_command(0,1);expect_reply(8'h80,0);end
            send_command(1,0);
            ticks=0;
            while(!dut.home_failed && ticks<25000000)begin
                if(reply_bytes>read_cursor)begin
                    if(replies[read_cursor]==8'ha6)service_home();
                    else $fatal(1,"unexpected token before expiry in long prefill");
                end
                @(negedge dut.core_clk);ticks=ticks+1;
            end
            if(!dut.home_failed || dut.home_enabled || dut.token_reset_n)$fatal(1,"expiry did not stop inference");
            before_count=reply_bytes;repeat(200000)@(negedge dut.core_clk);
            if(tx!==1'b1 || reply_bytes!=before_count || dut.request_valid)$fatal(1,"output/work after expiry");
            $display("PASS integrated lease loss cancels pending inference and suppresses output");$finish;
        end
    end
initial begin
        if(!dut.u_signed_boot.u_admission.SHARE_LMS_HASH ||
           !dut.u_signed_boot.u_admission.u_lms.USE_SHARED_HASH)
            $fatal(1,"full shared SHA mode not connected");
    end
endmodule
