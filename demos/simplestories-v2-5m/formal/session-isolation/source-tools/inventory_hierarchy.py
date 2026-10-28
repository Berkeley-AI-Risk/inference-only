"""Inventory actual instantiated custom RTL state at native top parameters.

This is an elaboration/census artifact, not a formal safety proof. Omitted
vendor IP is listed explicitly as unresolved leaf instances. Do not turn an
incomplete hierarchy into a whole-device state-coverage claim.
"""
import argparse
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

from run_attention_ownership import HERE, load
from run_exp_session import elaborate_initializer


def lower_constant_aes_key_function(text):
    """Unroll the exact constant key function; leave runtime AES unchanged."""
    import re
    match=re.search(r'    function automatic \[1919:0\] expand\(input \[255:0\] key\);[\s\S]*?    endfunction',text)
    if match is None:raise ValueError('Native constant AES key function changed')
    expected='''function automatic [1919:0] expand(input [255:0] key);
        reg [31:0] w [0:59]; reg [31:0] t; reg [7:0] rc; integer i;
        begin rc=8'h01;
            for(i=0;i<8;i=i+1) w[i]=key[255-i*32 -: 32];
            for(i=8;i<60;i=i+1) begin t=w[i-1];
                if(i%8==0) begin t=subword({t[23:0],t[31:24]}) ^ {rc,24'd0}; rc=xt(rc);
                end else if(i%8==4) t=subword(t);
                w[i]=w[i-8] ^ t; end
            for(i=0;i<60;i=i+1) expand[1919-i*32 -: 32]=w[i];
        end endfunction'''
    if re.sub(r'\s+','',match[0])!=re.sub(r'\s+','',expected):raise ValueError('Unreviewed AES initializer syntax')
    calls=re.findall(r'localparam \[1919:0\] ROUND_KEYS[01]?=expand\(KEY[01]?\);',text)
    if len(calls)not in(1,2)or len(re.findall(r'\bexpand\(',text))!=len(calls)+1:
        raise ValueError('Key expansion is no longer limited to constant localparams')
    rows=['    function automatic [1919:0] expand(input [255:0] key);',
          '        reg [31:0] '+','.join('w'+str(i)for i in range(60))+';',
          "        reg [31:0] t;reg [7:0] rc;begin rc=8'h01;"]
    for i in range(8):rows.append(f'        w{i}=key[{255-i*32} -:32];')
    for i in range(8,60):
        rows.append(f'        t=w{i-1};')
        if i%8==0:rows.append("        t=subword({t[23:0],t[31:24]}) ^ {rc,24'd0};rc=xt(rc);")
        elif i%8==4:rows.append('        t=subword(t);')
        rows.append(f'        w{i}=w{i-8} ^ t;')
    rows+=['        expand={'+','.join('w'+str(i)for i in range(60))+'};','        end','    endfunction']
    lowered='\n'.join(rows)
    return text[:match.start()]+lowered+text[match.end():],dict(original=match[0],lowered=lowered,
        method='Exact checked constant loop unrolling and local-array scalarization; no runtime logic changed')


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--package',type=Path,required=True)
    ap.add_argument('--variant',default='baseline')
    ap.add_argument('--out',type=Path,required=True)
    args=ap.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    binder=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    _,native,binding=binder.binding(args.package,args.variant)
    for relative in binding['distributed_inputs']:
        target=out/relative;target.parent.mkdir(parents=True,exist_ok=True)
        target.write_bytes((native/relative).read_bytes())
    project=out/'project'
    import re
    rom=project/'fpga/token_only_model0_ddr_board1/fixed_attention0/rtl/board1_fixed_attention_exp_lut_sync.sv'
    text=rom.read_text();asset=re.findall(r'parameter FILE = "([^"]+)"',text)
    if len(asset)!=1:raise ValueError('Exponential ROM asset changed')
    lowered,initialization=elaborate_initializer(text,(project/asset[0]).read_bytes())
    rom.write_text(lowered)
    aes_elaboration={}
    for name in ('tang_private_aes256_fixed2.sv','tang_private_aes256.sv'):
        aes=project/name
        if aes.is_file():
            lowered,aes_elaboration[name]=lower_constant_aes_key_function(aes.read_text());aes.write_text(lowered)
    tree=ET.parse(project/'product.gprj')
    files=[r.attrib['path']for r in tree.findall('.//File')if r.attrib.get('enable')=='1'and r.attrib['type']=='file.verilog']
    omitted=[n for n in files if not(project/n).is_file()]
    if set('project/'+n for n in omitted)!=set(binding['omitted_vendor_inputs']):
        raise ValueError('Omitted native compile inputs differ from source binding')
    files=[n for n in files if(project/n).is_file()]
    top='board1_fixed_shared_product_top'
    commands='read_verilog -sv -nosynthesis -D SYNTHESIS -defer '+' '.join(files)+'\n'
    # Remove only the frontend always_comb diagnostic annotation. This lets
    # PROC represent unused procedural loop temporaries as dead latches;
    # OPT_CLEAN then removes them. Actual retained latches are inventoried.
    # No transition or assignment is changed, and this remains census-only.
    commands+='hierarchy -top '+top+'\nsetattr -unset always_comb p:*\nproc\nopt_clean\nwrite_json ../hierarchy.json\nwrite_rtlil ../hierarchy.il\n'
    (project/'inventory.ys').write_text(commands)
    (out/'INPUTS.json').write_text(json.dumps(dict(native_join=binding,variant=args.variant,
        compile_files=files,omitted_vendor_files=omitted,initializer_elaboration=initialization,
        constant_aes_key_function_elaboration=aes_elaboration,
        frontend_annotation_policy='always_comb diagnostic attribute removed before PROC; all assignments retained, dead logic cleaned and remaining latches inventoried; census only',
        runner_sha256=binder.sha(Path(__file__).read_bytes()),proof=False),indent=2)+'\n')
    with(out/'yosys.log').open('w')as log:
        cp=subprocess.run(['yosys','-Q','inventory.ys'],cwd=project,stdout=log,stderr=subprocess.STDOUT,timeout=90)
    if cp.returncode:raise ValueError('Native custom hierarchy/state inventory failed; inspect retained log')
    graph=json.loads((out/'hierarchy.json').read_text())['modules']
    rows=[];unresolved=[];stack=[]
    def visit(module,path):
        if module in stack:raise ValueError('Recursive hardware hierarchy')
        stack.append(module);m=graph[module]
        # PROC is exact; OPT_CLEAN removes dead frontend temporary state.
        state={}
        for name,c in m['cells'].items():
            kind=c['type']
            if kind in graph:
                visit(kind,path+'/'+name)
            elif kind.startswith('$'):
                if re.match(r'^\$(?:a?dff|sdff|dffe|adffe|sdffe|dlatch|adlatch)',kind):
                    q={b for b in c['connections']['Q']if isinstance(b,int)}
                    state[name]=dict(type=kind,bits=len(q),src=c.get('attributes',{}).get('src'))
            else:unresolved.append(dict(path=path+'/'+name,type=kind,src=c.get('attributes',{}).get('src')))
        arrays={n:dict(width=r['width'],size=r['size'],src=r.get('attributes',{}).get('src'))
                for n,r in m.get('memories',{}).items()}
        rows.append(dict(path=path,module=module,original_module=m.get('attributes',{}).get('hdlname'),
            sequential_cells=state,declared_memory_objects=arrays,
            memory_port_cells={n:dict(type=c['type'],parameters=c['parameters'])
                for n,c in m['cells'].items()if c['type'].startswith('$mem')}))
        stack.pop()
    visit(top,top)
    result=dict(elaboration_passed=True,formal_proof=False,top=top,variant=args.variant,
        instantiated_custom_modules=len(rows),unresolved_leaf_instances=unresolved,instances=rows,
        hierarchy_json_sha256=binder.sha((out/'hierarchy.json').read_bytes()),
        hierarchy_rtlil_sha256=binder.sha((out/'hierarchy.il').read_bytes()),
        input_sha256=binder.sha((out/'INPUTS.json').read_bytes()),
        log_sha256=binder.sha((out/'yosys.log').read_bytes()))
    (out/'CENSUS.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps({k:v for k,v in result.items()if k not in ('instances','unresolved_leaf_instances')}))
    from collections import Counter
    print('Unresolved leaf types/counts:',dict(Counter(r['type']for r in unresolved)))


if __name__=='__main__':main()
