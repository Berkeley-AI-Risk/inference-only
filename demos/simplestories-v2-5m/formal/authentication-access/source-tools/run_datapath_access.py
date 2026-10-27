"""Actual semantic scheduler with complete child-output overapproximations.

The production controller, arbitration, operand muxes and write gates remain.
Each complete child output is a free input; no input or numerical-result
promise is made. Native ADDR_W=19 is selected by an explicit wrapper.
"""
import argparse
import importlib.util
from pathlib import Path
import re

HERE=Path(__file__).resolve().parent
REL='project/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_semantic_datapath.sv'
TOP='board1_context2048_semantic_datapath'


def load(name,path):
    s=importlib.util.spec_from_file_location('_dp_access_'+name,path)
    m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m


def derive(package,variant,mutant=None):
    common=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    _,native,bound=common.binding(package,variant)
    original=(native/REL).read_bytes();source=original.decode();files={'production-datapath.sv':original}
    modules={}
    for name in bound['distributed_inputs']:
        if not name.endswith('.sv'):continue
        raw=(native/name).read_bytes()
        for match in re.finditer(r'^module\s+(\w+)\b[\s\S]*?^endmodule\b',raw.decode(),re.M):
            if match[1] in modules and modules[match[1]][0]!=match[0]:
                raise ValueError('Ambiguous production module '+match[1])
            modules[match[1]]=(match[0],name,raw)
    additions=[];cuts=[];instances=[]
    for match in re.finditer(r'^    (board1_\w+)\s+(?:#\([^\n]*\)\s+)?(u_\w+)\s*\(',source,re.M):
        module,name=match[1],match[2];start=match.start();cursor=match.end();depth=1
        while depth:
            depth+=(source[cursor]=='(')-(source[cursor]==')');cursor+=1
        if source[cursor]!=';':raise ValueError('Instance terminator changed')
        instance=source[start:cursor+1];child,relative,raw=modules[module]
        files['production-child-'+module+'.sv']=raw
        rows=[]
        for port,(direction,shape) in parser.ports(child).items():
            if direction!='output':continue
            expressions=re.findall(r'\.'+re.escape(port)+r'\s*\(([^()]*)\)',instance)
            if len(expressions)!=1:raise ValueError('Child output binding changed: '+name+'.'+port)
            expression=expressions[0].strip()
            if not expression:continue
            if not re.fullmatch(r'\w+',expression):raise ValueError('Output is no longer a simple net')
            free='f_child_'+name+'_'+port
            additions.append('    input wire '+shape+free)
            rows.append('    assign '+expression+' = '+free+';')
            cuts.append(dict(instance=name,module=module,port=port,expression=expression,shape=shape,
                replacement=free,source=relative,assumptions=[]))
        instances.append((instance,'\n'.join(rows)))
    if len(instances)!=17:raise ValueError('Native child census changed: '+str(len(instances)))
    for before,after in instances:
        if source.count(before)!=1:raise ValueError('Instance is not unique')
        source=source.replace(before,after,1)
    ports=',\n'+',\n'.join(additions)
    source=source.replace('\n);',ports+'\n);',1)
    if mutant:
        before,after=("wire [3:0] projection_job = projection_is_head ? 4'd7 :", "wire [3:0] projection_job = projection_is_head ? 4'd6 :")
        if source.count(before)!=1:raise ValueError('Head descriptor mutation site changed')
        source=source.replace(before,after,1)
    monitor=(HERE/'datapath-access-monitor.inc.sv').read_text()
    source=source.replace('\nendmodule','\n'+monitor+'\nendmodule',1)
    files['datapath.sv']=b'`undef FORMAL\n'+source.encode();files['monitor.inc.sv']=monitor.encode()
    native_ports=parser.ports(source)
    wrapper='`default_nettype none\nmodule native_datapath_access (\n'+',\n'.join(
        '    '+direction+' wire '+shape+name for name,(direction,shape)in native_ports.items())+'\n);\n'
    wrapper+='    '+TOP+' #(.ADDR_W(19)) u_native (\n'+',\n'.join('        .'+n+'('+n+')'for n in native_ports)+'\n    );\nendmodule\n'
    files['wrapper.sv']=wrapper.encode()
    files['runner.py']=Path(__file__).read_bytes()
    files['binding_helper.py']=(HERE.parent/'formal-assurance/run_handoff.py').read_bytes()
    files['parser.py']=Path(parser.__file__).read_bytes()
    return files,dict(native_join=bound,variant=variant,production_path=REL,native_address_width=19,
        all_declared_private_and_child_inputs_unrestricted=True,child_instances=17),cuts,monitor


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--package',type=Path,required=True)
    ap.add_argument('--run',type=Path,required=True);ap.add_argument('--variant',default='kv-protected')
    ap.add_argument('--mutant',choices=('wrong-head-job',));ap.add_argument('--timeout',type=int,default=60)
    args=ap.parse_args();files,binding,cuts,monitor=derive(args.package,args.variant,args.mutant)
    engine=load('engine',HERE/'engine.py')
    return engine.check(args.run,files,top='native_datapath_access',reset_constraints='initial\nassume (= [rst_n] false)\nstate 1\nassume (= [rst_n] false)\n',
        assertions=monitor.count('assert('),covers=2,binding=binding,cuts=cuts,depth=6,induction_depth=3,
        cover_depth=12,timeout=args.timeout,mutant=args.mutant,source_list=['datapath.sv','wrapper.sv'],
        optimize_full=True,solver_cli={s:['--unroll']for s in('z3','cvc5')},
        scope='Actual native semantic scheduler, fixed descriptor/operand muxes, guarded writes and model-read owner arbitration, with every whole child output unrestricted. No numerical-child correctness or RAM initialization/data-history theorem is inferred from this controller proof. Public-to-private wiring, child address generators and protected K/V authentication/capture are separate source-bound compositions.')


if __name__=='__main__':raise SystemExit(main())
