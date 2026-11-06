#!/usr/bin/env python3
import argparse,json,shutil,subprocess,tempfile
from pathlib import Path
from run_proofs import HERE,PROJECT,sha
def main():
    p=argparse.ArgumentParser();p.add_argument('--name',default='renewal-witness-v1');a=p.parse_args()
    out=HERE/'runs'/a.name;out.mkdir(exist_ok=False)
    source=PROJECT/'home/home_boot_gate.sv'
    assert sha(source)==json.loads((HERE/'SOURCE-PINS.json').read_text())['files']['home/home_boot_gate.sv']
    shutil.copyfile(source,out/'controller.sv');shutil.copyfile(HERE/'renewal_witness.cpp',out/'witness.cpp')
    build=Path(tempfile.mkdtemp(prefix='sawic-renewal-witness-'))
    shutil.copyfile(source,build/'controller.sv');shutil.copyfile(HERE/'renewal_witness.cpp',build/'witness.cpp')
    command=['verilator','--cc','--exe','--build','-j','1','-Wno-fatal','-CFLAGS','-std=c++17','--top-module','home_boot_gate','-GUSE_SHARED_VERIFIER=1','-GRESPONSE_LIMIT_CYCLES=100000000','-GLEASE_CYCLES=250000000','-GRENEW_LEAD_CYCLES=125000000',"-GDEVICE_ID=128'h395c83e440d5252bfa59f6138e5ed3b8","-GGEOMETRY=256'h2128664c0025b4ed2ddbd53b2178ea926fe1b3c5e817a2b043a2abc9ee41f078",'controller.sv','witness.cpp']
    (out/'STARTED.json').write_text(json.dumps({'command':command,'controller_sha256':sha(source),'witness_sha256':sha(HERE/'renewal_witness.cpp'),'simulation_threads':1,'cycle_values_reduced':False},indent=2)+'\n')
    with (out/'compile.log').open('w') as log:r=subprocess.run(command,cwd=build,stdout=log,stderr=subprocess.STDOUT)
    if r.returncode==0:
        with (out/'simulation.log').open('w') as log:r=subprocess.run([str(build/'obj_dir/Vhome_boot_gate')],cwd=build,stdout=log,stderr=subprocess.STDOUT)
    ok=r.returncode==0 and 'WITNESS PASS' in (out/'simulation.log').read_text()
    record={'result':'PASS' if ok else 'FAIL','exit_code':r.returncode,'controller_sha256':sha(out/'controller.sv'),'witness_sha256':sha(out/'witness.cpp'),'compile_log_sha256':sha(out/'compile.log'),'simulation_log_sha256':sha(out/'simulation.log') if (out/'simulation.log').exists() else None,'scope':'Reachable controller simulation at unchanged production timer values; two accepted abstract-valid grants, complete renewal, withheld subsequent nonce/grant, stale private verifier verdict, expiry/publication guard and late-grant rejection. Not an LMS or board test.'}
    (out/'RESULT.json').write_text(json.dumps(record,indent=2)+'\n');print(json.dumps(record,indent=2));raise SystemExit(0 if ok else 1)
if __name__=='__main__':main()
