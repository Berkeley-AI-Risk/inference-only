"""Exercise both full native K/V staging architectures across logical CLEAR."""
import argparse
import json
from pathlib import Path
import subprocess
import time

from run_attention_ownership import HERE, load
from record_progress import sha
from run_kv_session_drain import TOP


def bench(ports,baseline):
    declarations=[];initials=[]
    for name,(direction,shape)in ports.items():
        declarations.append(('reg 'if direction=='input'else'wire ')+shape+name+';')
        if direction=='input':initials.append(name+'=0;')
    memories='\n'.join('        for(integer a=0;a<'+str(32 if baseline else 8)+';a=a+1) dut.'+
        ('g_pair_bank['+str(i)+'].words'if baseline else'g_stage_memory['+str(i)+'].memory')+
        "[a]=32'hdeadbeef ^ "+str(i*256)+' ^ a;'for i in range(8 if baseline else 16))
    observed='dut.'+('g_pair_bank[0].words[8]'if baseline else'g_stage_memory[0].memory[0]')
    text='module test;\n'+'\n'.join(declarations)+'\n'+TOP+' dut('+','.join('.'+n+'('+n+')'for n in ports)+');\n'
    text+='''
    integer ticks=0,tag=0,position=0,requests=0,completions=0,total_writes=0,total_reads=0;
    integer rd_count=0,rd_head=0,rd_tail=0;
    reg [255:0] backend[0:1][0:1][0:8];
    reg [255:0] read_queue[0:15];
    reg pending_write=0;
    reg [255:0] expected_word;
    reg [31:0] old_pair;
    function automatic [15:0] key(input integer t,input integer c);key=t*257+c*3-300;endfunction
    function automatic [15:0] value(input integer t,input integer c);value=-(t*193+c*5+11);endfunction
    function automatic [7:0] kexp(input integer t,input integer h);kexp=t+h;endfunction
    function automatic [7:0] vexp(input integer t,input integer h);vexp=-t-h;endfunction
    always #5 clk=~clk;
    always @(negedge clk)begin
        ticks=ticks+1;
        kv_write_req_ready_i=(ticks%3)!=0;
        kv_write_cpl_valid_i=pending_write && (ticks%4)!=0;
        kv_read_req_ready_i=(ticks%3)!=1 && rd_count<8;
        kv_read_rsp_valid_i=rd_count!=0 && (ticks%4)!=0;
        kv_read_rsp_data_i=rd_count!=0 ? read_queue[rd_head] : 256'd0;
        #1;
        if(reset_n && fail_closed_o)$fatal(1,"native fault at tick %0d state %0d",ticks,dut.state_q);
        if(ticks>4000)$fatal(1,"simulation watchdog");
    end
    always @(posedge clk)if(reset_n)begin
        if(kv_write_req_valid_o && kv_write_req_ready_i)begin
            if(pending_write)$fatal(1,"overlapping native writes");
            expected_word=0;
            if(kv_write_req_layer_o!=0 || kv_write_req_position_o!=position ||
               kv_write_req_head_o!=requests/9 || kv_write_req_row_word_o!=requests%9)
                $fatal(1,"unexpected typed write descriptor");
            if(BASELINE)begin
                if(requests%9==8)expected_word[15:0]=(requests/9==0) ?
                    {kexp(tag,1),kexp(tag,0)} : {vexp(tag,1),vexp(tag,0)};
                else for(integer j=0;j<16;j=j+1)expected_word[j*16 +:16]=(requests/9==0) ?
                    key(tag,(requests%9)*16+j) : value(tag,(requests%9)*16+j);
            end else begin
                if(requests%9==8)expected_word[15:0]={vexp(tag,requests/9),kexp(tag,requests/9)};
                else for(integer j=0;j<16;j=j+1)expected_word[j*16 +:16]=(requests%9<4) ?
                    key(tag,(requests/9)*64+(requests%9)*16+j) :
                    value(tag,(requests/9)*64+((requests%9)-4)*16+j);
            end
            if(kv_write_req_data_o!==expected_word)$fatal(1,"stale/wrong typed write tag %0d index %0d",tag,requests);
            backend[kv_write_req_head_o][kv_write_req_position_o][kv_write_req_row_word_o]=kv_write_req_data_o;
            total_writes=total_writes+1;
            pending_write<=1;requests=requests+1;
        end
        if(kv_write_cpl_valid_i && kv_write_cpl_ready_o)begin
            if(!pending_write)$fatal(1,"unowned completion");
            pending_write<=0;completions=completions+1;
        end
        if(kv_read_req_valid_o && kv_read_req_ready_i)begin
            if(kv_read_req_layer_o!=0 || kv_read_req_position_o!=0 || kv_read_req_head_o>1 || kv_read_req_row_word_o>8)
                $fatal(1,"unexpected committed read descriptor");
            read_queue[rd_tail]=backend[kv_read_req_head_o][kv_read_req_position_o][kv_read_req_row_word_o];
            rd_tail=(rd_tail+1)%16;rd_count=rd_count+1;total_reads=total_reads+1;
        end
        if(kv_read_rsp_valid_i && kv_read_rsp_ready_o)begin
            if(rd_count==0)$fatal(1,"unowned read response");
            rd_head=(rd_head+1)%16;rd_count=rd_count-1;
        end
    end
    task automatic stage(input integer t,input integer p);
        begin
            @(negedge clk);#2;tag=t;position=p;requests=0;completions=0;stage_position_i=p;
            stage_key_exponents_i={kexp(t,1),kexp(t,0)};
            stage_value_exponents_i={vexp(t,1),vexp(t,0)};
            stage_begin_valid_i=1;
            do @(posedge clk);while(!stage_begin_ready_o);
            @(negedge clk);#2;stage_begin_valid_i=0;
            for(integer c=0;c<128;c=c+1)begin
                @(negedge clk);#2;stage_payload_valid_i=1;stage_coordinate_i=c;
                stage_key_i=key(t,c);stage_value_i=value(t,c);stage_last_i=c==127;
                do @(posedge clk);while(!stage_payload_ready_o);
                @(negedge clk);#2;stage_payload_valid_i=0;
            end
            while(!pending_complete_o)begin @(negedge clk);#2;end
            if(requests!=18 || completions!=18)$fatal(1,"incomplete typed persistence");
        end
    endtask
    task automatic attention_read(input integer h,input integer kind,input integer t,input integer p,input integer is_pending);
        begin
            @(negedge clk);#2;attention_kv_head_i=h;attention_position_i=p;attention_req_kind_i=kind;attention_req_valid_i=1;
            do @(posedge clk);while(!attention_req_ready_o);
            @(negedge clk);#2;attention_req_valid_i=0;
            while(!attention_rsp_valid_o)begin @(negedge clk);#2;end
            if(attention_rsp_fault_o || attention_rsp_from_pending_o!=is_pending || attention_rsp_kind_o!=kind)
                $fatal(1,"bad attention response ownership");
            for(integer j=0;j<64;j=j+1)begin
                if(attention_rsp_key_vector_o[j*16 +:16]!==((kind==2)?16'd0:key(t,h*64+j)))
                    $fatal(1,"stale/wrong attention key tag %0d head %0d dim %0d",t,h,j);
                if(attention_rsp_value_vector_o[j*16 +:16]!==((kind==1)?16'd0:value(t,h*64+j)))
                    $fatal(1,"stale/wrong attention value tag %0d head %0d dim %0d",t,h,j);
            end
            if(attention_rsp_key_exponent_o!==((kind==2)?8'd0:kexp(t,h)) ||
               attention_rsp_value_exponent_o!==((kind==1)?8'd0:vexp(t,h)))$fatal(1,"stale/wrong exponent");
            @(negedge clk);#2;attention_rsp_ready_i=1;
            @(posedge clk);@(negedge clk);#2;attention_rsp_ready_i=0;
        end
    endtask
    task automatic commit_current;
        begin
            @(negedge clk);#2;commit_position_i=position;commit_valid_i=1;
            do @(posedge clk);while(!commit_ready_o);
            @(negedge clk);#2;commit_valid_i=0;
        end
    endtask
    task automatic check_session(input integer t);
        integer prior_reads;
        begin
            stage(t,0);
            for(integer h=0;h<2;h=h+1)for(integer k=0;k<3;k=k+1)attention_read(h,k,t,0,1);
            commit_current;
            stage(t+2,1);
            for(integer h=0;h<2;h=h+1)for(integer k=0;k<3;k=k+1)attention_read(h,k,t+2,1,1);
            for(integer k=1;k<3;k=k+1)begin
                attention_read(0,k,t,0,0);
                prior_reads=total_reads;
                attention_read(1,k,t,0,0);
                if(BASELINE && total_reads!=prior_reads)$fatal(1,"missing shared kind-row cache hit");
            end
            attention_read(0,0,t,0,0);attention_read(1,0,t,0,0);
            if(rd_count!=0 || pending_write)$fatal(1,"unfinished memory ownership at session end");
        end
    endtask
    initial begin
INITIALS
MEMORIES
        model_locked_i=1;
        repeat(2)@(posedge clk);
        @(negedge clk);#2;reset_n=1;clear_i=1;
        repeat(2)@(posedge clk);
        @(negedge clk);#2;clear_i=0;
        check_session(1);
        old_pair=OBSERVED;
        @(negedge clk);#2;clear_i=1;
        repeat(2)@(posedge clk);
        @(negedge clk);#2;clear_i=0;
        if(OBSERVED!==old_pair)$fatal(1,"CLEAR physically erased/changed payload unexpectedly");
        if(pending_complete_o || committed_prefixes_o!=0)$fatal(1,"old authority survived CLEAR");
        check_session(2);
        if(total_writes!=72 || total_reads==0)$fatal(1,"missing full session exercise");
        $display("PASS full native staging: two sessions, four 128-coordinate stages, 72 typed writes, 24 pending and 12 committed responses; payload retained across CLEAR; reads=%0d cycles=%0d",total_reads,ticks);
        $finish;
    end
    endmodule
'''
    return text.replace('BASELINE',"1'b1"if baseline else"1'b0").replace('INITIALS','\n'.join(initials)).replace('MEMORIES',memories).replace('OBSERVED',observed)


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--out',type=Path,required=True)
    args=ap.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    builder=load('addresses',HERE.parent/'authentication-access/run_model_addresses.py');builder.ROOTS['kv-cache']=TOP
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    results={};start=time.monotonic()
    for variant in ('baseline','kv-protected'):
        case=out/variant;case.mkdir();files,binding,_,_=builder.derive(HERE.parents[1]/'fpga-demo/public-release',variant,'kv-cache')
        selected={n+'.sv':files['production-'+n+'.sv']for n in binding['isolated_native_modules']}
        selected['test.sv']=bench(parser.ports(selected[TOP+'.sv'].decode()),variant=='baseline').encode()
        for n,raw in selected.items():(case/n).write_bytes(raw)
        commands=[['iverilog','-g2012','-D','SYNTHESIS','-s','test','-o','sim']+sorted(selected),['vvp','sim']]
        rows=[]
        for i,command in enumerate(commands):
            cp=subprocess.run(command,cwd=case,capture_output=True,text=True,timeout=30)
            raw=(cp.stdout+cp.stderr).encode();log=case/('compile.log'if i==0 else'sim.log');log.write_bytes(raw)
            rows.append(dict(command=command,exit=cp.returncode,log_sha256=sha(raw)))
            if cp.returncode:break
        passed=len(rows)==2 and all(r['exit']==0 for r in rows)and'PASS full native staging:'in(case/'sim.log').read_text()
        results[variant]=dict(passed=passed,binding=binding,commands=rows,
            files={n:dict(bytes=len(raw),sha256=sha(raw))for n,raw in selected.items()})
        print(variant,passed,flush=True)
    (out/'runner.py').write_bytes(Path(__file__).read_bytes())
    result=dict(passed=all(r['passed']for r in results.values()),cases=results,seconds=time.monotonic()-start,
        runner_sha256=sha(Path(__file__).read_bytes()),physical_boot_reset_used=True,reset_between_epochs=False,
        source_bound_behavioral_simulation_only=True,whole_device_session_theorem=False,
        scope='Full native controller/RAM/mapper bodies; poisoned old RAM payloads, two sessions with two legal complete stage/persistence epochs each, committed and pending reads, ordinary CLEAR between sessions with payload retention checked. Stalled typed memory handshakes, all FULL/K-only/V-only replies on both semantic heads and baseline shared-kind-row hits. Behavioral simulation with initial boot reset; no initial physical-reset-free reachability or guard/outer proof.')
    (out/'FINISHED.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print('FINISHED',result['passed'],flush=True);return 0 if result['passed']else 1


if __name__=='__main__':raise SystemExit(main())
