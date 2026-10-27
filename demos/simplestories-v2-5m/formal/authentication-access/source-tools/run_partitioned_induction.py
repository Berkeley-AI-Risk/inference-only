"""Fresh joint k-induction with one conclusion per query on an unchanged RTLIL.

All previous-state invariants are retained in every conclusion query. No
same-state premise is added, and all conclusions plus the reset base are
required. The bit-vector state encoding changes representation, not RTL.
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


def sha(raw):return hashlib.sha256(raw).hexdigest()


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--run',type=Path,required=True);p.add_argument('--out',type=Path,required=True)
    p.add_argument('--solver',choices=('z3','cvc5'),required=True)
    p.add_argument('--jobs',type=int,default=2);p.add_argument('--timeout',type=int,default=45)
    p.add_argument('--depth',type=int,default=3)
    p.add_argument('--indices',type=int,nargs='+',help='Selected conclusions only; does not credit a complete induction')
    p.add_argument('--z3-normalize-addition',action='store_true',help='Use the solver rewriter to sort and normalize bit-vector sums')
    p.add_argument('--state-encoding',choices=('bit-vector','original'),default='bit-vector')
    p.add_argument('--proved-owner-contract',type=Path,help='A source-audited derivation importing the 38 independently proved owner invariants')
    p.add_argument('--only-new-contract-conclusions',action='store_true')
    args=p.parse_args();run=args.run.resolve();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    inputs=json.loads((run/'INPUTS.json').read_bytes());top=inputs['top'];count=inputs['assertion_cells'];k=args.depth
    for n,row in inputs['files'].items():
        raw=(run/n).read_bytes()
        if row!={'bytes':len(raw),'sha256':sha(raw)}:raise ValueError('Compiled source/input file changed')
    graph=json.loads((run/'elaborated.json').read_bytes())['modules'][top]
    constants=sum(c['type']=='$anyconst'for c in graph['cells'].values())
    if constants!=inputs.get('observer_constants',0):raise ValueError('Readonly observer constant inventory changed')
    if any(c['type']=='$anyseq'or(args.state_encoding=='bit-vector'and c['type']in('$mem_v2','$anyconst'))for c in graph['cells'].values()):
        raise ValueError('Bit-vector state encoding requires a concrete finite-register model')
    contract=None
    if args.proved_owner_contract:
        if args.state_encoding!='original':raise ValueError('A proved source contract retains the original state encoding')
        contract_path=args.proved_owner_contract.resolve();contract=json.loads((contract_path/'INPUTS.json').read_bytes())
        if contract['source_inputs_sha256']!=sha((run/'INPUTS.json').read_bytes())or not contract['all_imported_invariants_independently_discharged']or not contract['exact_native_and_owner_projection_checked']:
            raise ValueError('Proved contract does not bind this exact native model')
        audit=Path(__file__).resolve().parent/'ENCRYPTED-HASH-OWNER-AUDIT.json'
        if sha(audit.read_bytes())!=contract['owner_audit_sha256']or not json.loads(audit.read_bytes())['passed']:
            raise ValueError('Owner contract evidence changed')
        original_model=(run/'design.smt2').read_text()
        old_u=f'(define-fun |{top}_u| ((state |{top}_s|)) Bool true)'
        new_u=f'(define-fun |{top}_u| ((state |{top}_s|)) Bool (and true '+ ' '.join(f'(|{top}_a {i}| state)'for i in contract['imported_current_state_assertion_indices'])+'))'
        if original_model.count(old_u)!=1:raise ValueError('Original model has additional SMT assumptions')
        derived=original_model.replace(old_u,new_u,1).encode()
        if sha(derived)!=contract['derived_model_sha256']or(contract_path/'design.smt2').read_bytes()!=derived:
            raise ValueError('Proved contract derivation changed more than the discharged invariants')
    elif args.only_new_contract_conclusions:raise ValueError('No source-proved owner contract was supplied')
    il=run/'elaborated.il';il_sha=sha(il.read_bytes())
    if args.state_encoding=='bit-vector':
        script='read_rtlil '+json.dumps(str(il))+'\nwrite_smt2 -stbv -wires model.smt2\n'
        (out/'encode.ys').write_text(script)
        with(out/'yosys.log').open('w')as log:
            cp=subprocess.run(['yosys','-Q','encode.ys'],cwd=out,stdout=log,stderr=subprocess.STDOUT,timeout=30)
        if cp.returncode:raise ValueError('Encoding conversion failed')
    else:(out/'model.smt2').write_bytes(derived if contract else(run/'design.smt2').read_bytes())
    model=(out/'model.smt2').read_text()
    if len(re.findall(r'^; yosys-smt2-assert ',model,re.M))!=count:raise ValueError('Assertion inventory changed')
    if args.state_encoding=='bit-vector'and '(define-sort '+top+'_s 'not in model and '(define-sort |'+top+'_s| 'not in model:
        raise ValueError('Expected concrete bit-vector state encoding')
    reset_names=[n for n in('reset_n_i','reset_n')if n in graph['ports']]
    if len(reset_names)!=1:raise ValueError('A single native reset port is required')
    reset_name=reset_names[0]
    expected_reset=f'initial\nassume (= [{reset_name}] false)\nstate 1\nassume (= [{reset_name}] false)\n'
    if (run/'reset.smtc').read_text()!=expected_reset:raise ValueError('Original model has extra base input constraints')
    def chain(base):
        text='(set-logic '+('QF_BV'if args.state_encoding=='bit-vector'else'QF_AUFBV')+')\n'+model+'\n'
        for i in range(k+1):
            text+=f'(declare-fun s{i} () {top}_s)\n(assert ({top}_h s{i}))\n(assert ({top}_u s{i}))\n'
            text+=f'(assert (= ({top}_is s{i}) '+('true'if base and i==0 else'false')+'))\n'
            if i:text+=f'(assert ({top}_t s{i-1} s{i}))\n'
        if base:
            text+=f'(assert ({top}_i s0))\n(assert (not (|{top}_n {reset_name}| s0)))\n(assert (not (|{top}_n {reset_name}| s1)))\n'
        else:
            for i in range(k):text+=f'(assert ({top}_a s{i}))\n'
        return text
    queries={'base':chain(True)+'(check-sat)\n(assert (not (and '+ ' '.join(f'({top}_a s{i})'for i in range(k+1))+')))\n(check-sat)\n'}
    prefix=chain(False)+'(check-sat)\n'
    queries.update({f'induction-{i:02}':prefix+f'(assert (not (|{top}_a {i}| s{k})))\n(check-sat)\n'for i in range(count)})
    if args.only_new_contract_conclusions:
        imported=set(contract['imported_current_state_assertion_indices'])
        queries={n:q for n,q in queries.items()if n=='base' or int(n.split('-')[1])not in imported}
    if args.indices:
        if any(i<0 or i>=count for i in args.indices):raise ValueError('Invalid conclusion index')
        queries={n:q for n,q in queries.items()if n=='base' or int(n.split('-')[1])in args.indices}
    for n,q in queries.items():(out/(n+'.smt2')).write_text(q)
    started=time.monotonic()
    def solve(name):
        cmd=[shutil.which(args.solver)]
        cmd += [f'-T:{args.timeout}','-smt2']if args.solver=='z3'else[f'--tlimit={args.timeout*1000}','--lang=smt2','--incremental']
        if args.z3_normalize_addition:
            if args.solver!='z3':raise ValueError('Z3 rewriter options require Z3')
            cmd+=['rewriter.bv_sort_ac=true','rewriter.som=true','rewriter.sort_sums=true']
        cmd += [str(out/(name+'.smt2'))]
        begin=time.monotonic();timed_out=False
        with(out/(name+'.log')).open('w')as log:
            try:cp=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,timeout=args.timeout+10);code=cp.returncode
            except subprocess.TimeoutExpired:code=None;timed_out=True
        text=(out/(name+'.log')).read_text();answers=[x for x in text.splitlines()if x in('sat','unsat','unknown')]
        row=dict(name=name,command=cmd,passed=code==0 and not timed_out and answers==['sat','unsat']and'(error 'not in text,
            exit=code,timed_out=timed_out,answers=answers,seconds=time.monotonic()-begin,
            query_sha256=sha(queries[name].encode()),log_sha256=sha(text.encode()))
        print(json.dumps(row),flush=True);return row
    with ThreadPoolExecutor(max_workers=args.jobs)as pool:rows=list(pool.map(solve,queries))
    result=dict(schema='partitioned-same-model-joint-induction-v1',passed=all(r['passed']for r in rows),
        assertion_count=count,depth=k,solver=args.solver,prior_joint_invariants_only=True,
        complete_assertion_inventory=not args.indices,selected_conclusions=args.indices,
        runner_sha256=sha(Path(__file__).read_bytes()),z3_addition_normalization=args.z3_normalize_addition,
        state_encoding=args.state_encoding,full_original_RAM_retained=args.state_encoding=='original',
        same_state_extra_assumptions=bool(contract),all_extra_current_invariants_source_proved=bool(contract),
        source_proved_owner_contract=contract,
        covers_all_new_conclusions_and_imported_proved_invariants=args.only_new_contract_conclusions and not args.indices,
        rtlil_sha256=il_sha,model_sha256=sha(model.encode()),
        parent_inputs_sha256=sha((run/'INPUTS.json').read_bytes()),parent_model=str(run),
        results=rows,seconds=time.monotonic()-started)
    (out/'FINISHED.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    return 0 if result['passed']else 1


if __name__=='__main__':raise SystemExit(main())
