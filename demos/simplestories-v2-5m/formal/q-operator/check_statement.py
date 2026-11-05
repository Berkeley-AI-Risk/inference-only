"""Match the readable main SMT-LIB functions to their frozen engine statements."""
import json,pathlib,tarfile
HERE=pathlib.Path(__file__).resolve().parent


def statement():
    with tarfile.open(HERE/'project.tar.gz','r:gz')as tar:
        def plan(label):return json.loads(tar.extractfile('q-operator/'+label+'-PLAN.json').read())
        main=plan('q-main');fault=plan('normalizer-faults');raw=plan('q-frontier-value-r3')
    lines=['; Complete baseline Q: readable endpoint implications.',
        '; Load the packet native models and history definitions first.',
        '; These definitions are statements, not assumptions or self-certifying proofs.',
        '; Engine receipts plus the checked common-trace induction discharge them.']
    def add(label,p,name,assumptions=None,conclusion=None):
        r=p['rules'][name];args=' '.join('('+d.removeprefix('(declare-const ').removesuffix(')')+')'for d in p['declarations'])
        root=r['assumptions']if assumptions is None else assumptions
        goal=r['conclusion']if conclusion is None else conclusion
        antecedent='(and '+' '.join(root)+')'if root else'true'
        lines.append('(define-fun '+label+' ('+args+') Bool (=> '+antecedent+' '+goal+'))')
    for name,r in main['rules'].items():
        if r.get('expected','unsat')=='unsat':add('MainQ-'+name,main,name)
    for name in ['first-fault-is-named-interruption-or-independent-rejection','clean-first-fault-enters-independent-numeric-rejection','clean-numeric-rejection-preserves-emitted-prefix']:
        add('MainQ-'+name,fault,name)
    root=list(raw['root_assumptions']);health='(not (|core_workflow_control_n u_native.u_private_ddr_arbiter.fail_q| a))'
    if root.count(health)!=1:raise ValueError('Changed raw contract health-discharge boundary')
    root.remove(health)
    add('MainQ-all-current-raw-value',raw,'next-output-raw-Q-value',assumptions=root)
    return '\n'.join(lines)+'\n'


if __name__=='__main__':
    if (HERE/'THEOREM.smt2').read_text()!=statement():raise ValueError('Readable theorem differs from its frozen engine statements')
    print('Readable SMT-LIB endpoint statements match the frozen engine rules; trace induction is checked by run.py.')
