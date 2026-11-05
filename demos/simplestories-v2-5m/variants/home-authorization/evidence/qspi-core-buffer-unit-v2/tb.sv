`timescale 1ns/1ps
module tb;
  reg core=0,trusted=0,run_core=1,run_trusted=1;
  always #20 if(run_core)core=~core;
  always #40 if(run_trusted)trusted=~trusted;
  reg cr=1,tr=1;
  swic_qspi_boot_source dut(.core_clk_i(core),.trusted_clk_i(trusted),
    .core_reset_n_i(cr),.trusted_reset_n_i(tr),.allow_model_i(1'b0),
    .byte_ready_i(1'b0),.qspi_dq_i(4'd0));
  wire common=cr&&tr;
  integer cn=0,sn=0,checks=0,cases=0,mask,phase;
  reg saw_falling=0;

  always @(posedge core or negedge common)begin
    if(!common)cn=0;else if(cn<3)cn=cn+1;
    #0.002;if(dut.core_release_q!==((1<<cn)-1))$fatal(1,"core release count differs");
    checks=checks+1;
  end
  always @(posedge trusted or negedge common)begin
    if(!common)sn=0;else if(sn<3)sn=sn+1;
    #0.003;if(dut.slow_release_q!==((1<<sn)-1))$fatal(1,"trusted release count differs");
    checks=checks+1;
  end
  initial begin
    #0.125;cr=0;tr=0;
    for(mask=1;mask<4;mask=mask+1)begin
      for(phase=0;phase<400;phase=phase+1)begin
        @(posedge core);#0.125;cr=(mask&1)==0;tr=(mask&2)==0;
        #(0.25+0.4*phase);cr=1;tr=1;
        #0.001;if(dut.core_release_q!==0||dut.slow_release_q!==0)$fatal(1,"early release");
        repeat(4)@(posedge trusted);
        #0.01;if(dut.core_release_q!==7||dut.slow_release_q!==7)$fatal(1,"startup did not settle");
        cases=cases+1;
      end
    end
    @(negedge core);#0.125;run_core=0;run_trusted=0;cr=0;
    #0.01;if(dut.core_release_q!==0||dut.slow_release_q!==0)$fatal(1,"stopped clock reset escaped");
    #103;cr=1;#161;
    if(dut.core_release_q!==0||dut.slow_release_q!==0)$fatal(1,"release without clocks");
    run_core=1;run_trusted=1;repeat(4)@(posedge trusted);
    #0.01;if(dut.core_release_q!==7||dut.slow_release_q!==7)$fatal(1,"restart did not release");
    $display("PASS actual flash-loader reset phases=%0d checks=%0d, stopped clocks and restart",cases,checks);
    $finish;
  end
endmodule
