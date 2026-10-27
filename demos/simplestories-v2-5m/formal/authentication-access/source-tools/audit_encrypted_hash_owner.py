"""Audit actual encrypted four-bank SHA ownership/data routing and source joins."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess

HERE=Path(__file__).resolve().parent
OLD=HERE.parent/'formal-assurance'


def sha(raw):return hashlib.sha256(raw).hexdigest()


def load(name,path):
    spec=importlib.util.spec_from_file_location('_encrypted_owner_audit_'+name,path)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--package',type=Path,required=True);p.add_argument('--out',type=Path,required=True)
    args=p.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    common=load('binding',OLD/'run_handoff.py');checks=load('checks',HERE/'audit_service_digest.py')
    arithmetic=load('arithmetic',HERE/'proved_arithmetic.py');queries=load('queries',OLD/'audit_fifo.py')
    observer=load('observer',OLD/'audit_boot_boundary.py')
    root,inputs,result=checks.checked_run('encrypted-hash-owner-r4-data-routing')
    _,directory,bound=common.binding(args.package,'encrypted-memory')
    original={n:(directory/('project/'+n)).read_bytes()for n in('sha.sv','bank.sv','service.sv','shared_token_probe.sv','uart_core.sv')}
    for n,raw in original.items():
        if (root/('production-'+n)).read_bytes()!=raw:raise ValueError('Actual native source identity changed')
    if re.findall(rb'\.AUTH_BANKS\((\d+)\)',original['uart_core.sv'])!=[b'4']or inputs['binding']['native_banks']!=4:
        raise ValueError('Actual four-bank geometry changed')
    if inputs['assumption_cells']or inputs['changed_production_parameters']or inputs['observer_constants']:
        raise ValueError('A protocol promise, state cut or native dimension change was introduced')
    rewritten,obligations,_=arithmetic.rewrite(original['sha.sv'])
    if inputs['internal_cuts']!=obligations:raise ValueError('Stateless arithmetic premises changed')
    normalization=json.loads((HERE/'POOL-LOOP-NORMALIZATION-AUDIT.json').read_bytes())
    native=(root/'pool-loop-native.sv').read_bytes();scoped=(root/'pool-loop-scoped.sv').read_bytes()
    if not normalization['passed']or sha(native)!=normalization['native_module_sha256']or sha(scoped)!=normalization['scoped_module_sha256']:
        raise ValueError('Frontend normalization premise is not discharged for this source')
    sha_source=(root/'sha.sv').read_bytes();prefix=b'`undef FORMAL\n'
    if not sha_source.startswith(prefix):raise ValueError('Formal-source boundary changed')
    sha_source=sha_source[len(prefix):]
    pool_monitor=(root/'pool-monitor.inc.sv').read_bytes();route_monitor=(root/'data-route-monitor.inc.sv').read_bytes()
    for monitor in(pool_monitor,route_monitor):observer.observer_writes_only(monitor.decode())
    if sha_source.count(b'\n'+pool_monitor)!=1 or sha_source.count(route_monitor)!=1:raise ValueError('Pool observer boundaries changed')
    sha_source=sha_source.replace(b'\n'+pool_monitor,b'',1).replace(route_monitor,b'',1)
    if sha_source.count(scoped)!=1:raise ValueError('Normalized native pool identity changed')
    sha_source=sha_source.replace(scoped,native,1)
    if sha_source!=rewritten:raise ValueError('Observer/normalization reversal changed a native SHA/pool expression')
    bank=(root/'bank.sv').read_bytes();bank_monitor=(root/'bank-monitor.inc.sv').read_bytes()
    observer.observer_writes_only(bank_monitor.decode())
    if not bank.startswith(prefix)or bank.count(b'\n'+bank_monitor)!=1 or bank[len(prefix):].replace(b'\n'+bank_monitor,b'',1)!=original['bank.sv']:
        raise ValueError('Bank observer reversal failed')
    # These exact native buses are the child ports on which the route
    # assertions operate. The result-mode and input selectors are unchanged.
    for connection in(b'.block_i(blocks[int\'(active_slot)*512 +: 512])',b'.state_i(states[int\'(active_slot)*256 +: 256])',
        b'board1_sha256_bank_owned_compress #(.REGISTER_RESULT(0)) u_sha'):
        if connection not in native:raise ValueError('Native compressor data/parameter join changed')
    harness=(root/'harness.sv').read_bytes();service=original['service.sv']
    for connection in(b'.abort_i(fault_o)',b'.request_valid_i(hash_request_valid)',b'.request_ready_o(hash_request_ready)',
        b'.request_block_i(hash_request_block)',b'.request_state_i(hash_request_state)',b'.pending_o(hash_pending)',
        b'.response_valid_o(hash_response_valid)',b'.response_state_o(hash_response_state)',
        b'.hash_request_valid_o(hash_request_valid[b])',b'.hash_request_ready_i(hash_request_ready[b])',
        b'.hash_pending_i(hash_pending[b])',b'.hash_response_valid_i(hash_response_valid[b])',
        b'.hash_request_block_o(hash_request_block[b*512 +: 512])',
        b'.hash_request_state_o(hash_request_state[b*256 +: 256])',
        b'.hash_response_state_i(hash_response_state[b*256 +: 256])'):
        if connection not in service or connection not in harness:raise ValueError('Actual private service-to-bank/pool join changed')
    for literal in(b".KEY_IS_PROVISIONED(1'b1)",b".MODEL_NONCE(96'h112233445566778899aabbcc)"):
        if literal not in harness or literal not in original['shared_token_probe.sv']:
            raise ValueError('Actual provisioned bank parameters differ')
    if b'assign fault_o=fault_q || (|bank_fault) || crypto_fault || hash_fault;'not in service:
        raise ValueError('Native fault-abort composition changed')
    graph=json.loads((root/'elaborated.json').read_bytes())['modules'][inputs['top']];cells=list(graph['cells'].values())
    if sum(c['type']=='$assert'for c in cells)!=38 or sum(c['type']=='$cover'for c in cells)!=2 or any(c['type']in('$anyconst','$anyseq','$assume')for c in cells):
        raise ValueError('Actual ownership/data-route property inventory changed')
    memories=[c for c in cells if c['type']=='$mem_v2']
    if len(memories)!=4 or any(int(c['parameters']['WIDTH'],2)!=256 or int(c['parameters']['SIZE'],2)!=128 for c in memories):
        raise ValueError('Four complete native page RAMs are not retained')
    owned=json.loads((HERE/'SHA-OWNED-AUDIT.json').read_bytes())
    record=[r for r in owned['runs']if r['variants']==['encrypted-memory']]
    if not owned['passed']or len(record)!=1 or record[0]['native_joins']['encrypted-memory']['library_sha256']!=sha(original['sha.sv']):
        raise ValueError('Exact native compressor FIPS correspondence theorem is missing')
    required={'z3-bmc','cvc5-bmc','cvc5-induction','z3-cover'}
    for phase in required:
        row=result['results'][phase]
        if not row['passed']or row['status']!=['PASSED']or row['exit']!=0:raise ValueError('Required ownership phase incomplete')
    if '--smtc'in result['results']['cvc5-induction']['command']:raise ValueError('A witness condition entered induction')
    work=out/'recompiled';work.mkdir()
    for n in inputs['files']:
        target=work/n;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes((root/n).read_bytes())
    with(work/'re-elaboration.log').open('w')as log:
        cp=subprocess.run(['yosys','-Q','prove.ys'],cwd=work,stdout=log,stderr=subprocess.STDOUT,timeout=60)
    if cp.returncode or any((work/n).read_bytes()!=(root/n).read_bytes()for n in('design.smt2','elaborated.json','elaborated.il')):
        raise ValueError('Full native bank/pool model does not reproduce')
    phases={}
    for phase in sorted(required):
        phases[phase]=queries.reproduce_query(root,phase,result['results'][phase],False,out/(phase+'-query-binding'),
            recorded_replies=root/(phase+'.responses'),keep_trace_outputs=phase.endswith('cover'))
    negative,negative_inputs,negative_result=checks.checked_run('encrypted-hash-owner-mutant-wrong-bank-r2-page2')
    primary=negative_result['results']['z3-bmc']
    if not primary['passed']or primary['status']!=['FAILED']or primary['exit']!=1 or not primary['traces']:
        raise ValueError('Wrong-bank data routing mutant lacks a real primary counterexample')
    for n in inputs['compile_sources']:
        expected=(root/n).read_bytes()
        if n=='sha.sv':expected=expected.replace(b"SLOT_W'(int'(owner_q[g])/2) : grant_slot[g];",b'grant_slot[g] : grant_slot[g];',1)
        if (negative/n).read_bytes()!=expected:raise ValueError('The wrong-bank control changes more than the single intended selector')
    secondary=negative_result['results']['cvc5-bmc']
    secondary_complete=secondary['passed']and secondary['status']==['FAILED']and secondary['exit']==1
    # The real primary BMC counterexample is sufficient for sensitivity. Do
    # not turn a secondary timeout into a successful independent check.
    replay=HERE/'runs/encrypted-hash-owner-mutant-wrong-bank-cvc5-vcd-r1/FINISHED.json'
    replay_complete=replay.is_file()and json.loads(replay.read_bytes()).get('passed')is True
    receipt=dict(schema='actual-native-encrypted-four-bank-hash-ownership-audit-v1',passed=True,run=root.name,
        image_sha256=bound['image_sha256'],native_banks=4,native_page_ram_bits=4*32768,assertions=38,
        full_actual_pool_and_sha_retained=True,actual_engine_data_bus_selection_checked=True,
        actual_bank_accepted_chain_preserved_through_DONE=True,actual_return_owner_and_data_routing_checked=True,
        private_crypto_and_bank_caller_inputs_unrestricted=True,no_crypto_behavior_assumptions=True,
        arithmetic_premises=obligations,frontend_scope_premise_independently_discharged=True,
        source_reversal=True,exact_model_reelaboration=True,required_query_bindings=phases,
        both_solver_satisfiable_reset_bases=True,cvc5_unbounded_induction=True,
        z3_unbounded_induction=result['results']['z3-induction']['passed'],z3_real_call_and_return_reachability=True,
        cvc5_cover_search_passed=result['results']['cvc5-cover']['passed'],
        semantic_wrong_bank_mutant_Z3_BMC_counterexample=True,
        semantic_wrong_bank_mutant_cvc5_BMC_counterexample=secondary_complete,
        semantic_wrong_bank_mutant_cvc5_VCD_witness_checked=replay_complete,
        secondary_negative_timeouts_not_credited=not(secondary_complete or replay_complete),
        inputs_sha256=sha((root/'INPUTS.json').read_bytes()),finished_sha256=sha((root/'FINISHED.json').read_bytes()),
        negative_finished_sha256=sha((negative/'FINISHED.json').read_bytes()),
        scope='Actual native four-bank encrypted SHA ownership and data routing, with all full RAMs and the complete native SHA datapaths. The private live-input SHA chain-owner premise is discharged; no arithmetic reply oracle or crypto protocol promise. This does not yet prove the encrypted sealed-page lifecycle, parent allocation/consumer composition, AES arithmetic, K/V guard use, physical security, mapped-image equivalence or a whole-device training bound.')
    (out/'FINISHED.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    (HERE/'ENCRYPTED-HASH-OWNER-AUDIT.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(passed=True,assertions=38,native_banks=4)))


if __name__=='__main__':main()
