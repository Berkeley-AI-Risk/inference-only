"""Portable exact V8 source bridge to the original V6 attention proof.

The caller supplies the source-pinned proof406781 validate_attention_proof
callback. Only authenticated reader callbacks are used; no original-path IO,
solver, elaborator, model, native or hardware operation is available here.
Projection arithmetic remains outside the reused attention-control scope.
"""
import hashlib
import json
from pathlib import PurePosixPath

BRIDGE=(19793,'e8305992f202e546ac32c630dff6da5c8469da60b8684301b701b8faa535f1a4')
ORIGINAL=(9109,'75b0eadd31e1f4b534f7425e4316479223a3d6362cac2d8764a68a08fba5d99a')
CANDIDATE=(71108,'c0929b466a40c3541d0b5ad797f62430e8802d405ada9afb1b1e23bb0dc43951')
FINITE=(3187,'581580bf67e9af0ed2921e90a3180b837f0f375c9747f622fedd29499cb2f46c')
DATAPATH='project/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_semantic_datapath.sv'

def need(ok,msg):
    if not ok:raise ValueError(msg)
def identity(raw):return dict(bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest())
def pin2(row):return {k:row[k]for k in ('bytes','sha256')}
def exact(raw,want,label):
    need(identity(raw)==dict(bytes=want[0],sha256=want[1]),'Exact actual '+label+' identity required')
    return json.loads(raw)
def child(root,name):
    p=PurePosixPath(name)
    need(type(name)is str and name and str(p)==name and not p.is_absolute()and '..'not in p.parts
         and '\\'not in name,'Safe original archive member required')
    return str(PurePosixPath(root)/p)
def read_pin(reader,row):return reader.read(row['path'],row)

def bridge_scope(bridge):
    """Pure scope contract, independently testable without proof replay."""
    need(bridge['schema']=='protected-v8-unchanged-v6-attention-control-scope-association-v1'
         and bridge['passed']is True and (bridge['assertions'],bridge['queries'])==(66,136)
         and bridge['additional_assertions_or_queries_claimed']==0
         and bridge['query_and_accumulator_memory_contents_abstracted']is True
         and bridge['retained_abstract_output_count']==len(bridge['arbitrary_child_replies'])==28,
         'Exact original66/136 scoped-source association required')
    for key in ('solver_or_auditor_executed','model_or_native_executed','hardware_access',
                'inherited_whole_image_qualification','projection_arithmetic_covered_by_this_proof',
                'whole_machine_refinement','numerical_attention_theorem','concrete_memory_theorem',
                'guard_cache_SIV_composition_theorem','phase_observer_relational_theorem',
                'model_phase_observer_macro_defined_in_proof','sha_arithmetic_covered_by_this_proof'):
        need(bridge[key]is False,'V8 attention bridge overclaims '+key)
    need((bridge['original_proof_package_members_rehashed'],bridge['original_audit_package_members_rehashed'],
          bridge['original_prepared_sources_rehashed'],bridge['original_solver_query_log_files_rehashed'])==(13,13,20,234),
         'Original archive/prepared/query census differs')

def validate_v8_attention_bridge(reader,bridge,spec,native_inputs,*,proof_recheck):
    need(callable(proof_recheck),'Caller must supply reviewed proof406781 callback')
    need(reader.variant=='kv-protected','Protected-only V8 source bridge required')
    origin=reader.data['roles']['source_scoped_proofs']
    need(exact(reader.read(origin),BRIDGE,'V8 bridge')==bridge,'Bridge detached from actual selected role')
    bridge_scope(bridge)
    candidate_origin=reader.data['roles']['source_candidate']
    candidate=exact(reader.read(candidate_origin),CANDIDATE,'V8 candidate')
    need(bridge['source_candidate']==reader.pin(candidate_origin),'Bridge candidate pointer differs')
    finite=exact(read_pin(reader,bridge['projection_finite_source_completion']),FINITE,'projection finite receipt')
    need(finite['passed']is True and finite['hardware_access']is False
         and bridge['projection_finite_source_completion']==candidate['projection_finite_source_completion']
         and bridge['projection_fourway_sources']==candidate['projection_fourway_sources'],
         'Separate changed-projection evidence/source association differs')
    sha=candidate['sha_direct_add_source'];sha_finite=candidate['sha_direct_add_finite_source_completion']
    need(bridge['sha_direct_add_source']==sha and bridge['sha_direct_add_finite_source_completion']==sha_finite
         and sha['path']==child(candidate['candidate'],'project/sha.sv')
         and 'project/sha.sv' in native_inputs
         and pin2(sha)==dict(bytes=29648,sha256='a6fc9c042784f9d48731acafcbb3c6366a5746c458fa6aa9abe1aac59c25df92')
         and identity(read_pin(reader,sha))==pin2(native_inputs['project/sha.sv'])
         and sha_finite['sha256']=='567a96144bd5e5244e599dae5ea9b4142da298c08cdaa49202e385cd14737f17',
         'Changed V8 SHA must remain separately source/component bound')
    component=reader.json(sha_finite['path'],sha_finite)
    need(component['passed']is True and component['native_primitive_finite_scope_only']is True
         and component['whole_machine_claim']is False and component['source_compressor_REGISTER_RESULT']==0
         and candidate['sha_model_native_macro_elaboration_identical']is False,
         'Separate R5 source scope cannot become an attention or macro-equivalence theorem')
    original=exact(read_pin(reader,bridge['original_v6_completion']),ORIGINAL,'original V6 completion')
    for old,key in [('plan','original_v6_plan'),('proof','original_v6_proof'),('raw_audit','original_v6_raw_audit'),
                    ('audit_shape_fix_plan','original_v6_shape_fix_plan'),('audit_only_execution','original_v6_audit_only_execution')]:
        need(original[old]==bridge[key],'Original V6 receipt pointer differs: '+old)
        read_pin(reader,bridge[key])
    plan=reader.json(bridge['original_v6_plan']['path'],bridge['original_v6_plan'])
    shape=reader.json(bridge['original_v6_shape_fix_plan']['path'],bridge['original_v6_shape_fix_plan'])
    proof_dir=str(PurePosixPath(bridge['original_v6_proof']['path']).parent)
    for key,record in [('original_proof_package_manifest',plan),('original_audit_package_manifest',shape)]:
        row=bridge[key];need(row==record['source_package_manifest'],'Original package manifest pointer differs')
        manifest=reader.json(row['path'],row)
        need(len(manifest['files'])==13,'Original13 package inputs required')
        for name,wanted in manifest['files'].items():reader.read(child(record['source_package'],name),wanted)
    need(len(plan['prepared_files'])==20 and len(shape['all_original_proof_files'])==234,'Original prepared/rawquery census differs')
    for name,wanted in plan['prepared_files'].items():reader.read(child(proof_dir,name),wanted)
    for name,wanted in shape['all_original_proof_files'].items():reader.read(child(proof_dir,name),wanted)
    joins=bridge['source_joins']
    need(len(joins)==6 and set(joins)==set(plan['actual_production'])==set(original['actual_source_origins']),
         'Exact six isolated actual attention inputs required')
    for name,row in joins.items():
        need(name in native_inputs and row['byte_identical']is True
             and row['original_v6']==original['actual_source_origins'][name]
             and row['selected_v8']['path']==child(candidate['candidate'],name)
             and row['original_proof_archive']['path']==child(plan['source_package'],'hardware/'+name)
             and row['original_audit_archive']['path']==child(shape['source_package'],'hardware/'+name),
             'Original/current/archive source paths differ')
        raws=[read_pin(reader,row[k])for k in ('original_v6','selected_v8','original_proof_archive','original_audit_archive')]
        need(all(data==raws[0]for data in raws)and identity(raws[0])==pin2(native_inputs[name]),
             'Selected native attention source differs from original proof scope')
    datapath=bridge['identical_production_datapath_instantiation']
    need(DATAPATH in native_inputs and datapath['path']==child(candidate['candidate'],DATAPATH),
         'Actual V8 attention instantiation source required')
    raw=read_pin(reader,datapath)
    old_root=next(iter(joins.values()))['original_v6']['path'].split('/project/')[0]
    need(identity(raw)==pin2(native_inputs[DATAPATH])
         and reader.read(child(old_root,DATAPATH),pin2(datapath))==raw
         and raw.count(b'board1_context2048_attention u_attention (')==1,
         'Production attention instantiation or parameters changed')
    actual=proof_recheck(reader,original,spec['v6_proof'],native_inputs)
    need(actual['passed']is True and (actual['assertions'],actual['queries'],actual['unknowns'])==(66,136,0)
         and actual['arbitrary_child_replies']==bridge['arbitrary_child_replies']
         and actual['fresh_solver_or_elaboration_executed']is False,
         'Original scoped proof callback result differs')
    return dict(passed=True,selected_source_epoch='v8-sha-direct-add',original_proof_epoch='v6-four-lane-coordinate',
        isolated_attention_inputs_joined=6,original_assertions_rechecked=66,original_queries_reparsed=136,
        additional_assertions_or_queries_claimed=0,original_package_members_rehashed=26,
        original_prepared_sources_rehashed=20,original_raw_proof_files_rehashed=234,
        changed_projection_finite_receipt_pinned_separate_from_attention=True,
        changed_SHA_finite_receipt_pinned_separate_from_attention=True,SHA_arithmetic_theorem=False,
        solver_model_native_or_elaboration_executed=False,projection_arithmetic_theorem=False,
        whole_machine_or_numerical_or_memory_or_composition_theorem=False,native_or_board_authority=False,
        counts_nonadditive=True)
