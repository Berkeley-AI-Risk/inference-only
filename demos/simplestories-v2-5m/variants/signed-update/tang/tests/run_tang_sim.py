#!/usr/bin/env python3
from pathlib import Path
import argparse,datetime,hashlib,json,subprocess,time
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--case',type=int,required=True,choices=[0,1,2,3]);p.add_argument('--fast',action='store_true');a=p.parse_args()
out=ROOT/'evidence'/('tang-fast-simulation' if a.fast else 'tang-simulation');build_bytes=(out/'BUILD.json').read_bytes();build=json.loads(build_bytes)
if any((out/f'case-{a.case}{suffix}').exists() for suffix in ['.log','-started.json','-result.json']):
    raise FileExistsError('Preserve the previous case evidence before starting another run')
for name,digest in build['source_sha256'].items():
    assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest,'source changed: '+name
fixtures=ROOT/'evidence/fixtures';records=json.loads((fixtures/'fixtures.json').read_text())
expected=next(x['tokens'] for x in records if x['case']==a.case) if a.case!=2 else [0,0]
cmd=[build['binary'],f'+CASE={a.case}',f'+EXPECTED0={expected[0]}',f'+EXPECTED1={expected[1]}',f'+FIXTURES={fixtures}']
t=time.time()
with (out/f'case-{a.case}.log').open('w',buffering=1) as log:
    child=subprocess.Popen(cmd,cwd=build['simulation_cwd'],stdout=log,stderr=subprocess.STDOUT)
    rec={'pid':child.pid,'case':a.case,'command':cmd,'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat()}
    (out/f'case-{a.case}-started.json').write_text(json.dumps(rec,indent=2)+'\n')
    keep=subprocess.Popen(['/usr/bin/caffeinate','-i','-w',str(child.pid)])
    code=child.wait();keep.wait()
log_text=(out/f'case-{a.case}.log').read_text()
marker='PASS bad signature rejected before image transaction' if a.case==2 else f'PASS {"fast" if a.fast else "full"} Tang SWIC case={a.case}'
passed=code==0 and marker in log_text and not any(x in log_text for x in ['%Fatal','%Error','Assertion failed'])
record={'case':a.case,'result':'PASS' if passed else 'FAIL','exit_code':code,'elapsed_seconds':time.time()-t,'expected_tokens':expected,
        'fast_flash_source_abstraction':a.fast,
        'build_receipt_sha256':hashlib.sha256(build_bytes).hexdigest(),
        'log_sha256':hashlib.sha256((out/f'case-{a.case}.log').read_bytes()).hexdigest()}
(out/f'case-{a.case}-result.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps(record,indent=2));raise SystemExit(0 if passed else 1)
