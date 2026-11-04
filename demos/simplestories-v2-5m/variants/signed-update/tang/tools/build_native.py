#!/usr/bin/env python3
"""Offline native SWIC build with pinned, separately acquired vendor inputs.

No device, flash operation, download, license acceptance or publication.
"""
from pathlib import Path
import argparse,datetime,hashlib,json,os,shutil,subprocess,tempfile,time

ROOT=Path(__file__).resolve().parents[1]
GW_SHA='1a2497e6752a4561b64f620e0aa68ae5da599b118f8d723ca70c491f6688678e'
p=argparse.ArgumentParser();p.add_argument('--vendor-dir',required=True,type=Path);p.add_argument('--ide',required=True,type=Path)
p.add_argument('--dependency-manifest',required=True,type=Path);p.add_argument('--synthesis-only',action='store_true');a=p.parse_args()
executable=a.ide/'bin/gw_sh'
assert hashlib.sha256(executable.read_bytes()).hexdigest()==GW_SHA,'Gowin executable differs'
dependencies=json.loads(a.dependency_manifest.read_text())['downloads']
out=Path(tempfile.mkdtemp(prefix='swic-tang-native-'))
shutil.copytree(ROOT/'hardware/project',out/'project')
(out/'project/official').mkdir(exist_ok=True)
for name,r in dependencies.items():
    data=(a.vendor_dir/name).read_bytes()
    assert len(data)==r['bytes'] and hashlib.sha256(data).hexdigest()==r['sha256'],name
    (out/'project/official'/name).write_bytes(data)
script=(ROOT/'hardware/run.tcl').read_text()
if a.synthesis_only:script=script[:script.index('set_option -place_option')]+'run close\nexit 0\n'
(out/'run.tcl').write_text(script)
hashes={str(s.relative_to(out)):hashlib.sha256(s.read_bytes()).hexdigest() for s in out.rglob('*') if s.is_file()}
(out/'INPUTS.json').write_text(json.dumps(hashes,indent=2)+'\n')
env=os.environ.copy();env['DYLD_LIBRARY_PATH']=str(a.ide/'lib');env['DYLD_FRAMEWORK_PATH']=str(a.ide/'lib')
for name,dirname in [('TMPDIR','private-tmp'),('XDG_CACHE_HOME','private-cache'),('XDG_CONFIG_HOME','private-config'),('XDG_DATA_HOME','private-data')]:
    folder=out/dirname;folder.mkdir();env[name]=str(folder)+'/'
receipts=ROOT/'evidence/native-build';receipts.mkdir(exist_ok=True)
cmd=[str(executable),str(out/'run.tcl')]
t=time.time()
with (out/'stdout.log').open('w',buffering=1) as stdout,(out/'stderr.log').open('w',buffering=1) as stderr:
    child=subprocess.Popen(cmd,cwd=out,env=env,stdout=stdout,stderr=stderr)
    started={'directory':str(out),'pid':child.pid,'command':cmd,'synthesis_only':a.synthesis_only,
             'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'hardware_access':False,'tool_sha256':GW_SHA}
    (receipts/'STARTED.json').write_text(json.dumps(started,indent=2)+'\n')
    print(json.dumps(started),flush=True)
    awake=subprocess.Popen(['/usr/bin/caffeinate','-i','-w',str(child.pid)])
    code=child.wait();awake.wait()
result=dict(started,exit_code=code,elapsed_seconds=time.time()-t,
            stdout_sha256=hashlib.sha256((out/'stdout.log').read_bytes()).hexdigest(),
            stderr_sha256=hashlib.sha256((out/'stderr.log').read_bytes()).hexdigest(),
            inputs_sha256=hashlib.sha256((out/'INPUTS.json').read_bytes()).hexdigest())
(receipts/'RESULT.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2));raise SystemExit(0 if code==0 else 1)
