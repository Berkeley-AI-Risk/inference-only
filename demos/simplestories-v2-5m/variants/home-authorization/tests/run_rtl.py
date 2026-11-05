#!/usr/bin/env python3
"""Real LMS/SHA gate simulation. Nonces and verified roots are test inputs."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'reference'))
import home_auth as h

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output',type=Path,default=ROOT/'evidence/rtl')
out=parser.parse_args().output.resolve()
out.mkdir(parents=True,exist_ok=False)
a=hashlib.sha256(b'model A test commitment').digest()
b=hashlib.sha256(b'model B test commitment').digest()
n1=hashlib.sha256(b'FIXED TEST NONCE 1 NOT HARDWARE ENTROPY').digest()
n2=hashlib.sha256(b'FIXED TEST NONCE 2 NOT HARDWARE ENTROPY').digest()
key=h.su.DemoAuthority(h.HOME_AUTHORITY)
def hexfile(name,data):
    (out/name).write_text(''.join(f'{v:02x}\n' for v in data))
requests={'a1':h.request_bytes(h.DEVICE_ID,n1,a),'a2':h.request_bytes(h.DEVICE_ID,n2,a),
          'b1':h.request_bytes(h.DEVICE_ID,n1,b),
          'device':h.request_bytes(bytes(16),n1,a)}
grants={}
for leaf,(name,request) in enumerate(requests.items()):
    hexfile('request-'+name+'.hex',request)
    grants[name]=request+key.sign_reserved_leaf(request,leaf)
    hexfile('grant-'+name+'.hex',grants[name])
bad=bytearray(grants['a1']);bad[-1]^=1
hexfile('grant-corrupt.hex',bad);hexfile('grant-extra.hex',grants['a1']+b'\0')
bad=bytearray(grants['a2']);bad[-1]^=1
hexfile('grant-renew-corrupt.hex',bad)
constants={'DEVICE':h.DEVICE_ID,'GEOM':h.su.GEOMETRY,'HOME_ID':key.public_key[8:24],
           'HOME_ROOT':key.public_key[24:],'A':a,'B':b,'N1':n1,'N2':n2}
(out/'fixtures.svh').write_text('\n'.join(f"localparam logic [{len(v)*8-1}:0] {k}={len(v)*8}'h{v.hex()};" for k,v in constants.items())+'\n')
sources=[ROOT/'rtl/home_boot_gate.sv',ROOT/'rtl/vendor/sha.sv',ROOT/'rtl/vendor/su_sha256.sv',
         ROOT/'rtl/vendor/su_lms_verify.sv',ROOT/'tests/tb_home.sv']
hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
build_dir=Path(tempfile.mkdtemp(prefix='sawic-home-'))
for p in sources:shutil.copyfile(p,build_dir/p.name)
shutil.copyfile(out/'fixtures.svh',build_dir/'fixtures.svh')
cmd=['verilator','--binary','--timing','--assert','-Wno-fatal','--top-module','tb_home','-j','1',
     '-I.','--Mdir','obj']+[p.name for p in sources]
start=time.monotonic()
with (out/'build.log').open('w') as log:
    build=subprocess.run(cmd,cwd=build_dir,stdout=log,stderr=subprocess.STDOUT)
if build.returncode:raise SystemExit('RTL build failed; see '+str(out/'build.log'))
with (out/'run.log').open('w') as log:
    run=subprocess.run([str(build_dir/'obj/Vtb_home')],cwd=out,stdout=log,stderr=subprocess.STDOUT)
text=(out/'run.log').read_text()
passed=run.returncode==0 and 'PASS all home-authorization cases' in text
for name,digest in hashes.items():assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest
result={'result':'PASS' if passed else 'FAIL','elapsed_seconds':time.monotonic()-start,
        'source_sha256':hashes,'build_command':cmd,'exit_code':run.returncode,
        'build_directory':str(build_dir),
        'nonce_scope':'Fixed simulation stimuli; no physical entropy claim.',
        'model_scope':'Private verified-root inputs; no complete Tang composition claim.',
        'cases':[line[5:] for line in text.splitlines() if line.startswith('PASS ')]}
(out/'RESULT.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({k:result[k] for k in ['result','elapsed_seconds','cases']},indent=2))
raise SystemExit(0 if passed else 1)
