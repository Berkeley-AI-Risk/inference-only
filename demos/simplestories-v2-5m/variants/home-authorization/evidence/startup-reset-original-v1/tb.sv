`timescale 1ns/1ps
module tb;
  reg clk=0,run_clock=1;
  always #20 if(run_clock)clk=~clk;
  reg b=1,t=1,a=1;
  wire ready;
  startup_reset dut(clk,b,t,a,ready);
  integer edges=0, checks=0, cases=0, pulse,mask;
  // Count active edges since all three source resets became inactive.
  always @(posedge clk or negedge b or negedge t or negedge a) begin
    if(!(b&&t&&a))edges=0;
    else if(edges<3)edges=edges+1;
    #0.001;
    if(ready !== ((b&&t&&a)&&(edges==3)))
      $fatal(1,"release sequencing mismatch time=%0t edges=%0d ready=%b",$time,edges,ready);
    checks=checks+1;
  end
  always @(posedge clk)begin
    #0.002;
    if(ready !== ((b&&t&&a)&&(edges==3)))$fatal(1,"rising-edge mismatch");
    checks=checks+1;
  end
  task assert_mask(input integer m);
    begin b=(m&1)==0;t=(m&2)==0;a=(m&4)==0;end
  endtask
  initial begin
    // All seven nonempty reset combinations, 320 sub-ns release phases,
    // and both short and multi-cycle assertion pulses. No coincident stimulus.
    #0.125;b=0;t=0;a=0;
    for(mask=1;mask<8;mask=mask+1)begin
      for(pulse=0;pulse<320;pulse=pulse+1)begin
        @(posedge clk);#0.125;assert_mask(mask);
        #(0.25+0.5*pulse);b=1;t=1;a=1;
        #0.001;if(ready!==0)$fatal(1,"early release");
        repeat(4)@(negedge clk);
        #0.01;if(ready!==1)$fatal(1,"release failed");
        cases=cases+1;
      end
    end
    // Assertion must work without a clock; release must wait for clock edges.
    @(negedge clk);#0.125;run_clock=0;b=0;
    #0.01;if(ready!==0)$fatal(1,"stopped-clock assertion failed");
    #103;b=1;
    #161;if(ready!==0)$fatal(1,"stopped-clock release escaped");
    run_clock=1;repeat(4)@(negedge clk);
    #0.01;if(ready!==1)$fatal(1,"restart release failed");
    $display("PASS reset phase sweep cases=%0d checks=%0d; stopped-clock assertion/restart",cases,checks);
    $finish;
  end
endmodule
