`timescale 1ns/1ps
module tb_combined_extended;
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
    string fixtures,path,role_input,role_output,b_role_output;
    integer fault_mode=0,grant_bytes_sent=0,target_reads=0,affected_uses=0;
    bit monitor_stale=0,siv_fault_seen=0;
    reg [255:0] saved_role[0:4];
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
            if(expired_seen && fault_mode==3 && (token_valid || mem_req_valid))$fatal(1,"new public reply or memory work after expiry");
            if(fault && fault_mode==0)begin
                $display("FAULT boot=%0d scan=%0d cipher=%0d admission=%0d context=%0d home=%0d guard=%0d core=%0d",
                    boot_locked,dut.scan_fault,dut.cipher_fault,dut.admission_fault,dut.context_fault,dut.home_failed,dut.guard_failed,dut.core_fault);
                $fatal(1,"unexpected combined fault");
            end
            if(cycles%10000000==0)begin $display("PROGRESS cycles=%0d boot=%0d lease=%0d steps=%0d tokens=%0d",cycles,boot_locked,lease_count,step_count,token_count);$fflush();end
            if(monitor_stale)begin
                if(read_fire && mem_req_word>=227072 && mem_req_word<=227076)target_reads<=target_reads+1;
                if(dut.u_core.u_kv_cipher.u_model1.codec_fault)siv_fault_seen<=1;
                if(dut.u_core.kv_read_rsp_valid && dut.u_core.kv_read_rsp_ready && !dut.u_core.kv_read_rsp_fault &&
                   dut.u_core.u_kv_integrity.layer_q==0 && dut.u_core.u_kv_integrity.position_q==0 &&
                   dut.u_core.u_kv_integrity.head_q==0 && dut.u_core.u_kv_integrity.role_q==0)affected_uses<=affected_uses+1;
            end
            if(cycles>300000000)$fatal(1,"bounded first-checkpoint protocol did not finish");
        end
    end
    task boot_model(input string label);
        begin
            path=$sformatf("%s/%s.frame.hex",fixtures,label);$readmemh(path,manifest);
            path=$sformatf("%s/%s.cipher.memh",fixtures,label);$readmemh(path,memory,0,IMAGE_WORDS-1);
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
            if(model!==(label=="A" ? MODEL_A : MODEL_B))$fatal(1,"signed model root differs");
            $display("BOOT_MODEL label=%s model=%h real_manifest=1 real_AES_CTR=1 full_image=1 all_signed_pages=1 fixed_LUTs=1 norms=1 cycles=%0d",label,model,cycles);$fflush();
        end
    endtask
    task home_exchange(input string expected_name,input string grant_name,input bit accept_grant);
        reg [7:0] expected[0:127];reg [7:0] grant[0:1419];
        integer leases_before;
        begin
            leases_before=lease_count;
            wait(boot_locked && nonce_request);
            @(negedge clk);nonce=CHALLENGE_1;nonce_valid=1;
            @(posedge clk);@(negedge clk);nonce_valid=0;
            path={fixtures,"/",expected_name,".request.hex"};$readmemh(path,expected);
            path={fixtures,"/",grant_name,".grant.hex"};$readmemh(path,grant);
            // Common domain/device/challenge/geometry must be identical for
            // every old-grant control. Only the context root is different.
            for(integer i=0;i<128;i=i+1)
                if((i<64 || i>=96) && grant[i]!==expected[i])$fatal(1,"control changed a non-context request field");
            request_ready=1;
            for(integer i=0;i<128;i=i+1)begin
                while(!request_valid)@(negedge clk);
                if(request_byte!==expected[i] || request_last!==(i==127))$fatal(1,"new context request mismatch byte=%0d",i);
                @(posedge clk);@(negedge clk);
            end
            request_ready=0;grant_bytes_sent=0;
            for(integer i=0;i<1420;i=i+1)begin
                grant_valid=1;grant_byte=grant[i];grant_last=i==1419;
                while(!grant_ready && !fault)@(negedge clk);
                if(fault)break;
                @(posedge clk);@(negedge clk);grant_bytes_sent=grant_bytes_sent+1;
                if(fault)break;
            end
            grant_valid=0;grant_last=0;
            if(accept_grant)begin
                wait(runtime_enabled || fault);@(negedge clk);
                if(fault || lease_count!=leases_before+1)$fatal(1,"fresh signed context not authorized");
                $display("FRESH_GRANT name=%s epoch=%0d context=%h",grant_name,epoch,context_digest);$fflush();
            end else begin
                wait(fault);repeat(10)@(negedge clk);
                if(runtime_enabled || token_valid || lease_count!=leases_before || grant_bytes_sent<65 || grant_bytes_sent>96)
                    $fatal(1,"old grant did not fail specifically at the context field");
                $display("OLD_GRANT_REFUSED expected=%s supplied=%s epoch=%0d prefix_bytes=%0d context=%h",expected_name,grant_name,epoch,grant_bytes_sent,context_digest);$fflush();
            end
        end
    endtask
    task new_session(input integer next_epoch);
        begin
            if(next_epoch<=epoch)$fatal(1,"modeled persistent epoch service must advance");
            @(negedge clk);session_reset_n=0;
            append_valid=0;step_valid=0;manifest_valid=0;cipher_valid=0;nonce_valid=0;grant_valid=0;request_ready=0;
            // Ownership ledger stays outside this reset; external old reads
            // drain with no consumer before new admission can receive a lease.
            wait(drained);repeat(8)@(negedge clk);epoch=32'(next_epoch);fault_mode=0;
            @(negedge clk);session_reset_n=1;
            $display("SESSION_RESET new_epoch=%0d owned_old_reads_drained=1 time=%0d",epoch,trusted_now);$fflush();
        end
    endtask
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
        if(!$value$plusargs("SCENARIO=%d",scenario))$fatal(1,"SCENARIO missing");
        if(scenario<2 || scenario>7)$fatal(1,"unsupported extended control");
        if(scenario==3)epoch=2;
        if(scenario==6 && !$value$plusargs("A2_ROLE=%s",role_input))$fatal(1,"A2_ROLE actual parent capture required");
        if(scenario==3 && !$value$plusargs("ROLE_OUTPUT=%s",role_output))$fatal(1,"ROLE_OUTPUT required");
        if(scenario==5 && !$value$plusargs("B2_ROLE_OUTPUT=%s",b_role_output))$fatal(1,"B2_ROLE_OUTPUT required");
        repeat(5)@(negedge clk);power_reset_n=1;session_reset_n=1;
        if(scenario==4)begin
            // Independent model-only branch: same epoch1, device and nonce
            // as the accepted A branch; only admitted model/key context differs.
            boot_model("B");fault_mode=1;home_exchange("B-e1-n1","A-e1-n1",0);
            if(epoch!=1 || model!==MODEL_B || token_count!=0 || step_count!=0)$fatal(1,"model-only isolation failed");
            $display("PASS_COMBINED_MODEL_OLD_GRANT epoch=1 device_same=1 nonce_same=1 old_A_signature_valid=1 B_context_only=1 public_tokens=0");$finish;
        end
        boot_model("A");
        if(scenario==3)begin
            home_exchange("A-e2-n1","A-e2-n1",1);append_one();issue_step();expect_token(108);
            if(token_count!=1 || write_count!=120)$fatal(1,"fresh A epoch2 positive control failed");
            for(integer i=0;i<5;i=i+1)saved_role[i]=memory[227072+i];
            $writememh(role_output,saved_role);
            $display("PASS_COMBINED_RESET_FRESH_GRANT model=A epoch=2 device_same=1 nonce_same=1 oracle_token=108 real_A2_cipher_role_captured=1");$finish;
        end
        home_exchange("A-e1-n1","A-e1-n1",1);
        if(scenario==2)begin
            new_session(2);boot_model("A");fault_mode=1;home_exchange("A-e2-n1","A-e1-n1",0);
            if(model!==MODEL_A || epoch!=2 || token_count!=0 || step_count!=0)$fatal(1,"reset-only isolation failed");
            $display("PASS_COMBINED_RESET_OLD_GRANT model_same=A device_same=1 nonce_same=1 epoch=1_to_2 actual_reset=1 public_tokens=0");$finish;
        end
        append_one();
        if(scenario==7)begin
            hold_returns=1;issue_step();wait(qcount>0);repeat(20)@(negedge clk);fault_mode=3;
            if(step_count!=1 || token_count!=0 || !runtime_enabled)$fatal(1,"late-return source STEP absent");
            time_jump=time_jump+64'd20000001;wait(expired);@(posedge clk);@(negedge clk);hold_returns=0;
            wait(qcount==0 && drained);repeat(10)@(negedge clk);
            if(!expired_seen || dropped==0 || late_return_count==0 || token_count!=0)$fatal(1,"expiry source did not drain real old responses");
            new_session(2);boot_model("B");home_exchange("B-e2-n1","B-e2-n1",1);
            append_one();issue_step();expect_token(0);issue_step();expect_token(0);
            if(token_count!=2 || step_count!=3 || dropped==0)$fatal(1,"fresh B after expiry/late return mismatch");
            $display("PASS_COMBINED_AFTER_EXPIRY old_A_public_tokens=0 late_returns_drained=1 new_epoch=2 new_B_tokens=0,0 old_state_not_resurrected=1");$finish;
        end
        issue_step();expect_token(108);
        new_session(2);boot_model("B");home_exchange("B-e2-n1","B-e2-n1",1);
        append_one();issue_step();expect_token(0);
        if(scenario==5)begin
            for(integer i=0;i<5;i=i+1)saved_role[i]=memory[227072+i];
            $writememh(b_role_output,saved_role);
            issue_step();expect_token(0);
            if(token_count!=3 || step_count!=3 || write_count!=360)$fatal(1,"actual A-to-B numerical replacement census failed");
            $display("PASS_COMBINED_MODEL_REPLACEMENT actual_A_to_B=1 A_token=108 B_tokens=0,0 fresh_signed_packages=2 distinct_model_keys=1 epoch=1_to_2 cipher_writes=360");$finish;
        end else begin
            // Parent data came from a real authorized A epoch2 run. B is
            // already authorized and populated at epoch2: AD fields match,
            // so refusal isolates the different model key domain.
            $readmemh(role_input,saved_role);
            begin: replace_role
                bit different;different=0;
                for(integer i=0;i<5;i=i+1)begin
                    if(memory[227072+i]!==saved_role[i])different=1;
                    memory[227072+i]=saved_role[i];
                end
                if(!different)$fatal(1,"A2 and B2 cipher-role controls did not differ");
            end
            fault_mode=2;monitor_stale=1;issue_step();wait(fault);repeat(20)@(negedge clk);
            if(!siv_fault_seen || target_reads==0 || affected_uses!=0 || token_count!=2 || runtime_enabled)
                $fatal(1,"authentic A2 K/V was not refused before B2 target use reads=%0d uses=%0d siv=%0d",target_reads,affected_uses,siv_fault_seen);
            $display("PASS_COMBINED_CROSS_MODEL_KV A2_cipher_authentic=1 B2_authorized_populated=1 same_epoch=2 actual_target_reads=%0d real_SIV_fault=1 affected_plaintext_uses=0 new_public_tokens=0",target_reads);$finish;
        end
    end

endmodule
