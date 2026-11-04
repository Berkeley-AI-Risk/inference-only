`timescale 1ns/1ps
module native_shared_runtime_tb;
 reg coreclk=0,appclk=0,resetn=0;
 always #7 coreclk=~coreclk;always #5 appclk=~appclk;
 reg model_valid=0,kv_valid=0,kv_write=0,vendor_stall=0,observe_clear=0;
 reg[18:0]model_word=0,kv_word=227072;reg[255:0]kv_data=0;
 reg boot_offer=0,boot_locked=0;reg[18:0]boot_word=0;
 wire model_ready,model_rsp,model_error,kv_ready,kv_rsp,kv_error;
 wire[255:0]model_data,kv_rsp_data;
 wire good,memoryfault,transportfault,sharedfault;
 wire[2:0]pcmd;wire pen,pwen,pwend;wire[28:0]paddr;wire[255:0]pwdata;wire[31:0]pmask;
 wire burst,selfrefresh,refresh;
 integer atick=0,ctick=0,tracefile,normalized_writes=0,normalized_reads=0,write_acks=0;
 integer physical_writes=0,physical_reads=0,physical_returns=0,model_admissions=0,kv_admissions=0;
 integer model_returns=0,kv_returns=0,boot_returns=0,raw_stall_cycles=0,simultaneous_admits=0,write_acks_before_issue=0;
 reg[255:0]memory[0:5],responses[0:31];
 reg[4:0]readhead=0,readtail=0;reg[5:0]pending=0;
 wire cmdready=resetn && !vendor_stall && atick%5!=2;
 wire dataready=resetn && atick%7!=3;
 wire rvalid=resetn && pending!=0 && atick%3!=1;
 wire[255:0]rdata=responses[readhead];
 wire kv_return_ready=ctick%7!=3 && ctick%7!=4;
 wire readtake=pen && pcmd==1;
 wire boot_ready=dut.u_memory.boot_cmd_ready;
 board1_runtime_transport_join dut(
  .core_clk(coreclk),.app_clk(appclk),.trusted_clk(coreclk),.board_reset_n(resetn),.trusted_reset_n(resetn),.app_reset_n(resetn),.pll_lock(resetn),.calibrated(resetn),
  .source_ready(1'b0),.boot_progress(1'b0),.loader_done(1'b0),.loader_valid(1'b0),.source_fault(1'b0),.loader_data(256'd0),.core_fault(1'b0),
  .model_app_req_valid(model_valid),.model_cdc_app_fault(1'b0),.model_app_req_word(model_word),.model_app_req_ready(model_ready),.model_app_rsp_valid(model_rsp),.model_app_rsp_error(model_error),.model_app_rsp_data(model_data),
  .private_kv_req_valid_o(kv_valid),.private_kv_req_write_o(kv_write),.private_kv_rsp_ready_o(kv_return_ready),.private_kv_req_word_address_o(kv_word),.private_kv_req_write_data_o(kv_data),
  .private_kv_req_ready_i(kv_ready),.private_kv_rsp_valid_i(kv_rsp),.private_kv_rsp_error_i(kv_error),.private_kv_rsp_data_i(kv_rsp_data),.shared_app_fault(sharedfault),.f_observe_clear_i(observe_clear),
  .app_cmd_ready(cmdready),.app_wr_ready(dataready),.app_rd_valid(rvalid),.app_rd_end(rvalid),.app_rd_data(rdata),.model_locked(good),.memory_fault(memoryfault),.transport_fault(transportfault),
  .app_cmd(pcmd),.app_cmd_en(pen),.app_wr_en(pwen),.app_wr_end(pwend),.app_addr(paddr),.app_wr_data(pwdata),.app_wr_mask(pmask),.app_burst(burst),.app_sr(selfrefresh),.app_ref(refresh),
  .f_boot_private_loader_ready_o(1'b0),
  .f_boot_app_cmd_o(3'd1),
  .f_boot_app_cmd_en_o(boot_offer && boot_ready),
  .f_boot_app_addr_o({7'd0,boot_word,3'd0}),
  .f_boot_app_wr_data_o(256'd0),
  .f_boot_app_wr_data_en_o(1'b0),
  .f_boot_app_wr_data_end_o(1'b0),
  .f_boot_app_wr_data_mask_o(32'd0),
  .f_boot_app_burst_o(1'b0),
  .f_boot_app_self_refresh_req_o(1'b0),
  .f_boot_app_refresh_req_o(1'b0),
  .f_boot_model_locked_o(boot_locked),
  .f_boot_fail_closed_o(1'b0),
  .f_boot_watchdog_fault_o(1'b0));
 function automatic[255:0]payload(input integer j);
  for(integer k=0;k<8;k=k+1)payload[k*32+:32]=32'h6d010203 ^ (j*32'h1030701) ^ (k*32'h01010101);
 endfunction
 function automatic[255:0]initial_word(input integer j);
  for(integer k=0;k<8;k=k+1)initial_word[k*32+:32]=32'h90a0b0c0 ^ (j*32'h10203) ^ (k*32'h01010101);
 endfunction
 function automatic integer memory_index(input integer word);
  memory_index=word<=2 ? word : word-227072+3;
 endfunction
 always @(posedge coreclk)begin
  ctick<=ctick+1;
  if(resetn)begin
   if(memoryfault || transportfault || sharedfault)$fatal(1,"UNEXPECTED_NATIVE_FAULT");
   if(dut.u_transport.enqueue)begin
    if(dut.u_transport.core_write)normalized_writes=normalized_writes+1;
    else normalized_reads=normalized_reads+1;
    $fdisplay(tracefile,"N %0t %0d %0d %0d %064h",$time,dut.u_memory.u_handoff.runtime_q,dut.u_transport.core_write,dut.u_transport.core_addr_i>>3,dut.u_transport.core_wr_data_i);
   end
   if(dut.u_shared.model_admit)begin model_admissions=model_admissions+1;$fdisplay(tracefile,"M %0t %0d",$time,dut.u_shared.model_req_word_i);end
   if(dut.u_shared.kv_admit)begin kv_admissions=kv_admissions+1;$fdisplay(tracefile,"K %0t %0d %0d %064h",$time,kv_write,kv_word,kv_data);end
   if(dut.u_shared.model_admit && dut.u_shared.kv_admit)simultaneous_admits=simultaneous_admits+1;
   if(good && dut.request_valid && !dut.request_ready)raw_stall_cycles=raw_stall_cycles+1;
   if(kv_valid && kv_write && kv_ready)begin
    if(normalized_writes<=write_acks)begin
     $display("ACK_BEFORE_NORMALIZED_ADMISSION ack=%0d admitted=%0d physical=%0d",write_acks+1,normalized_writes,physical_writes);
     $fatal(1,"ACK_BEFORE_NORMALIZED_ADMISSION");
    end
    write_acks=write_acks+1;
    if(physical_writes==0)write_acks_before_issue=write_acks_before_issue+1;
    $fdisplay(tracefile,"A %0t %0d %0d %0d",$time,write_acks,normalized_writes,physical_writes);
   end
   if(model_rsp)begin
    if(model_error || model_data!==initial_word(model_returns%3))$fatal(1,"MODEL_RETURN");
    $fdisplay(tracefile,"MR %0t %064h",$time,model_data);model_returns=model_returns+1;
   end
   if(kv_rsp && kv_return_ready)begin
    if(kv_error || kv_rsp_data!==payload(297+kv_returns%3))$fatal(1,"KV_RETURN");
    $fdisplay(tracefile,"KR %0t %064h",$time,kv_rsp_data);kv_returns=kv_returns+1;
   end
   if(dut.u_memory.boot_read_valid)begin
    if(dut.u_memory.selected_read_data!==initial_word(boot_returns))$fatal(1,"BOOT_RETURN");
    boot_returns=boot_returns+1;
   end
   if(observe_clear)$fdisplay(tracefile,"C %0t %0d %0d %0d",$time,dut.kv_write_pending_q,dut.u_transport.reserved_q,write_acks);
  end
 end
 always @(posedge appclk)begin
  atick<=atick+1;
  if(resetn)begin
   if(pen)begin
    if(!cmdready || paddr[2:0]!=0 || !((paddr>>3)<=2 || ((paddr>>3)>=227072 && (paddr>>3)<=227074)) || burst || selfrefresh || refresh)$fatal(1,"PHYSICAL_COMMAND");
    if(pcmd==0)begin
     if(!pwen || !pwend || !dataready || pmask!=0 || (paddr>>3)<227072)$fatal(1,"PHYSICAL_WRITE");
     memory[memory_index(paddr>>3)]<=pwdata;physical_writes=physical_writes+1;
     $fdisplay(tracefile,"W %0t %0d %064h",$time,paddr>>3,pwdata);
    end else if(pcmd==1)begin
     if(pwen || pending==32)$fatal(1,"PHYSICAL_READ");
     responses[readtail]<=memory[memory_index(paddr>>3)];readtail<=readtail+1'b1;physical_reads=physical_reads+1;
     $fdisplay(tracefile,"R %0t %0d %064h",$time,paddr>>3,memory[memory_index(paddr>>3)]);
    end else $fatal(1,"PHYSICAL_OPCODE");
   end
   if(rvalid)begin
    if(!dut.u_transport.response_s_ready || dut.u_transport.physical_reads_q==0)$fatal(1,"RETURN_CREDIT");
    $fdisplay(tracefile,"D %0t %064h",$time,rdata);readhead<=readhead+1'b1;physical_returns=physical_returns+1;
   end
   case({readtake,rvalid})2'b10:pending<=pending+1'b1;2'b01:pending<=pending-1'b1;default:;endcase
  end
 end
 initial begin
  tracefile=$fopen("events.txt","w");for(integer j=0;j<6;j=j+1)memory[j]=initial_word(j);
  #31;resetn=1;
  wait(dut.u_memory.app_domain_reset_n && dut.u_transport.core_controller_good_o);
  for(integer j=0;j<3;j=j+1)begin
   @(negedge coreclk);boot_offer=1;boot_word=19'(j);
   @(posedge coreclk);while(boot_ready!==1'b1)@(posedge coreclk);
   @(negedge coreclk);boot_offer=0;
  end
  boot_locked=1;wait(good===1'b1);repeat(5)@(negedge coreclk);vendor_stall=1;
  fork
   begin
    for(integer j=0;j<260;j=j+1)begin
     @(negedge coreclk);model_valid=1;model_word=19'(j%3);
     @(posedge coreclk);while(model_ready!==1'b1)@(posedge coreclk);
     @(negedge coreclk);model_valid=0;
    end
   end
   begin
    for(integer j=0;j<300;j=j+1)begin
     @(negedge coreclk);kv_valid=1;kv_write=1;kv_word=19'(227072+j%3);kv_data=payload(j);
     @(posedge coreclk);while(kv_ready!==1'b1)@(posedge coreclk);
     @(negedge coreclk);kv_valid=0;
    end
    for(integer j=0;j<12;j=j+1)begin
     @(negedge coreclk);kv_valid=1;kv_write=0;kv_word=19'(227072+j%3);
     @(posedge coreclk);while(kv_ready!==1'b1)@(posedge coreclk);
     @(negedge coreclk);kv_valid=0;
     wait(kv_returns==j+1);
    end
   end
   begin #60000;vendor_stall=0;end
   begin #2000;@(negedge coreclk);observe_clear=1;repeat(4)@(negedge coreclk);observe_clear=0;end
  join
  wait(physical_writes==300 && physical_reads==275 && model_returns==260 && kv_returns==12 && boot_returns==3);
  repeat(25)@(negedge coreclk);
  if(normalized_writes!=300 || normalized_reads!=275 || write_acks!=300 || physical_returns!=275 || model_admissions!=260 || kv_admissions!=312 || pending!=0 || dut.u_transport.reserved_q!=0 || dut.u_shared.busy_o || raw_stall_cycles==0 || simultaneous_admits==0 || write_acks_before_issue==0)$fatal(1,"FINAL_COUNTS_OR_DRAIN");
  $display("PASS SHARED_RUNTIME norm_writes=%0d norm_reads=%0d acks=%0d physical_writes=%0d physical_reads=%0d model_returns=%0d kv_returns=%0d boot_returns=%0d stalls=%0d simultaneous=%0d early_physical_acks=%0d",normalized_writes,normalized_reads,write_acks,physical_writes,physical_reads,model_returns,kv_returns,boot_returns,raw_stall_cycles,simultaneous_admits,write_acks_before_issue);$finish;
 end
 initial begin #250000;$fatal(1,"NATIVE_TIMEOUT");end
endmodule
