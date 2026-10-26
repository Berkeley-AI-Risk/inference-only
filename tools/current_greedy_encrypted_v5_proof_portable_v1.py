"""Portable CFC association to the unchanged original V5 attention34 proof.

Only authenticated byte callbacks are used. The caller supplies the source-pinned
proof406781 check_queries function. The original V5 completion schema is checked
directly, without adapting it to baseline34 or adding assertions to other scopes.
"""
import hashlib
import json
from pathlib import PurePosixPath

BRIDGE = (13498, 'f2cf9f3bc20b18bde97a6681c717b8762b24ab3862293542f84c89a2fe1ef756')
COMPLETION = (6999, '9ae6ba22c6039800a5b9b816b0519b638973f0d54957c4871e57ff943f3dd716')
CANDIDATE = (61661, '33f3e98bba59bb1942f7f2245ea435c5ee3981df2cd295702e5d5fe84fdb4b8b')
MONITOR = '5df806a9c9563130c15e18c4ba7523e514183058b6a1bcfd31dd0c48b3e2f200'
DATAPATH = 'project/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_semantic_datapath.sv'
# Observed archived artifact pins frozen by this portable preparation, rather
# than invented fields in the original completion or fresh elaboration results.
ARCHIVED_ARTIFACTS = {
    'prove.ys': (802, '20aa0a7c4aa67ad467bfaf1e2095bd2e249e3ba315097faa4d341d725b7aa911'),
    'design.smt2': (1262545, '4c09ed35c5967dfd99eec6a3cbd1020b17558ac4212438123be63f256615b9e5'),
    'elaborated.json': (3215874, 'e0c70c03d9b155a5f685252b24198ca0105f92951961ca9426ec163871bbf44a'),
    'elaborated.il': (1144469, '854c8b3e7e5e3dd269b83f3b16152f5c40d64ddb5129c4bc9929dac2f694eb3d'),
}


def need(ok, message):
    if not ok:
        raise ValueError(message)


def identity(raw):
    return dict(bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest())


def pin2(row):
    return {key: row[key] for key in ('bytes', 'sha256')}


def exact(raw, wanted, label):
    need(identity(raw) == dict(bytes=wanted[0], sha256=wanted[1]), 'Exact actual ' + label + ' identity required')
    return json.loads(raw)


def child(root, name):
    p = PurePosixPath(name)
    need(type(name) is str and name and str(p) == name and not p.is_absolute()
         and '..' not in p.parts and '\\' not in name, 'Safe original archive member required')
    return str(PurePosixPath(root) / p)


def read_pin(reader, row):
    return reader.read(row['path'], row)


def scope(bridge, completion):
    """Pure native-schema scope checks, separate from immutable identity pins."""
    need(bridge['schema'] == 'encrypted-coordinate-v5-identical-attention-control-scope-bridge-v1'
         and completion['schema'] == 'protected-coordinate-v5-fresh-attention-completion-v1'
         and bridge['passed'] is True and completion['passed'] is True
         and bridge['assertions'] == completion['assertions'] == 34
         and bridge['queries'] == completion['queries'] == 72 and completion['unknowns'] == 0
         and completion['queries_per_solver'] == dict(z3=36, cvc5=36)
         and bridge['both_solvers_complete'] is True and completion['both_solvers_complete'] is True,
         'Original V5 34/72/zero-unknown scope differs')
    for key in ('hardware_access', 'numerical_attention_theorem', 'phase_observer_relational_theorem',
                'model_phase_observer_macro_defined_in_proof', 'concrete_accumulator_memory_proved'):
        need(bridge[key] is False and completion[key] is False, 'Attention proof overclaim: ' + key)
    for key in ('whole_encrypted_machine_theorem', 'encrypted_guard_or_siv_composition_theorem',
                'concrete_query_memory_proved', 'mapped_accumulator_memory_claim',
                'older_results_relabelled', 'solver_executed_by_bridge', 'model_or_native_executed_by_bridge'):
        need(bridge[key] is False, 'CFC bridge overclaim: ' + key)
    for key in ('whole_machine_refinement', 'aggregate_assertion_total_claimed', 'older_proof_relabelled'):
        need(completion[key] is False, 'Original V5 completion overclaim: ' + key)
    for key in ('query_memory_contents_abstracted', 'accumulator_memory_contents_abstracted'):
        need(bridge[key] is True and completion[key] is True, 'Original arbitrary memory boundary differs')
    need(bridge['retained_abstract_outputs'] == completion['retained_abstract_output_count'] == 27
         and len(completion['arbitrary_child_replies']) == 27
         and completion['observer'] == dict(selector_bits=6, production_signal_hits=[])
         and bridge['arbitrary_child_interfaces'] == 8
         and bridge['proof_source_package_members_verified'] == 13
         and bridge['prepared_source_files_rehashed'] == 20
         and bridge['real_prefix_summary_retained'] is True
         and bridge['no_attention_parameter_override_in_identical_production_instantiation'] is True
         and completion['private_coordinate_driver_isolated'] is True
         and completion['byte_identical_audit_reelaboration'] is True
         and completion['fresh_solver_execution'] is True
         and completion['no_guard_or_cache_solver_rerun'] is True,
         'Original V5 observer/source/boundary scope differs')


def validate_encrypted_v5_attention_bridge(reader, bridge, spec, native_inputs, *, query_recheck):
    need(callable(query_recheck), 'Caller must supply pinned proof406781 check_queries callback')
    need(reader.variant == 'encrypted-memory', 'Encrypted V5 source bridge required')
    origin = reader.data['roles']['source_scoped_proofs']
    need(exact(reader.read(origin), BRIDGE, 'CFC bridge') == bridge, 'Bridge detached from actual role')
    candidate_origin = reader.data['roles']['source_candidate']
    candidate = exact(reader.read(candidate_origin), CANDIDATE, 'encrypted V5 candidate')
    need(bridge['encrypted_candidate'] == reader.pin(candidate_origin), 'CFC bridge/source candidate differs')
    completion = exact(read_pin(reader, bridge['original_new_v5_coordinate_completion']), COMPLETION, 'original V5 completion')
    scope(bridge, completion)
    for old, key in [('plan', 'original_new_v5_coordinate_plan'), ('proof', 'original_new_v5_coordinate_proof'),
                     ('audit', 'original_new_v5_coordinate_audit'), ('execution', 'original_new_v5_coordinate_execution')]:
        need(completion[old] == bridge[key], 'Original V5 pointer differs: ' + old)
        read_pin(reader, bridge[key])
    plan = reader.json(completion['plan']['path'], completion['plan'])
    need(plan['assumptions'] == [] and plan['added_internal_cuts'] == []
         and plan['assertions'] == 34 and plan['queries_expected'] == 72
         and plan['model_phase_observer_macro_defined_in_proof'] is False
         and plan['older_results_inherited'] is False, 'Original V5 proof plan differs')
    original_candidate = reader.json(completion['source_candidate_receipt']['path'], completion['source_candidate_receipt'])
    need(completion['source_candidate_receipt'] == plan['candidate_receipt']
         and original_candidate['candidate'] == plan['candidate'], 'Original protected source candidate differs')
    reader.read(plan['native_plan']['path'], plan['native_plan'])
    proof_dir = str(PurePosixPath(completion['proof']['path']).parent)
    audit_dir = str(PurePosixPath(completion['audit']['path']).parent)
    need(spec == dict(proof_directory=proof_dir, audit_directory=audit_dir), 'Exact original V5 proof/audit directories required')
    for name, wanted in ARCHIVED_ARTIFACTS.items():
        need(identity(reader.read(child(proof_dir, name))) == dict(bytes=wanted[0], sha256=wanted[1]),
             'Frozen archived V5 source/query/observer artifact differs')
    need(bridge['proof_source_package_manifest'] == plan['source_package_manifest'], 'Original source package manifest differs')
    manifest = reader.json(plan['source_package_manifest']['path'], plan['source_package_manifest'])
    need(len(manifest['files']) == 13 and len(plan['prepared_files']) == 20, 'Original13/20 source census differs')
    for name, wanted in manifest['files'].items():
        reader.read(child(plan['source_package'], name), wanted)
    for name, wanted in plan['prepared_files'].items():
        reader.read(child(proof_dir, name), wanted)
    joins = bridge['source_joins']
    need(len(joins) == 6 and set(joins) == set(plan['actual_production']) == set(completion['actual_source_origins']),
         'Exact six isolated source inputs required')
    for name, row in joins.items():
        need(name in native_inputs and row['byte_identical'] is True
             and row['protected'] == plan['actual_production'][name] == completion['actual_source_origins'][name]
             and row['protected']['path'] == child(original_candidate['candidate'], name)
             and row['encrypted']['path'] == child(candidate['source_root'], name)
             and row['exact_proof_package_archive']['path'] == child(plan['source_package'], 'hardware/' + name),
             'Original/encrypted/archive source pointer differs')
        raws = [read_pin(reader, row[key]) for key in ('protected', 'encrypted', 'exact_proof_package_archive')]
        need(all(raw == raws[0] for raw in raws) and identity(raws[0]) == pin2(native_inputs[name]),
             'Actual selected CFC native source differs from original proof')
    datapath = bridge['identical_datapath_instantiation']
    need(DATAPATH in native_inputs and datapath['path'] == child(candidate['source_root'], DATAPATH),
         'Actual CFC attention instantiation source required')
    raw = read_pin(reader, datapath)
    need(identity(raw) == pin2(native_inputs[DATAPATH])
         and reader.read(child(original_candidate['candidate'], DATAPATH), pin2(datapath)) == raw
         and raw.count(b'board1_context2048_attention u_attention (') == 1,
         'Original/CFC production attention instantiation differs')
    script = reader.read(child(proof_dir, 'prove.ys')).decode()
    need(script.splitlines()[0].startswith('read_verilog -formal -sv -nosynthesis -D SYNTHESIS ')
         and 'BOARD1_ATTENTION_COORDINATE_PHASE_CHECK' not in script, 'Original native-view proof macro differs')
    actual = query_recheck(reader, proof_dir, 34)
    inputs = actual.pop('inputs')
    need(inputs['source_origins'] == {'hardware/' + name: native_inputs[name]['sha256'] for name in joins}
         and len(inputs['abstract_children']) == 8
         and inputs['files']['attention_monitor.inc.sv']['sha256'] == MONITOR
         and inputs['private_coordinate_driver_isolated'] is True
         and inputs['real_prefix_summary_retained'] is True
         and inputs['timeout_reduced'] is False,
         'Original V5 query/source/monitor boundaries differ')
    audit = reader.json(completion['audit']['path'], completion['audit'])
    need(actual['passed'] is True and (actual['assertions'], actual['queries'], actual['unknowns']) == (34, 72, 0)
         and actual['observer'] == completion['observer'] == audit['observers']
         and actual['arbitrary_child_replies'] == completion['arbitrary_child_replies'] == audit['arbitrary_child_replies']
         and len(actual['arbitrary_child_replies']) == 27
         and audit['passed'] is True and audit['assertions'] == 34 and audit['queries_checked'] == 72
         and audit['byte_identical_elaboration'] is True and audit['whole_machine_refinement'] is False,
         'Original cached proof/audit/count/observer result differs')
    for name in ('elaborated.json', 'elaborated.il', 'design.smt2'):
        need(reader.read(child(audit_dir, name)) == reader.read(child(proof_dir, name)), 'Cached audit/proof identity differs')
    execution = reader.json(completion['execution']['path'], completion['execution'])
    need(execution['passed'] is True and execution['hardware_access'] is False
         and execution['plan'] == completion['plan'] and len(execution['executions']) == len(plan['steps']) == 2,
         'Original proof/audit execution differs')
    for operation, step in zip(execution['executions'], plan['steps']):
        need(operation['exit_code'] == 0 and operation['argv'] == step['argv']
             and operation['name'] == step['name'] and read_pin(reader, operation['stderr']) == b'',
             'Original proof/audit execution argv or error differs')
        read_pin(reader, operation['stdout'])
    return dict(passed=True, selected_source_epoch='encrypted-v5-coordinate',
        original_proof_epoch='protected-v5-coordinate', isolated_attention_inputs_joined=6,
        original_assertions_rechecked=34, original_queries_reparsed=72, unknowns=0,
        additional_assertions_or_queries_claimed=0, counts_nonadditive=True,
        original_package_members_rehashed=13, original_prepared_sources_rehashed=20,
        archived_artifact_pins_observed_by_portable_preparation=True,
        archived_queries_rebuilt_and_answers_reparsed=True,
        cached_elaboration_observer_and_arbitrary_replies_rechecked=True,
        retained_complete_arbitrary_child_outputs=27, selector_bits=6,
        solver_model_native_elaboration_or_hardware_executed=False,
        native_or_board_authority=False, numerical_attention_or_concrete_memory_theorem=False,
        encrypted_guard_SIV_or_whole_machine_theorem=False, training_capacity_calculated=False)
