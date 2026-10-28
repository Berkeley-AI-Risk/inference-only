"""Check a closed induction/corollary certificate against every raw query.

Independent solver/encoding lanes may discharge different conclusions. Every
query is regenerated below from the pinned RTL model, base constraints and
disjoint property sets. Corollaries are never induction premises. Completion
requires every invariant step, every corollary, a satisfiable base and covers.
This closes the conditional parent proof, not its child contracts.
"""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import re


def sha(raw):return hashlib.sha256(raw).hexdigest()


def checked(path,digest):
    raw=path.read_bytes()
    if sha(raw)!=digest:raise ValueError('Artifact changed: '+str(path))
    return raw


def checked_query(path,row):
    if row.get('query_artifact_format')=='gzip':
        if row.get('query_artifact')!=path.name+'.gz':raise ValueError('Unexpected compressed query path')
        raw=gzip.decompress(checked(path.with_name(path.name+'.gz'),row['query_artifact_sha256']))
        if sha(raw)!=row['query_sha256']:raise ValueError('Compressed query bytes changed')
        return raw
    return checked(path,row['query_sha256'])


def template_text(value):return''.join(value)if isinstance(value,tuple)else value


def query_templates(model,part,top,count,compact=False):
    k=part['depth'];inv=set(part['inductive_conclusions']);cor=set(part['corollary_conclusions'])
    if inv&cor or inv|cor!=set(range(count)):raise ValueError('Property partition is incomplete or circular')
    if part['current_state_premises_for_corollaries']!=(sorted(inv)if cor else[]):raise ValueError('Unproved current-state premise set')
    logic='QF_BV'if part['state_encoding']=='bitvector'else'QF_AUFBV'
    def predicate(state):return'(and '+' '.join(f'(|{top}_a {i}| {state})'for i in sorted(inv))+')'if cor else f'({top}_a {state})'
    constraints=[];state=None
    for line in part['base_constraint_text'].splitlines():
        if line=='initial':state=0;continue
        if line=='state 1':state=1;continue
        m=re.fullmatch(r'assume \(= \[([A-Za-z_][A-Za-z0-9_]*)\] (true|false)\)',line)
        if m is None or state is None:raise ValueError('Unexpected base constraint')
        constraints.append((state,m[1],m[2]))
    def chain(base):
        rows=['(set-logic '+logic+')',model]
        for i in range(k+1):
            rows += [f'(declare-fun s{i} () {top}_s)',f'(assert ({top}_h s{i}))',f'(assert ({top}_u s{i}))',
                     f'(assert (= ({top}_is s{i}) '+('true'if base and i==0 else'false')+'))']
            if i:rows.append(f'(assert ({top}_t s{i-1} s{i}))')
        if base:
            rows += [f'(assert ({top}_i s0))']
            rows += [f'(assert (= (|{top}_n {name}| s{i}) {value}))'for i,name,value in constraints]
        else:rows+=['(assert '+predicate('s'+str(i))+')'for i in range(k)]
        return'\n'.join(rows)+'\n(check-sat)\n'
    queries={'base':(chain(True),'(assert (not (and '+
        ' '.join(f'({top}_a s{i})'for i in range(k+1))+')))\n(check-sat)\n')}
    prefix=chain(False)
    queries.update({f'induction-{i:03}':(prefix,f'(assert (not (|{top}_a {i}| s{k})))\n(check-sat)\n')for i in inv})
    if part.get('joint_complete_invariant_step'):
        if cor or inv!=set(range(count)):raise ValueError('Joint step must cover the full invariant set')
        queries={'base':queries['base'],'joint-induction':(prefix,f'(assert (not ({top}_a s{k})))\n(check-sat)\n')}
    groups=part.get('conclusion_groups',{})
    if groups:
        flat=[i for indices in groups.values()for i in indices]
        if cor or sorted(flat)!=list(range(count))or len(flat)!=len(set(flat))or part.get('joint_complete_invariant_step'):
            raise ValueError('Grouped induction must partition every conclusion exactly once')
        queries={'base':queries['base'],**{name:(prefix,'(assert (not (and '+
            ' '.join(f'(|{top}_a {i}| s{k})'for i in indices)+')))\n(check-sat)\n')for name,indices in groups.items()}}
    direct='\n'.join(['(set-logic '+logic+')',model,f'(declare-fun c0 () {top}_s)',
        f'(assert ({top}_h c0))',f'(assert ({top}_u c0))',f'(assert (not ({top}_is c0)))',
        '(assert '+predicate('c0')+')','(check-sat)'])+'\n'
    queries.update({f'corollary-{i:03}':(direct,f'(assert (not (|{top}_a {i}| c0)))\n(check-sat)\n')for i in cor})
    if part.get('z3_smt_tactic'):
        if part['solver']!='z3':raise ValueError('Invalid solver strategy')
        queries={n:tuple(s.replace('(check-sat)','(check-sat-using smt)')for s in q)for n,q in queries.items()}
    return queries if compact else {n:template_text(q)for n,q in queries.items()}


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--run',type=Path,required=True);ap.add_argument('--parts',type=Path,nargs='+',required=True)
    ap.add_argument('--certificate',type=Path,required=True);args=ap.parse_args()
    run=args.run.resolve();inputs_raw=(run/'INPUTS.json').read_bytes();inputs=json.loads(inputs_raw)
    source_result=json.loads((run/'FINISHED.json').read_text());count=inputs['assertion_cells'];top=inputs['top']
    for n,row in inputs['files'].items():checked(run/n,row['sha256'])
    if inputs['assumption_cells']!=0:raise ValueError('Unexpected source assumption cells')
    source_map=None;partition=None;passed={};records=[]
    for path in args.parts:
        path=path.resolve();part=json.loads((path/'FINISHED.json').read_text())
        if part['source_inputs_sha256']!=sha(inputs_raw)or part['assertion_count']!=count:
            raise ValueError('Part bound to another source/assertion inventory')
        checked(run/'elaborated.il',part['rtlil_sha256'])
        if part['base_constraint_text']!=(run/'reset.smtc').read_text():raise ValueError('Base constraints changed')
        model=checked(path/'model.smt2'if part['state_encoding']=='bitvector'else run/'design.smt2',part['model_sha256']).decode()
        metadata={int(m[1]):m[2]for m in re.finditer(r'^; yosys-smt2-assert (\d+) (.*)$',model,re.M)}
        current_partition=(part['depth'],part['inductive_conclusions'],part['corollary_conclusions'],part.get('joint_complete_invariant_step',False),part.get('conclusion_groups',{}))
        if source_map is None:source_map=metadata;partition=current_partition
        if metadata!=source_map or current_partition!=partition:raise ValueError('Property identities or proof partition differ')
        expected=query_templates(model,part,top,count,compact=True)
        base=part['results']['base']
        if not base['passed']:raise ValueError('Every selected part needs its satisfiable reset base')
        for label,row in part['results'].items():
            raw=checked_query(path/(label+'.smt2'),row)
            if label not in expected or raw!=template_text(expected[label]).encode():raise ValueError('Unexpected proof premise/query: '+label)
            log=checked(path/(label+'.log'),row['reply_sha256']).decode()
            answers=[l for l in log.splitlines()if l in('sat','unsat','unknown')]
            if row['passed']:
                if row['exit']!=0 or answers!=['sat','unsat']or'(error 'in log:raise ValueError('Invalid recorded solver success')
                passed.setdefault(label,dict(part=str(path),solver=part['solver'],encoding=part['state_encoding'],
                    query_sha256=row['query_sha256'],reply_sha256=row['reply_sha256']))
        records.append(dict(path=str(path),result_sha256=sha((path/'FINISHED.json').read_bytes())))
    if source_map is None or set(source_map)!=set(range(count)):raise ValueError('Incomplete source property map')
    required={'base','joint-induction'}if partition[3]else{'base'}|{f'induction-{i:03}'for i in partition[1]}|{f'corollary-{i:03}'for i in partition[2]}
    if partition[4]:required={'base'}|set(partition[4])
    missing=sorted(required-set(passed))
    covers={}
    for solver in('z3','cvc5'):
        label=solver+'-cover';row=source_result['results'].get(label,{})
        if row.get('passed'):
            checked(run/(label+'.log'),row['log_sha256']);checked(run/(label+'.smt2'),row['query_sha256'])
            for n,digest in row['traces'].items():checked(run/n,digest)
            covers[solver]=dict(cover_count=inputs['cover_cells'],log_sha256=row['log_sha256'])
    result=dict(conditional_parent_proof_passed=not missing and bool(covers),missing=missing,assertions=count,
        independently_closed_inductive_conclusions=partition[1],combinational_corollaries=partition[2],
        per_conclusion_evidence=passed,part_results=records,source_property_map=source_map,covers=covers,
        source_input_sha256=sha(inputs_raw),source_result_sha256=sha((run/'FINISHED.json').read_bytes()),
        whole_device_token_output_theorem=False,child_contracts_composed=False,
        scope=inputs['scope'],binding=inputs['binding'],checker_sha256=sha(Path(__file__).read_bytes()))
    args.certificate.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(conditional_parent_proof_passed=result['conditional_parent_proof_passed'],assertions=count,missing=missing)))


if __name__=='__main__':main()
