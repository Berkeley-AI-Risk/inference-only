"""Actual projection engine CLEAR overwrites all declared sequential state.

The complete DSP-array replies are unrestricted. No arithmetic result premise
is needed for this cancellation/storage guarantee.
"""
import argparse
from pathlib import Path
import re

from run_attention_ownership import HERE, load
from run_service_memory import boundaries

REL='project/fpga/token_only_model0_ddr_board1/shared_projection_scale0/rtl/board1_shared_projection_scale_engine.sv'
TOP='board1_shared_projection_scale_engine'
SCALARS=['state_q','layer_q','job_q','group_q','columns_q','valid_lanes_q','activation_exponent_q',
         'metadata_count_q','column_q','chunk_q','emit_lane_q','fail_q']
ARRAYS={'accumulator_q':64,'result_q':64,'low_product_q':16,'multiplier_q':64,'source_exponent_q':64}


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
    original=(native/REL).read_bytes();found=re.findall(r'^module '+TOP+r'\b[\s\S]*?^endmodule',original.decode(),re.M)
    if len(found)!=1:raise ValueError('Native engine not unique')
    definitions={}
    for name in binding['distributed_inputs']:
        if not name.endswith('.sv'):continue
        raw=(native/name).read_bytes()
        for m in re.finditer(r'^module\s+(\w+)\b[\s\S]*?^endmodule',raw.decode(),re.M):definitions[m[1]]=(m[0],name,raw)
    source,files,cuts,count=boundaries(found[0],definitions,parser)
    if count!=1:raise ValueError('Native array census changed')
    # Check the assignment census against all three actual sequential blocks
    # (the source currently has one), excluding simulation-only observers.
    blocks=[]
    for m in re.finditer(r'    always_ff @\(posedge clk or negedge reset_n\)',found[0]):
        blocks.append(found[0][m.end():found[0].index('\n`ifdef FORMAL',m.end())])
    if len(blocks)!=1:raise ValueError('Sequential source census changed')
    functional=found[0].split('\n`ifdef FORMAL',1)[0]
    if len(re.findall(r'\b(?:always_ff|always)\s*@\([^)]*(?:posedge|negedge)',functional))!=1:
        raise ValueError('Additional sequential process requires storage coverage review')
    assigned=set(re.findall(r'\b(\w+)\s*(?:\[[^\]\n]+\])?\s*<=',blocks[0]))
    if assigned!=set(SCALARS)|set(ARRAYS):raise ValueError('Uncovered sequential variable '+str(assigned))
    all_zero=' && '.join([n+"=='0"for n in SCALARS]+[
        n+'['+str(i)+"]=='0"for n,size in ARRAYS.items()for i in range(size)])
    monitor='''
    reg f_past_valid=0;
    always @(posedge clk)begin
        f_past_valid<=1;
        if(f_past_valid && $past(reset_n && clear_i))begin
'''+''.join('            assert('+n+"=='0);\n"for n in SCALARS)+''.join(
        '            assert('+n+'['+str(i)+"]=='0);\n"for n,size in ARRAYS.items()for i in range(size))+'''
        end
        cover(f_past_valid && reset_n && clear_i && multiplier_q[0]!=0);
    end
'''
    source=source.replace('\nendmodule','\n'+monitor+'\nendmodule',1)
    ports=parser.ports(source)
    wrapper='module native_projection_clear(\n'+',\n'.join('    '+direction+' wire '+shape+('rst_n'if n=='reset_n'else n)
        for n,(direction,shape)in ports.items())+'\n);\n'
    wrapper+='    '+TOP+' u_native('+','.join('.'+n+'('+('rst_n'if n=='reset_n'else n)+')'for n in ports)+');\nendmodule\n'
    files.update({'production-engine.sv':original,'engine.sv':('`undef FORMAL\n'+source+'\n').encode(),
                  'wrapper.sv':wrapper.encode(),'monitor.inc.sv':monitor.encode(),'runner.py':Path(__file__).read_bytes()})
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='native_projection_clear',
        reset_constraints='initial\nassume (= [rst_n] false)\nstate 1\nassume (= [rst_n] false)\n',
        assertions=monitor.count('assert('),covers=1,binding=dict(native_join=binding,variant=args.variant,
            production_path=REL,sequential_variables=sorted(assigned),complete_sequential_assignment_census=True),cuts=cuts,
        depth=3,induction_depth=2,cover_depth=10,timeout=args.timeout,map_literal_roms=True,
        source_list=['engine.sv','wrapper.sv'],optimize_full=True,
        solver_cli={s:['--unroll']for s in ('z3','cvc5')},
        scope='All declared sequential storage in the actual projection scale engine is canonical zero after a CLEAR edge, including all64 accumulators/results/multipliers/exponents and16 low-product registers. Complete DSP-array outputs are arbitrary. This is digital CLEAR convergence for this component, not physical erasure or whole-device session isolation.')


if __name__=='__main__':raise SystemExit(main())
