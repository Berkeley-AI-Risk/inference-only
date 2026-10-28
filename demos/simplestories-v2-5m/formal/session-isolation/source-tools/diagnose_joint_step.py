"""Record an uncredited joint-induction countermodel, including native state."""
import argparse
import json
from pathlib import Path
import re
import subprocess

from join_parent_conclusions import checked_query, query_templates, template_text
from record_progress import sha


def sexprs(text):
    tokens=re.findall(r'\(|\)|\|[^|]*\||[^\s()]+',text);stack=[];roots=[]
    for token in tokens:
        if token=='(':
            row=[]
            if stack:stack[-1].append(row)
            else:roots.append(row)
            stack.append(row)
        elif token==')':
            if not stack:raise ValueError('Unbalanced solver reply')
            stack.pop()
        elif stack:stack[-1].append(token)
        else:roots.append(token)
    if stack:raise ValueError('Incomplete solver reply')
    return roots


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--run',type=Path,required=True);ap.add_argument('--part',type=Path,required=True)
    ap.add_argument('--out',type=Path,required=True);ap.add_argument('--timeout',type=int,default=90)
    ap.add_argument('--index',type=int,help='Inspect one actual partition conclusion instead of the joint step.')
    ap.add_argument('--signals',nargs='+',help='Exact recorded native/observer signal names to inspect.')
    args=ap.parse_args();run=args.run.resolve();part=args.part.resolve();out=args.out.resolve()
    out.mkdir(parents=True,exist_ok=False)
    inp=json.loads((run/'INPUTS.json').read_text());p=json.loads((part/'FINISHED.json').read_text())
    top=inp['top'];count=inp['assertion_cells'];k=p['depth']
    model=(run/'design.smt2'if p.get('state_encoding')=='native'else part/'model.smt2').read_text()
    label='joint-induction'if args.index is None else'induction-'+str(args.index).zfill(3)
    query=checked_query(part/(label+'.smt2'),p['results'][label]).decode()
    if query!=template_text(query_templates(model,p,top,count,compact=True)[label]):
        raise ValueError('Diagnostic query differs from the actual recorded joint step')
    properties=[f'(|{top}_a {i}| s{k})'for i in range(count)]
    names=re.findall(r'\(define-fun \|'+top+r'_n ([^|]+)\|',model)
    selected=args.signals if args.signals is not None else[n for n in names if n.startswith(('a_f_state','b_f_state','a_f_input_tile','b_f_input_tile',
        'a_tile0_f_','b_tile0_f_','u_a_tile0.f_','u_b_tile0.f_'))or n in('clear_i','rst_n','f_joined','model_locked_i','upstream_fail_closed_i')]
    if any(n not in names for n in selected):raise ValueError('Requested diagnostic signal is not recorded')
    calls={f'(|{top}_n {name}| s{i})':f's{i}.{name}'for i in range(k+1)for name in selected}
    query+='\n(get-value ('+' '.join(properties+list(calls))+'))\n'
    (out/'query.smt2').write_text(query)
    command=['z3','-memory:1024','-T:'+str(args.timeout),'-smt2',str(out/'query.smt2')]
    with(out/'reply.log').open('w')as log:
        cp=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=args.timeout+10)
    raw=(out/'reply.log').read_text();roots=sexprs(raw);values={};bad=[]
    for root in roots:
        if not isinstance(root,list):continue
        for pair in root:
            if not isinstance(pair,list)or len(pair)!=2 or not isinstance(pair[0],list):continue
            call,value=pair
            if len(call)!=2:continue
            match=re.fullmatch(r'\|'+top+r'_a (\d+)\|',call[0])
            if match and value=='false':bad.append(int(match[1]))
            else:
                key='('+call[0]+' '+call[1]+')'
                if key in calls:values[calls[key]]=value
    metadata={int(a):b for a,b in re.findall(r'^; yosys-smt2-assert (\d+) (.*)$',(run/'design.smt2').read_text(),re.M)}
    result=dict(credited=False,exit=cp.returncode,assertion_count=count,depth=k,query_label=label,
        violated={i:metadata[i]for i in bad},state_values=values,command=command,
        source_inputs_sha256=sha((run/'INPUTS.json').read_bytes()),query_sha256=sha(query.encode()),
        reply_sha256=sha(raw.encode()),runner_sha256=sha(Path(__file__).read_bytes()))
    (out/'runner.py').write_bytes(Path(__file__).read_bytes())
    (out/'FINISHED.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(violated=result['violated'],state_values=len(values),credited=False)))


if __name__=='__main__':main()
