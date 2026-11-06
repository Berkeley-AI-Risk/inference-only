#!/usr/bin/env python3
"""Retain actual RAM and prove all byte locations using a symbolic address."""
import argparse,json,os,shutil,signal,subprocess,time
from pathlib import Path
from run_proofs import HERE,PROJECT,sha

def monitored(command,out,name):
    peak=0;stopped=False
    with (out/(name+'.log')).open('w') as log:
        proc=subprocess.Popen(command,cwd=out,stdout=log,stderr=subprocess.STDOUT)
        while proc.poll() is None:
            rows=subprocess.check_output(['/bin/ps','-axo','pid=,ppid=,rss='],text=True)
            procs=[tuple(map(int,line.split())) for line in rows.splitlines() if line.strip()]
            owned={proc.pid}
            while True:
                nxt=owned | {p for p,parent,rss in procs if parent in owned}
                if nxt==owned:break
                owned=nxt
            peak=max(peak,sum(rss*1024 for p,parent,rss in procs if p in owned))
            if peak>8*1024**3:
                stopped=True
                for pid in owned:
                    try:os.kill(pid,signal.SIGTERM)
                    except ProcessLookupError:pass
                break
            time.sleep(1)
        code=proc.wait()
    return {'exit_code':code,'peak_sampled_process_tree_rss_bytes':peak,'memory_stopped':stopped,'log_sha256':sha(out/(name+'.log'))}

def main():
    p=argparse.ArgumentParser();p.add_argument('--name',default='memory-v1');p.add_argument('--depth',default=8,type=int);a=p.parse_args()
    out=HERE/'runs'/a.name;out.mkdir(exist_ok=False)
    pins=json.loads((HERE/'SOURCE-PINS.json').read_text())
    for f,h in pins['files'].items():assert sha(PROJECT/f)==h,f
    src=(PROJECT/'home/home_boot_gate.sv').read_text();pos=src.index('\nendmodule')
    (out/'design.sv').write_text(src[:pos]+'\n'+(HERE/'memory_properties.sv').read_text()+src[pos:])
    (out/'prove.ys').write_text('''read_verilog -formal -D SYNTHESIS -sv design.sv
chparam -set USE_SHARED_VERIFIER 1 -set RESPONSE_LIMIT_CYCLES 100000000 -set LEASE_CYCLES 250000000 -set RENEW_LEAD_CYCLES 125000000 home_boot_gate
prep -top home_boot_gate -flatten
async2sync
dffunmap
opt_clean
write_smt2 -wires model.smt2
''')
    (out/'STARTED.json').write_text(json.dumps({'runner_sha256':sha(Path(__file__)),'source_pins_sha256':sha(HERE/'SOURCE-PINS.json'),'properties_sha256':sha(HERE/'memory_properties.sv'),'rss_process_tree_watchdog_bytes':8*1024**3,'depth':a.depth},indent=2)+'\n')
    records={};records['prepare']=monitored(['yosys','-Q','-T','prove.ys'],out,'prepare')
    ok=records['prepare']['exit_code']==0
    if ok:
        for name,flag in [('base',[]),('induction',['-i'])]:
            records[name]=monitored(['yosys-smtbmc','-s','cvc5','--presat','--noprogress','-t',str(a.depth),'--dump-vcd',name+'.vcd']+flag+['model.smt2'],out,name)
            ok=ok and records[name]['exit_code']==0 and 'Status: PASSED' in (out/(name+'.log')).read_text()
            if not ok:break
    result={'result':'PASS' if ok else 'NOT_PROVEN','records':records,'scope':'Real synchronous signature RAM, all 1292 byte addresses via one arbitrary constant address; current-frame write coverage and verifier-visible registered-read freshness at START/VERIFY. Actual timer values; binary clocked model. No signature or SHA correctness claim.'}
    (out/'RESULT.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2));raise SystemExit(0 if ok else 1)
if __name__=='__main__':main()
