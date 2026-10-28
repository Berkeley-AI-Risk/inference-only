"""Derive final-hidden-output equality from the closed conditional parent proof.

These are current-state implications, not new induction premises. Fresh-read
and metadata ownership conditions must still be discharged at the real caller.
"""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess

from record_progress import sha


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--certificate',type=Path,required=True)
    ap.add_argument('--run',type=Path,required=True)
    ap.add_argument('--model',type=Path,required=True)
    ap.add_argument('--out',type=Path,required=True)
    args=ap.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    certificate=json.loads(args.certificate.read_text());run=args.run.resolve()
    if not certificate['conditional_parent_proof_passed']or certificate['missing']:
        raise ValueError('Source parent induction is incomplete')
    manifest={}
    def pin(path,digest=None):
        raw=path.read_bytes();actual=sha(raw)
        if digest is not None and actual!=digest:raise ValueError('Changed proof artifact: '+str(path))
        manifest[str(path.resolve())]=actual;return raw
    pin(args.certificate)
    for path,digest in certificate['artifact_manifest'].items():pin(Path(path),digest)
    inputs=json.loads(pin(run/'INPUTS.json',certificate['source_input_sha256']))
    pin(run/'FINISHED.json',certificate['source_result_sha256'])
    for name,row in inputs['files'].items():
        raw=pin(run/name,row['sha256'])
        if len(raw)!=row['bytes']:raise ValueError('Input length differs')
    top=inputs['top'];count=inputs['assertion_cells']
    if count!=certificate['assertions']or top!='semantic_parent_relational':raise ValueError('Unexpected theorem source')
    model=pin(args.model).decode()
    replay=args.certificate.parent/'new-encoding/model.smt2'
    if pin(replay)!=model.encode():raise ValueError('Model differs from checked source encoding replay')
    properties={int(m[1])for m in re.finditer(r'^; yosys-smt2-assert (\d+) ',model,re.M)}
    if properties!=set(range(count)):raise ValueError('Incomplete invariant inventory')
    def wire(name):
        if '(define-fun |'+top+'_n '+name+'|'not in model:raise ValueError('Unknown actual model net '+name)
        return '(|'+top+'_n '+name+'| c0)'
    prefix='\n'.join(['(set-logic QF_BV)',model,f'(declare-fun c0 () {top}_s)',
        f'(assert ({top}_h c0))',f'(assert ({top}_u c0))',f'(assert (not ({top}_is c0)))',
        '(assert (and '+' '.join(f'(|{top}_a {i}| c0)'for i in range(count))+'))',
        '(assert '+wire('rst_n')+')','(assert '+wire('f_joined')+')',
        '(assert (not '+wire('clear_i')+'))'])+'\n'
    cases={
        'mantissa':('a_f_rel_live_u_hidden_state','private_result_mantissa_o'),
        'exponent':('a_owner_f_hidden_meta','private_result_exponent_o'),
    }
    results={}
    for name,(owner,output)in cases.items():
        query=prefix+'(assert '+wire(owner)+')\n(check-sat)\n(assert (not (= '+wire('a_'+output)+' '+wire('b_'+output)+')))\n(check-sat)\n'
        path=out/(name+'.smt2');path.write_text(query)
        command=[shutil.which('z3'),'-memory:1024','-T:25','-smt2',str(path)]
        timed_out=False
        with(out/(name+'.log')).open('w')as log:
            try:cp=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=30);code=cp.returncode
            except subprocess.TimeoutExpired:code=None;timed_out=True
        raw=(out/(name+'.log')).read_bytes();answers=[s for s in raw.decode().splitlines()if s in('sat','unsat','unknown')]
        passed=code==0 and answers==['sat','unsat']and b'(error 'not in raw
        results[name]=dict(passed=passed,owner=owner,output=output,query_sha256=pin(path)and sha(query.encode()),
            reply_sha256=sha(pin(out/(name+'.log'))),command=command,exit=code,answers=answers,timed_out=timed_out)
    (out/'runner.py').write_bytes(Path(__file__).read_bytes());pin(out/'runner.py')
    result=dict(conditional_final_output_corollaries_passed=all(r['passed']for r in results.values()),
        proved_parent_assertions=count,source_certificate_sha256=sha(args.certificate.read_bytes()),
        source_inputs_sha256=sha((run/'INPUTS.json').read_bytes()),model_sha256=sha(model.encode()),
        no_new_corollary_is_an_induction_premise=True,results=results,artifact_manifest=manifest,
        caller_permissions_composed=False,child_contracts_composed=False,session_milestone_complete=False,
        scope='Actual conditional semantic-parent final hidden output equality only when the corresponding fresh-read or hidden-metadata owner holds. The actual caller and full child session contracts require separate composition.')
    (out/'FINISHED.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps({k:result[k]for k in('conditional_final_output_corollaries_passed','proved_parent_assertions','caller_permissions_composed')}))


if __name__=='__main__':main()
