"""Audit source-bound K/V guard epoch, ownership and verification gates."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

HERE=Path(__file__).resolve().parent


def sha(raw):return hashlib.sha256(raw).hexdigest()


def load(name,path):
    spec=importlib.util.spec_from_file_location('_guard_control_audit_'+name,path)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--package',type=Path,required=True)
    p.add_argument('--out',type=Path,required=True);args=p.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    checked=load('checked',HERE/'audit_service_digest.py');common=load('bindings',HERE.parent/'formal-assurance/run_handoff.py')
    observer=load('observer',HERE.parent/'formal-assurance/audit_boot_boundary.py');queries=load('queries',HERE.parent/'formal-assurance/audit_fifo.py')
    records=[]
    for variant,name in(('kv-protected','kv-guard-control-protected-r3-owner'),('encrypted-memory','kv-guard-control-encrypted-r1')):
        root,inputs,result=checked.checked_run(name);_,directory,bound=common.binding(args.package,variant)
        original=(directory/'project/kv_integrity_guard.sv').read_bytes();monitor=(root/'monitor.inc.sv').read_bytes()
        if original!=(root/'production-guard.sv').read_bytes():raise ValueError('Native guard source identity differs')
        observer.observer_writes_only(monitor.decode())
        source=(root/'guard.sv').read_bytes();prefix=b'`undef FORMAL\n'
        if not source.startswith(prefix)or source.count(b'\n'+monitor)!=1:raise ValueError('Observer boundary changed')
        source=source[len(prefix):].replace(b'\n'+monitor,b'',1)
        ports=b',\n    input wire f_hash_begin_ready_i,f_hash_word_ready_i,f_hash_digest_valid_i,f_hash_fault_i,\n    input wire [255:0] f_hash_digest_i'
        replacement=b'    assign hash_begin_ready=f_hash_begin_ready_i;\n    assign hash_word_ready=f_hash_word_ready_i;\n'
        replacement+=b'    assign hash_digest_valid=f_hash_digest_valid_i;\n    assign hash_digest=f_hash_digest_i;\n    assign hash_fault=f_hash_fault_i;'
        if source.count(ports)!=1 or source.count(replacement)!=1:raise ValueError('Private unrestricted child boundary changed')
        source=source.replace(ports,b'',1).replace(replacement,(root/'removed-hash-instance.sv.txt').read_bytes(),1)
        if source!=original:raise ValueError('Native guard source reversal failed')
        if inputs['assumption_cells']or inputs['observer_constants']or inputs['changed_production_parameters']or len(inputs['internal_cuts'])!=5:
            raise ValueError('A protocol promise or native geometry change was introduced')
        if any(c['assumptions']for c in inputs['internal_cuts']):raise ValueError('A private hash reply was restricted')
        graph=json.loads((root/'elaborated.json').read_bytes())['modules'][inputs['top']];cells=list(graph['cells'].values())
        if any(c['type']in('$anyseq','$anyconst','$assume')for c in cells)or sum(c['type']=='$assert'for c in cells)!=37:
            raise ValueError('Property/arbitrary-state inventory changed')
        memories=[c for c in cells if c['type']=='$mem_v2']
        geometry=sorted((int(c['parameters']['SIZE'],2),int(c['parameters']['WIDTH'],2))for c in memories)
        if geometry!=[(640,32)]+[(4096,32)]*6+[(13824,32)]:raise ValueError('Full native eight-RAM geometry changed')
        if len(graph['netnames']['epoch_q']['bits'])!=64 or len(graph['netnames']['watchdog_q']['bits'])!=26:
            raise ValueError('Native epoch/watchdog dimensions changed')
        if variant=='encrypted-memory'and graph['ports']['epoch_o']['bits']!=graph['netnames']['epoch_q']['bits']:
            raise ValueError('Actual encrypted guard epoch output differs from its proved counter')
        if (root/'reset.smtc').read_text()!='initial\nassume (= [reset_n] false)\nstate 1\nassume (= [reset_n] false)\n':
            raise ValueError('A caller condition was added to safety')
        work=out/variant;work.mkdir()
        for n in inputs['files']:
            target=work/n;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes((root/n).read_bytes())
        with(work/'re-elaboration.log').open('w')as log:
            cp=subprocess.run(['yosys','-Q','prove.ys'],cwd=work,stdout=log,stderr=subprocess.STDOUT,timeout=60)
        if cp.returncode or any((work/n).read_bytes()!=(root/n).read_bytes()for n in('design.smt2','elaborated.json','elaborated.il')):
            raise ValueError('Native guard control model does not reproduce')
        phases={}
        for phase,row in result['results'].items():
            if not row['passed']or row['status']!=['PASSED']or row['exit']!=0:raise ValueError('Guard solver phase incomplete')
            phases[phase]=queries.reproduce_query(root,phase,row,False,work/(phase+'-query-binding'),
                recorded_replies=root/(phase+'.responses'),keep_trace_outputs=phase.endswith('cover'))
        records.append(dict(run=name,variant=variant,image_sha256=bound['image_sha256'],assertions=37,native_RAM_bits=1249280,
            both_solver_satisfiable_bases_unbounded_induction_and_write_completion_covers=True,
            source_reversal=True,exact_model_reelaboration=True,exact_query_regeneration=phases,
            private_hash_and_DDR_replies_unrestricted=True,caller_protocol_and_payload_assumptions=[],
            inputs_sha256=sha((root/'INPUTS.json').read_bytes()),finished_sha256=sha((root/'FINISHED.json').read_bytes())))
    controls=[];positive=HERE/'runs/kv-guard-control-protected-r3-owner'
    for role,before,after in(('address',b"m_wr_shadow=address(layer_q,position_q,{1'b0,head_q},row_word_q);",b"m_wr_shadow=address(layer_q,position_q,{1'b0,head_q},row_word_q)^19'd1;"),
            ('epoch',b"epoch_q<=epoch_q+1'b1;",b"epoch_q<=epoch_q+64'd2;")):
        root,inputs,result=checked.checked_run('kv-guard-control-mutant-'+role+'-r1')
        for n in inputs['compile_sources']:
            wanted=(positive/n).read_bytes()
            if n=='guard.sv':
                if wanted.count(before)!=1:raise ValueError('Native sensitivity site changed')
                wanted=wanted.replace(before,after,1)
            if (root/n).read_bytes()!=wanted:raise ValueError('Guard control changes more than its one native expression')
        for row in result['results'].values():
            if not row['passed']or row['status']!=['FAILED']or row['exit']!=1 or not row['traces']:
                raise ValueError('Guard sensitivity lacks real bounded counterexamples')
        controls.append(dict(run=root.name,both_solver_real_BMC_counterexamples=True,finished_sha256=sha((root/'FINISHED.json').read_bytes())))
    receipt=dict(schema='native-KV-guard-epoch-address-ownership-control-audit-v1',passed=True,runs=records,semantic_controls=controls,
        epoch_one_step_per_CLEAR_rise_saturation_and_terminal_overflow_proved=True,
        typed_request_shape_exact_shadow_address_and_owned_write_payload_proved=True,
        single_owner_and_fault_CLEAR_output_gates_proved=True,
        normal_response_requires_verification_event_and_matching_request_identity=True,
        scope='Actual protected/encrypted guard control with all eight full native RAMs and no caller/hash/DDR promises. Prove saturating epoch history, typed address arithmetic, single ownership, fault/CLEAR gates and comparison-gated cached response identity. The private hash child is wholly unrestricted here. Trusted-tag/staging/partial RAM correspondence, actual hash composition, machine capture/use, cryptographic hardness, physical faults, bitstream equivalence and whole-device training bounds require separate evidence.')
    (out/'FINISHED.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    (HERE/'KV-GUARD-CONTROL-AUDIT.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(passed=True,variants=2,assertions_per_variant=37)))


if __name__=='__main__':main()
