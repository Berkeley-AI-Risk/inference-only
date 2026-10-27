"""Check a complete concrete primary counterexample against the frozen SMT RTL.

VCD values include resetless payload initial values and anyconst observers that
an input-only Yosys witness may leave free. These values constrain this negative
witness only; no assumption is added to any positive safety proof.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time


def sha(raw):return hashlib.sha256(raw).hexdigest()


def read_vcd(path):
    names={};scope=[];values={};states={};step=None;has_step=False
    def save():
        if has_step:
            if step in states:raise ValueError('Repeated trace state')
            states[step]=dict(values)
    for line in path.read_text().splitlines():
        parts=line.split()
        if parts and parts[0]=='$scope':scope.append(parts[2])
        elif parts and parts[0]=='$upscope':scope.pop()
        elif parts and parts[0]=='$var'and parts[3].startswith('n'):
            names[parts[3]]=('.'.join(scope[1:]+[parts[4]]),int(parts[2]))
        elif line.startswith('#'):save();has_step=False
        elif line.startswith('b'):
            bits,symbol=line[1:].split()
            if symbol=='t':step=int(bits,2);has_step=True
            elif symbol in names:
                values[symbol]=bits
    save()
    if not states or sorted(states)!=list(range(len(states))):raise ValueError('Noncontiguous trace')
    return names,states


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--proof',type=Path,required=True);p.add_argument('--out',type=Path,required=True)
    args=p.parse_args();run=args.proof.resolve();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    inputs=json.loads((run/'INPUTS.json').read_bytes());result=json.loads((run/'FINISHED.json').read_bytes());top=inputs['top']
    row=result['results']['z3-bmc']
    if not inputs['mutant']or not row['passed']or row['status']!=['FAILED']or row['exit']!=1:raise ValueError('No actual primary bounded counterexample')
    paths=[n for n in row['traces']if n.endswith('.vcd')]
    if len(paths)!=1:raise ValueError('Expected one primary VCD')
    vcd=run/paths[0]
    if sha(vcd.read_bytes())!=row['traces'][vcd.name]:raise ValueError('Primary VCD changed')
    names,states=read_vcd(vcd);model=(run/'design.smt2').read_text()
    yw_paths=[n for n in row['traces']if n.endswith('.yw')]
    if len(yw_paths)!=1:raise ValueError('Primary witness step inventory missing')
    yw=(run/yw_paths[0]).read_bytes()
    if sha(yw)!=row['traces'][yw_paths[0]]:raise ValueError('Primary witness changed')
    step_count=len(json.loads(yw)['steps'])
    # SMTBMC appends a clock-only VCD timestamp beyond the modeled witness.
    if len(states)not in(step_count,step_count+1):raise ValueError('VCD/YW step inventories differ')
    states={i:v for i,v in states.items()if i<step_count}
    parts=['(set-logic QF_AUFBV)',model];matched=0;unknown_words=0
    usable={}
    for symbol,(name,width)in names.items():
        if f'(define-fun |{top}_n {name}|'not in model:
            # VCD escapes generated/array indices with angle brackets.
            name=re.sub(r'<(\d+)>',lambda m:'['+str(int(m[1]))+']',name)
        if f'(define-fun |{top}_n {name}|'in model:usable[symbol]=(name,width)
    if not usable:raise ValueError('No concrete native wire values matched')
    for step,values in states.items():
        parts += [f'(declare-fun s{step} () |{top}_s|)',f'(assert (|{top}_h| s{step}))',f'(assert (|{top}_u| s{step}))',
            f'(assert (= (|{top}_is| s{step}) '+('true'if step==0 else'false')+'))']
        if step==0:parts.append(f'(assert (|{top}_i| s0))')
        else:parts.append(f'(assert (|{top}_t| s{step-1} s{step}))')
        if step<len(states)-1:parts.append(f'(assert (|{top}_a| s{step}))')
        for symbol,(name,width)in usable.items():
            if symbol not in values or len(values[symbol])!=width:raise ValueError('Concrete trace width/value missing')
            if set(values[symbol])-set('01'):
                # Unread RAM words can be omitted by SMTBMC. Leave those
                # values free; every actual transition and failure is still
                # checked in the unchanged finite-state model.
                unknown_words+=1;continue
            value=('true'if values[symbol]=='1'else'false')if width==1 else'#b'+values[symbol]
            parts.append(f'(assert (= (|{top}_n {name}| s{step}) {value}))');matched+=1
    parts += [f'(assert (not (|{top}_a| s{len(states)-1})))','(check-sat)','(exit)']
    query='\n'.join(parts)+'\n';(out/'witness.smt2').write_text(query)
    command=['cvc5','--lang=smt2','--tlimit=90000','witness.smt2'];begin=time.monotonic()
    with(out/'cvc5.log').open('w')as log:
        cp=subprocess.run(command,cwd=out,stdout=log,stderr=subprocess.STDOUT,timeout=105)
    raw=(out/'cvc5.log').read_bytes();answers=[x for x in raw.decode().splitlines()if x in('sat','unsat','unknown')]
    passed=cp.returncode==0 and answers==['sat']and b'(error 'not in raw
    receipt=dict(schema='complete-concrete-vcd-counterexample-check-v1',passed=passed,source_run=run.name,
        inputs_sha256=sha((run/'INPUTS.json').read_bytes()),original_finished_sha256=sha((run/'FINISHED.json').read_bytes()),
        model_sha256=sha(model.encode()),primary_vcd_sha256=sha(vcd.read_bytes()),query_sha256=sha(query.encode()),
        primary_yw_sha256=sha(yw),clock_only_trailing_timestamp_excluded=True,
        log_sha256=sha(raw),states_checked=len(states),wire_values_checked=matched,matched_wire_count=len(usable),
        all_native_state_transitions_checked=True,initial_state_checked=True,
        all_prior_safety_and_final_negated_safety_checked=True,independent_search=False,
        includes_resetless_payload_and_observer_constant_values=True,positive_safety_assumptions_added=False,
        unknown_trace_words_left_unconstrained=unknown_words,
        command=command,exit=cp.returncode,answers=answers,seconds=time.monotonic()-begin)
    (out/'checker.py').write_bytes(Path(__file__).read_bytes())
    (out/'FINISHED.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n');print(json.dumps(receipt))
    return 0 if passed else 1


if __name__=='__main__':raise SystemExit(main())
