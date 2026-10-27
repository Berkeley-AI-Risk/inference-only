"""Fresh solver phase for an immutable compiled model, with recorded options."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time


def sha(raw):return hashlib.sha256(raw).hexdigest()


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--run',type=Path,required=True)
    p.add_argument('--out',type=Path,required=True)
    p.add_argument('--solver',choices=('z3','cvc5'),required=True)
    p.add_argument('--phase',choices=('bmc','induction','cover'),required=True)
    p.add_argument('--depth',type=int,required=True)
    p.add_argument('--timeout',type=int,default=90)
    p.add_argument('--unroll',action='store_true')
    p.add_argument('--cover-constraints',type=Path,
        help='Finite input witness stimulus for coverage only; forbidden in safety/induction')
    args=p.parse_args();run=args.run.resolve();out=args.out.resolve()
    inputs=json.loads((run/'INPUTS.json').read_bytes())
    if args.cover_constraints and args.phase!='cover':
        raise ValueError('Directed input stimulus must not enter safety or induction')
    model=run/'design.smt2';model_sha=sha(model.read_bytes())
    out.mkdir(parents=True,exist_ok=False)
    command=['yosys-smtbmc','-s',args.solver,'--timeout',str(args.timeout),'-t',str(args.depth),
        '-m',inputs['top'],'--dump-smt2','query.smt2','--dummy','responses.txt',
        '--dump-vcd','trace-%.vcd','--dump-yw','trace-%.yw','--noprogress']
    if args.unroll:command+=['--unroll']
    if args.phase=='induction':command+=['-i']
    else:
        constraints=run/'reset.smtc'
        if args.cover_constraints:
            constraints=out/'cover.smtc'
            constraints.write_bytes(args.cover_constraints.read_bytes())
        command+=['--smtc',str(constraints),'--presat']
    if args.phase=='cover':command+=['-c']
    command+=[str(model)]
    receipt=dict(schema='fresh-bound-model-solver-phase-v1',model_sha256=model_sha,
        original_inputs_sha256=sha((run/'INPUTS.json').read_bytes()),command=command,
        solver=args.solver,phase=args.phase,unroll=args.unroll,depth=args.depth,
        original_model=str(run),passed=False)
    if args.cover_constraints:
        receipt['directed_coverage_only_constraints_sha256']=sha(args.cover_constraints.read_bytes())
    (out/'INPUTS.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    started=time.monotonic()
    with(out/'solver.log').open('w')as log:
        result=subprocess.run(command,cwd=out,stdout=log,stderr=subprocess.STDOUT,timeout=args.timeout+25)
    raw=(out/'solver.log').read_bytes();text=raw.decode(errors='replace')
    statuses=re.findall(r'Status: (\w+)',text)
    receipt.update(exit=result.returncode,status=statuses,seconds=time.monotonic()-started,
        passed=result.returncode==0 and statuses==['PASSED'] and sha(model.read_bytes())==model_sha,
        log_sha256=sha(raw),query_sha256=sha((out/'query.smt2').read_bytes()),
        responses_sha256=sha((out/'responses.txt').read_bytes()))
    if args.phase=='induction':receipt['passed'] &= 'Temporal induction successful.'in text
    if args.phase=='cover':receipt['passed'] &= text.count('Reached cover statement')==inputs['cover_cells']
    (out/'FINISHED.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    print(json.dumps(receipt))
    return 0 if receipt['passed']else 1


if __name__=='__main__':raise SystemExit(main())
