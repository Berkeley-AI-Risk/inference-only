"""Fresh reproduction of the frozen conditional model-service component.

Old development deadlines do not limit reproduction. Source, plans, complete
engine queries and finite operating controls are validated and rerun.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime,timezone
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time

HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent))
from prepare import sha,write_json
from checkpoint import snapshot
from native_induction import validate,query

PLANS=['PLAN.json','SERVICE-PLAN.json','INGRESS-PLAN.json','RAW-PLAN.json','MODEL-PLAN.json']


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--validate-only',action='store_true')
    ap.add_argument('--workers',type=int,default=4);args=ap.parse_args()
    if not 1<=args.workers<=8:raise ValueError('At most eight 4-GiB solver jobs')
    qualification=json.loads((HERE/'QUALIFICATION.json').read_text())
    if not qualification['passed']:raise ValueError('No qualified conditional component')
    for name,expected in qualification['bound_inputs'].items():
        if sha((HERE/name).read_bytes())!=expected:raise ValueError('Qualified input changed: '+name)
    jobs=[]
    for filename in PLANS:
        plan=validate(HERE,filename);checks=json.loads((HERE/plan.get('checks_file','CHECKS.json')).read_text())
        if checks['plan_sha256']!=sha((HERE/filename).read_bytes()) or not checks['all_rules_passed']:
            raise ValueError('Unfinished or stale plan: '+filename)
        body='\n'.join((HERE/name).read_text() for name in plan['bodies'])
        for name in plan['order']:
            record=checks['rules'][name];path=HERE/record['receipt'];engine=path.parent/'query.smt2'
            exact=query(plan,name,body).encode();raw=(path.parent/'z3.log').read_bytes()
            if (not record['passed'] or engine.read_bytes()!=exact or sha(exact)!=record['query_sha256'] or
                    raw.strip()!=b'unsat' or sha(raw)!=record['log_sha256']):raise ValueError('Bad exact engine evidence: '+name)
            jobs.append((name,engine))
    if len(jobs)*130>32*3600:raise ValueError('Replay could exceed accumulated solver allowance')
    if args.validate_only:
        print('Validated',len(jobs),'exact UNSAT queries, their dependencies and source identities.');return 0
    started=time.monotonic();run=HERE/'verification-runs'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    run.mkdir(parents=True)
    for label,manifest_name,folder in [('bank','SOURCES.json','project'),('service','SERVICE-SOURCES.json','service-project')]:
        manifest=json.loads((HERE/manifest_name).read_text());dest=run/('compile-'+label);dest.mkdir()
        for name in ['native.sv','compile.ys',*manifest.get('tables',{})]:shutil.copyfile(HERE/folder/name,dest/name)
        if sha((dest/'native.sv').read_bytes())!=manifest['source_sha256']:raise ValueError('Compile source changed')
        with (dest/'yosys.log').open('w') as log:
            cp=subprocess.run(['yosys','-Q','compile.ys'],cwd=dest,stdout=log,stderr=subprocess.STDOUT,timeout=120)
        if cp.returncode or sha((dest/'native.smt2').read_bytes())!=manifest['native_smt_sha256']:
            raise ValueError('Fresh native compilation differs: '+label)
    def replay(job):
        name,path=job
        if time.monotonic()-started+130>8*3600:raise ValueError('Replay wall bound')
        folder=run/name;folder.mkdir();before=time.monotonic()
        with (folder/'z3.log').open('w') as log:
            try:cp=subprocess.run(['z3','-memory:4096','-T:120',str(path)],stdout=log,stderr=subprocess.STDOUT,timeout=130)
            except subprocess.TimeoutExpired:cp=subprocess.CompletedProcess(['z3'],124)
        raw=(folder/'z3.log').read_bytes()
        result=dict(rule=name,passed=cp.returncode==0 and raw.strip()==b'unsat',exit_code=cp.returncode,
            solver_seconds=time.monotonic()-before,query_sha256=sha(path.read_bytes()),log_sha256=sha(raw))
        write_json(folder/'RESULT.json',result);return name,result
    with ThreadPoolExecutor(max_workers=args.workers) as pool:results=dict(pool.map(replay,jobs))
    for name,extra in [('bank',[]),('service',['--service'])]:
        cp=subprocess.run([sys.executable,'-B',str(HERE/'witness.py'),*extra],capture_output=True,text=True,timeout=180)
        (run/('operating-'+name+'.log')).write_text(cp.stdout+cp.stderr)
        if cp.returncode:raise ValueError('Fresh operating/defect evidence failed: '+name)
    result=dict(schema='Conditional-model-service-fresh-reproduction-v1',passed=all(v['passed'] for v in results.values()),
        source_recompiled=True,engine_queries=len(results),expected_unsat=len(results),results=results,
        solver_seconds=sum(v['solver_seconds'] for v in results.values()),elapsed_seconds=time.monotonic()-started,
        operating_evidence_replayed=True,whole_model_consumption_proved=False,whole_machine_theorem=False,
        upstream_raw_read_contract_discharged=False)
    write_json(run/'RESULT.json',result);write_json(HERE/'LATEST-VERIFICATION.json',dict(passed=result['passed'],
        result=str((run/'RESULT.json').relative_to(HERE)),sha256=sha((run/'RESULT.json').read_bytes())))
    snapshot('Conditional model-service fresh compilation, solver replay and operating evidence')
    print(json.dumps({k:v for k,v in result.items() if k!='results'},indent=2))
    return 0 if result['passed'] else 1


if __name__=='__main__':raise SystemExit(main())
