"""Check historical encrypted component summaries and two unchanged current AES sources.

Old model output records remain historical. Current CFC model/native/physical
qualification is checked separately by the current-three-greedy capsule reader.
"""
import hashlib
import json
from pathlib import Path, PurePosixPath
import re

ROOT = Path(__file__).resolve().parents[1]
IMAGE = '865e74e692d5978815fe921f11e4fa1b8e2c080401a8be05508dd9775823aecc'
INPUTS = '840c12ce7d1a5886966aca73e7c44eb3e42b9ee07ab33adcb2de3d273125e262'
CURRENT_INVENTORY_SHA='3361bbe05cd8ea087553a674ef0b3bcf2071d5131ef0b2f84bff150a1a4ba86b'
RECORD_SHA='74938c20c3ca122fea8fd91edfff16c3f37b33ae81ec577169a4a643c0cf8f32'
ORIGINAL_PRODUCTION_SOURCES={'project/adapter.sv': 'dd45423f8cc645a04bef821130faa5c0a7e4d9a81333c571db23c0139b8314e9',
 'project/arbiter.sv': '51f7e2d73f43ff02b934ae749fa790efa94c015b280cfa25ef7558c2c087605a',
 'project/bank.sv': 'e1277841ee17a3e31115d0392d4c52ecb7f87fe16c0f36091066bce03bd0ad55',
 'project/booted_memory.sv': 'e249a2fe7fe65b2cf27cb18d276977368a8f627e28007147addfa4ba388b697a',
 'project/candidate.sv': 'dd5a9d7a906e8645ea40a090c00ed3563ad252be692a2717b35cf3fe4e4d8374',
 'project/cdc.sv': 'aa564a0d1c65d6da82aac3242afea1ccc5e692a160aab0d9577b63ae31569b1e',
 'project/cluster-adapter.sv': '0b8d09a0fded73d93f5fddb6bc790b552968f2d8c38cf0e90d20eb5d49b9744b',
 'project/cluster-engine.sv': '715ac8ac24a45bb4389f905ad58fad84735c7dde2a41780b7a95fc409dc3ae54',
 'project/cluster-mul.sv': '93e12f47a8651a1c131609d132f7b50810ac1124200e583164fad3b83e589417',
 'project/cluster-tile.sv': '4aa3e7e95da24d4def91b772acaf166f245aac6a4c8651b109424a25436221c5',
 'project/fifo.sv': '1879b79074421cddd57592d0320f4c68c42f4a86e0ba3b10a554bf97cb2d2fa9',
 'project/fpga/token_only_model0_board0/rtl/physical/board0_exact_isqrt_u45_iterative.sv': 'c5ebf144aa1ba50e0459dc069ec6a38d49829cc921c5752fd21466bc89ab678a',
 'project/fpga/token_only_model0_board0/rtl/physical/board0_exact_rne_div_signed64_iterative.sv': 'efe1992ec59e927ab1bb24008477c1f7f31eaf9ef613e3215bb6011513b15193',
 'project/fpga/token_only_model0_ddr_board1/asymmetric_unified_dsp2/rtl/board1_asymmetric_private_issue_guard.sv': '95a555560d3b9f3c7e4d22bbabe1bdabc602364ce392e5a2da573e889f59499a',
 'project/fpga/token_only_model0_ddr_board1/asymmetric_unified_dsp2/rtl/board1_asymmetric_unified_dsp64.sv': 'e99f1e5049af79b53e42f681a4082451158c9912a43eb35397fd76f9acb15560',
 'project/fpga/token_only_model0_ddr_board1/context2048_gowin_portability0/rtl/board1_context2048_atomic_kv_typed_clear_consistent.sv': 'a41a61dd6a1a585adc6aaa3f36643a05046c98ed9350187d96c8dce7a5f79af7',
 'project/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_attention.sv': '5b8267c4da1a5b7be33e8f37be29d084f53394e45082e5f8dad7b685d0bf9a73',
 'project/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_attention_memories.sv': '922a5777c17a967fde39a2b8336ad819fcb6709d2b9a8b3552675188d32d1c34',
 'project/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_semantic_datapath.sv': '4c1e2e2eeef7eeb0736be32545336d49acce752088f5339a2e3ca6621e304dcc',
 'project/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_semantic_layer.sv': 'ec0c0a1527d7b9d480000187e09edea32d3236e8d6b844db032ac303fbc6b8e6',
 'project/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_semantic_lookup.sv': '92d8043230d9df3ab917427c4c619a5b57f918c2669abec310fe805d440034ef',
 'project/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_semantic_sequence.sv': 'f7ebce15ce1d3ee97d968014d17051ddd942d3dd2d582368e4aa81b6e0e52205',
 'project/fpga/token_only_model0_ddr_board1/context2048_token_machine2/rtl/board1_context2048_token_machine_core.sv': '0e4a38023c711abae1bdf1173444601723dc90a25b1f414c5618bf908432d4da',
 'project/fpga/token_only_model0_ddr_board1/context2048_token_machine2/rtl/board1_context2048_token_shell.sv': '55d56d5a4add9afa81b5622303ff0c81c27734fe23ac7ffa5b849d3944d8fe62',
 'project/fpga/token_only_model0_ddr_board1/context2048_typed_ddr_boundary0/rtl/board1_context2048_typed_ddr_app_boundary.sv': 'e893c0ca812a438d6e758690b3b5de3e7b8a92811dc8f1d85827312a149117d3',
 'project/fpga/token_only_model0_ddr_board1/context2048_typed_ddr_boundary0/rtl/board1_context2048_typed_ddr_boundary.sv': '8afb20c1c58790209023826f21ba9b5fe57af3a359cf77508c66e730a7137b14',
 'project/fpga/token_only_model0_ddr_board1/ddr_phy_open0/rtl/board1_private_ddr256_to_w640.sv': 'f2ba8bddfb40087af7c420b931631e7f83a12aae96510b232bb6ade853a9eedc',
 'project/fpga/token_only_model0_ddr_board1/ddr_preboard_closure0/rtl/board1_ddr_request_fifo2.sv': '084af34e394e9024f9a9b8d227f6c2385e0b161048c6091751e67ec6d8fd656f',
 'project/fpga/token_only_model0_ddr_board1/fixed_attention0/rtl/board1_fixed_attention_exp_lut_sync.sv': 'e47bf421e10435e6bffa10e0219415630d57ef00ccdc4040ca7d8d9f720e9477',
 'project/fpga/token_only_model0_ddr_board1/fixed_attention0/rtl/board1_fixed_attention_rne_div_signed64.sv': 'c09e6e1f864a9827a372d7486b22d20d3e6db700df6aff410d982c7b93a84e2d',
 'project/fpga/token_only_model0_ddr_board1/fixed_attention_compact1/rtl/board1_fixed_attention_rne_shift_iterative.sv': '7dece06c509b57f15859ec33cc758bc1734de572c5b3e55efa37774678f64854',
 'project/fpga/token_only_model0_ddr_board1/fixed_elementwise0/rtl/board1_fixed_elementwise_dsp_lane.sv': 'bd475b396f351e117a2c9740417a5dedeed7e4c7fc5d32d9d62bffd09417c19a',
 'project/fpga/token_only_model0_ddr_board1/fixed_elementwise_product_compact1/rtl/board1_fixed_elementwise_product_compact_lane.sv': '8d753b5e0e28b5f8bbbbdfdfe3b8894808e068068f44f57fa1b77cdec8a743eb',
 'project/fpga/token_only_model0_ddr_board1/fixed_elementwise_product_compact1/rtl/board1_fixed_elementwise_product_dsp.sv': '1c60a777659e7dea8ba1e13ed9d76ac0e6df544a9c70ccc7327d0e20c0fba5a9',
 'project/fpga/token_only_model0_ddr_board1/fixed_group_ddr_stream1/rtl/board1_fixed_group_ddr_stream.sv': 'cb40225f531224076ef6b1f32e2c856a146aa017ec5d71fb9424bdbe7ee2c359',
 'project/fpga/token_only_model0_ddr_board1/fixed_group_projection_scale_integration0/rtl/board1_fixed_group_projection_scale_job.sv': '653a0eebffff3724312847baf64c5eb188afdaea50ca3b2acb6d4e6e1e888339',
 'project/fpga/token_only_model0_ddr_board1/fixed_head_argmax0/rtl/board1_fixed_head_argmax.sv': '4491df0baa6e4e6ab4995d30c1ad64bfd87b418acdc0bd2a39672266f6f46b68',
 'project/fpga/token_only_model0_ddr_board1/fixed_head_argmax0/rtl/board1_fixed_head_logit_greater.sv': '9f1fd555ad0165d3617b3c0078c3ef5c9b9971824350aebb2f63a072a2a03a44',
 'project/fpga/token_only_model0_ddr_board1/fixed_metadata_stream0/rtl/board1_fixed_projection_metadata_reader.sv': '7eeb100adaa0c9402ff51d3df19707f7248987e1ec2f16b2f925d7d43e5faedc',
 'project/fpga/token_only_model0_ddr_board1/fixed_semantic_layer0/rtl/board1_fixed_semantic_rope_raw_ram.sv': 'd8b9f6c8229af472f8d69858f9412cbcd58991f58b4f4fb2feb508fd5d0b0e21',
 'project/fpga/token_only_model0_ddr_board1/fixed_semantic_layer0/rtl/board1_fixed_semantic_scratch_ram.sv': 'dbf09b83baf263397db18970535e41c8c3ab487e9f8926ca8a8740b58f65f901',
 'project/fpga/token_only_model0_ddr_board1/fixed_semantic_layer0/rtl/board1_fixed_semantic_vector128_ram.sv': '9282e788fc641f15f225986738a8a9d605c892b210e060763622026a5b05310a',
 'project/fpga/token_only_model0_ddr_board1/fixed_semantic_layer0/rtl/board1_fixed_semantic_vector256_ram.sv': '0767c4a1c69432f9537385223101d2e6d69a86259313ed9a27cff10cb9ccff57',
 'project/fpga/token_only_model0_ddr_board1/fixed_token_machine0/rtl/board1_fixed_private_ddr_arbiter.sv': 'e7cbb695697bd9d9c3cad5909927ad3bb512c03d99560b037693b86967affdd9',
 'project/fpga/token_only_model0_ddr_board1/fixed_token_machine1/rtl/board1_fixed_elementwise_lane_core.sv': '9e033db09b614f43999a94692d0f19a7ec58845dc65963d2e37a0e9d134bf7af',
 'project/fpga/token_only_model0_ddr_board1/fixed_token_shell0/rtl/board1_fixed_embedding_lookup.sv': '3fd4eea786b6ecde1f7d27199f3ef9d434d8692346ec12997cda688aa0766211',
 'project/fpga/token_only_model0_ddr_board1/fixed_vector_normalize0/rtl/board1_fixed_vector_rne_shift_iterative.sv': '22159952c558c41366eee3abc6f0932867e482a94bfde16d7f26f0a3228fd05b',
 'project/fpga/token_only_model0_ddr_board1/fixed_vector_rmsnorm0/rtl/board1_fixed_rmsnorm_arithmetic.sv': 'd95bb60428664695eabaa51ecab6aa6462d2657156ac7351ce79867347fefbc5',
 'project/fpga/token_only_model0_ddr_board1/fixed_vector_rmsnorm0/rtl/board1_fixed_rmsnorm_rom.sv': '46e85006cbe336e763414b117bad314078df448f897c707e83af0cee1dc92561',
 'project/fpga/token_only_model0_ddr_board1/fixed_vector_rmsnorm0/rtl/board1_fixed_vector_rmsnorm_service.sv': '739c55b600f56592841f7ca02dd034347c42fdc6c21b0c745e516d67e15ba2ae',
 'project/fpga/token_only_model0_ddr_board1/product8_timing_successor2/rtl/board1_context2048_ddr_locked_auth_watchdog_cdc.sv': '6d88adfc043926beedb41bba63f22f8d0b3793dc8bc87ea5a94b30169e6c4763',
 'project/fpga/token_only_model0_ddr_board1/product8_timing_successor2/rtl/board1_context2048_private_ddr_lock_bridge.sv': '71ecc05bad160b500ec2564dcbed62de196972d1b10673a1452af7049325b818',
 'project/fpga/token_only_model0_ddr_board1/product_top4/rtl/board1_context2048_ddr_preboard_locked_boundary.sv': '58760e39d6d82070f595b2b9d93d7116bc8864d4b0abc572cb2e2fc5fceaa8e9',
 'project/fpga/token_only_model0_ddr_board1/product_top4/rtl/board1_context2048_semantic_image_auth_compact.sv': '9777e7958f163f3f9ffd41dac778dc54d76b030f290370acf757837874e82d2a',
 'project/fpga/token_only_model0_ddr_board1/shared_projection_scale0/rtl/board1_shared_projection_scale_engine.sv': '443d16724abe6999af5af35c3685c8d5ef45b707cc1af6dd4514a5beefac209f',
 'project/fpga/token_only_model0_ddr_board1/unified_dsp0/rtl/board1_unified_projection_head_mul_exact.sv': 'ccf15c1ad0f5bef293a44e89ae56fb9fd6bf8382205d7b12bac472ad2fa295d2',
 'project/fpga/token_only_model0_ddr_board1/unified_dynamic_dsp1/rtl/board1_unified_projection_head_dynamic_mul_exact.sv': '21c3ebc878f36c7260bf203f78174584d0c3e0ce18546966707ead45a0631b83',
 'project/handoff.sv': 'd264a0cc8275aa426c6e5b268af94ef34cb17821b801b9a366e9c7faae3960c1',
 'project/kv_integrity_guard.sv': 'dbda7c6c19af0cf566979b6ad2ca6184bff788d2163755314cf095c42ed36d43',
 'project/kv_page_hash.sv': '0049e9501f377bde37274b3a63f9a1361a817f4dc0ff1953c3e1868ebecb4578',
 'project/mapper_portable.sv': '1e3000948b24f5d52dfd0f61697d713a9c8c4c9f2ecc90ccb91812a04fc3e0dc',
 'project/normalizer_pipeline.sv': '01918be4558244173ddac603e3e89c6114c44ef128e68e87c9ba0445e138fd40',
 'project/service.sv': 'b33c55b61eab7b0cea8c67ea01a17dd6c082dcf6d313fa147adec32692e9466c',
 'project/sha.sv': 'a80629c713103fd5e63e8d42b8864785555173620102fe9f31d327cf6cca238b',
 'project/shared_token_probe.sv': 'e0cac396105faef3fd5e56799965c56c32aa0b94f8cd48443a2f8714d3c9c6c5',
 'project/tang_private_aes256.sv': '6effc46b35e24639d959dbcd192d7108766f300b4b42ceaf14f6a1a27cd6c184',
 'project/tang_private_aes256_fixed2.sv': 'e45e4cd7c99f91ae0214ad3b5e5b28de37c5abbb047a20c59a058751b98e5f84',
 'project/tang_private_aes256_pool2.sv': 'f9c4c7411da54040ba6aba496cf4c1d6ab41bc79d529ef191af8e8840e0bfd04',
 'project/tang_private_kv_siv_bridge.sv': '53f6b4f1386d6c1a0a9cb47630d3decb03174546f6cb61f19c5da0e5d8102306',
 'project/tang_private_kv_siv_role.sv': '5c9e3eb444babb323f7d76bdcf36c199f7e5fdbbfe7aac6e37d4d4f124857485',
 'project/thin_transport.sv': 'a97c68a24155428446e0f3ca48d3dbcd3ac8110bdcbf789259bfacb26f351f76'}
EXPECTED = {
    'around-zero':[200,15,103,157,200,15],
    'around-stalled':[200,15,103,157,200,15],
    'fox-zero':[385,317,385],
    'help-zero':[106,165,106],
    'corrupt-boot':[], 'corrupt-runtime':[],
}


def need(ok, why):
    if not ok: raise ValueError(why)


def sha(raw): return hashlib.sha256(raw).hexdigest()


def validate(data, package=ROOT):
    package = Path(package)
    need(data['schema'] == 'tang-encrypted-current-validation-v1'
        and data['image_sha256'] == IMAGE and data['hardware_inputs_sha256'] == INPUTS,
        'Different encrypted validation identity')
    for key in ('long_context_whole_model_simulation','whole_machine_proved',
                'encrypted_variant_formally_verified','physical_security_qualified',
                'public_checker_replays_simulation'):
        need(data[key] is False, 'Unsupported qualification or replay claim')
    need(data['actual_ciphertext_boot'] is True and data['integer_and_kv_ciphertext_oracles'] is True,
         'Changed simulation scope')
    for key, value in {
        'native_launch_receipt_sha256':'a09c29742d1609c6963471bea3cf4dd8df90e5383bcf7422f0e69348e422feb9',
        'simulation_receipt_sha256':'5f249fff4d261ebc7c7c85493bfdde9f4305ccf6ee5e0a23a740732497280d4d',
        'simulation_audit_source_sha256':'93b5a2338d136bd99cb3502b0714dff40776b78e4e03a5e1ec57c3f0db41edb4',
    }.items():
        need(data[key] == value, 'Different recorded test provenance')
    inventory = json.loads((package/'host-app/hardware-inputs-encrypted-memory.json').read_bytes())
    canonical = (json.dumps(inventory,sort_keys=True,separators=(',',':'))+'\n').encode()
    need(sha(canonical) == CURRENT_INVENTORY_SHA and len(data['production_sources']) == 71,
         'Incomplete current inventory or historical source binding')
    need(data['production_sources']==ORIGINAL_PRODUCTION_SOURCES,
         'Changed historical production source map')
    need(set(data['cases']) == set(EXPECTED), 'Incomplete simulation cases')
    count = 0
    for name, tokens in EXPECTED.items():
        row = data['cases'][name]
        need(row['passed'] is True and row['generated_tokens'] == tokens,
             'Wrong simulated output')
        need(row['corruption_refused'] is name.startswith('corrupt-'), 'Wrong corruption scope')
        need(len(row['step_cycles']) == len(tokens)
            and all(type(n) is int and n > 0 for n in row['step_cycles'])
            and re.fullmatch('[0-9a-f]{64}',row['raw_log_sha256']), 'Bad recorded observation')
        count += len(tokens)
    need(count == data['total_step_or_replay_tokens'] == 18, 'Wrong simulation output count')
    components = data['component_evidence']
    aes = components['aes']
    need(aes['receipt_sha256'] == '6026806dcbcb336b3452fe16881004e00a1cd61741cf7e39d1d286fd4720d1d1'
        and aes['raw_sources_oracles_vectors_binaries_logs_rechecked'] is True
        and aes['coverage'] == dict(key_patterns=560,expected_jobs=2240,completed_jobs=2240,
            key_slot_block_pairs=120960,abort_recoveries=288,reset_recoveries=288),
        'Wrong AES component coverage')
    need(components['unchanged_exhaustive_sbox'] == dict(
        receipt_sha256='9d0f7653377c5ec4142ab79aec99ddd4fef2fbcce325d0a8e9a402e59c817307',
        binary_inputs=256,negative_controls=3,raw_sources_fixtures_binaries_logs_rechecked=True),
        'Wrong S-box coverage')
    need(data['key_selector_proof'] == dict(
        receipt_sha256='1554bd26498bc4b03c8ca2b44db7095c3cd9b3362a421f21230a14f169dc672a',
        arbitrary_expanded_keys=True,input_assumptions=0,harmful_controls_rejected=4,
        sequential_equivalence_proved=False), 'Wrong selector-only proof scope')
    need((data['weight_cache_banks'],data['weight_aes_engines'],data['weight_sha_engines']) == (4,2,2),
         'Wrong selected cache/crypto geometry')
    inherited = {
        'project/tang_private_aes256.sv':
            '6effc46b35e24639d959dbcd192d7108766f300b4b42ceaf14f6a1a27cd6c184',
        'project/tang_private_aes256_fixed2.sv':
            'e45e4cd7c99f91ae0214ad3b5e5b28de37c5abbb047a20c59a058751b98e5f84',
    }
    need(data['inherited_aes_primitive_sources'] == inherited
         and all(data['production_sources'].get(name) == pin and inventory.get(name)==pin
             and sha((package/'variants/encrypted-memory/hardware'/name).read_bytes())==pin
             for name,pin in inherited.items()),
         'Inherited AES component evidence does not match selected primitives')
    guard = data['kv_guard_component_evidence']
    need(guard['raw_sources_fixtures_commands_logs_rechecked'] is True
         and all(guard[name] is False for name in ('executable_hashes_recorded_at_execution',
             'whole_machine_proved','public_checker_replays_simulation')),
         'Unsupported K/V guard evidence scope')
    canonical_guard = (json.dumps(guard,sort_keys=True,separators=(',',':'))+'\n').encode()
    need(sha(canonical_guard) == 'ec5869180b6b988f0f9be9347cfd790ae79704738ae4b2763300a96e24518e47',
         'Different recorded K/V guard coverage or observations')
    return dict(passed=True,historical_production_source_entries=71,historical_simulation_cases=6,historical_recorded_outputs=count,
        current_inherited_aes_sources_byte_identical=2,current_model_qualification_inherited=False,
        inherited_byte_identical_aes_primitives=2,recorded_kv_guard_cases=9,
        raw_simulation_replayed=False,whole_machine_proved=False,
        scope='Historical component-summary consistency and exact current identity of two inherited AES source files only. Old six-case model outputs are not credited to the current CFC image; private component tests are not replayed.')


if __name__ == '__main__':
    raw=(ROOT/'evidence/encrypted-memory/current-validation.json').read_bytes()
    need(sha(raw)==RECORD_SHA,'Historical encrypted component summary changed')
    print(json.dumps(validate(json.loads(raw)),indent=2))
