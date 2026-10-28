"""Close one multiplication corollary by proved roots and exact RTL cone identity.

The 91 inductive conclusions never assume this corollary. Actual captured
multiplier/coefficient equality is proved in the complete current RTL model.
The output cones must be the same pure finite function of those exact roots.
No arithmetic output or numerical kernel is replaced in the source model.
"""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess

from run_attention_ownership import HERE
from record_progress import sha
from join_parent_conclusions import checked_query, query_templates, template_text
from audit_semantic_permissions import dense


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--out',type=Path,required=True)
    args=ap.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    run=HERE/'runs/embedding-parent-clear-r1';part=HERE/'runs/embedding-parent-clear-r1-corollary-long'
    manifest={}
    def pin(path,digest=None):
        raw=path.read_bytes();h=sha(raw)
        if digest is not None and h!=digest:raise ValueError('Changed proof artifact '+str(path))
        manifest[str(path.resolve())]=h;return raw
    inp=json.loads(pin(run/'INPUTS.json'));result_raw=pin(run/'FINISHED.json');base=json.loads(result_raw)
    for name,row in inp['files'].items():
        if len(pin(run/name,row['sha256']))!=row['bytes']:raise ValueError('Source length changed')
    p=json.loads(pin(part/'FINISHED.json'));top=inp['top'];count=inp['assertion_cells'];cor=43
    if count!=92 or p['corollary_conclusions']!=[cor]or p['inductive_conclusions']!=[i for i in range(count)if i!=cor]:
        raise ValueError('Unexpected invariant/corollary partition')
    if not p['all_current_state_premises_independently_proved']or p['source_inputs_sha256']!=sha(pin(run/'INPUTS.json')):
        raise ValueError('Current-state premises are not independently closed')
    model=pin(part/'model.smt2',p['model_sha256']).decode()
    identity=re.search(r'^; yosys-smt2-assert 43 (.*)$',model,re.M)
    location=re.search(r'wrapper.sv:(\d+)\.',identity[1])if identity else None
    wrapper=pin(run/'wrapper.sv').decode()
    statement="if(a_f_input_u_embedding_normalizer_input_raw_i_o_when)assert(a_f_input_u_embedding_normalizer_input_raw_i_o==b_f_input_u_embedding_normalizer_input_raw_i_o);"
    if location is None or dense(wrapper.splitlines()[int(location[1])-1])!=statement:
        raise ValueError('Derived output is not actual source conclusion 43')
    frame='    always @*if(rst_n && f_joined)begin'
    before=wrapper[:wrapper.index(wrapper.splitlines()[int(location[1])-1])]
    if frame not in before:raise ValueError('Output conclusion has a different epoch guard')
    tokens=re.findall(r'\bbegin\b|\bend\b',before[before.index(frame):])
    if sum(1 if t=='begin'else-1 for t in tokens)!=1:
        raise ValueError('Output conclusion has an unreviewed additional scope')
    templates=query_templates(model,p,top,count,compact=True)
    selected=['base']+['induction-'+str(i).zfill(3)for i in p['inductive_conclusions']]
    for name in selected:
        row=p['results'][name]
        if checked_query(part/(name+'.smt2'),row)!=template_text(templates[name]).encode():raise ValueError('Changed induction formula/premise')
        raw=pin(part/(name+'.log'),row['reply_sha256']).decode()
        pin(part/row['query_artifact'],row['query_artifact_sha256'])
        if not row['passed']or row['exit']or[l for l in raw.splitlines()if l in('sat','unsat','unknown')]!=['sat','unsat']or'(error 'in raw:
            raise ValueError('Incomplete independent induction conclusion')
    graph=json.loads(pin(run/'elaborated.json'))['modules'][top]
    if any(c['type']in('$assume','$anyseq')for c in graph['cells'].values()):raise ValueError('Unexpected source assumptions')
    def bits(name):
        if name not in graph['netnames']:raise ValueError('Unknown actual net '+name)
        return graph['netnames'][name]['bits']
    drivers={}
    for name,cell in graph['cells'].items():
        for port,values in cell['connections'].items():
            if cell['port_directions'][port]=='output':
                for index,bit in enumerate(values):
                    if isinstance(bit,int):drivers.setdefault(bit,[]).append((name,port,index))
    cones={};roots={}
    for copy in('a','b'):
        roots[copy]={'coefficient':bits('u_'+copy+'.selected_coefficient'),
            'multiplier':bits('u_'+copy+'.row_multiplier_q')}
        if {n:len(v)for n,v in roots[copy].items()}!={'coefficient':10,'multiplier':16}:raise ValueError('Native factor widths differ')
        labels={}
        for name,values in roots[copy].items():
            for i,bit in enumerate(values):
                if isinstance(bit,int):
                    if bit in labels:raise ValueError('Overlapping factor roots')
                    labels[bit]=('root',name,i)
        cache={};active=set();used=set()
        def cone(bit):
            if isinstance(bit,str):
                if bit not in('0','1'):raise ValueError('Undefined bit in product cone')
                return('constant',bit)
            if bit in labels:return labels[bit]
            if bit in cache:return cache[bit]
            if bit in active or len(drivers.get(bit,[]))!=1:raise ValueError('Cyclic/undriven product cone')
            active.add(bit);name,port,index=drivers[bit][0];cell=graph['cells'][name]
            if cell['type']!='$mul':raise ValueError('Extra functional/storage cell in actual product cone: '+cell['type'])
            used.add(name)
            value=('cell',cell['type'],tuple(sorted(cell['parameters'].items())),port,index,
                tuple((p,tuple(cone(v)for v in values))for p,values in sorted(cell['connections'].items())if cell['port_directions'][p]=='input'))
            active.remove(bit);cache[bit]=value;return value
        output=bits(copy+'_f_input_u_embedding_normalizer_input_raw_i_o')
        if len(output)!=50:raise ValueError('Native normalizer carrier is not 50 bits')
        value=tuple(cone(bit)for bit in output)
        if len(used)!=1 or any(value[i]!=value[25]for i in range(26,50)):
            raise ValueError('Actual carrier is not the single native product with exact sign extension')
        cones[copy]=value
    if cones['a']!=cones['b']:raise ValueError('Actual native function cones differ')
    native=dense(pin(run/'production-embedding.sv').decode());observed=dense(pin(run/'embedding.sv').decode())
    expression="selected_product=selected_coefficient*$signed({1'b0,row_multiplier_q});"
    if expression not in native or expression not in observed:raise ValueError('Actual native multiplication expression changed')
    carrier='{{24{selected_product[25]}},selected_product}'
    if '.input_raw_i('+carrier+')'not in native:raise ValueError('Native normalizer carrier changed')
    cone_raw=json.dumps(dict(roots=roots,function=cones['a'],output_bits=50),sort_keys=True).encode()
    (out/'cone.json').write_bytes(cone_raw);pin(out/'cone.json')
    def wire(name):
        if '(define-fun |'+top+'_n '+name+'|'not in model:raise ValueError('Unknown actual model wire '+name)
        return '(|'+top+'_n '+name+'| c0)'
    prefix='\n'.join(['(set-logic QF_BV)',model,f'(declare-fun c0 () {top}_s)',
        f'(assert ({top}_h c0))',f'(assert ({top}_u c0))',f'(assert (not ({top}_is c0)))',
        '(assert (and '+' '.join(f'(|{top}_a {i}| c0)'for i in p['inductive_conclusions'])+'))',
        '(assert '+wire('rst_n')+')','(assert '+wire('f_joined')+')',
        '(assert '+wire('a_f_input_u_embedding_normalizer_input_raw_i_o_when')+')'])+'\n'
    factors={}
    for name,signal in [('coefficient','selected_coefficient'),('multiplier','row_multiplier_q')]:
        query=prefix+'(check-sat)\n(assert (not (= '+wire('u_a.'+signal)+' '+wire('u_b.'+signal)+')))\n(check-sat)\n'
        path=out/(name+'.smt2');path.write_text(query)
        command=[shutil.which('z3'),'-memory:1024','-T:25','-smt2',str(path)]
        with(out/(name+'.log')).open('w')as log:
            cp=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=30)
        raw=(out/(name+'.log')).read_text();answers=[l for l in raw.splitlines()if l in('sat','unsat','unknown')]
        passed=cp.returncode==0 and answers==['sat','unsat']and'(error 'not in raw
        factors[name]=dict(passed=passed,answers=answers,command=command,exit=cp.returncode,
            query_sha256=sha(pin(path)),reply_sha256=sha(pin(out/(name+'.log'))))
        print(name,passed,answers,flush=True)
    cover=base['results']['z3-cover']
    if not cover['passed']:raise ValueError('Missing nonvacuity covers')
    pin(run/'z3-cover.log',cover['log_sha256']);pin(run/'z3-cover.smt2',cover['query_sha256'])
    for name,h in cover['traces'].items():pin(run/name,h)
    replay=out/'encoding-replay';replay.mkdir();(replay/'elaborated.il').write_bytes(pin(run/'elaborated.il',p['rtlil_sha256']))
    recipe='read_rtlil elaborated.il\nwrite_json encoded.json\nwrite_smt2 -stbv -wires model.smt2\n'
    (replay/'encode.ys').write_text(recipe)
    with(replay/'yosys.log').open('w')as log:
        cp=subprocess.run(['yosys','-Q','encode.ys'],cwd=replay,stdout=log,stderr=subprocess.STDOUT,timeout=30)
    if cp.returncode or pin(replay/'model.smt2')!=model.encode():raise ValueError('Exact model encoding replay differs')
    pin(replay/'encode.ys');pin(replay/'yosys.log')
    (out/'checker.py').write_bytes(Path(__file__).read_bytes());pin(out/'checker.py')
    from join_parent_conclusions import __file__ as helper
    (out/'query_checker.py').write_bytes(Path(helper).read_bytes());pin(out/'query_checker.py')
    complete=all(r['passed']for r in factors.values())
    result=dict(conditional_parent_proof_passed=complete,missing=[]if complete else['root-factor equality'],
        assertions=count,closed_inductive_conclusions=91,current_state_corollaries=1,
        no_current_state_corollary_is_an_induction_premise=True,
        source_input_sha256=sha((run/'INPUTS.json').read_bytes()),source_result_sha256=sha(result_raw),
        complete_backend_lanes=dict(z3=complete,cvc5=False),root_factor_results=factors,
        derived_corollary=dict(index=cor,kind='exact source-bound pure-function cone congruence',
            cone_sha256=sha(cone_raw),output_bits=50,current_premises=p['inductive_conclusions']),
        artifact_manifest=manifest,checker_sha256=sha(Path(__file__).read_bytes()),
        numerical_arithmetic_retained=True,whole_device_token_output_theorem=False,
        scope='All 91 actual embedding controller/input conclusions independently inductive. Output corollary 43 follows from current-RTL factor equality and identical one-multiply/sign-extension cones. No current corollary is an induction premise; no arithmetic output is abstracted. Numerical child and enclosing drain contracts remain separate.')
    (out/'CERTIFICATE.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps({k:result[k]for k in('conditional_parent_proof_passed','assertions','missing')}))
    return 0 if complete else 1


if __name__=='__main__':raise SystemExit(main())
