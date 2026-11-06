#!/usr/bin/env python3
"""Reachable positive/negative traces on exact controller; not a crypto test."""
import argparse,json,shutil,subprocess,tempfile
from pathlib import Path
from run_proofs import HERE,PROJECT,sha
p=argparse.ArgumentParser();p.add_argument('--name',default='witness-v3');a=p.parse_args()
out=HERE/'runs'/a.name;out.mkdir(exist_ok=False)
src=(PROJECT/'home/home_boot_gate.sv').read_text()
pin=json.loads((HERE/'SOURCE-PINS.json').read_text())
assert sha(PROJECT/'home/home_boot_gate.sv')==pin['files']['home/home_boot_gate.sv']
records=[]
for name,old,new in [('actual',None,None),('header-check','(index_q<128 && grant_byte_i!=selected_message_byte)',"1'b0"),('model-binding','(!admitted_root_valid_i || !root_equal)','(!admitted_root_valid_i)'),('ram-data','signature_mem[index_q-128]<=grant_byte_i;',"signature_mem[index_q-128]<=8'd0;")]:
    case=out/name;case.mkdir()
    design=src
    if old:
        assert src.count(old)==1;design=src.replace(old,new)
    (case/'controller.sv').write_text(design);shutil.copyfile(HERE/'witness.sv',case/'witness.sv')
    build=Path(tempfile.mkdtemp(prefix='sawic-auth-witness-'))
    command=['verilator','--binary','--timing','--assert','-j','1','-Wno-fatal','--Mdir',str(build),'--top-module','witness','controller.sv','witness.sv']
    with (case/'compile.log').open('w') as log: c=subprocess.run(command,cwd=case,stdout=log,stderr=subprocess.STDOUT)
    assert c.returncode==0,name+' compile failed'
    r=subprocess.run([str(build/'Vwitness')],cwd=case,capture_output=True,text=True)
    (case/'simulation.log').write_text(r.stdout+r.stderr)
    if name=='actual':good=r.returncode==0 and 'WITNESS PASS:' in r.stdout
    elif name=='header-check':good=r.returncode!=0 and 'wrong device header granted permission' in r.stdout+r.stderr
    elif name=='model-binding':good=r.returncode!=0 and 'changed model retained permission' in r.stdout+r.stderr
    else:good=r.returncode!=0 and 'signature RAM did not preserve current grant byte' in r.stdout+r.stderr
    records.append({'case':name,'expected_behavior_observed':good,'simulation_exit_code':r.returncode,'controller_sha256':sha(case/'controller.sv'),'compile_log_sha256':sha(case/'compile.log'),'simulation_log_sha256':sha(case/'simulation.log')})
    if not good:break
result={'result':'PASS' if len(records)==4 and all(r['expected_behavior_observed'] for r in records) else 'FAIL','cases':records,'scope':'Simulation witness with actual controller timer values and abstract successful crypto verdict; reaches an initial lease after full transcript, checks all 1292 RAM bytes, then checks binding/failure/reset and deliberately broken guards/RAM. No real LMS signature, nonce entropy, renewal deadline or board-power claim.'}
(out/'RESULT.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2));raise SystemExit(0 if result['result']=='PASS' else 1)
