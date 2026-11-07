"""Seal one compiler snapshot in the retained replay output directory."""
from pathlib import Path
import argparse, hashlib, json, shutil, sys, tempfile
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
from pin_sources import main as check_pins, sha

def main():
    p=argparse.ArgumentParser();p.add_argument('--label',required=True);p.add_argument('--top',default='combined_top');p.add_argument('--binary',action='store_true');p.add_argument('--prepared',default='prepared-v1');p.add_argument('--jobs',type=int,default=1);a=p.parse_args()
    if not 1<=a.jobs<=64:raise ValueError('Choose 1 through 64 compiler workers')
    if not a.label.replace('-','').replace('_','').isalnum(): raise ValueError('Unsafe label')
    check_pins()
    out=HERE/a.label;out.mkdir(exist_ok=False)
    scratch=out/'source';scratch.mkdir()
    prepared=(HERE/a.prepared).resolve()
    if not prepared.is_relative_to(HERE):raise ValueError('Prepared source outside this private target')
    shutil.copytree(prepared/'source',scratch,dirs_exist_ok=True)
    order=(scratch/'sources.f').read_text().splitlines()
    for source in sorted((HERE/'rtl').glob('*.sv')):
        shutil.copyfile(source,scratch/source.name);order.append(source.name)
    if a.top!='combined_top':
        tb=HERE/'tests'/f'{a.top}.sv';shutil.copyfile(tb,scratch/tb.name);order.append(tb.name)
    shutil.copyfile(HERE/'fixtures-v1/fixture_constants.svh',scratch/'fixture_constants.svh')
    (scratch/'sources.f').write_text('\n'.join(order)+'\n')
    pins={str(f.relative_to(scratch)):{'bytes':f.stat().st_size,'sha256':sha(f)} for f in sorted(scratch.rglob('*')) if f.is_file()}
    (out/'SOURCE-SEAL.json').write_text(json.dumps({'scratch':str(scratch),'files':pins,'public_base':'6045f521d2f68eecf7caddd9e7df48522a718075','top':a.top,'hardware_action':False,'portable_AES_lookup_model':True},indent=2,sort_keys=True)+'\n')
    cmd=[shutil.which('verilator') or 'verilator','--binary' if a.binary else '--lint-only','--timing','-DSYNTHESIS=1','-Wno-fatal','--top-module',a.top]
    if a.binary: cmd+=['--build-jobs',str(a.jobs),'--output-split','20000','--output-split-cfuncs','500','-CFLAGS','-O2','--Mdir','obj']
    cmd+=['-f','sources.f']
    plan={'command':cmd,'cwd':str(scratch),'receipt':str(out/'native'),'source_seal_sha256':sha(out/'SOURCE-SEAL.json'),'kind':'compile' if a.binary else 'lint','top':a.top,'binary':str(scratch/'obj'/('V'+a.top)) if a.binary else None}
    (out/'PLAN.json').write_text(json.dumps(plan,indent=2)+'\n');print(json.dumps(plan,indent=2))

if __name__=='__main__': main()
