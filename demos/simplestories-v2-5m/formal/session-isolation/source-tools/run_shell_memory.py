"""Actual token-shell tape and vector-RAM ownership/history."""
import argparse
from pathlib import Path
import re

from run_attention_ownership import HERE, load
from run_service_memory import boundaries

REL='project/fpga/token_only_model0_ddr_board1/context2048_token_machine2/rtl/board1_context2048_token_shell.sv'
TOP='board1_context2048_token_shell'


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--package',type=Path,required=True)
    ap.add_argument('--variant',default='baseline')
    ap.add_argument('--run',type=Path,required=True)
    ap.add_argument('--timeout',type=int,default=45)
    ap.add_argument('--clear-entry',action='store_true')
    ap.add_argument('--primary-only',action='store_true')
    ap.add_argument('--solver-memory-mib',type=int,default=0)
    args=ap.parse_args()
    if args.solver_memory_mib and(not args.primary_only or args.solver_memory_mib<1):
        raise ValueError('A positive Z3 memory cap requires primary-only mode')
    binder=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    _,native,binding=binder.binding(args.package,args.variant)
    original=(native/REL).read_bytes();found=re.findall(r'^module '+TOP+r'\b[\s\S]*?^endmodule',original.decode(),re.M)
    if len(found)!=1:raise ValueError('Native shell not unique')
    definitions={}
    for name in binding['distributed_inputs']:
        if not name.endswith('.sv'):continue
        raw=(native/name).read_bytes()
        for m in re.finditer(r'^module\s+(\w+)\b[\s\S]*?^endmodule',raw.decode(),re.M):definitions[m[1]]=(m[0],name,raw)
    source,files,cuts,count=boundaries(found[0],definitions,parser)
    if count!=3:raise ValueError('Native shell child census changed '+str(count))
    reference=binder.model_package(args.package)/'reference/baseline-formal-354/formal/token-shell'
    old_monitor=(reference/'control_monitor.inc.sv').read_text()+'\n'+(reference/'tape_monitor.inc.sv').read_text()
    if old_monitor.count('assert(')!=48:raise ValueError('Preserved source monitor changed')
    monitor=old_monitor+'\n'+(HERE/'shell-vector-monitor.inc.sv').read_text()
    if args.clear_entry:
        # Physical tape/vector RAMs and retained register payloads are not
        # reset or constrained. A real CLEAR edge starts the logical history.
        # Old boot-only initial checks remain gated by the completed edge.
        monitor=monitor.replace('if (rst_n)', 'if (rst_n && f_completed_clear)')
        monitor=monitor.replace('if(rst_n && !clear_i)',
            'if(rst_n && !clear_i && f_completed_clear)')
        monitor+='''
    reg f_completed_clear=0;
    always @(posedge clk)if(!rst_n)f_completed_clear<=0;
        else if(clear_i)f_completed_clear<=1;
'''
    source=source.replace('\nendmodule','\n'+monitor+'\nendmodule',1)
    ports=parser.ports(source)
    wrapper='module native_shell_memory(\n'+',\n'.join('    '+direction+' wire '+shape+n for n,(direction,shape)in ports.items())+'\n);\n'
    wrapper+='    '+TOP+' #(.ADDR_W(19)) u_native('+','.join('.'+n+'('+n+')'for n in ports)+');\nendmodule\n'
    files.update({'production-shell.sv':original,'shell.sv':('`undef FORMAL\n'+source+'\n').encode(),
                  'wrapper.sv':wrapper.encode(),'monitor.inc.sv':monitor.encode(),'runner.py':Path(__file__).read_bytes()})
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='native_shell_memory',
        reset_constraints=('initial\nassume (= [rst_n] true)\nstate 1\nassume (= [rst_n] true)\n'if args.clear_entry else
            'initial\nassume (= [rst_n] false)\nstate 1\nassume (= [rst_n] false)\n'),
        assertions=monitor.count('assert('),covers=1,observer_constants=2,expected_memories=4,
        binding=dict(native_join=binding,variant=args.variant,production_path=REL,
            initial_hard_reset=not args.clear_entry,clear_starts_logical_history=args.clear_entry),cuts=cuts,
        depth=4,induction_depth=4,cover_depth=8,timeout=args.timeout,
        source_list=['shell.sv','wrapper.sv'],optimize_full=True,
        primary_only=args.primary_only,
        solver_cli={s:['--unroll']+(['-S','-memory:'+str(args.solver_memory_mib)]if s=='z3'and args.solver_memory_mib else[])for s in ('z3','cvc5')},
        scope='Actual native token shell, all2049 tape words and all three256-word vector RAMs, with native read/write history and epoch ownership. Complete embedding/RMS/selection child outputs unrestricted. This establishes shell storage/access safety, not shared-child numerical or whole-session equivalence.')


if __name__=='__main__':raise SystemExit(main())
