"""Validate the recorded encrypted-model test summary, not rerun its tests."""
import hashlib
import json
from pathlib import Path, PurePosixPath
import re

ROOT = Path(__file__).resolve().parents[1]
IMAGE = '865e74e692d5978815fe921f11e4fa1b8e2c080401a8be05508dd9775823aecc'
INPUTS = '840c12ce7d1a5886966aca73e7c44eb3e42b9ee07ab33adcb2de3d273125e262'
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
    need(sha(canonical) == INPUTS and len(data['production_sources']) == 71,
         'Incomplete native source binding')
    for name, digest in data['production_sources'].items():
        path = PurePosixPath(name)
        need(not path.is_absolute() and '..' not in path.parts and name.startswith('project/')
             and not name.startswith('project/official/') and inventory.get(name) == digest
             and sha((package/'variants/encrypted-memory/hardware'/name).read_bytes()) == digest,
             'Changed production source')
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
         and all(data['production_sources'].get(name) == pin for name,pin in inherited.items()),
         'Inherited AES component evidence does not match selected primitives')
    guard = data['kv_guard_component_evidence']
    need(guard['raw_sources_fixtures_commands_logs_rechecked'] is True
         and all(guard[name] is False for name in ('executable_hashes_recorded_at_execution',
             'whole_machine_proved','public_checker_replays_simulation')),
         'Unsupported K/V guard evidence scope')
    canonical_guard = (json.dumps(guard,sort_keys=True,separators=(',',':'))+'\n').encode()
    need(sha(canonical_guard) == 'ec5869180b6b988f0f9be9347cfd790ae79704738ae4b2763300a96e24518e47',
         'Different recorded K/V guard coverage or observations')
    return dict(passed=True,production_sources=71,simulation_cases=6,recorded_outputs=count,
        inherited_byte_identical_aes_primitives=2,recorded_kv_guard_cases=9,
        raw_simulation_replayed=False,whole_machine_proved=False,
        scope='Recorded identifiers, source hashes and summary consistency; not an independent replay of the private simulations.')


if __name__ == '__main__':
    print(json.dumps(validate(json.loads(
        (ROOT/'evidence/encrypted-memory/current-validation.json').read_bytes())),indent=2))
