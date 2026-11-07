`timescale 1ns/1ps
module tb_combined_clear;
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
    bit clear_phase=0;
    integer old_return_target=0,old_returns=0;
    reg [255:0] original_context;
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
            if(clear_phase && !runtime_enabled)$fatal(1,"CLEAR reset permission instead of clearing the consumer");
            if(clear_phase && send_return && old_returns<old_return_target)old_returns<=old_returns+1;
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

    bit monitor_clear_inflight=0;
    always @(posedge clk)begin
        if(power_reset_n)begin
            if(clear && runtime_enabled)monitor_clear_inflight<=1;
            else if(monitor_clear_inflight && !dut.u_core.busy_o && !dut.core_token_valid && !dut.core_fault &&
                    drained && !read_fire && !mem_rsp_valid)monitor_clear_inflight<=0;
            if(clear || dut.u_guard.clear_pending_q || monitor_clear_inflight)begin
                if(append_ready || step_ready || token_valid)
                    $fatal(1,"public ready/token reopened inside CLEAR/drain interval");
                if((dut.u_core.append_valid_i && dut.u_core.append_ready_o) ||
                   (dut.u_core.step_valid_i && dut.u_core.step_ready_o) ||
                   (dut.u_core.token_valid_o && dut.u_core.token_ready_i))
                    $fatal(1,"inward command/publication handshake during CLEAR drain");
            end
        end
    end
    task wait_clear_drain;
        begin
            for(integer n=0;n<300000;n=n+1)begin
                @(negedge clk);
                if(!dut.u_core.busy_o && drained && qcount==0 && !mem_rsp_valid)return;
            end
            $fatal(1,"real consumer/physical CLEAR drain did not complete");
        end
    endtask
    task clear_with_competing_commands;
        integer accepted_steps;
        begin
            accepted_steps=step_count;
            @(negedge clk);clear=1;append_valid=1;step_valid=1;token_ready=1;
            #1;
            if(append_ready || step_ready || token_valid)$fatal(1,"CLEAR lost priority to APPEND/STEP/token handshake");
            @(posedge clk);@(negedge clk);clear=0;append_valid=0;step_valid=0;
            if(step_count!=accepted_steps || token_count!=0)$fatal(1,"canceled or coincident command was accepted");
        end
    endtask
    initial begin
        if(!$value$plusargs("FIXTURES=%s",fixtures))$fatal(1,"FIXTURES missing");
        if(!$value$plusargs("SCENARIO=%d",scenario))$fatal(1,"SCENARIO missing");
        if(scenario<8 || scenario>10)$fatal(1,"unsupported CLEAR case");
        repeat(5)@(negedge clk);power_reset_n=1;session_reset_n=1;
        boot_a();wait(runtime_enabled);repeat(10)@(negedge clk);original_context=context_digest;
        // Idle CLEAR also suppresses simultaneously presented normal commands.
        clear_with_competing_commands();wait_clear_drain();
        append_one();
        if(scenario==8)begin
            hold_returns=1;issue_step();wait(qcount>0);repeat(20)@(negedge clk);
            old_return_target=qcount;
            if(old_return_target==0 || step_count!=1 || token_count!=0)$fatal(1,"active CLEAR has no real accepted STEP/read");
            clear_phase=1;
            @(negedge clk);clear=1;hold_returns=0;
            @(posedge clk);@(negedge clk);clear=0;
        end else if(scenario==9)begin
            token_ready=0;issue_step();wait(token_valid);@(negedge clk);
            if(token!==12'd108 || token_count!=0)$fatal(1,"held candidate control absent");
            clear_phase=1;clear_with_competing_commands();
        end else begin : blocked_write
            reg [18:0] blocked_word;reg [255:0] blocked_data;
            issue_step();wait(write_count>0);@(negedge clk);mem_req_ready=0;
            wait(mem_req_valid && mem_req_write);@(negedge clk);
            blocked_word=mem_req_word;blocked_data=mem_req_data;clear_phase=1;
            clear_with_competing_commands();
            repeat(10)begin
                @(negedge clk);
                if(!mem_req_valid || !mem_req_write || mem_req_word!==blocked_word || mem_req_data!==blocked_data)
                    $fatal(1,"CLEAR lost an already offered owned write");
                if(!dut.u_guard.clear_pending_q || append_ready || step_ready || token_valid)
                    $fatal(1,"CLEAR completed while its offered write was blocked");
            end
            mem_req_ready=1;
        end
        wait_clear_drain();repeat(10)@(negedge clk);
        if(scenario==8 && (old_returns!=old_return_target || old_returns==0))$fatal(1,"old accepted reads did not actually return during CLEAR drain");
        if(!runtime_enabled || context_digest!==original_context || lease_count!=1 || token_count!=0 || fault)
            $fatal(1,"CLEAR changed valid authorization or published canceled work");
        $display("CLEAR_DRAIN_COMPLETE scenario=%0d old_return_target=%0d old_returns=%0d physical_drained=%0d consumer_busy=%0d cycles=%0d",scenario,old_return_target,old_returns,drained,dut.u_core.busy_o,cycles);$fflush();
        append_one();wait(dut.core_step_ready);repeat(3)@(negedge clk);
        if(dut.u_guard.clear_pending_q || monitor_clear_inflight || dut.u_guard.step_owned_q || !step_ready)$fatal(1,"CLEAR did not release STEP ownership after normal drain");
        issue_step();expect_token(108);
        if(step_count!=2 || token_count!=1 || !runtime_enabled || context_digest!==original_context || fault)
            $fatal(1,"fresh post-CLEAR STEP/oracle/session mismatch");
        if(scenario==8)$display("PASS_COMBINED_CLEAR_ACTIVE old_STEP_canceled=1 old_reads_returned=%0d fresh_oracle_token=108 same_live_lease=1 no_canceled_public_token=1",old_returns);
        else if(scenario==9)$display("PASS_COMBINED_CLEAR_HELD_TOKEN CLEAR_beats_token_APPEND_STEP=1 held_candidate_canceled=1 fresh_oracle_token=108 same_live_lease=1");
        else $display("PASS_COMBINED_CLEAR_WRITE_DRAIN offered_write_stable_until_accepted=1 old_work_drained=1 fresh_oracle_token=108 same_live_lease=1");
        $finish;
    end
endmodule
