"""Reconstruct the complete-Q trace proof and optionally replay native engines.

Python checks source identity and literal proof applications. The formal claims
are the native RTL/SMT-LIB rules checked by engines; executing Python without
those checked receipts proves no hardware property.
"""
import argparse,gzip,hashlib,json,os,pathlib,shutil,subprocess,sys,tarfile,time
HERE=pathlib.Path(__file__).resolve().parent


def sha(raw):return hashlib.sha256(raw).hexdigest()
def read(p):return json.loads(p.read_text())
def save(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,indent=2,sort_keys=True)+'\n')


def restore_old(project):
    old=project/'model-consumption';sys.path.insert(0,str(old))
    from staged_induction import validate,query
    from smtlib import standard_datatypes
    records=read(HERE/'OPERAND-EVIDENCE.json')
    for label,rows in records.items():
        plan=validate(old,label+'-PLAN.json');body='\n'.join((old/x).read_text()for x in plan['bodies']);restored={}
        for name,record in rows.items():
            canonical=query(plan,name,body).encode()
            if sha(canonical)!=record['query_sha256']:raise ValueError('Changed old canonical query '+label+':'+name)
            d=old/'queries'/(label+'-'+name);d.mkdir(parents=True,exist_ok=False);(d/'query.smt2').write_bytes(canonical)
            actual=d/'query.smt2'
            if record.get('solver')=='cvc5':actual=d/'query.cvc5.smt2';actual.write_text(standard_datatypes(canonical.decode()))
            if sha(actual.read_bytes())!=record.get('engine_query_sha256',record['query_sha256']):raise ValueError('Changed old actual engine query')
            raw=(HERE/'operand-replies'/pathlib.Path(record['log_file']).name).read_bytes()
            if sha(raw)!=record['log_sha256']or raw.strip()!=record['expected'].encode():raise ValueError('Changed old raw solver answer')
            logname=record.get('engine_log','z3.log');(d/logname).write_bytes(raw)
            command=list(record['command']);command[-1]=str(actual)
            restored[name]=dict(record,receipt=str((d/'RESULT.json').relative_to(old)),command=command,plan_sha256=sha((old/(label+'-PLAN.json')).read_bytes()))
            save(d/'RESULT.json',restored[name])
        save(old/plan['checks_file'],dict(plan_sha256=sha((old/(label+'-PLAN.json')).read_bytes()),rules=restored,all_rules_passed=True))


def normalize_new(project):
    op=project/'q-operator';sys.path.insert(0,str(op));sys.path.insert(0,str(project))
    from source_policy import native_source
    # These fields only locate the unchanged, externally pinned source files.
    for path in op.glob('*-SOURCES.json'):
        manifest=read(path)
        if 'sources'not in manifest:continue
        selection={name:row['modules']for name,row in manifest['sources'].items()}
        source,rows=native_source(selection)
        manifest['sources']=rows;save(path,manifest)
    from q_normalizer_product import source_binding as normalizer
    from norm_shift import source_binding as helper
    from q_write_source import binding as write_binding
    from q_exponent import source_binding as exponent
    from q_output_ownership_r3 import output_binding,exponent_binding
    bindings={'q-normalizer-product/SOURCE-BINDING.json':normalizer(),
        'norm-shift/INSTANCE-BINDING.json':helper(),'q-terminal/WRITE-SOURCE.json':write_binding(),
        'q-exponent/SOURCE-BINDING.json':exponent(),
        'q-output-ownership-r3/SOURCE-BINDING.json':dict(output=output_binding(),exponent=exponent_binding(),
            control_step='Full native product implies the literal MAC-update weakening; native normalization and exponent transitions retained')}
    for name,value in bindings.items():save(op/name,value)
    plans={p.name:read(p)for p in op.glob('*-PLAN.json')};done=set();active=set()
    def update(name):
        if name in done:return
        if name in active:raise ValueError('Circular exported plan pins')
        active.add(name);plan=plans[name]
        for path in plan['inputs']:
            if path in plans:update(path)
        plan['inputs']={path:sha((op/path).read_bytes())for path in plan['inputs']}
        save(op/name,plan);active.remove(name);done.add(name)
    for name in plans:update(name)
    # This source specialization pins its provider PLAN identity. Relocation
    # changed source-path bookkeeping in that plan, never its formal rules.
    meta=op/'q-meta-safety/INSTANCE-BINDING.json';binding=read(meta)
    binding['component_plan_sha256']=sha((op/'meta-safety-r2-PLAN.json').read_bytes())
    binding['source_instance_binding_sha256']=sha((op/'q-engine/INSTANCE-BINDING.json').read_bytes())
    save(meta,binding)
    done.clear()
    for name in plans:update(name)


def restore_new(project):
    op=project/'q-operator'
    from native_induction import validate,query
    from abstract_multiply import transform as uniform_mul,transform_arithmetic
    from pruned_arithmetic import transform as pruned_mul,prune_only
    from prefix_abstraction import transform as prefix
    from prefix_arithmetic_abstraction import transform as prefix_mul
    from native_function_abstraction import transform as native,transport_relation
    records=read(HERE/'EVIDENCE.json');census=read(HERE/'CENSUS.json')
    if {l:sorted(v)for l,v in records.items()}!=census:raise ValueError('Selected rule inventory changed')
    for label,rows in records.items():
        plan=validate(op,label+'-PLAN.json');body='\n'.join((op/x).read_text()for x in plan['bodies']);restored={}
        for name,record in rows.items():
            canonical=query(plan,name,body).encode()
            if sha(canonical)!=record['query_sha256']:raise ValueError('Portable canonical query changed '+label+':'+name)
            d=op/'queries'/(label+'-'+name);d.mkdir(parents=True,exist_ok=False);(d/'query.smt2').write_bytes(canonical)
            solver=record.get('solver','z3');text=canonical.decode()
            transforms={'z3-uniform-mul':uniform_mul,'z3-uniform-arithmetic':transform_arithmetic,
                'z3-pruned-mul48':pruned_mul,'z3-pruned':prune_only,'z3-prefix-abstract':prefix,
                'z3-prefix-abstract-mul':prefix_mul,'z3-prefix-native-abstract':native,'z3-certificate-transport':transport_relation}
            if solver in transforms:engine=transforms[solver](text).encode()
            elif solver=='cvc5-int':engine=canonical.replace(b'(bv2int ',b'(ubv_to_int ')
            elif solver=='z3':engine=canonical
            else:raise ValueError('Unknown selected replay method '+solver)
            filename=record.get('engine_query_file','query.smt2');(d/filename).write_bytes(engine)
            if sha(engine)!=record.get('engine_query_sha256',record['query_sha256']):raise ValueError('Portable actual engine query changed '+label+':'+name)
            raw=(HERE/record['log_file']).read_bytes()
            if sha(raw)!=record['log_sha256']or raw.strip()!=record['expected'].encode():raise ValueError('Changed new raw solver answer')
            (d/record.get('engine_log','z3.log')).write_bytes(raw)
            command=list(record['command']);command[-1]=str(d/filename)
            restored[name]=dict(record,command=command,receipt=str((d/'RESULT.json').relative_to(op)),plan_sha256=sha((op/(label+'-PLAN.json')).read_bytes()))
            save(d/'RESULT.json',restored[name])
        save(op/plan['checks_file'],dict(plan_sha256=sha((op/(label+'-PLAN.json')).read_bytes()),rules=restored,
            all_selected_rules_passed=True,all_rules_passed=set(restored)==set(plan['rules'])))
    save(op/'STATE.json',dict(active_owned_jobs=[],max_concurrent=8,memory_mib=8192,per_query_seconds=600,solver_seconds=0,token_limit=None,
        proved=False,published=False,whole_machine_theorem=False))


def native_replay(project,out):
    op=project/'q-operator';results={}
    for name in ['mac','mul','tile','prefix','selector','shift','q-exponent']:
        d=out/'native-replay'/name;d.mkdir(parents=True)
        for file in ['native.sv','compile.ys']:shutil.copyfile(op/name/file,d/file)
        begin=time.monotonic()
        with(d/'yosys.log').open('w')as log:r=subprocess.run(['yosys','-Q','compile.ys'],cwd=d,stdout=log,stderr=subprocess.STDOUT,timeout=180)
        files=['native.smt2','native.json']
        same={f:(d/f).is_file()and(d/f).read_bytes()==(op/name/f).read_bytes()for f in files}
        results[name]=dict(exit_code=r.returncode,byte_identical=same,seconds=time.monotonic()-begin)
        if r.returncode or not all(same.values()):raise ValueError('Fresh native compilation differs '+name)
    save(out/'NATIVE-REPLAY.json',results);return results


def original_typechecks(project,out,recorded_only=False):
    """Parse/typecheck every selected ORIGINAL obligation without check-sat."""
    from concurrent.futures import ThreadPoolExecutor,as_completed
    op=project/'q-operator';census=read(HERE/'CENSUS.json')
    def run(item):
        label,names=item;plan=read(op/(label+'-PLAN.json'))
        first=(op/'queries'/(label+'-'+names[0])/'query.smt2').read_text()
        if not first.endswith('(check-sat)\n'):raise ValueError('Unexpected original query terminator')
        text=first[:-len('(check-sat)\n')]
        for name in names:
            r=plan['rules'][name]
            text+='\n'+'\n'.join('(assert '+f+')'for f in r['assumptions']+[r['conclusion']])
        text+='\n(exit)\n';d=out/'original-typechecks'/label;d.mkdir(parents=True)
        (d/'typecheck.smt2').write_text(text);begin=time.monotonic()
        if recorded_only:
            saved=read(HERE/'TYPECHECKS.json')['components'][label]
            if (not saved.get('passed')or not saved.get('typecheck_only')or not saved.get('no_check_sat')or
                    saved.get('proof_result')is not False or saved['exit_code']!=0 or saved['rules']!=len(names)or
                    saved['query_sha256']!=sha(text.encode())or saved['log_sha256']!=sha(b'')):
                raise ValueError('Recorded original typecheck differs '+label)
            (d/'z3.log').write_bytes(b'');code=0
        else:
            with(d/'z3.log').open('w')as log:
                r=subprocess.run(['z3','-memory:8192','-T:30',str(d/'typecheck.smt2')],stdout=log,stderr=subprocess.STDOUT,timeout=35)
            code=r.returncode
        raw=(d/'z3.log').read_bytes();result=dict(typecheck_only=True,proof_result=False,no_check_sat=True,
            passed=code==0 and not raw.strip(),exit_code=code,recorded_only=recorded_only,rules=len(names),seconds=time.monotonic()-begin,
            query_sha256=sha(text.encode()),log_sha256=sha(raw))
        save(d/'RESULT.json',result);return label,result
    results={}
    with ThreadPoolExecutor(max_workers=8)as pool:
        for future in as_completed([pool.submit(run,item)for item in census.items()]):
            label,result=future.result();results[label]=result;save(out/'ORIGINAL-TYPECHECKS.json',results)
    if any(not r['passed']for r in results.values()):raise ValueError('Original native-theory typecheck failed')
    return results


def fresh_engines(project,out,all_new=False):
    from concurrent.futures import ThreadPoolExecutor,as_completed
    op=project/'q-operator';census=read(HERE/'CENSUS.json');original=read(HERE/'EVIDENCE.json')
    selected=census if all_new else{
        'q-main':list(original['q-main']),
        'q-main-witness':census['q-main-witness'],'q-trace-links':census['q-trace-links'],
        'q-endpoint-links':census['q-endpoint-links'],'normalizer-faults':census['normalizer-faults']}
    # restore_new already reconstructed and checked BOTH exact query files.
    # Run those files directly in one bounded batch; full typed/source/provider
    # reconstruction follows once in trace_closure, not once per tiny group.
    jobs=[(label,name)for label,names in selected.items()for name in names]
    def run(job):
        label,name=job;old=original[label][name];d=op/'queries'/(label+'-'+name)
        actual=d/old.get('engine_query_file','query.smt2');log=d/old.get('engine_log','z3.log')
        if sha(actual.read_bytes())!=old.get('engine_query_sha256',old['query_sha256']):raise ValueError('Fresh input changed')
        command=['z3','-memory:8192','-T:600',str(actual)]
        if old.get('solver')=='cvc5-int':
            command=[sys.executable,'-B',str(project/'model-consumption/bounded_engine.py'),'--memory-mib','8192','--wall-seconds','602','--',
                'cvc5','--force-logic=ALL','--lang=smt2','--arrays-exp','--tlimit=600000',str(actual)]
        begin=time.monotonic()
        with log.open('w')as stream:
            proc=subprocess.Popen(command,stdout=stream,stderr=subprocess.STDOUT)
            try:code=proc.wait(timeout=607)
            except subprocess.TimeoutExpired:proc.kill();proc.wait();code=-1
        raw=log.read_bytes();passed=code==0 and raw.strip()==old['expected'].encode()
        row=dict(old,passed=passed,command=command,exit_code=code,seconds=time.monotonic()-begin,
            log_sha256=sha(raw),receipt=str((d/'RESULT.json').relative_to(op)),plan_sha256=sha((op/(label+'-PLAN.json')).read_bytes()))
        save(d/'RESULT.json',row)
        return label,name,row
    result={}
    with ThreadPoolExecutor(max_workers=8)as pool:
        for future in as_completed([pool.submit(run,job)for job in jobs]):
            label,name,row=future.result();result.setdefault(label,{})[name]=row
            checks=read(op/(label+'-CHECKS.json'));checks['rules'][name]=row
            checks['all_selected_rules_passed']=all(r['passed']for r in checks['rules'].values());save(op/(label+'-CHECKS.json'),checks)
            save(out/'ENGINE-REPLAY.json',result)
            print(json.dumps(dict(component=label,rule=name,passed=row['passed'],seconds=row['seconds'])),flush=True)
    if any(not r['passed']for rows in result.values()for r in rows.values()):raise ValueError('Fresh engine replay failed; every attempt was saved')
    return result


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--out',type=pathlib.Path,required=True);ap.add_argument('--model',type=pathlib.Path,required=True)
    ap.add_argument('--recorded-only',action='store_true');ap.add_argument('--all-new-engines',action='store_true');args=ap.parse_args()
    package=read(HERE/'PACKAGE.json')
    for name,want in package['files'].items():
        file=(HERE/name).resolve()
        if not file.is_relative_to(HERE)or file.is_symlink():raise ValueError('Unsafe packet member')
        raw=file.read_bytes()
        if want!=dict(bytes=len(raw),sha256=sha(raw)):raise ValueError('Changed packet member '+name)
    out=args.out.resolve();out.mkdir(parents=True,exist_ok=False);project=out/'project';project.mkdir()
    with tarfile.open(HERE/'project.tar.gz','r:gz')as tar:
        for m in tar.getmembers():
            if not m.isfile()or not(project/m.name).resolve().is_relative_to(project):raise ValueError('Unsafe project member')
        tar.extractall(project,filter='data')
    model=args.model.resolve();os.environ['Q_PRODUCTION_MODEL']=str(model)
    dependency=read(HERE/'DEPENDENCY.json');public=model/dependency['public_path']
    if sha((public/'PACKAGE.json').read_bytes())!=dependency['package_sha256']or sha((public/'project.tar.gz').read_bytes())!=dependency['archive_sha256']:
        raise ValueError('Different published operand dependency')
    upstream=model/'formal/upstream-model-values'
    with(out/'upstream-recorded.log').open('w')as log:r=subprocess.run([sys.executable,'-B',str(upstream/'run.py'),'--recorded-only'],stdout=log,stderr=subprocess.STDOUT,timeout=240)
    if r.returncode:raise ValueError('Published upstream proof reconstruction failed')
    begin=time.monotonic();restore_old(project);normalize_new(project);restore_new(project)
    typed=original_typechecks(project,out,args.recorded_only)
    compilation={}if args.recorded_only else native_replay(project,out)
    engines={}if args.recorded_only else fresh_engines(project,out,args.all_new_engines)
    op=project/'q-operator'
    command=[sys.executable,'-B',str(op/'trace_closure.py'),'--verify']
    if args.recorded_only:
        trace_types=out/'TRACE-TYPECHECK.json';save(trace_types,read(HERE/'TYPECHECKS.json')['trace'])
        command+=['--recorded-types',str(trace_types)]
    with(out/'trace-closure.log').open('w')as log:r=subprocess.run(command,cwd=op,stdout=log,stderr=subprocess.STDOUT,timeout=1200)
    if r.returncode:raise ValueError('Portable common-trace reconstruction failed')
    closure=read(op/'TRACE-CLOSURE.json')
    if closure['verified_engine_rule_census']!=read(HERE/'CENSUS.json'):raise ValueError('Portable proof closure census changed')
    finite={}
    for path in (op/'finite').rglob('RESULT.json'):
        record=read(path);d=path.parent
        if not record['passed']:raise ValueError('Unqualified finite case')
        for file,key in [('native.sv','native_sha256'),('tb.sv','bench_sha256'),('simulation.log','log_sha256')]:
            if key in record and sha((d/file).read_bytes())!=record[key]:raise ValueError('Changed finite evidence '+str(path))
        finite[str(d.relative_to(op/'finite'))]=True
    result=dict(passed=True,recorded_only=args.recorded_only,new_engine_queries=package['new_queries'],old_operand_queries=449,
        every_canonical_and_actual_engine_query_byte_identical=True,complete_common_trace_reconstructed=True,
        upstream_recorded_proof_reconstructed=True,native_compilation=compilation,
        original_obligations_typechecked=sum(r['rules']for r in typed.values()),typechecks_counted_as_proofs=False,
        fresh_engine_query_count=sum(map(len,engines.values())),finite_cases=finite,
        full_new_engine_replay=args.all_new_engines and not args.recorded_only,
        qualified=False,whole_Q_operator_proved=False,whole_machine_theorem=False,seconds=time.monotonic()-begin)
    save(out/'RESULT.json',result);print(json.dumps(result,indent=2))

if __name__=='__main__':main()
