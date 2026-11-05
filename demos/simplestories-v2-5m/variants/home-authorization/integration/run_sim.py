#!/usr/bin/env python3
import argparse,hashlib,json,subprocess,time,datetime
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--build',type=Path,required=True);p.add_argument('--scenario',type=int,choices=[0,1,2,3],required=True)
a=p.parse_args();record=json.loads((a.build/'BUILD.json').read_text())
assert record['result']=='PASS'
# Bind HDL, testbench/include files and memories. Review helpers and metadata
# do not affect the compiled simulator and may be updated while it is running.
checked_sources={name:sha for name,sha in record['source_sha256'].items()
    if name.startswith('integration/project/') or name.startswith('integration/tests/')
    or name=='nonce/nonce_frontend.sv'}
for name,sha in checked_sources.items():assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==sha,name
for name,sha in record.get('compiled_snapshot_sha256',{}).items():
    assert hashlib.sha256((Path(record['build_directory'])/name).read_bytes()).hexdigest()==sha,name
if 'simulator_sha256' in record:
    assert hashlib.sha256(Path(record['binary']).read_bytes()).hexdigest()==record['simulator_sha256']
out=a.build/f'scenario-{a.scenario}';out.mkdir(exist_ok=False)
cmd=[record['binary'],'+CASE=0',f'+SCENARIO={a.scenario}',f'+FIXTURES={record["fixtures"]}',f'+HOMEFIX={record["home_fixtures"]}']
start=time.monotonic()
with (out/'run.log').open('w',buffering=1) as log:
    proc=subprocess.Popen(cmd,cwd=record['simulation_cwd'],stdout=log,stderr=subprocess.STDOUT)
    (out/'STARTED.json').write_text(json.dumps({'pid':proc.pid,'command':cmd,'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat()},indent=2)+'\n')
    code=proc.wait()
text=(out/'run.log').read_text();marker=['PASS integrated renewal preserves context','PASS integrated wrong-model authorization rejection','PASS integrated lease loss cancels pending inference','PASS integrated shared verifier rejects corrupt renewal'][a.scenario]
done={'result':'PASS' if code==0 and marker in text else 'FAIL','scenario':a.scenario,'exit_code':code,'elapsed_seconds':time.monotonic()-start,
      'compiled_source_files_checked':len(checked_sources),'runner_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
      'log_sha256':hashlib.sha256((out/'run.log').read_bytes()).hexdigest(),'build_receipt_sha256':hashlib.sha256((a.build/'BUILD.json').read_bytes()).hexdigest()}
(out/'RESULT.json').write_text(json.dumps(done,indent=2)+'\n');print(json.dumps(done,indent=2));raise SystemExit(0 if done['result']=='PASS' else 1)
