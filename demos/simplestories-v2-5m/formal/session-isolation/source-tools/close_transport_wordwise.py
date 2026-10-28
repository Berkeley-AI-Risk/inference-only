"""Close owner-count induction with actual per-slot RTL steps and BV algebra.

Prove every real owner/valid-bit update in the complete native transition
model. Audit the actual unsigned adder cones, then check a linear combination
of those steps, counter updates, prior invariants and exhaustive 4-bit index
partitions. No current owner-count conclusion is an induction premise.
"""
import argparse
import gzip
import json
from pathlib import Path
import re
import subprocess

from run_attention_ownership import HERE
from record_progress import sha
from join_parent_conclusions import checked_query, query_templates, template_text
from run_projection_relational import instance_con


def plus(*values):
    result={}
    for scale,row in values:
        for name,value in row.items():result[name]=(result.get(name,0)+scale*value)%32
    return {n:v for n,v in result.items()if v}


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--out',type=Path,required=True)
    ap.add_argument('--timeout',type=int,default=15)
    ap.add_argument('--run',type=Path,default=HERE/'runs/model-transport-drain-client-r1')
    ap.add_argument('--part',type=Path,default=HERE/'runs/model-transport-drain-client-r1-other-steps')
    ap.add_argument('--covers',type=Path);args=ap.parse_args()
    out=args.out.resolve();out.mkdir(parents=True,exist_ok=False);manifest={}
    def pin(path,digest=None):
        raw=path.read_bytes();h=sha(raw)
        if digest is not None and h!=digest:raise ValueError('Changed proof artifact: '+str(path))
        manifest[str(path.resolve())]=h;return raw
    run=args.run.resolve();part=args.part.resolve()
    inp=json.loads(pin(run/'INPUTS.json'));result_raw=pin(run/'FINISHED.json');base=json.loads(result_raw)
    p=json.loads(pin(part/'FINISHED.json'));top=inp['top'];count=inp['assertion_cells']
    if p['depth']!=1 or p['inductive_conclusions']!=list(range(count))or p['corollary_conclusions']:
        raise ValueError('Unexpected native induction inventory')
    if p['source_inputs_sha256']!=sha(pin(run/'INPUTS.json'))or p['base_constraint_text']!=(run/'reset.smtc').read_text():
        raise ValueError('Source/entry mismatch')
    for n,row in inp['files'].items():
        if len(pin(run/n,row['sha256']))!=row['bytes']:raise ValueError('Source byte count changed')
    model=pin(part/'model.smt2'if p['state_encoding']=='bitvector'else run/'design.smt2',p['model_sha256']).decode()
    metadata={int(i):v for i,v in re.findall(r'^; yosys-smt2-assert (\d+) (.*)$',model,re.M)}
    lines=(run/'arbiter.sv').read_text().splitlines();targets=[]
    for role in('shell','layer'):
        expected="assert({1'b0,f_"+role+"_count}==f_"+role+"_actual_count);";matches=[]
        for index,location in metadata.items():
            match=re.search(r'arbiter.sv:(\d+)\.',location)
            if match and re.sub(r'\s+','',lines[int(match[1])-1])==expected:matches.append(index)
        if len(matches)!=1:raise ValueError('Owner population target is not unique')
        targets.append(matches[0])
    templates=query_templates(model,p,top,count,compact=True)
    required={'base'}|{'induction-'+str(i).zfill(3)for i in range(count)if i not in targets}
    if set(p['results'])!=required:raise ValueError('Missing independent induction steps')
    for label,row in p['results'].items():
        if checked_query(part/(label+'.smt2'),row)!=template_text(templates[label]).encode():raise ValueError('Changed query/premise')
        raw=pin(part/(label+'.log'),row['reply_sha256']).decode();pin(part/row['query_artifact'],row['query_artifact_sha256'])
        if not row['passed']or row['exit']or[l for l in raw.splitlines()if l in('sat','unsat','unknown')]!=['sat','unsat']:
            raise ValueError('Unclosed independent step')
    graph=json.loads(pin(run/'elaborated.json'))['modules'][top]
    if any(c['type']in('$assume','$anyseq')for c in graph['cells'].values()):raise ValueError('Unexpected source assumptions')
    candidates=[n[:-len('owner_fifo_q')]for n in graph['netnames']if n.endswith('u_private_ddr_arbiter.owner_fifo_q')]
    if len(candidates)!=1:raise ValueError('Native owner arbiter is not unique')
    native=candidates[0];parent=native[:-len('u_private_ddr_arbiter.')]
    actual=instance_con((run/('core.sv'if (run/'core.sv').exists()else'wrapper.sv')).read_text(),'board1_fixed_private_ddr_arbiter','u_private_ddr_arbiter')
    if actual['f_scope_i']!='f_scope'or actual['reset_n']!='reset_n':raise ValueError('Native arbiter scope/reset wiring differs')
    def bits(name,width):
        value=graph['netnames'][native+name]['bits']
        if len(value)!=width:raise ValueError('Native width changed: '+name)
        return value
    valid=bits('f_saved_valid',16);owners=bits('owner_fifo_q',16)
    bits('owner_read_pointer_q',4);bits('owner_write_pointer_q',4)
    if len(set(valid+owners))!=32 or any(not isinstance(b,int)for b in valid+owners):
        raise ValueError('Owner/valid roots are not distinct native bits')
    roots={b:('valid',i)for i,b in enumerate(valid)};roots.update({b:('owner',i)for i,b in enumerate(owners)})
    drivers={}
    for name,cell in graph['cells'].items():
        for port,direction in cell['port_directions'].items():
            if direction=='output':
                for i,b in enumerate(cell['connections'][port]):
                    if isinstance(b,int):drivers.setdefault(b,[]).append((name,port,i))
    used=set();active=set()
    def boolean(bit):
        if bit in roots:return roots[bit]
        if not isinstance(bit,int)or bit in active or len(drivers.get(bit,[]))!=1:raise ValueError('Unsupported Boolean count cone')
        active.add(bit);name,port,index=drivers[bit][0];cell=graph['cells'][name];used.add(name)
        if port!='Y'or index or len(cell['connections']['Y'])!=1:raise ValueError('Count term is not a Boolean output')
        con=cell['connections'];kind=cell['type']
        if kind in('$not','$logic_not')and len(con['A'])==1:result=('not',boolean(con['A'][0]))
        elif kind in('$logic_and','$and')and len(con['A'])==len(con['B'])==1:
            result=('and',*sorted([boolean(con['A'][0]),boolean(con['B'][0])],key=repr))
        else:raise ValueError('Unexpected state/operation in count term: '+kind)
        active.remove(bit);return result
    cones={}
    for role in('shell','layer'):
        terms={}
        for i in range(16):
            owner=('owner',i)if role=='layer'else('not',('owner',i))
            terms[('and',*sorted([('valid',i),owner],key=repr))]='I'+str(i)
        cache={}
        def polynomial(word):
            word=list(word)
            while word and word[-1]=='0':word.pop()
            if not word:return{}
            key=tuple(word)
            if key in cache:return cache[key]
            if len(word)==1:
                expression=boolean(word[0])
                if expression not in terms:raise ValueError('Actual population term has different roots')
                result={terms[expression]:1}
            else:
                if any(not isinstance(b,int)or len(drivers.get(b,[]))!=1 for b in word):raise ValueError('Non-word count cone')
                name,port,index=drivers[word[0]][0];cell=graph['cells'][name]
                if port!='Y'or index or cell['type']!='$add'or cell['connections']['Y'][:len(word)]!=word:
                    raise ValueError('Actual count is not an unsigned adder tree')
                if any(int(cell['parameters'][n],2)for n in('A_SIGNED','B_SIGNED')):
                    raise ValueError('Signed count arithmetic')
                if any(drivers[b][0]!=(name,'Y',i)for i,b in enumerate(word)):raise ValueError('Count word spans different operations')
                used.add(name)
                result={}
                for child in('A','B'):
                    for symbol,value in polynomial(cell['connections'][child]).items():
                        result[symbol]=result.get(symbol,0)+value
            cache[key]=result;return result
        actual=polynomial(bits('f_'+role+'_actual_count',6));bits('f_'+role+'_count',5)
        if actual!={'I'+str(i):1 for i in range(16)}:raise ValueError('Population does not sum exactly all sixteen Boolean slots')
        # Every add is unsigned and has at most sixteen one-bit summands.
        # No intermediate can overflow its actual output width. Check each
        # visited word's interval against the elaborated port width.
        for word,poly in cache.items():
            maximum=sum(poly.values())
            if maximum>=(1<<len(word)):raise ValueError('Population cone can overflow before the final sum')
        cones[role]=dict(modular_polynomial=actual,terms=16,unsigned_interval=[0,16],full_width=6,
            interval_below_modulus=32,native_valid_root_bits=valid,native_owner_root_bits=owners)
    for index,role in zip(targets,('shell','layer')):
        match=re.search(r'arbiter.sv:(\d+)\.',metadata[index])
        expected="assert({1'b0,f_"+role+"_count}==f_"+role+"_actual_count);"
        if not match or re.sub(r'\s+','',lines[int(match[1])-1])!=expected:raise ValueError('Target is not the actual count equality')
        retire='wire f_'+role+'_retire=response_has_owner && '+('!'if role=='shell'else'')+'owner_fifo_q[owner_read_pointer_q];'
        if re.sub(r'\s+','',retire)not in re.sub(r'\s+','',(run/'arbiter.sv').read_text()):raise ValueError('Native response-role event differs')
    replay=out/'encoding-replay';replay.mkdir();(replay/'elaborated.il').write_bytes(pin(run/'elaborated.il',p['rtlil_sha256']))
    recipe='read_rtlil elaborated.il\n'+('memory_map\ndffunmap\nopt_clean\n'if p['state_encoding']=='bitvector'and p['exact_finite_memories_mapped']else'')+'write_json encoded.json\nwrite_smt2 '+('-stbv 'if p['state_encoding']=='bitvector'else'')+'-wires model.smt2\n'
    if p['state_encoding']=='bitvector'and pin(part/'encode.ys').decode()!=recipe:raise ValueError('Encoding recipe changed')
    (replay/'encode.ys').write_text(recipe)
    with(replay/'yosys.log').open('w')as log:cp=subprocess.run(['yosys','-Q','encode.ys'],cwd=replay,stdout=log,stderr=subprocess.STDOUT,timeout=30)
    if cp.returncode or pin(replay/'model.smt2')!=model.encode():raise ValueError('Native model encoding replay differs')
    pin(replay/'encode.ys');pin(replay/'yosys.log')
    prefix=templates['induction-'+str(targets[0]).zfill(3)][0];check='(check-sat-using smt)\n'if p.get('z3_smt_tactic')else'(check-sat)\n'
    if not prefix.endswith(check):raise ValueError('Unexpected step satisfiability check')
    prefix=prefix[:-len(check)]
    def net(name,state):return'(|'+top+'_n '+native+name+'| s'+str(state)+')'
    def ext(bit):return'((_ zero_extend 4) '+bit+')'
    def event(condition):return'(ite '+condition+' (_ bv1 5) (_ bv0 5))'
    def indicator(role,i,state):
        word=net('owner_fifo_q',state)
        if role=='shell':word='(bvnot '+word+')'
        return ext('((_ extract '+str(i)+' '+str(i)+') (bvand '+net('f_saved_valid',state)+' '+word+'))')
    before='(and (|'+top+'_n '+parent+'reset_n| s0) (|'+top+'_n '+parent+'f_scope| s0))'
    after='(and (|'+top+'_n '+parent+'reset_n| s1) (|'+top+'_n '+parent+'f_scope| s1))'
    rows={}
    def solve(label,predicates,claim):
        raw=(prefix+''.join('(assert '+q+')\n'for q in predicates)+check+'(assert (not '+claim+'))\n'+check).encode()
        path=out/(label+'.smt2');path.write_bytes(raw);command=['z3','-memory:1024','-T:'+str(args.timeout),'-smt2',str(path)]
        with(out/(label+'.log')).open('w')as log:
            try:cp=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=args.timeout+5);code=cp.returncode
            except subprocess.TimeoutExpired:code=None
        reply=pin(out/(label+'.log')).decode();answers=[l for l in reply.splitlines()if l in('sat','unsat','unknown')]
        passed=code==0 and answers==['sat','unsat']and'(error 'not in reply
        archive=path.with_suffix('.smt2.gz');archive.write_bytes(gzip.compress(raw));pin(archive);path.unlink()
        rows[label]=dict(passed=passed,answers=answers,exit=code,command=command,query_sha256=sha(raw),
            query_artifact=archive.name,query_artifact_sha256=sha(archive.read_bytes()),reply_sha256=sha(reply.encode()))
        print(label,passed,answers,flush=True)
    solve('inactive-entry',['(not '+before+')'],'(and '+' '.join('(|'+top+'_a '+str(i)+'| s1)'for i in targets)+')')
    solve('guard-off',[before,'(not '+after+')'],'(and '+' '.join('(|'+top+'_a '+str(i)+'| s1)'for i in targets)+')')
    algebra={}
    for role in('shell','layer'):
        request='(and '+net('request_transfer',0)+' '+(''if role=='layer'else'(not ')+net('layer_req_valid_i',0)+(''if role=='layer'else')')+')'
        retire=net('f_'+role+'_retire',0)
        solve(role+'-counter-update',[before,after],
            '(= '+net('f_'+role+'_count',1)+' (bvsub (bvadd '+net('f_'+role+'_count',0)+' '+event(request)+') '+event(retire)+'))')
        for i in range(16):
            push=event('(and '+request+' (= '+net('owner_write_pointer_q',0)+' (_ bv'+str(i)+' 4)))')
            pop=event('(and '+retire+' (= '+net('owner_read_pointer_q',0)+' (_ bv'+str(i)+' 4)))')
            solve(role+'-slot-'+str(i).zfill(2),[before,after],
                '(= '+indicator(role,i,1)+' (bvsub (bvadd '+indicator(role,i,0)+' '+push+') '+pop+'))')
        # For every actual four-bit index and either event value, the sum of
        # its sixteen equality-selected events equals that event exactly.
        for index in range(16):
            for flag in(0,1):
                if sum(flag*int(index==i)for i in range(16))!=flag:raise ValueError('Index partition failed')
        counter={'C1':1,'C0':-1,'R':-1,'P':1}
        slots=[{'N'+str(i):1,'O'+str(i):-1,'R'+str(i):-1,'P'+str(i):1}for i in range(16)]
        prior={'C0':1,**{'O'+str(i):-1 for i in range(16)}}
        push_partition={'R':1,**{'R'+str(i):-1 for i in range(16)}}
        pop_partition={'P':1,**{'P'+str(i):-1 for i in range(16)}}
        combination=plus((1,counter),*((-1,row)for row in slots),(1,prior),(1,push_partition),(-1,pop_partition))
        target=plus((1,{'C1':1,**{'N'+str(i):-1 for i in range(16)}}))
        if combination!=target:raise ValueError('Modular induction algebra failed')
        algebra[role]=dict(modulus=32,verified_linear_combination=combination,
            index_partition_values_checked=32,old_count_equality_is_prior_invariant=True,
            lifting='Current full six-bit population is in [0,16], so congruence modulo 32 equals the zero-extended five-bit counter.')
    external_cover=None
    if args.covers:
        external_cover=json.loads(pin(args.covers/'FINISHED.json'))
        if not external_cover['passed']or external_cover['cover_count']!=inp['cover_cells']or external_cover['source_inputs_sha256']!=sha((run/'INPUTS.json').read_bytes())or external_cover['source_model_sha256']!=sha((run/'design.smt2').read_bytes()):
            raise ValueError('Cover receipt source/model/targets differ')
        for path,digest in external_cover['artifact_manifest'].items():pin(Path(path),digest)
        if external_cover['status']!=['PASSED']or external_cover['exit']!=0:raise ValueError('External cover did not pass')
    else:
        cover=base['results']['z3-cover']
        if not cover['passed']:raise ValueError('Original nonvacuity covers incomplete')
        pin(run/'z3-cover.log',cover['log_sha256']);pin(run/'z3-cover.smt2',cover['query_sha256'])
        for name,digest in cover['traces'].items():pin(run/name,digest)
    checker=out/'checker.py';checker.write_bytes(Path(__file__).read_bytes());pin(checker)
    from join_parent_conclusions import __file__ as helper
    (out/'query_checker.py').write_bytes(Path(helper).read_bytes());pin(out/'query_checker.py')
    complete=len(rows)==36 and all(r['passed']for r in rows.values())
    result=dict(conditional_parent_proof_passed=complete,missing=[]if complete else[n for n,r in rows.items()if not r['passed']],
        assertions=count,closed_inductive_conclusions=count if complete else count-2,current_state_corollaries=0,
        no_current_state_corollary_is_an_induction_premise=True,source_input_sha256=sha((run/'INPUTS.json').read_bytes()),
        source_result_sha256=sha(result_raw),complete_backend_lanes=dict(z3=complete,cvc5=False),
        native_word_steps=rows,native_population_cones=cones,checked_modular_induction_algebra=algebra,
        external_cover_receipt=str((args.covers/'FINISHED.json').resolve())if args.covers else None,
        complete_source_model_cover_passed=True,
        primitive_boundary='No primitive function or numerical output is cut in this local transport model.',
        artifact_manifest=manifest,checker_sha256=sha(checker.read_bytes()),whole_device_token_output_theorem=False,
        scope='All '+str(count)+' native invariants: '+str(count-2)+' direct induction steps plus two owner-population steps derived from 36 actual-RTL queries, exact unsigned population-adder cones, finite native-index partitions and checked modular linear algebra. Only prior-state invariants are premises. All source-model boundaries and entry conditions remain explicit.')
    (out/'CERTIFICATE.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(conditional_parent_proof_passed=complete,missing=result['missing'])))
    return 0 if complete else 1


if __name__=='__main__':raise SystemExit(main())
