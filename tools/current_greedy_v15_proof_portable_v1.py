"""Associate one closed compact-prefix source proof with exact V15 source inputs only.

No proof, model, compiler, native, device or imported helper is executed.
The actual Root byte review and completion must bind the same closed results.
"""
import hashlib
import json
from pathlib import PurePosixPath as Path

ROOT = Path('/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-greedy-speed')
DRAFT_SOURCE_FINALIZED = True
FINAL_CACHE_ASSOCIATION_PIN = {'bytes': 447146, 'path': '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-greedy-speed/evidence/protected-cache-joint-proof-source-association-v15-compact-prefix.json', 'sha256': 'a66b9078c52fc7ebfe96f651cdb0ba53480e5780547c98ff0c91cdfa5bb52c7b'}
FINAL_DECLARED_OMISSIONS = {'/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-greedy-speed/build/native-kv-protected-v15-compact-prefix-p3r0-rep0-maxfan23-20261025-r1/input/project/official/ddr3_memory_interface.v': {'bytes': 2238123, 'sha256': 'd7cae5a16467ca35ee3f95411537344ae3702e1dba86a06571530e3dd0180c57'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-greedy-speed/build/native-kv-protected-v15-compact-prefix-p3r0-rep0-maxfan23-20261025-r1/input/project/official/gowin_pll.v': {'bytes': 992, 'sha256': '982ca6387f42086e88b4c858490eb00954a80a3284e0f07d959311d0975d7536'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-greedy-speed/build/native-kv-protected-v15-compact-prefix-p3r0-rep0-maxfan23-20261025-r1/input/project/official/gowin_pll_mod.v': {'bytes': 6081, 'sha256': '07398632b56749dbe52f6e5d739a526c7ca5e71c4060c7d062a64dada6e1a953'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-greedy-speed/build/native-kv-protected-v15-compact-prefix-p3r0-rep0-maxfan23-20261025-r1/input/project/official/pll_init.v': {'bytes': 6458, 'sha256': '502436115e507453e2c139a073f5b56484421311ef57088ce1a16140347957f5'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-greedy-speed/build/native-kv-protected-v15-compact-prefix-p3r0-rep0-maxfan23-20261025-r1/project/official/ddr3_memory_interface.v': {'bytes': 2238123, 'sha256': 'd7cae5a16467ca35ee3f95411537344ae3702e1dba86a06571530e3dd0180c57'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-greedy-speed/build/native-kv-protected-v15-compact-prefix-p3r0-rep0-maxfan23-20261025-r1/project/official/gowin_pll.v': {'bytes': 992, 'sha256': '982ca6387f42086e88b4c858490eb00954a80a3284e0f07d959311d0975d7536'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-greedy-speed/build/native-kv-protected-v15-compact-prefix-p3r0-rep0-maxfan23-20261025-r1/project/official/gowin_pll_mod.v': {'bytes': 6081, 'sha256': '07398632b56749dbe52f6e5d739a526c7ca5e71c4060c7d062a64dada6e1a953'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-greedy-speed/build/native-kv-protected-v15-compact-prefix-p3r0-rep0-maxfan23-20261025-r1/project/official/pll_init.v': {'bytes': 6458, 'sha256': '502436115e507453e2c139a073f5b56484421311ef57088ce1a16140347957f5'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-stochastic/variant/long-context-v8-sha-two-round/project/official/ddr3_memory_interface.v': {'bytes': 2238123, 'sha256': 'd7cae5a16467ca35ee3f95411537344ae3702e1dba86a06571530e3dd0180c57'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-stochastic/variant/long-context-v8-sha-two-round/project/official/gowin_pll.v': {'bytes': 992, 'sha256': '982ca6387f42086e88b4c858490eb00954a80a3284e0f07d959311d0975d7536'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-stochastic/variant/long-context-v8-sha-two-round/project/official/gowin_pll_mod.v': {'bytes': 6081, 'sha256': '07398632b56749dbe52f6e5d739a526c7ca5e71c4060c7d062a64dada6e1a953'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-stochastic/variant/long-context-v8-sha-two-round/project/official/pll_init.v': {'bytes': 6458, 'sha256': '502436115e507453e2c139a073f5b56484421311ef57088ce1a16140347957f5'}, '/Volumes/GowinIDE/GowinIDE.app/Contents/Resources/Gowin_EDA/IDE/simlib/gw5a/prim_sim.v': {'bytes': 709304, 'sha256': 'a5c5193b4b1cd1d86084e2c3a6a3d15d3fbacb931faa6cd08aa8c9c793fa37bd'}, '/opt/homebrew/Caskroom/cvc5/1.3.1/cvc5-macOS-arm64-static/bin/cvc5': {'bytes': 21099528, 'sha256': '6b93983220a5aefe7ff80238b0312274aa6c51e442e8adbdc00f47979adc60a8'}, '/opt/homebrew/Cellar/icarus-verilog/13.0/bin/iverilog': {'bytes': 92776, 'sha256': '5df81b269e1ff2c965dd00ad5a8071ca17717f416003b3661a18b2dde430e73c'}, '/opt/homebrew/Cellar/icarus-verilog/13.0/bin/vvp': {'bytes': 1231008, 'sha256': '1a9bdf1f40102f64f015514f5069f99a5dd9f9f38de343743ef4c169fb358392'}, '/opt/homebrew/Cellar/yosys/0.68/bin/yosys': {'bytes': 19221008, 'sha256': 'f59e100c4df830cf7898bc69da624225f15c25e09b1c5747c9b510a15a7a69f5'}, '/opt/homebrew/Cellar/z3/4.14.1/bin/z3': {'bytes': 15715120, 'sha256': 'ea69d1d234e0060fd480bf9b21a51f62244ed642ed2469d4373306e6e8ab6102'}}
LABELS = ('positive', 'negative-lost-clear', 'negative-raw-read-bypass')
CACHE = 'project/fpga/token_only_model0_ddr_board1/context2048_gowin_portability0/rtl/board1_context2048_atomic_kv_typed_clear_consistent.sv'
CACHE_SHA = 'a41a61dd6a1a585adc6aaa3f36643a05046c98ed9350187d96c8dce7a5f79af7'
FALSE_FLAGS = ('old_cache325_proof_inherited', 'local_cache59_proof_inherited',
               'current_cache_or_guard_composition_theorem')
EXPECTED = {
    'completion': (40321, '5d23d90c26325824a1b6d52a6d22ad0377a61a1ce6b12d89a183762ff5edcdee'),
    'root_byte_review': (3920, 'fc6b905d667a3b147031077f10622e1d4323c2b0ae69b5bd3d917ead32b870e0'),
    'candidate': (92708, 'a49d5ab7f1e6f024effd53ce4258a7278f3f2d94bd71bef2a0a11a5de109176b'),
    'native_source_plan': (43516, '7f78feaa4a3a9419bd7d3023b2f8cace2a6829a578362d347eff24d79b8d0684'),
}


def need(ok, message):
    if not ok:
        raise ValueError(message)


def identity(raw):
    return dict(bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest())


def validate_scope(completion, review, candidate, native, audit):
    """Pure closed-record scope checks; never a proof or admission callback."""
    need(completion['schema'] == 'protected-cache-compact-prefix-fresh-joint-proof-completion-v1'
         and completion['passed'] is True and completion['source_only'] is True,
         'Exact closed fresh compact-prefix source proof required')
    observed = completion['actual_elaboration']
    need(observed['assertions'] == 357
         and observed['concrete_memory_cells'] == 24 and observed['memory_bits'] == 1253376
         and observed['pending_arrays'] == 16 and observed['pending_depth'] == 8
         and observed['pending_width'] == 32 and observed['pending_payload_bits'] == 4096
         and observed['anyconst_cells'] == 5 and observed['selector_bits'] == 52
         and observed['assume_cells'] == 0,
         'Exact concrete source RAM/observer/assertion geometry required')
    inspected = completion['recorded_byte_inspection']
    need(inspected['canonical_solver_logs_rehashed_and_exact_answers_reparsed'] == 740
         and inspected['distinct_canonical_queries_rehashed'] == 370
         and inspected['positive_solver_results'] == 736
         and inspected['separate_negative_solver_results'] == 4
         and inspected['exact_answer_counts'] == {'sat': 6, 'unsat': 734}
         and inspected['new_solver_or_elaboration_or_auditor_call_in_receipt_creation'] is False,
         'Exact fresh canonical assertion/query census required; diagnostics add no credit')
    conclusions = completion['conclusions']
    for key in ('all_retained_R2_conclusions_freshly_reproved_in_current_joint_model',
                'old88_local_statement_text_retained', 'original085_assembled_mask_property_retained',
                'unconditional_LOAD_readmask0_retained',
                'initialized_staging_provenance_and_owned_visibility_only',
                'arbitrary_declared_private_scheduling_fault_inputs_and_SHA_replies',
                'reset_base_and_component_group_induction_exact_frozen_framework',
                'source_projected_parent_reset_CLEAR_reply_expression_safety'):
        need(conclusions[key] is True, 'Fresh retained source conclusion missing: ' + key)
    need(conclusions['payload_cutpoints'] == []
         and conclusions['new_assumptions_or_fault_waivers'] is False
         and conclusions['old_R2_CFC_guard_or_cache_results_assumed'] is False,
         'No old proof, payload cut, assumption or fault waiver replaces fresh obligations')
    need(conclusions['new_terminal_independent_source_conclusions'] == [
         'f_stage_active || pending_persisted_q -> pending_layer_q<6 && pending_position_q<2048',
         'f_stage_active || pending_persisted_q -> pending_position_q==committed_prefix_q[pending_layer_q]',
         'ST_STAGE || ((ST_WRITE_REQ || ST_WRITE_WAIT)&&!write_aborted_q) -> f_stage_active'],
         'Exact freshly proved terminal-independent descriptor/phase conclusions required')
    need(candidate['cache_compact_prefix_component_scope']['source_geometry'] == dict(
        array_depth=8, array_width=32, coordinates_per_head=64, distributed_arrays=16,
        kv_heads=2, pending_payload_bits=4096, row_bits=2064, scalar_bits=16,
        stage_coordinates=128, typed_word_bits=256, typed_words_per_head=9),
        'Current cache geometry differs')
    for key in ('old325_proof_inherited', 'local59_proof_inherited', 'old_R2_or_CFC_result_inherited',
                'uninitialized_physical_state_theorem', 'payload_erasure_theorem',
                'SHA_or_cryptographic_theorem', 'numerical_theorem',
                'old_new_cache_full_equivalence_theorem', 'guard_security_composition_theorem',
                'liveness_theorem', 'actual_attention_arithmetic_elaborated',
                'native_or_mapped_memory_or_full_model_qualification', 'whole_machine_theorem',
                'complete_timing_signoff', 'board_authority', 'production_variant_modified'):
        need(completion['scope_limits'][key] is False, 'Proof scope overclaimed: ' + key)
    need(completion['scope_limits']['current_candidate_or_native_source_association'] is None
         and completion['scope_limits']['current_release_admission'] is None,
         'Completion alone cannot confer current source/native/board admission')
    need(review['schema'] == 'root-cache-compact-prefix-joint-proof-closed-byte-inspection-v1'
         and review['passed'] is True, 'Exact actual Root byte review required')
    for key in ('actual357_assertion_positive_and_both_sensitivity_results_closed',
                'all10_origins_byte_join_current93_input_native_source_plan',
                'all59_original_source_tool_plan_pins_verified',
                'all740_raw_solver_answers_and_query_log_hashes_independently_reparsed',
                'exact_original_and_copied_plans', 'audit_shared_projection_generator_disclosed',
                'terminal_independent_descriptor_and_phase_conclusions_included',
                'real_pending_RAM_and_arbitrary_initial_payload_preserved'):
        need(review[key] is True, 'Root byte-review obligation missing: ' + key)
    for key in ('independent_projection_implementation_review',
                'native_or_model_or_board_qualification_conferred',
                'added_whole_image_or_erasure_or_numerical_or_crypto_theorem',
                'old_R2_or_CFC_or_failed_V1_credit'):
        need(review[key] is False, 'Root byte review overclaimed: ' + key)
    need(audit['schema'] == 'cache-pending-ram-joint-proof-audit-v1'
         and audit['passed'] is True and audit['old_results_assumed'] is False
         and audit['payload_cutpoints'] == []
         and audit['projection_generator_shared_with_runner'] is True
         and audit['independent_projection_review'] is False,
         'Shared projection generator and exact audit scope required')
    need(completion['audit_scope']['projection_generator_shared_with_runner'] is True
         and completion['audit_scope']['independent_projection_implementation_review'] is False
         and completion['audit_scope']['source_and_tool_end_capture_rows'] == 59,
         'Projection-audit disclosure or source lifetime census differs')
    need(candidate['schema'] == 'protected-cache-compact-prefix-source-candidate-v15'
         and native['schema'] == 'greedy-variant-native-input-plan-v1'
         and native['variant'] == 'kv-protected' and len(native['inputs']) == 93,
         'Exact current V15 source epoch required')
    need(candidate['changed_from_v14'] == [CACHE]
         and candidate['all_other_native_input_bytes_unchanged_count'] == 92
         and candidate['native_source_sha256_after'][CACHE] == CACHE_SHA
         and candidate['old_R2_or_CFC_result_inherited'] is False,
         'Only the selected current cache transition is associated')
    need(candidate['owned_inputs'] == 89 and candidate['planned_native_inputs'] == 93
         and len(candidate['vendor_original_paths']) == 4,
         'Complete89-owned/four-vendor input census required')
    for key in FALSE_FLAGS:
        need(candidate[key] is False, 'Existing candidate theorem flag must stay false: ' + key)
    for key in ('inherited_model_pass', 'inherited_native_pass', 'inherited_proof_pass',
                'model_passed', 'native_passed', 'physical_passed', 'proof_passed',
                'qualification_inherited'):
        need(candidate[key] is False, 'Source association cannot grant qualification: ' + key)
    need(candidate['fresh_cache_source_proof_association'] is None,
         'Immutable source candidate must not acquire an association in place')
    for key in ('actual_positive', 'actual_lost_clear', 'actual_raw_read_bypass', 'actual_frozen_auditor'):
        need(completion['calls'][key] == 1, 'Exact once campaign stage required')
    need(completion['calls']['retries'] == 0
         and completion['calls']['additional_unplanned_solver_or_elaboration'] == 0
         and completion['calls']['source_variant_native_model_device_PUBLIC'] is False,
         'Only the completed frozen once source campaign is associated')


def check_answer(row, raw, expected):
    need([line.strip() for line in raw.decode().splitlines() if line.strip()]
         == row['answers'] == row['expected'] == expected
         and row['passed'] is True and row['exit'] == 0,
         'Exact closed solver answer required')


def validate_contract_pins(contract):
    for key, (size, digest) in EXPECTED.items():
        row = contract[key]
        need(set(row) == {'path', 'bytes', 'sha256'}
             and row['bytes'] == size and row['sha256'] == digest,
             'Exact actual V15/compact-prefix record required: ' + key)
    need(contract['root_byte_review']['path'] == str(ROOT / 'evidence/root-cache-compact-prefix-joint-proof-closed-byte-inspection-v1.json'),
         'An alternate Root review is not accepted')


def validate_pointer_joins(completion, review, contract, native):
    need(native['candidate_receipt'] == contract['candidate']
         and review['native_source_plan'] == contract['native_source_plan'],
         'Root/native/candidate source pointers differ')
    need(review['audit'] == completion['audit']
         and review['plan'] == completion['plan'], 'Root review binds different proof records')
    need({key: completion['actual_execution_details'][key]['finished'] for key in LABELS}
         == review['actual_positive_and_controls'] == contract['results'],
         'Root review/completion must name the same positive and controls')


def replay_cache(reader,contract_path,contract_sha,review_path,review_sha,native_inputs,omissions):
    """Read and rehash bytes only; explicit reviewed contract required."""
    seen={};omitted={}
    def read(path,wanted=None):
        path=Path(path);origin=str(path)
        need(path.is_absolute()and '..'not in path.parts,'Canonical original provenance path required')
        if origin in omissions:
            need(wanted is not None and {k:wanted[k]for k in('bytes','sha256')}==
                {k:omissions[origin][k]for k in('bytes','sha256')},'Exact declared omission required')
            omitted[origin]=omissions[origin];return b''
        raw=reader.read(origin,wanted);fact=identity(raw)
        need(origin not in seen or seen[origin]==fact,'Conflicting original input identity')
        seen[origin]=fact;return raw
    def record(wanted):
        need(set(wanted) == {'path', 'bytes', 'sha256'}, 'Exact three-key record pin required')
        return json.loads(read(wanted['path'], wanted))
    raw = read(contract_path)
    need(identity(raw)['sha256'] == contract_sha, 'Explicit reviewed contract SHA required')
    contract = json.loads(raw)
    need(contract['schema'] == 'protected-v15-cache-joint-proof-source-association-contract-v1',
         'Exact source association contract required')
    need(contract['execution_authorized_by_contract'] is False,
         'Preparation contract cannot itself authorize a callback')
    validate_contract_pins(contract)
    need(contract['producer']['path']==str(ROOT/'tools/protected_cache_joint_proof_source_association_v15.py')
         and contract['producer']['sha256']=='c116e07ca47eac6184fb0af226729edf93cad43065ddb4348c9ab3b6d1fbde2c',
         'Exact original source-association producer required')
    read(contract['producer']['path'],contract['producer'])
    need(str(review_path) == contract['root_byte_review']['path']
         and review_sha == contract['root_byte_review']['sha256'],
         'Actual Root byte-review identity required')
    review = record(contract['root_byte_review'])
    completion = record(contract['completion'])
    candidate = record(contract['candidate'])
    native = record(contract['native_source_plan'])
    audit = record(completion['audit'])
    validate_scope(completion, review, candidate, native, audit)
    validate_pointer_joins(completion, review, contract, native)
    need(native['candidate'] == candidate['candidate'], 'Native/candidate source directory differs')
    plan = record(completion['plan'])
    need(completion['actual_elaboration']['component_assertions'] == plan['source_assertion_counts']
         and sum(plan['source_assertion_counts'].values()) == 357,
         'Fresh source assertion/component counts differ')
    package = Path(plan['source_package'])
    need(package == Path(contract['proof_package']), 'Exact compact-prefix source package required')
    manifest = record(completion['manifest'])
    need(identity(read(package / 'MANIFEST.json')) == plan['source_manifest'],
         'Plan source-manifest pin differs')
    for relative, wanted in manifest['files'].items():
        need(not Path(relative).is_absolute() and '..' not in Path(relative).parts,
             'Safe source-package member required')
        read(package / relative, wanted)
    for role, filename in (('driver', 'run_parent.py'), ('auditor', 'audit_parent.py'),
                           ('extractor', 'parent_model.py')):
        need(contract['proof_producers'][role] == completion['producers'][filename],
             'Completion/contract producer identity differs')
    for wanted in completion['producers'].values():
        read(wanted['path'], wanted)
    for wanted in contract['proof_producers'].values():
        read(wanted['path'], wanted)
    for key in ('preparation', 'authorization', 'guard_dependencies'):
        record(completion[key])
    diagnostic_pins = 0
    for item in completion['recorded_byte_inspection']['automatic_diagnostic_query_and_log_pins'].values():
        # Existing frozen-driver diagnostics are authenticated only as data.
        # They add no canonical proof-query count or execution authority.
        for key in ('query', 'log'):
            wanted = item[key]; read(wanted['path'], wanted); diagnostic_pins += 1
    origins = record(review['source_origins'])
    need(origins['sources'] == completion['all10_source_origins'] and len(origins['sources']) == 10,
         'Exact ten proof-production/interface origins required')
    joins = {}
    need(set(native['inputs']) == set(candidate['native_source_sha256_after']), 'All93 source input names required')
    for name, row in native['inputs'].items():
        need(not Path(name).is_absolute() and '..' not in Path(name).parts,
             'Safe native source member required')
        if not row['vendor']:need(row['path']not in omissions,'Owned proof-source input cannot be omitted')
        read(row['path'], row)
        need(row['sha256'] == candidate['native_source_sha256_after'][name], 'Native source hash differs')
        if row['vendor']:
            need(set(row) == {'path', 'bytes', 'sha256', 'vendor'} and row['vendor'] is True,
                 'Actual four-key vendor row required')
        else:
            need(row['path'] == str(Path(candidate['candidate']) / name)
                 and {key: row[key] for key in ('bytes', 'sha256')} == candidate['owned_files_after'][name],
                 'Owned native source identity/path differs')
    need(sum(row['vendor'] is True for row in native['inputs'].values()) == 4,
         'Exactly four original vendor inputs required')
    for relative, origin in origins['sources'].items():
        name = Path(relative).relative_to('production').as_posix()
        current = native['inputs'][name]
        original_bytes = read(origin['path'], origin)
        copied_bytes = read(package / relative, {key: origin[key] for key in ('bytes', 'sha256')})
        need(copied_bytes == original_bytes, 'Proof package copy differs from its pinned source origin')
        need(current['vendor'] is False and {key: current[key] for key in ('bytes', 'sha256')}
             == {key: origin[key] for key in ('bytes', 'sha256')}, 'Proof/current source bytes differ')
        joins[name] = dict(proof_origin=origin,
            proof_package=dict(path=str(package / relative), **identity(read(package / relative))),
            current_native_input={key: current[key] for key in ('path', 'bytes', 'sha256')})
    need(joins[CACHE]['current_native_input'] == candidate['cache_compact_prefix_source'], 'Current cache pointer differs')
    for name,row in joins.items():
        need(name in native_inputs and native_inputs[name]['vendor']is False
             and {k:native_inputs[name][k]for k in('bytes','sha256')}==
                 {k:row['current_native_input'][k]for k in('bytes','sha256')},
             'Actual selected native RTL differs from the ten proof-interface source origins')
    checked_answers = 0
    for label in LABELS:
        stage = completion['actual_execution_details'][label]; finished = record(stage['finished'])
        inputs = record(stage['inputs']); copied = read(stage['copied_plan']['path'], stage['copied_plan'])
        need(copied == read(completion['plan']['path'], completion['plan']),
             'Copied/original proof PLAN differs')
        need(finished['inputs_sha256'] == identity(read(stage['inputs']['path']))['sha256']
             and finished['passed'] is True and finished['assertions'] == 357
             and finished['source_unchanged'] is True
             and finished['original_and_copied_plan_unchanged'] is True,
             'Closed proof result/input binding differs')
        need(finished['production_proof'] == (label == 'positive')
             and finished['expected_negative_detected'] == (label != 'positive'),
             'Positive/negative roles cannot be relabelled')
        need(len(finished['solver_results']) == (736 if label == 'positive' else 2),
             'Complete fresh solver result set required')
        directory = Path(stage['finished']['path']).parent
        for relative, wanted in inputs['files'].items():
            need(Path(relative).name == relative, 'Flat compiled proof input expected')
            read(directory / relative, wanted)
        need(inputs['source_snapshot_before'] == finished['source_snapshot_after'], 'Proof input lifetime differs')
        for path, wanted in finished['source_snapshot_after'].items():
            read(path, wanted)
        for name, row in finished['solver_results'].items():
            solver, query = name.split('-', 1)
            need(solver in ('z3', 'cvc5') and Path(query).name == query, 'Exact solver/query role required')
            log = read(directory / (name + '.log'))
            raw_query = read(directory / (query + '.smt2'))
            need(identity(log)['sha256'] == row['log_sha256']
                 and identity(raw_query)['sha256'] == row['query_sha256'], 'Raw proof evidence changed')
            expected = ['sat'] if label != 'positive' or query == 'reset-witness' else ['unsat']
            check_answer(row, log, expected)
            checked_answers += 1
        report = audit['reports'][label]
        need(report['assertions'] == 357 and report['byte_identical_elaboration'] is True
             and report['queries_checked'] == (736 if label == 'positive' else 2)
             and report['observers']['memory_bits'] == 1253376
             and not report['observers']['production_signal_hits']
             and not report['observers']['production_memory_sink_hits'], 'Actual audit scope differs')
        for name in ('elaborated.json', 'elaborated.il', 'design.smt2'):
            need(read(directory / name) == read(Path(completion['audit']['path']).parent / label / name),
                 'Original/replayed elaboration bytes differ')
    need(checked_answers == 740, 'All740 exact raw solver answers required')
    for path,wanted in seen.items():need(identity(reader.read(path,wanted))==wanted,'Consumed portable input changed')
    result = dict(schema='protected-v15-cache-joint-proof-source-association-v1', passed=True,
        producer=contract['producer'],
        contract=dict(path=str(contract_path), **identity(raw)), root_byte_review=contract['root_byte_review'],
        proof_completion=contract['completion'], source_candidate=contract['candidate'],
        native_source_plan=contract['native_source_plan'], proof_source_joins=joins,
        matched_production_interface_sources=10, source_native_inputs_rehashed=89,
        omitted_inputs_declared_without_byte_rehash=omitted,
        actual_assertions_including_support=357, positive_solver_checks=736,
        sensitivity_solver_checks=4, canonical_raw_solver_checks=740,
        diagnostic_data_pins_rehashed_without_proof_credit=diagnostic_pins, initialized_staging_provenance_and_owned_visibility_scope=True,
        arbitrary_private_scheduling_and_SHA_replies=True, projection_generator_shared_with_runner=True,
        independent_projection_implementation_review=False, old325_or_local59_or_failedV1_credit=False, old_R2_or_CFC_or_V14_qualification_inherited=False,
        old_cache325_proof_inherited=False, local_cache59_proof_inherited=False,
        current_cache_or_guard_composition_theorem=False, candidate_false_flags_preserved=True,
        numerical_crypto_erasure_mapped_native_model_whole_image_theorem=False,
        native_model_policy_or_board_authority=False, solver_elaboration_or_auditor_reexecuted=False,
        hardware_access=False, source_inputs_unchanged=True, consumed_inputs=seen,
        current_release_admission=None)
    return result


def validate_attention_context(reader,spec,native_inputs,query_recheck):
    need(callable(query_recheck),'Reviewed original query parser callback required')
    joined=reader.role('source_join');context=joined['original_attention_source_context']
    completion_pin=context['original_V5_completion']
    need({k:completion_pin[k]for k in('bytes','sha256')}==dict(bytes=6999,
        sha256='9ae6ba22c6039800a5b9b816b0519b638973f0d54957c4871e57ff943f3dd716'),
        'Exact original V5 attention completion required')
    completion=reader.json(completion_pin['path'],completion_pin)
    need(completion['schema']=='protected-coordinate-v5-fresh-attention-completion-v1'
        and completion['passed']is True and(completion['assertions'],completion['queries'],completion['unknowns'])==(34,72,0)
        and completion['retained_abstract_output_count']==27
        and completion['whole_machine_refinement']is False and completion['numerical_attention_theorem']is False,
        'Original34/72 isolated nonnumerical attention scope required')
    plan=reader.json(completion['plan']['path'],completion['plan'])
    proof_dir=str(Path(completion['proof']['path']).parent);audit_dir=str(Path(completion['audit']['path']).parent)
    need(spec==dict(proof_directory=proof_dir,audit_directory=audit_dir)
        and plan['assumptions']==[]and plan['added_internal_cuts']==[],
        'Exact original V5 proof/audit boundaries required')
    manifest=reader.json(plan['source_package_manifest']['path'],plan['source_package_manifest'])
    need(len(manifest['files'])==13 and len(plan['prepared_files'])==20,'Original13/20 source census differs')
    for name,wanted in manifest['files'].items():reader.read(str(Path(plan['source_package'])/name),wanted)
    for name,wanted in plan['prepared_files'].items():reader.read(str(Path(proof_dir)/name),wanted)
    joins=context['source_joins'];need(len(joins)==6 and set(joins)==set(completion['actual_source_origins']),
        'Exact six isolated source inputs required')
    for name,row in joins.items():
        need(name in native_inputs and row['byte_identical']is True
            and row['original_v5']==completion['actual_source_origins'][name], 'Original/current source origin differs')
        a=reader.read(row['original_v5']['path'],row['original_v5']);b=reader.read(row['selected_v15']['path'],row['selected_v15'])
        need(a==b and identity(a)=={k:native_inputs[name][k]for k in('bytes','sha256')},
            'Current selected RTL differs from isolated attention proof source')
    actual=query_recheck(reader,proof_dir,34);inputs=actual.pop('inputs')
    need(actual['passed']is True and(actual['assertions'],actual['queries'],actual['unknowns'])==(34,72,0)
        and inputs['source_origins']=={'hardware/'+name:native_inputs[name]['sha256']for name in joins}
        and len(inputs['abstract_children'])==8 and len(actual['arbitrary_child_replies'])==27,
        'Original raw queries/source/abstract reply boundaries differ')
    audit=reader.json(completion['audit']['path'],completion['audit'])
    need(audit['passed']is True and audit['assertions']==34 and audit['queries_checked']==72
        and actual['observer']==completion['observer']==audit['observers']
        and actual['arbitrary_child_replies']==completion['arbitrary_child_replies']==audit['arbitrary_child_replies']
        and audit['byte_identical_elaboration']is True and audit['whole_machine_refinement']is False,
        'Original raw proof/audit/observer relation differs')
    for name in('elaborated.json','elaborated.il','design.smt2'):
        need(reader.read(str(Path(proof_dir)/name))==reader.read(str(Path(audit_dir)/name)),
            'Original proof/audit elaboration bytes differ')
    datapath=context['identical_production_datapath']
    a=reader.read(datapath['original_v5']['path'],datapath['original_v5'])
    b=reader.read(datapath['selected_v15']['path'],datapath['selected_v15'])
    member='project/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_semantic_datapath.sv'
    need(a==b and identity(b)=={k:native_inputs[member][k]for k in('bytes','sha256')}
        and b.count(b'board1_context2048_attention u_attention (')==1,
        'Unchanged original/current production attention instantiation required')
    return dict(passed=True,assertions=34,queries=72,unknowns=0,isolated_sources=6,
        retained_abstract_outputs=27,additional_assertion_credit=0,counts_nonadditive=True,
        numerical_or_concrete_memory_or_whole_machine_theorem=False)


def validate_v15_proofs(reader,association,spec,native_inputs,*,query_recheck):
    need(DRAFT_SOURCE_FINALIZED and type(FINAL_CACHE_ASSOCIATION_PIN)is dict and type(FINAL_DECLARED_OMISSIONS)is dict,
        'UNFINALIZED V15 proof callback: actual selected association role pin pending')
    need(reader.pin(reader.data['roles']['source_scoped_proofs'])==FINAL_CACHE_ASSOCIATION_PIN
        and reader.json(FINAL_CACHE_ASSOCIATION_PIN['path'],FINAL_CACHE_ASSOCIATION_PIN)==association
        and FINAL_CACHE_ASSOCIATION_PIN['sha256']=='a66b9078c52fc7ebfe96f651cdb0ba53480e5780547c98ff0c91cdfa5bb52c7b',
        'Exact closed current cache source-proof association required')
    need(spec['omitted_inputs']==FINAL_DECLARED_OMISSIONS,'Only source-frozen declared proof/tool omissions accepted')
    contract=association['contract'];review=association['root_byte_review']
    cache=replay_cache(reader,contract['path'],contract['sha256'],review['path'],review['sha256'],
        native_inputs,spec['omitted_inputs'])
    attention=validate_attention_context(reader,spec['attention'],native_inputs,query_recheck)
    return dict(passed=True,cache=cache,attention=attention,counts_nonadditive=True,
        source_proof_scope_only=True,native_or_board_authority=False,
        whole_machine_or_numerical_or_crypto_or_erasure_theorem=False,
        solver_elaboration_or_auditor_reexecuted=False)
