"""Classify every retained native memory object by its real write ports.

This is a coverage roster, not signoff. A module proof does not automatically
cover all its memories; read-only arrays still need initialization/range facts.
Packed registers and unresolved vendor storage remain separate census items.
"""
import json
from pathlib import Path

from record_progress import sha
from run_attention_ownership import HERE


def main():
    hierarchy=json.loads((HERE/'HIERARCHY-BINDINGS.json').read_text())
    proofs=json.loads((HERE/'PROOF-INSTANTIATION-BINDINGS.json').read_text())
    if not hierarchy['structural_binding_passed']or not proofs['instantiation_audit_passed']:
        raise ValueError('Native hierarchy/source association incomplete')
    variants={}
    for variant,binding in hierarchy['variants'].items():
        run=HERE/'runs'/binding['census_run'];raw=(run/'CENSUS.json').read_bytes()
        if sha(raw)!=binding['census_sha256']:raise ValueError('Native census changed')
        census=json.loads(raw);stores=[];modules={}
        for instance in census['instances']:
            declared=instance['declared_memory_objects'];ports=instance['memory_port_cells']
            for name,geometry in declared.items():
                relevant={n:p for n,p in ports.items()if p['parameters'].get('MEMID','').lstrip('\\')==name}
                writes=[n for n,p in relevant.items()if p['type']in('$memwr','$memwr_v2')]
                initializers=[n for n,p in relevant.items()if p['type'].startswith('$meminit')]
                reads=[n for n,p in relevant.items()if p['type'].startswith('$memrd')]
                module=instance['original_module']
                candidates=[]
                for proof,row in proofs['proof_module_joins'].items():
                    if module in row['modules']and variant in row['modules'][module]['variant_joins']:
                        candidates.append(proof)
                stores.append(dict(instance=instance['path'],module=module,memory=name,
                    words=geometry['size'],width=geometry['width'],bits=geometry['size']*geometry['width'],
                    source=geometry['src'],runtime_write_ports=writes,read_ports=reads,initialization_ports=initializers,
                    classification='runtime_writable_array'if writes else'no_runtime_write_port',
                    candidate_component_records=sorted(candidates),memory_specific_signoff=False))
                group=modules.setdefault(module,dict(array_instances=0,runtime_writable_array_instances=0,
                    runtime_writable_bits=0,readonly_array_instances=0,candidate_component_records=set()))
                group['array_instances']+=1;group['candidate_component_records'].update(candidates)
                if writes:group['runtime_writable_array_instances']+=1;group['runtime_writable_bits']+=geometry['size']*geometry['width']
                else:group['readonly_array_instances']+=1
        for row in modules.values():row['candidate_component_records']=sorted(row['candidate_component_records'])
        variants[variant]=dict(image_sha256=binding['image_sha256'],census_sha256=binding['census_sha256'],
            declared_memory_objects=len(stores),runtime_writable_arrays=sum(bool(r['runtime_write_ports'])for r in stores),
            runtime_writable_bits=sum(r['bits']for r in stores if r['runtime_write_ports']),
            modules=modules,stores=stores,
            unresolved_vendor_leaf_instances=census['unresolved_leaf_instances'],
            native_custom_sequential_cells=sum(len(i['sequential_cells'])for i in census['instances']),
            native_custom_sequential_bits=sum(c['bits']for i in census['instances']for c in i['sequential_cells'].values()))
    result=dict(structural_memory_roster_complete=True,whole_device_memory_signoff=False,
        memory_specific_signoff=False,session_milestone_complete=False,variants=variants,
        limits=[
            'Candidate module receipts require memory-specific obligation/source/geometry joins before signoff.',
            'No runtime write port does not establish initialized data or legal consumer indices.',
            'Packed registers and arrays lowered to FFs require the separate sequential-state inventory.',
            'Vendor leaves, including any embedded storage, need explicit assumptions or structural access audits.'
        ],checker_sha256=sha(Path(__file__).read_bytes()),
        hierarchy_binding_sha256=sha((HERE/'HIERARCHY-BINDINGS.json').read_bytes()),
        proof_instantiation_binding_sha256=sha((HERE/'PROOF-INSTANTIATION-BINDINGS.json').read_bytes()))
    (HERE/'NATIVE-STORE-ROSTER.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps({v:{k:d[k]for k in('declared_memory_objects','runtime_writable_arrays','runtime_writable_bits')}for v,d in variants.items()}))


if __name__=='__main__':main()
