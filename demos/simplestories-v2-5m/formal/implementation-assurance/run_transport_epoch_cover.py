"""Check legal component reachability without repeatedly queuing boot reads.

Uses the unchanged native safety SMT. The directed COVER-only stimulus emits
one boot read, waits for its reply, then emits K/V writes. No safety assumption
or production gate changes. Both original timeout records remain unchanged.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import time

HERE=Path(__file__).resolve().parent


def load(name):
    spec=importlib.util.spec_from_file_location('_epoch_cover_'+name,HERE/(name+'.py'))
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def stimulus(*,zero_initial_fifo_witness=False):
    text=load('run_transport_epoch').cover_stimulus(80,negative=True)
    old='assume (= [core_cmd_en_i] [core_cmd_ready_o])\n'
    new='assume (= [core_cmd_en_i] (and [core_cmd_ready_o] (or (not [f_source_read_seen_q]) [f_source_return_seen_q])))\n'
    if text.count(old)!=80:raise ValueError('Directed stimulus binding changed')
    text=text.replace(old,new)
    if zero_initial_fifo_witness:
        initial='initial\n'
        for name,width,size in [('u_commands',276,32),('u_returns',257,64)]:
            for row in range(size):
                initial+='assume (= ['+name+'.memory_q['+str(row)+']] (_ bv0 '+str(width)+'))\n'
        text=initial+text
    return text


def main():
    common=load('run_handoff');sha=common.sha
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--proof',type=Path,required=True)
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--timeout',type=int,default=180)
    parser.add_argument('--zero-initial-fifo-witness',action='store_true')
    args=parser.parse_args();run=args.proof.resolve();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    inp_raw=(run/'INPUTS.json').read_bytes();inp=json.loads(inp_raw)
    if inp['mutant']or inp['assertion_cells']!=105 or inp['assumption_cells']!=54 or inp['cover_cells']!=4:
        raise ValueError('Unexpected native epoch safety model')
    for name,row in inp['files'].items():
        raw=(run/name).read_bytes()
        if len(raw)!=row['bytes']or sha(raw)!=row['sha256']:raise ValueError('Native epoch proof input changed')
    constraints=(run/'reset.smtc').read_text()+stimulus(zero_initial_fifo_witness=args.zero_initial_fifo_witness)
    (out/'cover-constraints.smtc').write_text(constraints)
    results={}
    for solver in ('z3','cvc5'):
        command=['yosys-smtbmc','-s',solver,'--unroll','--timeout',str(args.timeout),'-t','80','-m',inp['top'],
            '--smtc',str(out/'cover-constraints.smtc'),'--presat','-c','--noprogress',
            '--dump-smt2',str(out/(solver+'.smt2')),'--dummy',str(out/(solver+'.responses')),'design.smt2']
        started=time.monotonic()
        with(out/(solver+'.log')).open('w')as log:
            cp=subprocess.run(command,cwd=run,stdout=log,stderr=subprocess.STDOUT,timeout=args.timeout+20)
        log=(out/(solver+'.log')).read_bytes();reached=[int(s)for s in re.findall(rb'Reached cover statement in step (\d+)',log)]
        passed=cp.returncode==0 and re.findall(rb'Status: (\w+)',log)==[b'PASSED']and len(reached)==4
        results[solver]=dict(command=command,passed=passed,exit=cp.returncode,cover_goal_states=reached,
            log_sha256=sha(log),query_sha256=sha((out/(solver+'.smt2')).read_bytes()),
            real_solver_responses_sha256=sha((out/(solver+'.responses')).read_bytes()),seconds=time.monotonic()-started)
        print(solver,passed,reached,flush=True)
    result=dict(schema='native-transport-epoch-separate-directed-coverage-v1',passed=all(r['passed']for r in results.values()),
        proof_run=run.name,inputs_sha256=sha(inp_raw),emitted_smt_sha256=sha((run/'design.smt2').read_bytes()),
        used_cover_constraints_sha256=sha(constraints.encode()),results=results,
        safety_assumptions_added=False,original_failed_records_unchanged=True,
        zero_initial_fifo_values_chosen_for_reachability_only=args.zero_initial_fifo_witness,
        board_clock_frequency_claim=False,hardware_access=False,checker_sha256=sha(Path(__file__).read_bytes()))
    (out/'checker.py').write_bytes(Path(__file__).read_bytes());(out/'FINISHED.json').write_bytes((json.dumps(result,indent=2,sort_keys=True)+'\n').encode())
    raise SystemExit(0 if result['passed']else 1)


if __name__=='__main__':main()
