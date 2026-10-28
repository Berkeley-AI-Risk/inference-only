"""Bind native K/V cancellation proofs to current images, RAMs and mapper edges."""
import argparse
import json
from pathlib import Path
import re

from record_progress import audit, sha
from run_attention_ownership import HERE
from audit_proof_instantiations import body
from audit_model_drain import observer_only
from audit_core_model_drain import instance_parameters
from run_projection_relational import instance_con
from run_kv_session_drain import TOP


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--runs',nargs='+',required=True)
    ap.add_argument('--out',type=Path,required=True)
    args=ap.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    joins_raw=(HERE/'PROOF-INSTANTIATION-BINDINGS.json').read_bytes()
    joins=json.loads(joins_raw);(out/'instantiation-bindings.json').write_bytes(joins_raw)
    results={};manifest={str((out/'instantiation-bindings.json').resolve()):sha(joins_raw)}
    for name in args.runs:
        run=HERE/'runs'/name;receipt=audit(name,'Native typed K/V cache cancellation/drain')
        if receipt['status']!='proved_component':raise ValueError('K/V drain proof is incomplete')
        inp=json.loads((run/'INPUTS.json').read_text());b=inp['binding']
        if (inp['mutant']or inp['assumption_cells']or inp['internal_cuts']or
            b['initial_hard_reset']or inp['changed_production_parameters']):
            raise ValueError('Unexpected reset, cuts, assumptions or parameters')
        for filename,row in inp['files'].items():
            path=run/filename;raw=path.read_bytes()
            if sha(raw)!=row['sha256']:raise ValueError('Changed proof input')
            manifest[str(path.resolve())]=row['sha256']
        monitor=(run/'session-drain-monitor.inc.sv').read_text();observer_only(monitor)
        native=body((run/('production-'+TOP+'.sv')).read_bytes(),TOP).decode()
        actual=(run/(TOP+'.sv')).read_text()
        if actual.count(monitor)!=1:raise ValueError('Observer is not uniquely removable')
        if actual.replace('\n'+monitor+'\n','\n',1)!='`undef FORMAL\n'+native+'\n':
            raise ValueError('Functional native cache body changed')
        mapper='board1_context2048_typed_address_mapper'
        original_mapper=body((run/('production-'+mapper+'.sv')).read_bytes(),mapper).decode()
        if (run/(mapper+'.sv')).read_text()!='`undef FORMAL\n'+original_mapper+'\n':
            raise ValueError('Functional mapper body changed')
        edges={}
        for instance in ('u_write_shadow_mapper','u_read_shadow_mapper'):
            ports=instance_con(native,mapper,instance)
            if ports!=instance_con(actual,mapper,instance):raise ValueError('Mapper functional ports changed')
            if instance_parameters(native,mapper,instance)!=instance_parameters(actual,mapper,instance):
                raise ValueError('Mapper parameter header changed')
            edges[instance]=ports
        baseline=b['variant']=='baseline';banks=8 if baseline else 16;size=32 if baseline else 8
        graph=json.loads((run/'elaborated.json').read_text())['modules'][inp['top']]
        memories={}
        for n,c in graph['cells'].items():
            if c['type']!='$mem_v2':continue
            geometry={k:int(c['parameters'][k],2)for k in ('WIDTH','SIZE','ABITS','RD_PORTS','WR_PORTS')}
            expected=dict(WIDTH=32,SIZE=size,ABITS=5 if baseline else 3,RD_PORTS=1,WR_PORTS=1)
            if geometry!=expected:raise ValueError('Native cache memory geometry changed')
            memories[n]=geometry
        if len(memories)!=banks:raise ValueError('Native cache bank count changed')
        variants=joins['proof_module_joins'][name]['active_variant_source_joins']
        expected_variants=['baseline','seeded-sampling']if baseline else['encrypted-memory','kv-protected']
        if variants!=expected_variants:raise ValueError('Unexpected current image source class')
        for filename in ('INPUTS.json','FINISHED.json','elaborated.json'):
            path=run/filename;manifest[str(path.resolve())]=sha(path.read_bytes())
        results[name]=dict(receipt=receipt,active_variants=variants,native_mapper_edges=edges,
            full_native_memories=memories,retained_payload_bits=banks*size*32,
            read_credit_limit=b['read_credit_limit'],physical_reset_required=False)
    checker=out/'checker.py';checker.write_bytes(Path(__file__).read_bytes());manifest[str(checker)]=sha(checker.read_bytes())
    result=dict(native_kv_cancellation_source_join_passed=True,cases=results,artifact_manifest=manifest,
        whole_device_session_theorem=False,full_payload_correspondence_proved=False,
        scope='Exact unchanged native cache/mapper hierarchy and all payload RAMs; accepted typed work conserved through CLEAR, healthy busy-low barrier, revoked prefixes/pending/cache authority, cancelled completions expose only fault/zero payload. Guard, outer transport, current tensor initialization and complete device composition remain separate.')
    (out/'FINISHED.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(native_kv_cancellation_source_join_passed=True,source_classes=len(results),whole_device_session_theorem=False)))


if __name__=='__main__':main()
