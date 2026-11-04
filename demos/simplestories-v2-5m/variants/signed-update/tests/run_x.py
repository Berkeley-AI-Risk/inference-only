#!/usr/bin/env python3
import hashlib
import json
import subprocess
import tempfile
from pathlib import Path

root=Path(__file__).resolve().parents[1]
out=root/'evidence/four-state';out.mkdir(parents=True,exist_ok=True)
build=Path(tempfile.mkdtemp(prefix='swic-x-'))
sources=[root/'rtl/vendor/sha.sv',root/'rtl/su_sha256.sv',root/'rtl/su_lms_verify.sv',
         root/'rtl/swic_boot_admission.sv',root/'rtl/su_image_check.sv',root/'tests/tb_x.sv']
cmd=['iverilog','-g2012','-I',str(root/'rtl'),'-s','tb_x','-o',str(build/'tb_x')]+[str(s) for s in sources]
with (out/'build.log').open('w') as log:subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,check=True)
with (out/'run.log').open('w') as log:subprocess.run(['vvp',str(build/'tb_x')],stdout=log,stderr=subprocess.STDOUT,check=True)
assert (out/'run.log').read_text().count('PASS unknown')==6
result={'result':'PASS','cases':6,'build_command':cmd,
        'source_sha256':{str(s.relative_to(root)):hashlib.sha256(s.read_bytes()).hexdigest() for s in sources+[root/'rtl/su_policy.svh']}}
(out/'result.json').write_text(json.dumps(result,indent=2)+'\n')
print('PASS six four-state checks')
