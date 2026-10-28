"""Transport a checked parent proof through nondriving port instrumentation.

Removing only added output ports, assign taps, observer wires/connections and
assertions must reproduce both original Verilog files byte for byte. Thus the
old transition relation and invariant proof apply unchanged. New interface
assertions are then derived at the current state from those proved invariants,
with no new interface assertion used as a premise. This avoids proving the
same controller invariant again merely because an observation port was added.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import time

from join_parent_conclusions import main as unused_main


def sha(raw):return hashlib.sha256(raw).hexdigest()


def deflate(raw,filename):
    text=raw.decode()
    if filename=='attention.sv':
        text=re.sub(r'^    output wire .*f_rel_contract_\w+_o[,]?\n','',text,flags=re.M)
        text=re.sub(r'^    assign f_rel_contract_\w+_o=[^;]+;\n','',text,flags=re.M)
        text=text.replace('f_rel_acc_write_data_o,\n);','f_rel_acc_write_data_o\n);')
    else:
        text=re.sub(r'^    wire (?:\[[^\]]+\] )?[ab]_contract_\w+;\n','',text,flags=re.M)
        text=re.sub(r',\.f_rel_contract_\w+_o\([ab]_contract_\w+\)','',text)
        text=re.sub(r'^.*assert\(.*contract_.*\n','',text,flags=re.M)
    if'contract_'in text:raise ValueError('Unremoved interface instrumentation')
    return text.encode()


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--run',type=Path,required=True)
    ap.add_argument('--original-run',type=Path,required=True)
    ap.add_argument('--original-certificate',type=Path,required=True)
    ap.add_argument('--out',type=Path,required=True)
    ap.add_argument('--solver',choices=('z3','cvc5'),default='z3')
    ap.add_argument('--jobs',type=int,default=2);ap.add_argument('--timeout',type=int,default=20)
    args=ap.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    run=args.run.resolve();old=args.original_run.resolve()
    started=time.monotonic();files={}
    for root in (run,old):
        raw=(root/'INPUTS.json').read_bytes();inputs=json.loads(raw)
        files[str(root/'INPUTS.json')]=sha(raw)
        if inputs['assumption_cells']:raise ValueError('Unexpected assumptions')
        for n,row in inputs['files'].items():
            raw=(root/n).read_bytes()
            if sha(raw)!=row['sha256']or len(raw)!=row['bytes']:raise ValueError('Frozen input changed')
            files[str(root/n)]=sha(raw)
    fresh=json.loads((run/'INPUTS.json').read_text());prior=json.loads((old/'INPUTS.json').read_text())
    if fresh['top']!=prior['top']or(run/'reset.smtc').read_bytes()!=(old/'reset.smtc').read_bytes():
        raise ValueError('Parent or entry policy changed')
    for name in ('attention.sv','wrapper.sv'):
        original=(old/name).read_bytes()
        if b'contract_'in original or deflate((run/name).read_bytes(),name)!=original:
            raise ValueError('Instrumentation changed original transition/observer text: '+name)
    certificate=json.loads(args.original_certificate.read_text())
    parts=[Path(x['path'])for x in certificate['part_results']]
    checker=Path(__file__).with_name('join_parent_conclusions.py')
    cmd=['python3',str(checker),'--run',str(old),'--parts',*[str(p)for p in parts],
         '--certificate',str(out/'rechecked-parent-certificate.json')]
    with(out/'certificate-check.log').open('w')as log:
        cp=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,timeout=60)
    if cp.returncode:raise ValueError('Original parent certificate failed independent query reconstruction')
    cert=json.loads((out/'rechecked-parent-certificate.json').read_text())
    if not cert['conditional_parent_proof_passed']or cert['source_input_sha256']!=sha((old/'INPUTS.json').read_bytes()):
        raise ValueError('Original conditional proof incomplete or bound elsewhere')
    top=fresh['top'];count=fresh['assertion_cells'];oldcount=prior['assertion_cells']
    (out/'elaborated.il').write_bytes((run/'elaborated.il').read_bytes())
    recipe='read_rtlil elaborated.il\nmemory_map\ndffunmap\nopt_clean\nwrite_smt2 -stbv -wires model.smt2\n'
    (out/'encode.ys').write_text(recipe)
    with(out/'yosys.log').open('w')as log:
        cp=subprocess.run(['yosys','-Q','encode.ys'],cwd=out,stdout=log,stderr=subprocess.STDOUT,timeout=30)
    if cp.returncode:raise ValueError('Exact finite-state encoding failed')
    model=(out/'model.smt2').read_text()
    metadata={int(m[1]):m[2]for m in re.finditer(r'^; yosys-smt2-assert (\d+) (.*)$',model,re.M)}
    if set(metadata)!=set(range(count)):raise ValueError('Incomplete source property inventory')
    oldlines=(old/'wrapper.sv').read_text().splitlines();newlines=(run/'wrapper.sv').read_text().splitlines()
    for i in range(oldcount):
        a=re.search(r'wrapper.sv:(\d+)\.',cert['source_property_map'][str(i)])
        b=re.search(r'wrapper.sv:(\d+)\.',metadata[i])
        if not a or not b or oldlines[int(a[1])-1]!=newlines[int(b[1])-1]:
            raise ValueError('Transported invariant identity changed: '+str(i))
    prefix='\n'.join(['(set-logic QF_BV)',model,f'(declare-fun c0 () {top}_s)',
        f'(assert ({top}_h c0))',f'(assert ({top}_u c0))',f'(assert (not ({top}_is c0)))',
        '(assert (and '+' '.join(f'(|{top}_a {i}| c0)'for i in range(oldcount))+'))','(check-sat)'])+'\n'
    queries={i:prefix+f'(assert (not (|{top}_a {i}| c0)))\n(check-sat)\n'for i in range(oldcount,count)}
    for i,query in queries.items():(out/(str(i)+'.smt2')).write_text(query)
    def solve(i):
        solver=[shutil.which(args.solver)]+([f'-T:{args.timeout}','-smt2']if args.solver=='z3'else
            [f'--tlimit={args.timeout*1000}','--lang=smt2','--incremental'])+[str(out/(str(i)+'.smt2'))]
        with(out/(str(i)+'.log')).open('w')as log:
            cp=subprocess.run(solver,stdout=log,stderr=subprocess.STDOUT,timeout=args.timeout+5)
        raw=(out/(str(i)+'.log')).read_bytes();answers=[x for x in raw.decode().splitlines()if x in('sat','unsat','unknown')]
        passed=cp.returncode==0 and answers==['sat','unsat']and b'(error 'not in raw
        return i,dict(passed=passed,answers=answers,exit=cp.returncode,command=solver,
            query_sha256=sha(queries[i].encode()),reply_sha256=sha(raw))
    with ThreadPoolExecutor(max_workers=args.jobs)as pool:results=dict(pool.map(solve,queries))
    if any(sha(Path(p).read_bytes())!=h for p,h in files.items()):raise ValueError('Proof input changed during run')
    passed=all(row['passed']for row in results.values())
    result=dict(interface_corollaries_passed=passed,transported_invariants=oldcount,new_interface_conclusions=count-oldcount,
        source_input_sha256=sha((run/'INPUTS.json').read_bytes()),original_input_sha256=sha((old/'INPUTS.json').read_bytes()),
        original_certificate_sha256=sha((out/'rechecked-parent-certificate.json').read_bytes()),
        source_projection='Exact byte equality after removal of nondriving output ports, assign taps, observer wires/connections and new assertions only',
        no_new_interface_assertion_is_a_premise=True,model_sha256=sha(model.encode()),rtlil_sha256=sha((run/'elaborated.il').read_bytes()),
        results=results,solver=args.solver,seconds=time.monotonic()-started,
        source_files=files,runner_sha256=sha(Path(__file__).read_bytes()),child_contracts_composed=False,
        whole_device_token_output_theorem=False)
    (out/'runner.py').write_bytes(Path(__file__).read_bytes())
    (out/'FINISHED.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(interface_corollaries_passed=passed,transported_invariants=oldcount,new_interface_conclusions=count-oldcount,
        incomplete=[i for i,v in results.items()if not v['passed']])),flush=True)


if __name__=='__main__':main()
