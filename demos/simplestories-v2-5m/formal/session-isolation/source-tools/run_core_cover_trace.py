"""Reach the actual core busy-CLEAR barrier with a concrete public IO schedule.

Reuses the frozen complete core transition model byte for byte. Only the cover
experiment fixes an input trace; these constraints never enter induction.
"""
import argparse
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import time

from run_attention_ownership import HERE, load
from record_progress import sha
from run_service_relational import width


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--out',type=Path,required=True)
    ap.add_argument('--run',type=Path,default=HERE/'runs/core-model-drain-r2')
    ap.add_argument('--timeout',type=int,default=45);args=ap.parse_args()
    out=args.out.resolve();out.mkdir(parents=True,exist_ok=False);run=args.run.resolve();manifest={}
    def pin(path,digest=None):
        raw=path.read_bytes();h=sha(raw)
        if digest is not None and h!=digest:raise ValueError('Changed source artifact')
        manifest[str(path.resolve())]=h;return raw
    inp=json.loads(pin(run/'INPUTS.json'));result=json.loads(pin(run/'FINISHED.json'))
    if inp['cover_cells']!=3 or not inp['binding']['logical_entry_constrained_in_base_and_covers']:
        raise ValueError('Expected core-only covers and a real logical empty entry')
    for name,row in inp['files'].items():
        if len(pin(run/name,row['sha256']))!=row['bytes']:raise ValueError('Source length changed')
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    ports=parser.ports((run/'wrapper.sv').read_text());rows=[pin(run/'reset.smtc').decode()];schedule={}
    for step in range(22):
        values={}
        for name,(direction,shape)in ports.items():
            if direction!='input'or name in('clk','private_runtime_rsp_data_i'):continue
            bits=width(shape)
            if name=='clear_i':value=step in(0,10)
            elif name=='append_valid_i':value=step==3
            elif name=='step_valid_i':value=step==4
            elif name=='private_runtime_rsp_valid_i':value=step==13
            elif name in('reset_n','model_locked_i')or 'ready'in name:value=True
            else:value=False
            values[name]=('true'if value else'false')if bits==1 else'(_ bv'+str(int(value))+' '+str(bits)+')'
        values['model_locked_o']='true'
        if step==3:values['append_ready_o']='true'
        if step==4:values['step_ready_o']='true'
        rows.append('state '+str(step)+'\n'+''.join('assume (= ['+n+'] '+v+')\n'for n,v in values.items()))
        schedule[str(step)]=values
    constraints=''.join(rows);(out/'cover.smtc').write_text(constraints)
    model=pin(run/'design.smt2');(out/'design.smt2').write_bytes(model)
    command=['yosys-smtbmc','-s','z3','--timeout',str(args.timeout),'-t','22','-m',inp['top'],
        '--dump-smt2','z3-cover.smt2','--dump-yw','z3-cover-%.yw','--dump-vcd','z3-cover-%.vcd',
        '--dummy','z3-cover.responses','--noprogress','--unroll','-S','-memory:1024',
        '--smtc','cover.smtc','--presat','-c','design.smt2']
    started=time.monotonic();timed_out=False
    with(out/'z3-cover.log').open('w')as log:
        cp=subprocess.Popen(command,cwd=out,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
        try:code=cp.wait(timeout=args.timeout+20)
        except subprocess.TimeoutExpired:
            timed_out=True;os.killpg(cp.pid,signal.SIGTERM)
            try:cp.wait(timeout=5)
            except subprocess.TimeoutExpired:os.killpg(cp.pid,signal.SIGKILL);cp.wait()
            code=None
    raw=pin(out/'z3-cover.log').decode();status=re.findall(r'Status: (\w+)',raw)
    passed=not timed_out and code==0 and status==['PASSED']
    for path in list(out.glob('z3-cover*'))+[out/'cover.smtc',out/'design.smt2']:
        if path.is_file():pin(path)
    (out/'runner.py').write_bytes(Path(__file__).read_bytes());pin(out/'runner.py')
    receipt=dict(passed=passed,cover_count=3,source_run=str(run),source_inputs_sha256=sha((run/'INPUTS.json').read_bytes()),
        source_model_sha256=sha(model),cover_constraints_sha256=sha(constraints.encode()),
        command=command,status=status,exit=code,timed_out=timed_out,seconds=time.monotonic()-started,
        schedule=schedule,artifact_manifest=manifest,induction_proved=False,whole_device_session_theorem=False,
        scope='Actual complete core model: logical empty entry, initial CLEAR, append/STEP, busy CLEAR while an accepted model read is queued, late private reply and return to public-ready. Numerical/service seams remain free; provider response data is unconstrained. Fixed inputs apply only to reachability, never to the unbounded proof.')
    (out/'FINISHED.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    print(json.dumps({k:receipt[k]for k in('passed','status','seconds')}))
    return 0 if passed else 1


if __name__=='__main__':raise SystemExit(main())
