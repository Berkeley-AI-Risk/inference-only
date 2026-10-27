"""Recheck exact native association and reversibility of the new auth proofs."""
import argparse
import hashlib
import json
from pathlib import Path

HERE=Path(__file__).resolve().parent
SELECTED=('image-auth-baseline-r3','image-auth-protected-r1','image-auth-encrypted-r1')


def sha(raw):return hashlib.sha256(raw).hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--once',action='store_true',help='Audit the extended one-BEGIN-per-reset caller proof')
    args=parser.parse_args()
    selected=('image-auth-baseline-r4-once','image-auth-protected-r2-once','image-auth-encrypted-r2-once')if args.once else SELECTED
    assertion_count=35 if args.once else 33
    records=[]
    for name in selected:
        root=HERE/'runs'/name
        raw=(root/'INPUTS.json').read_bytes()
        inputs=json.loads(raw)
        result=json.loads((root/'FINISHED.json').read_bytes())
        if result['inputs_sha256']!=sha(raw):raise ValueError('Input binding changed')
        if not result['passed'] or result['internal_cuts'] or inputs['internal_cuts']:
            raise ValueError('Only successful uncut proofs are selected')
        if inputs['changed_production_parameters'] or inputs['assumption_cells']:
            raise ValueError('Native dimension/assumption policy changed')
        for n,row in inputs['files'].items():
            data=(root/n).read_bytes()
            if row!={'bytes':len(data),'sha256':sha(data)}:raise ValueError('Changed proof member: '+n)
        monitor=(root/'monitor.inc.sv').read_bytes()
        source=(root/'auth.sv').read_bytes()
        prefix=b'`undef FORMAL\n'
        inserted=b'\n'+monitor+b'\n`ifdef FORMAL'
        if not source.startswith(prefix) or source.count(inserted)!=1:raise ValueError('Instrumentation boundary changed')
        if source[len(prefix):].replace(inserted,b'\n`ifdef FORMAL',1)!=(root/'production-auth.sv').read_bytes():
            raise ValueError('Observer reversal does not recover original native auth')
        if (root/'sha.sv').read_bytes()!=prefix+(root/'production-sha.sv').read_bytes():
            raise ValueError('The production SHA child was changed')
        bind=inputs['binding']
        for variant,join in bind['native_joins'].items():
            for local,path in bind['production_paths'].items():
                digest=sha((root/('production-'+local)).read_bytes())
                if digest!=join['distributed_inputs'][path] or digest!=bind['production_sources'][local]:
                    raise ValueError('Native source/image binding mismatch')
        module=json.loads((root/'elaborated.json').read_bytes())['modules'][inputs['top']]
        cells=list(module['cells'].values())
        if sum(c['type']=='$assert'for c in cells)!=assertion_count or sum(c['type']=='$cover'for c in cells)!=3:
            raise ValueError('Checked properties changed')
        if any(c['type']in('$assume','$anyconst','$anyseq')for c in cells):
            raise ValueError('A formal assumption or arbitrary internal data cut was added')
        required={'z3-bmc','z3-induction','z3-cover','cvc5-bmc','cvc5-induction','cvc5-cover'}
        if set(result['results'])!=required:raise ValueError('A solver phase is missing')
        for phase,row in result['results'].items():
            if not row['passed'] or row['timed_out'] or row['status']!=['PASSED'] or row['exit']!=0:
                raise ValueError('A required phase did not finish successfully')
            if sha((root/(phase+'.log')).read_bytes())!=row['log_sha256']:
                raise ValueError('Solver log changed')
            if sha((root/(phase+'.smt2')).read_bytes())!=row['query_sha256']:
                raise ValueError('Solver query changed')
            if sha((root/(phase+'.responses')).read_bytes())!=row['solver_responses_sha256']:
                raise ValueError('Solver responses changed')
        records.append(dict(run=name,variants=list(bind['native_joins']),passed=True,
            assertions=assertion_count,covers=3,inputs_sha256=sha(raw),finished_sha256=sha((root/'FINISHED.json').read_bytes()),
            source_reversal=True,all_six_solver_phases_passed=True,no_internal_cuts=True))
    out=dict(schema='native-image-authentication-input-admission-audit-v1',passed=True,runs=records,
        scope='Actual input serialization, complete native byte count, fixed padding and matching-digest admission. SHA arithmetic correspondence, parent LOCK, page-to-consumer composition and native-length successful reachability are not established by this audit.')
    out['one_BEGIN_per_reset_epoch_proved']=args.once
    (HERE/('IMAGE-AUTH-ONCE-AUDIT.json'if args.once else'IMAGE-AUTH-AUDIT.json')).write_text(json.dumps(out,indent=2,sort_keys=True)+'\n')
    print(json.dumps(out))


if __name__=='__main__':main()
