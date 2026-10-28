"""Concrete two-execution CLEAR/session isolation for scalar arithmetic RTL.

Copies begin with independent arbitrary sequential state and no hard reset.
After a common cancellation edge, all inventoried state and outputs must
agree for arbitrary matched future inputs. Arithmetic is retained in full.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess

from run_attention_ownership import HERE, load

CASES={
    'vector-shift':'board1_fixed_vector_rne_shift_iterative',
    'attention-shift':'board1_fixed_attention_rne_shift_iterative',
    'attention-divider':'board1_fixed_attention_rne_div_signed64',
    'rms-divider':'board0_exact_rne_div_signed64_iterative',
    'rms-bounded-divider':'board1_rmsnorm_bounded28_divider',
    'isqrt':'board0_exact_isqrt_u45_iterative',
    'normalizer-shift':'board1_fixed_vector_rne_shift_pipeline1',
    'elementwise':'board1_fixed_elementwise_product_compact_lane',
    'argmax':'board1_fixed_head_argmax',
}


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--package',type=Path,required=True)
    ap.add_argument('--variant',default='baseline')
    ap.add_argument('--kind',choices=CASES,required=True)
    ap.add_argument('--run',type=Path,required=True)
    ap.add_argument('--timeout',type=int,default=45)
    ap.add_argument('--abstract-combinational-product',action='store_true')
    ap.add_argument('--operation-relevant-inputs',action='store_true')
    ap.add_argument('--independent-unused-ready',action='store_true')
    args=ap.parse_args()
    binder=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    _,native,binding=binder.binding(args.package,args.variant)
    top=CASES[args.kind];matches=[]
    for path in binding['distributed_inputs']:
        if not path.endswith('.sv'):continue
        raw=(native/path).read_bytes()
        for m in re.finditer(r'^module '+top+r'\b[\s\S]*?^endmodule',raw.decode(),re.M):matches.append((m[0],path,raw))
    if len(matches)!=1:raise ValueError('Native scalar module not unique')
    original,relative,raw=matches[0]
    children={}
    if args.kind=='elementwise':
        child='board1_fixed_elementwise_product_dsp'
        paths=[n for n in binding['distributed_inputs']if n.endswith('/'+child+'.sv')]
        if len(paths)!=1:raise ValueError('Concrete elementwise product child missing')
        children['product-child.sv']=(native/paths[0]).read_bytes()
    if args.kind=='argmax':
        paths=[n for n in binding['distributed_inputs']if n.endswith('/board1_fixed_head_logit_greater.sv')]
        if len(paths)!=1:raise ValueError('Exact greedy comparator child missing')
        children['compare-child.sv']=(native/paths[0]).read_bytes()
    preparation=args.run.resolve().with_name(args.run.name+'-prepare');preparation.mkdir(parents=True,exist_ok=False)
    probe_source=('`undef FORMAL\n'+original+'\n').encode()
    (preparation/'probe.sv').write_bytes(probe_source)
    for n,data in children.items():(preparation/n).write_bytes(data)
    recipe='read_verilog -formal -sv -nosynthesis -D SYNTHESIS probe.sv '+' '.join(children)+'\nhierarchy -check -top '+top+'\nproc\nopt_clean\nwrite_json probe.json\n'
    (preparation/'probe.ys').write_text(recipe)
    with(preparation/'probe.log').open('w')as log:
        cp=subprocess.run(['yosys','-Q','probe.ys'],cwd=preparation,stdout=log,stderr=subprocess.STDOUT,timeout=30)
    if cp.returncode:raise ValueError('Native state inventory elaboration failed')
    graph=json.loads((preparation/'probe.json').read_text())['modules'][top]
    if any(c['type'].startswith('$mem')for c in graph['cells'].values()):raise ValueError('Scalar proof cannot omit memories')
    sequential=[c for c in graph['cells'].values()if re.match(r'^\$(?:a?dff|sdff|dffe|adffe|sdffe|dlatch|adlatch)',c['type'])]
    if not sequential:raise ValueError('No sequential state found')
    state_bits={bit for c in sequential for bit in c['connections']['Q']if isinstance(bit,int)}
    assignments=set(re.findall(r'\b(\w+)\s*(?:\[[^\]\n]+\])?\s*<=',original.split('`ifdef FORMAL',1)[0]))
    fields={name:len(graph['netnames'][name]['bits'])for name in sorted(assignments)
            if name in graph['netnames'] and state_bits.intersection(graph['netnames'][name]['bits'])}
    observed={bit for name in fields for bit in graph['netnames'][name]['bits']if isinstance(bit,int)}
    if not state_bits.issubset(observed):raise ValueError('Uncovered native sequential bits')
    relation={name:'1'for name in fields}
    if args.kind=='normalizer-shift':
        fixed={'state_q','response_valid_o','response_result_o','response_fault_o'}
        captured={'source_q','amount_q','left_q','negative_q','force_zero_q','bad_count_q'}
        if set(fields)!=fixed|captured|{'low_q','shifted_q'}:
            raise ValueError('Normalizer pipeline storage classification changed')
        if original.count('IDLE=0,LOW=1,HIGH=2,ROUND=3,HOLD=5;')!=1:
            raise ValueError('Normalizer phase encoding changed')
        for name in captured:relation[name]='a_state_state_q!=0'
        relation['low_q']='a_state_state_q==2 || a_state_state_q==3 || a_state_state_q==5'
        relation['shifted_q']='a_state_state_q==3 || a_state_state_q==5'
    if args.kind=='argmax':
        for n in ('pending_token_q','pending_scaled_q','pending_exponent_q'):
            if n not in fields:raise ValueError('Greedy pending-row census changed')
            relation[n]='a_state_state_q==4'
    if args.operation_relevant_inputs:
        if args.kind!='elementwise':raise ValueError('Operation relevance adapter is elementwise-specific')
        rope_states=sorted(set(int(v)for _,v in re.findall(r'(ST_ROPE_\w+)\s*=\s*\d+\x27d(\d+)',original)))
        if not rope_states:raise ValueError('Concrete RoPE phase inventory changed')
        for n in ('cosine_q','sine_q'):
            if n not in fields:raise ValueError('Missing retained coefficient field')
            relation[n]=' || '.join('a_state_state_q=='+str(v)for v in rope_states)
    cuts=[]
    if args.abstract_combinational_product:
        if args.kind!='elementwise':raise ValueError('Product congruence adapter is elementwise-specific')
        child_graph=json.loads((preparation/'probe.json').read_text())['modules']['board1_fixed_elementwise_product_dsp']
        if any(re.match(r'^\$(?:a?dff|sdff|dffe|adffe|sdffe|dlatch|adlatch|mem)',c['type'])for c in child_graph['cells'].values()):
            raise ValueError('Product child is stateful; congruence is insufficient')
        before=re.search(r'    board1_fixed_elementwise_product_dsp u_product_dsp\s*\([\s\S]*?\);',original)
        if before is None:raise ValueError('Actual product seam changed')
        original=original[:before.start()]+'    assign dsp_product=f_numeric_product_i;\n    assign f_numeric_operands_o={dsp_first,dsp_second};'+original[before.end():]
        original=original.replace('\n);',',\n    input wire [31:0] f_numeric_product_i,\n    output wire [31:0] f_numeric_operands_o\n);',1)
        cuts=[dict(module='board1_fixed_elementwise_product_dsp',instance='u_product_dsp',
            output='product_o',replacement='f_numeric_product_i',assumptions=[],
            contract='Shared arbitrary deterministic combinational reply; actual operand equality is a proved wrapper conclusion. Unmodified elaborated child is checked to have no sequential or memory state.')]
    ports=parser.ports(original)
    reset='rst_n'if'rst_n'in ports else'reset_n'
    cancel='clear_i'if'clear_i'in ports else'cancel_i'
    if reset not in ports or cancel not in ports:raise ValueError('Reset/cancellation ABI changed')
    extra=',\n'+',\n'.join(f'    output wire [{width-1}:0] f_state_{name}_o'for name,width in fields.items())+'\n'
    source=original.replace('\n);',extra+');',1)
    source=source.replace('\nendmodule','\n'+'\n'.join('    assign f_state_'+n+'_o='+n+';'for n in fields)+'\nendmodule',1)
    def common(name):return'rst_n'if name==reset else'clear_i'if name==cancel else name
    operands={n:shape for n,(direction,shape)in ports.items()
              if direction=='input' and n.startswith('request_') and n!='request_valid_i'}
    if args.kind=='elementwise':
        operands={n:shape for n,(direction,shape)in ports.items()if direction=='input'and n not in
                  ('clk',reset,cancel,'request_valid_i','result_ready_i','lut_response_valid_i','lut_fault_i','f_numeric_product_i')}
    if args.kind=='argmax':operands={n:shape for n,(d,shape)in ports.items()if d=='input'and n.startswith('row_')and n!='row_valid_i'}
    predicates={n:('row_valid_i'if args.kind=='argmax'else'lut_response_valid_i'if n=='lut_value_i'else'request_valid_i')for n in operands}
    if args.operation_relevant_inputs:
        for n in ('cosine_i','sine_i'):predicates[n]='request_valid_i && operation_i==0'
        if not re.search(r'ST_SILU_WAIT\s*=\s*4\x27d6',original):raise ValueError('SiLU LUT consumption encoding changed')
        predicates['lut_value_i']='lut_response_valid_i && a_state_state_q==6'
    if args.independent_unused_ready:
        for ready,valid in [('response_ready_i','response_valid_o'),('result_ready_i','result_valid_o')]:
            if ready in ports and valid in ports:
                operands[ready]=ports[ready][1];predicates[ready]='a_'+valid
    if not operands:raise ValueError('No request operands inventoried')
    lines=['module scalar_session_isolation(',
        ',\n'.join(['    input wire '+shape+common(n)for n,(direction,shape)in ports.items()if direction=='input']+
                   ['    input wire '+shape+'discarded_'+n for n,shape in operands.items()]),');',
        '    reg f_joined=0; reg f_past_valid=0;',
        '    always @(posedge clk)begin f_past_valid<=1;',
        '        if(!rst_n)f_joined<=0;else if('+('clear_i && model_locked_i && !upstream_fail_closed_i && !a_fail_closed_o && !b_fail_closed_o'if args.kind=='argmax'else'clear_i')+')f_joined<=1;end']
    for copy in ('a','b'):
        for n,(direction,shape)in ports.items():
            if direction=='output':lines.append('    wire '+shape+copy+'_'+n+';')
        for n,width in fields.items():lines.append(f'    wire [{width-1}:0] {copy}_state_{n};')
        connections=['.'+n+'('+ (
            '('+predicates[n]+' ? '+n+' : discarded_'+n+')'if copy=='b'and n in operands else
            common(n)if direction=='input'else copy+'_'+n)+')'for n,(direction,_)in ports.items()]
        connections+=['.f_state_'+n+'_o('+copy+'_state_'+n+')'for n in fields]
        lines.append('    '+top+' u_'+copy+'('+','.join(connections)+');')
    lines+=['    always @*if(rst_n && f_joined)begin']
    lines+=['        if('+relation[n]+')assert(a_state_'+n+'==b_state_'+n+');'for n in fields]
    if args.kind=='normalizer-shift':
        lines+=['        assert(a_state_state_q==0 || a_state_state_q==1 || a_state_state_q==2 || a_state_state_q==3 || a_state_state_q==5);',
                '        assert(a_response_valid_o==(a_state_state_q==5));']
    if args.kind=='argmax':lines+=['        assert(a_state_state_q<=4);']
    lines+=['        assert(a_'+n+'==b_'+n+');'for n,(direction,_)in ports.items()if direction=='output']
    lines+=['    end','    always @(posedge clk)begin',
        '        cover(!f_joined && rst_n && a_state_'+next(iter(fields))+'!=b_state_'+next(iter(fields))+');',
        '        cover(f_joined && rst_n && !clear_i && '+('start_valid_i && a_start_ready_o'if args.kind=='argmax'else'request_valid_i && a_request_ready_o')+');',
        '    end','endmodule']
    wrapper='\n'.join(lines)+'\n'
    files={'production-scalar.sv':raw,'scalar.sv':('`undef FORMAL\n'+source+'\n').encode(),**children,
           'wrapper.sv':wrapper.encode(),'runner.py':Path(__file__).read_bytes(),
           **{p.name:p.read_bytes()for p in preparation.iterdir()if p.is_file()}}
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='scalar_session_isolation',
        reset_constraints='initial\nassume (= [rst_n] true)\nstate 1\nassume (= [rst_n] true)\n',
        constraint_scope_description='No initial hard reset: base/cover rst_n high in states0/1, arbitrary independent native initial state. f_joined starts false. A common CLEAR/cancel edge enables the full-state/output equality theorem. No reset constraints in induction.',
        assertions=wrapper.count('assert('),covers=2,binding=dict(native_join=binding,variant=args.variant,
            production_path=relative,concrete_module=top,complete_sequential_bit_census=True,
            sequential_fields=fields,per_field_current_operation_relation=relation,
            native_sequential_bits=len(state_bits),initial_hard_reset=False,
            operand_coupling_predicates=predicates,arithmetic_product_congruence=args.abstract_combinational_product),cuts=cuts,
        depth=3,induction_depth=1,cover_depth=8,timeout=args.timeout,source_list=['scalar.sv',*children,'wrapper.sv'],
        optimize_full=True,solver_cli={s:['--unroll']for s in ('z3','cvc5')},
        scope='Concrete scalar session isolation. Two copies start with independent arbitrary native sequential states, without initial hard reset. After common CLEAR/cancel every observable output agrees for matched valid future operands until reset. Complete native state census: conventional units compare every sequential bit; the resetless normalizer pipeline compares each data stage only after its current-operation initialization. '+('Elementwise multiplication uses the explicit stateless congruence contract with actual operand equality proved; other arithmetic retained.'if args.abstract_combinational_product else'Actual arithmetic retained.')+' No numerical correctness or whole-device theorem.')


if __name__=='__main__':raise SystemExit(main())
