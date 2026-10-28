"""Run one real solver on a selected immutable session-evidence query."""
import argparse
import gzip
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import time

HERE=Path(__file__).resolve().parent


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--model',type=Path,default=HERE.parents[1])
    p.add_argument('--run',required=True);p.add_argument('--query',required=True)
    p.add_argument('--solver',choices=('z3','cvc5'),required=True);p.add_argument('--out',type=Path,required=True)
    p.add_argument('--timeout',type=int,default=120);args=p.parse_args()
    if not 1<=args.timeout<=900:p.error('Timeout must be 1..900 seconds')
    spec=importlib.util.spec_from_file_location('_session_replay_checker',HERE/'check_recorded.py')
    checker=importlib.util.module_from_spec(spec);spec.loader.exec_module(checker);e=checker.Evidence(args.model)
    checker.need(args.run in e.index['selected_directories'],'Run is not selected')
    checker.safe(e.root,args.query);checker.need(args.query.endswith('.smt2'),'Choose an SMT query')
    prefix='runs/'+args.run+'/';logical=prefix+args.query
    if logical in e.index['files']:raw=e.raw(logical)
    else:
        checker.need(logical+'.gz'in e.index['files'],'Selected query is absent')
        raw=gzip.decompress(e.raw(logical+'.gz'))
    text=raw.decode();digest=checker.sha(raw)
    checker.need(not re.search(r'^\s*\((?:include|exec|eval|system)\b',text,re.M),'External query command refused')
    response=logical[:-len('.smt2')]+'.responses';expected=None
    if response in e.index['files']:
        expected=re.findall(r'^(sat|unsat|unknown)\s*$',e.raw(response).decode(),re.M)
    candidates=[]
    def visit(value):
        if isinstance(value,dict):
            if value.get('query_sha256')==digest and value.get('passed')and value.get('answers'):
                candidates.append(value['answers'])
            for v in value.values():visit(v)
        elif isinstance(value,list):
            for v in value:visit(v)
    for name in ('FINISHED.json','CERTIFICATE.json'):
        if prefix+name in e.index['files']:visit(e.json(prefix+name))
    if expected is None and candidates:
        checker.need(all(x==candidates[0]for x in candidates),'Conflicting recorded expectations');expected=candidates[0]
    checker.need(expected and'unknown'not in expected,'Choose a completed real-solver query')
    out=args.out.resolve();out.mkdir(parents=True,exist_ok=False);query=out/'query.smt2';query.write_bytes(raw)
    executable=shutil.which(args.solver);checker.need(executable is not None,'Requested solver is unavailable')
    command=[executable]+(['-memory:1024','-T:'+str(args.timeout),'-smt2']if args.solver=='z3'else
        ['--tlimit='+str(args.timeout*1000),'--lang=smt2','--incremental','--produce-models'])+[str(query)]
    started=time.monotonic();timed_out=False
    with(out/'solver.log').open('w')as log:
        try:cp=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=args.timeout+10);code=cp.returncode
        except subprocess.TimeoutExpired:code=None;timed_out=True
    log=(out/'solver.log').read_bytes();answers=re.findall(rb'^(sat|unsat|unknown)\s*$',log,re.M)
    answers=[x.decode()for x in answers]
    passed=not timed_out and code==0 and answers==expected and b'(error 'not in log
    result=dict(passed=passed,run=args.run,query=args.query,query_sha256=digest,solver=args.solver,
        command=command,exit=code,timed_out=timed_out,expected_answers=expected,actual_answers=answers,
        seconds=time.monotonic()-started,original_receipts_modified=False,hardware_access=False,
        whole_device_session_theorem=False,
        scope='Fresh real-solver result for one exact frozen query. No source re-elaboration, new hardware qualification or completion of other component/device obligations.')
    (out/'FINISHED.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps(result,sort_keys=True));return 0 if passed else 1


if __name__=='__main__':raise SystemExit(main())
