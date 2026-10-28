"""Prove operation relevance in the actual stateless DSP operand/output muxes.

Retain the full behavioral multiplication. Every irrelevant source input is
independent between copies. The checked native vendor configuration must still
implement the stateless behavioral function; vendor internals are not proved.
"""
import argparse
from pathlib import Path
import re

from run_attention_ownership import HERE, load


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--package',type=Path,required=True)
    ap.add_argument('--kind',choices=('unified','rms'),required=True)
    ap.add_argument('--run',type=Path,required=True)
    args=ap.parse_args()
    binder=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    _,native,bound=binder.binding(args.package,'baseline')
    module={'unified':'board1_unified_projection_head_dynamic_mul_exact','rms':'board1_fixed_elementwise_dsp_lane'}[args.kind]
    paths=[p for p in bound['distributed_inputs']if p.endswith('/'+module+'.sv')]
    if len(paths)!=1:raise ValueError('Native stateless lane not unique')
    relative=paths[0];original=(native/relative).read_bytes()
    matches=re.findall(r'^module '+module+r'\b[\s\S]*?^endmodule',original.decode(),re.M)
    if len(matches)!=1:raise ValueError('Native module body not unique')
    source=matches[0]
    ports=parser.ports(source)
    modes={0:('activation_i','direct_weight_i'),1:('activation_i','coarse_weight0_i','coarse_weight1_i'),
           2:('activation_i','residual_weight0_i','residual_weight1_i'),3:('activation_i','dynamic_operand_i')}
    if args.kind=='rms':modes[4]=('wide_operand_i','scale_operand_i')
    source=source.replace('\n);',',\n    output wire [44:0] f_operands_o\n);',1)
    source=source.replace('\nendmodule','\n    assign f_operands_o={selected_a,selected_b};\nendmodule',1)
    inputs={n:shape for n,(direction,shape)in ports.items()if direction=='input'and n!='mode_i'}
    outputs={n:shape for n,(direction,shape)in ports.items()if direction=='output'}
    outputs['f_operands_o']='[44:0] '
    lines=['module stateless_mode_isolation(input wire clk,rst_n,',
           ',\n'.join('    input wire '+shape+prefix+n for prefix in ('','discarded_')for n,shape in inputs.items()),');']
    for mode,relevant in modes.items():
        for copy in ('a','b'):
            for name,shape in outputs.items():lines.append('    wire '+shape+copy+str(mode)+'_'+name+';')
            con=['.mode_i('+str(3 if args.kind=='rms'else 2)+"'d"+str(mode)+')']
            con+=['.'+n+'('+('discarded_'if copy=='b'and n not in relevant else'')+n+')'for n in inputs]
            con+=['.'+n+'('+copy+str(mode)+'_'+n+')'for n in outputs]
            lines.append('    '+module+' u_'+copy+str(mode)+'('+','.join(con)+');')
        lines+=['    always @*if(rst_n)begin']
        lines+=['        assert(a'+str(mode)+'_'+n+'==b'+str(mode)+'_'+n+');'for n in outputs]
        lines+=['    end']
    lines+=['    always @*cover(rst_n && activation_i!=discarded_activation_i);','endmodule']
    wrapper='\n'.join(lines)+'\n'
    files={'production-stateless.sv':original,'lane.sv':('`undef FORMAL\n'+source+'\n').encode(),
           'wrapper.sv':wrapper.encode(),'runner.py':Path(__file__).read_bytes()}
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='stateless_mode_isolation',reset_constraints='',
        assertions=wrapper.count('assert('),covers=1,binding=dict(native_join=bound,variant='baseline',
            production_path=relative,concrete_module=module,mode_relevant_inputs=modes,
            native_primitive_premise='Native bypass/no-feedback DSP implements the stateless behavioral product'),
        cuts=[],depth=1,induction_depth=1,cover_depth=1,timeout=15,
        source_list=['lane.sv','wrapper.sv'],expected_memories=0,optimize_full=True,
        scope='Actual native combinational lane, operand muxes and behavioral product retained. Independent irrelevant inputs cannot affect selected multiplier operands or any output in each supported mode. Vendor DSP stateless-function correspondence remains a separate explicit premise.')


if __name__=='__main__':raise SystemExit(main())
