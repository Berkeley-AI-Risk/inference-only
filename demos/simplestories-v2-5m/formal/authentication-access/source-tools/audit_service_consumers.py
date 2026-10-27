"""Audit native service/bank transaction composition and checked-copy use."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

HERE=Path(__file__).resolve().parent


def sha(raw):return hashlib.sha256(raw).hexdigest()


def load(name,path):
    spec=importlib.util.spec_from_file_location('_service_consumer_audit_'+name,path)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--package',type=Path,required=True)
    p.add_argument('--out',type=Path,required=True);args=p.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    checked=load('checked',HERE/'audit_service_digest.py');common=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    queries=load('queries',HERE.parent/'formal-assurance/audit_fifo.py')
    dependencies={}
    for name in('BANK-INTERFACE-AUDIT.json','SERVICE-METADATA-AUDIT.json','SERVICE-DIGEST-AUDIT.json',
            'HASH-OWNERS-AUDIT.json','ENCRYPTED-LIFECYCLE-AUDIT.json','SHA-OWNED-AUDIT.json','FIXED-DIGEST-ASSETS-AUDIT.json'):
        raw=(HERE/name).read_bytes()
        if not json.loads(raw)['passed']:raise ValueError('Undischarged component: '+name)
        dependencies[name]=sha(raw)
    records=[]
    for variant in('baseline','encrypted'):
        root,inputs,original=checked.checked_run('service-consumer-'+variant+'-r1')
        work=out/variant;work.mkdir()
        contract=HERE/('runs/service-consumer-'+variant+'-projected-contract-r2')
        command=[sys.executable,'-I','-S','-B',str(HERE/'derive_service_consumer_contract.py'),
            '--variant',variant,'--out',str(work/'source-projection')]
        with(work/'source-projection.log').open('w')as log:
            cp=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=30)
        if cp.returncode or any((work/'source-projection'/n).read_bytes()!=(contract/n).read_bytes()for n in('INPUTS.json','design.smt2','checker.py')):
            raise ValueError('Source projection/premise discharge does not reproduce')
        contract_raw=(contract/'INPUTS.json').read_bytes();contract_data=json.loads(contract_raw)
        group=('baseline','seeded-sampling','kv-protected')if variant=='baseline'else('encrypted-memory',)
        joins={}
        for v in group:
            _,directory,bound=common.binding(args.package,v)
            if (directory/'project/service.sv').read_bytes()!=(root/'production-service.sv').read_bytes():
                raise ValueError('Actual native service identity differs')
            shared=(directory/'project/shared_token_probe.sv').read_bytes()
            for connection in(b'.request_word_i(model_req_word)',b'.response_data_o(model_rsp_data)',
                    b'.response_valid_o(model_rsp_valid)',b'.response_ready_i(model_rsp_ready)',
                    b'.private_runtime_req_word_index_o(model_req_word)',b'.private_runtime_rsp_data_i(model_rsp_data)',
                    b'.private_runtime_rsp_valid_i(model_rsp_valid)',b'.private_runtime_rsp_ready_o(model_rsp_ready)'):
                if connection not in shared:raise ValueError('Actual service-to-machine memory port join changed')
            joins[v]=dict(image_sha256=bound['image_sha256'],shared_source_sha256=sha(shared))
        if inputs['assumption_cells']!=8 or inputs['changed_production_parameters']or inputs['observer_constants']:
            raise ValueError('Child premise/native geometry inventory differs')
        graph=json.loads((root/'elaborated.json').read_bytes())['modules'][inputs['top']]
        cells=list(graph['cells'].values())
        if sum(c['type']=='$assume'for c in cells)!=8 or any(c['type']in('$anyseq','$anyconst')for c in cells):
            raise ValueError('Unexpected input promise or arbitrary state')
        if (root/'reset.smtc').read_text()!='initial\nassume (= [reset_n] false)\nstate 1\nassume (= [reset_n] false)\n':
            raise ValueError('Caller conditions were added to the reset base')
        base=original['results']['z3-bmc']
        if not base['passed']or base['status']!=['PASSED']or base['exit']!=0:raise ValueError('Native reset base incomplete')
        rebuilt=work/'recompiled';rebuilt.mkdir()
        for n in inputs['files']:
            target=rebuilt/n;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes((root/n).read_bytes())
        with(rebuilt/'re-elaboration.log').open('w')as log:
            cp=subprocess.run(['yosys','-Q','prove.ys'],cwd=rebuilt,stdout=log,stderr=subprocess.STDOUT,timeout=60)
        if cp.returncode or any((rebuilt/n).read_bytes()!=(root/n).read_bytes()for n in('design.smt2','elaborated.json','elaborated.il')):
            raise ValueError('Native service model does not reproduce')
        base_binding=queries.reproduce_query(root,'z3-bmc',base,False,work/'base-query-binding',recorded_replies=root/'z3-bmc.responses')
        proof=HERE/('runs/service-consumer-'+variant+'-ordered-z3-k2-r1')
        result_raw=(proof/'FINISHED.json').read_bytes();result=json.loads(result_raw)
        imported=contract_data['imported_current_state_assertion_indices']
        selected=[i for i in range(inputs['assertion_cells'])if i not in imported]
        if not result['passed']or result['solver']!='z3'or result['depth']!=2 or inputs['base_depth']<2 or not result['response_log_flushed_before_digest']:
            raise ValueError('Complete ordered induction is missing')
        if result['source_inputs_sha256']!=sha((root/'INPUTS.json').read_bytes())or result['owner_contract_inputs_sha256']!=sha(contract_raw)or result['owner_audit_sha256']!=dependencies['SERVICE-METADATA-AUDIT.json']:
            raise ValueError('Induction/source/premise association changed')
        if result['selected_new_assertions']!=selected or result['imported_source_proved_invariants']!=imported or len(selected)!=91 or len(result['results'])!=91:
            raise ValueError('Consumer conclusion inventory incomplete')
        if any(r['index']!=i or r['answer']!='unsat'or not r['passed']for i,r in zip(selected,result['results'])):
            raise ValueError('Consumer induction includes an unresolved conclusion')
        for n,key in(('query.smt2','query_sha256'),('responses.txt','responses_sha256'),('runner.py','runner_sha256')):
            if sha((proof/n).read_bytes())!=result[key]:raise ValueError('Ordered solver evidence changed')
        if result['shared_premise_answer']!='sat'or(proof/'responses.txt').read_text().split()!=['sat']+['unsat']*91:
            raise ValueError('Real solver response inventory differs')
        library=Path('/opt/homebrew/share/yosys/python3/smtio.py').resolve()
        if sha(library.read_bytes())!=result['grounding_library_sha256']or sha(Path(shutil.which('z3')).resolve().read_bytes())!=result['solver_binary_sha256']:
            raise ValueError('Solver/grounding implementation identity changed')
        replay=work/'ordered-query-binding';replay.mkdir();backend=replay/'backend';backend.mkdir()
        (replay/'runner.py').write_bytes((proof/'runner.py').read_bytes())
        executable=backend/'z3';executable.write_text('#!'+sys.executable+'\n'+'''import os,sys
from pathlib import Path
answers=Path(os.environ['CONSUMER_RECORDED_REPLIES']).read_text().split();cursor=0
for line in sys.stdin:
    if line.startswith('(check-sat'):
        if cursor>=len(answers):raise SystemExit('Recorded replies exhausted')
        sys.stdout.write(answers[cursor]+'\\n');sys.stdout.flush();cursor+=1
    if line.strip()=='(exit)':break
''');executable.chmod(0o700)
        env=dict(os.environ,PATH=str(backend)+os.pathsep+os.environ['PATH'],CONSUMER_RECORDED_REPLIES=str(proof/'responses.txt'))
        command=[sys.executable,'-I','-S','-B',str(replay/'runner.py'),'--run',str(root),'--contract',str(contract),
            '--out',str(replay/'reproduced'),'--max-conclusions','999','--timeout','45','--depth','2','--solver','z3',
            '--premise-audit',str(HERE/'SERVICE-METADATA-AUDIT.json')]
        with(replay/'generation.log').open('w')as log:
            cp=subprocess.run(command,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=60)
        if cp.returncode or (replay/'reproduced/query.smt2').read_bytes()!=(proof/'query.smt2').read_bytes():
            raise ValueError('Ordered consumer query does not reproduce exactly')
        cover=HERE/('runs/service-consumer-'+variant+'-cover-k14-r2')
        cover_result=json.loads((cover/'FINISHED.json').read_bytes())
        if not cover_result['passed']or cover_result['status']!=['PASSED']or cover_result['original_inputs_sha256']!=sha((root/'INPUTS.json').read_bytes()):
            raise ValueError('Both consumer response paths lack reachability evidence')
        for n,key in(('solver.log','log_sha256'),('query.smt2','query_sha256'),('responses.txt','responses_sha256')):
            if sha((cover/n).read_bytes())!=cover_result[key]:raise ValueError('Consumer reachability evidence changed')
        if sha((cover/'cover.smtc').read_bytes())!=cover_result['directed_coverage_only_constraints_sha256']:
            raise ValueError('Coverage-only input stimulus changed')
        cover_binding=queries.reproduce_query(root,'z3-cover',cover_result,False,work/'cover-query-binding',
            actual_path=cover/'query.smt2',recorded_replies=cover/'responses.txt',keep_trace_outputs=True)
        records.append(dict(run=root.name,variants=group,native_joins=joins,assertions=inputs['assertion_cells'],
            imported_source_proved_service_invariants=len(imported),new_ownership_conclusions=91,
            child_interface_guarantees_independently_discharged=True,caller_protocol_and_payload_value_assumptions=[],
            Z3_satisfiable_reset_base_and_complete_unbounded_induction=True,
            bank_and_metadata_response_paths_reached=True,exact_source_projection_and_model_reelaboration=True,
            exact_ordered_query_regeneration=True,query_regeneration_is_not_a_new_solver_proof=True,
            base_query_binding=base_binding,cover_query_binding=cover_binding,
            inputs_sha256=sha((root/'INPUTS.json').read_bytes()),ordered_finished_sha256=sha(result_raw),
            source_projection_sha256=sha(contract_raw),original_aggregate_passed=original['passed']))
    controls=[]
    positive=HERE/'runs/service-consumer-baseline-r1'
    for role,before,after in(('bank',b'{metadata_read,head_bank}',b"{metadata_read,(head_bank^BANK_W'(1))}"),
            ('metadata',b'data_q<=memory[address];',b"data_q<=memory[address^12'd1];")):
        root,inputs,result=checked.checked_run('service-consumer-mutant-'+role+'-r1');row=result['results']['z3-bmc']
        if not row['passed']or row['status']!=['FAILED']or row['exit']!=1 or not row['traces']:
            raise ValueError('Composed consumer sensitivity lacks a real counterexample')
        for n in inputs['compile_sources']:
            wanted=(positive/n).read_bytes()
            if n=='service.sv':
                if wanted.count(before)!=1:raise ValueError('Native sensitivity site changed')
                wanted=wanted.replace(before,after,1)
            if (root/n).read_bytes()!=wanted:raise ValueError('Sensitivity changes more than its one native selector')
        controls.append(dict(run=root.name,real_Z3_BMC_counterexample=True,
            cvc5_independent_search_passed=result['results']['cvc5-bmc']['passed'],finished_sha256=sha((root/'FINISHED.json').read_bytes())))
    receipt=dict(schema='native-service-bank-consumer-composition-audit-v1',passed=True,runs=records,
        component_audits=dependencies,semantic_controls=controls,
        expected_digest_and_SHA_and_same_sealed_RAM_premises_independently_discharged=True,
        checked_bank_request_word_matches_in_order_response=True,metadata_word_matches_fixed_ROM_row=True,
        actual_service_to_machine_private_model_port_join_checked=True,
        scope='Native four-bank model service composed with source-proved bank handshake contracts and separately proved SHA/fixed-digest/sealed-RAM lifecycle. Each in-order model response corresponds to the requested checked bank word or fixed metadata ROM row, with the same sealed copy retained through stalls. Actual wiring to the machine private model-memory port is checked. Numerical use inside arithmetic, protected K/V guard use, cryptographic hardness, bitstream equivalence, physical faults and whole-device training bounds remain separate obligations.')
    (out/'FINISHED.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    (HERE/'SERVICE-CONSUMER-AUDIT.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(passed=True,distinct_services=2,variants=4,new_conclusions_per_service=91)))


if __name__=='__main__':main()
