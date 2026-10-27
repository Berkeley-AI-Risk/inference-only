"""Audit the full native encrypted RAM lifecycle and its ordered induction.

The owner contract is an independently proved source projection. The remaining
joint induction step is derived in order: a current-state conclusion enters
the context only after its negation has received a real UNSAT response. The
query-generation replay below reuses recorded replies only to check identity;
it establishes no new theorem and does not replace a real solver result.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

HERE=Path(__file__).resolve().parent


def sha(raw):return hashlib.sha256(raw).hexdigest()


def load(name,path):
    spec=importlib.util.spec_from_file_location('_encrypted_lifecycle_audit_'+name,path)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--package',type=Path,required=True);p.add_argument('--out',type=Path,required=True)
    args=p.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    checks=load('checked_runs',HERE/'audit_service_digest.py')
    mapping=load('owner_mapping',HERE/'run_proved_owner_contract.py')
    observer=load('readonly_observer',HERE.parent/'formal-assurance/audit_boot_boundary.py')
    bindings=load('native_binding',HERE.parent/'formal-assurance/run_handoff.py')
    queries=load('query_binding',HERE.parent/'formal-assurance/audit_fifo.py')
    root,inputs,native_result=checks.checked_run('encrypted-bank-lifecycle-r6-response-hold')
    prior,prior_inputs,prior_result=checks.checked_run('encrypted-hash-owner-r4-data-routing')
    owner_raw=(HERE/'ENCRYPTED-HASH-OWNER-AUDIT.json').read_bytes();owner=json.loads(owner_raw)
    if not owner['passed']or not owner['cvc5_unbounded_induction']or owner['finished_sha256']!=sha((prior/'FINISHED.json').read_bytes()):
        raise ValueError('The independent actual-owner theorem is missing')
    _,directory,bound=bindings.binding(args.package,'encrypted-memory')
    for n in('sha.sv','bank.sv','service.sv','shared_token_probe.sv','uart_core.sv'):
        actual=(directory/'project'/n).read_bytes()
        if actual!=(root/('production-'+n)).read_bytes()or actual!=(prior/('production-'+n)).read_bytes():
            raise ValueError('Actual native source identity differs')
    if inputs['top']!=prior_inputs['top']or inputs['internal_cuts']!=prior_inputs['internal_cuts']:
        raise ValueError('Native circuit/arithmetic premises changed')
    if (root/'sha.sv').read_bytes()!=(prior/'sha.sv').read_bytes():raise ValueError('Native SHA/pool source differs')
    old_monitor=(prior/'bank-monitor.inc.sv').read_bytes();combined=(root/'bank-monitor.inc.sv').read_bytes()
    if not combined.startswith(old_monitor+b'\n'):raise ValueError('The old owner observer was changed')
    extra=combined[len(old_monitor)+1:];observer.observer_writes_only(extra.decode())
    stripped=re.sub(r'assert\([^;]*\);','',extra.decode())
    writes=re.findall(r'\b(\w+)\s*(?:<=|=(?!=))',re.sub(r'//[^\n]*','',stripped))
    if any(not n.startswith('f_life_')for n in writes):raise ValueError('New observer changes pre-existing state')
    bank=(root/'bank.sv').read_bytes();port=b',\n    input wire f_service_active_i'
    if bank.count(port)!=1 or bank.count(b'\n'+combined)!=1:raise ValueError('Observer-only input/insertion changed')
    if bank.replace(port,b'',1).replace(b'\n'+combined,b'\n'+old_monitor,1)!=(prior/'bank.sv').read_bytes():
        raise ValueError('Native/owner bank projection does not reverse exactly')
    harness=(root/'harness.sv').read_text().replace('.f_service_active_i(!fault_o),','',1)
    if harness!=re.sub(r'cover\([^;]*\);',';',(prior/'harness.sv').read_text()):
        raise ValueError('Containing circuit/owner connectivity changed')
    graph=json.loads((root/'elaborated.json').read_bytes())['modules'][inputs['top']]
    cells=list(graph['cells'].values());assertions=38+4*extra.count(b'assert(')
    if assertions!=258 or sum(c['type']=='$assert'for c in cells)!=assertions:
        raise ValueError('Full lifecycle assertion inventory changed')
    if sum(c['type']=='$anyconst'for c in cells)!=4 or any(c['type']in('$anyseq','$assume','$cover')for c in cells):
        raise ValueError('Unexpected input promise, data cut or property inventory')
    memories=[c for c in cells if c['type']=='$mem_v2']
    if len(memories)!=4 or any(int(c['parameters']['WIDTH'],2)!=256 or int(c['parameters']['SIZE'],2)!=128 for c in memories):
        raise ValueError('Four full native RAMs are not retained')
    if inputs['assumption_cells']or inputs['changed_production_parameters']or inputs['binding']['native_banks']!=4:
        raise ValueError('Native parameter/assumption policy changed')
    reset='initial\nassume (= [reset_n] false)\nstate 1\nassume (= [reset_n] false)\n'
    if (root/'reset.smtc').read_text()!=reset:raise ValueError('A protocol condition was added to the reset base')
    base=native_result['results']['z3-bmc']
    if not base['passed']or base['status']!=['PASSED']or base['exit']!=0:
        raise ValueError('Unmodified native reset base incomplete')
    work=out/'recompiled';work.mkdir()
    for n in inputs['files']:
        target=work/n;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes((root/n).read_bytes())
    with(work/'re-elaboration.log').open('w')as log:
        cp=subprocess.run(['yosys','-Q','prove.ys'],cwd=work,stdout=log,stderr=subprocess.STDOUT,timeout=60)
    if cp.returncode or any((work/n).read_bytes()!=(root/n).read_bytes()for n in('design.smt2','elaborated.json','elaborated.il')):
        raise ValueError('Full native model does not reproduce')
    base_binding=queries.reproduce_query(root,'z3-bmc',base,False,out/'reset-base-query-binding',recorded_replies=root/'z3-bmc.responses')
    model=(root/'design.smt2').read_text();top=inputs['top']
    previous=mapping.assertion_map((prior/'design.smt2').read_text());current=mapping.assertion_map(model,bank_line_delta=1)
    if sum(map(len,previous.values()))!=38 or not set(previous)<=set(current)or any(len(previous[k])!=len(current[k])for k in previous):
        raise ValueError('Source association of the owner conjunction changed')
    imported=sorted(i for k in previous for i in current[k]);all_new=[i for i in range(assertions)if i not in imported]
    contract_path=HERE/'runs/encrypted-bank-lifecycle-r6-owner-contract-r1'
    contract_raw=(contract_path/'INPUTS.json').read_bytes();contract=json.loads(contract_raw)
    before=f'(define-fun |{top}_u| ((state |{top}_s|)) Bool true)'
    after=f'(define-fun |{top}_u| ((state |{top}_s|)) Bool (and true '+' '.join(f'(|{top}_a {i}| state)'for i in imported)+'))'
    if model.count(before)!=1:raise ValueError('Original model already contains unexplained assumptions')
    derived=model.replace(before,after,1)
    if (contract_path/'design.smt2').read_text()!=derived or contract['derived_model_sha256']!=sha(derived.encode())or contract['owner_audit_sha256']!=sha(owner_raw):
        raise ValueError('Contract changes more than independently source-proved facts')
    proof=HERE/'runs/encrypted-bank-lifecycle-r6-ordered-all-k2-r2'
    result_raw=(proof/'FINISHED.json').read_bytes();result=json.loads(result_raw)
    if not result['response_log_flushed_before_digest']or not result['passed']or result['schema']!='ordered-derivation-grounded-joint-induction-v1'or result['shared_premise_answer']!='sat':
        raise ValueError('Complete ordered joint induction did not pass')
    if result['selected_new_assertions']!=all_new or result['imported_source_proved_invariants']!=imported or len(result['results'])!=len(all_new):
        raise ValueError('Not every new joint-induction conclusion was proved')
    if any(r['index']!=i or r['answer']!='unsat'or not r['passed']for i,r in zip(all_new,result['results'])):
        raise ValueError('Induction includes an unresolved conclusion')
    if result['source_inputs_sha256']!=sha((root/'INPUTS.json').read_bytes())or result['owner_contract_inputs_sha256']!=sha(contract_raw)or result['depth']!=2 or inputs['base_depth']<2:
        raise ValueError('Induction/base/source association differs')
    for name,key in(('query.smt2','query_sha256'),('responses.txt','responses_sha256'),('runner.py','runner_sha256')):
        if sha((proof/name).read_bytes())!=result[key]:raise ValueError('Ordered induction evidence changed')
    answers=(proof/'responses.txt').read_text().split()
    if answers!=['sat']+['unsat']*len(all_new):raise ValueError('Real solver response inventory differs')
    library=Path('/opt/homebrew/share/yosys/python3/smtio.py').resolve()
    if sha(library.read_bytes())!=result['grounding_library_sha256']:raise ValueError('Grounding library changed')
    solver=Path(shutil.which('cvc5')).resolve()
    if sha(solver.read_bytes())!=inputs['tools']['cvc5']['sha256']:raise ValueError('Solver identity changed')
    replay=out/'ordered-query-binding';replay.mkdir();player=replay/'backend';player.mkdir()
    (replay/'runner.py').write_bytes((proof/'runner.py').read_bytes())
    (replay/'ENCRYPTED-HASH-OWNER-AUDIT.json').write_bytes(owner_raw)
    executable=player/'cvc5'
    program='#!'+sys.executable+'\n'+'''import os,sys
from pathlib import Path
answers=Path(os.environ['ORDERED_RECORDED_REPLIES']).read_text().split();cursor=0
for line in sys.stdin:
    if line.startswith('(check-sat'):
        if cursor>=len(answers):raise SystemExit('Recorded replies exhausted')
        sys.stdout.write(answers[cursor]+'\\n');sys.stdout.flush();cursor+=1
    if line.strip()=='(exit)':break
'''
    executable.write_text(program);executable.chmod(0o700)
    env=dict(os.environ,PATH=str(player)+os.pathsep+os.environ['PATH'],ORDERED_RECORDED_REPLIES=str(proof/'responses.txt'))
    command=[sys.executable,'-I','-S','-B',str(replay/'runner.py'),'--run',str(root),'--contract',str(contract_path),
        '--out',str(replay/'reproduced'),'--max-conclusions','999','--timeout','60','--depth','2']
    with(replay/'generation.log').open('w')as log:
        cp=subprocess.run(command,cwd=root,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=90)
    if cp.returncode or (replay/'reproduced/query.smt2').read_bytes()!=(proof/'query.smt2').read_bytes():
        raise ValueError('Ordered induction query does not reproduce exactly from source')
    negatives=[]
    for role,before,after in(('digest',b'expected_q<=expected_digest_i;chain_q',b'expected_q<=~expected_digest_i;chain_q'),
            ('fill',b'memory_q[state_q==CR_STORE ? crypto_word_q : fill_count_q[6:0]]<=memory_write_data;',b"memory_q[state_q==CR_STORE ? crypto_word_q : fill_count_q[6:0]]<=memory_write_data^256'd1;")):
        negative,negative_inputs,negative_result=checks.checked_run('encrypted-bank-lifecycle-mutant-'+role+'-r1')
        row=negative_result['results']['z3-bmc']
        if not row['passed']or row['status']!=['FAILED']or row['exit']!=1 or not row['traces']:
            raise ValueError('Lifecycle sensitivity control lacks a real bounded counterexample')
        for n in inputs['compile_sources']:
            wanted=(root/n).read_bytes()
            if n=='bank.sv':
                if wanted.count(before)!=1:raise ValueError('Native sensitivity site changed')
                wanted=wanted.replace(before,after,1)
            if (negative/n).read_bytes()!=wanted:raise ValueError('Sensitivity control changes more than its one native assignment')
        negatives.append(dict(run=negative.name,real_Z3_BMC_counterexample=True,
            cvc5_independent_search_passed=negative_result['results']['cvc5-bmc']['passed'],
            finished_sha256=sha((negative/'FINISHED.json').read_bytes())))
    receipt=dict(schema='native-encrypted-sealed-RAM-lifecycle-audit-v1',passed=True,run=root.name,
        image_sha256=bound['image_sha256'],native_banks=4,native_RAM_bits=4*32768,assertions=assertions,
        whole_native_SHA_and_pool_retained=True,actual_owner_contract_independently_discharged=True,
        source_projection_and_observer_reversal=True,exact_model_reelaboration=True,
        unmodified_Z3_satisfiable_reset_base=True,CVC5_complete_unbounded_joint_induction=True,
        ordered_new_induction_conclusions=len(all_new),all_conclusions_derived_before_import=True,
        exact_ordered_query_regeneration=True,query_regeneration_replies_are_not_a_new_solver_proof=True,
        positive_protocol_input_assumptions=[],arbitrary_data_outputs_added=False,
        observed_word_addresses_universally_quantified=True,all_64_data_blocks_and_padding_sequence_proved=True,
        checked_plaintext_RAM_copy_held_through_consumer_stall=True,partial_page_zero_tail_proved=True,
        native_call_return_reachability_from_source_equivalent_owner_model=True,
        owner_audit_sha256=sha(owner_raw),inputs_sha256=sha((root/'INPUTS.json').read_bytes()),
        original_finished_sha256=sha((root/'FINISHED.json').read_bytes()),ordered_finished_sha256=sha(result_raw),
        ordered_query_sha256=result['query_sha256'],ordered_responses_sha256=result['responses_sha256'],
        reset_query_binding=base_binding,semantic_controls=negatives,
        scope='Actual four encrypted banks, full RAM and native two-engine SHA pool under native provisioned parameters. Complete fill/decrypt/hash sequence, accepted block/chain ownership, comparison-gated seal, checked-RAM identity and held consumer response are proved in the usable shared-fault-free epoch. Private crypto replies and callers are unrestricted. Fixed digest selection, actual service-to-consumer composition, AES algorithm, cryptographic hardness, protected K/V use, bitstream equivalence, physical faults and whole-device training bounds require separate evidence.')
    (out/'FINISHED.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    (HERE/'ENCRYPTED-LIFECYCLE-AUDIT.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(passed=True,assertions=assertions,new_induction_conclusions=len(all_new))))


if __name__=='__main__':main()
