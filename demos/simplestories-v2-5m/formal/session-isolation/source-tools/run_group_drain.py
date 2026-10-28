"""Native model group reader: accepted-request accounting through busy CLEAR.

All metadata-reader, width-adapter, beat-register and delta children remain
connected. The logical observer starts at an empty native control point, with
arbitrary old payloads and no physical reset prerequisite. Public CLEAR never
resets the observer's pending count.
"""
import argparse
from pathlib import Path

from run_attention_ownership import HERE, load
from run_semantic_ingress import tap, extend_instance


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--run',type=Path,required=True)
    ap.add_argument('--timeout',type=int,default=25)
    args=ap.parse_args()
    builder=load('addresses',HERE.parent/'authentication-access/run_model_addresses.py')
    files,binding,assertions,covers=builder.derive(HERE.parents[1]/'fpga-demo/public-release','baseline','group-stream')
    removed=[]
    for name,data in list(files.items()):
        if not name.endswith('address-monitor.inc.sv'):continue
        targets=[n+'.sv'for n in binding['isolated_native_modules']if data in files[n+'.sv']]
        if len(targets)!=1 or files[targets[0]].count(data)!=1:raise ValueError('Address observer not unique')
        files[targets[0]]=files[targets[0]].replace(data,b'',1)
        assertions-=data.decode().count('assert(');covers-=data.decode().count('cover(');removed.append(name)
    if assertions or covers:raise ValueError('Unreviewed original property inventory')
    child='board1_fixed_projection_metadata_reader.sv'
    metadata=files[child].decode()
    metadata=tap(metadata,{
        'f_pending_o':('','request_outstanding_q'),
        'f_sticky_fail_o':('','fail_closed_q'),
        'f_state_o':('[2:0] ','state_q')})
    metadata=metadata.replace('\n);',',\n    input wire f_scope_i\n);',1)
    child_monitor='''
    always @*if(reset_n && f_scope_i && !fail_closed_q)begin
        assert(state_q!=ST_FAIL);
        if(request_outstanding_q)assert(state_q==ST_WAIT || state_q==ST_DRAIN);
        if(state_q==ST_WAIT || state_q==ST_DRAIN)assert(request_outstanding_q);
        if(!busy_o)assert(!request_outstanding_q);
    end
'''
    metadata=metadata.replace('\nendmodule','\n'+child_monitor+'\nendmodule',1)
    files[child]=metadata.encode()
    top='board1_fixed_group_ddr_stream';name=top+'.sv';source=files[name].decode()
    source=extend_instance(source,'u_metadata_reader',{
        'f_pending_o':'f_meta_pending','f_sticky_fail_o':'f_meta_fail',
        'f_state_o':'f_meta_state','f_scope_i':'f_scope'})
    monitor='''
    wire f_meta_pending,f_meta_fail;
    wire[2:0]f_meta_state;
    reg f_active=0,f_any_reset=0,f_cleared_pending=0,f_clear_seen=0,f_quiet=0;
    reg[12:0]f_pending=0;
    wire f_arm=reset_n && model_locked_i && !fail_closed_q && !f_meta_fail &&
        !upstream_fail_closed_i && state_q==ST_IDLE && owner_q==OWNER_NONE &&
        outstanding_words_q==0 && f_meta_state==0 && !f_meta_pending;
    wire f_scope=f_active || f_arm;
    wire f_request=private_word_req_valid_o && private_word_req_ready_i;
    wire f_response=private_word_rsp_valid_i && private_word_rsp_ready_o;
    always @(posedge clk)begin
        if(!reset_n)begin
            f_active<=0;f_pending<=0;f_cleared_pending<=0;f_any_reset<=1;f_clear_seen<=0;f_quiet<=0;
        end else begin
            if(f_scope)begin
                f_active<=1;
                f_pending<=(f_active ? f_pending : 13'd0)+{12'd0,f_request}-{12'd0,f_response};
            end
            if(clear_i && f_active && f_pending!=0)f_cleared_pending<=1;
            if(clear_i && f_scope)begin f_clear_seen<=1;f_quiet<=1;end
            else if(descriptor_transfer)f_quiet<=0;
        end
    end
    wire f_healthy=reset_n && f_scope && !fail_closed_q && !f_meta_fail;
    always @*if(reset_n && !f_active)assert(f_pending==0);
    always @*if(reset_n && !f_active)assert(!f_clear_seen);
    always @*if(f_healthy)begin
        assert(state_q!=ST_FAIL);
        assert(owner_q<=OWNER_WEIGHT);
        if(f_meta_pending)assert(owner_q==OWNER_META);
        if(owner_q!=OWNER_WEIGHT)assert(outstanding_words_q==0);
        assert(f_pending==(owner_q==OWNER_WEIGHT ? {1'b0,outstanding_words_q} :
            owner_q==OWNER_META ? {12'd0,f_meta_pending} : 13'd0));
        if(state_q==ST_IDLE || state_q==ST_HEADER || state_q==ST_DONE)assert(owner_q==OWNER_NONE);
        if(state_q==ST_META_START || state_q==ST_META_RUN)assert(owner_q==OWNER_META);
        if(state_q==ST_META_START || state_q==ST_META_RUN || state_q==ST_HEADER ||
           state_q==ST_WEIGHT || state_q==ST_DONE)assert(group_words_q==640 || group_words_q==1705);
        if(state_q==ST_WEIGHT)begin
            assert(owner_q==OWNER_WEIGHT);
            assert(outstanding_words_q<={1'b0,issued_words_q});
            assert(issued_words_q<=group_words_q);
        end
        if(owner_q==OWNER_WEIGHT)begin
            assert(group_words_q==640 || group_words_q==1705);
            assert(outstanding_words_q<=1705);
        end
        if(!busy_o)begin assert(f_pending==0);assert(!f_meta_pending);end
        if(clear_i)assert(!private_word_req_valid_o);
    end
    always @*if(f_healthy && f_clear_seen && f_quiet)begin
            assert(state_q==ST_IDLE || state_q==ST_DRAIN);
            assert(f_meta_state==0 || f_meta_state==5);
            assert(issued_words_q==0 && consumed_words_q==0);
            assert(accepted_beats_q==0 && metadata_count_q==0);
            assert(!private_word_req_valid_o);
            if(!busy_o)assert(!meta_busy && f_meta_state==0);
    end
    always @(posedge clk)begin
        cover(f_healthy && f_active && !f_any_reset && clear_i && f_pending!=0);
        cover(f_healthy && f_active && !f_any_reset && f_cleared_pending &&
              !clear_i && state_q==ST_DRAIN && f_pending!=0);
        cover(f_healthy && f_active && !f_any_reset && f_cleared_pending &&
              !clear_i && !busy_o && f_pending==0);
    end
'''
    source=source.replace('\nendmodule','\n'+monitor+'\nendmodule',1);files[name]=source.encode()
    files['drain-monitor.inc.sv']=monitor.encode();files['metadata-drain-monitor.inc.sv']=child_monitor.encode()
    files['drain-runner.py']=Path(__file__).read_bytes()
    binding.update(initial_hard_reset=False,removed_address_only_observers=removed,
        pending_counter_bits=13,clear_resets_pending_observer=False,
        entry_policy='Logical tracking starts at native parent/metadata IDLE, no pending requests, no sticky fault; arbitrary old payloads. No hard reset or empty-at-CLEAR prerequisite.')
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='native_model_addresses',
        reset_constraints='initial\nassume (= [reset_n] true)\nstate 1\nassume (= [reset_n] true)\n',
        assertions=monitor.count('assert(')+child_monitor.count('assert('),covers=3,
        binding=binding,cuts=[],depth=4,induction_depth=4,cover_depth=16,timeout=args.timeout,
        source_list=[n+'.sv'for n in binding['isolated_native_modules']]+['wrapper.sv'],
        map_literal_roms=True,optimize_full=True,primary_only=True,
        solver_cli={'z3':['--unroll','-S','-memory:1024']},
        scope='Full native group reader and all reachable children. Accepted private model requests remain counted until actual consumed replies, across busy CLEAR. Healthy busy-low implies no owed response, including the real metadata-child pending bit. Arbitrary old payloads and no physical reset entry; global endpoint/core transport and enclosing device-ready composition remain separate.')


if __name__=='__main__':raise SystemExit(main())
