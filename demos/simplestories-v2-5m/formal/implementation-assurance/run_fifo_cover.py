"""Check FIFO traffic goals without exporting every register at every state.

The actual source-bound SMT, constraints and dimensions are unchanged. Store
real solver responses and all queries. The original trace-export timeouts stay
unchanged; this is a separate reachability run, not a safety theorem.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time


def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--proof',type=Path,required=True)
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--timeout',type=int,default=180)
    parser.add_argument('--clock-profile',choices=('recorded','arbitrary-coincident'),default='recorded')
    args=parser.parse_args();proof=args.proof.resolve();out=args.out.resolve()
    out.mkdir(parents=True,exist_ok=False)
    inp=json.loads((proof/'INPUTS.json').read_bytes())
    for name,row in inp['files'].items():
        p=proof/name
        if p.stat().st_size!=row['bytes']or sha(p)!=row['sha256']:raise ValueError('Frozen input changed')
    if inp['mutant']or not inp['multiclock']or inp['cover_cells']!=4:raise ValueError('Unexpected coverage source')
    constraints=proof/'cover.smtc';depth=inp['cover_depth']
    if args.clock_profile=='arbitrary-coincident':
        # The safety theorem permits every independent clock schedule. This
        # is a reachability witness in that model, not a 25/100-MHz board trace.
        capacity=inp['binding']['depth'];width=inp['binding']['width'];bits=capacity.bit_length()-1
        depth=capacity*6+48
        text=(proof/'reset.smtc').read_text()+'initial\nassume (= [dut.f_slot] (_ bv0 '+str(bits)+'))\n'
        for step in range(depth):
            text+='state '+str(step)+'\n'
            for name,value in dict(core_clk_i=bool(step%2),app_clk_i=bool(step%2),
                core_reset_n_i=step>=2,app_reset_n_i=step>=2,s_valid_i=step>=2,
                s_abort_i=False,m_ready_i=step>=capacity*2+24).items():
                text+=f'assume (= [{name}] {str(value).lower()})\n'
            text+=f'assume (= [s_data_i] (_ bv1 {width}))\n'
        constraints=out/'cover-constraints.smtc';constraints.write_text(text)
    results={}
    for solver in ('z3','cvc5'):
        cmd=['yosys-smtbmc','-s',solver,'--unroll','--timeout',str(args.timeout),
            '-t',str(depth),'-m',inp['top'],'--smtc',str(constraints),
            '--presat','-c','--noprogress','--dump-smt2',str(out/(solver+'.smt2')),
            '--dummy',str(out/(solver+'.responses')),'design.smt2']
        start=time.monotonic()
        with (out/(solver+'.log')).open('w')as log:
            cp=subprocess.run(cmd,cwd=proof,stdout=log,stderr=subprocess.STDOUT,timeout=args.timeout+20)
        raw=(out/(solver+'.log')).read_bytes()
        reached=[int(x)for x in re.findall(rb'Reached cover statement in step (\d+)',raw)]
        passed=cp.returncode==0 and re.findall(rb'Status: (\w+)',raw)==[b'PASSED']and len(reached)==4
        results[solver]=dict(passed=passed,exit=cp.returncode,cover_goal_states=reached,command=cmd,
            log_sha256=sha(out/(solver+'.log')),query_sha256=sha(out/(solver+'.smt2')),
            real_solver_responses_sha256=sha(out/(solver+'.responses')),seconds=time.monotonic()-start)
        print(solver,passed,reached,flush=True)
    record=dict(schema='current-fifo-no-register-trace-export-coverage-v1',passed=all(r['passed']for r in results.values()),
        proof_run=proof.name,inputs_sha256=sha(proof/'INPUTS.json'),emitted_smt_sha256=sha(proof/'design.smt2'),
        cover_constraints_sha256=sha(proof/'cover.smtc'),results=results,
        used_cover_constraints_sha256=sha(constraints),clock_profile=args.clock_profile,
        clock_schedule_is_board_frequency_claim=False,
        safety_theorem_claimed=False,original_failed_runs_unchanged=True,
        no_register_value_dump_requested=True,hardware_access=False,checker_sha256=sha(Path(__file__)))
    (out/'FINISHED.json').write_text(json.dumps(record,indent=2,sort_keys=True)+'\n')
    raise SystemExit(0 if record['passed']else 1)


if __name__=='__main__':main()
