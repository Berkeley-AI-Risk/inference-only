"""Connected tied embedding + full native group reader: busy-CLEAR barrier.

The numerical normalizer remains an explicit free child. The real model-read
hierarchy and all its pending/history logic are connected, with no reply cut.
"""
import argparse
import json
from pathlib import Path
import re

from run_attention_ownership import HERE, load
from run_semantic_ingress import tap, extend_instance
from run_service_memory import boundaries


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--run',type=Path,required=True)
    ap.add_argument('--timeout',type=int,default=25)
    ap.add_argument('--kind',choices=('embedding','projection'),default='embedding');args=ap.parse_args()
    projection=args.kind=='projection'
    prior=HERE/'runs/group-drain-r6';pi=json.loads((prior/'INPUTS.json').read_text())
    files={n:(prior/n).read_bytes()for n in pi['files']if n.endswith('.sv')and n!='wrapper.sv'}
    parent=HERE/'runs'/('projection-parent-clear-r9'if projection else'embedding-parent-clear-r1')
    ei=json.loads((parent/'INPUTS.json').read_text())
    original=(parent/('production-service.sv'if projection else'production-embedding.sv')).read_bytes()
    norm='board1_shared_projection_scale_group_adapter'if projection else'board1_fixed_vector_normalizer'
    norm_raw=(parent/('production-child-'+norm+'.sv')).read_bytes()
    matches=re.findall(r'^module\s+'+norm+r'\b[\s\S]*?^endmodule\b',norm_raw.decode(),re.M)
    if len(matches)!=1:raise ValueError('Native normalizer source not unique')
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    source,extra,cuts,count=boundaries(original.decode(),{norm:(matches[0],'native normalizer contract',norm_raw)},parser)
    if count!=1:raise ValueError('Expected only the numerical normalizer seam')
    group='board1_fixed_group_ddr_stream.sv'
    files[group]=tap(files[group].decode(),{
        'f_drain_pending_o':('[12:0] ','f_pending'),'f_drain_scope_o':('','f_scope'),
        'f_drain_state_o':('[2:0] ','state_q'),'f_drain_clear_seen_o':('','f_clear_seen'),
        'f_drain_quiet_o':('','f_quiet')}).encode()
    source=extend_instance(source,'u_group_stream'if projection else'u_tied_group_reader',{
        'f_drain_pending_o':'f_group_pending','f_drain_scope_o':'f_group_scope',
        'f_drain_state_o':'f_group_state','f_drain_clear_seen_o':'f_group_clear_seen',
        'f_drain_quiet_o':'f_group_quiet'})
    monitor='''
    wire[12:0]f_group_pending;wire[2:0]f_group_state;
    wire f_group_scope,f_group_clear_seen,f_group_quiet;
    reg f_active=0,f_any_reset=0,f_clear_seen=0,f_quiet=0,f_cleared_pending=0;
    reg[12:0]f_pending=0;
    wire f_arm=rst_n && model_lock_i && !aggregate_fault && !fail_q &&
        state_q==ST_IDLE && !group_busy && !norm_busy && f_group_scope && f_group_pending==0;
    wire f_scope=f_active || f_arm;
    wire f_request=private_word_req_valid_o && private_word_req_ready_i;
    wire f_response=private_word_rsp_valid_i && private_word_rsp_ready_o;
    always @(posedge clk)begin
        if(!rst_n)begin
            f_active<=0;f_any_reset<=1;f_clear_seen<=0;f_quiet<=0;f_pending<=0;f_cleared_pending<=0;
        end else begin
            if(f_scope)begin
                f_active<=1;
                f_pending<=(f_active ? f_pending : 13'd0)+{12'd0,f_request}-{12'd0,f_response};
            end
            if(clear_i && f_scope)begin
                f_clear_seen<=1;f_quiet<=1;
                if(f_active && f_pending!=0)f_cleared_pending<=1;
            end else if(start_valid_i && start_ready_o)f_quiet<=0;
        end
    end
    wire f_healthy=rst_n && f_scope && !fail_q && !group_fault;
    always @*if(rst_n && !f_active)begin assert(f_pending==0);assert(!f_clear_seen);end
    always @*if(f_healthy)begin
        assert(f_group_scope);
        assert(f_pending==f_group_pending);
        assert(state_q<=ST_DRAIN);
        if(state_q==ST_IDLE || state_q==ST_GROUP_START || state_q==ST_DONE || group_done_seen_q)
            assert(f_group_state==0 && f_group_pending==0);
        if(!busy_o)assert(f_pending==0 && !group_busy);
        if(private_word_req_valid_o)assert(busy_o);
        if(f_clear_seen && f_quiet)begin
            assert(state_q==ST_IDLE || state_q==ST_DRAIN);
            assert(f_group_clear_seen && f_group_quiet);
            assert(!private_word_req_valid_o);
        end
    end
    always @(posedge clk)begin
        cover(f_healthy && !f_any_reset && f_active && clear_i && f_pending!=0);
        cover(f_healthy && !f_any_reset && f_cleared_pending && !clear_i && busy_o && f_pending!=0);
        cover(f_healthy && !f_any_reset && f_cleared_pending && !clear_i && !busy_o && f_pending==0);
    end
'''
    if projection:
        aliases={'rst_n':'reset_n','model_lock_i':'model_locked_i','aggregate_fault':'integrated_fail',
            'group_busy':'stream_busy','norm_busy':'engine_busy','group_fault':'stream_fail',
            'group_done_seen_q':'stream_done_seen_q','ST_IDLE':'JOB_IDLE','ST_GROUP_START':'JOB_GROUP_START',
            'ST_DONE':'JOB_DONE','ST_DRAIN':'JOB_DRAIN'}
        for before,after in aliases.items():monitor=re.sub(r'\b'+before+r'\b',after,monitor)
        monitor=monitor.replace('state_q==JOB_IDLE || state_q==JOB_GROUP_START',
            'state_q==JOB_IDLE || state_q==JOB_LOAD || state_q==JOB_GROUP_START')
        # Pending accounting may start at any selected empty pre-request
        # boundary. GROUP_START additionally permits short nonvacuity traces
        # from an already captured current activation vector. It introduces
        # no model-read ownership and is a superset of the boot-IDLE entry.
        monitor=monitor.replace('state_q==JOB_IDLE && !stream_busy',
            '(state_q==JOB_IDLE || state_q==JOB_GROUP_START) && !stream_busy')
    source=source.replace('\nendmodule','\n'+monitor+'\nendmodule',1)
    top='board1_fixed_group_projection_scale_job'if projection else'board1_fixed_embedding_lookup'
    proof_top=args.kind+'_drain';reset='reset_n'if projection else'rst_n';ports=parser.ports(source)
    wrapper='module '+proof_top+'(\n'+',\n'.join('    '+di+' wire '+sh+n for n,(di,sh)in ports.items())+'\n);\n'
    wrapper+='    '+top+' #(.ADDR_W(19))u_native('+','.join('.'+n+'('+n+')'for n in ports)+');\nendmodule\n'
    files.update(extra);files.update({'production-embedding.sv':original,'embedding.sv':('`undef FORMAL\n'+source).encode(),
        'wrapper.sv':wrapper.encode(),'embedding-drain-monitor.inc.sv':monitor.encode(),'embedding-drain-runner.py':Path(__file__).read_bytes()})
    for n in('INPUTS.json','FINISHED.json'):files['group-prerequisite-'+n]=(prior/n).read_bytes()
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top=proof_top,
        reset_constraints='initial\nassume (= ['+reset+'] true)\nstate 1\nassume (= ['+reset+'] true)\n',
        assertions=pi['assertion_cells']+monitor.count('assert('),covers=pi['cover_cells']+3,
        binding=dict(native_join=ei['binding']['native_join'],variant='baseline',initial_hard_reset=False,
            concrete_hierarchy_modules=[top]+list(pi['binding']['isolated_native_modules']),
            fully_connected_model_reader=True,kind=args.kind,numerical_child_contract=norm,
            common_physical_clear=True,entry_policy='Tracking starts at healthy native '+args.kind+'/group empty model-read boundary (parent IDLE'+(' or pre-request GROUP_START'if projection else'')+'); arbitrary old payloads. Busy CLEAR is allowed later without reset.'),
        cuts=cuts,depth=4,induction_depth=4,cover_depth=20,timeout=args.timeout,
        source_list=pi['compile_sources'][:-1]+['embedding.sv','wrapper.sv'],
        optimize_full=True,primary_only=True,solver_cli={'z3':['--unroll','-S','-memory:1024']},
        scope='Actual '+args.kind+' plus full native group-read hierarchy and all native model-read handshakes. Healthy parent busy-low implies no group-reader busy or owed model reply; requests imply busy. Across a tracked busy CLEAR, no fresh request until new accepted upper work. Numerical '+norm+' remains a free child; core/shell public-ready and complete device session composition remain separate.')


if __name__=='__main__':raise SystemExit(main())
