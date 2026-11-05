`timescale 1ns/1ps
module GSR;
  wire GSRO=1; // Hierarchical GSR.GSRO used by the unmodified vendor primitive.
  reg pll=0,reset_n=0;
  always #10 pll=~pll;
  wire core,trusted;
  CLKDIV #(.DIV_MODE("2"))c(core,1'b0,pll,reset_n);
  CLKDIV #(.DIV_MODE("4"))t(trusted,1'b0,pll,reset_n);
  reg[2:0] tr;
  always @(posedge trusted or negedge reset_n)
    if(!reset_n)tr<=0;else tr<={tr[1:0],1'b1};
  wire ready;
  startup_reset dut(core,reset_n,tr[2],reset_n,ready);
  realtime last_core_rise,last_trusted_rise;
  integer alignments=0,releases=0,i;
  always @(posedge core)last_core_rise=$realtime;
  always @(posedge trusted)begin
    last_trusted_rise=$realtime;
    #0.001;
    if(reset_n && last_core_rise!=last_trusted_rise)$fatal(1,"unaligned divided rising edges");
    if(reset_n)alignments=alignments+1;
  end
  always @(posedge ready)begin
    if(core!==1)$fatal(1,"reset release is not on rising edge");
    if($realtime-last_core_rise!=0.0)$fatal(1,"not on rising edge");
    releases=releases+1;
  end
  initial begin
    #0.125;reset_n=1;#0.125;reset_n=0;
    for(i=0;i<160;i=i+1)begin
      #(20.25+0.5*i);reset_n=1;
      #800;if(ready!==1)$fatal(1,"vendor-clock startup failed");
      reset_n=0;#0.001;if(ready!==0)$fatal(1,"async assertion failed");
    end
    if(releases!=160)$fatal(1,"missing startup releases");
    $display("PASS vendor divided clocks alignments=%0d startups=%0d",alignments,releases);
    $finish;
  end
endmodule
