"""Reconstruct/check the native Q proof or recompile and rerun every obligation.

The formal specification is the native SystemVerilog plus SMT-LIB histories,
invariants, induction rules and joined Q-operands-theorem. Python orchestrates
engines and validates source and literal theorem applications; compiling this
file alone establishes no hardware property.
"""
import argparse,gzip,hashlib,json,os,pathlib,re,shutil,subprocess,sys,tarfile,tempfile,time
from concurrent.futures import ThreadPoolExecutor,as_completed

HERE=pathlib.Path(__file__).resolve().parent


def sha(raw):return hashlib.sha256(raw).hexdigest()
def read(path):return json.loads(path.read_text())
def save(path,value):
    tmp=path.with_name(path.name+'.partial');tmp.write_text(json.dumps(value,indent=2,sort_keys=True)+'\n');tmp.replace(path)


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--recorded-only',action='store_true');ap.add_argument('--out',type=pathlib.Path);ap.add_argument('--model',type=pathlib.Path);ap.add_argument('--jobs',type=int,default=8);args=ap.parse_args()
    if not 1<=args.jobs<=8:raise ValueError('Use 1..8 workers')
    package=read(HERE/'PACKAGE.json')
    for name,want in package['files'].items():
        p=(HERE/name).resolve()
        if not p.is_relative_to(HERE)or p.is_symlink():raise ValueError('Packet member escapes scope')
        raw=p.read_bytes()
        if want!=dict(bytes=len(raw),sha256=sha(raw)):raise ValueError('Packet member changed: '+name)
    if not args.out and not args.recorded_only:raise ValueError('Fresh verification requires --out <new-directory>')
    temporary=tempfile.TemporaryDirectory(prefix='q-proof-recorded-')if not args.out else None
    out=pathlib.Path(temporary.name).resolve()if temporary else args.out.resolve()
    if not temporary:out.mkdir(parents=True,exist_ok=False)
    project=out/'project';project.mkdir()
    with tarfile.open(HERE/'project.tar.gz','r:gz')as tar:
        for member in tar.getmembers():
            if not member.isfile()or not(project/member.name).resolve().is_relative_to(project):raise ValueError('Invalid project archive member')
        tar.extractall(project,filter='data')
    model=(args.model or HERE.parents[1]).resolve();os.environ['Q_PRODUCTION_MODEL']=str(model)
    for shown,actual in [('THEOREM.smt2','qcomposition/history.smt2'),('conclusions.smt2','qcomposition/conclusions.smt2')]:
        if (HERE/shown).read_bytes()!=(project/actual).read_bytes():raise ValueError('Readable statement differs from engine input')
    upstream=model/'formal/upstream-model-values'
    context=read(project/'PORTABLE-CONTEXT.json')
    if sha((upstream/'PACKAGE.json').read_bytes())!=context['upstream_package_sha256']:raise ValueError('Published memory packet changed')
    with(out/'upstream-recorded.log').open('w')as log:
        r=subprocess.run([sys.executable,'-B',str(upstream/'run.py'),'--recorded-only'],stdout=log,stderr=subprocess.STDOUT,timeout=180)
    if r.returncode:raise ValueError('Published upstream recorded proof did not validate')
    sys.path.insert(0,str(project))
    from staged_induction import validate,query
    from smtlib import standard_datatypes
    from check_derivation import check
    labels=read(project/'LABELS.json');evidence=read(HERE/'EVIDENCE.json');jobs=[];plans={}
    for label in labels:
        plan=validate(project,label+'-PLAN.json');check(label,False);plans[label]=plan
        body='\n'.join((project/name).read_text()for name in plan['bodies'])
        for name in plan['order']:
            raw=query(plan,name,body).encode();old=evidence[label][name]
            if sha(raw)!=old['query_sha256']:raise ValueError('Changed exact canonical query: '+label+':'+name)
            d=project/'queries'/(label+'-'+name);d.mkdir(parents=True);(d/'query.smt2').write_bytes(raw)
            actual=d/'query.smt2';solver=old.get('solver','z3')
            if solver=='cvc5':actual=d/'query.cvc5.smt2';actual.write_text(standard_datatypes(raw.decode()))
            logname=old.get('engine_log','z3.log');log=(HERE/old['log_file']).read_bytes()
            if sha(log)!=old['log_sha256']or log.strip()!=old['expected'].encode():raise ValueError('Recorded raw answer changed')
            if sha(actual.read_bytes())!=old.get('engine_query_sha256',old['query_sha256']):raise ValueError('Changed actual engine input')
            jobs.append(dict(label=label,name=name,folder=d,actual=actual,logname=logname,old=old,solver=solver,raw_log=log))
    if len(jobs)!=package['queries']:raise ValueError('Incomplete obligation census')
    compilation={}
    if not args.recorded_only:
        for name in ['connected','cache']:
            source=project/name;d=out/('compile-'+name);d.mkdir()
            for f in source.rglob('*'):
                if f.is_file()and(f.suffix in ['.sv','.memh']or f.name=='compile.ys'):
                    target=d/f.relative_to(source);target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(f,target)
            with(d/'compile.log').open('w')as log:r=subprocess.run(['yosys','-Q','compile.ys'],cwd=d,stdout=log,stderr=subprocess.STDOUT,timeout=180)
            compilation[name]=r.returncode==0 and(d/'native.smt2').read_bytes()==(source/'native.smt2').read_bytes()
            if not compilation[name]:raise ValueError('Fresh native compilation differs: '+name)
    started=time.monotonic();results={};count=0
    def run(job):
        old=job['old'];d=job['folder'];actual=job['actual'];log=d/job['logname'];begin=time.monotonic()
        if args.recorded_only:log.write_bytes(job['raw_log']);code=old['exit_code'];command=list(old['command']);command[-1]=str(actual)
        else:
            command=['z3','-memory:8192','-T:600',str(actual)]if job['solver']=='z3'else[sys.executable,'-B',str(project/'bounded_engine.py'),'--memory-mib','8192','--wall-seconds','602','--','cvc5','--force-logic=ALL','--lang=smt2','--arrays-exp','--tlimit=600000',str(actual)]
            with log.open('w')as stream:
                try:code=subprocess.run(command,stdout=stream,stderr=subprocess.STDOUT,timeout=607).returncode
                except subprocess.TimeoutExpired:code=-1
        raw=log.read_bytes();answers=re.findall(r'^(sat|unsat|unknown|timeout)$',raw.decode(),re.M)
        result=dict(old,passed=code==0 and answers==[old['expected']],answers=answers,exit_code=code,seconds=time.monotonic()-begin,command=command,log_sha256=sha(raw),receipt=str((d/'RESULT.json').relative_to(project)),plan_sha256=sha((project/(job['label']+'-PLAN.json')).read_bytes()),original_command=old['command'])
        save(d/'RESULT.json',result)
        return job['label'],job['name'],result
    with ThreadPoolExecutor(max_workers=args.jobs)as pool:
        for future in as_completed([pool.submit(run,job)for job in jobs]):
            label,name,r=future.result();results.setdefault(label,{})[name]=r;count+=1
            save(out/'PROGRESS.json',dict(completed=count,total=len(jobs),failed=[l+':'+n for l,rs in results.items()for n,v in rs.items()if not v['passed']],elapsed_seconds=time.monotonic()-started))
            if count%25==0 or not r['passed']:print(json.dumps(dict(completed=count,total=len(jobs),last=label+':'+name,passed=r['passed'])),flush=True)
    for label,records in results.items():save(project/plans[label]['checks_file'],dict(plan_sha256=sha((project/(label+'-PLAN.json')).read_bytes()),rules=records,all_rules_passed=all(r['passed']for r in records.values())))
    if any(not r['passed']for rows in results.values()for r in rows.values()):raise ValueError('One or more obligations did not pass; all completed work is saved')
    derivation=check('qcomposition',True)
    from source_policy import controls
    inventory=read(project/'model-consumption-setup/SOURCES.json');selection={}
    for module,row in inventory['compiled_modules'].items():selection.setdefault(row['source'],[]).append(module)
    source_refusals=controls(dict(sorted(selection.items())))
    logical_refusals={label:read(project/(label+'-DERIVATION.json'))['logical_controls']for label in labels}
    if any(not r['rejected']for rows in logical_refusals.values()for r in rows.values()):raise ValueError('Logical refusal control accepted')
    finite={}
    for path in (project/'finite').rglob('RESULT.json'):
        r=read(path);folder=path.parent
        if not r['passed']or sha((folder/'simulation.log').read_bytes())!=r['log_sha256']or sha((folder/'native.sv').read_bytes())!=r['native_sha256']or sha((folder/'tb.sv').read_bytes())!=r['bench_sha256']:raise ValueError('Finite evidence changed')
        finite[str(folder.relative_to(project/'finite'))]=True
    if len(finite)!=8:raise ValueError('Missing finite operating/defect case')
    if not args.recorded_only:
        for case in ['operating','wrong-halfword','wrong-activation','wrong-layer','wrong-group','swapped-metadata']:
            with(out/('finite-'+case+'.log')).open('w')as log:r=subprocess.run([sys.executable,'-B',str(project/'witness_job.py'),'--case',case,'--out',str(out/'fresh-operating')],stdout=log,stderr=subprocess.STDOUT,timeout=240)
            if r.returncode:raise ValueError('Fresh operating/defect check failed: '+case)
        for args2 in [[],['--defect']]:
            with(out/('finite-owner-'+str(bool(args2))+'.log')).open('w')as log:r=subprocess.run([sys.executable,'-B',str(project/'witness_owner.py'),*args2],stdout=log,stderr=subprocess.STDOUT,timeout=90)
            if r.returncode:raise ValueError('Fresh owner check failed')
    result=dict(passed=True,recorded_only=args.recorded_only,engine_queries=len(jobs),expected_sat=sum(j['old']['expected']=='sat'for j in jobs),expected_unsat=sum(j['old']['expected']=='unsat'for j in jobs),canonical_query_bytes_unchanged=True,native_compilation=compilation,upstream_recorded_proof_validated=True,finite_cases=finite,source_refusals=source_refusals,logical_refusals=logical_refusals,source_and_literal_derivation_checked=True,Q_operand_provenance_proved=derivation.get('Q_operand_provenance_theorem_proved',False),whole_machine_theorem=False,elapsed_seconds=time.monotonic()-started,solver_seconds=sum(r['seconds']for rows in results.values()for r in rows.values()))
    save(out/'RESULT.json',result);print(json.dumps(result,indent=2))


if __name__=='__main__':main()
