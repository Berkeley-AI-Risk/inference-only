"""Actual semantic model-read mux connected to projection and lookup readers."""
import argparse
import json
from pathlib import Path
import re

from run_attention_ownership import HERE, load
from run_semantic_ingress import tap, extend_instance


def restore_child(source,original,module,instance,rows):
    pattern=r'^    '+re.escape(module)+r'\s+(?:#\([^\n]*\)\s+)?'+re.escape(instance)+r'\s*\('
    matches=list(re.finditer(pattern,original,re.M))
    if len(matches)!=1:raise ValueError('Actual native child instance is not unique')
    match=matches[0];end=match.end();level=1
    while level:level+=(original[end]=='(')-(original[end]==')');end+=1
    if original[end]!=';':raise ValueError('Native child instance terminator changed')
    block=original[match.start():end+1]
    for index,row in enumerate(rows):
        port=',\n    input wire '+row['shape']+row['replacement']
        assignment='    assign '+row['expression']+' = '+row['replacement']+';'
        if source.count(port)!=1 or source.count(assignment)!=1:raise ValueError('Free reply seam changed')
        source=source.replace(port,'',1).replace(assignment,block if index==0 else'',1)
        if row['replacement']in source:raise ValueError('A complete native reply remains cut')
    return source


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--run',type=Path,required=True)
    ap.add_argument('--timeout',type=int,default=60);args=ap.parse_args()
    previous=HERE/'runs/semantic-drain-r1';di=json.loads((previous/'INPUTS.json').read_text())
    original=(previous/'production-datapath.sv').read_bytes();source=(previous/'datapath.sv').read_text()
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    files={};compile_sources=[];extra_cuts=[];extra_assertions=0;extra_covers=0;modules=[];receipts={}
    specs=[('proj','projection-drain-r2','embedding.sv','board1_fixed_group_projection_scale_job','u_projection',13),
        ('lookup','lookup-drain-r1','board1_context2048_semantic_lookup.sv','board1_context2048_semantic_lookup','u_lookup',2)]
    declarations=[]
    for key,name,filename,module,instance,bits in specs:
        prior=HERE/'runs'/name;pi=json.loads((prior/'INPUTS.json').read_text())
        for n in pi['files']:
            if not n.endswith('.sv')or n=='wrapper.sv':continue
            data=(prior/n).read_bytes()
            target=key+'-'+n if n.endswith('.inc.sv')else'projection.sv'if n=='embedding.sv'else n
            if target in files and files[target]!=data:raise ValueError('Conflicting shared native source')
            files[target]=data
        target='projection.sv'if filename=='embedding.sv'else filename
        text=files[target].decode();free={n:sh for n,(direction,sh)in parser.ports(text).items()if direction=='input'and n.startswith('f_child_')}
        text=tap(text,{'f_dp_pending_o':('['+str(bits-1)+':0] ','f_pending'),'f_dp_scope_o':('','f_scope'),
            'f_dp_clear_seen_o':('','f_clear_seen'),'f_dp_quiet_o':('','f_quiet')})
        files[target]=text.encode()
        rows=[r for r in di['internal_cuts']if r.get('instance')==instance]
        source=restore_child(source,original.decode(),module,instance,rows)
        if free:source=source.replace('\n);',',\n'+',\n'.join('    input wire '+sh+n for n,sh in free.items())+'\n);',1)
        source=extend_instance(source,instance,{**{n:n for n in free},'f_dp_pending_o':'f_'+key+'_pending',
            'f_dp_scope_o':'f_'+key+'_scope','f_dp_clear_seen_o':'f_'+key+'_clear_seen','f_dp_quiet_o':'f_'+key+'_quiet'})
        declarations.append('    wire['+str(bits-1)+':0]f_'+key+'_pending;wire f_'+key+'_scope,f_'+key+'_clear_seen,f_'+key+'_quiet;')
        compile_sources.extend(('projection.sv'if n=='embedding.sv'else n)for n in pi['compile_sources']if n!='wrapper.sv')
        extra_assertions+=pi['assertion_cells'];extra_covers+=pi['cover_cells'];extra_cuts+=pi['internal_cuts']
        modules+=pi['binding'].get('concrete_hierarchy_modules',list(pi['binding'].get('isolated_native_modules',{})))
        receipts[name]={}
        for n in('INPUTS.json','FINISHED.json'):
            raw=(prior/n).read_bytes();files[key+'-prerequisite-'+n]=raw
            receipts[name][n]=load('engine_hash',HERE/'proof_engine.py').sha(raw)
    before='wire f_arm=rst_n && !ddr_arbiter_fault_q && ddr_owner_q==DDR_NONE && ddr_pending_q==0;'
    after=before[:-1]+' && !fault_q && !projection_fault && !lookup_fault && !projection_busy && !lookup_busy && f_proj_scope && f_lookup_scope && f_proj_pending==0 && f_lookup_pending==0;'
    if source.count(before)!=1:raise ValueError('Actual semantic ledger entry changed')
    source=source.replace(before,after,1)
    source=source.replace('wire f_healthy=rst_n && f_scope && !ddr_arbiter_fault_q;',
        'wire f_healthy=rst_n && f_scope && !ddr_arbiter_fault_q && !fault_q && !projection_fault && !lookup_fault;',1)
    monitor='\n'.join(declarations)+'''
    always @*if(f_healthy)begin
        assert(f_proj_scope && f_lookup_scope);
        assert({9'd0,ddr_pending_q}==f_proj_pending+{11'd0,f_lookup_pending});
        if(ddr_owner_q==DDR_NONE)assert(f_proj_pending==0 && f_lookup_pending==0);
        if(ddr_owner_q==DDR_PROJ)assert(f_lookup_pending==0);
        if(ddr_owner_q==DDR_LOOK)assert(f_proj_pending==0);
        if(private_word_req_valid_o)assert(busy_o);
        if(!busy_o)assert(!private_word_req_valid_o && f_proj_pending==0 && f_lookup_pending==0);
    end
'''
    source=source.replace('\nendmodule','\n'+monitor+'\nendmodule',1)
    top='board1_context2048_semantic_datapath';ports=parser.ports(source)
    wrapper='module connected_semantic_drain(\n'+',\n'.join('    '+direction+' wire '+shape+n for n,(direction,shape)in ports.items())+'\n);\n'
    wrapper+='    '+top+' #(.ADDR_W(19))u_native('+','.join('.'+n+'('+n+')'for n in ports)+');\nendmodule\n'
    files.update({'production-datapath.sv':original,'datapath.sv':source.encode(),'wrapper.sv':wrapper.encode(),
        'connected-monitor.inc.sv':monitor.encode(),'connected-runner.py':Path(__file__).read_bytes()})
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='connected_semantic_drain',
        reset_constraints='initial\nassume (= [rst_n] true)\nstate 1\nassume (= [rst_n] true)\n',
        assertions=di['assertion_cells']+extra_assertions+monitor.count('assert('),covers=di['cover_cells']+extra_covers,
        binding=dict(native_join=di['binding']['native_join'],variant='baseline',initial_hard_reset=False,
            concrete_hierarchy_modules=sorted(set(modules+[top])),component_model_receipts=receipts,
            concrete_model_readers=['u_projection','u_lookup'],
            entry_policy='Native semantic owner/count and both connected readers empty and healthy at one common tracking boundary. No physical reset or idle-at-CLEAR prerequisite.'),
        cuts=[r for r in di['internal_cuts']if r.get('instance')not in('u_projection','u_lookup')]+extra_cuts,
        depth=4,induction_depth=4,cover_depth=20,timeout=args.timeout,
        source_list=list(dict.fromkeys(compile_sources))+['datapath.sv','wrapper.sv'],
        optimize_full=True,primary_only=True,solver_cli={'z3':['--unroll','-S','-memory:1024']},
        scope='Actual semantic controller/mux with actual projection job, full group-reader hierarchy and actual semantic lookup. Healthy pending count equals the connected readers; actual model requests imply semantic busy, and busy-low implies no owed or presented model request. Numerical/RAM services remain explicit seams. Ordinary CLEAR preserves pending reads; core and typed K/V/outer composition remain separate.')


if __name__=='__main__':raise SystemExit(main())
