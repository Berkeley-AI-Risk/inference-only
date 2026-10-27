"""Source-bound composition of token control, fixed schedule and K/V use.

Component safety predicates quantify over unrestricted complete private
outputs. Joining actual signal expressions therefore introduces no caller or
payload oracle. This checker audits the interfaces of those universal facts;
it adds no numerical, cryptographic-hardness or whole-machine assertion count.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re

HERE=Path(__file__).resolve().parent
RTL='project/fpga/token_only_model0_ddr_board1/'
MACHINE=RTL+'context2048_token_machine2/rtl/'
SEMANTIC=RTL+'context2048_token_machine0/rtl/'


def sha(raw):return hashlib.sha256(raw).hexdigest()


def load(name,path):
    s=importlib.util.spec_from_file_location('_machine_access_'+name,path)
    m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m


def instance(source,module,name):
    # Parse complete nested named port expressions from this pinned source.
    source=re.sub(r'//[^\n]*','',source)
    pattern=r'^    '+re.escape(module)+r'\b\s+(?:#\([\s\S]*?\)\s+)?'+re.escape(name)+r'\s*\('
    matches=list(re.finditer(pattern,source,re.M))
    if len(matches)!=1:raise ValueError('Actual instance changed: '+name)
    cursor=matches[0].end();depth=1;start=cursor
    while depth:
        depth+=(source[cursor]=='(')-(source[cursor]==')');cursor+=1
    body=source[start:cursor-1];ports={};cursor=0
    while cursor<len(body):
        while cursor<len(body)and body[cursor]in' \t\r\n,':cursor+=1
        if cursor==len(body):break
        m=re.match(r'\.(\w+)\s*\(',body[cursor:])
        if not m:raise ValueError('Unexpected named connection syntax')
        port=m[1];cursor+=m.end();start=cursor;depth=1
        while depth:
            depth+=(body[cursor]=='(')-(body[cursor]==')');cursor+=1
        if port in ports:raise ValueError('Duplicate port')
        ports[port]=re.sub(r'\s+',' ',body[start:cursor-1]).strip()
    return ports


def same(a,pa,b,pb):
    if a[pa]!=b[pb]:raise ValueError('Actual interface expression differs: '+pa+' / '+pb)
    return dict(producer_port=pa,consumer_port=pb,actual_expression=a[pa])


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--package',type=Path,required=True)
    p.add_argument('--out',type=Path,required=True);args=p.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    common=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    package=common.model_package(args.package);prerequisites={}
    for name in('CONTROLLER-ACCESS-AUDIT.json','MODEL-ADDRESS-AUDIT.json','KV-HISTORY-CACHE-COMPOSITION-AUDIT.json',
            'SERVICE-CONSUMER-AUDIT.json','AUTH-BOOT-JOIN-AUDIT.json'):
        raw=(HERE/name).read_bytes();d=json.loads(raw)
        if not d.get('passed'):raise ValueError('A component prerequisite is incomplete')
        prerequisites[name]=dict(bytes=len(raw),sha256=sha(raw))
    greedy_path=HERE/'runs/current-control-source-query-audit-r1.json'
    greedy=json.loads(greedy_path.read_bytes())
    if not greedy['passed']or greedy['primary_assertions_proved']!=134 or greedy['assumption_cells']:
        raise ValueError('Current connected greedy token-controller theorem is incomplete')
    seeded=package/'formal/current-seeded-sampling/CURRENT-REPLAY.json'
    provider=load('seeded_provider',seeded.parent/'source_provider.py')
    contract=load('seeded_contract',seeded.parent/'completion_contract.py')
    source_binding=provider.source_binding();seeded_record=json.loads(seeded.read_bytes())
    contract.validate_completion(seeded_record,source_binding)
    if seeded_record['connected']['assertions']!=196 or not seeded_record['connected']['primary_passed']:
        raise ValueError('Current connected seeded primary theorem is incomplete')
    attention_joins=json.loads((HERE/'CURRENT-ATTENTION-SOURCE-JOIN-r2.json').read_bytes())
    if not attention_joins['passed']:raise ValueError('Current attention source joins incomplete')
    records=[]
    for variant in('baseline','kv-protected','encrypted-memory','seeded-sampling'):
        _,native,bound=common.binding(args.package,variant)
        text={k:(native/relative).read_text() for k,relative in(
            ('core',MACHINE+'board1_context2048_token_machine_core.sv'),
            ('shell',MACHINE+'board1_context2048_token_shell.sv'),
            ('layer',SEMANTIC+'board1_context2048_semantic_layer.sv'),
            ('sequence',SEMANTIC+'board1_context2048_semantic_sequence.sv'),
            ('datapath',SEMANTIC+'board1_context2048_semantic_datapath.sv'))}
        core_layer=instance(text['core'],'board1_context2048_semantic_layer','u_six_layers')
        core_shell=instance(text['core'],'board1_context2048_token_shell','u_token_shell')
        sequence=instance(text['layer'],'board1_context2048_semantic_sequence','u_sequence')
        datapath=instance(text['layer'],'board1_context2048_semantic_datapath','u_datapath')
        attention=instance(text['datapath'],'board1_context2048_attention','u_attention')
        cache=instance(text['datapath'],'board1_context2048_atomic_kv_typed','u_kv_cache')
        projection=instance(text['datapath'],'board1_fixed_group_projection_scale_job','u_projection')
        lookup=instance(text['datapath'],'board1_context2048_semantic_lookup','u_lookup')
        connections=[]
        for suffix in('clear','start_valid','start_ready','position','input_exponent','input_valid','input_ready',
                'input_index','input_mantissa','input_last','result_valid','result_ready','result_index',
                'result_mantissa','result_exponent','result_last','done_valid','done_ready'):
            shell_port='private_layer_'+suffix+('_o'if suffix not in('start_ready','input_ready','result_valid','result_index',
                'result_mantissa','result_exponent','result_last','done_valid')else'_i')
            layer_port=('clear_i'if suffix=='clear'else'fixed_position_i'if suffix=='position'else
                suffix+('_o'if suffix in('start_ready','input_ready','result_valid','result_index','result_mantissa','result_exponent','result_last','done_valid')else'_i'))
            # CLEAR comes from the same retained token shell output.
            connections.append(same(core_shell,shell_port,core_layer,layer_port))
        for port in core_layer:
            if port.startswith('private_head_'):
                shell_port=port[:-1]+('o'if port.endswith('_i')else'i')
                connections.append(same(core_shell,shell_port,core_layer,port))
        for p1,p2 in(('private_ingress_write_o','private_ingress_write_i'),('private_stage_valid_o','private_stage_valid_i'),
                ('private_stage_ready_i','private_stage_ready_o'),('private_stage_o','private_stage_i'),('private_layer_o','private_layer_i'),
                ('private_position_o','private_position_i'),('private_input_exponent_o','private_initial_exponent_i'),
                ('private_stage_done_i','private_stage_done_o'),('private_stage_fault_i','private_stage_fault_o')):
            connections.append(same(sequence,p1,datapath,p2))
        for p1,p2 in(('input_index_i','private_ingress_index_i'),('input_mantissa_i','private_ingress_mantissa_i')):
            connections.append(same(sequence,p1,datapath,p2))
        for port in('clk','rst_n','clear_i','model_lock_i'):connections.append(same(sequence,port,datapath,port))
        for p1,p2 in(('private_cache_request_valid_o','attention_req_valid_i'),('private_cache_request_kind_o','attention_req_kind_i'),
                ('private_cache_request_ready_i','attention_req_ready_o'),('private_cache_response_valid_i','attention_rsp_valid_o'),
                ('private_cache_response_ready_o','attention_rsp_ready_i'),('private_cache_response_key_vector_i','attention_rsp_key_vector_o'),
                ('private_cache_response_key_exponent_i','attention_rsp_key_exponent_o'),('private_cache_response_value_vector_i','attention_rsp_value_vector_o'),
                ('private_cache_response_value_exponent_i','attention_rsp_value_exponent_o'),('private_cache_response_fault_i','attention_rsp_fault_o'),
                ('clk','clk'),('rst_n','reset_n'),('clear_i','clear_i'),('model_lock_i','model_locked_i'),('upstream_fault_i','upstream_fault_i')):
            connections.append(same(attention,p1,cache,p2))
        if cache['attention_position_i']!="{1'b0, "+attention['private_cache_request_position_o']+'}'or cache['attention_kv_head_i']!="{1'b0, "+attention['private_cache_request_kv_head_o']+'}':
            raise ValueError('Typed attention request extension differs')
        if projection['fixed_layer_i']!='projection_layer'or projection['fixed_job_i']!='projection_job' or lookup['fixed_kind_i']!='lookup_kind':
            raise ValueError('Fixed private child descriptor connection differs')
        if core_layer['rst_n']!='child_reset_n'or core_layer['clk']!='clk'or core_layer['clear_i']!='layer_clear':
            raise ValueError('Actual child epoch/reset/clock differs')
        join=next(row for row in attention_joins['variants']if row['variant']==variant)
        for row in join['sources']:
            if Path(row['native']).read_bytes()!=Path(row['proof_copy']).read_bytes():raise ValueError('Attention source changed')
        protected=variant in('kv-protected','encrypted-memory')
        attention_run='current-attention34-r1'if protected else'current-baseline-attention34-r1'
        attention_audit='audit-current-attention34-r1'if protected else'audit-current-baseline-attention34-r1'
        att=json.loads((HERE/'runs'/attention_audit/'FINISHED.json').read_bytes())
        if not att['passed']or att['assertions']!=34 or att['queries_checked']!=72 or not att['byte_identical_elaboration']:
            raise ValueError('Actual attention capture/use theorem incomplete')
        records.append(dict(variant=variant,image_sha256=bound['image_sha256'],native_inventory_sha256=bound['native_inventory_sha256'],
            exact_actual_connections=connections,attention_run=attention_run,attention_assertions=34,
            source_hashes={key:sha(value.encode())for key,value in text.items()},
            typed_KV_guard_to_current_cache_to_attention_capture_use_composed=protected,
            public_token_control_primary_assertions=196 if variant=='seeded-sampling' else 134,
            private_services_have_no_public_raw_tensor_address_job_or_arithmetic_mode_port=True))
    receipt=dict(schema='native-token-through-fixed-schedule-and-protected-KV-use-composition-v1',passed=True,
        component_audits=prerequisites,current_greedy_control_audit_sha256=sha(greedy_path.read_bytes()),
        current_seeded_control_completion_sha256=sha(seeded.read_bytes()),runs=records,
        source_projection_and_component_queries_audited=True,imported_private_behavior_assumptions=[],
        overlap_counts_added=False,monolithic_whole_machine_numerical_refinement=False,
        scope='Source-bound composition of actual public token control, six-layer schedule, fixed job/operand/address routing, authenticated model service and protected K/V checked-copy/capture/use. The baseline and seeded images do not gain physical K/V integrity. Mathematical cryptographic hardness, arbitrary training-strategy impossibility, ASIC/bitstream equivalence, numerical transformer correctness and physical fault resistance are not proved.')
    (out/'FINISHED.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    (HERE/'MACHINE-ACCESS-COMPOSITION-AUDIT.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(passed=True,variants=4)))


if __name__=='__main__':main()
