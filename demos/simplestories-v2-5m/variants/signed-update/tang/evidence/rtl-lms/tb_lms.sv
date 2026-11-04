`timescale 1ns/1ps
module tb_lms;
  reg clk=0;always #5 clk=~clk;
  reg reset_n=0,start=0;
  reg [127:0] identifier;reg [255:0] root;
  reg [8:0] length;
  wire [10:0] sa;wire [7:0] ma;
  reg [7:0] signature[0:1291];reg [7:0] message[0:255];
  wire busy,done,valid,fault;
  integer total_cycles=0;
  reg [3:0] stall_cycle=0;
  always @(posedge clk) if(!reset_n) stall_cycle<=0;else stall_cycle<=stall_cycle+1;
  su_lms_verify dut(.clk(clk),.reset_n(reset_n),.start_i(start),
    .public_i_i(identifier),.public_root_i(root),.message_length_i(length),
    .signature_address_o(sa),.signature_byte_i(signature[sa]),.signature_ready_i(stall_cycle[1:0]!=3),
    .message_address_o(ma),.message_byte_i(message[ma]),
    .busy_o(busy),.done_o(done),.valid_o(valid),.fault_o(fault));
  task run_case(input integer n,input integer len,input [127:0] id,
                input [255:0] expected_root,input expected);
    integer cycles;string path;
    begin
      reset_n=0;start=0;repeat(3) @(negedge clk);
      path=$sformatf("LOCAL_INTEGRATION/evidence/rtl-lms/%0d-signature.hex",n);$readmemh(path,signature);
      path=$sformatf("LOCAL_INTEGRATION/evidence/rtl-lms/%0d-message.hex",n);$readmemh(path,message);
      identifier=id;root=expected_root;length=9'(len);
      reset_n=1;@(negedge clk);start=1;@(negedge clk);start=0;
      cycles=0;
      while(!done && cycles<3000000) begin
        if(valid) $fatal(1,"early validity");
        @(negedge clk);cycles=cycles+1;
      end
      if(!done || valid!==expected) $fatal(1,"vector %0d done=%0d valid=%0d expected=%0d fault=%0d state=%0d cycles=%0d",n,done,valid,expected,fault,dut.state_q,cycles);
      total_cycles=total_cycles+cycles;
      $display("PASS vector=%0d cycles=%0d expected=%0d",n,cycles,expected);
    end
  endtask
  initial begin
run_case(0, 56, 128'h61a5d57d37f5e46bfb7520806b07a1b8, 256'h50650e3b31fe4a773ea29a07f09cf2ea30e579f0df58ef8e298da0434cb2b878, 1'b1);
run_case(1, 56, 128'h61a5d57d37f5e46bfb7520806b07a1b8, 256'h50650e3b31fe4a773ea29a07f09cf2ea30e579f0df58ef8e298da0434cb2b878, 1'b0);
run_case(2, 162, 128'hd2f14ff6346af964569f7d6cb880a1b6, 256'h6c5004917da6eafe4d9ef6c6407b3db0e5485b122d9ebe15cda93cfec582d7ab, 1'b1);
run_case(3, 162, 128'hd2f14ff6346af964569f7d6cb880a1b6, 256'h6c5004917da6eafe4d9ef6c6407b3db0e5485b122d9ebe15cda93cfec582d7ab, 1'b0);
run_case(4, 128, 128'hd4fb8c0c47f8740765ae0d128274c548, 256'h3e920c09320298bd7806989e22d1cf97594269d76a7dfd1c4ea894185f857990, 1'b1);
run_case(5, 128, 128'h82651cf4a90344fb9ee755e7f75aa634, 256'h45f6638f959894f58e7e58c1ae8dde460e04b686be66977438a7ec24d35b77e7, 1'b1);
run_case(6, 128, 128'hd4fb8c0c47f8740765ae0d128274c548, 256'h3e920c09320298bd7806989e22d1cf97594269d76a7dfd1c4ea894185f857990, 1'b1);
run_case(7, 128, 128'h82651cf4a90344fb9ee755e7f75aa634, 256'h45f6638f959894f58e7e58c1ae8dde460e04b686be66977438a7ec24d35b77e7, 1'b1);
run_case(8, 128, 128'hd4fb8c0c47f8740765ae0d128274c548, 256'h3e920c09320298bd7806989e22d1cf97594269d76a7dfd1c4ea894185f857990, 1'b1);
run_case(9, 128, 128'h82651cf4a90344fb9ee755e7f75aa634, 256'h45f6638f959894f58e7e58c1ae8dde460e04b686be66977438a7ec24d35b77e7, 1'b1);
run_case(10, 128, 128'h82651cf4a90344fb9ee755e7f75aa634, 256'h45f6638f959894f58e7e58c1ae8dde460e04b686be66977438a7ec24d35b77e7, 1'b0);
run_case(11, 128, 128'h82651cf4a90344fb9ee755e7f75aa634, 256'h45f6638f959894f58e7e58c1ae8dde460e04b686be66977438a7ec24d35b77e7, 1'b0);
run_case(12, 128, 128'h82651cf4a90344fb9ee755e7f75aa634, 256'h45f6638f959894f58e7e58c1ae8dde460e04b686be66977438a7ec24d35b77e7, 1'b0);
run_case(13, 128, 128'h82651cf4a90344fb9ee755e7f75aa634, 256'h45f6638f959894f58e7e58c1ae8dde460e04b686be66977438a7ec24d35b77e7, 1'b0);
run_case(14, 128, 128'h82651cf4a90344fb9ee755e7f75aa634, 256'h45f6638f959894f58e7e58c1ae8dde460e04b686be66977438a7ec24d35b77e7, 1'b0);
run_case(15, 128, 128'h82651cf4a90344fb9ee755e7f75aa634, 256'h45f6638f959894f58e7e58c1ae8dde460e04b686be66977438a7ec24d35b77e7, 1'b0);
run_case(16, 128, 128'h82651cf4a90344fb9ee755e7f75aa634, 256'h45f6638f959894f58e7e58c1ae8dde460e04b686be66977438a7ec24d35b77e6, 1'b0);
    $display("PASS all LMS vectors total_cycles=%0d",total_cycles);$finish;
  end
endmodule
