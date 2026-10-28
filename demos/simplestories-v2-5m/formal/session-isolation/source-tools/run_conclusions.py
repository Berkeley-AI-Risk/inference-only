"""Partition joint induction, preserving the exact elaborated SMT model.

Each conclusion imports only the complete invariant conjunction at prior
states. No current-state assertion is a premise. All conclusions and a
satisfiable reset base are required for a complete result.
"""
import argparse
import gzip
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import time


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def main():
    producer=Path(__file__).read_bytes()
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--run',type=Path,required=True)
    ap.add_argument('--out',type=Path,required=True)
    ap.add_argument('--solver',choices=('z3','cvc5'),required=True)
    ap.add_argument('--timeout',type=int,default=45)
    ap.add_argument('--jobs',type=int,default=4)
    ap.add_argument('--depth',type=int,default=3)
    ap.add_argument('--encoding',choices=('native','bitvector'),default='native')
    ap.add_argument('--map-memories',action='store_true')
    ap.add_argument('--compress-queries',action='store_true',help='Archive exact query bytes as gzip, writing plaintext only for active solver jobs.')
    ap.add_argument('--solver-memory-mib',type=int,default=0,help='Z3 virtual-memory cap; memory stops remain unresolved.')
    ap.add_argument('--origin',help='Only conclusions whose recorded source includes this substring; explicitly partial.')
    ap.add_argument('--corollaries',default='',help='Comma-separated combinational conclusions derived from an independently closed remaining invariant set.')
    ap.add_argument('--indices',help='Only these comma-separated property indices; explicitly partial.')
    ap.add_argument('--joint',action='store_true',help='One exact joint step for the complete invariant conjunction in the alternative encoding.')
    ap.add_argument('--group-size',type=int,default=0,help='Disjoint batches of induction conclusions under the same prior-state invariant set.')
    ap.add_argument('--z3-smt-tactic',action='store_true',help='Use Z3 smt strategy on the identical formulas, preserving bit-vector function congruence before eager bit blasting.')
    args=ap.parse_args()
    if args.z3_smt_tactic and args.solver!='z3':raise ValueError('The explicit smt tactic is Z3-only')
    if args.joint and(args.origin or args.indices or args.corollaries):
        raise ValueError('Joint induction must cover every conclusion without corollaries')
    if args.group_size and(args.group_size<1 or args.joint or args.origin or args.indices or args.corollaries):
        raise ValueError('Grouped induction requires a positive group size and the complete invariant inventory')
    if args.solver_memory_mib and(args.solver!='z3'or args.solver_memory_mib<1):raise ValueError('Memory guard currently supports positive Z3 limits only')
    run=args.run.resolve();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    (out/'runner.py').write_bytes(producer)
    inputs=json.loads((run/'INPUTS.json').read_bytes())
    for name,row in inputs['files'].items():
        raw=(run/name).read_bytes()
        if row!={'bytes':len(raw),'sha256':sha(raw)}:
            raise ValueError('Source input changed '+name)
    top=inputs['top'];count=inputs['assertion_cells'];k=args.depth
    corollaries=set(int(n)for n in args.corollaries.split(',')if n)
    if any(n<0 or n>=count for n in corollaries)or len(corollaries)==count:
        raise ValueError('Invalid corollary partition')
    invariant_indices=set(range(count))-corollaries
    def invariant_at(state):
        return f'({top}_a {state})'if not corollaries else'(and '+' '.join(
            f'(|{top}_a {i}| {state})'for i in sorted(invariant_indices))+')'
    graph=json.loads((run/'elaborated.json').read_text())['modules'][top]
    if any(c['type'] in ('$assume','$anyseq')for c in graph['cells'].values()):
        raise ValueError('Unexpected assumption or arbitrary cell')
    if args.encoding=='bitvector':
        if any(c['type']=='$mem_v2'for c in graph['cells'].values()) and not args.map_memories:
            raise ValueError('Bitvector representation requires a register-only model')
        (out/'elaborated.il').write_bytes((run/'elaborated.il').read_bytes())
        (out/'encode.ys').write_text('read_rtlil elaborated.il\n'+
            ('memory_map\ndffunmap\nopt_clean\n'if args.map_memories else'')+
            'write_json encoded.json\nwrite_smt2 -stbv -wires model.smt2\n')
        with(out/'yosys.log').open('w')as log:
            cp=subprocess.run(['yosys','-Q','encode.ys'],cwd=out,stdout=log,stderr=subprocess.STDOUT)
        if cp.returncode:raise ValueError('Bitvector encoding failed')
        model=(out/'model.smt2').read_text()
    else:model=(run/'design.smt2').read_text()
    # Translate only the deliberately small Boolean base-constraint grammar.
    # This supports no-hard-reset CLEAR lemmas without replacing their healthy
    # entry conditions by a different reset experiment.
    constraint_text=(run/'reset.smtc').read_text()
    initial_constraints=[];state=None
    for line in constraint_text.splitlines():
        if line=='initial':state=0;continue
        if line=='state 1':state=1;continue
        match=re.fullmatch(r'assume \(= \[([A-Za-z_][A-Za-z0-9_]*)\] (true|false)\)',line)
        if state is None or match is None:raise ValueError('Unsupported base constraint grammar')
        initial_constraints.append((state,match[1],match[2]))
    def chain(base):
        rows=['(set-logic '+('QF_BV'if args.encoding=='bitvector'else'QF_AUFBV')+')',model]
        for i in range(k+1):
            rows += [f'(declare-fun s{i} () {top}_s)',f'(assert ({top}_h s{i}))',
                     f'(assert ({top}_u s{i}))',
                     f'(assert (= ({top}_is s{i}) '+('true'if base and i==0 else'false')+'))']
            if i:rows.append(f'(assert ({top}_t s{i-1} s{i}))')
        if base:
            rows += [f'(assert ({top}_i s0))']
            rows += [f'(assert (= (|{top}_n {name}| s{i}) {value}))'for i,name,value in initial_constraints]
        else:
            rows += ['(assert '+invariant_at('s'+str(i))+')'for i in range(k)]
        return '\n'.join(rows)+'\n(check-sat)\n'
    queries={'base':(chain(True),'(assert (not (and '+
        ' '.join(f'({top}_a s{i})'for i in range(k+1))+')))\n(check-sat)\n')}
    prefix=chain(False)
    queries.update({f'induction-{i:03}':(prefix,f'(assert (not (|{top}_a {i}| s{k})))\n(check-sat)\n')
                    for i in sorted(invariant_indices)})
    if args.joint:
        queries={'base':queries['base'],'joint-induction':(prefix,f'(assert (not ({top}_a s{k})))\n(check-sat)\n')}
    groups={}
    if args.group_size:
        groups={f'induction-batch-{i:03}':list(range(i,min(i+args.group_size,count)))
            for i in range(0,count,args.group_size)}
        queries={'base':queries['base'],**{name:(prefix,'(assert (not (and '+
            ' '.join(f'(|{top}_a {i}| s{k})'for i in indices)+')))\n(check-sat)\n')for name,indices in groups.items()}}
    if corollaries:
        # These current-state premises are a separate, independently proved
        # inductive set. No corollary is a premise for induction or another
        # corollary. The two disjoint sets together cover every source assert.
        direct='\n'.join(['(set-logic '+('QF_BV'if args.encoding=='bitvector'else'QF_AUFBV')+')',model,
            f'(declare-fun c0 () {top}_s)',f'(assert ({top}_h c0))',f'(assert ({top}_u c0))',
            f'(assert (not ({top}_is c0)))','(assert '+invariant_at('c0')+')','(check-sat)'])+'\n'
        queries.update({f'corollary-{i:03}':(direct,f'(assert (not (|{top}_a {i}| c0)))\n(check-sat)\n')
                        for i in sorted(corollaries)})
    selected=None
    if args.origin:
        selected=[int(m[1])for m in re.finditer(r'^; yosys-smt2-assert (\d+) (.*)$',model,re.M)
                  if args.origin in m[2]]
        if not selected:raise ValueError('No selected source conclusions')
        queries={n:q for n,q in queries.items()if n=='base' or int(n.split('-')[1])in selected}
    if args.indices:
        if selected is not None:raise ValueError('Choose source origin or indices, not both')
        selected=sorted(set(int(n)for n in args.indices.split(',')))
        if not selected or any(n<0 or n>=count for n in selected):raise ValueError('Invalid partial conclusion selection')
        queries={n:q for n,q in queries.items()if n=='base' or int(n.split('-')[1])in selected}
    if args.z3_smt_tactic:
        queries={n:tuple(s.replace('(check-sat)','(check-sat-using smt)')for s in q)for n,q in queries.items()}
    if not args.compress_queries:
        for name,parts in queries.items():(out/(name+'.smt2')).write_text(''.join(parts))
    started=time.monotonic()
    def solve(name):
        query=''.join(queries[name]).encode()
        path=out/(name+'.smt2')
        if args.compress_queries:path.write_bytes(query)
        cmd=[shutil.which(args.solver)]+([f'-T:{args.timeout}','-smt2']if args.solver=='z3'else
            [f'--tlimit={args.timeout*1000}','--lang=smt2','--incremental'])+[str(out/(name+'.smt2'))]
        if args.solver_memory_mib:cmd.insert(1,'-memory:'+str(args.solver_memory_mib))
        begin=time.monotonic();code=None
        with(out/(name+'.log')).open('w')as log:
            try:code=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,timeout=args.timeout+10).returncode
            except subprocess.TimeoutExpired:pass
        raw=(out/(name+'.log')).read_bytes()
        answers=[line for line in raw.decode().splitlines()if line in ('sat','unsat','unknown')]
        row=dict(passed=code==0 and answers==['sat','unsat'] and b'(error 'not in raw,
                 exit=code,answers=answers,command=cmd,seconds=time.monotonic()-begin,
                 query_sha256=sha(query),reply_sha256=sha(raw))
        if args.compress_queries:
            packed=gzip.compress(query,mtime=0);archive=out/(name+'.smt2.gz');archive.write_bytes(packed)
            row.update(query_artifact=archive.name,query_artifact_format='gzip',query_artifact_sha256=sha(packed))
            path.unlink()
        if not args.compress_queries or not row['passed']:print(name,row['passed'],answers,flush=True)
        return name,row
    # A sequential campaign has no queued future jobs to survive an interrupt.
    if args.jobs==1:
        rows={}
        for name in queries:
            key,row=solve(name);rows[key]=row
    else:
        with ThreadPoolExecutor(max_workers=args.jobs)as pool:rows=dict(pool.map(solve,queries))
    result=dict(passed=all(r['passed']for r in rows.values()),solver=args.solver,depth=k,
                joint_complete_invariant_step=args.joint,
                conclusion_groups=groups,
                z3_smt_tactic=args.z3_smt_tactic,
                assertion_count=count,complete_conclusion_inventory=selected is None,selected_conclusions=selected,
                prior_state_joint_invariants_only=True,current_state_extra_assumptions=bool(corollaries),
                inductive_conclusions=sorted(invariant_indices),corollary_conclusions=sorted(corollaries),
                current_state_premises_for_corollaries=sorted(invariant_indices)if corollaries else[],
                all_current_state_premises_independently_proved=bool(corollaries)and all(
                    rows.get(f'induction-{i:03}',{}).get('passed',False)for i in invariant_indices),
                base_constraint_text=constraint_text,base_constraint_translation=initial_constraints,
                source_inputs_sha256=sha((run/'INPUTS.json').read_bytes()),
                state_encoding=args.encoding,exact_finite_memories_mapped=args.map_memories,
                rtlil_sha256=sha((run/'elaborated.il').read_bytes()),
                model_sha256=sha(model.encode()),runner_sha256=sha(producer),
                query_artifact_format='gzip'if args.compress_queries else'plain',
                solver_memory_limit_mib=args.solver_memory_mib or None,
                results=rows,seconds=time.monotonic()-started)
    (out/'FINISHED.json').write_text(json.dumps(result,indent=2)+'\n')
    if args.compress_queries:print(json.dumps(dict(passed=result['passed'],conclusions=len(rows)-1,
        complete=sum(r['passed']for r in rows.values()),incomplete=[n for n,r in rows.items()if not r['passed']])),flush=True)
    return 0 if result['passed']else 1


if __name__=='__main__':raise SystemExit(main())
