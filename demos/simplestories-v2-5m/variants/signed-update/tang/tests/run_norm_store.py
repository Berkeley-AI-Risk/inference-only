#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,shutil,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
out=ROOT/'evidence/norm-store';out.mkdir(exist_ok=True)
build=Path(tempfile.mkdtemp(prefix='swic-norm-'))
sources=[ROOT/'hardware/project/swic/swic_norm_store.sv',ROOT/'tests/tb_norm_store.sv']
for s in sources:shutil.copyfile(s,build/s.name)
cmd=['verilator','--binary','--timing','-Wno-fatal','--top-module','tb_norm_store','-j','1','--Mdir','obj']+[s.name for s in sources]
with (out/'build.log').open('w') as log:subprocess.run(cmd,cwd=build,stdout=log,stderr=subprocess.STDOUT,check=True)
with (out/'run.log').open('w') as log:subprocess.run([str(build/'obj/Vtb_norm_store'),f'+FIXTURES={ROOT/"evidence/fixtures"}'],stdout=log,stderr=subprocess.STDOUT,check=True)
text=(out/'run.log').read_text()
assert 'PASS norm-store regression' in text and '%Fatal' not in text
result={'result':'PASS','positive_models':2,'rows_per_model':3328,'read_ports':2,
        'negative_cases':['coefficient -512','zero scale multiplier'],'reset_and_output_masking':True,
        'source_sha256':{str(s.relative_to(ROOT)):hashlib.sha256(s.read_bytes()).hexdigest() for s in sources}}
(out/'result.json').write_text(json.dumps(result,indent=2)+'\n');print('PASS norm-store regression: all rows on both ports, changed model, reset and invalid encodings')
