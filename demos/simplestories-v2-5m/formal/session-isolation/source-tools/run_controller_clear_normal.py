"""Actual parent control/authority normal forms across busy-child CLEAR drain."""
import argparse
import json
from pathlib import Path
import re

from run_attention_ownership import HERE, load
from run_semantic_relational import erase_checks
from run_service_relational import synthesis_text


CASES={
    'embedding':dict(prior='embedding-parent-clear-r1',source='embedding.sv',original='production-embedding.sv',
        module='board1_fixed_embedding_lookup',new='start_valid_i && start_ready_o',
        pending='group_busy || norm_busy',owners=['f_token_owned','f_header_owned']),
    'shell':dict(prior='shell-parent-clear-r4',source='shell.sv',original='production-shell.sv',
        module='board1_context2048_token_shell',new='append_transfer || step_transfer',
        pending='ddr_owner_q!=DDR_OWNER_NONE || embed_busy || rms_busy || argmax_busy || private_layer_busy_i',
        owners=['f_meta_embedding','f_meta_layer','f_meta_norm']),
    'seeded-shell':dict(prior='shell-parent-seeded-clear-r1',source='shell.sv',original='production-shell.sv',
        module='board1_context2048_token_shell',new='append_transfer || step_transfer',
        pending='ddr_owner_q!=DDR_OWNER_NONE || embed_busy || rms_busy || argmax_busy || private_layer_busy_i',
        owners=['f_meta_embedding','f_meta_layer','f_meta_norm']),
}


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--kind',choices=CASES,required=True)
    ap.add_argument('--run',type=Path,required=True);ap.add_argument('--timeout',type=int,default=25)
    args=ap.parse_args();case=CASES[args.kind];prior=HERE/'runs'/case['prior']
    pi=json.loads((prior/'INPUTS.json').read_text());original=(prior/case['original']).read_bytes()
    native=synthesis_text(original.decode());source=erase_checks((prior/case['source']).read_text())
    matches=list(re.finditer(r'if\s*\(clear_i\)\s*begin',native))
    if len(matches)!=1:raise ValueError('Native parent CLEAR branch not unique')
    at=native.index('begin',matches[0].start());end=at+5;level=1
    for token in re.finditer(r'\bbegin\b|\bend\b',native[end:]):
        level+=1 if token[0]=='begin'else-1
        if not level:end=end+token.end();break
    else:raise ValueError('Native CLEAR branch unbalanced')
    fields=dict(re.findall(r'\b(\w+)\s*<=\s*([^;]+);',native[at:end]))
    cancel=fields.pop('state_q')
    for name,value in fields.items():
        if not re.fullmatch(r"[A-Za-z_]\w*|\d+'[sS]?[bdhBDH][0-9a-fA-F_]+",value.strip()):
            raise ValueError('Unreviewed parent normal-form value')
    monitor='''
    reg f_normal_seen=0,f_normal_quiet=0,f_normal_pending=0;
    always @(posedge clk)begin
        if(!rst_n)begin f_normal_seen<=0;f_normal_quiet<=0;f_normal_pending<=0;end
        else if(clear_i)begin f_normal_seen<=1;f_normal_quiet<=1;f_normal_pending<=PENDING;end
        else if(NEW_OPERATION)f_normal_quiet<=0;
    end
    wire f_normal=rst_n && f_normal_seen && f_normal_quiet && !fail_q;
    always @*if(f_normal)begin
'''.replace('PENDING',case['pending']).replace('NEW_OPERATION',case['new'])
    monitor+='        assert(state_q==ST_IDLE || state_q=='+cancel.strip()+');\n'
    monitor+='\n'.join('        assert('+name+'=='+value.strip()+');'for name,value in fields.items())+'\n'
    monitor+='\n'.join('        assert(!'+name+');'for name in case['owners'])
    monitor+='''
    end
    always @(posedge clk)begin
        cover(f_normal && model_lock_i && !f_fatal_o && f_normal_pending && busy_o && !clear_i);
        cover(f_normal && model_lock_i && !f_fatal_o && f_normal_pending && !busy_o && !clear_i);
    end
'''
    source=source.replace('\nendmodule','\n'+monitor+'\nendmodule',1)
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    ports=parser.ports(source);top='controller_clear_normal'
    wrapper='module '+top+'(\n'+',\n'.join('    '+di+' wire '+sh+n for n,(di,sh)in ports.items())+'\n);\n'
    wrapper+='    '+case['module']+' #(.ADDR_W(19))u_native('+','.join('.'+n+'('+n+')'for n in ports)+');\nendmodule\n'
    files={case['original']:original,'controller.sv':source.encode(),'wrapper.sv':wrapper.encode(),
        'normal-form-monitor.inc.sv':monitor.encode(),'runner.py':Path(__file__).read_bytes()}
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top=top,
        reset_constraints='initial\nassume (= [rst_n] true)\nstate 1\nassume (= [rst_n] true)\n',
        assertions=monitor.count('assert('),covers=2,binding=dict(native_join=pi['binding']['native_join'],
            variant=pi['binding']['variant'],initial_hard_reset=False,concrete_module=case['module'],
            normal_fields=fields,normal_states=['ST_IDLE',cancel.strip()],observer_authority_fields=case['owners'],
            requires_idle_children_at_clear=False,quiet_definition=case['new']),cuts=pi['internal_cuts'],
        depth=3,induction_depth=3,cover_depth=8,timeout=args.timeout,
        source_list=['controller.sv','wrapper.sv'],expected_memories=0,primary_only=True,optimize_full=True,
        solver_cli={'z3':['--unroll','-S','-memory:1024']},
        scope='Actual '+args.kind+' parent control/authority normal form after real CLEAR with busy children permitted and no initial hard reset. Until new accepted upper work, healthy control stays in IDLE/drain with actual cleared counters/valid fields and revoked transient metadata authority. Whole child replies are free; accepted endpoint-pending ownership and full device drain require their contracts.')


if __name__=='__main__':raise SystemExit(main())
