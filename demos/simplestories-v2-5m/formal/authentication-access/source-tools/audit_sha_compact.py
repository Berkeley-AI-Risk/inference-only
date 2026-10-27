"""Audit the complete compact-compressor result and its native source joins."""
import argparse
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import re

HERE=Path(__file__).resolve().parent
MODEL='sha-compact-fips-r3-local-invariants'
TOP='board1_sha256_compact_compress'


def sha(raw):return hashlib.sha256(raw).hexdigest()


def load(name,path):
    spec=importlib.util.spec_from_file_location('_sha_audit_'+name,path)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def literal_module(raw):
    start=raw.index(b'module '+TOP.encode()+b' (')
    end=raw.index(b'\nendmodule',start)+len(b'\nendmodule')
    return raw[start:end]


def check_phase(name,model_sha,phase):
    root=HERE/'runs'/name
    r=json.loads((root/'FINISHED.json').read_bytes())
    if not r['passed'] or r['phase']!=phase or r['model_sha256']!=model_sha:
        raise ValueError('Required solver phase is incomplete: '+name)
    for fn,key in [('solver.log','log_sha256'),('query.smt2','query_sha256'),('responses.txt','responses_sha256')]:
        if sha((root/fn).read_bytes())!=r[key]:raise ValueError('Changed solver evidence')
    if phase=='induction' and 'directed_coverage_only_constraints_sha256'in r:
        raise ValueError('Coverage stimulus entered induction')
    if phase=='cover':
        if sha((root/'cover.smtc').read_bytes())!=r['directed_coverage_only_constraints_sha256']:
            raise ValueError('Coverage input changed')
        trace=root/'trace-0.vcd'
        names={};scope=[];values={};seen=[]
        def save():
            if values.get('done_o')==1:seen.append(values.get('state_o'))
        for line in trace.read_text().splitlines():
            parts=line.split()
            if parts and parts[0]=='$scope':scope.append(parts[2])
            if parts and parts[0]=='$upscope':scope.pop()
            if parts and parts[0]=='$var' and len(scope)==1 and parts[4]in('done_o','state_o'):
                names[parts[3]]=parts[4]
            if line.startswith('#'):save()
            elif line.startswith('b'):
                bits,ident=line[1:].split()
                if ident in names and set(bits)<=set('01'):values[names[ident]]=int(bits,2)
        save()
        expected=int.from_bytes(hashlib.sha256(b'abc').digest(),'big')
        if not seen or any(v!=expected for v in seen):raise ValueError('The completed native trace has the wrong ABC digest')
    return dict(run=name,solver=r['solver'],phase=phase,passed=True,result_sha256=sha((root/'FINISHED.json').read_bytes()))


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--package',type=Path,required=True)
    args=p.parse_args();root=HERE/'runs'/MODEL
    inputs=json.loads((root/'INPUTS.json').read_bytes())
    old=json.loads((root/'FINISHED.json').read_bytes())
    for n,row in inputs['files'].items():
        raw=(root/n).read_bytes()
        if row!={'bytes':len(raw),'sha256':sha(raw)}:raise ValueError('Changed model source: '+n)
    monitor=(root/'reference-monitor.inc.sv').read_bytes()
    source=(root/'sha.sv').read_bytes();prefix=b'`undef FORMAL\n'
    if not source.startswith(prefix)or source.count(b'\n'+monitor)!=1:
        raise ValueError('Instrumentation boundary changed')
    native=(root/'production-sha.sv').read_bytes()
    if source[len(prefix):].replace(b'\n'+monitor,b'',1)!=native:
        raise ValueError('Reference reversal failed')
    ref=load('fips_reference',root/'reference.py')
    primes=[];n=2
    while len(primes)<64:
        if all(n%d for d in range(2,math.isqrt(n)+1)):primes.append(n)
        n+=1
    for prime,constant in zip(primes,ref.K):
        value=prime<<96;low,high=0,1<<36
        while high-low>1:
            mid=(low+high)//2
            if mid**3<=value:low=mid
            else:high=mid
        if low**3>value or (low+1)**3<=value or low&0xffffffff!=constant:
            raise ValueError('Round constants fail the exact cube-root definition')
    if tuple(math.isqrt(prime<<64)&0xffffffff for prime in primes[:8])!=ref.IV:
        raise ValueError('Initial constants fail the exact square-root definition')
    common=load('native_binding',HERE.parent/'formal-assurance/run_handoff.py')
    joins={}
    for variant in ('baseline','kv-protected','encrypted-memory','seeded-sampling'):
        _,directory,binding=common.binding(args.package,variant)
        actual=(directory/'project/sha.sv').read_bytes()
        if literal_module(actual)!=literal_module(native):raise ValueError('The selected compressor differs in '+variant)
        joins[variant]=dict(image_sha256=binding['image_sha256'],sha_library_sha256=sha(actual),
            exact_compressor_module_sha256=sha(literal_module(actual)))
    module=json.loads((root/'elaborated.json').read_bytes())['modules'][TOP]
    cells=list(module['cells'].values())
    if sum(c['type']=='$assert'for c in cells)!=29 or any(c['type']in('$anyseq','$anyconst','$assume','$mem_v2')for c in cells):
        raise ValueError('Elaborated property, cut or literal-ROM policy changed')
    for base in ('schedule_q','f_ring_q'):
        bits=[b for i in range(16)for b in module['netnames'][base+'['+str(i)+']']['bits']]
        if len(bits)!=512 or len(set(bits))!=512 or any(not isinstance(b,int)for b in bits):
            raise ValueError('Full actual/reference schedule storage was not retained')
    if not inputs['literal_roms_mapped'] or inputs['internal_cuts'] or inputs['assumption_cells']:
        raise ValueError('Proof abstraction policy changed')
    for solver in ('z3','cvc5'):
        phase=solver+'-bmc';r=old['results'][phase]
        if not r['passed'] or r['status']!=['PASSED']:raise ValueError('Reset base not proved')
        for suffix,key in [('.log','log_sha256'),('.smt2','query_sha256'),('.responses','solver_responses_sha256')]:
            if sha((root/(phase+suffix)).read_bytes())!=r[key]:raise ValueError('Reset-base evidence changed')
    model_sha=sha((root/'design.smt2').read_bytes())
    phases=[check_phase('sha-compact-r3-cvc5-unroll-induction-r1',model_sha,'induction')]
    phases += [check_phase('sha-compact-r3-'+s+'-directed-cover-r1',model_sha,'cover')for s in ('z3','cvc5')]
    primary=HERE/'runs/sha-compact-r3-z3-unroll-induction-r2/FINISHED.json'
    primary_complete=primary.is_file()and json.loads(primary.read_bytes()).get('passed')is True
    if primary_complete:phases.append(check_phase(primary.parent.name,model_sha,'induction'))
    negative=[]
    for name in ('sha-compact-mutant-wrong-k-r1','sha-compact-mutant-wrong-tap-r1'):
        r=json.loads((HERE/'runs'/name/'FINISHED.json').read_bytes())
        if not r['passed']or not r['mutation_detected']:raise ValueError('Required semantic control not detected')
        if not all(x['status']==['FAILED']and x['passed']and x['traces']for x in r['results'].values()):
            raise ValueError('A semantic control lacks a real counterexample')
        negative.append(dict(run=name,passed=True,finished_sha256=sha((HERE/'runs'/name/'FINISHED.json').read_bytes())))
    out=dict(schema='native-sha-compact-reference-correspondence-audit-v1',passed=True,
        model_sha256=model_sha,assertions=29,source_reversal=True,native_joins=joins,
        exact_fips_constant_definitions_checked=True,both_solver_reset_bases_passed=True,
        cvc5_unbounded_induction_passed=True,z3_unbounded_induction_passed=primary_complete,
        completed_transaction_witness_with_correct_abc_digest_both_solvers=True,
        no_internal_cuts_or_arithmetic_assumptions=True,phases=phases,semantic_controls=negative,
        scope='Complete one-round compact compressor correctness against the explicit FIPS-based circular reference; arbitrary accepted blocks/chaining states and subsequent input changes. The page-bank compressor, stream chaining, parent LOCK and data-to-consumer composition remain open; no cryptographic hardness or physical theorem.')
    (HERE/'SHA-COMPACT-AUDIT.json').write_text(json.dumps(out,indent=2,sort_keys=True)+'\n')
    print(json.dumps(out))


if __name__=='__main__':main()
