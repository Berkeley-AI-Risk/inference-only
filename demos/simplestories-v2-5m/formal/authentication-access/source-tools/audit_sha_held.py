"""Audit the actual encrypted boot/KV resetless-payload SHA refinement."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path

HERE=Path(__file__).resolve().parent


def sha(raw):return hashlib.sha256(raw).hexdigest()


def load(name,path):
    spec=importlib.util.spec_from_file_location('_held_audit_'+name,path)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--package',type=Path,required=True)
    args=p.parse_args();common=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    helpers=load('helpers',HERE/'audit_hash_owners.py')
    root=HERE/'runs/sha-held-boot-r1';raw=(root/'INPUTS.json').read_bytes();inputs=json.loads(raw)
    result=json.loads((root/'FINISHED.json').read_bytes())
    if result['inputs_sha256']!=sha(raw):raise ValueError('Input/result binding changed')
    for n,row in inputs['files'].items():
        data=(root/n).read_bytes()
        if row!={'bytes':len(data),'sha256':sha(data)}:raise ValueError('Changed model source: '+n)
    monitor=(root/'reference-monitor.inc.sv').read_bytes();source=(root/'sha.sv').read_bytes();prefix=b'`undef FORMAL\n'
    native=(root/'production-sha.sv').read_bytes()
    if not source.startswith(prefix)or source.count(b'\n'+monitor)!=1 or source[len(prefix):].replace(b'\n'+monitor,b'',1)!=native:
        raise ValueError('Observer reversal does not recover native source')
    _,directory,bound=common.binding(args.package,'encrypted-memory')
    if (directory/'project/sha.sv').read_bytes()!=native:raise ValueError('Native source identity changed')
    boot=helpers.module(native,'board1_sha256_owner_held_boot_compress')
    kv=helpers.module(native,'board1_sha256_owner_held_kv_compress')
    if boot.replace(b'board1_sha256_owner_held_boot_compress',b'SAME')!=kv.replace(b'board1_sha256_owner_held_kv_compress',b'SAME'):
        raise ValueError('Claimed boot/KV implementation identity changed')
    graph=json.loads((root/'elaborated.json').read_bytes())['modules'][inputs['top']];cells=list(graph['cells'].values())
    if inputs['internal_cuts']or inputs['assumption_cells']or inputs['changed_production_parameters']or any(c['type']in('$anyseq','$anyconst','$assume','$mem_v2')for c in cells):
        raise ValueError('Native geometry/no-cut/no-assumption policy changed')
    if sum(c['type']=='$assert'for c in cells)!=17 or inputs['assertion_cells']!=17:
        raise ValueError('Refinement inventory changed')
    if not inputs['literal_roms_mapped']:raise ValueError('Round constants not mapped to literals')
    for i in range(16):
        if len(graph['netnames']['schedule_q['+str(i)+']']['bits'])!=32:raise ValueError('Native schedule truncated')
    required={'z3-bmc','z3-induction','cvc5-induction','z3-cover','cvc5-cover'}
    for phase,row in result['results'].items():
        for ext,key in(('.log','log_sha256'),('.smt2','query_sha256'),('.responses','solver_responses_sha256')):
            if sha((root/(phase+ext)).read_bytes())!=row[key]:raise ValueError('Solver evidence changed')
        for fn,digest in row['traces'].items():
            if sha((root/fn).read_bytes())!=digest:raise ValueError('Trace changed')
        if phase in required and(not row['passed']or row['status']!=['PASSED']or row['exit']!=0):raise ValueError('Required phase incomplete')
        if phase.endswith('induction')and('--smtc'in row['command']or'Temporal induction successful.'not in(root/(phase+'.log')).read_text()):
            raise ValueError('Induction policy/evidence changed')
    for solver in('z3','cvc5'):
        values=[f['state_o']for f in helpers.top_frames(root/(solver+'-cover-0.vcd'))if f.get('done_o')==1]
        if not values or any(v!=int(hashlib.sha256(b'abc').hexdigest(),16)for v in values):raise ValueError('Complete ABC result wrong')
    compact=json.loads((HERE/'SHA-COMPACT-AUDIT.json').read_bytes())
    if not compact['passed']:raise ValueError('Independent FIPS reference audit missing')
    if (root/'reference.py').read_bytes()!=(HERE/'runs/sha-compact-fips-r3-local-invariants/reference.py').read_bytes():
        raise ValueError('Independent FIPS reference source differs')
    out=dict(schema='native-owner-held-sha-fips-refinement-audit-v1',passed=True,run=root.name,
        inputs_sha256=sha(raw),finished_sha256=sha((root/'FINISHED.json').read_bytes()),
        model_sha256=sha((root/'design.smt2').read_bytes()),image_sha256=bound['image_sha256'],
        library_sha256=sha(native),boot_module_sha256=sha(boot),kv_module_sha256=sha(kv),
        boot_kv_exact_body_identity_except_module_name=True,source_reversal=True,assertions=17,
        z3_satisfiable_reset_base=True,both_solver_unbounded_induction=True,
        cvc5_reset_base_passed=result['results']['cvc5-bmc']['passed'],
        cvc5_base_timeout_not_credited=True,complete_correct_abc_transaction_both_solvers=True,
        no_internal_data_cuts_or_assumptions=True,
        scope='Actual encrypted boot/KV one-round resetless-payload compressors: initial-load, all 64 FIPS round/schedule transitions, progress and live-state feed-forward. A valid initial reset base is supplied by Z3; cvc5 independently completes induction and the ABC transaction, but its separate unconstrained base searches timed out. Accepted-chain message correctness still requires actual caller chain ownership. No cryptographic-hardness, bitstream or physical theorem.')
    (HERE/'SHA-HELD-AUDIT.json').write_text(json.dumps(out,indent=2,sort_keys=True)+'\n');print(json.dumps(out))


if __name__=='__main__':main()
