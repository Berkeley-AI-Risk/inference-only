`timescale 1ns/1ps
module witness;
    logic clk=0; always #5 clk=~clk;
    logic reset_n=0,nonce_valid=0,grant_valid=0,grant_last=0;
    logic [7:0] grant_byte=0;
    logic [255:0] root=256'h12345678;
    localparam [255:0] NONCE=256'hfeedbeef;
    localparam [127:0] DEVICE=128'h395c83e440d5252bfa59f6138e5ed3b8;
    localparam [255:0] GEOMETRY=256'h2128664c0025b4ed2ddbd53b2178ea926fe1b3c5e817a2b043a2abc9ee41f078;
    wire [1023:0] header={128'h53415749432d484f4d452d7631000000,DEVICE,NONCE,root,GEOMETRY};
    wire request_valid,request_last,grant_ready,enabled,failed,accepted,start;
    wire [7:0] request_byte;
    wire [63:0] remaining;
    logic [10:0] signature_address=0;
    wire [7:0] signature_byte;
    wire signature_ready;
    logic verdict_done=0,verdict_valid=0;
    integer sent=0,grants=0,phase=0;
    home_boot_gate #(.USE_SHARED_VERIFIER(1),.DEVICE_ID(DEVICE),.GEOMETRY(GEOMETRY),
        .RESPONSE_LIMIT_CYCLES(100000000),.LEASE_CYCLES(250000000),.RENEW_LEAD_CYCLES(125000000)) dut(
        .clk(clk),.reset_n(reset_n),.nonce_valid_i(nonce_valid),.nonce_fault_i(1'b0),.nonce_i(NONCE),
        .admitted_root_valid_i(1'b1),.admitted_root_i(root),.model_fault_i(1'b0),
        .request_valid_o(request_valid),.request_last_o(request_last),.request_byte_o(request_byte),.request_ready_i(1'b1),
        .grant_valid_i(grant_valid),.grant_last_i(grant_last),.grant_byte_i(grant_byte),.grant_ready_o(grant_ready),
        .inference_enabled_o(enabled),.failed_o(failed),.new_lease_o(accepted),.lease_cycles_remaining_o(remaining),
        .shared_start_o(start),.shared_message_address_i(8'd0),.shared_signature_address_i(signature_address),
        .shared_signature_byte_o(signature_byte),.shared_signature_ready_o(signature_ready),
        .shared_busy_i(1'b0),.shared_done_i(verdict_done),.shared_valid_i(verdict_valid),.shared_fault_i(1'b0));
    always @(posedge clk) if(reset_n) begin
        if(request_valid) begin
            if(request_byte !== header[1023-8*sent -:8]) $fatal(1,"request byte mismatch");
            if(request_last !== (sent==127)) $fatal(1,"request framing mismatch");
            sent=sent+1;
        end
        if(accepted) grants=grants+1;
    end
    task automatic boot;
        @(negedge clk);reset_n=0;nonce_valid=0;grant_valid=0;verdict_done=0;verdict_valid=0;sent=0;
        repeat(3) @(negedge clk);
        if(enabled) $fatal(1,"permission survived reset");
        reset_n=1;nonce_valid=1;
        wait(grant_ready);@(negedge clk);
        if(sent!=128) $fatal(1,"request incomplete");
    endtask
    task automatic frame(input bit bad);
        for(integer i=0;i<1420;i=i+1) begin
            grant_valid=1;grant_last=(i==1419);
            grant_byte=(i<128)?header[1023-8*i -:8]:8'h5c;
            if(bad && i==16) grant_byte=grant_byte^8'h01;
            @(negedge clk);
        end
        grant_valid=0;grant_last=0;
    endtask
    initial begin
        boot();frame(0);
        wait(start);@(negedge clk);
        for(integer i=0;i<1292;i=i+1) begin
            signature_address=11'(i);repeat(2) @(negedge clk);
            if(!signature_ready || signature_byte!==8'h5c) $fatal(1,"signature RAM did not preserve current grant byte");
        end
        verdict_done=1;verdict_valid=1;
        repeat(2) @(negedge clk);
        verdict_done=0;verdict_valid=0;
        if(!enabled || failed || grants!=1 || remaining>=250000000) $fatal(1,"valid grant did not activate bounded lease");
        repeat(4) @(negedge clk);
        root=root^256'd1;#1;
        if(enabled || !failed) $fatal(1,"changed model retained permission");
        repeat(3) @(negedge clk);
        root=root^256'd1;#1;
        if(enabled || !failed) $fatal(1,"failure not sticky");
        boot();frame(1);verdict_done=1;verdict_valid=1;
        repeat(8) @(negedge clk);
        if(enabled || !failed || grants!=1) $fatal(1,"wrong device header granted permission");
        $display("WITNESS PASS: valid grant reachable; all 1292 signature bytes, model substitution, failure recovery without reset, wrong-device header and reset controls checked. Abstract crypto verdict only.");
        $finish;
    end
    initial begin #100000; $fatal(1,"witness did not finish"); end
endmodule
