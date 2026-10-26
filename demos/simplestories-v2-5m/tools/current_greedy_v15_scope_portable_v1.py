"""Pure authenticated-reader scope joins for the V15 compact-prefix source epoch.

No captured source is imported. Actual future completion and producer contracts
must be frozen in this source before any V15 stage can pass.
"""
import hashlib
import json
from pathlib import PurePosixPath

DRAFT_SOURCE_FINALIZED = True
FINAL_MODEL_COMPLETION_PIN = {'bytes': 43176, 'path': '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-greedy-speed/evidence/protected-model-complete-v15-compact-prefix.json', 'sha256': 'daed383a63cb8d7dc27d1620f0f7403f9533e499f087949a8ac9f26a2179c467'}
FINAL_RAW_MODEL_PIN = {'bytes': 52356, 'path': '/Users/halcrow/Documents/GitHub/pause/inference-only/tang-greedy-speed/build/protected-model-v15-compact-prefix/candidate-run2/FINISHED.json', 'sha256': '410285821631b60ff7675c29afbcf94476fcc25b75289900619a0760dcab280e'}
FINAL_SOURCE_JOIN_PRODUCER = {'bytes': 70287, 'path': '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-greedy-speed/tools/selected_v15_native_model_join_r4.py', 'sha256': '7178c0eecfcca1bfc05a190515aea37b9eb97a87be0347aca28f8c08285d01fb'}
FINAL_CLOSED_ASSOCIATION_PRODUCER = {'bytes': 11733, 'path': '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-greedy-speed/tools/selected_v15_closed_model_native_association_r3.py', 'sha256': 'f8b928db62ed594743f8b15825d3fbb9337daeeeed3bd756940c4944534330d1'}
FINAL_ROOT_GUARD_PRODUCER = {'path': '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-greedy-speed/tools/guarded_sram_trial_v15_compact_prefix_r3.py', 'bytes': 16435, 'sha256': 'db408994786bc20ceec2114436015923f5d39106f1bf41d00b8f92627e19168d'}
SELECTED_NATIVE_PROFILE_PIN = {'bytes': 45118, 'path': '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-greedy-speed/build/native-kv-protected-v15-compact-prefix-p3r0-rep0-maxfan23-20261025-r1/PLAN.json', 'sha256': '28723b986157535f4611f747e7bb30e6aeef9576abc1767b1d6b5744bd709f9a'}
FINAL_DECLARED_OMISSIONS = {'/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-greedy-speed/build/native-kv-protected-v15-compact-prefix-p3r0-rep0-maxfan23-20261025-r1/input/project/official/ddr3_memory_interface.v': {'bytes': 2238123, 'sha256': 'd7cae5a16467ca35ee3f95411537344ae3702e1dba86a06571530e3dd0180c57'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-greedy-speed/build/native-kv-protected-v15-compact-prefix-p3r0-rep0-maxfan23-20261025-r1/input/project/official/gowin_pll.v': {'bytes': 992, 'sha256': '982ca6387f42086e88b4c858490eb00954a80a3284e0f07d959311d0975d7536'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-greedy-speed/build/native-kv-protected-v15-compact-prefix-p3r0-rep0-maxfan23-20261025-r1/input/project/official/gowin_pll_mod.v': {'bytes': 6081, 'sha256': '07398632b56749dbe52f6e5d739a526c7ca5e71c4060c7d062a64dada6e1a953'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-greedy-speed/build/native-kv-protected-v15-compact-prefix-p3r0-rep0-maxfan23-20261025-r1/input/project/official/pll_init.v': {'bytes': 6458, 'sha256': '502436115e507453e2c139a073f5b56484421311ef57088ce1a16140347957f5'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-greedy-speed/build/native-kv-protected-v15-compact-prefix-p3r0-rep0-maxfan23-20261025-r1/project/official/ddr3_memory_interface.v': {'bytes': 2238123, 'sha256': 'd7cae5a16467ca35ee3f95411537344ae3702e1dba86a06571530e3dd0180c57'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-greedy-speed/build/native-kv-protected-v15-compact-prefix-p3r0-rep0-maxfan23-20261025-r1/project/official/gowin_pll.v': {'bytes': 992, 'sha256': '982ca6387f42086e88b4c858490eb00954a80a3284e0f07d959311d0975d7536'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-greedy-speed/build/native-kv-protected-v15-compact-prefix-p3r0-rep0-maxfan23-20261025-r1/project/official/gowin_pll_mod.v': {'bytes': 6081, 'sha256': '07398632b56749dbe52f6e5d739a526c7ca5e71c4060c7d062a64dada6e1a953'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-greedy-speed/build/native-kv-protected-v15-compact-prefix-p3r0-rep0-maxfan23-20261025-r1/project/official/pll_init.v': {'bytes': 6458, 'sha256': '502436115e507453e2c139a073f5b56484421311ef57088ce1a16140347957f5'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-stochastic/variant/long-context-v8-sha-two-round/project/official/ddr3_memory_interface.v': {'bytes': 2238123, 'sha256': 'd7cae5a16467ca35ee3f95411537344ae3702e1dba86a06571530e3dd0180c57'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-stochastic/variant/long-context-v8-sha-two-round/project/official/gowin_pll.v': {'bytes': 992, 'sha256': '982ca6387f42086e88b4c858490eb00954a80a3284e0f07d959311d0975d7536'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-stochastic/variant/long-context-v8-sha-two-round/project/official/gowin_pll_mod.v': {'bytes': 6081, 'sha256': '07398632b56749dbe52f6e5d739a526c7ca5e71c4060c7d062a64dada6e1a953'}, '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-stochastic/variant/long-context-v8-sha-two-round/project/official/pll_init.v': {'bytes': 6458, 'sha256': '502436115e507453e2c139a073f5b56484421311ef57088ce1a16140347957f5'}, '/Volumes/GowinIDE/GowinIDE.app/Contents/Resources/Gowin_EDA/IDE/simlib/gw5a/prim_sim.v': {'bytes': 709304, 'sha256': 'a5c5193b4b1cd1d86084e2c3a6a3d15d3fbacb931faa6cd08aa8c9c793fa37bd'}, '/opt/homebrew/Caskroom/cvc5/1.3.1/cvc5-macOS-arm64-static/bin/cvc5': {'bytes': 21099528, 'sha256': '6b93983220a5aefe7ff80238b0312274aa6c51e442e8adbdc00f47979adc60a8'}, '/opt/homebrew/Cellar/icarus-verilog/13.0/bin/iverilog': {'bytes': 92776, 'sha256': '5df81b269e1ff2c965dd00ad5a8071ca17717f416003b3661a18b2dde430e73c'}, '/opt/homebrew/Cellar/icarus-verilog/13.0/bin/vvp': {'bytes': 1231008, 'sha256': '1a9bdf1f40102f64f015514f5069f99a5dd9f9f38de343743ef4c169fb358392'}, '/opt/homebrew/Cellar/yosys/0.68/bin/yosys': {'bytes': 19221008, 'sha256': 'f59e100c4df830cf7898bc69da624225f15c25e09b1c5747c9b510a15a7a69f5'}, '/opt/homebrew/Cellar/z3/4.14.1/bin/z3': {'bytes': 15715120, 'sha256': 'ea69d1d234e0060fd480bf9b21a51f62244ed642ed2469d4373306e6e8ab6102'}}
CANDIDATE_PIN=dict(bytes=92708,sha256='a49d5ab7f1e6f024effd53ce4258a7278f3f2d94bd71bef2a0a11a5de109176b')
BASE_PLAN_PIN=dict(bytes=43516,sha256='7f78feaa4a3a9419bd7d3023b2f8cace2a6829a578362d347eff24d79b8d0684')
PACKET_PIN=dict(bytes=200446,sha256='c15e6c0eb672d177348e7e755e9941337f393e1a524db428f78734e2b076ed36')
PROFILE_PINS={
 'cdce00d8d936e98e134e59eaabe9bf9c94b0345c8c81142e80b33aef5ea43dc4':(45165,['route_option:0->1']),
 '28723b986157535f4611f747e7bb30e6aeef9576abc1767b1d6b5744bd709f9a':(45118,['place_option:4->3'])}
CACHE='project/fpga/token_only_model0_ddr_board1/context2048_gowin_portability0/rtl/board1_context2048_atomic_kv_typed_clear_consistent.sv'
COMPONENT_PINS={
 'cache_compact_prefix_component_completion':dict(bytes=7824,sha256='64b917349313d4b948278ec1ac4879b9743576a653904aaeaca9c610c8d55a13'),
 'cache_compact_prefix_component_finite':dict(bytes=38681,sha256='3b317aa846646ec8c7c834a07631aa0801943c8859be3e4eb2a30087804b8b44'),
 'projection_shared16_finite_source_completion':dict(bytes=4083,sha256='f59456a474bb3950d166626eee6797083560bca4063be36fe09c72afc634e091'),
 'plaintext_direct4_result_lut_component_finite':dict(bytes=187719,sha256='933e20d42812ba25ae994d437151493fc3af8ab8220f55f08bb57a239d26075e')}
SHARED16=dict(tiles=4,physical_projection_lanes=4,physical_lanes_per_tile=1,logical_rows_per_tile=16,
    accumulator_contexts_per_multiplier=16,minimum_weight_accept_spacing_clocks=16)


def need(ok,message):
    if not ok:raise ValueError(message)
def identity(raw):return dict(bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest())
def pin2(row):return {k:row[k]for k in('bytes','sha256')}
def exact_pin(row):
    return type(row)is dict and set(row)=={'path','bytes','sha256'}and type(row['path'])is str

def finalized():
    need(DRAFT_SOURCE_FINALIZED and type(FINAL_DECLARED_OMISSIONS)is dict and all(exact_pin(x)for x in(FINAL_MODEL_COMPLETION_PIN,FINAL_RAW_MODEL_PIN,
        FINAL_SOURCE_JOIN_PRODUCER,FINAL_CLOSED_ASSOCIATION_PRODUCER,FINAL_ROOT_GUARD_PRODUCER,SELECTED_NATIVE_PROFILE_PIN)),
        'UNFINALIZED V15 portable scope: actual completion/profile/producer source contract pending')
    need(SELECTED_NATIVE_PROFILE_PIN['sha256']in PROFILE_PINS
        and SELECTED_NATIVE_PROFILE_PIN['bytes']==PROFILE_PINS[SELECTED_NATIVE_PROFILE_PIN['sha256']][0],
        'Only exact reviewed P4R1 or P3R0 source profile can be selected')

def root_guard_identity(reader,origin,native_guard_sha256):
    """Join the source-frozen guard pin to actual physical bytes/epoch registry."""
    finalized()
    need(reader.pin(origin)==FINAL_ROOT_GUARD_PRODUCER
        and native_guard_sha256==FINAL_ROOT_GUARD_PRODUCER['sha256']
        and identity(reader.read(origin,FINAL_ROOT_GUARD_PRODUCER))==pin2(FINAL_ROOT_GUARD_PRODUCER),
        'Actual protected physical guard differs from reviewed scope/native epoch producer')
    return dict(protected_guard_identity_reparsed=True,
        protected_guard_producer=FINAL_ROOT_GUARD_PRODUCER)

def rehash_tree(reader,value,omissions=None):
    omissions={}if omissions is None else omissions
    if type(value)is dict:
        if {'path','bytes','sha256'}<=set(value):
            origin=value['path'];wanted=pin2(value)
            if origin in omissions:need(wanted==pin2(omissions[origin]),'Declared omitted source differs')
            else:reader.read(origin,{k:value[k]for k in('path','bytes','sha256')})
        for child in value.values():rehash_tree(reader,child,omissions)
    elif type(value)is list:
        for child in value:rehash_tree(reader,child,omissions)

def source_scope(reader,candidate,metadata,raw,completion,*,omissions=None):
    finalized();roles=reader.data['roles']
    need(omissions==FINAL_DECLARED_OMISSIONS,'Only source-reviewed exact proprietary/tool omission identities are accepted')
    need(reader.variant=='kv-protected'and identity(reader.read(roles['source_candidate']))==CANDIDATE_PIN,
        'Exact current V15 source candidate required')
    need(identity(reader.read(FINAL_MODEL_COMPLETION_PIN['path'],FINAL_MODEL_COMPLETION_PIN))==pin2(FINAL_MODEL_COMPLETION_PIN)
        and reader.json(FINAL_MODEL_COMPLETION_PIN['path'])==completion
        and reader.json(FINAL_RAW_MODEL_PIN['path'],FINAL_RAW_MODEL_PIN)==raw,
        'Exact actual complete run2 model records required')
    need(candidate['schema']=='protected-cache-compact-prefix-source-candidate-v15'
        and completion['schema']=='protected-cache-compact-prefix-paired-model-join-v15'
        and raw['schema']=='greedy-speed-candidate-only-model-result-v15-compact-prefix'
        and completion['passed']is raw['passed']is raw['complete']is True,
        'V15 schemas/closed results required; old results cannot be relabelled')
    need(completion['selected_candidate']=='variants/kv-protected-v15-compact-prefix'
        and completion['source_candidate']==reader.pin(roles['source_candidate'])
        and pin2(completion['selected_packet'])==PACKET_PIN
        and identity(reader.read(completion['candidate_result'].get('path',FINAL_RAW_MODEL_PIN['path'])))==pin2(FINAL_RAW_MODEL_PIN)
        and(completion['new_candidate_cases_executed'],completion['old_control_cases_reused'],completion['paired_cases_covered'],
            completion['paired_heads'],completion['paired_head_rows'])==(12,12,24,60,241140)
        and(raw['case_count'],raw['heads'],raw['head_rows_compared'])==(12,30,120570),
        'Exact current run2 full model/old-control scope required')
    need(pin2(metadata['native_plan']['candidate_receipt'])==CANDIDATE_PIN
        and metadata['native_plan_sha256']==BASE_PLAN_PIN['sha256']
        and metadata['production_compile_order']==list(dict.fromkeys(metadata['production_compile_order']))
        and len(metadata['production_compile_order'])==66
        and metadata['candidate_kind_major']is metadata['control_kind_major']is False,
        'Actual unchanged base-source packet and complete66 source order required')
    phase=candidate['coordinate_phase_observer']
    need(phase==metadata['coordinate_phase_observer']==raw['coordinate_phase_observer']==completion['coordinate_phase_observer']
        and phase['source']['sha256']=='b37dbad3835e2b3195cce5cc30afba20116431882a827d4e9d42d4446609e9dd',
        'Exact eight-lane phase-only source binding required')
    for item in(metadata,raw,completion):
        need(item['projection_shared16_geometry']==SHARED16
            and item['projection_shared16_cancel_payload_erasure_claimed']is False
            and item['old_cache325_proof_inherited']is item['local_cache59_proof_inherited']is False
            and item['current_cache_or_guard_composition_theorem']is False
            and item['prior_V14_candidate_results_reused']is False
            and item['sha_model_native_macro_elaboration_identical']is False,
            'V15 geometry and limited component/macro/proof scope required')
        for key in('projection_shared16_sources','plaintext_direct4_result_lut_sources',
            'plaintext_direct4_result_lut_component_scope','fixed_add_helper_only_prior_component_context',
            'cache_compact_prefix_source','cache_compact_prefix_component_scope'):
            need(item[key]==candidate[key],'Current component/source object differs: '+key)
    for key,wanted in COMPONENT_PINS.items():
        need(pin2(candidate[key])==wanted,'Exact original current component identity required: '+key)
        record=reader.json(candidate[key]['path'],candidate[key]);need(record['passed']is True,'Closed source component required')
        rehash_tree(reader,record,omissions)
    for item in(raw,completion):
        need(item['all_current_cache_production_sources_recompiled']is True
            and item['all_current_attention_production_sources_recompiled']is True
            and item['all_current_projection_production_sources_recompiled']is True
            and item['all_current_plaintext_direct4_result_lut_sources_recompiled']is True
            and item['all_healthy_cases_have_all15_use_and_CLEAR_coverage']is True
            and item['healthy_phase_case_count']==6 and item['native_phase_observer_macro_added']is False,
            'Fresh current source/phase compilation required')
    rehash_tree(reader,phase,omissions)
    return dict(source_epoch='protected-v15-compact-prefix',current_components_pinned_and_scoped=True,
        original_attention_scope_only=True,cache_guard_or_numerical_or_whole_machine_theorem=False,
        sha_model_native_macro_elaboration_identical=False,prior_candidate_results_reused=False)
