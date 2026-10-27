"""Check local arithmetic preservation cases in the actual elaborated miter.

These are local relational proof obligations, not a replacement for the reset
base, sequential induction or completed transaction reachability.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import subprocess

TOP='board1_sha256_compact_compress'


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--run',type=Path,required=True)
    p.add_argument('--out',type=Path,required=True)
    p.add_argument('--cases',type=int,default=16)
    args=p.parse_args();args.out.mkdir(parents=True,exist_ok=False)
    smt=(args.run/'design.smt2').read_text()
    def n(name):
        token='|'+TOP+'_n '+name+'|'
        if '(define-fun '+token+' 'not in smt:raise ValueError('Missing native signal '+name)
        return '('+token+' s)'
    work=n('h_q')
    for name in ('g_q','f_q','e_q','d_q','c_q','b_q','a_q'):
        work='(concat '+n(name)+' '+work+')'
    def solve(head):
        constraints=[n('reset_n_i'),'(= '+n('f_head_q')+f' (_ bv{head} 4))',
            '(= '+n('f_work_q')+' '+work+')','(= '+n('round_q')+' '+n('f_round_q')+')']
        constraints += ['(= '+n(f'schedule_q[{j}]')+' '+n(f'f_ring_q[{(head+j)%16}]')+')'for j in range(16)]
        conclusion='(and (= '+n('next_a')+' ((_ extract 255 224) '+n('f_next_work')+')) (= '+n('next_e')+' ((_ extract 127 96) '+n('f_next_work')+')) (= '+n('schedule_next')+' '+n('f_new_word')+'))'
        query='(set-logic QF_AUFBV)\n'+smt+f'\n(declare-fun s () {TOP}_s)\n'+''.join('(assert '+c+')\n'for c in constraints)
        tactic='(check-sat-using (then simplify solve-eqs bit-blast sat))\n'
        query+='(check-sat)\n'+'(assert (not '+conclusion+'))\n'+tactic
        path=args.out/f'head-{head:02}.smt2';path.write_text(query)
        cp=subprocess.run(['z3','-T:60','-smt2',str(path)],capture_output=True,text=True,timeout=70)
        log=cp.stdout+cp.stderr;(args.out/f'head-{head:02}.log').write_text(log)
        answers=[s for s in log.splitlines()if s in ('sat','unsat','unknown')]
        row=dict(head=head,passed=cp.returncode==0 and answers==['sat','unsat'],answers=answers,
            exit=cp.returncode,query_sha256=hashlib.sha256(query.encode()).hexdigest(),log_sha256=hashlib.sha256(log.encode()).hexdigest())
        print(json.dumps(row),flush=True);return row
    with ThreadPoolExecutor(max_workers=2)as pool:
        rows=list(pool.map(solve,range(args.cases)))
    result=dict(schema='sha-local-relational-arithmetic-diagnostic-v1',passed=all(r['passed']for r in rows),
        cases=rows,complete_head_partition=args.cases==16,model_sha256=hashlib.sha256(smt.encode()).hexdigest(),
        whole_sequential_proof=False)
    (args.out/'FINISHED.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    return 0 if result['passed']else 1


if __name__=='__main__':raise SystemExit(main())
