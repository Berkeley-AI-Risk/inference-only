"""Universal word-level SHA sum lemma, with no circuit or cryptographic premise.

The five arguments are independent 32-bit words. This separates modular sum
regrouping from the nonlinear expressions later substituted for those words.
"""
import hashlib
import json
from pathlib import Path
import subprocess

HERE=Path(__file__).resolve().parent


def sha(raw):return hashlib.sha256(raw).hexdigest()


def main():
    out=HERE/'runs/modular-sum-regroup-r1';out.mkdir(exist_ok=False)
    query='''(set-logic QF_BV)
(declare-fun h () (_ BitVec 32))
(declare-fun s () (_ BitVec 32))
(declare-fun c () (_ BitVec 32))
(declare-fun k () (_ BitVec 32))
(declare-fun w () (_ BitVec 32))
(check-sat)
(assert (not (= (bvadd (bvadd (bvadd (bvadd h s) c) k) w)
                    (bvadd (bvadd s c) (bvadd (bvadd h k) w)))))
(check-sat)
'''
    (out/'lemma.smt2').write_text(query)
    rows=[]
    for solver in('z3','cvc5'):
        command=[solver,'-T:30','rewriter.bv_sort_ac=true','rewriter.som=true','-smt2','lemma.smt2']if solver=='z3'else[solver,'--tlimit=30000','--incremental','--lang=smt2','lemma.smt2']
        p=subprocess.run(command,cwd=out,capture_output=True,timeout=40)
        raw=p.stdout+p.stderr;(out/(solver+'.log')).write_bytes(raw)
        answers=[x for x in raw.decode().splitlines()if x in('sat','unsat','unknown')]
        rows.append(dict(solver=solver,command=command,exit=p.returncode,answers=answers,
            passed=p.returncode==0 and answers==['sat','unsat'],log_sha256=sha(raw)))
    result=dict(schema='universal-five-independent-word-modular-sum-regroup-v1',
        passed=all(r['passed']for r in rows),word_width=32,free_words=['h','s','c','k','w'],
        no_assumptions=True,query_sha256=sha(query.encode()),results=rows,
        runner_sha256=sha(Path(__file__).read_bytes()))
    (out/'FINISHED.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps(result));return 0 if result['passed']else 1


if __name__=='__main__':raise SystemExit(main())
