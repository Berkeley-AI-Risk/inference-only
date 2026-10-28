"""Actual semantic model-read hierarchy with the native typed K/V cache restored."""
import argparse
import json
from pathlib import Path
import re

from run_attention_ownership import HERE, load
from run_connected_semantic_drain import restore_child
from run_semantic_ingress import tap, extend_instance
from run_kv_session_drain import TOP
from run_service_relational import width


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--run',type=Path,required=True)
    ap.add_argument('--variant',choices=('baseline','kv-protected'),default='baseline')
    ap.add_argument('--directed-covers',action='store_true',help='Reachability only: delayed owned typed completion after busy CLEAR.')
    ap.add_argument('--timeout',type=int,default=30);args=ap.parse_args()
    parent=HERE/'runs/connected-semantic-drain-r1'
    cache=HERE/'runs'/('kv-session-drain-baseline-r2'if args.variant=='baseline'else'kv-session-drain-protected-r1')
    pi=json.loads((parent/'INPUTS.json').read_text());ci=json.loads((cache/'INPUTS.json').read_text())
    engine=load('engine',HERE/'proof_engine.py');files={}
    for n,row in pi['files'].items():
        raw=(parent/n).read_bytes()
        if engine.sha(raw)!=row['sha256']:raise ValueError('Frozen parent input changed')
        if n in ('wrapper.sv','engine.py','prove.ys','reset.smtc'):continue
        if n.startswith('production')and n.endswith('.sv')and re.search(rb'^module\s+'+TOP.encode()+rb'\b',raw,re.M):
            files['reference-uncompiled-'+n+'.txt']=raw
        else:files[n]=raw
    for n,row in ci['files'].items():
        if not n.endswith('.sv')or n=='wrapper.sv':continue
        raw=(cache/n).read_bytes()
        if engine.sha(raw)!=row['sha256']:raise ValueError('Frozen cache input changed')
        if n in files and files[n]!=raw:raise ValueError('Conflicting native source')
        files[n]=raw
    source=files['datapath.sv'].decode();original=files['production-datapath.sv'].decode()
    rows=[r for r in pi['internal_cuts']if r.get('instance')=='u_kv_cache']
    if len(rows)!=30:raise ValueError('Actual K/V child output inventory changed')
    source=restore_child(source,original,TOP,'u_kv_cache',rows)
    cache_source=files[TOP+'.sv'].decode()
    cache_source=tap(cache_source,{'f_dp_scope_o':('','f_scope'),
        'f_dp_write_pending_o':('[1:0] ','f_write_pending'),'f_dp_read_pending_o':('[4:0] ','f_read_pending')})
    files[TOP+'.sv']=cache_source.encode()
    source=extend_instance(source,'u_kv_cache',{'f_dp_scope_o':'f_kv_scope',
        'f_dp_write_pending_o':'f_kv_write_pending','f_dp_read_pending_o':'f_kv_read_pending'})
    before='f_proj_pending==0 && f_lookup_pending==0;'
    after='f_proj_pending==0 && f_lookup_pending==0 && f_kv_scope && f_kv_write_pending==0 && f_kv_read_pending==0 && !kv_fault;'
    if source.count(before)!=1:raise ValueError('Parent common tracking entry changed')
    source=source.replace(before,after,1)
    before='wire f_healthy=rst_n && f_scope && !ddr_arbiter_fault_q && !fault_q && !projection_fault && !lookup_fault;'
    if source.count(before)!=1:raise ValueError('Parent health guard changed')
    source=source.replace(before,before[:-1]+' && !kv_fault;',1)
    monitor='''
    wire f_kv_scope;
    wire [1:0] f_kv_write_pending;
    wire [4:0] f_kv_read_pending;
    reg f_kv_cleared_pending=0;
    always @(posedge clk)begin
        if(!rst_n)f_kv_cleared_pending<=0;
        else if(f_healthy && clear_i && (f_kv_write_pending!=0 || f_kv_read_pending!=0))f_kv_cleared_pending<=1;
    end
    always @*if(f_healthy)begin
        assert(f_kv_scope);
        if(kv_write_req_valid_o || kv_read_req_valid_o)assert(busy_o);
        if(!busy_o)begin
            assert(f_kv_write_pending==0 && f_kv_read_pending==0);
            assert(!kv_write_req_valid_o && !kv_read_req_valid_o);
        end
    end
    always @(posedge clk)begin
        cover(f_healthy && !f_any_reset && clear_i && f_kv_write_pending!=0);
        cover(f_healthy && !f_any_reset && clear_i && f_kv_read_pending!=0);
        cover(f_healthy && !f_any_reset && f_kv_cleared_pending && !clear_i && !busy_o && f_kv_write_pending==0 && f_kv_read_pending==0);
    end
'''
    # Model-reader and K/V unit covers remain in their completed receipts.
    # This connected scope requests only the three parent barrier targets.
    sources=list(dict.fromkeys(pi['compile_sources']+ci['compile_sources']))
    sources=[n for n in sources if n!='wrapper.sv']
    files['datapath.sv']=source.encode()
    for n in sources:
        text=files[n].decode()
        while 'cover('in text:
            at=text.index('cover(');end=at+6;level=1
            while level:level+=(text[end]=='(')-(text[end]==')');end+=1
            if text[end]!=';':raise ValueError('Inherited cover syntax changed')
            text=text[:at]+' begin end '+text[end+1:]
        files[n]=text.encode()
    source=files['datapath.sv'].decode().replace('\nendmodule','\n'+monitor+'\nendmodule',1)
    files['datapath.sv']=source.encode();files['connected-kv-monitor.inc.sv']=monitor.encode()
    files['connected-kv-runner.py']=Path(__file__).read_bytes()
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    ports=parser.ports(source);wrapper='module connected_kv_drain(\n'+',\n'.join('    '+di+' wire '+sh+n for n,(di,sh)in ports.items())+'\n);\n'
    wrapper+='    board1_context2048_semantic_datapath #(.ADDR_W(19))u_native('+','.join('.'+n+'('+n+')'for n in ports)+');\nendmodule\n'
    files['wrapper.sv']=wrapper.encode()
    cover_constraints=None
    if args.directed_covers:
        constraints=['initial\nassume (= [rst_n] true)\n']
        for step in range(8):
            constraints.append('state '+str(step)+'\n')
            for n,(direction,shape)in ports.items():
                if direction!='input'or n=='clk':continue
                if step==3 and n in ('kv_write_cpl_valid_i','kv_read_rsp_valid_i'):
                    ready='kv_write_cpl_ready_o'if n=='kv_write_cpl_valid_i'else'kv_read_rsp_ready_o'
                    literal='['+ready+']'
                else:
                    value=int(n in ('rst_n','model_lock_i')or 'ready'in n or(n=='clear_i'and step==1))
                    bits=width(shape);literal=('true'if value else'false')if bits==1 else'(_ bv'+str(value)+' '+str(bits)+')'
                constraints.append('assume (= ['+n+'] '+literal+')\n')
        cover_constraints=''.join(constraints)
    return engine.check(args.run,files,top='connected_kv_drain',
        reset_constraints=(parent/'reset.smtc').read_text(),cover_constraints=cover_constraints,
        assertions=pi['assertion_cells']+ci['assertion_cells']+monitor.count('assert('),
        covers=3,binding=dict(native_join=ci['binding']['native_join'],variant=args.variant,initial_hard_reset=False,
            concrete_hierarchy_modules=sorted(set(pi['binding']['concrete_hierarchy_modules']+ci['binding']['concrete_hierarchy_modules'])),
            native_KV_child_outputs_restored=len(rows),
            entry_policy='Semantic/model readers and native K/V typed ledgers start at a common logically empty accepted-work boundary. Already captured current tensors/pre-request K/V control may be present. No physical reset or empty-at-CLEAR prerequisite.'),
        cuts=[r for r in pi['internal_cuts']if r.get('instance')!='u_kv_cache'],
        depth=2,induction_depth=1,cover_depth=8 if args.directed_covers else 12,timeout=args.timeout,source_list=sources+['wrapper.sv'],
        optimize_full=True,primary_only=True,solver_cli={'z3':['--unroll','-S','-memory:1024']},
        scope='Actual semantic controller and full model-read/typed K/V protocols connected, including every native K/V payload RAM and mapper. Healthy active semantic busy-low implies no owed or presented model/typed K/V work. Numerical/attention/service replies remain explicit seams; no complete K/V or model-reader reply is free. Core shell/outer transport and full payload/session correspondence remain separate.')


if __name__=='__main__':raise SystemExit(main())
