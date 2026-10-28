"""Audit the connected core barrier against native sources and parameters."""
import argparse
import json
from pathlib import Path
import re
import subprocess

from record_progress import audit, sha
from run_attention_ownership import HERE
from run_projection_relational import instance_con
from audit_connected_drain import GROUP, EMBED, SHELL, PROJECTION, header


CORE='board1_context2048_token_machine_core'
EDGES=[(CORE,'board1_context2048_token_shell','u_token_shell'),
    (CORE,'board1_context2048_semantic_layer','u_six_layers'),
    ('board1_context2048_semantic_layer','board1_context2048_semantic_sequence','u_sequence'),
    ('board1_context2048_semantic_layer','board1_context2048_semantic_datapath','u_datapath'),
    ('board1_context2048_semantic_datapath','board1_fixed_group_projection_scale_job','u_projection'),
    ('board1_context2048_semantic_datapath','board1_context2048_semantic_lookup','u_lookup'),
    (CORE,'board1_fixed_private_ddr_arbiter','u_private_ddr_arbiter'),SHELL,EMBED,PROJECTION]+GROUP+[
    (CORE,'board1_ddr_request_fifo2','u_'+role+'_model_'+kind+'_queue')
    for role in('shell','layer')for kind in('request','response')]


def original_name(name,modules):
    value=modules[name].get('attributes',{}).get('hdlname')
    return value.split()[-1]if value else name.rsplit('\\',1)[-1]


def instance_parameters(text,module,instance):
    found=[]
    for match in re.finditer(r'\b'+re.escape(module)+r'\s+',text):
        cursor=match.end();start=cursor
        if text[cursor]=='#':
            opening=text.index('(',cursor);cursor=opening+1;level=1
            while level:level+=(text[cursor]=='(')-(text[cursor]==')');cursor+=1
        after=re.match(r'\s*(u_\w+)\s*\(',text[cursor:])
        if after and after[1]==instance:found.append(re.sub(r'\s+','',text[start:cursor]))
    if len(found)!=1:raise ValueError('Native parameter header not unique: '+instance)
    return found[0]


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--run',default='core-model-drain-r4')
    ap.add_argument('--out',type=Path,required=True);args=ap.parse_args()
    run=HERE/'runs'/args.run;out=args.out.resolve();out.mkdir(parents=True,exist_ok=False);manifest={}
    def pin(path,digest=None):
        raw=path.read_bytes();h=sha(raw)
        if digest is not None and h!=digest:raise ValueError('Changed source artifact: '+str(path))
        manifest[str(path.resolve())]=h;return raw
    receipt=audit(args.run,'actual connected core model-read drain barrier')
    if receipt['status']!='proved_component':raise ValueError('Core proof is not completely qualified')
    inp=json.loads(pin(run/'INPUTS.json'));pin(run/'FINISHED.json')
    if inp['assumption_cells']or inp['binding']['initial_hard_reset']or inp['changed_production_parameters']:
        raise ValueError('Unexpected assumptions/reset/parameters')
    originals={};compiled={}
    for filename,row in inp['files'].items():
        raw=pin(run/filename,row['sha256'])
        if not filename.endswith('.sv')or filename.endswith('.inc.sv'):continue
        if filename=='production-transport-production-core.sv':
            from audit_model_drain import block
            if block(raw.decode())!=block((run/'production-core.sv').read_text()):
                raise ValueError('Transport reference differs from active core')
            continue
        target=originals if filename.startswith('production')else compiled if filename in inp['compile_sources']else None
        if target is not None:
            for match in re.finditer(r'^module\s+(\w+)\b[\s\S]*?^endmodule\b',raw.decode(),re.M):
                if match[1]in target and target[match[1]]!=match[0]:raise ValueError('Conflicting module body')
                target[match[1]]=match[0]
    connections=[]
    for parent,child,instance in EDGES:
        native=instance_con(originals[parent],child,instance);actual=instance_con(compiled[parent],child,instance)
        if {n:v for n,v in actual.items()if not n.startswith('f_')}!=native:
            raise ValueError('Functional core/reader connection changed: '+instance)
        if instance_parameters(originals[parent],child,instance)!=instance_parameters(compiled[parent],child,instance):
            raise ValueError('Native instance parameter expression changed: '+instance)
        if any(r.get('instance')==instance and r.get('module')==child for r in inp['internal_cuts']):
            raise ValueError('A whole connected reader response remains cut')
        connections.append(dict(parent=parent,child=child,instance=instance,ports=native))
    read_cuts=[r for r in inp['internal_cuts']if r.get('kind')=='unrestricted_registered_RAM_read_payload']
    if len(read_cuts)!=4:raise ValueError('Unexpected registered data abstraction inventory')
    for row in read_cuts:
        original=originals[row['module']];model=compiled[row['module']]
        before=row['source_statement'];after=row['native_capture']+' <= '+row['port']+';'
        if original.count(before)!=1 or model.count(after)!=1 or before in model or not row['control_and_capture_clock_retained']or row['assumptions']:
            raise ValueError('Data-only RAM read abstraction differs')
        # Compare the complete enclosing native capture block, changing only
        # that RHS. This verifies enables and posedge capture/hold semantics.
        start=original.rfind('always',0,original.index(before));stop=original.index('\n    end',original.index(before))+8
        native_block=original[start:stop]
        for other in read_cuts:native_block=native_block.replace(other['source_statement'],other['native_capture']+' <= '+other['port']+';')
        if native_block not in model:raise ValueError('Native RAM capture control/clock changed')
    bindings_raw=(HERE/'PROOF-INSTANTIATION-BINDINGS.json').read_bytes()
    (out/'source-instantiations.json').write_bytes(bindings_raw);pin(out/'source-instantiations.json')
    joins=json.loads(bindings_raw)['proof_module_joins'][args.run];controlled=set(inp['binding']['concrete_hierarchy_modules'])
    for module in controlled:
        if sha(originals[module].encode())!=joins['modules'][module]['original_module_sha256']:
            raise ValueError('Original core module not bound to current native source')
    # Re-elaborate the exact frozen proof model, without flattening, so every
    # concrete instance's actual parameter values can be checked against the
    # production hierarchy rather than inferred from a generic default.
    replay=out/'parameter-replay';replay.mkdir()
    for filename in inp['compile_sources']:(replay/filename).write_bytes((run/filename).read_bytes())
    recipe='read_verilog -formal -sv -nosynthesis -D SYNTHESIS -defer '+' '.join(inp['compile_sources'])+'\nhierarchy -check -top '+inp['top']+'\nproc\nopt_clean\nwrite_json hierarchy.json\n'
    (replay/'replay.ys').write_text(recipe)
    with(replay/'yosys.log').open('w')as log:cp=subprocess.run(['yosys','-Q','replay.ys'],cwd=replay,stdout=log,stderr=subprocess.STDOUT,timeout=30)
    if cp.returncode:raise ValueError('Protocol parameter replay failed')
    graph=json.loads(pin(replay/'hierarchy.json'))['modules'];pin(replay/'replay.ys');pin(replay/'yosys.log')
    root=graph[inp['top']]['cells']['u_native']['type'];instances={}
    def visit(module,path):
        base=original_name(module,graph)
        if base not in controlled:return
        instances[path]=dict(module=base,parameters=graph[module].get('parameter_default_values',{}))
        for name,cell in graph[module]['cells'].items():
            if cell['type']in graph:visit(cell['type'],path+'/'+name if path else name)
    visit(root,'')
    hierarchy=json.loads(pin(HERE/'HIERARCHY-BINDINGS.json'));variants={}
    for variant in joins['active_variant_source_joins']:
        entry=hierarchy['variants'][variant];folder=HERE/'runs'/entry['census_run']
        census=json.loads(pin(folder/'CENSUS.json',entry['census_sha256']));native_graph=json.loads(pin(folder/'hierarchy.json'))['modules']
        roots=[r for r in census['instances']if r['original_module']==CORE]
        if len(roots)!=1:raise ValueError('Native core instance not unique')
        root_path=roots[0]['path'];native_instances={r['path']:r for r in census['instances']};checked={}
        for relative,row in instances.items():
            path=root_path+('/'+relative if relative else'')
            if path not in native_instances or native_instances[path]['original_module']!=row['module']:
                raise ValueError('Concrete protocol instance not at the native path: '+path)
            target=native_graph[native_instances[path]['module']].get('parameter_default_values',{})
            if target!=row['parameters']:raise ValueError('Actual native parameters differ at '+path)
            checked[relative]=row
        variants[variant]=dict(protocol_instance_parameters=checked,image_sha256=entry['image_sha256'])
    checker=out/'checker.py';checker.write_bytes(Path(__file__).read_bytes());pin(checker)
    result=dict(core_model_read_barrier_source_join_passed=True,qualified_receipt=receipt,
        native_functional_edges=connections,current_variant_parameters=variants,protocol_instances=len(instances),
        registered_RAM_data_overapproximations=read_cuts,artifact_manifest=manifest,
        reference_only_core_source='production-transport-production-core.sv; its transport block equals the active production-core.sv exactly.',
        typed_KV_and_outer_transport_composed=False,numerical_memory_reply_contracts_composed=False,
        whole_device_session_theorem=False,
        scope='Exact core, layer/sequence, model-read client and queue functional ports and actual elaborated production parameters. Only declared data/numerical/service boundaries remain; every real RAM read stream is included by the unrestricted data overapproximation.')
    (out/'FINISHED.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(core_model_read_barrier_source_join_passed=True,variants=len(variants),protocol_instances=len(instances),whole_device_session_theorem=False)))


if __name__=='__main__':main()
