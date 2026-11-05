`timescale 1ns/1ps
module tb_home;
    reg clk=0;always #5 clk=~clk;
    reg reset_n=0,nv=0,nf=0,rv=0,mf=0,ready=1,gv=0,gl=0;
    reg [255:0] nonce=0,root=0;
    reg [7:0] gb=0;
    wire nr,qv,ql,gr,enabled,failed;wire [7:0] qb;
    reg [7:0] frame[0:1420];
    reg [7:0] expected_request[0:127];
    integer passed=0;
    `include "fixtures.svh"
    home_boot_gate #(.DEVICE_ID(DEVICE),.GEOMETRY(GEOM),.HOME_KEY_ID(HOME_ID),
      .HOME_KEY_ROOT(HOME_ROOT),.RESPONSE_LIMIT_CYCLES(3000000),
      .LEASE_CYCLES(10000000),.RENEW_LEAD_CYCLES(4000000)) dut(
      .clk(clk),.reset_n(reset_n),.nonce_valid_i(nv),.nonce_fault_i(nf),.nonce_i(nonce),.nonce_request_o(nr),
      .admitted_root_valid_i(rv),.model_fault_i(mf),.admitted_root_i(root),
      .request_valid_o(qv),.request_last_o(ql),.request_byte_o(qb),.request_ready_i(ready),
      .grant_valid_i(gv),.grant_last_i(gl),.grant_byte_i(gb),.grant_ready_o(gr),
      .inference_enabled_o(enabled),.failed_o(failed));

    reg sr=0;wire se,sf;
    home_boot_gate #(.DEVICE_ID(DEVICE),.GEOMETRY(GEOM),.HOME_KEY_ID(HOME_ID),.HOME_KEY_ROOT(HOME_ROOT),
      .RESPONSE_LIMIT_CYCLES(20),.LEASE_CYCLES(100),.RENEW_LEAD_CYCLES(40)) timeout_dut(
      .clk(clk),.reset_n(sr),.nonce_valid_i(1'b1),.nonce_fault_i(1'b0),.nonce_i(N1),.nonce_request_o(),
      .admitted_root_valid_i(1'b1),.model_fault_i(1'b0),.admitted_root_i(A),
      .request_valid_o(),.request_last_o(),.request_byte_o(),.request_ready_i(1'b0),
      .grant_valid_i(1'b0),.grant_last_i(1'b0),.grant_byte_i(8'd0),.grant_ready_o(),
      .inference_enabled_o(se),.failed_o(sf));

    task ok(input string name);
      begin passed=passed+1;$display("PASS %s",name);end
    endtask
    task clean;
      begin
        reset_n=0;nv=0;nf=0;rv=0;mf=0;ready=0;gv=0;gl=0;
        repeat(4) @(negedge clk);reset_n=1;@(negedge clk);
        if(enabled || failed) $fatal(1,"reset retained authorization/fault");
      end
    endtask
    task collect_request(input string file_name);
      integer i,cycles;
      begin
        $readmemh(file_name,expected_request);i=0;cycles=0;ready=1;
        while(i<128 && cycles<1000) begin
          @(posedge clk);
          if(qv && ready) begin
            if(qb!==expected_request[i] || ql!==(i==127)) $fatal(1,"request mismatch index=%0d",i);
            i=i+1;
          end
          @(negedge clk);cycles=cycles+1;
        end
        ready=0;if(i!=128) $fatal(1,"request did not complete %0d",i);
      end
    endtask
    task boot(input [255:0] n,input [255:0] r,input string req_file);
      begin
        clean();nonce=n;root=r;nv=1;rv=1;
        @(negedge clk);nv=0;
        collect_request(req_file);
        if(enabled) $fatal(1,"inference before grant");
      end
    endtask
    task deliver(input string file_name,input integer size,input bit expect_old_permit);
      integer i,cycles;
      begin
        $readmemh(file_name,frame,0,size-1);i=0;cycles=0;
        while(i<size && !failed && cycles<3000) begin
          gv=(cycles%7)!=0;gb=frame[i];gl=(i==size-1);
          @(posedge clk);if(gv && gr)i=i+1;
          @(negedge clk);cycles=cycles+1;
          if(!expect_old_permit && enabled) $fatal(1,"early grant acceptance");
        end
        gv=0;gl=0;
      end
    endtask
    task result(input bit expect_enabled,input string name);
      integer cycles;
      begin
        cycles=0;
        while(!enabled && !failed && cycles<3000000) begin @(negedge clk);cycles=cycles+1;end
        if(enabled!==expect_enabled || (!expect_enabled && !failed))
          $fatal(1,"%s enabled=%0d failed=%0d state=%0d",name,enabled,failed,dut.state_q);
        ok(name);
      end
    endtask
    task wait_renew;
      integer cycles;
      begin
        cycles=0;
        while(!nr && !failed && cycles<10000000) begin @(negedge clk);cycles=cycles+1;end
        if(!nr || !enabled) $fatal(1,"no live renewal opportunity");
      end
    endtask
    initial begin
      boot(N1,A,"request-a1.hex");deliver("grant-a1.hex",1420,0);result(1,"valid exact model and nonce");
      wait_renew();nonce=N2;nv=1;@(negedge clk);nv=0;
      collect_request("request-a2.hex");deliver("grant-a2.hex",1420,1);
      // An old valid lease remains live while the new signature is checked.
      while(dut.state_q!=5 && !failed) begin
        @(negedge clk);
        if(!enabled)$fatal(1,"renewal caused an outage state=%0d fault=%0d age=%0d lease_age=%0d crypto_fault=%0d",dut.state_q,failed,dut.age_q,dut.lease_age_q,dut.crypto_fault);
      end
      if(failed || dut.lease_age_q>3000000)$fatal(1,"renewal did not refresh lease");
      ok("successful fresh renewal without outage");
      root=B;#1;if(enabled)$fatal(1,"changed model retained authorization");
      @(negedge clk);result(0,"model identity change revokes immediately");

      boot(N1,A,"request-a1.hex");deliver("grant-a1.hex",1420,0);result(1,"bad renewal setup");
      wait_renew();nonce=N2;nv=1;@(negedge clk);nv=0;
      collect_request("request-a2.hex");deliver("grant-renew-corrupt.hex",1420,1);
      while(dut.state_q!=15 && dut.state_q!=5) @(negedge clk);
      if(!failed || enabled)$fatal(1,"bad renewal reused an old signature verdict");
      ok("invalid renewal cannot reuse previous signature verdict");

      boot(N2,A,"request-a2.hex");deliver("grant-a1.hex",1420,0);result(0,"previous boot grant replay");
      boot(N1,A,"request-a1.hex");deliver("grant-b1.hex",1420,0);result(0,"valid signature for wrong model");
      boot(N1,A,"request-a1.hex");deliver("grant-device.hex",1420,0);result(0,"valid signature for wrong device");
      boot(N1,A,"request-a1.hex");deliver("grant-corrupt.hex",1420,0);result(0,"corrupt LMS signature");
      boot(N1,A,"request-a1.hex");deliver("grant-a1.hex",1419,0);result(0,"truncated grant");
      boot(N1,A,"request-a1.hex");deliver("grant-extra.hex",1421,0);result(0,"oversized grant");

      boot(N1,A,"request-a1.hex");deliver("grant-a1.hex",1420,0);
      repeat(100) @(negedge clk);clean();repeat(100) @(negedge clk);
      if(enabled)$fatal(1,"reset during crypto retained approval");ok("reset during signature verification");

      boot(N1,A,"request-a1.hex");deliver("grant-a1.hex",1420,0);result(1,"lease expiry setup");
      wait_renew();
      // No entropy or renewal reply arrives. The existing permit must expire anyway.
      while(enabled) @(negedge clk);
      if(dut.lease_age_q<9999999)$fatal(1,"unexpected early expiry without fault");
      ok("no renewal means inference stops at bounded lease expiry");

      boot(N1,A,"request-a1.hex");deliver("grant-a1.hex",1420,0);result(1,"repeated nonce setup");
      wait_renew();nonce=N1;nv=1;@(negedge clk);nv=0;@(negedge clk);
      result(0,"repeated entropy output fails closed");

      clean();nonce=0;nv=1;root=A;rv=1;repeat(3)@(negedge clk);result(0,"zero nonce rejected");
      clean();nonce=N1;nv=1;root=A;rv=0;repeat(10)@(negedge clk);
      if(qv||enabled)$fatal(1,"request/inference before model admission");ok("no request before verified model root");
      nf=1;@(negedge clk);result(0,"entropy fault fails closed");

      sr=1;repeat(30)@(negedge clk);if(!sf||se)$fatal(1,"stalled request did not expire");
      ok("response window includes stalled request transmission");
      $display("PASS all home-authorization cases count=%0d",passed);$finish;
    end
endmodule
