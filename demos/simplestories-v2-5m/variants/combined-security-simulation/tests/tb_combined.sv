`timescale 1ns/1ps
module tb_combined;
    reg clk=0;always #5 clk=~clk;
    reg power_reset_n=0,session_reset_n=0;
    reg [31:0] epoch=1;
    reg [63:0] cycles=0,time_jump=0;
    wire [63:0] trusted_now=cycles+time_jump;
    always @(posedge clk) if(power_reset_n) cycles<=cycles+1'b1;
    reg manifest_valid=0,manifest_last=0,cipher_valid=0;
    reg [7:0] manifest_byte=0;reg [255:0] cipher_word=0;
    wire manifest_ready,cipher_ready;
    reg nonce_valid=0;reg [255:0] nonce=0;wire nonce_request;
    wire request_valid,request_last;wire [7:0] request_byte;
    reg request_ready=0,grant_valid=0,grant_last=0;reg [7:0] grant_byte=0;wire grant_ready;
    reg append_valid=0,step_valid=0,token_ready=1,clear=0;
    reg [11:0] append_token=1;wire append_ready,step_ready,token_valid;wire [11:0] token;
    wire mem_req_valid,mem_req_write;wire [18:0] mem_req_word;wire [255:0] mem_req_data;
    reg mem_req_ready=1,mem_rsp_valid=0;reg [255:0] mem_rsp_data=0;
    wire boot_locked,runtime_enabled,new_lease,expired,fault,drained;
    wire [255:0] model,context_digest;wire [63:0] dropped;
    combined_top dut(.clk(clk),.power_reset_n(power_reset_n),.session_reset_n(session_reset_n),
        .private_epoch_i(epoch),.private_trusted_now_i(trusted_now),
        .manifest_valid_i(manifest_valid),.manifest_last_i(manifest_last),.manifest_byte_i(manifest_byte),.manifest_ready_o(manifest_ready),
        .cipher_valid_i(cipher_valid),.cipher_word_i(cipher_word),.cipher_ready_o(cipher_ready),
        .private_nonce_valid_i(nonce_valid),.private_nonce_i(nonce),.private_nonce_request_o(nonce_request),
        .home_request_valid_o(request_valid),.home_request_last_o(request_last),.home_request_byte_o(request_byte),.home_request_ready_i(request_ready),
        .grant_valid_i(grant_valid),.grant_last_i(grant_last),.grant_byte_i(grant_byte),.grant_ready_o(grant_ready),
        .append_valid_i(append_valid),.append_token_i(append_token),.append_ready_o(append_ready),
        .step_valid_i(step_valid),.step_ready_o(step_ready),.token_ready_i(token_ready),.clear_i(clear),.token_valid_o(token_valid),.token_o(token),
        .memory_req_valid_o(mem_req_valid),.memory_req_write_o(mem_req_write),.memory_req_word_o(mem_req_word),.memory_req_data_o(mem_req_data),
        .memory_req_ready_i(mem_req_ready),.memory_rsp_valid_i(mem_rsp_valid),.memory_rsp_error_i(1'b0),.memory_rsp_data_i(mem_rsp_data),
        .boot_locked_o(boot_locked),.runtime_enabled_o(runtime_enabled),.new_lease_o(new_lease),.expired_o(expired),.fault_o(fault),
        .admitted_model_o(model),.authorization_context_o(context_digest),.dropped_response_count_o(dropped),.memory_drained_o(drained));
    `include "fixture_constants.svh"
    localparam integer FRAME_BYTES=115396,IMAGE_WORDS=227062;
    reg [7:0] manifest[0:FRAME_BYTES-1];
    // Untrusted external memory: ciphertext model followed by cipher K/V.
    reg [255:0] memory[0:472831];
    reg [255:0] return_queue[0:63];
    integer qhead=0,qtail=0,qcount=0;
    integer scenario,lease_count=0,step_count=0,token_count=0;
    integer read_count=0,write_count=0,late_return_count=0;
    bit hold_returns=0,expired_seen=0,ever_enabled=0,renewal_reset_seen=0;
    string fixtures,path;
    wire read_fire=mem_req_valid && mem_req_ready && !mem_req_write;
    wire send_return=power_reset_n && !hold_returns && qcount!=0;
    always @(posedge clk) begin
        mem_rsp_valid<=0;
        if(power_reset_n) begin
            if(mem_req_valid && mem_req_ready) begin
                if(mem_req_word>=472832)$fatal(1,"external address outside fixed memory");
                if(mem_req_write)begin
                    if(mem_req_word<227072)$fatal(1,"inference write into model");
                    memory[mem_req_word]<=mem_req_data;write_count<=write_count+1;
                end else begin
                    if(qcount>=64)$fatal(1,"behavioral return queue overflow");
                    return_queue[qtail]<=memory[mem_req_word];qtail<=(qtail+1)%64;read_count<=read_count+1;
                end
            end
            if(send_return)begin
                mem_rsp_valid<=1;mem_rsp_data<=return_queue[qhead];qhead<=(qhead+1)%64;
                if(expired_seen)late_return_count<=late_return_count+1;
            end
            case({read_fire,send_return})
                2'b10:qcount<=qcount+1;
                2'b01:qcount<=qcount-1;
                default:begin end
            endcase
            if(new_lease)begin
                lease_count<=lease_count+1;
                $display("LEASE accepted=%0d cycles=%0d context=%h",lease_count+1,cycles,context_digest);$fflush();
            end
            if(step_valid && step_ready)step_count<=step_count+1;
            if(token_valid && token_ready)token_count<=token_count+1;
            if(runtime_enabled)ever_enabled<=1;
            if(scenario==0 && ever_enabled && !runtime_enabled)renewal_reset_seen<=1;
            if(expired)expired_seen<=1;
            if(expired_seen && (token_valid || mem_req_valid))$fatal(1,"new public reply or memory work after expiry");
            if(fault && !(scenario==1 && (expired_seen || expired)))begin
                $display("FAULT boot=%0d scan=%0d cipher=%0d admission=%0d context=%0d home=%0d guard=%0d core=%0d",
                    boot_locked,dut.scan_fault,dut.cipher_fault,dut.admission_fault,dut.context_fault,dut.home_failed,dut.guard_failed,dut.core_fault);
                $fatal(1,"unexpected combined fault");
            end
            if(cycles%10000000==0)begin $display("PROGRESS cycles=%0d boot=%0d lease=%0d steps=%0d tokens=%0d",cycles,boot_locked,lease_count,step_count,token_count);$fflush();end
            if(cycles>300000000)$fatal(1,"bounded first-checkpoint protocol did not finish");
        end
    end
    task boot_a;
        begin
            path={fixtures,"/A.frame.hex"};$readmemh(path,manifest);
            path={fixtures,"/A.cipher.memh"};$readmemh(path,memory,0,IMAGE_WORDS-1);
            for(integer i=0;i<FRAME_BYTES;i=i+1)begin
                @(negedge clk);manifest_valid=1;manifest_byte=manifest[i];manifest_last=i==FRAME_BYTES-1;
                while(!manifest_ready)@(negedge clk);
                @(posedge clk);
            end
            @(negedge clk);manifest_valid=0;manifest_last=0;
            for(integer i=0;i<IMAGE_WORDS;i=i+1)begin
                @(negedge clk);cipher_valid=1;cipher_word=memory[i];
                while(!cipher_ready)@(negedge clk);
                @(posedge clk);
            end
            @(negedge clk);cipher_valid=0;
            wait(boot_locked);
            if(model!==MODEL_A)$fatal(1,"boot root differs from signed model A");
            $display("BOOT_A real_manifest=1 real_AES_CTR=1 full_image=1 all_signed_pages=1 fixed_LUTs=1 norms=1 cycles=%0d",cycles);$fflush();
        end
    endtask
    task home_turn(input integer turn);
        reg [7:0] expected[0:127];reg [7:0] grant[0:1419];string suffix;
        begin
            wait(boot_locked && nonce_request);
            @(negedge clk);nonce=turn==0 ? CHALLENGE_1 : CHALLENGE_2;nonce_valid=1;
            @(posedge clk);@(negedge clk);nonce_valid=0;
            suffix=turn==0 ? "A-e1-n1" : "A-e1-n2";
            path={fixtures,"/",suffix,".request.hex"};$readmemh(path,expected);
            path={fixtures,"/",suffix,".grant.hex"};$readmemh(path,grant);
            request_ready=1;
            for(integer i=0;i<128;i=i+1)begin
                while(!request_valid)@(negedge clk);
                if(request_byte!==expected[i] || request_last!==(i==127))$fatal(1,"request/context mismatch byte=%0d got=%x expected=%x",i,request_byte,expected[i]);
                @(posedge clk);@(negedge clk);
            end
            request_ready=0;
            for(integer i=0;i<1420;i=i+1)begin
                grant_valid=1;grant_byte=grant[i];grant_last=i==1419;
                while(!grant_ready)@(negedge clk);
                @(posedge clk);@(negedge clk);
            end
            grant_valid=0;grant_last=0;
            $display("HOME signed response supplied turn=%0d cycles=%0d",turn+1,cycles);$fflush();
        end
    endtask
    initial begin
        wait(power_reset_n && session_reset_n);
        home_turn(0);
        if(scenario==0)home_turn(1);
    end
    task append_one;
        begin
            @(negedge clk);append_valid=1;append_token=1;
            while(!append_ready)@(negedge clk);
            @(posedge clk);@(negedge clk);append_valid=0;
        end
    endtask
    task issue_step;
        begin
            @(negedge clk);step_valid=1;
            while(!step_ready)@(negedge clk);
            @(posedge clk);@(negedge clk);step_valid=0;
        end
    endtask
    task expect_token(input integer expected);
        begin
            while(!token_valid)@(negedge clk);
            if(token!==12'(expected))$fatal(1,"full-model token mismatch got=%0d expected=%0d",token,expected);
            $display("NUMERICAL_TOKEN token=%0d cycles=%0d",token,cycles);$fflush();
            @(posedge clk);@(negedge clk);
        end
    endtask
    initial begin
        if(!$value$plusargs("FIXTURES=%s",fixtures))$fatal(1,"FIXTURES missing");
        if(!$value$plusargs("SCENARIO=%d",scenario))scenario=0;
        if(scenario!=0 && scenario!=1)$fatal(1,"first checkpoint supports only A positive/expiry");
        repeat(5)@(negedge clk);power_reset_n=1;session_reset_n=1;
        boot_a();wait(runtime_enabled);repeat(10)@(negedge clk);
        append_one();
        if(scenario==0)begin
            issue_step();expect_token(108);
            wait(lease_count>=2);repeat(10)@(negedge clk);
            issue_step();expect_token(32);
            if(renewal_reset_seen || lease_count!=2 || step_count!=2 || token_count!=2 || write_count!=240 || read_count==0)
                $fatal(1,"renewal/context/write census mismatch resets=%0d leases=%0d steps=%0d tokens=%0d cipher_writes=%0d",renewal_reset_seen,lease_count,step_count,token_count,write_count);
            $display("PASS_COMBINED_A_RENEWAL tokens=108,32 native_six_layers=1 real_signed_boot=1 encrypted_weight_reads=1 encrypted_authenticated_KV=1 cipher_writes=240 leases=2 context_reset=0");$finish;
        end else begin
            hold_returns=1;issue_step();
            wait(qcount>0);repeat(20)@(negedge clk);
            if(step_count!=1 || token_count!=0 || !runtime_enabled)$fatal(1,"expiry target did not own an active STEP and accepted memory read");
            // Advance only the explicitly modeled private time service. No
            // force, valid-bit seed, changed model state or simulated verdict.
            time_jump=time_jump+64'd20000001;
            wait(expired);@(posedge clk);@(negedge clk);
            if(runtime_enabled || token_valid || !fault)$fatal(1,"absolute lease expiry failed to close consumer/publication");
            hold_returns=0;
            wait(qcount==0 && drained);repeat(1000)@(negedge clk);
            if(!expired_seen || token_count!=0 || dropped==0 || late_return_count==0 || runtime_enabled || token_valid || mem_req_valid)
                $fatal(1,"old return resurrected output or late-return control absent");
            $display("PASS_COMBINED_A_EXPIRY active_steps=1 public_tokens=0 actual_expiry=1 late_returns=%0d owned_drops=%0d no_DUT_force=1 modeled_monotonic_time=1",late_return_count,dropped);$finish;
        end
    end
endmodule
