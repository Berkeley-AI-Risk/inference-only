"""Join exact native model-read edges to the completed connected drain proofs."""
import argparse
import json
from pathlib import Path
import re

from record_progress import audit, sha
from run_attention_ownership import HERE
from run_projection_relational import instance_con
from audit_proof_instantiations import body


GROUP=[('board1_fixed_group_ddr_stream','board1_private_outstanding_delta','u_outstanding_delta'),
    ('board1_fixed_group_ddr_stream','board1_fixed_projection_metadata_reader','u_metadata_reader'),
    ('board1_fixed_group_ddr_stream','board1_private_ddr256_to_w640','u_width_adapter'),
    ('board1_fixed_group_ddr_stream','board1_private_weight_beat_register','u_weight_beat_register')]
EMBED=('board1_fixed_embedding_lookup','board1_fixed_group_ddr_stream','u_tied_group_reader')
SHELL=('board1_context2048_token_shell','board1_fixed_embedding_lookup','u_fixed_embedding')
PROJECTION=('board1_fixed_group_projection_scale_job','board1_fixed_group_ddr_stream','u_group_stream')
CASES={
    'embedding-drain-r1':[EMBED]+GROUP,
    'projection-drain-r2':[PROJECTION]+GROUP,
    'shell-drain-r3':[SHELL,EMBED]+GROUP,
    'seeded-shell-drain-r1':[SHELL,EMBED]+GROUP,
    'connected-semantic-drain-r1':[
        ('board1_context2048_semantic_datapath','board1_fixed_group_projection_scale_job','u_projection'),
        ('board1_context2048_semantic_datapath','board1_context2048_semantic_lookup','u_lookup'),PROJECTION]+GROUP}


def header(text,module,instance):
    # These concrete production instance headers have no nested function call
    # in the parameter list. Preserve parameter values separately from ports.
    matches=re.findall(r'\b'+re.escape(module)+r'\s*(.*?)\b'+re.escape(instance)+r'\s*\(',text,re.S)
    if len(matches)!=1:raise ValueError('Native instance header is ambiguous')
    return re.sub(r'\s+','',matches[0])


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--out',type=Path,required=True)
    args=ap.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    joins=json.loads((HERE/'PROOF-INSTANTIATION-BINDINGS.json').read_text())
    snapshot=out/'source-instantiations.json';snapshot.write_bytes((HERE/'PROOF-INSTANTIATION-BINDINGS.json').read_bytes())
    manifest={str(snapshot):sha(snapshot.read_bytes())};results={}
    for name,edges in CASES.items():
        run=HERE/'runs'/name;receipt=audit(name,'connected model-read drain')
        if receipt['status']!='proved_component':raise ValueError('Connected proof not closed')
        inp=json.loads((run/'INPUTS.json').read_text())
        if inp['assumption_cells']or inp['binding']['initial_hard_reset']or inp['changed_production_parameters']:
            raise ValueError('Unexpected assumptions/reset/parameters')
        originals={};instrumented={}
        for filename,row in inp['files'].items():
            path=run/filename;raw=path.read_bytes()
            if sha(raw)!=row['sha256']:raise ValueError('Changed proof input')
            manifest[str(path.resolve())]=row['sha256']
            if not filename.endswith('.sv')or filename.endswith('.inc.sv'):continue
            target=originals if filename.startswith('production')else instrumented if filename in inp['compile_sources']else None
            if target is None:continue
            for match in re.finditer(r'^module\s+(\w+)\b[\s\S]*?^endmodule\b',raw.decode(),re.M):
                if match[1]in target and target[match[1]]!=match[0]:raise ValueError('Conflicting module body')
                target[match[1]]=match[0]
        connected=[]
        for parent,child,instance in edges:
            if parent not in originals or child not in originals or parent not in instrumented or child not in instrumented:
                raise ValueError('Missing actual connected module')
            original=instance_con(originals[parent],child,instance)
            actual=instance_con(instrumented[parent],child,instance)
            if {n:v for n,v in actual.items()if not n.startswith('f_')}!=original:
                raise ValueError('Functional child port differs: '+instance)
            if header(originals[parent],child,instance)!=header(instrumented[parent],child,instance):
                raise ValueError('Functional child parameters differ')
            if any(r.get('instance')==instance and r.get('module')==child for r in inp['internal_cuts']):
                raise ValueError('A complete connected reply is still cut')
            connected.append(dict(parent=parent,child=child,instance=instance,
                actual_ports=original,parameter_header=header(originals[parent],child,instance),
                original_parent_sha256=sha(originals[parent].encode()),original_child_sha256=sha(originals[child].encode())))
        for module in inp['binding']['concrete_hierarchy_modules']:
            if module not in originals:raise ValueError('Concrete source module missing')
            expected=joins['proof_module_joins'][name]['modules'][module]['original_module_sha256']
            if sha(originals[module].encode())!=expected:raise ValueError('Current native source binding differs')
        for filename in('INPUTS.json','FINISHED.json'):
            path=run/filename;manifest[str(path.resolve())]=sha(path.read_bytes())
        results[name]=dict(receipt=receipt,edges=connected,
            active_variants=joins['proof_module_joins'][name]['active_variant_source_joins'],
            numerical_and_other_service_seams=inp['internal_cuts'])
    checker=out/'checker.py';checker.write_bytes(Path(__file__).read_bytes());manifest[str(checker)]=sha(checker.read_bytes())
    result=dict(connected_model_read_source_joins_passed=True,cases=results,artifact_manifest=manifest,
        core_transport_epoch_composition_complete=False,whole_device_session_theorem=False,
        remaining=['Common core/client transport history and public completed-CLEAR barrier.',
            'Typed K/V/outer transport, conditional numerical/reply seams and complete mutable-state signoff.'])
    (out/'FINISHED.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(connected_model_read_source_joins_passed=True,cases=len(results),whole_device_session_theorem=False)))


if __name__=='__main__':main()
