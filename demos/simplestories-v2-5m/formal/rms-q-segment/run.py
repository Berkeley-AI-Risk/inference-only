"""Reconstruct the source-bound RMS→Q segment and replay selected engines.

The formal statements are RTL/SMT-LIB plus explicit finite induction/source
specialization rules. Python reconstructs exact obligations and applications;
a recorded PASS without its source, formula and raw reply is never evidence.
"""
import argparse,json,os,pathlib,shutil,subprocess,sys,tarfile,time
from concurrent.futures import ThreadPoolExecutor,as_completed
HERE=pathlib.Path(__file__).resolve().parent


def sha(raw):return __import__('hashlib').sha256(raw).hexdigest()
def read(p):return json.loads(p.read_text())
def save(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,indent=2,sort_keys=True)+'\n')


def normalize(project):
    n=project/'rms-q-segment';sys.path.insert(0,str(n))
    from common import HERE as local
    from source_policy import native_source
    from prepare_context import reconstruction
    _,_,actual=reconstruction()
    for p in n.glob('*-SOURCES.json'):
        manifest=read(p)
        if manifest.get('sources'):
            _,rows=native_source({name:row['modules'] for name,row in manifest['sources'].items()})
            manifest['sources']=rows
        if p.name=='context-SOURCES.json':manifest['prior_context_manifest_sha256']=actual['prior_context_manifest_sha256']
        save(p,manifest)
    plans={p.name:read(p) for p in n.glob('*-PLAN.json')};done=set();active=set()
    def update(name):
        if name in done:return
        if name in active:raise ValueError('Circular plan metadata')
        active.add(name);plan=plans[name]
        for p in plan['inputs']:
            if p in plans:update(p)
        plan['inputs']={p:sha((n/p).read_bytes()) for p in plan['inputs']};save(n/name,plan)
        active.remove(name);done.add(name)
    for name in plans:update(name)
    save(n/'STATE.json',dict(active_owned_jobs=[],max_concurrent=8,memory_mib=8192,per_query_seconds=600,solver_seconds=0,
        connected_segment_proved=False,published=False,whole_machine_theorem=False))
    for d in (n/'operating').glob('*-r4'):
        os.link(n/'fixture-assets/model.memh',d/'model.memh')


def restore(project):
    n=project/'rms-q-segment'
    from native_induction import validate,query
    from prefix_forgetting import transform
    records=read(HERE/'EVIDENCE.json');census=read(HERE/'CENSUS.json')
    if {k:sorted(v) for k,v in records.items()}!=census:raise ValueError('Changed selected rule census')
    for label,rows in records.items():
        plan=validate(n,label+'-PLAN.json');body='\n'.join((n/p).read_text() for p in plan['bodies']);restored={}
        for name,record in rows.items():
            original=query(plan,name,body)
            if sha(original.encode())!=record['query_sha256']:raise ValueError('Canonical portable formula changed '+label+':'+name)
            d=n/'queries'/(label+'-'+name);d.mkdir(parents=True);(d/'query.smt2').write_text(original)
            engine=original;kind=record.get('engine','original')
            if kind=='cvc5-int':
                engine=original.replace('(bv2int ','(ubv_to_int ')
                save(d/'CONVERSION.json',dict(rule='Z3 unsigned bv2int spelling to standard ubv_to_int',original_sha256=sha(original.encode()),engine_sha256=sha(engine.encode()),no_other_changes=True))
            elif kind!='original':
                engine,conversion=transform(original,label,name);save(d/'ABSTRACTION.json',conversion)
            filename=record.get('engine_file','query.smt2');(d/filename).write_text(engine)
            if sha(engine.encode())!=record.get('engine_query_sha256',record['query_sha256']):raise ValueError('Actual portable engine input changed')
            raw=(HERE/record['log_file']).read_bytes()
            if sha(raw)!=record['log_sha256'] or raw.strip()!=record['expected'].encode():raise ValueError('Changed raw engine reply')
            (d/record.get('engine_log','z3.log')).write_bytes(raw)
            command=list(record['command']);command[-1]=str(d/filename)
            row=dict(record,command=command,receipt=str((d/'RESULT.json').relative_to(n)),plan_sha256=sha((n/(label+'-PLAN.json')).read_bytes()))
            save(d/'RESULT.json',row);restored[name]=row
        save(n/plan['checks_file'],dict(plan_sha256=sha((n/(label+'-PLAN.json')).read_bytes()),rules=restored,
            all_selected_rules_passed=True,all_rules_passed=set(restored)==set(plan['rules'])))
        # Reconstruct the exact complete ORIGINAL theory typecheck, including
        # unused candidate formulas. Typechecking is never counted as proof.
        typed=query(plan,plan['order'][0],body)
        if not typed.endswith('(check-sat)\n'):raise ValueError('Changed query terminator')
        typed=typed[:-len('(check-sat)\n')]
        for r in plan['rules'].values():typed+='\n'.join('(assert '+t+')' for t in [*r['assumptions'],r['conclusion']])+'\n'
        typed+='(exit)\n';d=n/'typechecks'/(label+'-recorded');record=read(d/'RESULT.json')
        if record['query_sha256']!=sha(typed.encode()) or record['exit_code'] or record['log_sha256']!=sha(b'') or not record['typecheck_only']:
            raise ValueError('Original type evidence changed '+label)
        (d/'typecheck.smt2').write_text(typed)


def fresh_types(project,out):
    n=project/'rms-q-segment';result={}
    def run(label):
        d=n/'typechecks'/(label+'-recorded');begin=time.monotonic()
        with (d/'z3.log').open('w') as log:r=subprocess.run(['z3','-memory:8192','-T:30',str(d/'typecheck.smt2')],stdout=log,stderr=subprocess.STDOUT,timeout=35)
        raw=(d/'z3.log').read_bytes();old=read(d/'RESULT.json')
        row=dict(old,exit_code=r.returncode,passed=r.returncode==0 and not raw.strip(),log_sha256=sha(raw),seconds=time.monotonic()-begin)
        save(d/'RESULT.json',row);return label,row
    with ThreadPoolExecutor(max_workers=8) as pool:
        for future in as_completed([pool.submit(run,label) for label in read(HERE/'CENSUS.json')]):
            label,row=future.result();result[label]=row;save(out/'ORIGINAL-TYPECHECKS.json',result)
    if any(not row['passed'] for row in result.values()):raise ValueError('Fresh original typecheck failed')
    return result


def native_replay(project,out):
    n=project/'rms-q-segment';results={}
    for label in ['context','rms-local','root-r2','divider']:
        d=out/'native-replay'/label;d.mkdir(parents=True)
        # The context recipe retains its original source-file basenames and
        # relative ROM path, making both SMT and graph byte comparison exact.
        recipe=(n/label/'compile.ys').read_text()
        for f in (n/label).rglob('*'):
            if f.is_file() and f.suffix in ['.sv','.ys','.memh']:
                target=d/f.relative_to(n/label);target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(f,target)
        begin=time.monotonic()
        with (d/'yosys.log').open('w') as log:r=subprocess.run(['yosys','-Q','compile.ys'],cwd=d,stdout=log,stderr=subprocess.STDOUT,timeout=180)
        same={name:(d/name).is_file() and (d/name).read_bytes()==(n/label/name).read_bytes() for name in ['native.smt2','native.json']}
        results[label]=dict(exit_code=r.returncode,byte_identical=same,seconds=time.monotonic()-begin)
        save(out/'NATIVE-REPLAY.json',results)
        if r.returncode or not all(same.values()):raise ValueError('Fresh native compilation differs '+label)
    return results


def fresh_engines(project,out,all_new):
    n=project/'rms-q-segment';records=read(HERE/'EVIDENCE.json')
    wanted=['rms-numeric-producer','rms-q-argument-r4','query-numeric-store','query-numeric-authority',
        'query-numeric-producer-r2','query-write-event','normalizer-frame','rms-frame-control','rms-frame-admission','record-transport-r2','q-record-context','q-record-admission-r2','admission-fold-r2','q-origin-source']
    selected=records if all_new else {k:records[k] for k in wanted}
    def run(job):
        label,name,old=job;d=n/'queries'/(label+'-'+name);actual=d/old.get('engine_file','query.smt2');log=d/old.get('engine_log','z3.log')
        if sha(actual.read_bytes())!=old.get('engine_query_sha256',old['query_sha256']):raise ValueError('Fresh solver input differs')
        cmd=['z3','-memory:8192','-T:600',str(actual)]
        if old.get('engine')=='cvc5-int':
            cmd=[sys.executable,'-B',str(project/'model-consumption/bounded_engine.py'),'--memory-mib','8192','--wall-seconds','602','--',
                'cvc5','--force-logic=ALL','--lang=smt2','--arrays-exp','--tlimit=600000',str(actual)]
        begin=time.monotonic()
        with log.open('w') as stream:
            proc=subprocess.Popen(cmd,stdout=stream,stderr=subprocess.STDOUT)
            try:code=proc.wait(timeout=607)
            except subprocess.TimeoutExpired:proc.kill();proc.wait();code=-1
        raw=log.read_bytes();row=dict(old,command=cmd,exit_code=code,passed=code==0 and raw.strip()==old['expected'].encode(),
            log_sha256=sha(raw),seconds=time.monotonic()-begin,receipt=str((d/'RESULT.json').relative_to(n)),plan_sha256=sha((n/(label+'-PLAN.json')).read_bytes()))
        save(d/'RESULT.json',row);return label,name,row
    result={}
    with ThreadPoolExecutor(max_workers=8) as pool:
        for future in as_completed([pool.submit(run,(label,name,old)) for label,rows in selected.items() for name,old in rows.items()]):
            label,name,row=future.result();result.setdefault(label,{})[name]=row
            checks=read(n/(label+'-CHECKS.json'));checks['rules'][name]=row;save(n/(label+'-CHECKS.json'),checks)
            save(out/'ENGINE-REPLAY.json',result)
            print(json.dumps(dict(component=label,rule=name,passed=row['passed'],seconds=row['seconds'])),flush=True)
    if any(not row['passed'] for rows in result.values() for row in rows.values()):raise ValueError('Fresh selected engine replay failed')
    return result


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--out',type=pathlib.Path,required=True);ap.add_argument('--model',type=pathlib.Path,required=True)
    ap.add_argument('--recorded-only',action='store_true');ap.add_argument('--all-new-engines',action='store_true');args=ap.parse_args()
    package=read(HERE/'PACKAGE.json')
    for name,want in package['files'].items():
        p=(HERE/name).resolve()
        if not p.is_relative_to(HERE) or p.is_symlink():raise ValueError('Unsafe packet member')
        raw=p.read_bytes()
        if want!=dict(bytes=len(raw),sha256=sha(raw)):raise ValueError('Changed packet '+name)
    out=args.out.resolve();out.mkdir(parents=True,exist_ok=False);model=args.model.resolve();os.environ['Q_PRODUCTION_MODEL']=str(model)
    dep=read(HERE/'DEPENDENCY.json');prior=model/dep['public_path']
    if sha((prior/'PACKAGE.json').read_bytes())!=dep['package_sha256'] or sha((prior/'project.tar.gz').read_bytes())!=dep['archive_sha256']:
        raise ValueError('Changed qualified Q dependency')
    started=time.monotonic();prior_out=out/'qualified-Q-recorded'
    with (out/'qualified-Q-recorded.log').open('w') as log:
        r=subprocess.run([sys.executable,'-B',str(prior/'run.py'),'--out',str(prior_out),'--model',str(model),'--recorded-only'],stdout=log,stderr=subprocess.STDOUT,timeout=1200)
    if r.returncode:raise ValueError('Qualified Q/operand/upstream reconstruction failed')
    project=prior_out/'project'
    with tarfile.open(HERE/'project.tar.gz','r:gz') as tar:
        for m in tar.getmembers():
            target=(project/m.name).resolve()
            if not m.isfile() or not target.is_relative_to(project) or target.exists():raise ValueError('Unsafe or overwriting project member '+m.name)
        tar.extractall(project,filter='data')
    normalize(project);restore(project)
    typed={} if args.recorded_only else fresh_types(project,out)
    native={} if args.recorded_only else native_replay(project,out)
    engines={} if args.recorded_only else fresh_engines(project,out,args.all_new_engines)
    n=project/'rms-q-segment'
    with (out/'connected-derivation.log').open('w') as log:
        r=subprocess.run([sys.executable,'-B',str(n/'qualify_derivation.py')],cwd=n,stdout=log,stderr=subprocess.STDOUT,timeout=1800)
    if r.returncode:raise ValueError('Portable connected derivation failed; see connected-derivation.log')
    if read(n/'SELECTED-CENSUS.json')!=read(HERE/'CENSUS.json'):raise ValueError('Portable proof census changed')
    result=dict(passed=True,recorded_only=args.recorded_only,selected_engine_checks=package['selected_engine_checks'],
        exact_original_and_actual_queries_reconstructed=True,complete_connected_derivation_reconstructed=True,
        qualified_Q_operand_upstream_receipts_reconstructed=True,
        original_type_components_fresh=len(typed),typechecks_counted_as_proofs=False,
        native_compilation=native,fresh_engine_query_count=sum(map(len,engines.values())),
        full_new_engine_replay=args.all_new_engines and not args.recorded_only,
        finite_native_operating_evidence_reconstructed=True,fresh_simulations=False,
        qualified=False,whole_machine_theorem=False,seconds=time.monotonic()-started)
    save(out/'RESULT.json',result);print(json.dumps(result,indent=2))


if __name__=='__main__':main()
