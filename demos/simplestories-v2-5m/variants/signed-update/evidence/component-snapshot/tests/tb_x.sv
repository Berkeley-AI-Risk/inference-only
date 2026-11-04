`timescale 1ns/1ps
module tb_x;
  reg clk=0;always #5 clk=~clk;
  reg reset_n=0,bv=0,bl=0;reg [7:0] bb=0;
  wire br,sealed,fault;wire [255:0] image_sha;
  wire [31:0] digest;wire [191:0] metadata;
  reg start=0,rv=0,rl=0;reg [7:0] rb=0;
  wire rr,iv,ifault;
  swic_boot_admission dut(.clk(clk),.reset_n(reset_n),.boot_valid_i(bv),.boot_last_i(bl),.boot_byte_i(bb),
    .boot_ready_o(br),.sealed_o(sealed),.fail_closed_o(fault),.expected_image_sha_o(image_sha),
    .digest_read_i(1'b0),.digest_address_i(14'd0),.digest_data_o(digest),
    .metadata_read_i(1'b0),.metadata_address_i(12'd0),.metadata_data_o(metadata));
  su_image_check image_check(.clk(clk),.reset_n(reset_n),.start_i(start),.expected_sha_i(256'd0),
    .readback_valid_i(rv),.readback_last_i(rl),.readback_byte_i(rb),.readback_ready_o(rr),
    .verified_o(iv),.fault_o(ifault));
  task reset_all;
    begin reset_n=0;bv=0;bl=0;bb=0;start=0;rv=0;rl=0;rb=0;
      repeat(4) @(negedge clk);reset_n=1;@(negedge clk);
      if(fault || ifault || sealed || iv) $fatal(1,"known reset failed");end
  endtask
  initial begin
    reset_all();bv=1;bb=8'hxx;@(negedge clk);
    if(!fault || sealed || image_sha!==0 || digest!==0 || metadata!==0) $fatal(1,"unknown frame data");
    $display("PASS unknown frame data rejected");
    reset_all();bv=1;bl=1'bx;@(negedge clk);if(!fault || sealed) $fatal(1,"unknown last");
    $display("PASS unknown frame last rejected");
    reset_all();bv=1'bx;@(negedge clk);if(!fault || sealed) $fatal(1,"unknown valid");
    $display("PASS unknown frame valid rejected");
    reset_all();start=1;@(negedge clk);start=0;rv=1;rb=8'hxx;@(negedge clk);
    if(!ifault || iv) $fatal(1,"unknown readback data");
    $display("PASS unknown DDR readback data rejected");
    reset_all();start=1;@(negedge clk);start=0;rv=1;rl=1'bx;@(negedge clk);
    if(!ifault || iv) $fatal(1,"unknown readback last");
    $display("PASS unknown DDR last rejected");
    reset_all();start=1'bx;@(negedge clk);if(!ifault || iv) $fatal(1,"unknown image start");
    $display("PASS unknown private image start rejected");
    $display("PASS six four-state checks");$finish;
  end
endmodule
