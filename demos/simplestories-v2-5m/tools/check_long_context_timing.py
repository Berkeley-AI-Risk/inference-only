# NEW DISABLED baseline-scope selected-native timing source. Actual source association is recorded; native/image/mapped authority remains pending.
# Optional universal SHA arithmetic/composition research is open and is not an added baseline qualification gate.
"""Replay selected recorded command timings, not hardware or exact clock starts.

Literal record pins are filled only by the separately reviewed timing exporter
after all actual V8 SHA2 stage-store promotion and mapped-ROM gates. The original operation.seconds is retained;
logging timestamps provide bounds, not a replacement duration measurement.
"""
import argparse
import gzip
import hashlib
import json
import math
from pathlib import Path,PurePosixPath
import re

TIMING_RECORD_SHA = 'ae81f740b937068d4dd111010871c557dfa28b62b44a6f95de5a155607bc1bdf'
NATIVE_SUMMARY_SHA = 'cca6d4856dd0d64a0b19420b4c54046284375b6039e5f3ffc49668a65721c72d'
MODEL='cad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0'
REFERENCE='bc5e2dce531cf10b05590dee483f9f561f5fd8b5bfa82f73022ef93952667897'
INDEX='a66052169a9abc7f6a509413e798d4d61fd2bcb4beac06b1a7dc7d9987f0477b'
PARENT_IMAGE='0e6d30b68bd8757657bc1c3b949ac5b9571a0a8d1f8bb1a6e6018b241f733033'
BASELINE='5949ab455e5c9db4e88dea77e09e1522168bc9903713728772c8eabd1a2e5565'
PUBLIC_BASELINE='fa268181bd5866e6676a79a3b592401caf68262eeba04b64e236e2ac098104de'
WIRE_SOURCE='39cb01633234115407ba9d0a65bf0ea3a96ab101954451df66855133047510d9'
EXCHANGE_SOURCE='dc730aa668b2aa2b511068d0f8a0cb136ddc44b36bd70ff3e7249a912d8fdcc6'
# NEW preparation only. No current image or producer is admitted by these sources.
SOURCE_REVIEWED=True


# NEW DISABLED baseline-scope workflow. No selected image or mapped authority.
# Optional SHA arithmetic/private-bank refinement is OPEN, not a baseline gate.
CHOSEN_NATIVE_KIND='p3r0_maxfan60'
CHOSEN_NATIVE_IMAGE_AUTHORITY={'image_sha256': 'd271626a7fb9ce1debdf7a9cd847125ec7eb4c907fa9d06af9d5f8146cecc725', 'kind': 'p3r0_maxfan60', 'native_audit_passed': True, 'native_audit_sha256': '3fd3d8220e74f6158832a9fe39528faef92d9c983c247f21dec58359a13e22e1', 'native_finished_sha256': '0fbf9fb5e01bf69791eb14fca803eeace1af3e0a59918ec5aa4fdf4f1cbf2887', 'reviewed': True, 'vo_sha256': 'bdc79ac7bfff8103cf055ae6c8d52c1bc06cb395bb29faa961f1736364bcea94'}
NATIVE_CONTRACTS={'p3r0_maxfan60': {'native_run_relative': 'build/native-long-context-v8-sha-two-round-20261024-attempt3-p3r0-rep0-maxfan60', 'builder_relative': 'tools/run_long_context_native_v8_sha_two_round_place3_route0_maxfan60.py', 'builder_sha256': '9eac92442c63f2ed37972d7035917ba41c9a064c987b1611b1999c15680206c7', 'auditor_relative': 'tools/check_long_context_native_v8_sha_two_round_place3_route0_maxfan60.py', 'auditor_sha256': '0c6eafe9d72f02afc95a389732b5b4d4f3c1c379859699ce2b081c99deaf3a7c', 'build_schema': 'long-context-native-build-v8-sha-two-round-place3-route0-maxfan60', 'admission_schema': 'long-context-native-admission-v8-sha-two-round-place3-route0-maxfan60', 'audit_schema': 'long-context-native-audit-v8-sha-two-round-place3-route0-maxfan60', 'placement': 3, 'routing': 0, 'replication': 0, 'route_maxfan': 60, 'implemented_recipe_sha256': '0f17cd877087ee30c97ee102e758ac6625a1ac2790d8e9dc605c6a3c9fe51a5f', 'public_recipe': {'placement_option': 3, 'route_option': 0, 'replication_option': 0, 'qualified_parent_route_option': 0, 'model_tested_recipe_route_option': 0, 'experiment_recipe_route_option': 0, 'model_tested_recipe_placement_option': 3, 'model_tested_recipe_replication_option': 0, 'experiment_recipe_replication_option': 0, 'qualified_parent_recipe_sha256': 'dacf0fc22dbedcebc1fcdb719bf6077a6ba60116c0502f45365e3e7483fab41e', 'implemented_recipe_sha256': '0f17cd877087ee30c97ee102e758ac6625a1ac2790d8e9dc605c6a3c9fe51a5f', 'model_tested_recipe_sha256': 'd3a7a2bc2d3f58854466173183dc27dec9877bf1eca7237c782866a5e1d51730', 'route_maxfan': 60, 'qualified_parent_route_maxfan': 23, 'model_tested_recipe_route_maxfan': 23, 'experiment_recipe_route_maxfan': 23, 'qualified_parent_recipe_deltas': ['place_option:4->3', 'route_maxfan:23->60'], 'qualified_intermediate_recipe_sha256': 'dacf0fc22dbedcebc1fcdb719bf6077a6ba60116c0502f45365e3e7483fab41e', 'qualified_intermediate_recipe_deltas': ['place_option:4->3', 'route_maxfan:23->60'], 'baseline_implemented_recipe_sha256': '8fcabe58675ca456f7f7d46dfc6d6b834fcf9d143eb165c074fbb1dd58207325', 'baseline_recipe_deltas': ['place_option:4->3', 'route_option:1->0'], 'source_delta_from_comparison': ['project/sha.sv'], 'comparison_started_sha256': 'ca2c1884680a79e7bb4be0c98db06fe4bfe38a89732399304e9445233dd9f649', 'comparison_admission_sha256': '83cbe7ff4b41d95fea81ef281d750823822f15c555540b1cf4dcc69dbc9a1f75', 'comparison_recipe_sha256': '8fcabe58675ca456f7f7d46dfc6d6b834fcf9d143eb165c074fbb1dd58207325', 'comparison_native_builder_sha256': '2b99a7a85259f96d2c1f935db41602e30405a2d602ef0d484bcc15568ddcb704', 'baseline_result_credited': False, 'baseline_failure_required': False, 'baseline_outcome_assessed': False, 'sha_source_sha256': 'd1b7785186aa486de41507e7a45876693690b52aff9eebe31ea8e31437bdff94', 'route1_v8_comparison': {'started_sha256': 'd73365520f1ec0e13a1292df20d66cac8a66e921cf496685a26adaa56a2567df', 'admission_sha256': 'ddd4067fda5788a9ce1702be5ebbedce5c7cd37f53acc8f85208c68ac6b81860', 'native_builder_sha256': '32fade064ae2110e1891922b3f168b6ea523f4161d7116a83d61c4b85acb458a', 'recipe_sha256': '8fcabe58675ca456f7f7d46dfc6d6b834fcf9d143eb165c074fbb1dd58207325', 'implemented_recipe_deltas': ['place_option:4->3', 'route_option:1->0'], 'baseline_result_credited': False, 'baseline_failure_required': False, 'baseline_outcome_assessed': False}}, 'started_sha256': 'b8293aa639ec2e887bdac1966ae645a13d7220e022c97d452a0d42daf06838b6', 'admission_sha256': '1304b4ed43c43db17fe771cdb928d2e4bc717151e626bf95dfd2d8029afedac3'}, 'p4r1_maxfan60': {'native_run_relative': 'build/native-long-context-v8-sha-two-round-20261024-attempt1-p4r1-rep0-maxfan60', 'builder_relative': 'tools/run_long_context_native_v8_sha_two_round.py', 'builder_sha256': '32fade064ae2110e1891922b3f168b6ea523f4161d7116a83d61c4b85acb458a', 'auditor_relative': 'tools/check_long_context_native_v8_sha_two_round.py', 'auditor_sha256': 'f11aeea86c7d6cbfb947a47ed587ba8ad0cc7c7d030e246dec7fe6914470a4e1', 'build_schema': 'long-context-native-build-v8-sha-two-round', 'admission_schema': 'long-context-native-admission-v8-sha-two-round', 'audit_schema': 'long-context-native-audit-v8-sha-two-round', 'placement': 4, 'routing': 1, 'replication': 0, 'route_maxfan': 60, 'implemented_recipe_sha256': '8fcabe58675ca456f7f7d46dfc6d6b834fcf9d143eb165c074fbb1dd58207325', 'public_recipe': {'placement_option': 4, 'route_option': 1, 'replication_option': 0, 'qualified_parent_route_option': 0, 'model_tested_recipe_route_option': 0, 'experiment_recipe_route_option': 0, 'model_tested_recipe_placement_option': 3, 'model_tested_recipe_replication_option': 0, 'experiment_recipe_replication_option': 0, 'qualified_parent_recipe_sha256': 'dacf0fc22dbedcebc1fcdb719bf6077a6ba60116c0502f45365e3e7483fab41e', 'implemented_recipe_sha256': '8fcabe58675ca456f7f7d46dfc6d6b834fcf9d143eb165c074fbb1dd58207325', 'model_tested_recipe_sha256': 'd3a7a2bc2d3f58854466173183dc27dec9877bf1eca7237c782866a5e1d51730', 'route_maxfan': 60, 'qualified_parent_route_maxfan': 23, 'model_tested_recipe_route_maxfan': 23, 'experiment_recipe_route_maxfan': 23, 'qualified_parent_recipe_deltas': ['route_option:0->1', 'route_maxfan:23->60'], 'qualified_intermediate_recipe_sha256': 'ba2d39fe40715612436417269b2481e65fa61978d689fa2a635b223a50b8669d', 'qualified_intermediate_recipe_deltas': ['route_maxfan:23->60'], 'baseline_implemented_recipe_sha256': '8fcabe58675ca456f7f7d46dfc6d6b834fcf9d143eb165c074fbb1dd58207325', 'baseline_recipe_deltas': [], 'source_delta_from_comparison': ['project/sha.sv'], 'comparison_started_sha256': 'ca2c1884680a79e7bb4be0c98db06fe4bfe38a89732399304e9445233dd9f649', 'comparison_admission_sha256': '83cbe7ff4b41d95fea81ef281d750823822f15c555540b1cf4dcc69dbc9a1f75', 'comparison_recipe_sha256': '8fcabe58675ca456f7f7d46dfc6d6b834fcf9d143eb165c074fbb1dd58207325', 'comparison_native_builder_sha256': '2b99a7a85259f96d2c1f935db41602e30405a2d602ef0d484bcc15568ddcb704', 'baseline_result_credited': False, 'baseline_failure_required': False, 'baseline_outcome_assessed': False, 'sha_source_sha256': 'd1b7785186aa486de41507e7a45876693690b52aff9eebe31ea8e31437bdff94'}, 'started_sha256': 'd73365520f1ec0e13a1292df20d66cac8a66e921cf496685a26adaa56a2567df', 'admission_sha256': 'ddd4067fda5788a9ce1702be5ebbedce5c7cd37f53acc8f85208c68ac6b81860'}}
RETAINED_SCOPE_FIELDS=('retained_scope_association',)
RETAINED_SCOPE_CONTRACT={'aggregate_assertion_total': None, 'arithmetic_refinement_pending': True, 'changed_cache_stage_proof': {'actual_ram_bits': 8192, 'aggregate_assertion_total': None, 'arbitrary_readonly_selector_bits': 13, 'assumptions': [], 'cancellation_knownness_scope': 'Cancellation may revoke logical knownness while captured payload/assembly coherence remains. Fault replies are masked. These source properties do not establish physical memory erasure.', 'candidate_sha256': 'ba17ba73a9c708aabd246cbc538f4e81e25b33cc116ded91da4fd554566ead39', 'hardware_access': False, 'induction_conclusions': 154, 'internal_cuts': [], 'limits': ['No whole-machine or full cache-equivalence theorem.', 'No trusted external DDR content or cryptographic K/V integrity assumption or claim.', 'No eventual-response/fairness or fatal-reset-free liveness claim.', 'No unconditional local accepted-write ownership/drain theorem across terminal failure. No unexpected completion input is assumed away.', 'No independently latched historical-DDR semantic row content theorem; physical fill mux fidelity is separate from accepted pending-stage provenance.', 'No physical RAM initialization/erasure, mapped/native/timing/route/board qualification.', 'No inherited141 assertion total or pass flag.', 'Cancellation revokes logical stage knownness only. Selected-point and captured/stage/assembled payload coherence remain required through CLEAR and terminal failure; retained payload erasure is not claimed.', 'Synchronous two-state source safety only; no electrical CDC, physical implementation, native timing or board qualification is inferred.', 'Only the primary Z3 campaign is credited. No independent second-solver completion or proof credit is claimed.', 'The recorded audit reconstructs consumed evidence and repeats the RAM/observer audit without rerunning the solver or elaborator; independent tool-execution attestation is excluded.'], 'mapped_image_equivalence': False, 'mapper_sha256': '1e3000948b24f5d52dfd0f61697d713a9c8c4c9f2ecc90ccb91812a04fc3e0dc', 'old_cache141_credited': False, 'passed': True, 'physical_equivalence': False, 'primary_solver': 'z3', 'production_ram_banks': 8, 'qualification_inherited': False, 'reset_base_queries': 1, 'sat_premise_then_unsat_queries': 155, 'scope': 'Recorded full source reset-base plus joint-prior inductive safety with exact consumed-query/log reconstruction and actual RAM/observer audit. Independent tool-execution attestation, full cache equivalence, terminal-local write drain and mapped/physical claims are excluded.', 'solver_executed_by_this_binding': False, 'source_assertions': 154, 'source_query_log_closure': True, 'source_receipts': {'actual_run': {'bytes': 256776, 'sha256': 'e39204ffc039b4e157af8758c9b7c1095cfe96f95088d3b80870f341c9948883'}, 'auditor_source': {'bytes': 13478, 'sha256': '9a35fa710afde1416226564273ea2f56b05742030743ce793621a8a8d2b01a42'}, 'preparation': {'bytes': 9188, 'sha256': '8281070c15c4005886caa2f4e7a1a69a7eb56c3283d9affdb0dfa4415e52f612'}, 'primary_index': {'bytes': 5299, 'sha256': '2d9874c97bafd9b7c767b91bd416e61c18e58fee42a65b8d69bf2cf45fe705a2'}, 'recorded_audit': {'bytes': 305651, 'sha256': 'a2abd17878e15c9499f9e7d9879364897830c2fcbb0a65be6811ae59cf964c60'}}, 'state': 'complete', 'statement_origin': {'aborted_write_and_lock_history_support': 2, 'exponent_snapshot_support': 2, 'original_knownness_statement_scoped_for_cancellation': 1, 'original_monitor_statements_retained_exactly': 116, 'phase_history_support': 27, 'revoked_semantic_owner_history_support': 1, 'through_cancel_coherence_support': 5}, 'terminal_scope': 'Healthy and CLEAR ownership/drain safety; terminal fail-stop may abandon local accepted writes until reset. No unexpected-input assumptions or unconditional terminal-local-drain claim.', 'whole_cache_equivalence': False, 'whole_machine_proof': False}, 'changed_exp_rom_proof': {'aggregate_assertion_total': None, 'candidate_sha256': '042df8b9da13bc2a66f945b2942a30374d52fa38766ba73916999901fa63622f', 'default_table_sha256': 'c3e491c6abcd545f73dce0fabb37f86d2eed31a0334268da1e035a75f4c62a3f', 'limits': ['Source-only relative ROM safety/equivalence; no full attention FSM, whole model, vendor primitive, mapped image, physical or security theorem.', 'FILE parser/I/O uses standard RTL readmemh semantics. Arbitrary32-bit image dataflow is proved; partial/addressed/XZ FILEs are finite actual simulation fixtures.', 'Coupled unspecified initial selected payload/metadata is an explicit representation premise, not an assumption that valid response data already matches.', 'Clock-level source induction uses async2sync; analog reset pulse widths, glitches and metastability are not claimed.', 'No native inference/resource/routing/timing result or FPGA model/flash/write action is credited here. Root-owned synthesis previews and any future mapped-ROM audit remain separate.', 'These query/transcript counts are nonadditive with all existing stochastic, transport, arithmetic and whole-model evidence; no aggregate machine assertion total is claimed.'], 'mapped_canonical_rom_audit_passed': False, 'mapped_canonical_rom_audit_required_before_preload': True, 'mapped_image_equivalence': False, 'passed': True, 'physical_equivalence': False, 'qualification_inherited': False, 'reference_sha256': 'e47bf421e10435e6bffa10e0219415630d57ef00ccdc4040ca7d8d9f720e9477', 'scope': {'composition': 'Initializer image correspondence and source-proved immutable storage plus runtime state induction preserve all four observable outputs along unbounded clock-sampled digital input sequences. Reset assertion outputs and actual asynchronous pulse behavior are separately checked.', 'file_image': 'Actual source-parsed1024loop and four disjoint copies prove each low word0..4095 and independent endpoint4096 come from the same complete FILE image; addresses/counts are checked nonwrapping. Source-runtime theorem assumes the resulting requested-word image relation, discharged by that copy construction.', 'four_state': 'Nine actual original/candidate FILE simulations, all8192 addresses each, pre-read/unreset X,32X/Z control cases and one between-clock asynchronous reset pulse perFILE. Six complete known-integer files also get198144 independent public transaction-oracle comparisons. This is finite four-state evidence, not a universal four-state SMT theorem.', 'independent_scalar': 'Unmodified full e47 reference, namespace-only in simulations; no candidate ROM is shared with the reference.', 'initial_state': 'Explicit representation coupling of unspecified initial selected payload and metadata/sticky state; constructive low-selected witness covers every initial32-bit payload. Unrelated power-up states are not compared.', 'runtime': 'Complete actual-source four-output and inductive state-correspondence proof for arbitrary13-bit request/index sequences and arbitrary32-bit immutable FILE words. No valid-encoding assumption or runtime/output cuts.'}, 'scope_premises_not_dropped': True, 'separate_from_reused_modular_scopes': True, 'shared_mac_proof_credited': False, 'source_query_log_closure': True, 'source_receipts': {'component': {'bytes': 69396, 'sha256': '80309bee650ec898b7e2a81eb59fa4c925779d56188b448dd37c4729d94273d0'}, 'final_index': {'bytes': 6256, 'sha256': '6ccf19de26525697a144b3995efc31c225f73f6fd1a424247a4863d547e95596'}, 'source_audit': {'bytes': 184623, 'sha256': '3410f9dcab7cc87180deceb4f4e726edbd271c73822f432ca422eadeaa0c0dd3'}, 'source_proof': {'bytes': 6501, 'sha256': '797f55044171f4b3df5565eaaf13875c8562f34e872d572bf95ba870bd8bdeae'}}, 'state': 'complete', 'whole_machine_proof': False}, 'changed_native_inputs': ['project/sha.sv'], 'formal_replay_of_this_variant': False, 'mapped_image_equivalence': False, 'old_atomic87_credited': False, 'old_cache141_credited': False, 'public_association_inventory': {'bytes': 100932, 'sha256': '335a9b266bdd8b5d5a2276a3d843f79b6fd2317f579ac54a5ecdcee56e18ae7d'}, 'retained_scope_binding_pass': True, 'retained_scope_names': ['app138', 'backend29', 'fast_shift_intermediate', 'front44_composed', 'prefix_divider', 'small_shift', 'typed15'], 'reused_scopes_sha256': 'dcc24f886310ab0c9ed7681d4c21ecf1299459b823506f5f03c79113fe4afdd0', 'source_ancestry_sha256': 'd29069ad81ab3921519bb3220cd28c5c1bcf519828b3618b76d870474b9dcd5f', 'source_inventory_sha256': '568eb3314ec96ad7fb4963be80217880b1531385a50beeebdb3f88da7e8e4b8d', 'source_scope_assessment': {'bytes': 80030, 'sha256': 'd8a5d7284e17dfef2cd0113cb03f05415753b3144ddfd1058043ab25eb401100'}, 'source_scope_decision': {'bytes': 2922, 'sha256': '3acbc6468a8fb5e3c6bc55262afd4a7b80501ca82d67e45e9c476bb65ab4bb91'}, 'universal_sha_refinement_proved': False, 'unproved_private_sha_boundary': {'archived_7e_sha_record_unchanged': True, 'arithmetic_refinement_pending': True, 'baseline_page_bank_sha_outputs_unconstrained': True, 'busy_done_latency_assumed': False, 'candidate_sha256': 'd1b7785186aa486de41507e7a45876693690b52aff9eebe31ea8e31437bdff94', 'current_d1_sha_outside_theorem': True, 'finite_bank_good_bad_cases': 6, 'finite_component': {'bytes': 86037, 'sha256': '265894090b35e47cdb42e0b94ed195386442702b336820918810de20bbb42657'}, 'finite_compression_vectors': 235, 'finite_model': {'bytes': 1975137, 'sha256': '5d09fcecf413a2a010ef14ffdadeef6d670dc0333b6afe20e8590945baf81dcb'}, 'finite_reset_phases': 32, 'finite_source_finished_sha256': '19d2264e67d75a4eb22221f57e7693b288f02a690c6d99867709d00bc30fb701', 'finite_validator_sha256': '8d3cbcc6496c0a28c0b5d0b78b1caa0b0a3462246f86c40925bbd2d09428e105', 'kind': 'unproved-compressor-interface-with-finite-evidence', 'model_cases': 30, 'model_heads': 108, 'model_rows': 434052, 'new_page_bank42_run_claimed': False, 'owned_interface_header_sha256': '539dbf73b10797d01e7dd1021aece121269b69dd7a1385651754730a2424c036', 'private_bank_composition_pending': True, 'production_sha_not_elaborated': True, 'reference_sha256': '7e4992bdf5c7a6e6405979a01a351254d4a84fb8c0e2e47afcbe3fc4ff7d3610', 'returned_digest_correctness_assumed': False, 'scope': 'Unproved private compression boundary; finite arithmetic/transactions and full-model executions only. No SHA arithmetic/security/private-bank refinement theorem is claimed.', 'unchanged_bank_sha256': 'ced8becfe26c4a733058119f5ec4c88025377973b09411f0ae5141ca9f594aa1', 'universal_refinement_proved': False}, 'whole_machine_proof': False}
V8_PROOF_SCHEMA='long-context-v8-baseline-scoped-source-association-v1'
V8_SCOPE_VALIDATOR_SHA='195439965aa44f449622aa7ed3deaed6c4d203b19ba0c944433f06094086c829'
V8_SCOPE_RECEIPT_SHA='8a43f4135949c669499facc1df693c7cdaf8d9659d8306133b7b5a123d16e3e1'

def selected_native_contract():
    if CHOSEN_NATIVE_KIND not in NATIVE_CONTRACTS:
        raise ValueError('Actual successful R1 or P3 native selection is pending')
    choice=NATIVE_CONTRACTS[CHOSEN_NATIVE_KIND];image=CHOSEN_NATIVE_IMAGE_AUTHORITY
    if not(type(image)is dict and image.get('reviewed')is True and image.get('native_audit_passed')is True
           and image.get('kind')==CHOSEN_NATIVE_KIND):
        raise ValueError('Reviewed actual passing FIN/audit/FS/VO authority is pending')
    for key in('native_finished_sha256','native_audit_sha256','image_sha256','vo_sha256'):
        value=image.get(key)
        if not(type(value)is str and len(value)==64 and all(c in'0123456789abcdef'for c in value)):
            raise ValueError('Pending chosen-native artifact: '+key)
    return choice

def require_v8_baseline_scope():
    if SOURCE_REVIEWED is not True:
        raise ValueError('NEW baseline-selected-native workflow source is not adopted')
    if not(RETAINED_SCOPE_CONTRACT.get('retained_scope_binding_pass')is True
           and RETAINED_SCOPE_CONTRACT.get('universal_sha_refinement_proved')is False
           and RETAINED_SCOPE_CONTRACT.get('arithmetic_refinement_pending')is True):
        raise ValueError('Exact reviewed baseline source-scope contract differs')
    return selected_native_contract()

def retained_scope_fragment(value):
    import json as _scope_json
    encode=lambda row:_scope_json.dumps(row,sort_keys=True,separators=(',',':'),allow_nan=False)
    row=value.get('retained_scope_association')if type(value)is dict else None
    if not(type(row)is dict and encode(row)==encode(RETAINED_SCOPE_CONTRACT)):
        raise ValueError('Full retained nine-scope/private-SHA-boundary association differs')
    for key in('changed_cache_stage_proof','old_cache141_credited'):
        if key not in value or encode(value[key])!=encode(row[key]):
            raise ValueError('Top-level cache scope differs from the same nested association')
    return {'retained_scope_association':row}


def cap60_public_recipe(tested_sha256):
    """Exact chosen R1 or P3 recipe; source comparison conveys no outcome credit."""
    if tested_sha256!='d3a7a2bc2d3f58854466173183dc27dec9877bf1eca7237c782866a5e1d51730':
        raise ValueError('Exact model-tested P3/R0/maxfan23 recipe required')
    return selected_native_contract()['public_recipe']


PLANNER='e25407d915d8f33d997de32182d22ca3a9b5c819e2667b2b9c20c45815459283'
BOARD='ba06e18e744807a3d5c57808c7cc55a2c03e0a083f5f0ae1cb373472618b977d'
REVIEWED_POLICY='bfb28ab9f8e0e9ec78d867e2dc54f25c9b6b0b005e3ffeadc66350a114e9e73f'
NATIVE_PRODUCER=None
NATIVE_AUDITOR=None
PROOF_BINDER='195439965aa44f449622aa7ed3deaed6c4d203b19ba0c944433f06094086c829'
MAPPED_ROM_VALIDATOR='29ab9644aee69f09c376a6cffd5aceca1062f8e60818cd23f2d080ceb0631b3f'
SOURCE_BINDING='8a43f4135949c669499facc1df693c7cdaf8d9659d8306133b7b5a123d16e3e1'
SOURCE_BINDING_BYTES=2707893
REUSED_SCOPE_METADATA_SHA='c3142d51c84e683224bd5a3a6167d1efb4a1e862339038d3cfd5b93e5b4b038a'
PROOF_INVENTORY='09362a0518887130b4187bb770b2052ea00d52cc3da8df24a20de30f7e1ab28a'
EXP='project/fpga/token_only_model0_ddr_board1/fixed_attention0/rtl/board1_fixed_attention_exp_lut_sync.sv'
TABLE='project/model_rtl_evidence/attention_sublayer/exp_neg_q30.memh'
KV='project/fpga/token_only_model0_ddr_board1/context2048_gowin_portability0/rtl/board1_context2048_atomic_kv_typed_clear_consistent.sv'
KV_SOURCE='ba17ba73a9c708aabd246cbc538f4e81e25b33cc116ded91da4fd554566ead39'
MODEL_ASSEMBLY='0a3c8fa5498641374b1205f325f2bbedecd820bbeb8cc74d1d796292f61d4376'
ATTENTION='project/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_attention.sv'
ROM_SOURCE='042df8b9da13bc2a66f945b2942a30374d52fa38766ba73916999901fa63622f'
TABLE_SOURCE='c3e491c6abcd545f73dce0fabb37f86d2eed31a0334268da1e035a75f4c62a3f'
ATTENTION_SOURCE='368596a5f8470cd28ccd429cd2ab479db5c77aef0b34eb9541c55aa44c0baf0c'
ANCESTRY='d29069ad81ab3921519bb3220cd28c5c1bcf519828b3618b76d870474b9dcd5f'
REUSED_SCOPES='dcc24f886310ab0c9ed7681d4c21ecf1299459b823506f5f03c79113fe4afdd0'
SCOPES={'prefix_divider', 'front44_composed', 'fast_shift_intermediate', 'typed15', 'backend29', 'app138', 'small_shift'}
# No invented shape or pass flag for the pending fresh cache theorem.
SOURCE_PROOF_FIELDS=('changed_exp_rom_proof', 'changed_cache_stage_proof', 'old_cache141_credited', 'retained_scope_association')
SOURCE_PROOF_PUBLIC_CONTRACT={'changed_cache_stage_proof': {'actual_ram_bits': 8192, 'aggregate_assertion_total': None, 'arbitrary_readonly_selector_bits': 13, 'assumptions': [], 'cancellation_knownness_scope': 'Cancellation may revoke logical knownness while captured payload/assembly coherence remains. Fault replies are masked. These source properties do not establish physical memory erasure.', 'candidate_sha256': 'ba17ba73a9c708aabd246cbc538f4e81e25b33cc116ded91da4fd554566ead39', 'hardware_access': False, 'induction_conclusions': 154, 'internal_cuts': [], 'limits': ['No whole-machine or full cache-equivalence theorem.', 'No trusted external DDR content or cryptographic K/V integrity assumption or claim.', 'No eventual-response/fairness or fatal-reset-free liveness claim.', 'No unconditional local accepted-write ownership/drain theorem across terminal failure. No unexpected completion input is assumed away.', 'No independently latched historical-DDR semantic row content theorem; physical fill mux fidelity is separate from accepted pending-stage provenance.', 'No physical RAM initialization/erasure, mapped/native/timing/route/board qualification.', 'No inherited141 assertion total or pass flag.', 'Cancellation revokes logical stage knownness only. Selected-point and captured/stage/assembled payload coherence remain required through CLEAR and terminal failure; retained payload erasure is not claimed.', 'Synchronous two-state source safety only; no electrical CDC, physical implementation, native timing or board qualification is inferred.', 'Only the primary Z3 campaign is credited. No independent second-solver completion or proof credit is claimed.', 'The recorded audit reconstructs consumed evidence and repeats the RAM/observer audit without rerunning the solver or elaborator; independent tool-execution attestation is excluded.'], 'mapped_image_equivalence': False, 'mapper_sha256': '1e3000948b24f5d52dfd0f61697d713a9c8c4c9f2ecc90ccb91812a04fc3e0dc', 'old_cache141_credited': False, 'passed': True, 'physical_equivalence': False, 'primary_solver': 'z3', 'production_ram_banks': 8, 'qualification_inherited': False, 'reset_base_queries': 1, 'sat_premise_then_unsat_queries': 155, 'scope': 'Recorded full source reset-base plus joint-prior inductive safety with exact consumed-query/log reconstruction and actual RAM/observer audit. Independent tool-execution attestation, full cache equivalence, terminal-local write drain and mapped/physical claims are excluded.', 'solver_executed_by_this_binding': False, 'source_assertions': 154, 'source_query_log_closure': True, 'source_receipts': {'actual_run': {'bytes': 256776, 'sha256': 'e39204ffc039b4e157af8758c9b7c1095cfe96f95088d3b80870f341c9948883'}, 'auditor_source': {'bytes': 13478, 'sha256': '9a35fa710afde1416226564273ea2f56b05742030743ce793621a8a8d2b01a42'}, 'preparation': {'bytes': 9188, 'sha256': '8281070c15c4005886caa2f4e7a1a69a7eb56c3283d9affdb0dfa4415e52f612'}, 'primary_index': {'bytes': 5299, 'sha256': '2d9874c97bafd9b7c767b91bd416e61c18e58fee42a65b8d69bf2cf45fe705a2'}, 'recorded_audit': {'bytes': 305651, 'sha256': 'a2abd17878e15c9499f9e7d9879364897830c2fcbb0a65be6811ae59cf964c60'}}, 'state': 'complete', 'statement_origin': {'aborted_write_and_lock_history_support': 2, 'exponent_snapshot_support': 2, 'original_knownness_statement_scoped_for_cancellation': 1, 'original_monitor_statements_retained_exactly': 116, 'phase_history_support': 27, 'revoked_semantic_owner_history_support': 1, 'through_cancel_coherence_support': 5}, 'terminal_scope': 'Healthy and CLEAR ownership/drain safety; terminal fail-stop may abandon local accepted writes until reset. No unexpected-input assumptions or unconditional terminal-local-drain claim.', 'whole_cache_equivalence': False, 'whole_machine_proof': False}, 'changed_exp_rom_proof': {'aggregate_assertion_total': None, 'candidate_sha256': '042df8b9da13bc2a66f945b2942a30374d52fa38766ba73916999901fa63622f', 'default_table_sha256': 'c3e491c6abcd545f73dce0fabb37f86d2eed31a0334268da1e035a75f4c62a3f', 'limits': ['Source-only relative ROM safety/equivalence; no full attention FSM, whole model, vendor primitive, mapped image, physical or security theorem.', 'FILE parser/I/O uses standard RTL readmemh semantics. Arbitrary32-bit image dataflow is proved; partial/addressed/XZ FILEs are finite actual simulation fixtures.', 'Coupled unspecified initial selected payload/metadata is an explicit representation premise, not an assumption that valid response data already matches.', 'Clock-level source induction uses async2sync; analog reset pulse widths, glitches and metastability are not claimed.', 'No native inference/resource/routing/timing result or FPGA model/flash/write action is credited here. Root-owned synthesis previews and any future mapped-ROM audit remain separate.', 'These query/transcript counts are nonadditive with all existing stochastic, transport, arithmetic and whole-model evidence; no aggregate machine assertion total is claimed.'], 'mapped_canonical_rom_audit_passed': False, 'mapped_canonical_rom_audit_required_before_preload': True, 'mapped_image_equivalence': False, 'passed': True, 'physical_equivalence': False, 'qualification_inherited': False, 'reference_sha256': 'e47bf421e10435e6bffa10e0219415630d57ef00ccdc4040ca7d8d9f720e9477', 'scope': {'composition': 'Initializer image correspondence and source-proved immutable storage plus runtime state induction preserve all four observable outputs along unbounded clock-sampled digital input sequences. Reset assertion outputs and actual asynchronous pulse behavior are separately checked.', 'file_image': 'Actual source-parsed1024loop and four disjoint copies prove each low word0..4095 and independent endpoint4096 come from the same complete FILE image; addresses/counts are checked nonwrapping. Source-runtime theorem assumes the resulting requested-word image relation, discharged by that copy construction.', 'four_state': 'Nine actual original/candidate FILE simulations, all8192 addresses each, pre-read/unreset X,32X/Z control cases and one between-clock asynchronous reset pulse perFILE. Six complete known-integer files also get198144 independent public transaction-oracle comparisons. This is finite four-state evidence, not a universal four-state SMT theorem.', 'independent_scalar': 'Unmodified full e47 reference, namespace-only in simulations; no candidate ROM is shared with the reference.', 'initial_state': 'Explicit representation coupling of unspecified initial selected payload and metadata/sticky state; constructive low-selected witness covers every initial32-bit payload. Unrelated power-up states are not compared.', 'runtime': 'Complete actual-source four-output and inductive state-correspondence proof for arbitrary13-bit request/index sequences and arbitrary32-bit immutable FILE words. No valid-encoding assumption or runtime/output cuts.'}, 'scope_premises_not_dropped': True, 'separate_from_reused_modular_scopes': True, 'shared_mac_proof_credited': False, 'source_query_log_closure': True, 'source_receipts': {'component': {'bytes': 69396, 'sha256': '80309bee650ec898b7e2a81eb59fa4c925779d56188b448dd37c4729d94273d0'}, 'final_index': {'bytes': 6256, 'sha256': '6ccf19de26525697a144b3995efc31c225f73f6fd1a424247a4863d547e95596'}, 'source_audit': {'bytes': 184623, 'sha256': '3410f9dcab7cc87180deceb4f4e726edbd271c73822f432ca422eadeaa0c0dd3'}, 'source_proof': {'bytes': 6501, 'sha256': '797f55044171f4b3df5565eaaf13875c8562f34e872d572bf95ba870bd8bdeae'}}, 'state': 'complete', 'whole_machine_proof': False}, 'old_cache141_credited': False, 'retained_scope_association': {'aggregate_assertion_total': None, 'arithmetic_refinement_pending': True, 'changed_cache_stage_proof': {'actual_ram_bits': 8192, 'aggregate_assertion_total': None, 'arbitrary_readonly_selector_bits': 13, 'assumptions': [], 'cancellation_knownness_scope': 'Cancellation may revoke logical knownness while captured payload/assembly coherence remains. Fault replies are masked. These source properties do not establish physical memory erasure.', 'candidate_sha256': 'ba17ba73a9c708aabd246cbc538f4e81e25b33cc116ded91da4fd554566ead39', 'hardware_access': False, 'induction_conclusions': 154, 'internal_cuts': [], 'limits': ['No whole-machine or full cache-equivalence theorem.', 'No trusted external DDR content or cryptographic K/V integrity assumption or claim.', 'No eventual-response/fairness or fatal-reset-free liveness claim.', 'No unconditional local accepted-write ownership/drain theorem across terminal failure. No unexpected completion input is assumed away.', 'No independently latched historical-DDR semantic row content theorem; physical fill mux fidelity is separate from accepted pending-stage provenance.', 'No physical RAM initialization/erasure, mapped/native/timing/route/board qualification.', 'No inherited141 assertion total or pass flag.', 'Cancellation revokes logical stage knownness only. Selected-point and captured/stage/assembled payload coherence remain required through CLEAR and terminal failure; retained payload erasure is not claimed.', 'Synchronous two-state source safety only; no electrical CDC, physical implementation, native timing or board qualification is inferred.', 'Only the primary Z3 campaign is credited. No independent second-solver completion or proof credit is claimed.', 'The recorded audit reconstructs consumed evidence and repeats the RAM/observer audit without rerunning the solver or elaborator; independent tool-execution attestation is excluded.'], 'mapped_image_equivalence': False, 'mapper_sha256': '1e3000948b24f5d52dfd0f61697d713a9c8c4c9f2ecc90ccb91812a04fc3e0dc', 'old_cache141_credited': False, 'passed': True, 'physical_equivalence': False, 'primary_solver': 'z3', 'production_ram_banks': 8, 'qualification_inherited': False, 'reset_base_queries': 1, 'sat_premise_then_unsat_queries': 155, 'scope': 'Recorded full source reset-base plus joint-prior inductive safety with exact consumed-query/log reconstruction and actual RAM/observer audit. Independent tool-execution attestation, full cache equivalence, terminal-local write drain and mapped/physical claims are excluded.', 'solver_executed_by_this_binding': False, 'source_assertions': 154, 'source_query_log_closure': True, 'source_receipts': {'actual_run': {'bytes': 256776, 'sha256': 'e39204ffc039b4e157af8758c9b7c1095cfe96f95088d3b80870f341c9948883'}, 'auditor_source': {'bytes': 13478, 'sha256': '9a35fa710afde1416226564273ea2f56b05742030743ce793621a8a8d2b01a42'}, 'preparation': {'bytes': 9188, 'sha256': '8281070c15c4005886caa2f4e7a1a69a7eb56c3283d9affdb0dfa4415e52f612'}, 'primary_index': {'bytes': 5299, 'sha256': '2d9874c97bafd9b7c767b91bd416e61c18e58fee42a65b8d69bf2cf45fe705a2'}, 'recorded_audit': {'bytes': 305651, 'sha256': 'a2abd17878e15c9499f9e7d9879364897830c2fcbb0a65be6811ae59cf964c60'}}, 'state': 'complete', 'statement_origin': {'aborted_write_and_lock_history_support': 2, 'exponent_snapshot_support': 2, 'original_knownness_statement_scoped_for_cancellation': 1, 'original_monitor_statements_retained_exactly': 116, 'phase_history_support': 27, 'revoked_semantic_owner_history_support': 1, 'through_cancel_coherence_support': 5}, 'terminal_scope': 'Healthy and CLEAR ownership/drain safety; terminal fail-stop may abandon local accepted writes until reset. No unexpected-input assumptions or unconditional terminal-local-drain claim.', 'whole_cache_equivalence': False, 'whole_machine_proof': False}, 'changed_exp_rom_proof': {'aggregate_assertion_total': None, 'candidate_sha256': '042df8b9da13bc2a66f945b2942a30374d52fa38766ba73916999901fa63622f', 'default_table_sha256': 'c3e491c6abcd545f73dce0fabb37f86d2eed31a0334268da1e035a75f4c62a3f', 'limits': ['Source-only relative ROM safety/equivalence; no full attention FSM, whole model, vendor primitive, mapped image, physical or security theorem.', 'FILE parser/I/O uses standard RTL readmemh semantics. Arbitrary32-bit image dataflow is proved; partial/addressed/XZ FILEs are finite actual simulation fixtures.', 'Coupled unspecified initial selected payload/metadata is an explicit representation premise, not an assumption that valid response data already matches.', 'Clock-level source induction uses async2sync; analog reset pulse widths, glitches and metastability are not claimed.', 'No native inference/resource/routing/timing result or FPGA model/flash/write action is credited here. Root-owned synthesis previews and any future mapped-ROM audit remain separate.', 'These query/transcript counts are nonadditive with all existing stochastic, transport, arithmetic and whole-model evidence; no aggregate machine assertion total is claimed.'], 'mapped_canonical_rom_audit_passed': False, 'mapped_canonical_rom_audit_required_before_preload': True, 'mapped_image_equivalence': False, 'passed': True, 'physical_equivalence': False, 'qualification_inherited': False, 'reference_sha256': 'e47bf421e10435e6bffa10e0219415630d57ef00ccdc4040ca7d8d9f720e9477', 'scope': {'composition': 'Initializer image correspondence and source-proved immutable storage plus runtime state induction preserve all four observable outputs along unbounded clock-sampled digital input sequences. Reset assertion outputs and actual asynchronous pulse behavior are separately checked.', 'file_image': 'Actual source-parsed1024loop and four disjoint copies prove each low word0..4095 and independent endpoint4096 come from the same complete FILE image; addresses/counts are checked nonwrapping. Source-runtime theorem assumes the resulting requested-word image relation, discharged by that copy construction.', 'four_state': 'Nine actual original/candidate FILE simulations, all8192 addresses each, pre-read/unreset X,32X/Z control cases and one between-clock asynchronous reset pulse perFILE. Six complete known-integer files also get198144 independent public transaction-oracle comparisons. This is finite four-state evidence, not a universal four-state SMT theorem.', 'independent_scalar': 'Unmodified full e47 reference, namespace-only in simulations; no candidate ROM is shared with the reference.', 'initial_state': 'Explicit representation coupling of unspecified initial selected payload and metadata/sticky state; constructive low-selected witness covers every initial32-bit payload. Unrelated power-up states are not compared.', 'runtime': 'Complete actual-source four-output and inductive state-correspondence proof for arbitrary13-bit request/index sequences and arbitrary32-bit immutable FILE words. No valid-encoding assumption or runtime/output cuts.'}, 'scope_premises_not_dropped': True, 'separate_from_reused_modular_scopes': True, 'shared_mac_proof_credited': False, 'source_query_log_closure': True, 'source_receipts': {'component': {'bytes': 69396, 'sha256': '80309bee650ec898b7e2a81eb59fa4c925779d56188b448dd37c4729d94273d0'}, 'final_index': {'bytes': 6256, 'sha256': '6ccf19de26525697a144b3995efc31c225f73f6fd1a424247a4863d547e95596'}, 'source_audit': {'bytes': 184623, 'sha256': '3410f9dcab7cc87180deceb4f4e726edbd271c73822f432ca422eadeaa0c0dd3'}, 'source_proof': {'bytes': 6501, 'sha256': '797f55044171f4b3df5565eaaf13875c8562f34e872d572bf95ba870bd8bdeae'}}, 'state': 'complete', 'whole_machine_proof': False}, 'changed_native_inputs': ['project/sha.sv'], 'formal_replay_of_this_variant': False, 'mapped_image_equivalence': False, 'old_atomic87_credited': False, 'old_cache141_credited': False, 'public_association_inventory': {'bytes': 100932, 'sha256': '335a9b266bdd8b5d5a2276a3d843f79b6fd2317f579ac54a5ecdcee56e18ae7d'}, 'retained_scope_binding_pass': True, 'retained_scope_names': ['app138', 'backend29', 'fast_shift_intermediate', 'front44_composed', 'prefix_divider', 'small_shift', 'typed15'], 'reused_scopes_sha256': 'dcc24f886310ab0c9ed7681d4c21ecf1299459b823506f5f03c79113fe4afdd0', 'source_ancestry_sha256': 'd29069ad81ab3921519bb3220cd28c5c1bcf519828b3618b76d870474b9dcd5f', 'source_inventory_sha256': '568eb3314ec96ad7fb4963be80217880b1531385a50beeebdb3f88da7e8e4b8d', 'source_scope_assessment': {'bytes': 80030, 'sha256': 'd8a5d7284e17dfef2cd0113cb03f05415753b3144ddfd1058043ab25eb401100'}, 'source_scope_decision': {'bytes': 2922, 'sha256': '3acbc6468a8fb5e3c6bc55262afd4a7b80501ca82d67e45e9c476bb65ab4bb91'}, 'universal_sha_refinement_proved': False, 'unproved_private_sha_boundary': {'archived_7e_sha_record_unchanged': True, 'arithmetic_refinement_pending': True, 'baseline_page_bank_sha_outputs_unconstrained': True, 'busy_done_latency_assumed': False, 'candidate_sha256': 'd1b7785186aa486de41507e7a45876693690b52aff9eebe31ea8e31437bdff94', 'current_d1_sha_outside_theorem': True, 'finite_bank_good_bad_cases': 6, 'finite_component': {'bytes': 86037, 'sha256': '265894090b35e47cdb42e0b94ed195386442702b336820918810de20bbb42657'}, 'finite_compression_vectors': 235, 'finite_model': {'bytes': 1975137, 'sha256': '5d09fcecf413a2a010ef14ffdadeef6d670dc0333b6afe20e8590945baf81dcb'}, 'finite_reset_phases': 32, 'finite_source_finished_sha256': '19d2264e67d75a4eb22221f57e7693b288f02a690c6d99867709d00bc30fb701', 'finite_validator_sha256': '8d3cbcc6496c0a28c0b5d0b78b1caa0b0a3462246f86c40925bbd2d09428e105', 'kind': 'unproved-compressor-interface-with-finite-evidence', 'model_cases': 30, 'model_heads': 108, 'model_rows': 434052, 'new_page_bank42_run_claimed': False, 'owned_interface_header_sha256': '539dbf73b10797d01e7dd1021aece121269b69dd7a1385651754730a2424c036', 'private_bank_composition_pending': True, 'production_sha_not_elaborated': True, 'reference_sha256': '7e4992bdf5c7a6e6405979a01a351254d4a84fb8c0e2e47afcbe3fc4ff7d3610', 'returned_digest_correctness_assumed': False, 'scope': 'Unproved private compression boundary; finite arithmetic/transactions and full-model executions only. No SHA arithmetic/security/private-bank refinement theorem is claimed.', 'unchanged_bank_sha256': 'ced8becfe26c4a733058119f5ec4c88025377973b09411f0ae5141ca9f594aa1', 'universal_refinement_proved': False}, 'whole_machine_proof': False}}
CACHE_FIELDS=('changed_cache_stage_proof','old_cache141_credited')
CACHE_SCOPE_CONTRACT={'actual_ram_bits': 8192, 'aggregate_assertion_total': None, 'arbitrary_readonly_selector_bits': 13, 'assumptions': [], 'cancellation_knownness_scope': 'Cancellation may revoke logical knownness while captured payload/assembly coherence remains. Fault replies are masked. These source properties do not establish physical memory erasure.', 'candidate_sha256': 'ba17ba73a9c708aabd246cbc538f4e81e25b33cc116ded91da4fd554566ead39', 'hardware_access': False, 'induction_conclusions': 154, 'internal_cuts': [], 'limits': ['No whole-machine or full cache-equivalence theorem.', 'No trusted external DDR content or cryptographic K/V integrity assumption or claim.', 'No eventual-response/fairness or fatal-reset-free liveness claim.', 'No unconditional local accepted-write ownership/drain theorem across terminal failure. No unexpected completion input is assumed away.', 'No independently latched historical-DDR semantic row content theorem; physical fill mux fidelity is separate from accepted pending-stage provenance.', 'No physical RAM initialization/erasure, mapped/native/timing/route/board qualification.', 'No inherited141 assertion total or pass flag.', 'Cancellation revokes logical stage knownness only. Selected-point and captured/stage/assembled payload coherence remain required through CLEAR and terminal failure; retained payload erasure is not claimed.', 'Synchronous two-state source safety only; no electrical CDC, physical implementation, native timing or board qualification is inferred.', 'Only the primary Z3 campaign is credited. No independent second-solver completion or proof credit is claimed.', 'The recorded audit reconstructs consumed evidence and repeats the RAM/observer audit without rerunning the solver or elaborator; independent tool-execution attestation is excluded.'], 'mapped_image_equivalence': False, 'mapper_sha256': '1e3000948b24f5d52dfd0f61697d713a9c8c4c9f2ecc90ccb91812a04fc3e0dc', 'old_cache141_credited': False, 'passed': True, 'physical_equivalence': False, 'primary_solver': 'z3', 'production_ram_banks': 8, 'qualification_inherited': False, 'reset_base_queries': 1, 'sat_premise_then_unsat_queries': 155, 'scope': 'Recorded full source reset-base plus joint-prior inductive safety with exact consumed-query/log reconstruction and actual RAM/observer audit. Independent tool-execution attestation, full cache equivalence, terminal-local write drain and mapped/physical claims are excluded.', 'solver_executed_by_this_binding': False, 'source_assertions': 154, 'source_query_log_closure': True, 'source_receipts': {'actual_run': {'bytes': 256776, 'sha256': 'e39204ffc039b4e157af8758c9b7c1095cfe96f95088d3b80870f341c9948883'}, 'auditor_source': {'bytes': 13478, 'sha256': '9a35fa710afde1416226564273ea2f56b05742030743ce793621a8a8d2b01a42'}, 'preparation': {'bytes': 9188, 'sha256': '8281070c15c4005886caa2f4e7a1a69a7eb56c3283d9affdb0dfa4415e52f612'}, 'primary_index': {'bytes': 5299, 'sha256': '2d9874c97bafd9b7c767b91bd416e61c18e58fee42a65b8d69bf2cf45fe705a2'}, 'recorded_audit': {'bytes': 305651, 'sha256': 'a2abd17878e15c9499f9e7d9879364897830c2fcbb0a65be6811ae59cf964c60'}}, 'state': 'complete', 'statement_origin': {'aborted_write_and_lock_history_support': 2, 'exponent_snapshot_support': 2, 'original_knownness_statement_scoped_for_cancellation': 1, 'original_monitor_statements_retained_exactly': 116, 'phase_history_support': 27, 'revoked_semantic_owner_history_support': 1, 'through_cancel_coherence_support': 5}, 'terminal_scope': 'Healthy and CLEAR ownership/drain safety; terminal fail-stop may abandon local accepted writes until reset. No unexpected-input assumptions or unconditional terminal-local-drain claim.', 'whole_cache_equivalence': False, 'whole_machine_proof': False}
SOURCE_BINDING_PATHS_COUNT=8423
ROM_PROJECTION_SHA='30db110022ff8c418dc33e6f7af4dc3fb38ec4a6d36314374f5696221d584a05'
SEED=0x99aabbccddeeff001122334455667788
TEMPS=('0','0.5','1','2')
BASELINE_TIMES={'prefix128-t2-seed-a':12.358249625001918,'prefix2048-t2-seed-a':1331.417028625001}
CLOCK_TOLERANCE=1e-6
RECORD='evidence/seeded-sampling/current-timing-v8-baseline-selected-native.json'
NATIVE='evidence/seeded-sampling/current-native-summary-v8-baseline-selected-native.json'
TIMER=dict(source_file_sha256=WIRE_SOURCE,exchange_source_sha256=EXCHANGE_SOURCE,
    clock='time.monotonic',measured_field='operation.seconds',
    starts='Immediately before tx_attempt report',ends='After reply validation, before operation report',
    includes=['tx_attempt report flush/fsync','send and response wait','raw_rx observer report flush/fsync','reply decode and validation'],
    excludes=['operation report flush/fsync','caller arrival sample','inter-command host gaps','connection and prompt upload','earlier probe commands'],
    exact_start_end_timestamps_logged=False,logging_bounds_only=True,clock_rounding_tolerance_seconds=CLOCK_TOLERANCE,
    note='Do not substitute RX-TX or operation-TX timestamps for operation.seconds. UTC is provenance only; monotonic origins are local to each raw file.')


def need(ok,message):
    if not ok:raise ValueError(message)


def number(value,positive=False):
    need(type(value)in(int,float)and math.isfinite(value)and(value>0 if positive else value>=0),'Nonfinite/invalid recorded number')
    return value


def integer(value):need(type(value)is int and value>=0,'Invalid integer census');return value
def digest(value):need(type(value)is str and re.fullmatch('[0-9a-f]{64}',value)is not None,'Invalid source digest');return value
def canonical(value):return(json.dumps(value,sort_keys=True,separators=(',',':'),allow_nan=False)+'\n').encode()
def reject_constant(value):raise ValueError('Nonfinite JSON constant: '+value)
def json_bytes(raw):return json.loads(raw,parse_constant=reject_constant)


def target(package,name):
    part=PurePosixPath(name);need(type(name)is str and name and str(part)==name and not part.is_absolute()and'..'not in part.parts and'\\'not in name,'Unsafe timing input path')
    path=Path(package)/name;need(not any(p.is_symlink()for p in(path,*path.parents)if p.is_relative_to(package)),'Linked timing input')
    return path


def identity(path):
    path=Path(path);need(path.is_file()and not path.is_symlink(),'Missing/linked timing input')
    with path.open('rb')as stream:value=hashlib.file_digest(stream,'sha256').hexdigest()
    return dict(bytes=path.stat().st_size,sha256=value)


def source_identity(value):
    need(set(value)=={'bytes','sha256'},'Unsafe source identity fields');integer(value['bytes']);digest(value['sha256'])


def read(package,name,pin=None):
    path=target(package,name);actual=identity(path)
    if pin is not None:need(actual['sha256']==pin,'Recorded timing source changed: '+name)
    return json_bytes(path.read_bytes())


def crc8(raw):
    value=0
    for byte in raw:
        value^=byte
        for _ in range(8):value=((value<<1)^7)&255 if value&128 else(value<<1)&255
    return value


def request(opcode,operand=0,seed=None):
    raw=bytes((0xa5,3,operand))+seed.to_bytes(16,'little')if seed is not None else bytes((0xa5,opcode,operand&255,operand>>8))
    return(raw+bytes((crc8(raw),))).hex()


def response(frame):
    raw=bytes.fromhex(frame);need(len(raw)==5 and raw[0]==0x5a and crc8(raw[:-1])==raw[-1],'Malformed timed response')
    return raw[1],int.from_bytes(raw[2:4],'little')


def golden(package,name,code,prompt_count,outputs):
    root=Path(package)/'reference/seeded-sampling'
    need(identity(root/'SOURCE.json')['sha256']==REFERENCE and identity(root/'goldens/INDEX.json')['sha256']==INDEX,'Independent timing fixture inventory changed')
    index=json_bytes((root/'goldens/INDEX.json').read_bytes())['files'];filename=f'{name}-t{code}-seed-a.json'
    path=target(package,'reference/seeded-sampling/goldens/'+filename);need(identity(path)==index[filename],'Timed golden changed')
    row=json_bytes(path.read_bytes())
    need(row['model_image_sha256']==MODEL and row['temperature']==TEMPS[code]and row['seed']==f'0x{SEED:032x}'
         and len(row['prompt_tokens'])==prompt_count and len(row['generated_tokens'])==outputs,'Timed golden configuration differs')
    return row


def expected_workload(package,suite,label):
    matched=re.fullmatch(r'around128-t([0-3])-run([12])',label)if suite=='matched128'else None
    context=re.fullmatch(r'(prefix128|prefix512|prefix2047|prefix2048)-t([0-3])-seed-a',label)if suite=='context'else None
    need(matched is not None or context is not None,'Unknown timing workload')
    code=int(matched[1]if matched else context[2]);rows=[]
    def cmd(operation,opcode,kind,operand=0,expected=0):
        rows.append(dict(operation=operation,frame_hex=request(opcode,operand),kind=kind,operand=expected,
            role='main'if operation.startswith('long-step-')else'probe'if kind==0x81 else'ack'))
    cmd('initial-clear',2,0x82)
    if context or matched[2]=='1':rows.append(dict(operation='settings',frame_hex=request(3,code,SEED),kind=0x83,operand=code,role='ack'))
    around=golden(package,'around128',code,1,128)
    if matched:
        fixture=around;cmd('prompt-1',0,0x80,378)
        for i,token in enumerate(fixture['generated_tokens'],1):cmd(f'long-step-{i}',1,0x81,expected=token)
    else:
        dimensions={'prefix128':(128,128),'prefix512':(512,4),'prefix2047':(2047,2),'prefix2048':(2048,1)}
        n,m=dimensions[context[1]];fixture=golden(package,context[1],code,n,m)
        def probe(name):
            cmd(name+'-clear',2,0x82);cmd(name+'-empty-step',1,0xc1);cmd(name+'-append',0,0x80,378)
            for i,token in enumerate(around['generated_tokens'][:4],1):cmd(name+f'-step-{i}',1,0x81,expected=token)
        probe('before');cmd('long-clear',2,0x82)
        for i,token in enumerate(fixture['prompt_tokens'],1):cmd(f'prompt-{i}',0,0x80,token)
        tape=n
        for i,token in enumerate(fixture['generated_tokens'],1):
            if tape==2048:cmd('input-limit-append-rejected',0,0xc0,378)
            cmd(f'long-step-{i}',1,0x81,expected=token);tape+=1
        if tape==2049:cmd('final-slot-append-rejected',0,0xc0,378);cmd('final-slot-step-rejected',1,0xc1)
        probe('after-1');probe('after-2')
    cmd('final-clear',2,0x82)
    return dict(suite=suite,label=label,temperature=TEMPS[code],seed=f'0x{SEED:032x}',prompt_tokens=fixture['prompt_tokens'],
        generated_tokens=fixture['generated_tokens'],commands=rows)


def near(actual,expected):
    number(actual);number(expected);need(math.isclose(actual,expected,rel_tol=1e-12,abs_tol=1e-12),'Recorded rate differs from measured durations')


def replay_case(events,expected,summary,arrival_required=True):
    """Pure offline event/role/duration replay, also usable by unit fixtures."""
    need(set(summary)=={'generated_tokens','commands','first_step_seconds','cached_step_seconds','cached_command_tokens_per_second',
        'step_arrival_elapsed_seconds','cached_stream_tokens_per_second','independent_probe_outputs','total_checked_outputs'},'Unsafe/unknown timing summary fields')
    commands=expected['commands'];need(len(events)==3*len(commands),'Timed event/command census differs')
    previous_sequence=previous_ns=-1;main=[];main_indices=[];all_outputs=[];durations=[]
    for i,spec in enumerate(commands):
        tx,rx,done=events[3*i:3*i+3]
        if i==0:need(tx['source_sequence']==2 and tx['prior_source_sequence']==1 and tx['prior_source_event']=='campaign'
            and tx['prior_source_elapsed_ns']==0,'First timing transaction lacks its genuine campaign origin')
        for event,kind in((tx,'tx_attempt'),(rx,'raw_rx'),(done,'operation')):
            fields={'event','operation','role','source_sequence','elapsed_ns'}
            fields|={'frame_hex','prior_source_sequence','prior_source_elapsed_ns','prior_source_event'}if kind=='tx_attempt'else{'frame_hex'}if kind=='raw_rx'else{'response_kind','operand','seconds'}
            need(set(event)==fields,'Unsafe/unknown selected timing event fields')
            need(event['event']==kind and event['operation']==spec['operation']and event['role']==spec['role'],'Timed operation/role/order differs')
            seq=integer(event['source_sequence']);ns=integer(event['elapsed_ns'])
            need(seq>previous_sequence and ns>=previous_ns,'Timed source order/clock differs');previous_sequence=seq;previous_ns=ns
        need(rx['source_sequence']==tx['source_sequence']+1 and done['source_sequence']==rx['source_sequence']+1,'Timed source transaction is not contiguous')
        need(tx['frame_hex']==spec['frame_hex']and response(rx['frame_hex'])==(spec['kind'],spec['operand'])
             and done['response_kind']==spec['kind']and done['operand']==spec['operand'],'Timed STEP/wire/golden reply differs')
        seconds=number(done['seconds'],True);integer(tx['prior_source_elapsed_ns']);integer(tx['prior_source_sequence'])
        need(tx['prior_source_sequence']==tx['source_sequence']-1 and tx['prior_source_event']in('campaign','operation','receive_error')
             and tx['prior_source_elapsed_ns']<=tx['elapsed_ns'],'Invalid pre-timer source anchor')
        lower=(rx['elapsed_ns']-tx['elapsed_ns'])/1e9;upper=(done['elapsed_ns']-tx['prior_source_elapsed_ns'])/1e9
        need(lower-CLOCK_TOLERANCE<=seconds<=upper+CLOCK_TOLERANCE,'Recorded duration exceeds logging timestamp bounds')
        if i and tx['prior_source_sequence']==events[3*i-1]['source_sequence']:
            need(tx['prior_source_event']=='operation'and tx['prior_source_elapsed_ns']==events[3*i-1]['elapsed_ns'],'Previous timing anchor changed')
        if spec['kind']==0x81:all_outputs.append(spec['operand'])
        if spec['role']=='main':main.append(spec['operand']);durations.append(seconds);main_indices.append(i)
    integer(summary['commands']);integer(summary['total_checked_outputs']);integer(summary['independent_probe_outputs'])
    number(summary['first_step_seconds'],True)
    for value in summary['cached_step_seconds']:number(value,True)
    need(main==expected['generated_tokens']==summary['generated_tokens']and len(commands)==summary['commands'], 'Original timed main-token summary differs')
    need(summary['first_step_seconds']==durations[0]and summary['cached_step_seconds']==durations[1:], 'Original duration summary differs from operation.seconds')
    need(summary['total_checked_outputs']==len(all_outputs)and summary['independent_probe_outputs']==len(all_outputs)-len(main),'Timed probe/main census differs')
    count=len(main)-1;cached=math.fsum(durations[1:]);rate=count/cached if count else None
    if count and summary['cached_command_tokens_per_second']is not None:near(summary['cached_command_tokens_per_second'],count/sum(durations[1:]))
    elif count:need(not arrival_required,'Original cached-command rate missing')
    else:need(summary['cached_command_tokens_per_second']is None,'One-output case has no cached command rate')
    arrivals=summary['step_arrival_elapsed_seconds'];stream=summary['cached_stream_tokens_per_second']
    if arrivals is None:
        need(not arrival_required and stream is None,'Current caller-arrival metrics missing')
    else:
        need(len(arrivals)==len(main)and arrivals[0]==0 and all(number(x)>=0 for x in arrivals),'Caller-arrival census differs')
        need(all(a<b for a,b in zip(arrivals,arrivals[1:])),'Caller-arrival clock is not increasing')
        low=-math.inf;high=math.inf
        for index,elapsed in zip(main_indices,arrivals):
            need(index+1<len(commands),'Missing post-arrival timing anchor')
            low=max(low,events[3*index+2]['elapsed_ns']/1e9-elapsed)
            high=min(high,events[3*(index+1)]['elapsed_ns']/1e9-elapsed)
        need(low<=high+2*CLOCK_TOLERANCE,'Caller arrivals violate their logging bounds')
        if count:near(stream,count/arrivals[-1])
        else:need(stream is None,'One-output case has no streaming rate')
        need(arrivals[-1]+CLOCK_TOLERANCE>=cached,'Caller streaming interval is shorter than its command durations')
    return dict(first_step_seconds=durations[0],cached_outputs=count,cached_command_seconds=cached,
        cached_command_tokens_per_second=rate,caller_arrival_metrics_recorded=arrivals is not None,
        cached_stream_tokens_per_second=stream,logging_timestamp_bounds_checked=True,
        exact_timer_reconstructed_from_timestamps=False),durations


def event_archive(package,record):
    path=target(package,record['path']);need(identity(path)=={k:record[k]for k in('bytes','sha256')},'Selected timing event archive changed')
    with gzip.open(path,'rb')as stream:raw=stream.read(16*1024*1024+1)
    need(len(raw)<=16*1024*1024 and len(raw)==record['uncompressed_bytes']and hashlib.sha256(raw).hexdigest()==record['uncompressed_sha256'],'Selected timing event payload changed')
    events=[json_bytes(line)for line in raw.splitlines()];need(len(events)==record['events'],'Selected timing event count differs');return events


def aggregate(metrics,durations):
    rows={}
    for code,temperature in enumerate(TEMPS):
        keys=[f'matched128/around128-t{code}-run{repeat}'for repeat in(1,2)]
        samples=[value for key in keys for value in durations[key][1:]]
        need(len(samples)==254,'Matched temperature must contain exactly254 cached outputs')
        total=math.fsum(samples);rows[temperature]=dict(runs=2,generated_outputs=256,cached_outputs=254,
            cached_command_seconds=total,weighted_cached_command_tokens_per_second=254/total,
            per_run_cached_command_tokens_per_second=[metrics[key]['cached_command_tokens_per_second']for key in keys])
    return rows


def validate_native(summary,image_sha256,hardware_digest):
    need(summary['schema']=='long-context-current-native-numerical-summary-v8-baseline-selected-native'and summary['image_sha256']==image_sha256
         and summary['hardware_inputs_sha256']==hardware_digest,'Native numerical image/source association differs')
    choice=selected_native_contract();image=CHOSEN_NATIVE_IMAGE_AUTHORITY
    need(summary['placement_option']==choice['placement']and summary['routing_option']==choice['routing']
         and summary['replication_option']==choice['replication']
         and summary['implemented_recipe_sha256']==choice['implemented_recipe_sha256'],
         'Native recipe is not the exact selected R1/P3 contract')
    need(summary['route_maxfan']==60 and summary['native_recipe']==cap60_public_recipe('d3a7a2bc2d3f58854466173183dc27dec9877bf1eca7237c782866a5e1d51730'),
         'Timing selected-native full recipe/comparison profile differs')
    need(summary['image_sha256']==image['image_sha256']and summary['source_build']['sha256']==image['native_finished_sha256']
         and summary['source_audit']['sha256']==image['native_audit_sha256']and summary['source_vo']['sha256']==image['vo_sha256'],
         'Native summary differs from chosen actual FIN/audit/FS/VO authority')
    for name in('source_audit','source_build','source_admission','source_resource_report','source_timing_report','source_vo'):source_identity(summary[name])
    need(summary['requested_inference_clock_mhz']==25 and number(summary['reported_inference_fmax_mhz'],True)>=25
         and number(summary['core_setup_slack_ns'])>=0 and number(summary['core_hold_slack_ns'])>=0,'Native core screen differs')
    expected_clocks={'board_clk50':50,'memory_clk400':400,'app_clk100':100,'trusted_clk12p5':12.5,'inference_clk25':25}
    need(set(summary['clock_summaries'])==set(expected_clocks),'Native clock summary census differs')
    for name,value in summary['clock_summaries'].items():
        need(value['constraint_mhz']==expected_clocks[name]and number(value['actual_fmax_mhz'],True)>=value['constraint_mhz'],'Native clock target/screen differs')
    need(summary['clock_summaries']['inference_clk25']['actual_fmax_mhz']==summary['reported_inference_fmax_mhz'],'Native Fmax summaries disagree')
    need(set(summary['resources'])=={'BSRAM','CLS','DSP','Logic','Register'},'Resource census differs')
    for row in summary['resources'].values():need(number(row['used'])<=number(row['available'],True),'Resource usage exceeds capacity')
    tables=summary['negative_endpoint_tables'];need(set(tables)=={'setup','hold','recovery','removal'},'Negative endpoint table census differs')
    targets={};vendor={};nonvendor={}
    for kind,table in tables.items():
        rows=table['negative_paths'];targets[kind]=set();vendor[kind]=set();nonvendor[kind]=set()
        for row in rows:
            digest(row['target_sha256']);digest(row['source_sha256']);need(type(row['vendor_ddr'])is bool and type(row['slack_ns'])in(int,float)
                and math.isfinite(row['slack_ns'])and row['slack_ns']<0,'Invalid sanitized negative path')
            targets[kind].add(row['target_sha256']);(vendor if row['vendor_ddr']else nonvendor)[kind].add(row['target_sha256'])
        for name in('negative_path_count','negative_endpoint_count','vendor_negative_endpoint_count','nonvendor_negative_endpoint_count'):integer(table[name])
        need(table['negative_path_count']==len(rows)and table['negative_endpoint_count']==len(targets[kind])
             and table['vendor_negative_endpoint_count']==len(vendor[kind])and table['nonvendor_negative_endpoint_count']==len(nonvendor[kind]),'Negative endpoint counts differ')
        need(integer(table['reported_rows'])>=len(rows)and integer(table['report_limit'])>=table['reported_rows'],'Truncated endpoint table')
    for group,kinds in(('setup',('setup','recovery')),('hold',('hold','removal'))):
        total=set.union(*(targets[k]for k in kinds));v=set.union(*(vendor[k]for k in kinds));n=set.union(*(nonvendor[k]for k in kinds))
        row=summary['negative_endpoint_unions'][group]
        for value in row.values():integer(value)
        integer(summary['global_violated_endpoints'][group])
        need(row==dict(total=len(total),vendor=len(v),nonvendor=len(n),overlap=len(v&n))
             and summary['global_violated_endpoints'][group]==len(total),'Global vendor/nonvendor endpoint reconciliation differs')
    need(all(not rows for rows in nonvendor.values())and summary['endpoint_census_complete']is True
         and summary['nonvendor_screen_clear']is True and summary['complete_timing_signoff']is False
         and summary['mapped_image_equivalence']is False and summary['hardware_access']is False,'Unsupported timing/signoff scope')
    return dict(recorded_native_numerical_summary_checked=True,complete_timing_signoff=False,raw_vendor_timing_replayed=False)


def authority():
    require_v8_baseline_scope()
    need(SOURCE_REVIEWED is True,'V8 SHA2 timing source/producer policy is pending review; no timing evidence is admitted')
    choice=selected_native_contract()
    for value in(PLANNER,BOARD,REVIEWED_POLICY,choice['builder_sha256'],choice['auditor_sha256'],PROOF_BINDER,MAPPED_ROM_VALIDATOR,
                 SOURCE_BINDING,PROOF_INVENTORY,REUSED_SCOPE_METADATA_SHA):digest(value)
    need(type(SOURCE_BINDING_BYTES)is int and SOURCE_BINDING_BYTES>0
         and type(SOURCE_BINDING_PATHS_COUNT)is int and SOURCE_BINDING_PATHS_COUNT>0
         and type(SOURCE_PROOF_FIELDS)is tuple and type(SOURCE_PROOF_PUBLIC_CONTRACT)is dict
         and all(key in SOURCE_PROOF_FIELDS for key in CACHE_FIELDS)
         and type(CACHE_SCOPE_CONTRACT)is dict and bool(CACHE_SCOPE_CONTRACT),
         'Actual complete cache/source projection pins remain pending')


def validate_v7_bindings(record,native):
    """Recorded seven unchanged scopes plus separate fresh cache/ROM and mapped links."""
    require_v8_baseline_scope()
    scope=record['source_scope'];mapped=record['mapped_canonical_rom_audit']
    need(type(SOURCE_PROOF_FIELDS)is tuple and type(SOURCE_PROOF_PUBLIC_CONTRACT)is dict
         and all(key in SOURCE_PROOF_FIELDS for key in CACHE_FIELDS)
         and type(CACHE_SCOPE_CONTRACT)is dict and bool(CACHE_SCOPE_CONTRACT),
         'Actual reviewed fresh-cache/source projection contract is pending')
    fields={'schema','source_binding_receipt','validator_sha256','private_proof_inventory_sha256','checked_paths_count',
        'scope_names','limits','counting','divider_equivalence_chain','nonadditive','aggregate_assertion_total',
        'shared_mac_proof_credited','old_cache141_credited'}|set(SOURCE_PROOF_FIELDS)
    need(set(scope)==fields and scope['schema']=='long-context-timing-source-scope-v8-baseline-selected-native',
         'Wrong current timing source-scope fields')
    source_identity(scope['source_binding_receipt'])
    need(scope['source_binding_receipt']==dict(sha256=SOURCE_BINDING,bytes=SOURCE_BINDING_BYTES)
         and scope['validator_sha256']==PROOF_BINDER and scope['private_proof_inventory_sha256']==PROOF_INVENTORY
         and scope['checked_paths_count']==SOURCE_BINDING_PATHS_COUNT and scope['scope_names']==sorted(SCOPES)
         and scope['nonadditive']is True and scope['aggregate_assertion_total']is None
         and scope['shared_mac_proof_credited']is False and scope['old_cache141_credited']is False,
         'Current timing source scope lacks the actual complete fresh-cache binding')
    need(canonical({key:scope[key]for key in SOURCE_PROOF_FIELDS})==canonical(SOURCE_PROOF_PUBLIC_CONTRACT)
         and 'changed_cache_stage_proof'in SOURCE_PROOF_PUBLIC_CONTRACT
         and 'changed_exp_rom_proof'in SOURCE_PROOF_PUBLIC_CONTRACT,
         'Separate actual cache/ROM projection contracts differ')
    retained_scope_fragment(scope)
    cache={key:scope[key]for key in CACHE_FIELDS}
    need(cache['old_cache141_credited']is False and type(cache['changed_cache_stage_proof'])is dict
         and bool(cache['changed_cache_stage_proof']) and canonical(cache['changed_cache_stage_proof'])==canonical(CACHE_SCOPE_CONTRACT),
         'Current full fresh-cache fragment differs from the actual audited contract')
    need(sha256(canonical({key:scope[key]for key in('limits','counting','divider_equivalence_chain')}))==REUSED_SCOPE_METADATA_SHA,
         'Seven-scope limits/counting/divider-chain premises changed')
    rom=scope['changed_exp_rom_proof']
    need(sha256(canonical(rom))==ROM_PROJECTION_SHA and rom['passed']is True
         and rom['candidate_sha256']==ROM_SOURCE and rom['default_table_sha256']==TABLE_SOURCE
         and rom['scope_premises_not_dropped']is True and rom['shared_mac_proof_credited']is False
         and rom['mapped_canonical_rom_audit_required_before_preload']is True
         and rom['mapped_canonical_rom_audit_passed']is False,
         'Source ROM FILE/initial-state premises or nonadditive limits changed')
    fields={'schema','passed','image_sha256','hardware_inputs_sha256','native_finished_sha256','vo_sha256',
        'rom_source_sha256','canonical_table_sha256','validator_sha256','source_record','proof_inventory_sha256',
        'checked_paths_count','summary','whole_image_equivalence','hardware_access','replayed_by_recipient'}
    need(set(mapped)==fields and mapped['schema']=='long-context-current-mapped-rom-public-v8-baseline-selected-native'
         and mapped['passed']is True and mapped['whole_image_equivalence']is False
         and mapped['hardware_access']is False and mapped['replayed_by_recipient']is False
         and mapped['validator_sha256']==MAPPED_ROM_VALIDATOR,
         'Actual V8 SHA2 mapped canonical-ROM record is absent or overclaims')
    for key in('image_sha256','hardware_inputs_sha256','native_finished_sha256','vo_sha256','rom_source_sha256',
               'canonical_table_sha256','validator_sha256','proof_inventory_sha256'):digest(mapped[key])
    source_identity(mapped['source_record']);integer(mapped['checked_paths_count'])
    need(mapped['source_record']['bytes']>0 and mapped['checked_paths_count']>0
         and mapped['image_sha256']==record['image_sha256'] and mapped['hardware_inputs_sha256']==record['hardware_inputs_sha256']
         and mapped['native_finished_sha256']==native['source_build']['sha256']
         and mapped['vo_sha256']==native['source_vo']['sha256'] and mapped['rom_source_sha256']==ROM_SOURCE
         and mapped['canonical_table_sha256']==TABLE_SOURCE and type(mapped['summary'])is dict
         and type(mapped['summary']['canonical_addresses'])is int and mapped['summary']['canonical_addresses']==4097
         and mapped['summary']['audit_record_sha256']==mapped['source_record']['sha256']
         and mapped['summary']['image_sha256']==record['image_sha256'],
         'V8 SHA2 mapped audit is detached from current image/native FIN/VO/source/table/record')
    encoded=json.dumps(dict(source_scope=scope,mapped_canonical_rom_audit=mapped),sort_keys=True,allow_nan=False)
    need(not any(prefix in encoded for prefix in('/Users/','/Volumes/','/private/','/opt/homebrew/')),
         'Private path in V8 SHA2 timing source/mapped metadata')
    return dict(recorded_scoped_ROM_and_mapped_associations_checked=True,solver_or_mapped_VO_replayed=False,
        shared_mac_proof_credited=False,whole_image_equivalence=False)


def bind_active_metadata(record,native,active):
    """Pure metadata linkage; this alone grants no image/physical qualification."""
    require_v8_baseline_scope()
    candidate,source,build,cli=(active[name]for name in('candidate','source','build','cli'))
    image=record['image_sha256'];hardware=record['hardware_inputs_sha256'];model=record['model_image_sha256']
    need(active['fs']['sha256']==candidate['image_sha256']==source['image_sha256']==build['image_sha256']==cli['image_sha256']==image,
         'Timing record is detached from the active image')
    inventory=active['inventory'];need(candidate['native_source_sha256']==inventory
         and sha256(canonical(inventory))==candidate['hardware_inputs_sha256']==source['hardware_inputs_sha256']==build['hardware_inputs_sha256']==cli['hardware_inputs_sha256']==hardware,
         'Timing record is detached from the active hardware inventory')
    need(active['model']['sha256']==candidate['model_image_sha256']==cli['model_image_sha256']==model,
         'Timing record is detached from the active model asset')
    need(source['image_bytes']==build['image_bytes']==active['fs']['bytes'],'Active FS size association differs')
    need(build['original_build_receipt_sha256']==source['native_build_receipt_sha256']==native['source_build']['sha256']
         and build['native_timing_inspection_sha256']==source['native_timing_inspection_sha256']==native['source_audit']['sha256'],
         'Active BUILD/native audit provenance differs from timing summary')
    need(source['complete_model_receipt_sha256']==record['source_roles']['complete_model']['sha256']
         and source['model_assembly_receipt_sha256']==candidate['model_assembly_receipt_sha256']==record['source_roles']['model_assembly']['sha256'],
         'Active complete-model/assembly provenance differs')
    need(candidate['cli_evidence']==active['cli_identity'],'Active CLI identity differs')
    campaigns={row['suite']:row for row in cli['campaigns']};need(len(campaigns)==len(cli['campaigns']),'Duplicate active CLI suite role')
    for suite,origin in record['campaign_sources'].items():
        need(suite in campaigns and campaigns[suite]['source_receipt_sha256']==origin['finished']['sha256'],
             'Active CLI campaign receipt differs from timing origin')
        cases={row['label']:row for row in campaigns[suite]['cases']};expected={key.split('/',1)[1]:case for key,case in record['cases'].items()if key.startswith(suite+'/')}
        need(len(cases)==len(campaigns[suite]['cases'])and set(cases)==set(expected),'Active CLI timing case census differs')
        for label,case in expected.items():
            need(cases[label]['source_raw_sha256']==case['source_raw']['sha256']and cases[label]['generated_tokens']==case['summary']['generated_tokens'],
                 'Active CLI raw source/main outputs differ from timing case')
    need(record['source_roles']['model_assembly']['sha256']==MODEL_ASSEMBLY,'Timing belongs to another model packet')
    proof=active['proof'];scope=record['source_scope'];mapped=record['mapped_canonical_rom_audit']
    need(proof['schema']=='long-context-current-scoped-proofs-record-v4' and proof['passed']is True
         and candidate['current_scoped_proofs']==dict(path='evidence/seeded-sampling/current-scoped-proofs-v4.json',**active['proof_identity'])
         and proof['image_sha256']==image and proof['native_source_sha256']==inventory
         and proof['model_tested_source_sha256']==candidate['model_tested_source_sha256'],
         'Timing source scope is detached from active proof/image/source roles')
    need(type(SOURCE_PROOF_FIELDS)is tuple,'Actual source/cache projection contract is pending')
    for key in('validator_sha256','private_proof_inventory_sha256','checked_paths_count',
               'limits','counting','divider_equivalence_chain',*SOURCE_PROOF_FIELDS):
        need(canonical(proof[key])==canonical(scope[key]),'Active source/cache proof differs from timing source metadata: '+key)
    retained_scope_fragment(scope)
    cache={key:scope[key]for key in CACHE_FIELDS}
    need(cache['old_cache141_credited']is False,'Historical cache141 credit is forbidden')
    for value in(candidate,source,build,cli,proof):
        need(canonical(retained_scope_fragment(value))==canonical(retained_scope_fragment(scope)),
             'Full retained source/SHA-boundary fragment differs across all five timing artifacts')
        need(canonical({key:value[key]for key in CACHE_FIELDS})==canonical(cache),
             'Full fresh-cache fragment differs across timing/five current artifacts')
    need(set(proof['scopes'])==SCOPES and sha256(canonical(proof['scopes']))==REUSED_SCOPES
         and inventory[KV]==KV_SOURCE and inventory[EXP]==ROM_SOURCE and inventory[TABLE]==TABLE_SOURCE and inventory[ATTENTION]==ATTENTION_SOURCE
         and 'changed_attention_mac_proof'not in proof,'Active V8 SHA2 source scope or MAC credit differs')
    for value in(candidate,source,build,cli,proof):
        need(value['mapped_canonical_rom_audit']==mapped,'Active mapped audit differs across timing/five current binding artifacts')
    need(candidate['native_build_receipt_sha256']==source['native_build_receipt_sha256']==build['original_build_receipt_sha256']
         ==cli['native_build_receipt_sha256']==mapped['native_finished_sha256']
         and candidate['native_vo_product_sha256']==source['native_vo_product_sha256']==build['native_vo_product_sha256']
         ==cli['native_vo_product_sha256']==mapped['vo_sha256'],'Active V8 SHA2 FIN/VO and mapped source roles differ')
    return True


def sha256(raw):return hashlib.sha256(raw).hexdigest()


def bind_current_release(package,record,native,wire_projection):
    manifest=read(package,'MANIFEST.json');files=manifest['files']
    names={'candidate':'CANDIDATE.json','source':'variants/seeded-sampling/SOURCE.json',
        'build':'prebuilt/seeded-sampling/BUILD.json','cli':'evidence/seeded-sampling/current-candidate-cli.json',
        'inventory':'host-app/hardware-inputs-seeded-sampling.json',
        'proof':'evidence/seeded-sampling/current-scoped-proofs-v4.json'}
    active={key:read(package,name)for key,name in names.items()}
    need(active['candidate']['schema']=='long-context-private-recipient-v1'and active['source']['schema']=='fixed-seeded-source-binding-v8-baseline-selected-native'
         and active['build']['schema']=='fixed-fpga-local-build-v1'and active['build']['variant']=='seeded-sampling'
         and active['build']['flow_completed']is True and active['cli']['schema']=='long-context-current-cli-public-v1'
         and active['cli']['physical_campaign_schema']=='long-context-physical-campaign-v8-baseline-selected-native','Wrong active release record roles')
    need(len(active['inventory'])==91 and active['source']['native_inputs']==91 and active['source']['distributable_inputs']==87,'Active source census differs')
    fs='prebuilt/seeded-sampling/project/impl/pnr/shared_product.fs';model='assets/board1-real-semantic-image2048.bin'
    active.update(fs=identity(target(package,fs)),model=identity(target(package,model)),cli_identity=identity(package/names['cli']),
        proof_identity=identity(target(package,names['proof'])))
    bind_active_metadata(record,native,active)
    need(set(row['suite']for row in active['cli']['campaigns'])=={'control','registration','matched128','context','seed-domain','recovery','around'},'Active current CLI suite set differs')
    for suite in active['cli']['campaigns']:
        if suite['suite']not in record['campaign_sources']:continue
        need(suite['image_sha256']==record['image_sha256']and suite['physical_fpga']is True,'Active CLI physical image role differs')
        for case in suite['cases']:
            wire=[]
            for event in case['wire']:
                need(event['operation']==event['expected_operation'],'Active CLI operation label changed')
                wire.append((event['direction'],event['operation'],event['frame_hex'],event.get('output_role')if event['direction']=='rx'else None))
            need(wire==wire_projection[suite['suite']+'/'+case['label']],'Active CLI wire/role differs from timed original')
    consumed=set(names.values())|{fs,model,RECORD,NATIVE,'tools/check_long_context_timing.py',
        'evidence/seeded-sampling/timing-sources/wire-client-exchange.txt'}
    consumed|={case['selected_events']['path']for case in record['cases'].values()}
    consumed|={case['selected_events']['path']for case in record['parent']['cases'].values()}
    reference=read(package,'reference/seeded-sampling/SOURCE.json')
    consumed|={'reference/seeded-sampling/SOURCE.json'}|{'reference/seeded-sampling/'+name for name in reference['files']}
    for name in consumed:need(name in files and identity(target(package,name))==files[name],'Timing/current input is absent or changed in active MANIFEST: '+name)
    return True


def check(package,require_current_release=True):
    require_v8_baseline_scope()
    authority()
    package=Path(package).resolve();need(TIMING_RECORD_SHA is not None and NATIVE_SUMMARY_SHA is not None,'Timing evidence has no actual final pins')
    record=read(package,RECORD,TIMING_RECORD_SHA)
    need(record['schema']=='long-context-current-timing-record-v8-baseline-selected-native'and record['timer']==TIMER,'Timing record/measurement contract differs')
    digest(record['image_sha256']);digest(record['hardware_inputs_sha256']);need(record['image_sha256']!=PARENT_IMAGE and record['model_image_sha256']==MODEL,'Current timing image/model role differs')
    need(record['source_roles']['planner_sha256']==PLANNER and record['source_roles']['board_sha256']==BOARD
         and record['source_roles']['reviewed_policy_sha256']==REVIEWED_POLICY
         and record['source_roles']['native_producer_sha256']==selected_native_contract()['builder_sha256']
         and record['source_roles']['native_auditor_sha256']==selected_native_contract()['auditor_sha256']
         and record['source_roles']['proof_validator_sha256']==PROOF_BINDER
         and record['source_roles']['mapped_validator_sha256']==MAPPED_ROM_VALIDATOR,'Reviewed timing producer roles differ')
    for name in('promotion_plan','promotion_inputs','reviewed_policy','complete_model','model_assembly'):source_identity(record['source_roles'][name])
    need(record['source_roles']['reviewed_policy']['sha256']==REVIEWED_POLICY,'Timing policy source differs')
    source=target(package,'evidence/seeded-sampling/timing-sources/wire-client-exchange.txt')
    need(identity(source)['sha256']==EXCHANGE_SOURCE,'Released timer source differs')
    labels={f'matched128/around128-t{code}-run{repeat}'for code in range(4)for repeat in(1,2)}
    labels|={f'context/{name}-t{code}-seed-a'for code in range(4)for name in('prefix128','prefix512','prefix2047','prefix2048')}
    need(set(record['cases'])==labels,'Timing requires all16 context and8 matched128 cases')
    metrics={};durations={};wire_projection={}
    need(set(record['campaign_sources'])=={'context','matched128'},'Timing campaign source-role census differs')
    for suite,count in(('context',16),('matched128',8)):
        source=record['campaign_sources'][suite];need(source['case_count']==count,'Timing physical case census differs')
        source_identity(source['finished']);source_identity(source['plan'])
    for key,case in record['cases'].items():
        suite,label=key.split('/');need(case['suite']==suite and case['label']==label,'Timing case role differs')
        need(set(case)=={'suite','label','source_campaign','source_plan','source_case','source_raw','selected_events','summary'},'Unsafe/unknown timing case fields')
        for name in('source_campaign','source_plan','source_case','source_raw'):source_identity(case[name])
        need(case['source_campaign']==record['campaign_sources'][suite]['finished']and case['source_plan']==record['campaign_sources'][suite]['plan'],'Timing case original campaign/plan role differs')
        events=event_archive(package,case['selected_events']);expected=expected_workload(package,suite,label)
        metrics[key],durations[key]=replay_case(events,expected,case['summary'])
        wire_projection[key]=[('tx'if row['event']=='tx_attempt'else'rx',row['operation'],row['frame_hex'],row['role']if row['event']=='raw_rx'else None)
            for row in events if row['event']in('tx_attempt','raw_rx')]
    need(record['derived_case_metrics']==metrics and record['matched128']==aggregate(metrics,durations),'Published command/cached metrics differ')
    parent=record['parent'];need(parent['image_sha256']==PARENT_IMAGE and parent['source_finished']['sha256']==BASELINE
        and parent['source_public_record']['sha256']==PUBLIC_BASELINE and set(parent['cases'])==set(BASELINE_TIMES),'Parent baseline roles differ')
    source_identity(parent['source_finished']);source_identity(parent['source_public_record']);source_identity(parent['source_plan']);comparisons={}
    for label,seconds in BASELINE_TIMES.items():
        case=parent['cases'][label]
        for name in('source_campaign','source_plan','source_case','source_raw'):source_identity(case[name])
        need(case['source_campaign']==parent['source_finished']and case['source_plan']==parent['source_plan'],'Parent original campaign/plan role differs')
        old,_=replay_case(event_archive(package,case['selected_events']),expected_workload(package,'context',label),case['summary'],False)
        need(old['first_step_seconds']==seconds,'Exact hashed parent first-STEP value differs')
        current=metrics['context/'+label]['first_step_seconds'];comparisons[label]=dict(parent_first_step_seconds=seconds,current_first_step_seconds=current,measured_speedup=seconds/current)
    need(record['parent_comparisons']==comparisons,'Parent speed comparison differs')
    native=read(package,NATIVE,NATIVE_SUMMARY_SHA);need(record['native_summary']==dict(path=NATIVE,**identity(package/NATIVE)),'Native timing summary identity differs')
    native_result=validate_native(native,record['image_sha256'],record['hardware_inputs_sha256'])
    source_result=validate_v7_bindings(record,native)
    need(record['browser_timing_published']is False and record['configuration_independently_attested']is False
         and record['complete_timing_signoff']is False,'Unsupported browser/configuration/timing claim')
    bound=bind_current_release(package,record,native,wire_projection)if require_current_release else False
    return dict(schema='long-context-timing-record-replay-v1',recorded_cases=24,matched128_trials=8,
        temperature1_weighted_cached_tokens_per_second=record['matched128']['1']['weighted_cached_command_tokens_per_second'],
        parent_comparisons=comparisons,**native_result,**source_result,current_release_bound=bound,hardware_access=False,model_replayed=False,browser_timing_published=False,
        scope='Source-bound recorded durations, wire/reference roles and numerical summaries replayed. No exact clock-start reconstruction, live hardware/browser measurement or complete timing signoff.')


def main():
    require_v8_baseline_scope()
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--package',type=Path,default=Path(__file__).resolve().parents[1])
    mode=parser.add_mutually_exclusive_group();mode.add_argument('--detached',dest='require_current_release',action='store_false',help='Explicit producer-only bundle replay; grants no current-release binding')
    mode.add_argument('--require-current-release',dest='require_current_release',action='store_true');parser.set_defaults(require_current_release=True);args=parser.parse_args()
    print(json.dumps(check(args.package,args.require_current_release),indent=2,sort_keys=True,allow_nan=False))


if __name__=='__main__':main()
