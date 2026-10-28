"""Close native owner-population induction by exhaustive pointer case splits.

Every query retains the exact model and complete prior-state invariant set.
The cases partition the actual four-bit native pointer, with no current-state
conclusion imported as a premise. All other induction steps must already pass.
"""
import argparse
import gzip
import json
from pathlib import Path
import re
import subprocess
import time

from run_attention_ownership import HERE
from record_progress import sha
from join_parent_conclusions import checked_query, query_templates, template_text


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--out',type=Path,required=True)
    ap.add_argument('--timeout',type=int,default=10);args=ap.parse_args()
    out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    run=HERE/'runs/model-transport-drain-client-r1';part=HERE/'runs/model-transport-drain-client-r1-other-steps'
    manifest={}
    def pin(path,digest=None):
        raw=path.read_bytes();h=sha(raw)
        if digest is not None and digest!=h:raise ValueError('Changed proof artifact '+str(path))
        manifest[str(path.resolve())]=h;return raw
    inp=json.loads(pin(run/'INPUTS.json'));result_raw=pin(run/'FINISHED.json');base=json.loads(result_raw)
    p=json.loads(pin(part/'FINISHED.json'));count=inp['assertion_cells'];top=inp['top'];targets=[63,64]
    if count!=93 or p['depth']!=1 or p['corollary_conclusions']or p['inductive_conclusions']!=list(range(count)):
        raise ValueError('Unexpected native invariant inventory or step depth')
    if p['source_inputs_sha256']!=sha(pin(run/'INPUTS.json'))or p['base_constraint_text']!=(run/'reset.smtc').read_text():
        raise ValueError('Step source/entry mismatch')
    for n,row in inp['files'].items():
        if len(pin(run/n,row['sha256']))!=row['bytes']:raise ValueError('Changed source length')
    graph=json.loads(pin(run/'elaborated.json'))['modules'][top]
    if any(c['type']in('$assume','$anyseq')for c in graph['cells'].values()):raise ValueError('Unexpected assumptions')
    pointers={k:'u_private_ddr_arbiter.owner_'+k+'_pointer_q'for k in('read','write')}
    if any(len(graph['netnames'][n]['bits'])!=4 for n in pointers.values()):raise ValueError('Native pointer width changed')
    model=pin(part/'model.smt2',p['model_sha256']).decode()
    replay=out/'encoding-replay';replay.mkdir()
    (replay/'elaborated.il').write_bytes(pin(run/'elaborated.il',p['rtlil_sha256']))
    recipe='read_rtlil elaborated.il\n'+('memory_map\ndffunmap\nopt_clean\n'if p['exact_finite_memories_mapped']else'')+'write_json encoded.json\nwrite_smt2 -stbv -wires model.smt2\n'
    if pin(part/'encode.ys').decode()!=recipe:raise ValueError('Finite-memory encoding recipe changed')
    (replay/'encode.ys').write_text(recipe)
    with(replay/'yosys.log').open('w')as log:
        cp=subprocess.run(['yosys','-Q','encode.ys'],cwd=replay,stdout=log,stderr=subprocess.STDOUT,timeout=30)
    if cp.returncode or pin(replay/'model.smt2')!=model.encode():raise ValueError('Exact source-model encoding replay differs')
    pin(replay/'encode.ys');pin(replay/'yosys.log')
    metadata={int(i):n for i,n in re.findall(r'^; yosys-smt2-assert (\d+) (.*)$',model,re.M)}
    arb=(run/'arbiter.sv').read_text().splitlines()
    for index,role in zip(targets,('shell','layer')):
        m=re.search(r'arbiter.sv:(\d+)\.',metadata[index])
        expected="assert({1'b0,f_"+role+"_count}==f_"+role+"_actual_count);"
        if not m or re.sub(r'\s+','',arb[int(m[1])-1])!=expected:raise ValueError('Case target is not the native role count')
    templates=query_templates(model,p,top,count,compact=True)
    required={'base'}|{'induction-'+str(i).zfill(3)for i in range(count)if i not in targets}
    if set(p['results'])!=required:raise ValueError('Other independent steps are incomplete')
    for label,row in p['results'].items():
        if checked_query(part/(label+'.smt2'),row)!=template_text(templates[label]).encode():raise ValueError('Prior-state step query changed')
        raw=pin(part/(label+'.log'),row['reply_sha256']).decode();pin(part/row['query_artifact'],row['query_artifact_sha256'])
        if not row['passed']or row['exit']or[l for l in raw.splitlines()if l in('sat','unsat','unknown')]!=['sat','unsat']:
            raise ValueError('A required other induction step is unresolved')
    prefix=templates['induction-063'][0];check='(check-sat-using smt)\n'if p.get('z3_smt_tactic')else'(check-sat)\n'
    if not prefix.endswith(check):raise ValueError('Step premise does not end in exactly one satisfiability check')
    prefix=prefix[:-len(check)]
    suffix='(assert (not (and '+' '.join('(|'+top+'_a '+str(i)+'| s1)'for i in targets)+')))\n'+check
    rows={};coverage={};started=time.monotonic()
    def solve(label,predicates,target=suffix):
        raw=(prefix+''.join('(assert '+q+')\n'for q in predicates)+check+target).encode();path=out/(label+'.smt2');path.write_bytes(raw)
        command=['z3','-memory:1024','-T:'+str(args.timeout),'-smt2',str(path)]
        with(out/(label+'.log')).open('w')as log:
            try:cp=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=args.timeout+5);code=cp.returncode
            except subprocess.TimeoutExpired:code=None
        reply=pin(out/(label+'.log')).decode();answers=[l for l in reply.splitlines()if l in('sat','unsat','unknown')]
        passed=code==0 and answers==['sat','unsat']and'(error 'not in reply
        archive=path.with_suffix('.smt2.gz');archive.write_bytes(gzip.compress(raw));pin(archive);path.unlink()
        rows[label]=dict(passed=passed,case_predicates=predicates,targets=targets,answers=answers,exit=code,command=command,
            query_sha256=sha(raw),query_artifact=archive.name,query_artifact_sha256=sha(archive.read_bytes()),
            query_artifact_format='gzip',reply_sha256=sha(reply.encode()))
        print(label,passed,answers,flush=True);return passed
    reset='(|'+top+'_n reset_n| s0)';scope='(|'+top+'_n f_scope| s0)'
    count_net='u_private_ddr_arbiter.owner_count_q'
    if len(graph['netnames'][count_net]['bits'])!=5:raise ValueError('Native owner count width changed')
    cases={'reset-low':['(not '+reset+')'],'inactive':[reset,'(not '+scope+')']}
    for read in range(16):
        for count_value in range(17):
            cases['read-'+str(read).zfill(2)+'-count-'+str(count_value).zfill(2)]=[
                reset,scope,'(= (|'+top+'_n '+pointers['read']+'| s0) (_ bv'+str(read)+' 4))',
                '(= (|'+top+'_n '+count_net+'| s0) (_ bv'+str(count_value)+' 5))',
                '(= (|'+top+'_n '+pointers['write']+'| s0) (_ bv'+str((read+count_value)%16)+' 4))']
    exhaustive='(or '+' '.join('(and '+' '.join(q)+')'for q in cases.values())+')'
    coverage_passed=solve('exhaustive-case-coverage',[],target='(assert (not '+exhaustive+'))\n'+check)
    if not coverage_passed:raise ValueError('Pointer cases do not exhaust the exact prior-state model')
    for label,predicates in cases.items():coverage[label]=solve(label,predicates)
    complete=len(coverage)==274 and all(coverage.values())
    cover=base['results']['z3-cover']
    if not cover['passed']:raise ValueError('Original covers incomplete')
    pin(run/'z3-cover.log',cover['log_sha256']);pin(run/'z3-cover.smt2',cover['query_sha256'])
    for n,digest in cover['traces'].items():pin(run/n,digest)
    checker=out/'checker.py';checker.write_bytes(Path(__file__).read_bytes());pin(checker)
    from join_parent_conclusions import __file__ as helper
    (out/'query_checker.py').write_bytes(Path(helper).read_bytes());pin(out/'query_checker.py')
    cert=dict(conditional_parent_proof_passed=complete,missing=[]if complete else['exhaustive owner-pointer cases'],
        assertions=count,closed_inductive_conclusions=count if complete else count-len(targets),current_state_corollaries=0,
        no_current_state_corollary_is_an_induction_premise=True,source_input_sha256=sha((run/'INPUTS.json').read_bytes()),
        source_result_sha256=sha(result_raw),complete_backend_lanes=dict(z3=complete,cvc5=False),
        pointer_widths=dict(read=4,write=4,count=5),case_coverage=coverage,exhaustive_case_coverage_proved=coverage_passed,results=rows,targets=targets,
        base_and_other_steps=str(part),artifact_manifest=manifest,checker_sha256=sha(checker.read_bytes()),
        whole_device_token_output_theorem=False,seconds=time.monotonic()-started,
        scope='All 93 native transport invariants use the same complete prior-state invariant set. Two role-population steps split exhaustively on actual four-bit native owner pointers; 91 other steps and satisfiable base independently checked. No current-state conclusion is a premise.')
    (out/'CERTIFICATE.json').write_text(json.dumps(cert,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(conditional_parent_proof_passed=complete,cases=len(rows),missing=cert['missing'])))
    return 0 if complete else 1


if __name__=='__main__':raise SystemExit(main())
