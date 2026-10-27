`timescale 1ns/1ps
`default_nettype none
module tb_hwic_simplestories;
    logic clk=0; always #5 clk=~clk;
    logic reset_n=0,clear_i=0,append_valid_i=0,step_valid_i=0,token_ready_i=0;
    logic [11:0] append_token_i=0;
    wire append_ready_o,step_ready_o,token_valid_o,busy_o,model_locked_o,fail_closed_o;
    wire [11:0] token_o;
    hwic_simplestories dut(.*);
    `define D dut.u_core.u_six_layers.u_datapath
    `define S dut.u_core.u_token_shell
    integer trace_file,scan_status,trace_count=0,epoch=0;
    bit trace_on=0;
    logic [127:0] expected_record;
    longint cycles=0;
    logic [31:0] config_words [0:4095];
    integer prompt_count,output_count,replay_count,expected_count;
    integer i;
    // Independent verification storage, excluded from the synthesized top.
    // Payload is never assumed zero: a read must follow an accepted write.
    bit kv_ever_written [0:221183];
    logic [255:0] kv_shadow_payload [0:221183];
    logic [255:0] kv_expected_response;
    logic kv_shadow_pending=0;
    longint kv_reads_checked=0,kv_writes_checked=0;
    always @(posedge clk)begin
        if(!reset_n)begin
            kv_shadow_pending<=0;kv_reads_checked<=0;kv_writes_checked<=0;
            for(integer shadow_index=0;shadow_index<221184;shadow_index=shadow_index+1)
                kv_ever_written[shadow_index]=0;
        end else begin
            if(dut.kv_rsp_valid && dut.kv_rsp_ready)begin
                if(!kv_shadow_pending || dut.kv_rsp_data!==kv_expected_response)
                    $fatal(1,"PRIVATE_CACHE_RESPONSE_MISMATCH pending=%b",kv_shadow_pending);
                kv_shadow_pending<=0;kv_reads_checked<=kv_reads_checked+1;
            end
            if(dut.kv_req_valid && dut.kv_req_ready &&
               dut.kv_req_word>=227072 && dut.kv_req_word<448256)begin
                if(dut.kv_req_write)begin
                    kv_shadow_payload[dut.kv_req_word-227072]<=dut.kv_req_data;
                    kv_ever_written[dut.kv_req_word-227072]=1;
                    kv_writes_checked<=kv_writes_checked+1;
                end else begin
                    if(!kv_ever_written[dut.kv_req_word-227072])
                        $fatal(1,"PRIVATE_CACHE_UNWRITTEN_READ word=%0d",dut.kv_req_word);
                    if(kv_shadow_pending && !(dut.kv_rsp_valid && dut.kv_rsp_ready))
                        $fatal(1,"PRIVATE_CACHE_RESPONSE_OWNERSHIP_OVERLAP");
                    kv_expected_response<=kv_shadow_payload[dut.kv_req_word-227072];
                    kv_shadow_pending<=1;
                end
            end
        end
    end
    task automatic observe(input integer pos,layer,stage,index,
                           input logic signed [63:0] value,
                           input logic signed [7:0] exponent);
        logic [127:0] actual;
        begin
            if(trace_on && (config_words[6]!=0 ?
                config_words[3072+(pos>>5)][pos&31] :
                (config_words[4]==0 || pos==config_words[4]-1))) begin
                actual={8'(epoch),16'(pos),8'(layer),8'(stage),16'(index),exponent,value};
                scan_status=$fscanf(trace_file,"%h\n",expected_record);
                if(scan_status!=1 || actual!==expected_record)
                    $fatal(1,"TENSOR_MISMATCH ordinal=%0d pos=%0d layer=%0d stage=%0d index=%0d actual=%h expected=%h read=%0d",trace_count,pos,layer,stage,index,actual,expected_record,scan_status);
                trace_count=trace_count+1;
            end
        end
    endtask
    always @(posedge clk) begin
        if(reset_n) begin
            cycles<=cycles+1;
            if(cycles>64'd1_000_000_000_000) $fatal(1,"WATCHDOG");
            if(cycles!=0 && cycles%10_000_000==0)begin
                $display("HWIC_PROGRESS cycles=%0d replay_position=%0d layer=%0d stage=%0d tensors=%0d",cycles,`S.replay_position_q,`D.current_layer_q,`D.current_stage_q,trace_count);
                $fflush();
            end
            if(trace_on && fail_closed_o) $fatal(1,"UNEXPECTED_HWIC_FAULT cycles=%0d",cycles);
            if(`S.embed_result_transfer)
                observe(`S.replay_position_q,7,17,`S.embed_result_index,
                    {{48{`S.embed_result_mantissa[15]}},`S.embed_result_mantissa},`S.embed_result_exponent);
            if(`D.rms_result_fire)
                observe(`D.current_position_q,`D.current_layer_q,`D.current_stage_q,`D.rms_result_index,
                    {{48{`D.rms_result_mantissa[15]}},`D.rms_result_mantissa},`D.rms_result_exponent);
            if(`D.norm_result_fire)
                observe(`D.current_position_q,`D.current_layer_q,`D.current_stage_q,`D.norm_result_index,
                    {{48{`D.norm_result_mantissa[15]}},`D.norm_result_mantissa},`D.norm_result_exponent);
            if(`D.attention_ram_write_enable)
                observe(`D.current_position_q,`D.current_layer_q,7,`D.attention_ram_write_address,
                    {{48{`D.attention_ram_write_data[15]}},`D.attention_ram_write_data},`D.attention_result_exponent);
            if(`S.rms_result_valid && `S.rms_result_ready)
                observe(`S.replay_position_q,7,18,`S.rms_result_index,
                    {{48{`S.rms_result_mantissa[15]}},`S.rms_result_mantissa},`S.rms_result_exponent);
            if(dut.u_core.head_result_valid && dut.u_core.head_result_ready)
                observe(`S.replay_position_q,7,19,dut.u_core.head_result_row_index,
                    {{14{dut.u_core.head_result_scaled_raw[49]}},dut.u_core.head_result_scaled_raw},dut.u_core.head_result_source_exponent);
        end
    end
    task automatic append_token(input logic [11:0] token);
        begin
            @(negedge clk);while(!append_ready_o) begin
                if(fail_closed_o)$fatal(1,"append fault");@(negedge clk);
            end
            append_token_i=token;append_valid_i=1;
            @(negedge clk);append_valid_i=0;
        end
    endtask
    task automatic launch_step;
        begin
            @(negedge clk);while(!step_ready_o) begin
                if(fail_closed_o)$fatal(1,"step fault");@(negedge clk);
            end
            step_valid_i=1;@(negedge clk);step_valid_i=0;
        end
    endtask
    task automatic accept_token(input logic [11:0] expected);
        logic [11:0] held;
        begin
            while(!token_valid_o) begin
                if(fail_closed_o)$fatal(1,"inference fault");@(negedge clk);
            end
            held=token_o;
            if(held!==expected)$fatal(1,"TOKEN_MISMATCH actual=%0d expected=%0d",held,expected);
            repeat(7)begin
                @(negedge clk);
                if(!token_valid_o || token_o!==held)$fatal(1,"held token changed");
            end
            token_ready_i=1;@(negedge clk);token_ready_i=0;
            profile_dump();
            $display("HWIC_TOKEN epoch=%0d token=%0d cycles=%0d tensors=%0d",epoch,expected,cycles,trace_count);
        end
    endtask
    task automatic clear_tape;
        begin
            // Callers are already on a falling edge. Assert now so a CLEAR
            // can coincide with the next owned memory-response edge.
            clear_i=1;
            repeat(4)begin
                @(negedge clk);
                if(append_ready_o || step_ready_o || token_valid_o)$fatal(1,"public activity during CLEAR");
            end
            clear_i=0;
            while(!append_ready_o)begin
                if(fail_closed_o)$fatal(1,"CLEAR caused fault");@(negedge clk);
            end
            if(`S.tape_count_q!=0 || dut.u_core.layer_committed_prefixes!=0)
                $fatal(1,"CLEAR did not revoke tape/cache");
        end
    endtask

    // Observation-only counters; excluded from sealed synthesized top.
    `define P `D.u_projection
    `define G `P.u_group_stream
    longint profile_engine[0:15];
    longint profile_stage[0:31];
    longint profile_stream[0:7];
    longint profile_job[0:7];
    longint profile_rms[0:31];
    longint profile_norm[0:15];
    longint profile_rms_norm[0:15];
    longint profile_div_requests=0;
    longint profile_rom_requests=0,profile_rom_blocked=0,profile_rom_response_stall=0;
    longint profile_weight_accept=0,profile_weight_starved=0,profile_weight_stall=0;
    initial begin
        foreach(profile_engine[n])profile_engine[n]=0;
        foreach(profile_stage[n])profile_stage[n]=0;
        foreach(profile_stream[n])profile_stream[n]=0;
        foreach(profile_job[n])profile_job[n]=0;
        foreach(profile_rms[n])profile_rms[n]=0;
        foreach(profile_norm[n])profile_norm[n]=0;
        foreach(profile_rms_norm[n])profile_rms_norm[n]=0;
    end
    always @(posedge clk)if(reset_n)begin
        profile_engine[`D.engine_state_q]++;
        if(`D.engine_state_q!=0)
            profile_stage[`D.engine_state_q==8 ? 31 : `D.current_stage_q]++;
        profile_stream[`G.state_q]++; profile_job[`P.state_q]++;
        profile_rms[`D.u_rmsnorm.state_q]++;
        profile_norm[`D.u_normalizer.state_q]++;
        profile_rms_norm[`D.u_rmsnorm.u_frozen_vector_normalizer.state_q]++;
        if(`D.u_rmsnorm.div_request_valid && `D.u_rmsnorm.div_request_ready)profile_div_requests++;
        if(dut.private_runtime_req_valid_o && dut.private_runtime_req_ready_i)profile_rom_requests++;
        if(dut.private_runtime_req_valid_o && !dut.private_runtime_req_ready_i)profile_rom_blocked++;
        if(dut.private_runtime_rsp_valid_i && !dut.private_runtime_rsp_ready_o)profile_rom_response_stall++;
        if(`G.weight_valid_o && `G.weight_ready_i)profile_weight_accept++;
        if(`G.state_q==4 && !`G.weight_valid_o && `G.weight_ready_i)profile_weight_starved++;
        if(`G.weight_valid_o && !`G.weight_ready_i)profile_weight_stall++;
    end
    task automatic profile_dump;
        foreach(profile_engine[n])$display("PROFILE_ENGINE id=%0d cycles=%0d",n,profile_engine[n]);
        foreach(profile_stage[n])$display("PROFILE_STAGE id=%0d cycles=%0d",n,profile_stage[n]);
        foreach(profile_stream[n])$display("PROFILE_STREAM id=%0d cycles=%0d",n,profile_stream[n]);
        foreach(profile_job[n])$display("PROFILE_JOB id=%0d cycles=%0d",n,profile_job[n]);
        foreach(profile_rms[n])$display("PROFILE_RMS id=%0d cycles=%0d",n,profile_rms[n]);
        foreach(profile_norm[n])$display("PROFILE_NORM id=%0d cycles=%0d",n,profile_norm[n]);
        foreach(profile_rms_norm[n])$display("PROFILE_RMS_NORM id=%0d cycles=%0d",n,profile_rms_norm[n]);
        $display("PROFILE_DIV requests=%0d",profile_div_requests);
        $display("PROFILE_MEMORY requests=%0d request_blocked=%0d response_stall=%0d weight_accept=%0d weight_starved=%0d weight_stall=%0d",profile_rom_requests,profile_rom_blocked,profile_rom_response_stall,profile_weight_accept,profile_weight_starved,profile_weight_stall);
    endtask

    initial begin
        $readmemh("case.memh",config_words);
        prompt_count=config_words[0];output_count=config_words[1];
        replay_count=config_words[2];expected_count=config_words[3];
        trace_file=$fopen("expected.memh","r");
        if(!trace_file)$fatal(1,"missing independent tensor expectations");
        repeat(8)@(negedge clk);reset_n=1;
        while(!append_ready_o)@(negedge clk);
        if($test$plusargs("EXPECT_FAULT"))begin
            append_token(378);launch_step();
            while(!fail_closed_o)begin
                if(token_valid_o)$fatal(1,"token before expected fault");@(negedge clk);
            end
            repeat(32)@(negedge clk);
            clear_i=1;repeat(4)@(negedge clk);clear_i=0;
            repeat(32)begin
                @(negedge clk);
                if(!fail_closed_o || append_ready_o || step_ready_o || token_valid_o)
                    $fatal(1,"terminal fault reopened");
            end
            $display("PASS_HWIC_FAULT terminal_until_reset=1 cycles=%0d",cycles);$finish;
        end else begin
            if($test$plusargs("CANCEL_HELD"))begin
                append_token(378);launch_step();
                while(!token_valid_o)begin
                    if(fail_closed_o)$fatal(1,"held-result setup fault");@(negedge clk);
                end
                repeat(32)begin
                    @(negedge clk);
                    if(!token_valid_o || token_o!==12'(config_words[1024]))
                        $fatal(1,"unconsumed token changed");
                end
                clear_tape();
                repeat(64)begin
                    @(negedge clk);
                    if(token_valid_o || step_ready_o || busy_o || fail_closed_o)
                        $fatal(1,"held token survived CLEAR or empty STEP opened");
                end
                step_valid_i=1;repeat(4)@(negedge clk);step_valid_i=0;
                repeat(16)begin
                    @(negedge clk);
                    if(token_valid_o || busy_o || fail_closed_o)
                        $fatal(1,"unaccepted empty STEP produced work");
                end
                $display("HWIC_HELD_CLEAR held_cycles=32 stale_token_suppressed=1 empty_step_work=0");
            end
            if($test$plusargs("ADMISSION"))begin
                if(step_ready_o)$fatal(1,"STEP opened on empty tape");
                for(i=0;i<2048;i=i+1)append_token(378);
                @(negedge clk);append_token_i=378;append_valid_i=1;
                repeat(16)begin
                    @(negedge clk);
                    if(append_ready_o || `S.tape_count_q!=2048 || fail_closed_o)
                        $fatal(1,"context2048 admission bound");
                end
                append_valid_i=0;launch_step();
                while(!(dut.private_runtime_rsp_valid_i && dut.private_runtime_rsp_ready_o))@(negedge clk);
                clear_tape();
                $display("HWIC_ADMISSION positions=2048 overlimit_rejected=1 active_clear=1 numerical_full_window=0");
            end
            if($test$plusargs("CANCEL_MODEL") || $test$plusargs("CANCEL_KV"))begin
                append_token(378);launch_step();
                if($test$plusargs("CANCEL_MODEL"))begin
                    while(!(dut.private_runtime_rsp_valid_i && dut.private_runtime_rsp_ready_o))@(negedge clk);
                end else begin
                    while(!(dut.kv_req_valid && dut.kv_req_ready && dut.kv_req_write))@(negedge clk);
                end
                clear_tape();
                repeat(64)begin @(negedge clk);if(token_valid_o)$fatal(1,"cancelled token escaped");end
                $display("HWIC_CANCEL drained=1 public_tokens=0 cycles=%0d",cycles);
            end
            trace_on=1;
            for(i=0;i<prompt_count;i=i+1)append_token(config_words[5]!=0 ? 12'd378 : 12'(config_words[16+i]));
            for(i=0;i<output_count;i=i+1)begin launch_step();accept_token(12'(config_words[1024+i]));end
            if(config_words[4]!=0 || config_words[6]!=0)begin
                if(`S.tape_count_q!=prompt_count+output_count ||
                   dut.u_core.layer_committed_prefixes!=={6{12'(prompt_count)}})
                    $fatal(1,"LONG_CONTEXT_COMMIT_COUNT");
                $display("HWIC_CONTEXT_COMPLETED numerical_inputs=%0d output_slot=%0d all_six_prefixes=%0d",prompt_count,prompt_count,prompt_count);
            end
            trace_on=0;clear_tape();epoch=1;trace_on=1;
            for(i=0;i<prompt_count;i=i+1)append_token(config_words[5]!=0 ? 12'd378 : 12'(config_words[16+i]));
            for(i=0;i<replay_count;i=i+1)begin launch_step();accept_token(12'(config_words[2048+i]));end
            trace_on=0;
            repeat(32)@(negedge clk);
            if(trace_count!=expected_count || fail_closed_o || busy_o || kv_shadow_pending)
                $fatal(1,"final count/drain expected=%0d actual=%0d busy=%b fault=%b",expected_count,trace_count,busy_o,fail_closed_o);
            scan_status=$fscanf(trace_file,"%h\n",expected_record);
            if(scan_status!=-1 && scan_status!=0)$fatal(1,"extra expected tensor record");
            $display("PASS_HWIC_MODEL main_tokens=%0d replay_tokens=%0d tensor_values=%0d cycles=%0d sealed_model_rom=1 private_kv=1 cache_reads_checked=%0d cache_writes_checked=%0d",output_count,replay_count,trace_count,cycles,kv_reads_checked,kv_writes_checked);
            $finish;
        end
    end
endmodule
`default_nettype wire
