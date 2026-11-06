#!/usr/bin/env python3
"""Build the selected source with pinned vendor inputs; never access hardware.

The compiler uses the caller's authorized installation and may contact its
configured license server. Recorded evidence and prebuilt images are unchanged.
"""
from pathlib import Path
import argparse,datetime,hashlib,json,os,shutil,subprocess,time
ROOT=Path(__file__).resolve().parents[1]
MODEL=ROOT.parents[2]
TOOL_SHA='76b24d18ec9785be73de6e9e98866bbd7bec330aff67d1fa8462f71f79b5f72c'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--ide',type=Path,required=True)
 p.add_argument('--vendor-dir',type=Path,required=True)
 p.add_argument('--output',type=Path,required=True)
 p.add_argument('--dependency-manifest',type=Path,default=MODEL/'VENDOR-DEPENDENCIES.json')
 p.add_argument('--synthesis-only',action='store_true')
 a=p.parse_args();tool=a.ide/'bin/gw_sh'
 assert sha(tool)==TOOL_SHA,'Different Gowin executable'
 identity=json.loads((ROOT/'SOURCE-IDENTITY.json').read_text())
 for name,pin in identity['native_inputs'].items():assert sha(ROOT/'hardware'/name)==pin,name
 deps=json.loads(a.dependency_manifest.read_text())['downloads']
 for name,row in deps.items():
  f=a.vendor_dir/name;assert f.stat().st_size==row['bytes']and sha(f)==row['sha256'],name
 out=a.output.resolve();assert not out.exists()and not out.is_relative_to(ROOT),'Use a new output directory outside this demo'
 out.mkdir(parents=True);shutil.copytree(ROOT/'hardware/project',out/'project')
 official=out/'project/official';official.mkdir(exist_ok=True)
 for name in deps:shutil.copyfile(a.vendor_dir/name,official/name)
 tcl=(ROOT/'hardware/run.tcl').read_text()
 if a.synthesis_only:
  marker='if {[catch {run pnr}'
  assert tcl.count(marker)==1
  tcl=tcl[:tcl.index(marker)]+'run close\nexit 0\n'
 (out/'run.tcl').write_text(tcl)
 pins={str(f.relative_to(out)):sha(f)for f in out.rglob('*')if f.is_file()}
 (out/'INPUTS.json').write_text(json.dumps(pins,indent=2)+'\n')
 env=os.environ.copy();env.update(DYLD_LIBRARY_PATH=str(a.ide/'lib'),DYLD_FRAMEWORK_PATH=str(a.ide/'lib'),QT_QPA_PLATFORM='offscreen',QT_OPENGL='software')
 for name,folder in [('TMPDIR','tmp'),('XDG_CACHE_HOME','cache'),('XDG_CONFIG_HOME','config'),('XDG_DATA_HOME','data')]:
  f=out/folder;f.mkdir();env[name]=str(f)+'/'
 command=[str(tool),str(out/'run.tcl')];start=time.monotonic()
 record=dict(command=command,started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),tool_sha256=TOOL_SHA,source_identity_sha256=sha(ROOT/'SOURCE-IDENTITY.json'),synthesis_only=a.synthesis_only,hardware_access=False)
 (out/'STARTED.json').write_text(json.dumps(record,indent=2)+'\n')
 with(out/'build.log').open('w')as log:r=subprocess.run(command,cwd=out,env=env,stdout=log,stderr=subprocess.STDOUT)
 record.update(exit_code=r.returncode,elapsed_seconds=time.monotonic()-start,inputs_sha256=sha(out/'INPUTS.json'),full_timing_signoff=False)
 (out/'RESULT.json').write_text(json.dumps(record,indent=2)+'\n');print(json.dumps(record));raise SystemExit(r.returncode)
if __name__=='__main__':main()
