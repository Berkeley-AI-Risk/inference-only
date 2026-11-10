"""One opt-in bounded component build and simulator; no devices or retries."""
import argparse,os,platform,shutil,signal,subprocess,time
from datetime import datetime,timezone
from pathlib import Path
from common import ROOT,identity,need,save,verify
def command(argv,cwd,out,seconds):
    out.mkdir();start=time.monotonic();begin=datetime.now(timezone.utc).isoformat();code=None;stop=None
    with (out/'stdout.log').open('wb') as stdout,(out/'stderr.log').open('wb') as stderr:
        env=dict(os.environ,CCACHE_DISABLE='1',CCACHE_DIR=str(out/'cache'))
        child=subprocess.Popen(argv,cwd=cwd,stdout=stdout,stderr=stderr,start_new_session=True,env=env)
        try:code=child.wait(timeout=seconds)
        except subprocess.TimeoutExpired:
            stop='finite_stage_timeout';os.killpg(child.pid,signal.SIGTERM)
            try:code=child.wait(timeout=3)
            except subprocess.TimeoutExpired:os.killpg(child.pid,signal.SIGKILL);code=child.wait()
    receipt=dict(started_utc=begin,finished_utc=datetime.now(timezone.utc).isoformat(),elapsed_seconds=time.monotonic()-start,actual_child_exit=code,stop_reason=stop,stdout=identity(out/'stdout.log'),stderr=identity(out/'stderr.log'),command=argv,cwd=str(cwd),compiler_cache_disabled=True)
    save(out/'EXIT.json',receipt);need(code==0 and stop is None,'Stage failed/interrupted; original evidence retained, no retry');return receipt
def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--case',choices=('plain','protected','bounds'),required=True);parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
    verify();out=args.output.resolve();need(not out.exists() and not out.is_relative_to(ROOT),'Use a fresh output outside the immutable package');need(not any(c.isspace() for c in str(ROOT)+str(out)),'Use package and build paths without whitespace');out.mkdir(parents=True)
    case=args.case;protected=case!='plain';source=ROOT/'source';build=out/'build';verilator=shutil.which('verilator');need(verilator,'Verilator required')
    top='qwen_kv_hbm_transport' if case=='bounds' else 'operand_test';entry=source/('qwen_kv_hbm_transport.sv' if case=='bounds' else 'top.sv');bench=ROOT/'cases/bounds.cpp' if case=='bounds' else source/'test.cpp'
    argv=[verilator,'--cc','--exe','--build','--assert','-Wno-fatal','-j','1','--threads','1','--output-split','12000','--top-module',top,'-I'+str(source),'-y',str(source),'+libext+.sv+.v','-Mdir',str(build),'-o','component-test','-CFLAGS','-std=c++17 -O2 -ffp-contract=off -I'+str(source)+' -DPROTECTED_BUILD='+str(int(protected))]
    argv+=['-GPROTECTED_KV=1'] if case=='bounds' else ['+define+PROTECTED_PROFILE='+str(int(protected))]+(['+define+KV_PROTECTED'] if protected else [])
    argv += [str(p) for p in sorted(source.glob('*.v'))]+[str(entry),str(bench)]
    save(out/'STARTED.json',dict(case=case,manifest=identity(ROOT/'MANIFEST.json'),runner=identity(Path(__file__)),output=str(out),package_root=str(ROOT),compiler_command=argv,system=platform.system(),machine=platform.machine(),compiler_workers=1,simulator_threads=1,automatic_retry=False,physical_qualification=False))
    compiled=command(argv,ROOT,out/'compile',900);warning=(out/'compile/stderr.log').read_text()
    need(not any('%Warning-'+x+':' in warning for x in ('UNOPTFLAT','MODDUP','LATCH','MULTIDRIVEN')),'Unsafe compiler warning; no simulator launched')
    verify();shutil.copyfile(ROOT/'rom/softmax-exp2.hex',out/'softmax-exp2.hex');binary=build/'component-test'
    native=command([str(binary)],out,out/'native',240);verify()
    need(not (out/'native/stderr.log').read_bytes(),'Nonempty native stderr')
    save(out/'FINISHED.json',dict(case=case,manifest=identity(ROOT/'MANIFEST.json'),binary=identity(binary),compile=compiled,native=native,tool_completed=True,numerical_review_pending=True,physical_qualification=False))
    print('Tool completed; run the independent checker on all three cases.')
if __name__=='__main__':main()
