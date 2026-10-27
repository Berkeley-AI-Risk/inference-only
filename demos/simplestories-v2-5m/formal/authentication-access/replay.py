"""Fresh solver check of a selected immutable recorded query.

No FPGA is accessed. Extracts only the chosen query and runs a real local
solver. Original receipts are preserved. The new result covers that query,
not all component proofs or a new source-to-bitstream equivalence theorem.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import time

HERE=Path(__file__).resolve().parent


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--model',type=Path,default=HERE.parents[1]);p.add_argument('--run',required=True)
    p.add_argument('--query',required=True,help='Recorded query filename inside the selected run')
    p.add_argument('--solver',choices=('z3','cvc5'),required=True);p.add_argument('--out',type=Path,required=True)
    p.add_argument('--timeout',type=int,default=120);args=p.parse_args()
    if not 1<=args.timeout<=900:p.error('timeout must be 1..900 seconds')
    spec=importlib.util.spec_from_file_location('_recorded_authentication',HERE/'check_recorded.py')
    checker=importlib.util.module_from_spec(spec);spec.loader.exec_module(checker)
    evidence=checker.Evidence(args.model)
    if args.run not in evidence.index['selected_directories']:raise ValueError('Run is not in the sealed selected evidence')
    prefix='runs/'+args.run+'/';logical=prefix+args.query
    checker.safe(evidence.root,args.query)
    if not args.query.endswith('.smt2')or logical not in evidence.index['files']:raise ValueError('Selected query absent')
    raw=evidence.raw(logical);text=raw.decode()
    # A source-fixed query is data: refuse external includes and filesystem
    # extensions even if a future solver adds such commands.
    if re.search(r'^\s*\((?:include|exec|eval|system)\b',text,re.M):raise ValueError('External query command refused')
    expected_path=args.query.removesuffix('.smt2')+'.responses'
    # SMTBMC stores complete real solver replies. Manual split proofs store
    # the expected single answer in the original result row.
    expected=None
    if prefix+expected_path in evidence.index['files']:
        replies=evidence.raw(prefix+expected_path).decode()
        expected=re.findall(r'^(sat|unsat|unknown)\s*$',replies,re.M)
    finished=evidence.json(prefix+'FINISHED.json')
    if expected is None:
        for label,row in finished.get('solver_results',{}).items():
            if row.get('query_sha256')==evidence.index['files'][logical]['sha256']:
                expected=row['answers'];break
    if expected is None and finished.get('query_sha256')==evidence.index['files'][logical]['sha256']:
        replies=evidence.raw(prefix+'responses.txt').decode()if prefix+'responses.txt'in evidence.index['files']else''
        expected=re.findall(r'^(sat|unsat|unknown)\s*$',replies,re.M)
    if not expected or'unknown'in expected:raise ValueError('Choose a completed real-solver query; unresolved queries confer no proof credit')
    out=args.out.resolve();out.mkdir(parents=True,exist_ok=False);query=out/'query.smt2';query.write_bytes(raw)
    executable=shutil.which(args.solver)
    if not executable:raise ValueError('Solver is unavailable: '+args.solver)
    command=[executable]+(['-smt2']if args.solver=='z3'else['--lang=smt2','--incremental','--produce-models'])+[str(query)]
    started=time.monotonic();timed_out=False
    with(out/'solver.log').open('w')as log:
        try:cp=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=args.timeout);code=cp.returncode
        except subprocess.TimeoutExpired:code=None;timed_out=True
    log=(out/'solver.log').read_bytes();answers=re.findall(rb'^(sat|unsat|unknown)\s*$',log,re.M)
    answers=[s.decode()for s in answers]
    passed=not timed_out and code==0 and answers==expected and b'(error 'not in log
    result=dict(schema='fresh-current-authentication-access-query-replay-v1',passed=passed,run=args.run,query=args.query,
        query_sha256=checker.sha(raw),solver=args.solver,command=command,exit=code,timed_out=timed_out,
        expected_answers=expected,actual_answers=answers,seconds=time.monotonic()-started,
        original_receipts_modified=False,hardware_access=False,
        scope='New real-solver result for exactly the sealed selected query. Does not rerun source instrumentation/auditing, every component theorem or hardware.')
    (out/'FINISHED.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps(result,sort_keys=True));raise SystemExit(0 if passed else 1)


if __name__=='__main__':main()
