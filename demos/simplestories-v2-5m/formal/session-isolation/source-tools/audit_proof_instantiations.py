"""Require credited proof modules to exist in the actual native hierarchy.

Bind original module bodies, not merely a distributed filename, to each native
instance. Identical module definitions can transfer across different enclosing
files. Parameter/primitive semantics and contract composition remain explicit.
"""
import json
from pathlib import Path
import re

from record_progress import CASES
from run_attention_ownership import HERE, load
from run_memory_isolation import SPECS
from run_service_memory import CASES as SERVICES


def body(raw,name):
    found=re.findall(r'^module\s+'+re.escape(name)+r'\b[\s\S]*?^endmodule\b',raw.decode(),re.M)
    if len(found)!=1:raise ValueError('Original module definition not unique: '+name)
    return found[0].encode()


def modules(name,b):
    if b.get('kind')in SPECS:return[SPECS[b['kind']][0]]
    if b.get('kind')in('group-stream','lookup'):return sorted(b['isolated_native_modules'])
    if b.get('concrete_hierarchy_modules'):return b['concrete_hierarchy_modules']
    if 'concrete_module'in b:return[b['concrete_module']]
    if 'service'in b:return[SERVICES[b['service']][1]]
    if name.startswith(('joint-attention','attention-ownership')):return['board1_context2048_attention']
    if name.startswith(('semantic-ingress','semantic-result')):return['board1_context2048_semantic_sequence','board1_context2048_semantic_datapath','board1_context2048_semantic_layer']
    if name.startswith('sequence-parent'):return['board1_context2048_semantic_sequence']
    if name.startswith(('projection-stream','projection-parent')):return['board1_fixed_group_projection_scale_job','board1_fixed_group_ddr_stream','board1_private_outstanding_delta']
    if name.startswith('semantic-scratch'):return['board1_context2048_semantic_datapath']
    if name.startswith('semantic-parent'):return['board1_context2048_semantic_datapath']
    if name.startswith('lut-protocol'):return['board1_context2048_semantic_datapath','board1_fixed_elementwise_lane_core',
        'board1_fixed_elementwise_product_compact_lane','board1_fixed_vector_normalizer']
    if name.startswith('shell-memory'):return['board1_context2048_token_shell']
    if name.startswith('assembled-cluster'):return['board1_clustered_projection_scale2','board1_projection_tile16']
    if 'cluster-ownership'in name or 'cluster-reply-ownership'in name:return['board1_clustered_projection_scale2','board1_projection_tile16']
    if name.startswith('projection-mac'):return['board1_projection_dsp_accumulator']
    if name.startswith('rms-rom'):return['board1_fixed_rmsnorm_rom']
    if name.startswith('exp-session'):return['board1_fixed_attention_exp_lut_sync']
    raise ValueError('Proof scope needs explicit module inventory: '+name)


def main():
    binder=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    hierarchy=json.loads((HERE/'HIERARCHY-BINDINGS.json').read_text())
    if not hierarchy['structural_binding_passed']:raise ValueError('Native hierarchy audit incomplete')
    package=HERE.parents[1]/'fpga-demo/public-release'
    native={v:binder.binding(package,v)for v in hierarchy['variants']}
    classes=hierarchy['instantiated_module_source_classes'];results={}
    for name in CASES:
        run=HERE/'runs'/name;inputs=json.loads((run/'INPUTS.json').read_text());b=inputs['binding']
        variants=set(native);rows={}
        for module in modules(name,b):
            if module not in classes:raise ValueError('Credited module is not instantiated: '+name+' '+module)
            originals=[]
            for filename,row in inputs['files'].items():
                if not filename.endswith('.sv')or filename=='wrapper.sv':continue
                if not(filename.startswith('production')or filename=='rom.sv'):continue
                raw=(run/filename).read_bytes()
                if binder.sha(raw)!=row['sha256']:raise ValueError('Original proof input changed')
                if (b.get('concrete_shell_and_semantic_model_clients')and module=='board1_context2048_token_machine_core'and
                    filename=='production-transport-production-core.sv'):
                    # This is the transport prerequisite's baseline core
                    # provenance. The active core is production-core.sv; only
                    # the identical queue/arbiter block transfers to seeded.
                    from audit_model_drain import block
                    if block(raw.decode())!=block((run/'production-core.sv').read_text()):
                        raise ValueError('Reference transport differs from active native core')
                    continue
                if re.search(r'^module\s+'+re.escape(module)+r'\b',raw.decode(),re.M):originals.append(body(raw,module))
            digests={binder.sha(raw)for raw in originals}
            if len(digests)!=1:raise ValueError('Missing or ambiguous frozen original module: '+name+' '+module)
            digest=digests.pop();eligible={};
            for cls in classes[module].values():
                for variant in cls['variants']:
                    _,root,bound=native[variant];path=cls['production_path'];raw=(root/path).read_bytes()
                    if binder.sha(raw)!=cls['source_sha256']or bound['distributed_inputs'][path]!=cls['source_sha256']:
                        raise ValueError('Native module source class changed')
                    if binder.sha(body(raw,module))==digest:
                        eligible[variant]=dict(production_path=path,source_sha256=cls['source_sha256'],
                            instances=cls['instances_by_variant'][variant],
                            native_defines_sha256=bound['distributed_inputs']['project/defines.v'])
            if not eligible:raise ValueError('Proof definition absent from current images: '+name+' '+module)
            rows[module]=dict(original_module_sha256=digest,variant_joins=eligible)
            variants.intersection_update(eligible)
        if not variants:raise ValueError('No actual design contains all proved modules: '+name)
        results[name]=dict(active_variant_source_joins=sorted(variants),modules=rows,
            proof_inputs_sha256=binder.sha((run/'INPUTS.json').read_bytes()))
    inactive=['board1_shared_projection_scale_engine','board1_fixed_vector_rne_shift_iterative','board0_exact_rne_div_signed64_iterative']
    if any(n in classes for n in inactive):raise ValueError('Inactive-example assumptions changed; review current scope')
    result=dict(instantiation_audit_passed=True,formal_composition_complete=False,
        proof_module_joins=results,inactive_distributed_modules_excluded=inactive,
        hierarchy_binding_sha256=binder.sha((HERE/'HIERARCHY-BINDINGS.json').read_bytes()),
        checker_sha256=binder.sha(Path(__file__).read_bytes()))
    (HERE/'PROOF-INSTANTIATION-BINDINGS.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(instantiation_audit_passed=True,credited_component_records=len(results),
        inactive_distributed_modules_excluded=len(inactive),formal_composition_complete=False)))


if __name__=='__main__':main()
