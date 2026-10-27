"""Native model address generators with all reachable children retained."""
import argparse
import importlib.util
from pathlib import Path
import re

HERE=Path(__file__).resolve().parent
ROOTS={'group-stream':'board1_fixed_group_ddr_stream','lookup':'board1_context2048_semantic_lookup'}


def load(name,path):
    s=importlib.util.spec_from_file_location('_model_addresses_'+name,path)
    m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m


def derive(package,variant,kind,mutant=None):
    common=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    _,native,bound=common.binding(package,variant);modules={}
    for name in bound['distributed_inputs']:
        if not name.endswith('.sv'):continue
        raw=(native/name).read_bytes()
        for match in re.finditer(r'^module\s+(\w+)\b[\s\S]*?^endmodule\b',raw.decode(),re.M):
            if match[1]in modules and modules[match[1]][0]!=match[0]:raise ValueError('Ambiguous native module')
            modules[match[1]]=(match[0],name,raw)
    selected=set()
    def visit(name):
        if name in selected:return
        selected.add(name);text=modules[name][0]
        for other in modules:
            if other!=name and re.search(r'\b'+re.escape(other)+r'\s+(?:#\([\s\S]*?\)\s+)?u_\w+\s*\(',text):visit(other)
    visit(ROOTS[kind]);files={};origins={};properties=0;cover_count=0
    for name in sorted(selected):
        text,relative,raw=modules[name];files['production-'+name+'.sv']=raw
        origins[name]=dict(native_path=relative,isolated_module_sha256=common.sha(text.encode()),source_sha256=common.sha(raw))
        monitor_name=('group-stream-address-monitor.inc.sv'if name==ROOTS['group-stream']else
            'metadata-address-monitor.inc.sv'if name=='board1_fixed_projection_metadata_reader'else
            'lookup-address-monitor.inc.sv'if name==ROOTS['lookup']else None)
        if monitor_name:
            monitor=(HERE/monitor_name).read_text();files[monitor_name]=monitor.encode()
            properties+=monitor.count('assert(');cover_count+=monitor.count('cover(')
            text=text.replace('\nendmodule','\n'+monitor+'\nendmodule',1)
        if mutant and name==ROOTS[kind]:
            before,after=("weight_base_word_q <=\n                                    ADDR_W'(descriptor_word_base_wide);",
                "weight_base_word_q <=\n                                    ADDR_W'(descriptor_word_base_wide)+19'd1;")if kind=='group-stream'else(
                'word_index_q <= derived_word_index;', "word_index_q <= ADDR_W'(227062);")
            if text.count(before)!=1:raise ValueError('Native address mutation site changed')
            text=text.replace(before,after,1)
        files[name+'.sv']=b'`undef FORMAL\n'+text.encode()+b'\n'
    table=parser.ports(modules[ROOTS[kind]][0])
    wrapper='`default_nettype none\nmodule native_model_addresses (\n'+',\n'.join(
        '    '+direction+' wire '+shape+name for name,(direction,shape)in table.items())+'\n);\n'
    wrapper+='    '+ROOTS[kind]+' #(.ADDR_W(19)) u_native (\n'+',\n'.join('        .'+n+'('+n+')'for n in table)+'\n    );\nendmodule\n'
    files['wrapper.sv']=wrapper.encode();files['runner.py']=Path(__file__).read_bytes();files['parser.py']=Path(parser.__file__).read_bytes()
    return files,dict(native_join=bound,variant=variant,kind=kind,isolated_native_modules=origins,
        all_reachable_children_retained=True,native_address_width=19),properties,cover_count


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--package',type=Path,required=True)
    p.add_argument('--run',type=Path,required=True);p.add_argument('--variant',default='kv-protected')
    p.add_argument('--kind',choices=tuple(ROOTS),required=True);p.add_argument('--mutant',action='store_true')
    p.add_argument('--timeout',type=int,default=60);args=p.parse_args()
    files,binding,count,covers=derive(args.package,args.variant,args.kind,args.mutant)
    engine=load('engine',HERE/'engine.py')
    return engine.check(args.run,files,top='native_model_addresses',
        reset_constraints='initial\nassume (= [reset_n] false)\nstate 1\nassume (= [reset_n] false)\n',
        assertions=count,covers=covers,binding=binding,cuts=[],depth=8,induction_depth=3,
        cover_depth=16,timeout=args.timeout,mutant='wrong-model-address'if args.mutant else None,
        source_list=[n+'.sv'for n in binding['isolated_native_modules']]+['wrapper.sv'],
        map_literal_roms=True,optimize_full=True,solver_cli={s:['--unroll']for s in('z3','cvc5')},
        scope='Actual native model address generators and every reachable child, with arbitrary private descriptors, model replies and backpressure. Fixed region/descriptor address provenance and no model write interface. Numerical correctness, image authenticity and public-to-private descriptor ownership are supplied by separate proofs.')


if __name__=='__main__':raise SystemExit(main())
