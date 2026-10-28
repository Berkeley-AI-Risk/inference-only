"""Native semantic control normal form after CLEAR with an old DDR drain.

No idle/empty prerequisite at the CLEAR edge. Retain actual parent DDR owner
and control; whole numerical/RAM child replies remain unrestricted. Quiet
means no newly accepted upper-level operation since the latest CLEAR.
"""
import argparse
import json
from pathlib import Path
import re

from run_attention_ownership import HERE, load
from run_semantic_relational import erase_checks
from run_service_relational import synthesis_text


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--run',type=Path,required=True)
    ap.add_argument('--timeout',type=int,default=25);args=ap.parse_args()
    prior=HERE/'runs/semantic-result-clear-r8';pi=json.loads((prior/'INPUTS.json').read_text())
    original=(prior/'production-datapath.sv').read_bytes();native=synthesis_text(original.decode())
    match=re.search(r'if\s*\(clear_i\)\s*begin\s*if\s*\(fault_q\)',native)
    if not match:raise ValueError('Native CLEAR branch changed')
    at=native.index('begin',match.start());end=at+5;level=1
    for token in re.finditer(r'\bbegin\b|\bend\b',native[end:]):
        level+=1 if token[0]=='begin'else-1
        if not level:end=end+token.end();break
    else:raise ValueError('Native CLEAR branch unbalanced')
    block=native[at:end]
    fields=dict(re.findall(r'\b(\w+)\s*<=\s*([^;]+);',block))
    if fields.get('engine_state_q')!='E_IDLE':raise ValueError('Healthy native engine CLEAR target changed')
    for name,value in fields.items():
        if not re.fullmatch(r"[A-Za-z_]\w*|\d+'[sS]?[bdhBDH][0-9a-fA-F_]+",value.strip()):
            raise ValueError('Unreviewed native normal-form value: '+name+'='+value)
    source=erase_checks((prior/'datapath.sv').read_text())
    monitor='''
    reg f_clear_seen=0,f_quiet=0,f_cleared_pending=0;
    always @(posedge clk)begin
        if(!rst_n)begin f_clear_seen<=0;f_quiet<=0;f_cleared_pending<=0;end
        else if(clear_i)begin f_clear_seen<=1;f_quiet<=1;f_cleared_pending<=ddr_owner_q!=DDR_NONE;end
        else if(stage_accept || head_start_accept)f_quiet<=0;
    end
    wire f_normal_state=rst_n && f_clear_seen && f_quiet && !fault_q;
    wire f_normal_healthy=f_normal_state && model_lock_i && !child_fault && !upstream_fault_i;
    always @*if(f_normal_state)begin
'''
    monitor+='\n'.join('        assert('+name+'=='+value.strip()+');'for name,value in fields.items())
    monitor+='''
        if(!busy_o)assert(ddr_owner_q==DDR_NONE);
    end
    always @(posedge clk)begin
        cover(f_normal_healthy && !busy_o && f_cleared_pending && !clear_i);
        cover(f_normal_healthy && busy_o && ddr_owner_q!=DDR_NONE && f_cleared_pending && !clear_i);
    end
'''
    source=source.replace('\nendmodule','\n'+monitor+'\nendmodule',1)
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    ports=parser.ports(source);top='board1_context2048_semantic_datapath'
    wrapper='module semantic_clear_normal(\n'+',\n'.join('    '+di+' wire '+sh+n for n,(di,sh)in ports.items())+'\n);\n'
    wrapper+='    '+top+' #(.ADDR_W(19))u_native('+','.join('.'+n+'('+n+')'for n in ports)+');\nendmodule\n'
    files={'production-datapath.sv':original,'datapath.sv':source.encode(),'wrapper.sv':wrapper.encode(),
        'normal-form-monitor.inc.sv':monitor.encode(),'runner.py':Path(__file__).read_bytes()}
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='semantic_clear_normal',
        reset_constraints='initial\nassume (= [rst_n] true)\nstate 1\nassume (= [rst_n] true)\n',
        assertions=monitor.count('assert('),covers=2,binding=dict(native_join=pi['binding']['native_join'],
            variant='baseline',initial_hard_reset=False,concrete_module=top,normal_fields=fields,
            requires_empty_ddr_at_clear=False,quiet_definition='No accepted new stage/head operation since the most recent real CLEAR',
            complete_actual_ddr_owner_retained=True),cuts=pi['internal_cuts'],
        depth=3,induction_depth=3,cover_depth=8,timeout=args.timeout,
        source_list=['datapath.sv','wrapper.sv'],primary_only=True,optimize_full=True,
        solver_cli={'z3':['--unroll','-S','-memory:1024']},
        scope='Actual semantic parent CLEAR-control normal form without an initial hard reset or an empty/idle prerequisite at CLEAR. Until a newly accepted upper operation, healthy control/ownership fields retain their real CLEAR values. An accepted old model transaction may drain; busy-low implies native DDR owner empty. Numerical/RAM child replies remain free, and child busy/pending and enclosing device barriers require composition.')


if __name__=='__main__':raise SystemExit(main())
