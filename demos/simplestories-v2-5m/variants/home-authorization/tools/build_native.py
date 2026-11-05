#!/usr/bin/env python3
"""Build the frozen source composition without accessing hardware."""
from pathlib import Path
import argparse,hashlib,json,os,shutil,subprocess,time
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--ide',type=Path,required=True)
p.add_argument('--vendor-dir',type=Path,required=True)
p.add_argument('--output',type=Path,required=True)
p.add_argument('--dependency-manifest',type=Path,default=ROOT.parents[1]/'VENDOR-DEPENDENCIES.json')
a=p.parse_args();out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
tool=a.ide/'bin/gw_sh'
assert sha(tool)=='1a2497e6752a4561b64f620e0aa68ae5da599b118f8d723ca70c491f6688678e','Different Gowin executable'
identity=json.loads((ROOT/'SOURCE-IDENTITY.json').read_text())
for name,digest in identity['native_inputs'].items():assert sha(ROOT/'hardware'/name)==digest,name
shutil.copytree(ROOT/'hardware/project',out/'project')
official=out/'project/official';official.mkdir(exist_ok=True)
for name,record in json.loads(a.dependency_manifest.read_text())['downloads'].items():
 source=a.vendor_dir/name
 assert source.stat().st_size==record['bytes']and sha(source)==record['sha256'],name
 shutil.copyfile(source,official/name)
shutil.copyfile(ROOT/'hardware/run.tcl',out/'run.tcl')
inputs={str(q.relative_to(out)):sha(q)for q in out.rglob('*')if q.is_file()}
(out/'INPUTS.json').write_text(json.dumps(inputs,indent=2)+'\n')
env=os.environ.copy();env['DYLD_LIBRARY_PATH']=str(a.ide/'lib');env['DYLD_FRAMEWORK_PATH']=str(a.ide/'lib')
env['QT_QPA_PLATFORM']='offscreen';env['QT_OPENGL']='software'
for key,folder in [('TMPDIR','tmp'),('XDG_CACHE_HOME','cache'),('XDG_CONFIG_HOME','config'),('XDG_DATA_HOME','data')]:
 d=out/folder;d.mkdir();env[key]=str(d)+'/'
command=[str(tool),str(out/'run.tcl')];started=time.monotonic()
with (out/'build.log').open('w')as log:r=subprocess.run(command,cwd=out,env=env,stdout=log,stderr=subprocess.STDOUT)
(out/'RESULT.json').write_text(json.dumps({'exit_code':r.returncode,'elapsed_seconds':time.monotonic()-started,'tool_sha256':sha(tool),'hardware_access':False,'full_timing_signoff':False},indent=2)+'\n')
raise SystemExit(r.returncode)
