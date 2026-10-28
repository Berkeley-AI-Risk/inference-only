"""Full native lookup: model-read pending ownership and quiet CLEAR barrier."""
import argparse
from pathlib import Path

from run_attention_ownership import HERE, load


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--run',type=Path,required=True)
    ap.add_argument('--timeout',type=int,default=25);args=ap.parse_args()
    builder=load('addresses',HERE.parent/'authentication-access/run_model_addresses.py')
    files,binding,count,covers=builder.derive(HERE.parents[1]/'fpga-demo/public-release','baseline','lookup')
    for n,data in list(files.items()):
        if not n.endswith('address-monitor.inc.sv'):continue
        targets=[k+'.sv'for k in binding['isolated_native_modules']if data in files[k+'.sv']]
        if len(targets)!=1:raise ValueError('Original address observer not unique')
        files[targets[0]]=files[targets[0]].replace(data,b'',1)
        count-=data.decode().count('assert(');covers-=data.decode().count('cover(')
    if count or covers:raise ValueError('Unreviewed original assertions')
    monitor='''
    reg f_active=0,f_any_reset=0,f_clear_seen=0,f_quiet=0,f_cleared_pending=0;
    reg[1:0]f_pending=0;
    wire f_arm=reset_n && state_q==ST_IDLE && !fail_q && !drain_to_fail_q;
    wire f_scope=f_active || f_arm;
    always @(posedge clk)begin
        if(!reset_n)begin
            f_active<=0;f_any_reset<=1;f_clear_seen<=0;f_quiet<=0;f_pending<=0;f_cleared_pending<=0;
        end else begin
            if(f_scope)begin
                f_active<=1;
                f_pending<=(f_active ? f_pending : 2'd0)+{1'b0,private_request_transfer}-{1'b0,private_response_transfer};
            end
            if(clear_i && f_scope)begin
                f_clear_seen<=1;f_quiet<=1;
                if(f_active && f_pending!=0)f_cleared_pending<=1;
            end else if(request_transfer)f_quiet<=0;
        end
    end
    wire f_healthy=reset_n && f_scope && !fail_q;
    always @*if(reset_n && !f_active)begin assert(f_pending==0);assert(!f_clear_seen);end
    always @*if(f_healthy)begin
        assert(state_q!=ST_FAIL);
        assert(!drain_to_fail_q);
        assert(f_pending=={1'b0,((state_q==ST_WAIT)||(state_q==ST_DRAIN))});
        if(!busy_o)assert(f_pending==0);
        if(private_word_req_valid_o)assert(busy_o && f_pending==0);
        if(f_clear_seen && f_quiet)begin
            assert(state_q==ST_IDLE || state_q==ST_DRAIN);
            assert(!private_word_req_valid_o && !response_valid_o);
        end
    end
    always @(posedge clk)begin
        cover(f_healthy && !f_any_reset && f_active && clear_i && f_pending!=0);
        cover(f_healthy && !f_any_reset && f_cleared_pending && !clear_i && busy_o && f_pending!=0);
        cover(f_healthy && !f_any_reset && f_cleared_pending && !clear_i && !busy_o && f_pending==0);
    end
'''
    name='board1_context2048_semantic_lookup.sv'
    files[name]=files[name].replace(b'\nendmodule',b'\n'+monitor.encode()+b'\nendmodule',1)
    files['drain-monitor.inc.sv']=monitor.encode();files['drain-runner.py']=Path(__file__).read_bytes()
    binding.update(initial_hard_reset=False,entry_policy='Tracking begins at healthy native IDLE with no pending model read; arbitrary retained payloads. Busy CLEAR can occur later without reset.')
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='native_model_addresses',
        reset_constraints='initial\nassume (= [reset_n] true)\nstate 1\nassume (= [reset_n] true)\n',
        assertions=monitor.count('assert('),covers=3,binding=binding,cuts=[],depth=4,induction_depth=3,
        cover_depth=8,timeout=args.timeout,source_list=[n+'.sv'for n in binding['isolated_native_modules']]+['wrapper.sv'],
        optimize_full=True,primary_only=True,solver_cli={'z3':['--unroll','-S','-memory:1024']},
        scope='Full native semantic lookup with accepted model-read pending accounting through busy CLEAR. Healthy busy-low implies no owed reply; requests imply busy. Tracked CLEAR prevents fresh reads or data publication until a new upper request. No hard reset or numerical reply restriction; enclosing semantic/core composition remains separate.')


if __name__=='__main__':raise SystemExit(main())
