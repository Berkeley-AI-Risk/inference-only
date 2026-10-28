"""Concrete healthy-CLEAR isolation of the attention exponent-prefix summary."""
import argparse
from pathlib import Path
import re

from run_attention_ownership import HERE, load

REL='project/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_attention_memories.sv'
TOP='board1_attention_value_fit_prefix'


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--package',type=Path,required=True)
    ap.add_argument('--variant',default='baseline')
    ap.add_argument('--run',type=Path,required=True)
    ap.add_argument('--timeout',type=int,default=45)
    args=ap.parse_args()
    binder=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    _,native,binding=binder.binding(args.package,args.variant)
    raw=(native/REL).read_bytes();matches=re.findall(r'^module '+TOP+r'\b[\s\S]*?^endmodule',raw.decode(),re.M)
    if len(matches)!=1:raise ValueError('Prefix module changed')
    original=matches[0];ports=parser.ports(original)
    fields={
        'staging_q':('', '1'),'pending_valid_q':('', '1'),'consumed_q':('', '1'),
        'lock_seen_q':('', '1'),'next_coordinate_q':('[6:0] ','1'),
        'pending_layer_q':('[2:0] ','staging_q || pending_valid_q'),
        'pending_position_q':('[10:0] ','staging_q || pending_valid_q'),
        'pending_exponent_q':('[7:0] ','staging_q || pending_valid_q'),
    }
    for layer in range(6):
        fields[f'prefix_q[{layer}]']=('[11:0] ','1')
        for head in range(2):
            fields[f'maximum_q[{layer}][{head}]']=('[7:0] ','1')
            fields[f'nonzero_q[{layer}][{head}]']=('', '1')
    for head in range(2):
        fields[f'pending_max_q[{head}]']=('[7:0] ','staging_q || pending_valid_q')
        fields[f'pending_nonzero_q[{head}]']=('', 'staging_q || pending_valid_q')
    def name(field):return field.replace('[','_').replace(']','')
    source=original.replace('\n);',',\n'+',\n'.join('    output wire '+shape+'f_state_'+name(n)+'_o'
        for n,(shape,_)in fields.items())+'\n);',1)
    source=source.replace('\nendmodule','\n'+'\n'.join('    assign f_state_'+name(n)+'_o='+n+';'for n in fields)+'\nendmodule',1)
    operands={'value_i':'stage_value_valid_i','coordinate_i':'stage_value_valid_i',
              'exponent_i':'stage_begin_i || stage_value_valid_i'}
    lines=['module prefix_session_isolation(',
        ',\n'.join(['    input wire '+shape+n for n,(direction,shape)in ports.items()if direction=='input']+
                   ['    input wire '+ports[n][1]+'discarded_'+n for n in operands]),');',
        '    reg f_joined=0;',
        '    always @(posedge clk)if(!rst_n)f_joined<=0;else if(clear_i && model_lock_i && !upstream_fault_i && !a_fault_o && !b_fault_o)f_joined<=1;']
    for copy in ('a','b'):
        for n,(direction,shape)in ports.items():
            if direction=='output':lines.append('    wire '+shape+copy+'_'+n+';')
        for n,(shape,_)in fields.items():lines.append('    wire '+shape+copy+'_'+name(n)+';')
        connections=['.'+n+'('+ ('(('+operands[n]+') ? '+n+' : discarded_'+n+')'if copy=='b'and n in operands else
                                n if direction=='input'else copy+'_'+n)+')'for n,(direction,_)in ports.items()]
        connections+=['.f_state_'+name(n)+'_o('+copy+'_'+name(n)+')'for n in fields]
        lines+=['    '+TOP+' u_'+copy+'('+','.join(connections)+');']
    lines+=['    always @*if(rst_n && f_joined)begin',
            '        assert(a_read_valid_o==b_read_valid_o);assert(a_fault_o==b_fault_o);']
    for n,(_,predicate)in fields.items():
        predicate=predicate.replace('staging_q','a_staging_q').replace('pending_valid_q','a_pending_valid_q')
        lines+=['        if('+predicate+')assert(a_'+name(n)+'==b_'+name(n)+');']
    lines+=['        if(a_read_valid_o)begin assert(a_exponent0_o==b_exponent0_o);assert(a_exponent1_o==b_exponent1_o);end',
            '    end','    always @(posedge clk)begin',
            '        cover(!f_joined && a_pending_position_q!=b_pending_position_q);',
            '        cover(f_joined && rst_n && !clear_i && a_staging_q && !a_fault_o);',
            '    end','endmodule']
    wrapper='\n'.join(lines)+'\n'
    files={'production-memories.sv':raw,'prefix.sv':('`undef FORMAL\n'+source+'\n').encode(),
           'wrapper.sv':wrapper.encode(),'runner.py':Path(__file__).read_bytes()}
    engine=load('engine',HERE/'proof_engine.py')
    initial='initial\nassume (= [rst_n] true)\nassume (= [clear_i] true)\nassume (= [model_lock_i] true)\nassume (= [upstream_fault_i] false)\nassume (= [a_fault_o] false)\nassume (= [b_fault_o] false)\nstate 1\nassume (= [rst_n] true)\nassume (= [clear_i] true)\nassume (= [model_lock_i] true)\nassume (= [upstream_fault_i] false)\n'
    return engine.check(args.run,files,top='prefix_session_isolation',reset_constraints=initial,
        constraint_scope_description='Healthy CLEAR entry, no initial hard reset: arbitrary independent old states, both sticky faults initially false; rst_n/model_lock high and clear high with upstream fault low in states0/1. Inputs unrestricted afterwards and in induction. Pending invalid metadata may differ and is compared only once newly owned.',
        assertions=wrapper.count('assert('),covers=2,binding=dict(native_join=binding,variant=args.variant,
            production_path=REL,concrete_module=TOP,healthy_entry_required=True,initial_hard_reset=False,
            valid_operand_coupling=operands),cuts=[],
        depth=3,induction_depth=1,cover_depth=8,timeout=args.timeout,
        source_list=['prefix.sv','wrapper.sv'],optimize_full=True,
        solver_cli={s:['--unroll']for s in ('z3','cvc5')},
        scope='Actual prefix-summary healthy CLEAR isolation: old staging/committed statistics and invalid metadata cannot affect future fault/admission or owned exponent replies under matched current inputs. Sticky faults require a healthy entry and are not cleared by this theorem. Actual arithmetic and all arrays retained. No whole-device theorem.')


if __name__=='__main__':raise SystemExit(main())
