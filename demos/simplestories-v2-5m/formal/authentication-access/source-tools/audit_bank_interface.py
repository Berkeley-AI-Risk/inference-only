"""Discharge the native bank interface premises needed by service composition."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

HERE=Path(__file__).resolve().parent


def sha(raw):return hashlib.sha256(raw).hexdigest()


def load(name,path):
    spec=importlib.util.spec_from_file_location('_bank_interface_audit_'+name,path)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--package',type=Path,required=True)
    p.add_argument('--out',type=Path,required=True);args=p.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    checked=load('checked',HERE/'audit_service_digest.py');common=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    observer=load('observer',HERE.parent/'formal-assurance/audit_boot_boundary.py');queries=load('queries',HERE.parent/'formal-assurance/audit_fifo.py')
    records=[]
    for variant,name in(('baseline','bank-interface-baseline-r1'),('kv-protected','bank-interface-protected-r1'),('encrypted-memory','bank-interface-encrypted-r1')):
        root,inputs,result=checked.checked_run(name);encrypted=variant=='encrypted-memory'
        if not result['passed']or inputs['assumption_cells']or inputs['observer_constants']or inputs['changed_production_parameters']:
            raise ValueError('Interface proof is incomplete or introduces an input promise')
        monitor=(root/'monitor.inc.sv').read_bytes();observer.observer_writes_only(monitor.decode())
        source=(root/'bank.sv').read_bytes();prefix=b'`undef FORMAL\n'
        if not source.startswith(prefix)or source.count(b'\n'+monitor)!=1:raise ValueError('Observer insertion changed')
        source=source[len(prefix):].replace(b'\n'+monitor,b'',1)
        if not encrypted:
            ports=b',\n    input wire f_sha_busy_i,f_sha_done_i,\n    input wire [255:0] f_sha_state_i'
            replacement=b'    assign sha_busy=f_sha_busy_i;\n    assign sha_done=f_sha_done_i;\n    assign sha_state=f_sha_state_i;'
            if source.count(ports)!=1 or source.count(replacement)!=1:raise ValueError('Unrestricted SHA replacement changed')
            source=source.replace(ports,b'',1).replace(replacement,(root/'removed-sha-instance.sv.txt').read_bytes(),1)
        if source!=(root/'production-bank.sv').read_bytes():raise ValueError('Native bank source reversal failed')
        if len(inputs['internal_cuts'])!=(0 if encrypted else 3)or any(c['assumptions']for c in inputs['internal_cuts']):
            raise ValueError('Interface theorem gained a child behavior restriction')
        graph=json.loads((root/'elaborated.json').read_bytes())['modules'][inputs['top']]
        if any(c['type']in('$anyseq','$anyconst','$assume')for c in graph['cells'].values()):raise ValueError('Unexpected assumption or arbitrary-state cell')
        group=('baseline','seeded-sampling')if variant=='baseline'else(variant,);joins={}
        for v in group:
            _,directory,bound=common.binding(args.package,v)
            if (directory/'project/bank.sv').read_bytes()!=source:raise ValueError('Native source identity differs')
            joins[v]=bound
        harness=(root/'harness.sv').read_text()
        if '#(.IMAGE_WORDS(227062)'not in harness:raise ValueError('Actual bank geometry changed')
        if encrypted and ".KEY_IS_PROVISIONED(1'b1),.MODEL_NONCE(96'h112233445566778899aabbcc)"not in harness:
            raise ValueError('Native provisioned parameters changed')
        work=out/variant;work.mkdir()
        for n in inputs['files']:
            target=work/n;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes((root/n).read_bytes())
        with(work/'re-elaboration.log').open('w')as log:
            cp=subprocess.run(['yosys','-Q','prove.ys'],cwd=work,stdout=log,stderr=subprocess.STDOUT,timeout=60)
        if cp.returncode or any((work/n).read_bytes()!=(root/n).read_bytes()for n in('design.smt2','elaborated.json','elaborated.il')):
            raise ValueError('Native interface model does not reproduce')
        phases={}
        for phase,row in result['results'].items():
            if not row['passed']or row['status']!=['PASSED']or row['exit']!=0:raise ValueError('Interface solver phase incomplete')
            phases[phase]=queries.reproduce_query(root,phase,row,False,work/(phase+'-query-binding'),
                recorded_replies=root/(phase+'.responses'),keep_trace_outputs=phase.endswith('cover'))
        records.append(dict(run=name,variants=group,native_joins=joins,assertions=inputs['assertion_cells'],
            both_solver_satisfiable_bases_and_unbounded_induction=True,both_solver_begin_reachability=True,
            private_SHA_and_crypto_replies_unrestricted=True,child_behavior_assumptions=[],
            source_reversal=True,exact_model_reelaboration=True,query_bindings=phases,
            inputs_sha256=sha((root/'INPUTS.json').read_bytes()),finished_sha256=sha((root/'FINISHED.json').read_bytes())))
    negative,negative_inputs,negative_result=checked.checked_run('bank-interface-mutant-raw-valid-r1')
    positive=HERE/'runs/bank-interface-baseline-r1'
    for n in negative_inputs['compile_sources']:
        wanted=(positive/n).read_bytes()
        if n=='bank.sv':wanted=wanted.replace(b'response_valid_q<=read_fire;',b'response_valid_q<=read_valid_i;',1)
        if (negative/n).read_bytes()!=wanted:raise ValueError('Negative control changes more than response ownership')
    for row in negative_result['results'].values():
        if not row['passed']or row['status']!=['FAILED']or row['exit']!=1 or not row['traces']:
            raise ValueError('Response-ownership control lacks a real counterexample')
    receipt=dict(schema='native-bank-single-pending-interface-audit-v1',passed=True,runs=records,
        response_valid_equals_reference_pending_when_not_cancelled=True,
        read_ready_requires_empty_slot_or_old_response_acceptance=True,
        reference_transaction_page_and_word_preserved=True,native_fault_sticky_until_hard_reset=True,
        both_solver_response_ownership_mutant_real_counterexamples=True,
        negative_finished_sha256=sha((negative/'FINISHED.json').read_bytes()),
        scope='Native bank single-pending interface, cancellation, refill exclusion, response READY and recorded page/word, independent of every private SHA/crypto reply. These child handshake premises are proved without assumptions for subsequent parent composition. This overapproximation does not prove payload authentication; the full native bank/SHA lifecycle theorems supply that separate result.')
    (out/'FINISHED.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    (HERE/'BANK-INTERFACE-AUDIT.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(passed=True,distinct_sources=3,variants=4)))


if __name__=='__main__':main()
