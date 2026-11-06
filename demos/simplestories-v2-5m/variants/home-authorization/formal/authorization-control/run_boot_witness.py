#!/usr/bin/env python3
import argparse,json,shutil,subprocess,tempfile
from pathlib import Path
from run_proofs import HERE,PROJECT,sha
from run_boot_handoff import handoff_design
def main():
    p=argparse.ArgumentParser();p.add_argument('--name',default='boot-witness-v1');a=p.parse_args()
    out=HERE/'runs'/a.name;out.mkdir(exist_ok=False)
    source=PROJECT.parents[1]/'evidence/model-replacement-v2'
    prefix=(source/'model-A-signed-prefix.bin').read_bytes();grant=None
    for line in (source/'EVENTS.jsonl').read_text().splitlines():
        d=json.loads(line);g=bytes.fromhex(d.get('grant_hex',''))
        if len(g)==1420 and g[64:96]==prefix[72:104]:grant=g;break
    assert grant
    (out/'model-prefix.bin').write_bytes(prefix);(out/'grant.bin').write_bytes(grant)
    records=[]
    for name,mutant in [('actual',None),('reset-bypass','reset-bypass')]:
        case=out/name;case.mkdir();design,_=handoff_design(observe=True,mutant=mutant)
        (case/'design.sv').write_text(design);shutil.copyfile(HERE/'boot_handoff_witness.cpp',case/'witness.cpp')
        build=Path(tempfile.mkdtemp(prefix='sawic-boot-handoff-'))
        for f in ['design.sv','witness.cpp']:shutil.copyfile(case/f,build/f)
        cmd=['verilator','--cc','--exe','--build','-j','1','--no-assert','-Wno-fatal','-CFLAGS','-std=c++17','--top-module','swic_boot_admission','-GSHARE_VERIFIER=1','-GSHARE_NONCE_HASH=1','-GSHARE_LMS_HASH=1','design.sv','witness.cpp']
        with (case/'compile.log').open('w') as log:r=subprocess.run(cmd,cwd=build,stdout=log,stderr=subprocess.STDOUT)
        if r.returncode==0:r=subprocess.run([str(build/'obj_dir/Vswic_boot_admission'),str(out/'model-prefix.bin'),str(out/'grant.bin')],capture_output=True,text=True)
        else:r.stdout='';r.stderr='compile failed'
        (case/'simulation.log').write_text(r.stdout+r.stderr)
        good=(r.returncode==0 and 'WITNESS PASS' in r.stdout) if mutant is None else r.returncode!=0 and 'boot verdict survived lease ownership transfer' in r.stdout+r.stderr
        records.append({'case':name,'expected_behavior_observed':good,'exit_code':r.returncode,'design_sha256':sha(case/'design.sv'),'witness_sha256':sha(case/'witness.cpp'),'simulation_log_sha256':sha(case/'simulation.log'),'compile_log_sha256':sha(case/'compile.log')})
        if not good:break
    result={'result':'PASS' if len(records)==2 and all(x['expected_behavior_observed'] for x in records) else 'FAIL','cases':records,'model_prefix_sha256':sha(out/'model-prefix.bin'),'grant_sha256':sha(out/'grant.bin'),'scope':'Reachable full admission-to-home simulation using real published signed-prefix/grant fixtures, real admission/home/shared-LMS controllers and memories, but abstract SHA digests chosen for each fixed key. Not a cryptographic or board test. Reset-bypass control must retain the old boot verdict and be detected.'}
    (out/'RESULT.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2));raise SystemExit(0 if result['result']=='PASS' else 1)
if __name__=='__main__':main()
