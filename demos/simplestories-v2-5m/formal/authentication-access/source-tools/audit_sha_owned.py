"""Audit page SHA refinement, exact source reversal and discharged sum premises."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re

HERE=Path(__file__).resolve().parent
TOP='board1_sha256_bank_owned_compress'


def sha(raw):return hashlib.sha256(raw).hexdigest()


def load(name,path):
    spec=importlib.util.spec_from_file_location('_owned_audit_'+name,path)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--package',type=Path,required=True)
    args=p.parse_args();common=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    arithmetic=load('arithmetic',HERE/'proved_arithmetic.py')
    traces=load('trace',HERE/'audit_hash_owners.py')
    selected=(('baseline','sha-owned-baseline-step-r1'),
        ('kv-protected','sha-owned-protected-step-r4-cache-ref'),
        ('encrypted-memory','sha-owned-encrypted-step-r2-cache-ref'))
    records=[]
    for variant,name in selected:
        root=HERE/'runs'/name;inputs_raw=(root/'INPUTS.json').read_bytes();inputs=json.loads(inputs_raw)
        result=json.loads((root/'FINISHED.json').read_bytes())
        if result['inputs_sha256']!=sha(inputs_raw):raise ValueError('Model/result input binding changed')
        for n,row in inputs['files'].items():
            raw=(root/n).read_bytes()
            if row!={'bytes':len(raw),'sha256':sha(raw)}:raise ValueError('Changed model input: '+n)
        native=(root/'production-sha.sv').read_bytes();monitor=(root/'reference-monitor.inc.sv').read_bytes()
        model=(root/'sha.sv').read_bytes();prefix=b'`undef FORMAL\n'
        if not model.startswith(prefix)or model.count(b'\n'+monitor)!=1:raise ValueError('Observer boundary changed')
        reversed_source=model[len(prefix):].replace(b'\n'+monitor,b'',1)
        obligations=[]
        if variant!='baseline':
            rewritten,obligations,_=arithmetic.rewrite(native)
            if reversed_source!=rewritten:raise ValueError('Only the proved stateless leaves may change')
            if inputs['internal_cuts']!=obligations:raise ValueError('Substitution premise inventory changed')
            lemma=HERE/'runs/modular-sum-regroup-r1';receipt=json.loads((root/'regroup-FINISHED.json').read_bytes())
            if (root/'regroup-FINISHED.json').read_bytes()!=(lemma/'FINISHED.json').read_bytes():raise ValueError('Regrouping receipt changed')
            if not receipt['passed']or not receipt['no_assumptions']or receipt['free_words']!=['h','s','c','k','w']:
                raise ValueError('Regrouping lemma premises changed')
            query=(root/'regroup-lemma.smt2').read_bytes()
            if sha(query)!=receipt['query_sha256']or query.count(b'(declare-fun')!=5 or query.count(b'(assert')!=1:
                raise ValueError('Regrouping query changed')
            for row in receipt['results']:
                if not row['passed']or row['answers']!=['sat','unsat']or sha((lemma/(row['solver']+'.log')).read_bytes())!=row['log_sha256']:
                    raise ValueError('Regrouping lemma not proved')
            text=monitor.decode()
            original=re.search(r'    function automatic \[255:0\] f_round\(.*?    endfunction',text,re.S)[0]
            expected=original.replace('f_round','f_round_cached').replace('input [31:0] w, input [31:0] k','input [31:0] cached_hkw').replace(
                't1=h+f_S1(e)+((e & f) ^ (~e & g))+k+w;','t1=f_S1(e)+((e & f) ^ (~e & g))+cached_hkw;')
            if text.count(expected)!=1:raise ValueError('Cached reference is not the proved modular regrouping')
            for required in('f_round_cached(f_work,hkw_q)','f_round_cached(f_step1,gkw_q)',
                "assert(hkw_q==32'(h_q+f_k(round_q)+schedule_q[0]));",
                "assert(gkw_q==32'(g_q+f_k(round_q+6'd1)+schedule_q[1]));"):
                if text.count(required)!=1:raise ValueError('Reference/cache invariant composition changed')
        elif reversed_source!=native or inputs['internal_cuts']:raise ValueError('Baseline production source changed')
        group=('baseline','seeded-sampling')if variant=='baseline'else(variant,);joins={}
        for v in group:
            _,directory,bound=common.binding(args.package,v)
            if (directory/'project/sha.sv').read_bytes()!=native:raise ValueError('Native library identity changed')
            joins[v]=dict(image_sha256=bound['image_sha256'],library_sha256=sha(native))
        graph=json.loads((root/'elaborated.json').read_bytes())['modules'][TOP];cells=list(graph['cells'].values())
        count=19 if variant=='baseline'else 28
        if inputs['assertion_cells']!=count or sum(c['type']=='$assert'for c in cells)!=count:
            raise ValueError('Refinement inventory changed')
        if inputs['assumption_cells']or inputs['changed_production_parameters']or any(c['type']in('$anyseq','$anyconst','$assume','$mem_v2')for c in cells):
            raise ValueError('Data-cut, geometry or assumption policy changed')
        if not inputs['literal_roms_mapped']:raise ValueError('Round constants are not literal logic')
        for n in range(16):
            if len(graph['netnames']['schedule_q['+str(n)+']']['bits'])!=32:raise ValueError('Native full schedule not retained')
        required={'z3-bmc','z3-induction','z3-cover','cvc5-bmc','cvc5-cover'}
        for phase,row in result['results'].items():
            for ext,key in(('.log','log_sha256'),('.smt2','query_sha256'),('.responses','solver_responses_sha256')):
                if sha((root/(phase+ext)).read_bytes())!=row[key]:raise ValueError('Solver evidence changed')
            for fn,digest in row['traces'].items():
                if sha((root/fn).read_bytes())!=digest:raise ValueError('Solver trace changed')
            if phase in required and(not row['passed']or row['exit']!=0 or row['status']!=['PASSED']):raise ValueError('Required phase incomplete: '+name+' '+phase)
            if phase=='z3-induction'and('--smtc'in row['command']or'Temporal induction successful.'not in(root/(phase+'.log')).read_text()):
                raise ValueError('Induction policy/evidence changed')
        for solver in('z3','cvc5'):
            done=[f['state_o']for f in traces.top_frames(root/(solver+'-cover-0.vcd'))if f.get('done_o')==1]
            if not done or any(v!=int(hashlib.sha256(b'abc').hexdigest(),16)for v in done):raise ValueError('Completed ABC result incorrect')
        records.append(dict(run=name,variants=group,assertions=count,native_joins=joins,
            inputs_sha256=sha(inputs_raw),finished_sha256=sha((root/'FINISHED.json').read_bytes()),
            source_reversal=True,arithmetic_leaf_premises=obligations,
            modular_regrouping_premise_discharged=variant!='baseline',
            both_solver_satisfiable_reset_bases=True,z3_unbounded_induction=True,
            cvc5_unbounded_induction=result['results']['cvc5-induction']['passed'],
            correct_complete_abc_transaction_both_solvers=True,original_aggregate_passed=result['passed']))
    controls=[]
    for name in('sha-owned-step-mutant-wrong-k-r1','sha-owned-step-mutant-wrong-tap-r1'):
        root=HERE/'runs'/name;r=json.loads((root/'FINISHED.json').read_bytes())
        if not r['passed']or not r['mutation_detected']or not all(x['passed']and x['status']==['FAILED']and x['traces']for x in r['results'].values()):
            raise ValueError('Semantic mutation was not detected by an actual base counterexample')
        controls.append(dict(run=name,result_sha256=sha((root/'FINISHED.json').read_bytes())))
    out=dict(schema='native-page-sha-fips-step-refinement-audit-v1',passed=True,runs=records,semantic_controls=controls,
        scope='All native two-round page compressors: initial-load, exact FIPS working/schedule transitions for 64 rounds, progress, and DONE live-input feed-forward. Accepted-chain digest correctness also requires actual owner chain preservation. Baseline/protected bank owner proofs and encrypted pool owner proofs are separate. Vendor functional model equivalence is source-level, not physical silicon or bitstream equivalence. No hash-hardness theorem.')
    (HERE/'SHA-OWNED-AUDIT.json').write_text(json.dumps(out,indent=2,sort_keys=True)+'\n');print(json.dumps(out))


if __name__=='__main__':main()
