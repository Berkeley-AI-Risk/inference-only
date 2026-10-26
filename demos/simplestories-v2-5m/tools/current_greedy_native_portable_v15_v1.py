"""Byte-only selected-native/source/finite-ROM role joins with the selected exact V15 source profile.

Raw legacy field names saying 'modules' are preserved. Counts64/66/71 below
refer to compiled production source entries, not HDL definitions or instances.
Licensed omitted inputs retain exact declared hashes; no omitted source is
silently treated as having been rehashed. No native or finite tool is run.
"""
import hashlib
import json
import math
from pathlib import PurePosixPath
import re

EPOCHS = {
    'protected-v15-compact-prefix':dict(variant='kv-protected',inputs=93,compiled=66,
        candidate_sha256='a49d5ab7f1e6f024effd53ce4258a7278f3f2d94bd71bef2a0a11a5de109176b',
        source_join_schema='greedy-selected-v15-compact-prefix-actual-native-model-source-join-v1',
        policy_schema='root-greedy-sram-selection-v15-compact-prefix',guard_sha256='db408994786bc20ceec2114436015923f5d39106f1bf41d00b8f92627e19168d',
        allow_closed_native_validation=True,observed_image_sha256='90ac68150d0c297b666bc1963d05e32d1d2d0d7d69706593e58d48d5ab2e79e2'),
    'protected-v9-dense-sha': dict(variant='kv-protected', inputs=93, compiled=66,
        candidate_sha256='e2f8ca8e8d0414310ea99272922f3ac11659adfc3c676df9bddec5fcc8c59151',
        source_join_schema='greedy-selected-v9-dense-sha-actual-native-model-source-join-v1',
        policy_schema='root-greedy-sram-selection-v9-dense-sha',
        guard_sha256='65aa9c73d990559111832a4fdcb517aad729369bc5e7cca74cd712210bdbe1ff',
        allow_closed_native_validation=True, observed_image_sha256=None),
    # Source preparation for actual closed-record validation only; no image
    # exists merely because this epoch has a validation implementation.
    'protected-v8-sha-direct-add': dict(variant='kv-protected', inputs=93, compiled=66,
        candidate_sha256='c0929b466a40c3541d0b5ad797f62430e8802d405ada9afb1b1e23bb0dc43951',
        source_join_schema='greedy-selected-v8-sha-direct-add-actual-native-model-source-join-v1',
        policy_schema='root-greedy-sram-selection-v8-sha-direct-add',
        guard_sha256='9e0a560e69b8711d527b09d5bd0109c48a746233588e581ed5b2bb37004af723',
        allow_closed_native_validation=True, observed_image_sha256=None),
    'baseline-v1': dict(variant='baseline', inputs=90, compiled=64,
        candidate_sha256='f22f7f4d53e8b94b591c3174e67e01cd154cf1c90d5848db4b6b348df0e52122',
        source_join_schema='greedy-selected-v2-actual-native-model-source-join-v1',
        policy_schema='root-greedy-sram-selection-v2',
        guard_sha256='72685488f91e49de951cc15902030cc0e60dff36837e46ef08d48b5d3207c2a5',
        allow_closed_native_validation=True),
    'encrypted-v5-coordinate': dict(variant='encrypted-memory', inputs=100, compiled=71,
        candidate_sha256='33f3e98bba59bb1942f7f2245ea435c5ee3981df2cd295702e5d5fe84fdb4b8b',
        source_join_schema='greedy-selected-v5-coordinate-actual-native-model-source-join-v1',
        policy_schema='root-greedy-sram-selection-v5-coordinate',
        guard_sha256='1230d7f193f47e0a1aaf734fcb84c00cee859595295cfc4ba33175e64f2788ce',
        allow_closed_native_validation=True),
    # This is a MODEL/SOURCE epoch only. All three native attempts failed.
    # A new protected source epoch requires a separate explicit registry entry.
    'protected-v6-four-lane-coordinate': dict(variant='kv-protected', inputs=93, compiled=66,
        candidate_sha256='b90f447d820a48a65ea71616875fdf241ba4637e0a5131769721eab87d84a404',
        source_join_schema='greedy-selected-v6-four-lane-coordinate-actual-native-model-source-join-v1',
        policy_schema='root-greedy-sram-selection-v6-four-lane-coordinate',
        guard_sha256='3f4bd59c9c3aa36db3a557223b788296b57b8a0063890df71b6108bf8a8b1c14',
        allow_closed_native_validation=False),
    # Authorizes checking a FUTURE closed native receipt. No eligible protected
    # image or census exists in this source preparation; None is not a pass.
    'protected-v7-projection-fourway': dict(variant='kv-protected', inputs=93, compiled=66,
        candidate_sha256='82e0d1fc4b4cfcfb0c7b74d5557a5e3ee7d8fe0291c570bb7fd397da9bc68b4e',
        source_join_schema='greedy-selected-v7-projection-fourway-actual-native-model-source-join-v1',
        policy_schema='root-greedy-sram-selection-v7-projection-fourway',
        guard_sha256='676cbc536595fe530dcc39134e6c61eab0b05c0c1880bf822fd2b1232205965f',
        allow_closed_native_validation=True, observed_image_sha256=None),
}

V8_SHA = dict(bytes=29648, sha256='a6fc9c042784f9d48731acafcbb3c6366a5746c458fa6aa9abe1aac59c25df92')
V8_SHA_SCOPE = 'Native SYNTHESIS without VERILATOR selects exact DSP helper; fresh Verilator model uses portable modulo32 helper. Primitive finite evidence is separate.'
V8_NATIVE_PLANS = {
    '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-greedy-speed/build/native-kv-protected-v8-sha-direct-add-20261025-p4r1-rep0-maxfan60/PLAN.json':
        dict(bytes=45003, sha256='27572b5b9c13a28a74c8705451c8a6bef67310f90a8bae08e818f54fa2d301c9'),
    '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-greedy-speed/build/native-kv-protected-v8-sha-direct-add-20261025-p3r0-rep0-maxfan60/PLAN.json':
        dict(bytes=45065, sha256='c32cb628b0885081c8123b44ec853f3e809fb9d414c25139d2e5d33e1e06689d'),
}


def v8_candidate_scope(candidate, parent):
    """Pure source transition contract, not a native or physical resource result."""
    need(candidate['schema'] == 'protected-sha-direct-add-source-candidate-v8'
         and candidate['changed_from_v7'] == ['project/sha.sv']
         and candidate['planned_native_inputs'] == 93 and candidate['owned_inputs'] == 89
         and candidate['all_other_native_input_bytes_unchanged_count'] == 92
         and candidate['guard_cache_RTL_unchanged'] is True
         and candidate['compact_boot_KV_SHA_modules_unchanged'] is True
         and candidate['weight_page_SHA_arithmetic_mapping_changed'] is True
         and candidate['sha_model_native_macro_elaboration_identical'] is False
         and candidate['qualification_inherited'] is False,
         'Exact one-file V8 SHA source delta and honest macro/security scope required')
    before, after = candidate['native_source_sha256_before'], candidate['native_source_sha256_after']
    need(before == parent['native_source_sha256_after'] and set(before) == set(after) and len(after) == 93
         and [name for name in sorted(before) if before[name] != after[name]] == ['project/sha.sv']
         and after['project/sha.sv'] == V8_SHA['sha256']
         and len(candidate['owned_files_before']) == len(candidate['owned_files_after']) == 89
         and set(candidate['owned_files_before']) == set(candidate['owned_files_after'])
         and [name for name in sorted(candidate['owned_files_before'])
              if candidate['owned_files_before'][name] != candidate['owned_files_after'][name]] == ['project/sha.sv'],
         'V8 must retain all other92 native identities and all other88 owned files')


def v8_finite_component_scope(checked):
    """Scope of the pinned recorded R5 result; no query/simulator replay here."""
    need(checked['schema'] == 'source-only-sha-direct-add-check-result-v8' and checked['passed'] is True
         and checked['source_unchanged'] is True and checked['solver_word_domain_all_32bit_pairs'] is True
         and checked['source_compressor_REGISTER_RESULT'] == 0
         and checked['native_primitive_finite_scope_only'] is True
         and all(checked[key] is False for key in ('candidate_adopted', 'hardware_access', 'full_model', 'native_build', 'whole_machine_claim')),
         'Exact separately scoped R5 source-word/compressor/vendor finite receipt required')
    clock = checked['compressor_clock_event_model']
    need(clock['normalization'] == 'yosys clk2fflogic on both source modules before equiv_make'
         and clock['binary_clock_event_semantics'] is True
         and clock['asynchronous_input_negative_holdtime_model'] is True
         and clock['explicit_input_assumptions_added'] is False
         and clock['physical_async_reset_theorem'] is False and clock['metastability_theorem'] is False,
         'R5 normalized binary clock-event/negative-hold scope differs')
    return clock


def validate_v8_source_association(reader, data, spec):
    roles = reader.data['roles']
    candidate, plan, joined, association, model = (data[name] for name in
        ('source_candidate', 'native_plan', 'source_join', 'closed_model_native_association', 'model_complete'))
    plan_origin = roles['native_plan']
    need(plan_origin in V8_NATIVE_PLANS and pin2(reader.pin(plan_origin)) == V8_NATIVE_PLANS[plan_origin],
         'Only the two actual Root-reviewed V8 physical-profile input plans are selectable')
    parent = candidate['source_transition_parent_record']
    need(parent['sha256'] == '82e0d1fc4b4cfcfb0c7b74d5557a5e3ee7d8fe0291c570bb7fd397da9bc68b4e',
         'Exact V7 source transition parent required')
    v8_candidate_scope(candidate, reader.json(parent['path'], parent))
    for record, sha in [(joined, 'ce6c8e150da13bb741bdfc672bcf4a3d6cbf266de683bdd6db49db06a0f6ba49'),
                        (association, '979477a97965947f13fe20aff670f726d853f7ad3c5d14aa85080fb4f4b04086')]:
        need(record['producer']['sha256'] == sha and identity(pin(reader, record['producer']))['sha256'] == sha,
             'Exact V8 source-join/association producer required')
    need(model['schema'] == 'protected-sha-direct-add-paired-model-join-v8'
         and reader.pin(roles['model_complete'])['sha256'] == '3f2a23dbce240ea9692f6175ffad4f7e823cf05b325fd1c7c77461e5447e167c'
         and model['producer']['sha256'] == '0822b60ca0db8dfa2e8266c177b1d981d0f0a1e0e159c30c84fca6c5e1b507a3'
         and model['prior_V7_candidate_results_reused'] is False,
         'Actual corrected_r2 V8 closed model required; no V7 relabelling')
    pin(reader, model['producer'])
    metadata = reader.json(spec['model_metadata'])
    metadata_want = dict(bytes=169651, sha256='4e69920fd5359da140b2953cd9a84848ac09b9defe05a09bbfb75668dd3088dc')
    raw_want = dict(bytes=55706, sha256='4229d0740b75f6bf46e7dc5e406385d1c2053b8b9b7b2bfbaeced8cdd8483ed7')
    binding = association['model_metadata_binding']
    need(model['selected_packet'] == metadata_want
         and identity(reader.read(spec['model_metadata'])) == metadata_want
         and binding['kind'] == 'protected-selected-ASSEMBLED-packet'
         and binding['selected_metadata'] == joined['model_source_metadata']
         and binding['all_compiled_production_modules'] == 66
         and model['candidate_result'] == pin2(binding['closed_candidate_result']) == raw_want
         and identity(pin(reader, binding['closed_candidate_result'])) == raw_want,
         'Actual selected V8 full-model packet/result association differs')
    for field, role in [('native_finished', 'native_finished'), ('native_static_audit', 'native_static')]:
        linked(reader, association[field], roles[role])
    need('sha.sv' in metadata['production_compile_order']
         and metadata['files']['optimized/sha.sv'] == V8_SHA
         and metadata['sha_model_native_macro_elaboration_identical'] is False
         and metadata['sha_macro_scope'] == V8_SHA_SCOPE,
         'Actual compiled model SHA source and macro disclosure required')
    sha = candidate['sha_direct_add_source']
    need(pin2(sha) == V8_SHA and sha['path'] == str(PurePosixPath(plan['candidate']) / 'project/sha.sv')
         and pin2(plan['inputs']['project/sha.sv']) == V8_SHA
         and identity(pin(reader, sha)) == V8_SHA, 'Actual selected SHA source differs')
    finite = candidate['sha_direct_add_finite_source_completion']
    need(finite['sha256'] == '567a96144bd5e5244e599dae5ea9b4142da298c08cdaa49202e385cd14737f17', 'Exact R5 component receipt required')
    checked = reader.json(finite['path'], finite)
    clock = v8_finite_component_scope(checked)
    component_plan = checked['plan']
    need(component_plan['sha256'] == '03285601173d51afd305511d0d44453421503f958565fe9629af434d84185554', 'Actual R5 component plan required')
    pin(reader, component_plan)
    expected_scope = dict(source_check_completion=finite, source_check_plan=component_plan,
        portable_word_domain='all2^64 binary32 operandpairs', normalized_compressor_model=clock,
        matched_existing_state_REGISTER_RESULT=0, actual_vendor_finite_pairs=4352,
        vendor_all_word_theorem=False, physical_async_reset_theorem=False,
        metastability_theorem=False, whole_machine_theorem=False)
    need(joined['sha_direct_add_component_scope'] == association['sha_direct_add_component_scope'] == expected_scope
         and joined['actual_SHA_production_module_joined'] is True
         and joined['all_other_candidate_native_inputs_identical_to_v7'] == 92
         and association['native_and_model_macro_elaboration_identical'] is False
         and association['source_bytes_bound_to_closed_model'] is True
         and association['prior_V7_candidate_results_reused'] is False,
         'Recorded V8 source/native/model component and macro association differs')
    for record in (metadata, joined, association, model):
        need(record['sha_direct_add_source'] == sha and record['sha_direct_add_finite_source_completion'] == finite
             and record['sha_model_native_macro_elaboration_identical'] is False
             and record['sha_macro_scope'] == V8_SHA_SCOPE, 'V8 SHA source/component/macro object differs by role')
    need(model['all_current_SHA_production_source_recompiled'] is True
         and association['all_current_SHA_production_source_recompiled'] is True,
         'Fresh V8 SHA production compile closure required')
    projection = candidate['projection_fourway_sources']
    need(joined['projection_fourway_sources'] == association['projection_fourway_sources'] == model['projection_fourway_sources'] == projection
         and joined['actual_projection_production_modules_joined'] is True
         and model['all_current_projection_production_sources_recompiled'] is True,
         'Unchanged exact V7 projection sources must remain joined in V8')
    for kind, name in [('engine', 'project/cluster-engine.sv'), ('tile', 'project/cluster-tile.sv')]:
        need(pin2(plan['inputs'][name]) == pin2(projection[kind])
             and identity(pin(reader, projection[kind])) == pin2(plan['inputs'][name]),
             'V8 projection source/native input differs')
    return dict(V8_SHA_production_source_entries_joined=1, V8_projection_production_source_entries_joined=2,
        native_and_model_macro_elaboration_identical=False,
        recorded_SHA_R5_component_scope_pinned=True, SHA_R5_queries_or_simulation_replayed_here=False,
        source_expected_extra_fixed_add_DSP_instances=112, expected_count_is_not_observed_native_census=True,
        new_training_or_whole_machine_or_vendor_all_words_theorem=False)


# Actual fresh V9 model closure. These identities do not imply a successful
# native image, selected policy or physical qualification.
V9_MODEL_IDENTITIES = {
    'completion': dict(bytes=36839, sha256='46d2a129081049ec78746bef74ff4d3fd6bec5a188d60fb38e0a6c23c7346d02'),
    'raw': dict(bytes=55815, sha256='265db2eaea290c7617824e8f7ac2b78a257be3629e248a454e7a063d41512e2e'),
}
V9_METADATA = dict(bytes=168995, sha256='4a49bbbbddbb98f4e131ddad3732a2a6a08d5c3c54fc724f6201c928da153eaf')
V9_NATIVE_PLANS = {
    '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-greedy-speed/build/native-kv-protected-v9-dense-sha-20261025-p4r1-rep0-maxfan60/PLAN.json':
        dict(bytes=44550, sha256='90cd6be4d35cd1c70aeb20319ab00c1ad7b218e67ab8cb539f0d68298e82e444'),
}
V9_DENSE_GEOMETRY = dict(tiles=4, rows_per_tile=16, physical_projection_lanes=64,
    contexts_per_physical_multiplier=1, minimum_weight_accept_spacing=1)
V9_DENSE_SOURCES = {
    'engine': ('project/cluster-engine.sv', dict(bytes=12136, sha256='97a3edaccef6dba1f095f82706c260cb0520fae49751ba34d76dda0ad314ec88')),
    'tile': ('project/cluster-tile.sv', dict(bytes=5635, sha256='19bcb21499706281f7f1505b905e56656c833901d7978d7ae94b3bc2ad361908')),
    'multiplier': ('project/cluster-mul.sv', dict(bytes=3395, sha256='93e12f47a8651a1c131609d132f7b50810ac1124200e583164fad3b83e589417')),
}


def v9_candidate_scope(candidate, parent):
    """Exact two-file dense transition; source geometry is not a native census."""
    need(candidate['schema'] == 'protected-dense-sha-source-candidate-v9'
         and candidate['changed_from_v8'] == ['project/cluster-engine.sv', 'project/cluster-tile.sv']
         and candidate['planned_native_inputs'] == 93 and candidate['owned_inputs'] == 89
         and candidate['all_other_native_input_bytes_unchanged_count'] == 91
         and candidate['guard_cache_RTL_unchanged_from_v8'] is True
         and candidate['compact_boot_KV_SHA_modules_unchanged'] is True
         and candidate['weight_page_SHA_arithmetic_mapping_retained_from_v8'] is True
         and candidate['attention_four_lane_memory_UART_clocks_model_layout_unchanged_from_v8'] is True
         and candidate['sha_model_native_macro_elaboration_identical'] is False
         and candidate['prior_V8_candidate_results_reused'] is False
         and candidate['qualification_inherited'] is False
         and candidate['projection_dense_geometry'] == V9_DENSE_GEOMETRY
         and candidate['dense_projection_cancel_payload_erasure_claimed'] is False
         and 'projection_fourway_sources' not in candidate
         and 'projection_finite_source_completion' not in candidate,
         'Exact V9 dense two-file source transition/non-erasure/macro scope required')
    before, after = candidate['native_source_sha256_before'], candidate['native_source_sha256_after']
    need(before == parent['native_source_sha256_after'] and len(before) == len(after) == 93
         and set(before) == set(after)
         and [name for name in sorted(before) if before[name] != after[name]] == ['project/cluster-engine.sv', 'project/cluster-tile.sv']
         and before['project/sha.sv'] == after['project/sha.sv'] == V8_SHA['sha256']
         and len(candidate['owned_files_before']) == len(candidate['owned_files_after']) == 89
         and set(candidate['owned_files_before']) == set(candidate['owned_files_after'])
         and [name for name in sorted(candidate['owned_files_before'])
             if candidate['owned_files_before'][name] != candidate['owned_files_after'][name]] == ['project/cluster-engine.sv', 'project/cluster-tile.sv'],
         'All other91 native and87 owned V8 source identities must remain unchanged')
    for role in ('engine', 'tile'):
        name, wanted = V9_DENSE_SOURCES[role]
        need(after[name] == wanted['sha256'] and pin2(candidate['projection_dense_sources'][role]) == wanted,
             'Exact initialized dense donor identity required')


def v9_dense_component_scope(record):
    """Pinned initialized finite scope only; no component rerun or erasure claim."""
    need(record['schema']=='protected-dense-donor-initialized-component-completion-v1'
         and record['passed'] is True and record['source_only'] is True
         and record['source_inputs_unchanged'] is True and record['new_semantic_mutants_refused']==9
         and record['source_geometry']==dict(tiles=4,physical_projection_lanes=64,physical_lanes_per_tile=16,
             accumulator_contexts_per_multiplier=1,minimum_weight_accept_spacing_clocks=1)
         and record['pending_payload_write_at_cancel_edge_observed'] is True
         and all(record[key] is True for key in ('initialized_payload_and_metadata_all16_checked',
             'semantic_DONE_immediate_last_row_checked','full_first_overwrite_recovery_checked',
             'engine_CLEAR_lock_fault_public_gates_checked','tile_kill_begin_reset_control_revocation_checked',
             'initialized_dense_busy_read_before_write_checked','adjacent_dense_accepts_legal_checked'))
         and all(record[key] is False for key in ('payload_erasure_claimed','fourway_V7_finite_reused',
             'hardware_access','native_build','full_model','vendor_primitive_tested','whole_machine_claim')),
         'Exact new initialized dense donor/non-erasure finite scope required')


V9_R1_RECIPE_SHA = '7137320c46443b0ce20ed6056db96e66b202101c176339a48c51e452b03a5f20'
V9_STOCK_PLAN_SHA = '799d9dbd86fe5eb181b7cac7e1fd805b9de4147e6424e57e802315263f7027dd'


def v9_r1_source_records_scope(plan, joined, association):
    """Same V9 source/model epoch, one explicitly recorded physical-only profile."""
    override = plan['implementation_recipe_override']
    need(override['changed_options'] == ['route_option:0->1', 'route_maxfan:23->60']
         and override['original_plan']['sha256'] == V9_STOCK_PLAN_SHA
         and override['implemented_recipe'] == plan['inputs']['run.tcl']
         and plan['inputs']['run.tcl']['sha256'] == V9_R1_RECIPE_SHA
         and plan['inputs']['run.tcl']['bytes'] == 894
         and override['production_RTL_unchanged'] is True
         and override['project_file_list_unchanged'] is True
         and override['clocks_and_constraints_unchanged'] is True,
         'Exact two-literal R1 implemented recipe and unchanged source/clock scope required')
    for record in (joined, association):
        need(record['exact_reviewed_R1_native_plan_sha256'] == '90cd6be4d35cd1c70aeb20319ab00c1ad7b218e67ab8cb539f0d68298e82e444'
             and record['exact_two_literal_recipe_inverse_checked'] is True
             and record['all_other92_implemented_inputs_stock_identical'] is True,
             'R1 source/association must retain exact plan/inverse/other92 provenance')
    need(joined['native_input_delta'] == association['declared_Tcl_only_native_delta'] == ['run.tcl'],
         'Only implemented run.tcl may differ from the unchanged V9 source candidate')



def validate_v9_source_association(reader, data, spec):
    need(V9_MODEL_IDENTITIES is not None, 'V9 raw/final model closure identities are not frozen; association unavailable')
    roles = reader.data['roles']
    candidate, plan, joined, association, model = (data[name] for name in
        ('source_candidate', 'native_plan', 'source_join', 'closed_model_native_association', 'model_complete'))
    plan_origin = roles['native_plan']
    need(plan_origin in V9_NATIVE_PLANS and pin2(reader.pin(plan_origin)) == V9_NATIVE_PLANS[plan_origin],
         'Only the exact R1 Root-reviewed V9 source/native plan is selectable')
    v9_r1_source_records_scope(plan, joined, association)
    parent = candidate['source_transition_parent_record']
    need(parent['sha256'] == 'c0929b466a40c3541d0b5ad797f62430e8802d405ada9afb1b1e23bb0dc43951',
         'Exact V8 source transition parent required')
    v9_candidate_scope(candidate, reader.json(parent['path'], parent))
    for record, sha in [(joined, '51c56d3712b80aecfc79c93f082cf17717ca1ef0ac5066cbe701ca302392f9f6'),
                        (association, '858ffe9809101079f8a74aacec56755866d2dde510431a013defebc6c9b9a1e9')]:
        need(record['producer']['sha256'] == sha and identity(pin(reader, record['producer']))['sha256'] == sha,
             'Exact V9 source-join/association producer required')
    need(model['schema'] == 'protected-dense-sha-paired-model-join-v9'
         and pin2(reader.pin(roles['model_complete'])) == V9_MODEL_IDENTITIES['completion']
         and model['producer']['sha256'] == '2c325f93fbf768fa7ba2d95ace7c8099892cb2e671827cfd19ed0f59eb2b0794'
         and model['prior_V8_candidate_results_reused'] is False,
         'Actual new V9 closed model required; no V8 relabelling')
    pin(reader, model['producer'])
    metadata = reader.json(spec['model_metadata'])
    raw_want = V9_MODEL_IDENTITIES['raw']
    binding = association['model_metadata_binding']
    need(model['selected_packet'] == V9_METADATA
         and identity(reader.read(spec['model_metadata'])) == V9_METADATA
         and binding['kind'] == 'protected-selected-ASSEMBLED-packet'
         and binding['selected_metadata'] == joined['model_source_metadata']
         and binding['all_compiled_production_modules'] == 66
         and model['candidate_result'] == pin2(binding['closed_candidate_result']) == raw_want
         and identity(pin(reader, binding['closed_candidate_result'])) == raw_want,
         'Actual selected V9 full-model packet/result association differs')
    for field, role in [('native_finished', 'native_finished'), ('native_static_audit', 'native_static')]:
        linked(reader, association[field], roles[role])
    need('sha.sv' in metadata['production_compile_order']
         and metadata['files']['optimized/sha.sv'] == V8_SHA
         and metadata['sha_model_native_macro_elaboration_identical'] is False
         and metadata['sha_macro_scope'] == V8_SHA_SCOPE,
         'Actual compiled V9 SHA source and macro disclosure required')
    sha = candidate['sha_direct_add_source']
    need(pin2(sha) == V8_SHA and sha['path'] == str(PurePosixPath(plan['candidate']) / 'project/sha.sv')
         and pin2(plan['inputs']['project/sha.sv']) == V8_SHA
         and identity(pin(reader, sha)) == V8_SHA, 'Actual selected retained SHA source differs')
    finite = candidate['sha_direct_add_finite_source_completion']
    need(finite['sha256'] == '567a96144bd5e5244e599dae5ea9b4142da298c08cdaa49202e385cd14737f17',
         'Exact retained R5 component receipt required')
    checked = reader.json(finite['path'], finite)
    clock = v8_finite_component_scope(checked)
    component_plan = checked['plan']
    need(component_plan['sha256'] == '03285601173d51afd305511d0d44453421503f958565fe9629af434d84185554', 'Actual R5 component plan required')
    pin(reader, component_plan)
    sha_scope = dict(source_check_completion=finite, source_check_plan=component_plan,
        portable_word_domain='all2^64 binary32 operandpairs', normalized_compressor_model=clock,
        matched_existing_state_REGISTER_RESULT=0, actual_vendor_finite_pairs=4352,
        vendor_all_word_theorem=False, physical_async_reset_theorem=False,
        metastability_theorem=False, whole_machine_theorem=False)
    projection = candidate['projection_dense_sources']
    dense_pin = candidate['projection_dense_finite_source_completion']
    need(pin2(dense_pin) == dict(bytes=3534,sha256='b758877e03a33aa86f81450d62ffeab86002cfa74f13ba71552a0feeb1ccc675'),
         'Exact new dense finite completion required')
    dense = reader.json(dense_pin['path'], dense_pin); v9_dense_component_scope(dense)
    for key in ('producer', 'plan', 'execution'): pin(reader, dense[key])
    need(dense['producer']['sha256'] == '311488a9fd8c814e671de331a6273c85b9670aea26aac762debbc1aa23633208',
         'Exact new dense finite producer required')
    for role,(name,wanted) in V9_DENSE_SOURCES.items():
        need(pin2(dense['sources'][role]) == wanted and pin2(plan['inputs'][name]) == wanted
             and identity(pin(reader,dense['sources'][role])) == wanted,
             'Exact dense component donor/native input association required')
        if role != 'multiplier':
            need(projection[role]['path'] == str(PurePosixPath(plan['candidate']) / name)
                 and pin2(projection[role]) == wanted and identity(pin(reader,projection[role])) == wanted,
                 'Actual current dense production source pointer differs')
    dense_scope = dict(source_check_completion=dense_pin, initialized_dense_semantics=True,
        geometry=dense['source_geometry'], payload_erasure_claimed=False,
        pending_payload_cancel_edge_write_permitted=True, vendor_primitive_theorem=False,
        whole_machine_theorem=False, component_reexecuted=False)
    for record in (metadata, joined, association, model):
        need(record['sha_direct_add_source'] == sha and record['sha_direct_add_finite_source_completion'] == finite
             and record['sha_model_native_macro_elaboration_identical'] is False
             and record['sha_macro_scope'] == V8_SHA_SCOPE
             and record['projection_dense_sources'] == projection
             and record['projection_dense_geometry'] == V9_DENSE_GEOMETRY
             and record['projection_dense_finite_source_completion'] == dense_pin
             and record['dense_projection_cancel_payload_erasure_claimed'] is False
             and 'projection_fourway_sources' not in record and 'projection_finite_source_completion' not in record,
             'V9 dense/SHA source/component/macro object differs by role')
    need(joined['sha_direct_add_component_scope'] == association['sha_direct_add_component_scope'] == sha_scope
         and joined['projection_dense_component_scope'] == association['projection_dense_component_scope'] == dense_scope
         and joined['actual_SHA_production_module_joined'] is True
         and joined['actual_projection_production_modules_joined'] is True
         and joined['all_other_candidate_native_inputs_identical_to_v8'] == association['all_other_candidate_native_inputs_identical_to_v8'] == 91
         and association['native_and_model_macro_elaboration_identical'] is False
         and association['source_bytes_bound_to_closed_model'] is True
         and association['prior_V8_candidate_results_reused'] is False
         and model['all_current_SHA_production_source_recompiled'] is True
         and model['all_current_projection_production_sources_recompiled'] is True
         and association['all_current_SHA_production_source_recompiled'] is True
         and association['all_current_projection_production_sources_recompiled'] is True,
         'Fresh V9 dense/SHA compile/source/component association differs')
    return dict(V9_SHA_production_source_entries_joined=1, V9_projection_production_source_entries_joined=2,
        physical_implementation_profile='P4/R1/rep0/maxfan60',
        exact_reviewed_R1_native_plan_sha256='90cd6be4d35cd1c70aeb20319ab00c1ad7b218e67ab8cb539f0d68298e82e444',
        exact_implemented_recipe_sha256=V9_R1_RECIPE_SHA,
        all_other92_implemented_inputs_stock_identical=True,
        native_and_model_macro_elaboration_identical=False,
        recorded_SHA_R5_component_scope_pinned=True, SHA_R5_queries_or_simulation_replayed_here=False,
        recorded_dense_initialized_component_scope_pinned=True, dense_component_reexecuted_here=False,
        dense_payload_erasure_claimed=False, expected_dense_projection_lanes=64,
        source_expected_extra_fixed_add_DSP_instances=112, expected_count_is_not_observed_native_census=True,
        new_training_or_whole_machine_or_vendor_all_words_theorem=False)



def need(ok, message):
    if not ok:
        raise ValueError(message)


def identity(raw):
    return dict(bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest())


def pin2(row):
    return {key: row[key] for key in ('bytes', 'sha256')}


def pin(reader, row):
    return reader.read(row['path'], {key: row[key] for key in ('path', 'bytes', 'sha256')})


def same_pin(a, b):
    return {key: a[key] for key in ('path', 'bytes', 'sha256')} == {key: b[key] for key in ('path', 'bytes', 'sha256')}


def linked(reader, row, origin, allow_pathless=False):
    if allow_pathless and set(row) == {'bytes', 'sha256'}:
        return reader.read(origin, row)
    need(same_pin(row, reader.pin(origin)), 'Raw record pointer differs from selected actual role')
    return pin(reader, row)


def finite_number(number, lower=None):
    return (type(number) in (int, float) and math.isfinite(number)
            and (lower is None or number >= lower))


def actual_source_joins(reader, join, epoch, native_plan, metadata_origin):
    need(join['schema'] == epoch['source_join_schema'] and join['variant'] == epoch['variant']
         and join['passed_source_join'] is True and join['every_compiled_model_production_module_matches_actual_native'] is True
         and join['native_input_count'] == epoch['inputs'] and join['compiled_production_module_count'] == epoch['compiled'],
         'Explicit actual native/model source-entry epoch required')
    linked(reader, join['model_source_metadata'], metadata_origin)
    metadata = reader.json(metadata_origin)
    folder = PurePosixPath(metadata_origin).parent
    paired_metadata = epoch['variant'] in ('baseline', 'kv-protected')
    if paired_metadata:
        need(metadata['schema'] == 'greedy-speed-paired-model-packet-v1', 'Known paired-model metadata schema required')
        order = metadata['production_compile_order']
        mapping = {name: 'project/' + name for name in order}
        model_files = {name: str(folder / 'optimized' / name) for name in order}
        compiler_list = str(folder / 'optimized/production_sources.f')
        expected_list = metadata['files']['optimized/production_sources.f']
    else:
        need(metadata['schema'] == 'tang-greedy-encrypted-attention-model-inputs-v1', 'Known encrypted-model metadata schema required')
        order, mapping = metadata['compile_order'], metadata['native_source_mapping']
        model_files = {name: str(folder / name) for name in order}
        compiler_list = str(folder / 'production_sources.f')
        expected_list = dict(sha256=metadata['files']['production_sources.f'])
    need(len(order) == epoch['compiled'] and len(set(order)) == len(order)
         and set(mapping) == set(order) and len(set(mapping.values())) == len(order),
         'Unique complete metadata production-source order/mapping required')
    list_bytes = reader.read(compiler_list)
    need(list_bytes == ('\n'.join(order) + '\n').encode()
         and identity(list_bytes)['sha256'] == expected_list['sha256'],
         'Actual compiler .f bytes do not equal complete metadata source order')
    entries = []
    if epoch['variant'] == 'baseline':
        for name, row in join['compiled_production_source_joins'].items():
            entries.append(('project/' + name, row['model'], row['native_execution_source'], row['native_execution_snapshot']))
    else:
        entries = [(row['native_input'], row['model_source'], row['actual_native_origin'], row['actual_native_archive'])
                   for row in join['production_modules']]
    need(len(entries) == epoch['compiled'] and len({row[0] for row in entries}) == len(entries),
         'Complete unique compiled production source entries required')
    need({row[0] for row in entries} == set(mapping.values()), 'Compiled source joins omit/replace metadata production entries')
    reverse_mapping = {native_name: model_name for model_name, native_name in mapping.items()}
    for name, model, actual, archive in entries:
        model_name = reverse_mapping[name]
        need(model['path'] == model_files[model_name], 'Compiled source pointer differs from exact metadata/per-flavor model file')
        source_want = metadata['files']['optimized/' + model_name] if paired_metadata else dict(sha256=metadata['files'][model_name])
        need(model['sha256'] == source_want['sha256'], 'Compiled source pin differs from actual model metadata entry')
        need(name in native_plan['inputs'] and name.endswith('.sv') and not native_plan['inputs'][name]['vendor'],
             'Compiled production source is absent/native-vendor/unsupported')
        source = native_plan['inputs'][name]
        expected_actual_path = (str(PurePosixPath(join['native_plan']['path']).parent / name)
                                if epoch['variant'] == 'baseline' else source['path'])
        need(actual['path'] == expected_actual_path and pin2(actual) == pin2(source) and identity(pin(reader, model)) == pin2(source)
             and identity(pin(reader, actual)) == identity(pin(reader, archive)) == pin2(source),
             'Compiled production bytes differ from actual native source/snapshot')
    return dict(compiled_production_source_entries=len(entries), raw_legacy_field_names_unchanged=True,
                HDL_module_definition_or_physical_instance_count_claimed=False)


def validate_static(reader, static, native_plan_origin, native_finished_origin, image_sha256):
    need(static['schema'] == 'greedy-variant-native-static-screen-v1' and static['passed'] is True
         and static['source_inputs_unchanged'] is True and static['resources_fit'] is True
         and static['inference_setup_hold_nonnegative'] is True and static['image_sha256'] == image_sha256
         and static['complete_timing_signoff'] is False, 'Actual scoped positive inference25MHz static role required')
    linked(reader, static['native_plan'], native_plan_origin, allow_pathless=True)
    linked(reader, static['native_finished'], native_finished_origin)
    need(finite_number(static['reported_inference_fmax_mhz'], 25), 'Inference frequency below25MHz/nonfinite')
    for kind in ('setup', 'hold'):
        row = static['inference_paths'][kind]
        need(row['launch_clock'] == row['capture_clock'] == 'inference_clk25:[R]'
             and finite_number(row['slack_ns'], 0), 'Negative/nonfinite/incomplete inference timing paths')
    need(set(static['resources']) == {'BSRAM', 'CLS', 'DSP', 'Logic', 'Register'}, 'Resource class census differs')
    for row in static['resources'].values():
        need(finite_number(row['used'], 0) and finite_number(row['available'], 0) and row['used'] <= row['available'],
             'Resource count exceeds device/invalid value')
    need(set(static['raw_products']) == {'.fs', '.rpt.txt', '.tr', '.vo'}, 'Actual four native product roles required')
    for row in static['raw_products'].values():
        pin(reader, row)
    return dict(reported_inference_fmax_mhz=static['reported_inference_fmax_mhz'],
                inference_setup_hold_nonnegative=True, resources=static['resources'], complete_timing_signoff=False)


def execution(reader, row, licensed_inputs):
    for name in ('stdout', 'stderr'):
        pin(reader, row[name])
    need(row['os_timed_out'] is False and row['retries'] == 0 and type(row['exit_code']) is int,
         'Timed out/retried/unclosed mapped finite execution')
    for origin, wanted in row['input_snapshot'].items():
        if origin in licensed_inputs:
            need(wanted == licensed_inputs[origin], 'Omitted licensed finite input pin differs')
        else:
            reader.read(origin, wanted)
    return pin(reader, row['stdout']).decode(), pin(reader, row['stderr']).decode()


def validate_mapped(reader, mapped, epoch, source_candidate_origin, native_plan_origin,
                    native_finished_origin, native_static_origin, image_sha256, licensed_inputs):
    need(mapped['schema'] == 'greedy-native-canonical-mapped-rom-finite-v1' and mapped['passed'] is True
         and mapped['passed_local_canonical_checks'] is True and mapped['whole_image_equivalence'] is False
         and mapped['board_load_allowed'] is False and mapped['hardware_access'] is False
         and (mapped['canonical_addresses'], mapped['invalid_addresses'], mapped['clocked_checks'],
              mapped['async_checks'], mapped['extra_startup_reset_assertions']) == (4097, 4095, 16399, 4, 1),
         'Exact actual-image local finite-ROM scope required')
    binding = mapped['native_binding']
    expected = dict(variant=epoch['variant'], input_count=epoch['inputs'], image_sha256=image_sha256,
        source_candidate_sha256=reader.pin(source_candidate_origin)['sha256'],
        native_plan_sha256=reader.pin(native_plan_origin)['sha256'],
        native_finished_sha256=reader.pin(native_finished_origin)['sha256'],
        native_audit_sha256=reader.pin(native_static_origin)['sha256'],
        rom_source_sha256='042df8b9da13bc2a66f945b2942a30374d52fa38766ba73916999901fa63622f',
        canonical_table_sha256='c3e491c6abcd545f73dce0fabb37f86d2eed31a0334268da1e035a75f4c62a3f')
    need(all(binding[key] == value for key, value in expected.items()), 'Finite-ROM role belongs to another source/native/image')
    positive = mapped['positive']
    pin(reader, positive['binary'])
    out, err = execution(reader, positive['compile'], licensed_inputs)
    need(positive['compile']['exit_code'] == 0, 'Mapped positive compile failed')
    out, err = execution(reader, positive['run'], licensed_inputs)
    lines = out.splitlines()
    bench = str(PurePosixPath(positive['binary']['path']).parent / 'canonical_mapped_tb.sv')
    need(positive['run']['exit_code'] == 0 and len(lines) == 2 and bench in positive['run']['input_snapshot']
         and lines[0] == 'PASS GREEDY canonical mapped finite legal=4097 invalid=4095 clocked=16399 async=4 startup_reset=1'
         and lines[1] == bench + ':87: $finish called at 164003000 (1ps)',
         'Mapped finite actual positive run marker/terminal simulator metadata differs')
    need(len(mapped['simulation_mutants']) == 6 and len(mapped['parser_controls']) == 9
         and len(mapped['ancillary_controls']) == 6 and len(mapped['executions']) == 7, 'Exact finite/control census differs')
    for row in mapped['simulation_mutants']:
        need(row['detected'] is True and row['before'] != row['after'], 'Undetected/nonmutation finite control')
        trial = row['execution']
        pin(reader, trial['binary'])
        execution(reader, trial['compile'], licensed_inputs)
        stdout, stderr = execution(reader, trial['run'], licensed_inputs)
        need(trial['compile']['exit_code'] == 0 and trial['run']['exit_code'] != 0
             and 'PASS GREEDY' not in stdout, 'Mutation did not fail actual finite run')
    need(all(row['rejected'] is True and row['reason'] for row in mapped['parser_controls'] + mapped['ancillary_controls']),
         'Missing recorded parser/ancillary refusal')
    # Frozen exact-result pins and input/producer references authenticate the
    # parser controls; no claim that portable checking reran Icarus or parsing.
    return dict(legal=4097, invalid=4095, clocked=16399, async_checks=4, startup_reset=1,
                recorded_simulation_mutants=6, recorded_parser_controls=9, recorded_ancillary_controls=6,
                actual_positive_and_mutant_execution_outputs_reparsed=True, finite_tools_reexecuted=False,
                licensed_inputs_rehashed=False, omitted_licensed_inputs_declared=len(licensed_inputs),
                whole_image_equivalence=False)


def validate_recipe_delta(original,implemented,changes):
    """Invert only declared, bounded integer-option changes; all other bytes stay."""
    allowed={'place_option':{(4,3)},'route_option':{(0,1)},
             'route_maxfan':{(23,60)},'replicate_resources':{(1,0),(0,1)}}
    need(type(changes)is list and changes,'Declared physical-option delta required')
    seen=set();reverted=implemented.splitlines(keepends=True);original_lines=original.splitlines(keepends=True)
    for change in changes:
        need(type(change)is str,'Typed physical option change required')
        match=re.fullmatch(r'([a-z_]+):(0|[1-9][0-9]*)->(0|[1-9][0-9]*)',change)
        need(match is not None,'Integer physical option transition required')
        option,before,after=match.groups();before=int(before);after=int(after)
        need(option in allowed and option not in seen and (before,after)in allowed[option],
             'Undeclared, repeated or unreviewed physical option transition')
        seen.add(option)
        old_line=f'set_option -{option} {before}\n'.encode()
        new_line=f'set_option -{option} {after}\n'.encode()
        need(original_lines.count(old_line)==1 and reverted.count(new_line)==1,
             'Unique actual stock/implemented integer option required')
        reverted=[old_line if line==new_line else line for line in reverted]
    need(b''.join(reverted)==original,'Tcl contains bytes outside declared integer-option changes')



def candidate_input_inventory(reader, candidate, plan, epoch):
    if epoch['variant'] == 'baseline':
        original_path = str(PurePosixPath(plan['candidate']) / 'NATIVE-INPUTS.json')
        original = reader.json(original_path)
        owned = reader.json(str(PurePosixPath(plan['candidate']) / 'OWNED-INPUTS.json'))
        canonical = lambda value: (json.dumps(value, sort_keys=True, separators=(',', ':')) + '\n').encode()
        need(identity(canonical(original))['sha256'] == candidate['native_inventory_sha256']
             and identity(canonical(owned))['sha256'] == candidate['owned_inventory_sha256']
             and len(original) == candidate['native_inputs'] == 90 and len(owned) == candidate['owned_inputs'] == 87,
             'Frozen baseline complete native/owned inventory differs')
        need(set(plan['inputs']) == set(original), 'Native input census differs from frozen baseline inventory')
        for name, row in plan['inputs'].items():
            need(pin2(row) == pin2(original[name]), 'Baseline native input differs from frozen candidate: ' + name)
        need({name: row for name, row in owned.items() if not name.endswith('.NOTICE')} ==
             {name: pin2(row) for name, row in original.items() if row['materialized_in_candidate'] is True},
             'Baseline complete owned/native source association differs')
        return dict(all_candidate_native_input_identities_checked=True, declared_physical_recipe_delta=[])
    original = (candidate['native_source_sha256_after'] if epoch['variant'] == 'kv-protected' else candidate['native_inputs'])
    need(set(plan['inputs']) == set(original) and len(original) == epoch['inputs'],
         'Actual complete input census differs from frozen source candidate')
    changed = [name for name, row in plan['inputs'].items() if row['sha256'] != original[name]]
    override = plan.get('implementation_recipe_override')
    if override is None:
        need(not changed, 'Undeclared production/guard/cache/crypto/source input change')
    else:
        need(changed == ['run.tcl'] and override['production_RTL_unchanged'] is True
             and override['project_file_list_unchanged'] is True and override['clocks_and_constraints_unchanged'] is True
             and override['diagnostic_generation_options_preserved'] is True,
             'Only explicitly declared bounded Tcl physical profile may differ')
        old, new = override['original_recipe'], override['implemented_recipe']
        need(old['path'] == str(PurePosixPath(plan['candidate']) / 'run.tcl') and old['sha256'] == original['run.tcl']
             and new == plan['inputs']['run.tcl'], 'Physical profile detached from frozen source/native input')
        validate_recipe_delta(pin(reader, old), pin(reader, new), override['changed_options'])
        base = reader.json(override['original_plan']['path'], override['original_plan'])
        need(base['candidate_receipt'] == plan['candidate_receipt'] and set(base['inputs']) == set(plan['inputs'])
             and all(base['inputs'][name] == row for name, row in plan['inputs'].items() if name != 'run.tcl'),
             'Physical override changes another native input/candidate/constraint')
    return dict(all_candidate_native_input_identities_checked=True, declared_physical_recipe_delta=changed)

def validate_native_graph(reader, epoch_name, spec):
    need(epoch_name in EPOCHS, 'Unreviewed source/native epoch')
    epoch = EPOCHS[epoch_name]
    need(epoch['allow_closed_native_validation'], 'ProtectedV6 has no eligible image; fresh protected epoch required')
    roles = reader.data['roles']
    required = ('source_candidate', 'native_plan', 'native_finished', 'native_static', 'mapped_rom',
                'source_join', 'model_complete', 'closed_model_native_association', 'root_policy')
    data = {name: reader.role(name) for name in required}
    need(reader.variant == epoch['variant'], 'Capsule variant differs from epoch')
    candidate, plan, finished = (data[key] for key in ('source_candidate', 'native_plan', 'native_finished'))
    need(reader.pin(roles['source_candidate'])['sha256'] == epoch['candidate_sha256'], 'Source candidate epoch differs')
    need(plan['variant'] == finished['variant'] == epoch['variant'] and len(plan['inputs']) == epoch['inputs']
         and finished['schema'] == 'greedy-variant-offline-native-build-v1' and finished['exit_code'] == 0
         and finished['flow_completed'] is True and finished['source_inputs_unchanged'] is True
         and finished['plan_sha256'] == reader.pin(roles['native_plan'])['sha256'], 'Actual successful native/source closure required')
    linked(reader, plan['candidate_receipt'], roles['source_candidate'])
    candidate_inputs = candidate_input_inventory(reader, candidate, plan, epoch)
    inventory = reader.json(spec['inventory'])
    need(inventory == {name: row['sha256'] for name, row in plan['inputs'].items()}, 'Public inventory differs from actual implemented native input set')
    need(set(spec['native_snapshots']) == {name for name, row in plan['inputs'].items() if not row['vendor']},
         'Every redistributable native input snapshot required')
    vendor = {}
    for name, row in plan['inputs'].items():
        if row['vendor']:
            need(name.startswith('project/official/'), 'Unexpected omitted native source')
            vendor[row['path']] = pin2(row)
        else:
            reader.read(spec['native_snapshots'][name], pin2(row))
            reader.read(row['path'], pin2(row))
    need(len(vendor) == 4 and all(spec['licensed_inputs'].get(name) == value for name, value in vendor.items()),
         'Exactly four licensed vendor source identities required')
    image = identity(reader.read(spec['image']))
    need(finished['image'] == image, 'Selected actual native image differs')
    static = validate_static(reader, data['native_static'], roles['native_plan'], roles['native_finished'], image['sha256'])
    joined = data['source_join']
    for field, role in [('candidate_receipt', 'source_candidate'), ('native_plan', 'native_plan'),
                        ('native_finished', 'native_finished'), ('native_static_audit', 'native_static')]:
        linked(reader, joined[field], roles[role])
    need(joined['image_sha256'] == image['sha256'], 'Source join image differs')
    source_entries = actual_source_joins(reader, joined, epoch, plan, spec['model_metadata'])
    if epoch['variant'] == 'baseline':
        # Retain the original cde9285 baseline association's four non-SV ROM
        # byte joins separately from the64 compiled production source entries.
        roms = ('digests32.memh', 'metadata192.memh',
            'fpga/token_only_model0_ddr_board1/fixed_vector_rmsnorm0/recorded/norm_rom34.memh',
            'model_rtl_evidence/attention_sublayer/exp_neg_q30.memh')
        model_metadata = reader.json(spec['model_metadata'])
        for name in roms:
            wanted = model_metadata['files']['optimized/' + name]
            need(wanted == pin2(plan['inputs']['project/' + name]), 'Baseline model/native ROM identity differs')
            reader.read(str(PurePosixPath(spec['model_metadata']).parent / 'optimized' / name), wanted)
        need(joined['model_native_rom_count'] == len(roms) == 4, 'Original baseline four-ROM count differs')
        source_entries['baseline_additional_model_native_ROM_files'] = 4

    if epoch_name == 'protected-v7-projection-fourway':
        projection = candidate['projection_fourway_sources']
        wanted_projection = {
            'engine': ('project/cluster-engine.sv', dict(bytes=12710, sha256='d329b95e9208694cbe224e6218b646adf5ba7ffeb1ba76022c2259aa26e21829')),
            'tile': ('project/cluster-tile.sv', dict(bytes=7717, sha256='abf9a54465be769f37f6ed06499749db7a4bf03fcc7f8ea996aef602efa98d63'))}
        need(set(projection) == set(wanted_projection) and joined['projection_fourway_sources'] == projection
             and data['model_complete']['projection_fourway_sources'] == projection
             and joined['actual_projection_production_modules_joined'] is True,
             'Exact protectedV7 projection source/model/native association required')
        for role, (name, wanted) in wanted_projection.items():
            need(projection[role]['path'] == str(PurePosixPath(plan['candidate']) / name)
                 and pin2(plan['inputs'][name]) == wanted and identity(pin(reader, projection[role])) == wanted,
                 'ProtectedV7 projection source identity/owner differs')
        source_entries['V7_projection_production_source_entries_joined'] = 2
        source_entries['new_projection_theorem_or_observed_native_census_claimed'] = False
    association = data['closed_model_native_association']
    if epoch_name == 'protected-v8-sha-direct-add':
        source_entries.update(validate_v8_source_association(reader, data, spec))
    if epoch_name == 'protected-v9-dense-sha':
        source_entries.update(validate_v9_source_association(reader, data, spec))
    if epoch_name=='protected-v15-compact-prefix':
        source_entries.update(validate_v15_source_association(reader,data,spec))
    need(association['schema'] == 'greedy-selected-closed-model-native-association-v1'
         and association['passed'] is True and association['variant'] == epoch['variant'], 'Closed source/native/model association required')
    for field, role in [('source_candidate', 'source_candidate'), ('native_plan', 'native_plan'),
                        ('model_record', 'model_complete'), ('source_join', 'source_join')]:
        linked(reader, association[field], roles[role])
    need(identity(pin(reader, association['image'])) == image, 'Closed model/native association image differs')
    policy = data['root_policy']
    need(policy['schema'] == epoch['policy_schema'] and policy['variant'] == epoch['variant']
         and policy['selected_by'] == '/root' and policy['ready_for_sram_trial'] is True
         and policy['flash_operations_permitted'] is False and policy['automatic_retry'] is False,
         'Exact explicit Root four-role SRAM policy required')
    for name, role in [('model', 'model_complete'), ('native', 'native_finished'), ('static', 'native_static'), ('mapped', 'mapped_rom')]:
        linked(reader, policy['closed_records'][name], roles[role])
    need(set(policy['closed_records']) == {'model', 'native', 'static', 'mapped'}, 'Unexpected proof/memory role epoch')
    linked(reader, policy['source_native_model_association'], roles['closed_model_native_association'])
    linked(reader, policy['source_candidate'], roles['source_candidate'])
    linked(reader, policy['native_plan'], roles['native_plan'])
    need(identity(pin(reader, policy['image'])) == image, 'Root policy image differs')
    mapped = validate_mapped(reader, data['mapped_rom'], epoch, roles['source_candidate'], roles['native_plan'],
        roles['native_finished'], roles['native_static'], image['sha256'], spec['licensed_inputs'])
    return dict(passed=True, variant=epoch['variant'], epoch=epoch_name, image=image,
                native_input_files=epoch['inputs'], **source_entries, inventory_sha256=identity((json.dumps(inventory, sort_keys=True,
                    separators=(',', ':')) + '\n').encode())['sha256'], static=static, mapped=mapped,
                actual_role_origin_paths_unchanged=True, **candidate_inputs, native_or_finite_tools_executed=False,
                complete_timing_or_whole_image_equivalence_claimed=False)


V15_SCOPE_HELPER_SHA256 = '68a4c48b986a31f402b446a03f2f19953a552cca7828105088cf97c8f4643b17'
FINAL_MAPPED_RAM_RESULT_PIN = {'bytes': 1673345, 'path': '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-greedy-speed/build/protected-v15-p3r0-mapped-ram-run-r1/FINISHED.json', 'sha256': '2f8c3fdb05d229bc50f0fb9aa407f997fdc604e1726ca7aa5ae8889a275a5912'}
FINAL_MAPPED_RAM_PRODUCER_PIN = {'bytes': 29700, 'path': '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-greedy-speed/tools/cache_compact_prefix_ram_mapped_finite_v5.py', 'sha256': '0c6ddb65b375c16270d656387e956548aebdecbe3d8ba24275d7236ff13d2847'}


def v15_scope_helper():
    import importlib.util
    from pathlib import Path
    path=Path(__file__).resolve().parent/'current_greedy_v15_scope_portable_v1.py'
    need(type(V15_SCOPE_HELPER_SHA256)is str and hashlib.sha256(path.read_bytes()).hexdigest()==V15_SCOPE_HELPER_SHA256,
        'Reviewed V15 scope-helper source contract pending')
    spec=importlib.util.spec_from_file_location('_portable_current_v15_native_scope',path)
    helper=importlib.util.module_from_spec(spec);spec.loader.exec_module(helper);return helper


def validate_v15_mapped_ram(reader,row,policy,joined,spec,helper):
    need(type(FINAL_MAPPED_RAM_RESULT_PIN)is dict and type(FINAL_MAPPED_RAM_PRODUCER_PIN)is dict
        and row==FINAL_MAPPED_RAM_RESULT_PIN,'Exact final mapped-RAM result/producer pins pending')
    result=reader.json(row['path'],row)
    need(result['schema']=='cache-pending-ram-initialized-primitive-finite-result-v1'
        and result['passed']is True and result['producer']==FINAL_MAPPED_RAM_PRODUCER_PIN,
        'Actual closed mapped mutable-RAM result required')
    helper.rehash_tree(reader,result,spec['omitted_inputs'])
    plan=reader.json(result['reviewed_plan']['path'],result['reviewed_plan'])
    need(reader.read(result['reviewed_plan']['path'])==reader.read(result['copied_plan']['path'],result['copied_plan']),
        'Original/copied mutable-RAM plans differ')
    descriptor=reader.json(plan['descriptor']['path'],plan['descriptor'])
    need(descriptor['native_plan']==policy['native_plan']and descriptor['native_finished']==policy['closed_records']['native']
        and descriptor['native_static']==policy['closed_records']['static']
        and reader.json(descriptor['native_source_join']['path'],descriptor['native_source_join'])==joined
        and descriptor['candidate']==policy['source_candidate'],'Mutable-RAM result belongs to another implementation')
    need(result['geometry']==plan['geometry']==descriptor['geometry']
        and result['geometry']['shape']['RAM16SDP4_instances']==128
        and result['geometry']['shape']['assembly_literal_DFFRE_bindings']==2064,
        'Exact selected initialized primitive geometry required')
    for key in('compile','simulation'):
        stage=result[key];need(stage['exit_code']==0 and stage['timed_out']is False,'Mapped RAM stage failed')
        pin(reader,stage['stdout']);pin(reader,stage['stderr'])
    output=pin(reader,result['simulation']['stdout']).decode().splitlines()
    need(len(output)==2 and output[0]=='PASS PENDING_RAM initialized=128 lanes=16 addresses=8 pair_bits=32 cycles=4608 writes=4480 row_checks=8848 disabled=128 same_address=128 different_address=128 walking=4096'
        and re.fullmatch(re.escape(plan['bench']['path'])+r':114: \$finish called at \d+ \(1ps\)',output[1])is not None
        and pin(reader,result['simulation']['stderr'])==b'', 'Exact initialized RAM simulation/finish output required')
    for key in('controller_write_enable_logic_simulated','assembly_or_response_path_simulated',
        'pending_5_5_9_protocol_tested','CLEAR_or_fault_publication_tested','physical_same_address_data_theorem',
        'uninitialized_state_theorem','payload_erasure_claimed','full_cache_equivalence',
        'numerical_or_whole_image_theorem','ROM_campaign_replayed_or_relabelled','hardware_access'):
        need(result[key]is False,'Mapped finite RAM scope overclaim: '+key)
    return dict(mapped_mutable_RAM_primitive_finite_reparsed=True,controller_or_full_cache_equivalence=False)


def validate_v15_source_association(reader,data,spec):
    helper=v15_scope_helper();helper.finalized()
    candidate,plan,joined,association,completion,policy=(data[k]for k in
        ('source_candidate','native_plan','source_join','closed_model_native_association','model_complete','root_policy'))
    need(reader.pin(reader.data['roles']['native_plan'])==helper.SELECTED_NATIVE_PROFILE_PIN,
        'Only final reviewed exact P4R1 or P3R0 native profile is supported')
    profile=helper.PROFILE_PINS[helper.SELECTED_NATIVE_PROFILE_PIN['sha256']]
    need(plan['implementation_recipe_override']['changed_options']==profile[1], 'Final profile Tcl delta differs')
    base_pin=joined['model_source_base_plan'];base=reader.json(base_pin['path'],base_pin)
    need(pin2(base_pin)==helper.BASE_PLAN_PIN and base['candidate_receipt']==plan['candidate_receipt']
        and [k for k in base['inputs']if base['inputs'][k]!=plan['inputs'][k]]==['run.tcl'],
        'Base-source proof/model inputs differ outside the declared Tcl')
    for row,wanted in((joined['producer'],helper.FINAL_SOURCE_JOIN_PRODUCER),
        (association['producer'],helper.FINAL_CLOSED_ASSOCIATION_PRODUCER)):
        need(row==wanted,'Current source/closed association producer differs');pin(reader,row)
    raw_pin=joined['candidate_raw_result'];raw=reader.json(raw_pin['path'],raw_pin)
    need(raw_pin==helper.FINAL_RAW_MODEL_PIN and joined['closed_model_completion']==helper.FINAL_MODEL_COMPLETION_PIN,
        'Actual selected run2 model records differ')
    metadata=reader.json(spec['model_metadata'])
    helper.source_scope(reader,candidate,metadata,raw,completion,omissions=spec['omitted_inputs'])
    need(joined['closed_model_actual24_numerical_ownership_and12phase_byte_reparse']is True
        and joined['no_compiled_production_module_excluded_from_join']is True
        and joined['actual_cache_production_source_joined']is True
        and joined['all_current_cache_production_sources_recompiled_in_closed_model']is True
        and joined['all_native_candidate_inputs_match_except_declared_Tcl']is True,
        'Complete V15 native/model/cache/source closure required')
    for key in('projection_shared16_sources','projection_shared16_geometry','projection_shared16_cancel_payload_erasure_claimed',
        'plaintext_direct4_result_lut_sources','plaintext_direct4_result_lut_component_scope',
        'fixed_add_helper_only_prior_component_context','current_cache_or_guard_composition_theorem',
        'old_cache325_proof_inherited','local_cache59_proof_inherited'):
        need(joined[key]==association[key]==candidate[key],'Current association scope differs: '+key)
    need(joined['current_cache_source_proof_context']==association['current_cache_source_proof_context']
        and joined['current_cache_source_proof_context']['sha256']=='a66b9078c52fc7ebfe96f651cdb0ba53480e5780547c98ff0c91cdfa5bb52c7b'
        and joined['source_join_grants_current_proof_or_theorem_credit']is False,
        'Current separately scoped source proof context required')
    pin(reader,joined['current_cache_source_proof_context'])
    ram=validate_v15_mapped_ram(reader,policy['mapped_mutable_ram'],policy,joined,spec,helper)
    return dict(V15_cache_shared16_direct4_source_join_rechecked=True,
        current_cache_proof_scope_must_be_replayed_separately=True,**ram,
        source_expected_multiply_roles_are_not_native_measurements=True)
