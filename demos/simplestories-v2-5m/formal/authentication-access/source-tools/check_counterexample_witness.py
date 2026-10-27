"""Independently verify a real bounded counterexample using cvc5.

SMTBMC --check-witness succeeds with exit zero when the witness is satisfiable
and safety cannot hold under that witness. This is not a new independent search
and never rewrites a timed-out original solver campaign.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import time


def sha(raw):return hashlib.sha256(raw).hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--proof',type=Path,required=True)
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--timeout',type=int,default=90)
    parser.add_argument('--observer-constant',help='Pin an existing anyconst observer to its primary VCD value, for this negative witness only')
    args=parser.parse_args();run=args.proof.resolve(strict=True);out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    inp_raw=(run/'INPUTS.json').read_bytes();fin_raw=(run/'FINISHED.json').read_bytes();inp,fin=json.loads(inp_raw),json.loads(fin_raw)
    if fin['inputs_sha256']!=sha(inp_raw)or not inp['mutant']:raise ValueError('Source run is not a mutation with intact inputs')
    row=fin['results']['z3-bmc']
    if not row['passed']or row['status']!=['FAILED']or row['exit']!=1:raise ValueError('No real primary bounded counterexample')
    trace_names=[n for n in row['traces']if n.endswith('.yw')]
    if len(trace_names)!=1:raise ValueError('Expected one complete primary witness')
    trace=run/trace_names[0];trace_raw=trace.read_bytes()
    if sha(trace_raw)!=row['traces'][trace.name]:raise ValueError('Primary witness changed')
    for n,r in inp['files'].items():
        raw=(run/n).read_bytes()
        if len(raw)!=r['bytes']or sha(raw)!=r['sha256']:raise ValueError('Frozen proof input changed')
    steps=len(json.loads(trace_raw)['steps'])
    constraints=run/'reset.smtc';observer=None
    if args.observer_constant:
        graph=json.loads((run/'elaborated.json').read_bytes())['modules'][inp['top']]
        bits=graph['netnames'][args.observer_constant]['bits']
        if not any(c['type']=='$anyconst'and c['connections']['Y']==bits for c in graph['cells'].values()):
            raise ValueError('Requested witness constant is not a read-only anyconst observer')
        vcd_names=[n for n in row['traces']if n.endswith('.vcd')]
        if len(vcd_names)!=1:raise ValueError('Primary VCD is missing')
        vcd=run/vcd_names[0];scope=[];symbol=None;value=None
        for line in vcd.read_text().splitlines():
            parts=line.split()
            if parts and parts[0]=='$scope':scope.append(parts[2])
            elif parts and parts[0]=='$upscope':scope.pop()
            elif parts and parts[0]=='$var'and '.'.join(scope[1:]+[parts[4]])==args.observer_constant:
                symbol=parts[3]
            elif symbol and line.startswith('b'):
                encoded,ident=line[1:].split()
                if ident==symbol:
                    if set(encoded)-set('01'):raise ValueError('Unknown observer constant in the primary trace')
                    value=encoded;break
        if value is None or len(value)!=len(bits):raise ValueError('Primary observer constant value is absent')
        observer=dict(name=args.observer_constant,value_binary=value,width=len(bits),
            primary_vcd_sha256=sha(vcd.read_bytes()),negative_witness_only=True)
        constraints=out/'witness.smtc'
        constraints.write_bytes((run/'reset.smtc').read_bytes()+
            ('\nalways\nassume (= ['+args.observer_constant+'] #b'+value+')\n').encode())
    command=['yosys-smtbmc','-s','cvc5','--unroll','--timeout',str(args.timeout),'-t',str(steps),
        '-m',inp['top'],'--smtc',str(constraints),'--presat','--yw',str(trace),'--check-witness',
        '--dump-smt2',str(out/'query.smt2'),'--dummy',str(out/'responses.txt'),'--noprogress','design.smt2']
    started=time.monotonic()
    with(out/'cvc5.log').open('w')as log:
        cp=subprocess.run(command,cwd=run,stdout=log,stderr=subprocess.STDOUT,timeout=args.timeout+20)
    log=(out/'cvc5.log').read_bytes();responses=(out/'responses.txt').read_bytes()
    answers=re.findall(rb'^(sat|unsat|unknown)$',responses,re.M)
    passed=(cp.returncode==0 and re.findall(rb'Status: (\w+)',log)==[b'PASSED']and
        b'BMC failed!'in log and b'Checking witness constraints...'in log and answers[-2:]==[b'sat',b'unsat'])
    result=dict(schema='source-bound-secondary-counterexample-witness-check-v1',passed=passed,
        source_run=run.name,inputs_sha256=sha(inp_raw),original_finished_sha256=sha(fin_raw),
        emitted_smt_sha256=sha((run/'design.smt2').read_bytes()),witness_sha256=sha(trace_raw),steps=steps,
        command=command,exit=cp.returncode,seconds=time.monotonic()-started,
        log_sha256=sha(log),query_sha256=sha((out/'query.smt2').read_bytes()),solver_responses_sha256=sha(responses),
        final_answers=[x.decode()for x in answers[-2:]],independent_search=False,
        sufficient_counterexample_witness_verified=passed,original_record_unchanged=True,
        observer_constant_witness=observer,additional_constraints_not_used_in_positive_safety_proofs=True,
        witness_constraints_sha256=sha(constraints.read_bytes()),
        solver_sha256=sha(Path(shutil.which('cvc5')).read_bytes()),hardware_access=False)
    (out/'checker.py').write_bytes(Path(__file__).read_bytes())
    (out/'FINISHED.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps({k:result[k]for k in ('passed','source_run','steps','exit','final_answers','seconds')}))
    raise SystemExit(0 if passed else 1)


if __name__=='__main__':main()
