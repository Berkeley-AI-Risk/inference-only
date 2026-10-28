"""Actual semantic sequence correspondence after healthy CLEAR without reset.

Only the final hidden mantissa and exponent have phase-conditional equality
premises. Every native register and output is observed; the actual caller's
permission and nested datapath replies remain separate obligations.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess

from run_attention_ownership import HERE, load
from run_semantic_ingress import ROOT, tap
from run_service_relational import synthesis_text


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--package',type=Path,required=True)
    ap.add_argument('--variant',default='baseline')
    ap.add_argument('--run',type=Path,required=True)
    ap.add_argument('--timeout',type=int,default=25)
    args=ap.parse_args()
    binder=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    _,native,binding=binder.binding(args.package,args.variant)
    relative=ROOT+'board1_context2048_semantic_sequence.sv';top='board1_context2048_semantic_sequence'
    original=(native/relative).read_bytes();raw=original.decode()
    prepare=args.run.resolve().with_name(args.run.name+'-prepare');prepare.mkdir(parents=True,exist_ok=False)
    (prepare/'probe.sv').write_text('`undef FORMAL\n'+raw)
    (prepare/'probe.ys').write_text('read_verilog -formal -sv -nosynthesis -D SYNTHESIS probe.sv\nhierarchy -check -top '+top+'\nproc\nwrite_json probe.json\n')
    with(prepare/'probe.log').open('w')as log:
        cp=subprocess.run(['yosys','-Q','probe.ys'],cwd=prepare,stdout=log,stderr=subprocess.STDOUT,timeout=30)
    if cp.returncode:raise ValueError('Native sequence scalar inventory failed')
    graph=json.loads((prepare/'probe.json').read_text())['modules'][top]
    qbits={b for c in graph['cells'].values()if re.match(r'^\$(?:a?dff|sdff|dffe|adffe|sdffe|dlatch|adlatch)',c['type'])
        for b in c['connections']['Q']if isinstance(b,int)}
    assigned=set(re.findall(r'\b(\w+)\s*(?:\[[^\]]+\])?\s*<=',synthesis_text(raw)))
    fields={n:len(graph['netnames'][n]['bits'])for n in sorted(assigned)if n in graph['netnames']and qbits.intersection(graph['netnames'][n]['bits'])}
    observed={b for n in fields for b in graph['netnames'][n]['bits']if isinstance(b,int)}
    if not qbits.issubset(observed):raise ValueError('Unobserved native sequence state')
    taps={**{'f_state_'+n+'_o':('['+str(w-1)+':0] ',n)for n,w in fields.items()},
        'f_protocol_fault_o':('','protocol_fault')}
    source=tap(raw,taps);ports=parser.ports(source)
    coupling={
        'private_result_mantissa_i':'a_result_valid_o && !a_f_protocol_fault_o',
        'private_result_exponent_i':'!clear_i && !a_f_protocol_fault_o && !a_state_fault_q && (a_state_state_q==4 || (a_state_state_q==3 && a_state_stage_q==15 && a_state_layer_q==5 && private_stage_done_i))',
    }
    lines=['module sequence_parent_relational(',',\n'.join(
        ['    input wire '+sh+n for n,(di,sh)in ports.items()if di=='input']+
        ['    input wire '+ports[n][1]+'discarded_'+n for n in coupling]),');','    reg f_joined=0;']
    for copy in('a','b'):
        for n,(di,sh)in ports.items():
            if di=='output':lines.append('    wire '+sh+copy+'_'+n+';')
        for n,w in fields.items():lines.append('    wire ['+str(w-1)+':0] '+copy+'_state_'+n+'='+copy+'_f_state_'+n+'_o;')
        con=[]
        for n,(di,_)in ports.items():
            value=n if di=='input'else copy+'_'+n
            if copy=='b'and n in coupling:value='('+coupling[n]+' ? '+n+' : discarded_'+n+')'
            con.append('.'+n+'('+value+')')
        lines.append('    '+top+' u_'+copy+'('+','.join(con)+');')
    lines+=['    always @(posedge clk)if(!rst_n)f_joined<=0;else if(clear_i)f_joined<=model_lock_i && !upstream_fault_i && !private_stage_fault_i && !a_f_protocol_fault_o && !b_f_protocol_fault_o && !a_state_fault_q && !b_state_fault_q;',
        '    always @*if(rst_n && f_joined)begin',
        '        assert(a_state_lock_seen_q && b_state_lock_seen_q);',
        '        assert(a_state_state_q<=7 && b_state_state_q<=7);',
        '        assert(a_state_layer_q<=5 && b_state_layer_q<=5);',
        '        assert(a_state_stage_q<=16 && b_state_stage_q<=16);']
    lines+=['        assert(a_state_'+n+'==b_state_'+n+');'for n in fields]
    for n,(di,_)in ports.items():
        if di!='output'or n.startswith('f_'):continue
        guard='a_result_valid_o && !a_f_protocol_fault_o'if n.startswith('result_')and n!='result_valid_o'else'1'
        lines.append('        if('+guard+')assert(a_'+n+'==b_'+n+');')
    lines+=['    end','    always @(posedge clk)begin',
        '        cover(rst_n && !f_joined && a_state_input_exponent_q!=b_state_input_exponent_q);',
        '        cover(rst_n && f_joined && a_input_ready_o && input_valid_i && input_index_i==2);',
        '    end','endmodule']
    wrapper='\n'.join(lines)+'\n'
    files={'production-sequence.sv':original,'sequence.sv':('`undef FORMAL\n'+source).encode(),
        'wrapper.sv':wrapper.encode(),'runner.py':Path(__file__).read_bytes(),
        'inventory-helper.py':(HERE/'run_service_relational.py').read_bytes(),
        'tap-helper.py':(HERE/'run_semantic_ingress.py').read_bytes(),
        **{p.name:p.read_bytes()for p in prepare.iterdir()if p.is_file()}}
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='sequence_parent_relational',
        reset_constraints='initial\nassume (= [rst_n] true)\nstate 1\nassume (= [rst_n] true)\n',
        assertions=wrapper.count('assert('),covers=2,binding=dict(native_join=binding,variant=args.variant,
            production_path=relative,initial_hard_reset=False,native_sequential_bits=len(qbits),sequential_fields=fields,
            reply_coupling_predicates=coupling,
            entry_policy='Common healthy CLEAR with model LOCK and no native sequence protocol fault in either copy'),cuts=[],
        depth=3,induction_depth=2,cover_depth=8,timeout=args.timeout,
        source_list=['sequence.sv','wrapper.sv'],expected_memories=0,optimize_full=True,
        primary_only=True,solver_cli={'z3':['--unroll','-S','-memory:1024']},
        scope='Actual sequence conditional correspondence after healthy model-locked CLEAR without hard reset. Every native register and guarded output compared; independent final-hidden payloads outside actual consuming phases. Final caller permissions, nested datapath contracts and whole-device session composition remain separate.')


if __name__=='__main__':raise SystemExit(main())
