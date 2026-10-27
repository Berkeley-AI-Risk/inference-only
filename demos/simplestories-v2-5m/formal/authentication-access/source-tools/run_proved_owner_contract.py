"""Compose already-proved owner invariants into the larger RAM lifecycle proof.

No protocol promise or arbitrary data replacement is added. The 38 imported
invariants have an independently audited unbounded proof on the exact same
native circuit/owner observers. New lifecycle observers have no feedback; the
source reversal below checks that projection before strengthening SMT _u.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import time

HERE=Path(__file__).resolve().parent


def sha(raw):return hashlib.sha256(raw).hexdigest()


def load(name,path):
    spec=importlib.util.spec_from_file_location('_proved_owner_contract_'+name,path)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def assertion_map(model,bank_line_delta=0):
    found={}
    for index,cell,file,a,ac,b,bc in re.findall(r'^; yosys-smt2-assert (\d+) (\S+) (bank|sha)\.sv:(\d+)\.(\d+)-(\d+)\.(\d+)$',model,re.M):
        scope=cell.rsplit('$assert$',1)[0]
        delta=bank_line_delta if file=='bank'else 0
        key=(scope,file,int(a)-delta,int(ac),int(b)-delta,int(bc))
        # Generated loops can have several instances at the same source
        # span. Import their entire conjunction, never a chosen instance.
        found.setdefault(key,[]).append(int(index))
    return found


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--run',type=Path,required=True);p.add_argument('--out',type=Path,required=True)
    p.add_argument('--timeout',type=int,default=90)
    args=p.parse_args();run=args.run.resolve();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    old=HERE/'runs/encrypted-hash-owner-r4-data-routing';audit_path=HERE/'ENCRYPTED-HASH-OWNER-AUDIT.json'
    audit=json.loads(audit_path.read_bytes())
    if not audit['passed']or not audit['cvc5_unbounded_induction']or audit['finished_sha256']!=sha((old/'FINISHED.json').read_bytes()):
        raise ValueError('The owner contract is not independently discharged')
    inputs=json.loads((run/'INPUTS.json').read_bytes());old_inputs=json.loads((old/'INPUTS.json').read_bytes())
    for directory,data in((run,inputs),(old,old_inputs)):
        for n,row in data['files'].items():
            raw=(directory/n).read_bytes()
            if row!={'bytes':len(raw),'sha256':sha(raw)}:raise ValueError('Frozen source changed')
    if inputs['top']!=old_inputs['top']or inputs['internal_cuts']!=old_inputs['internal_cuts']:
        raise ValueError('Native circuit/arithmetic premise identity differs')
    if (run/'sha.sv').read_bytes()!=(old/'sha.sv').read_bytes():raise ValueError('Native SHA/pool source differs')
    old_monitor=(old/'bank-monitor.inc.sv').read_bytes();combined=(run/'bank-monitor.inc.sv').read_bytes()
    if not combined.startswith(old_monitor+b'\n'):raise ValueError('Existing owner observer was changed')
    extra=combined[len(old_monitor)+1:]
    observer=load('observer',HERE.parent/'formal-assurance/audit_boot_boundary.py')
    observer.observer_writes_only(extra.decode())
    # Extra ghost state may read the old owner state, but cannot write it.
    stripped=re.sub(r'assert\([^;]*\);','',extra.decode())
    writes=re.findall(r'\b(\w+)\s*(?:<=|=(?!=))',re.sub(r'//[^\n]*','',stripped))
    if any(not n.startswith('f_life_')for n in writes):raise ValueError('New lifecycle observer changes pre-existing state')
    bank=(run/'bank.sv').read_bytes()
    port=b',\n    input wire f_service_active_i'
    if bank.count(port)!=1 or bank.count(b'\n'+combined)!=1:raise ValueError('Readonly observer boundary changed')
    bank=bank.replace(port,b'',1).replace(b'\n'+combined,b'\n'+old_monitor,1)
    if bank!=(old/'bank.sv').read_bytes():raise ValueError('Native/owner state projection does not reverse exactly')
    harness=(run/'harness.sv').read_text().replace('.f_service_active_i(!fault_o),','',1)
    prior=re.sub(r'cover\([^;]*\);',';',(old/'harness.sv').read_text())
    if harness!=prior:raise ValueError('The containing circuit or owner connectivity changed')
    model=(run/'design.smt2').read_text();top=inputs['top']
    previous=assertion_map((old/'design.smt2').read_text());current=assertion_map(model,bank_line_delta=1)
    if sum(map(len,previous.values()))!=38 or not set(previous)<=set(current):raise ValueError('Owner contract assertion map is incomplete')
    if any(len(previous[k])!=len(current[k])for k in previous):raise ValueError('Generated owner assertion multiplicity changed')
    indices=sorted(i for k in previous for i in current[k])
    if len(set(indices))!=38:raise ValueError('Owner assertion association is ambiguous')
    old_u=f'(define-fun |{top}_u| ((state |{top}_s|)) Bool true)'
    new_u=f'(define-fun |{top}_u| ((state |{top}_s|)) Bool (and true '+ ' '.join(f'(|{top}_a {i}| state)'for i in indices)+'))'
    if model.count(old_u)!=1:raise ValueError('Source model already contains additional SMT assumptions')
    derived=model.replace(old_u,new_u,1);(out/'design.smt2').write_text(derived)
    (out/'reset.smtc').write_bytes((run/'reset.smtc').read_bytes())
    receipt=dict(schema='source-proved-owner-contract-lifecycle-induction-v1',passed=False,top=top,
        source_model=str(run),source_inputs_sha256=sha((run/'INPUTS.json').read_bytes()),
        original_model_sha256=sha(model.encode()),derived_model_sha256=sha(derived.encode()),
        owner_audit_sha256=sha(audit_path.read_bytes()),owner_finished_sha256=audit['finished_sha256'],
        imported_current_state_assertion_indices=indices,imported_assertions=38,
        all_imported_invariants_independently_discharged=True,exact_native_and_owner_projection_checked=True,
        new_observer_writes_only_new_lifecycle_state=True,protocol_input_promises_added=False,
        arbitrary_internal_data_outputs_added=False,reset_constraints_in_induction=False,
        source_assertions=inputs['assertion_cells'],induction_depth=inputs['induction_depth'])
    (out/'INPUTS.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    command=['yosys-smtbmc','-s','cvc5','--timeout',str(args.timeout),'--unroll','-i',
        '-t',str(inputs['induction_depth']),'-m',top,'--dump-smt2','query.smt2','--dummy','responses.txt',
        '--dump-vcd','trace-%.vcd','--dump-yw','trace-%.yw','--noprogress','design.smt2']
    start=time.monotonic()
    with(out/'solver.log').open('w')as log:
        cp=subprocess.run(command,cwd=out,stdout=log,stderr=subprocess.STDOUT,timeout=args.timeout+20)
    raw=(out/'solver.log').read_bytes();statuses=re.findall(rb'Status: (\w+)',raw)
    receipt.update(command=command,exit=cp.returncode,status=[x.decode()for x in statuses],seconds=time.monotonic()-start,
        passed=cp.returncode==0 and statuses==[b'PASSED']and b'Temporal induction successful.'in raw,
        log_sha256=sha(raw),query_sha256=sha((out/'query.smt2').read_bytes()),
        responses_sha256=sha((out/'responses.txt').read_bytes()))
    (out/'checker.py').write_bytes(Path(__file__).read_bytes())
    (out/'FINISHED.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(passed=receipt['passed'],assertions=inputs['assertion_cells'],imported_proved_invariants=38,status=receipt['status'])))
    return 0 if receipt['passed']else 1


if __name__=='__main__':raise SystemExit(main())
