#!/usr/bin/env python3
"""Check the original encrypted image's historical board record and arithmetic.

This checks published data against fixed integer references and source hashes.
It does not replay private UART transcripts or attest the physical FPGA.
"""
import argparse
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
ORDER = ('around128', 'fox128', 'help64', 'moon64', 'prefix128',
         'prefix512', 'prefix1024', 'prefix2047')
RESTORED = ('around128', 'prefix128', 'prefix512')
CASES_SHA = '00e4e7ef40f965b3c5a0fbf035ce2ee01b4bd85c187a3cfd2e91c0ad124e2a6f'
REFERENCE_SHA = 'ff258275225ba9ccb24589ca2fdf402df35e55dbbffb2c6c88ff36cb07e1d438'
ORACLE_SHA = '9b048a8e8b82faba3d21fd6b259aa1c23d91f04662fe2734fc109602777b4a74'
PLAIN_SHA = 'cad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0'
CIPHER_SHA = '88da38f3eb64bacc21aa472666b0cc8ea1e516cb04c80e0678f768425e6390eb'
ENCRYPTED_SHA = '32970712a318f605d5822bb7ac2234f080df15341103e0a78bad8863b5c9361e'
RESTORED_SHA = 'e22079c855cdf6cfb983c73850db15b1b5010f0511fa62f98f3d040ae0654ea2'
STAGED_MANIFEST = '6f7983133e5b8586c3a51e6f3d6718e906fbcbb7eda5d2d31eff69532ac6c439'
BUILD_SHA = '259e307db3b71bffd3eadd1d14122f5b9c11b573d82727d80c7afd9fa2f603ae'
INVENTORY_SHA = 'd2f75e9b1425bc82b712569b7ea754c3fdc9116fa2460ebffac6d6dc1ad26ba6'
HOST_FILES = ('qualify_board.py', 'runtime_profile.py', 'fpga_backend.py',
              'token_machine_uart.py', 'uart_channel.py')
SCOPE = ('Physical token-interface results checked against the fixed integer reference; '
         'sanitized summary, not a public replay of private raw transcripts, physical '
         'configuration attestation, browser test or timing/security qualification.')


def require(ok, message):
    if not ok: raise ValueError(message)


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(',', ':'))+'\n').encode()


def sha(raw): return hashlib.sha256(raw).hexdigest()


def historical(package, name):
    spec = importlib.util.spec_from_file_location('speed_history',Path(package)/'tools/speed_release_history.py')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module.previous_bytes(package,name,(Path(package)/name).read_bytes())


def fields(value, names):
    require(isinstance(value, dict) and set(value) == set(names.split()), 'Unexpected evidence fields')


def digest(value):
    require(isinstance(value, str) and re.fullmatch('[0-9a-f]{64}', value), 'Invalid evidence digest')


def positive(value):
    require(type(value) in (float, int) and math.isfinite(value) and value > 0, 'Invalid duration')


def equal_number(value, expected):
    positive(value)
    require(math.isclose(value, expected, rel_tol=1e-12, abs_tol=1e-12), 'Timing arithmetic differs')


def timing(first, remaining):
    positive(first)
    require(isinstance(remaining, list) and remaining, 'Missing cached decode durations')
    for value in remaining: positive(value)
    total = first + sum(remaining)
    return dict(first_step_seconds=first, cached_decode_seconds=remaining,
        cached_decode_tokens_per_second=len(remaining)/sum(remaining),
        all_long_steps_seconds=total, all_long_steps_tokens_per_second=(1+len(remaining))/total)


def check_case(row, name, expected):
    fields(row, 'case prompt_count output_count evaluated_positions maximum_occupied_tape '
        'first_step_seconds cached_decode_seconds cached_decode_tokens_per_second '
        'all_long_steps_seconds all_long_steps_tokens_per_second known_answer_steps '
        'known_answer_passes empty_step_rejections boundary_rejections final_clear_acknowledged '
        'receipt_sha256 uart_sha256 command_plan_sha256 max_wall_monotonic_discrepancy_seconds')
    p, n = len(expected['prompt_tokens']), len(expected['generated_tokens'])
    require(row['case'] == name and row['prompt_count'] == p and row['output_count'] == n
        and row['evaluated_positions'] == p+n-1 and row['maximum_occupied_tape'] == p+n,
        'Case dimensions differ')
    require(row['known_answer_passes'] == 3 and row['known_answer_steps'] == 12
        and row['empty_step_rejections'] == 3 and row['final_clear_acknowledged'] is True,
        'Missing CLEAR/known-answer checks')
    boundary = ['input-limit-append-rejected', 'final-slot-append-rejected',
                'final-slot-step-rejected'] if name == 'prefix2047' else []
    require(row['boundary_rejections'] == boundary, 'Capacity boundary differs')
    require(len(row['cached_decode_seconds']) == n-1, 'STEP duration census differs')
    expected_timing = timing(row['first_step_seconds'], row['cached_decode_seconds'])
    for key in ('cached_decode_tokens_per_second', 'all_long_steps_seconds', 'all_long_steps_tokens_per_second'):
        equal_number(row[key], expected_timing[key])
    for key in ('receipt_sha256', 'uart_sha256', 'command_plan_sha256'): digest(row[key])
    value = row['max_wall_monotonic_discrepancy_seconds']
    require(type(value) in (float, int) and math.isfinite(value) and 0 <= value < 1,
        'Clock-discontinuous timing must not be silently published')


def validate(data, package):
    package = Path(package)
    fields(data, 'schema passed scope reference_cases reference image_sha256 campaigns '
        'matched_cases source_receipts staged_qualification restoration public_test_keys_only '
        'timing_qualified physical_secrecy_qualified configuration_independently_attested '
        'physical_corruption_injection_tested browser_tested')
    require(data['schema'] == 'encrypted-memory-broad-board-v1' and data['passed'] is True
        and data['scope'] == SCOPE, 'Wrong evidence scope')
    require(data['public_test_keys_only'] is True, 'Published demonstration keys are not secret')
    for key in ('timing_qualified', 'physical_secrecy_qualified', 'configuration_independently_attested',
                'physical_corruption_injection_tested', 'browser_tested'):
        require(data[key] is False, 'Unsupported qualification claim')
    cases = data['reference_cases']
    require(set(cases) == set(ORDER) and sha(canonical(cases)) == CASES_SHA, 'Fixed references differ')
    published = json.loads((package/'tests/reference-cases.json').read_bytes())
    for name in ORDER[:5]:
        require(cases[name] == {key: published[name][key] for key in ('prompt_tokens', 'generated_tokens')},
            'Published integer reference differs')
    # The original public prefix512 fixture contains one output, whereas the
    # revalidated historical long-case reference contains four. Its complete
    # sequence (and both longer cases) is covered by the fixed case-set hash.
    require(cases['prefix512']['prompt_tokens'] == published['prefix512']['prompt_tokens']
        and cases['prefix512']['generated_tokens'][:len(published['prefix512']['generated_tokens'])]
            == published['prefix512']['generated_tokens'], 'Published prefix512 reference differs')
    ref = data['reference']
    require(ref == dict(model_image_sha256=PLAIN_SHA, ciphertext_sha256=CIPHER_SHA,
        integer_oracle_sha256=ORACLE_SHA, receipt_sha256=REFERENCE_SHA, case_set_sha256=CASES_SHA,
        fresh_cases=list(ORDER[:5]), historical_cases_revalidated=list(ORDER[5:]),
        long_references_rerun=False), 'Reference/source scope differs')
    require(sha((package/'reference/quantization/oracle.py').read_bytes()) == ORACLE_SHA,
        'Shipped reference oracle differs')
    require(data['image_sha256'] == dict(encrypted=ENCRYPTED_SHA, restored=RESTORED_SHA), 'Wrong tested images')
    fields(data['campaigns'], 'encrypted restored')
    mapped = {}
    for variant, names in [('encrypted', ORDER), ('restored', RESTORED)]:
        rows = data['campaigns'][variant]
        require(isinstance(rows, list) and [r['case'] for r in rows] == list(names), 'Campaign census differs')
        mapped[variant] = {r['case']: r for r in rows}
        for name, row in zip(names, rows): check_case(row, name, cases[name])
    require(isinstance(data['matched_cases'], list)
        and [r['case'] for r in data['matched_cases']] == list(RESTORED), 'Matched census differs')
    for row in data['matched_cases']:
        fields(row, 'case first_step_latency_ratio cached_decode_latency_ratio')
        a, b = mapped['encrypted'][row['case']], mapped['restored'][row['case']]
        equal_number(row['first_step_latency_ratio'], a['first_step_seconds']/b['first_step_seconds'])
        equal_number(row['cached_decode_latency_ratio'], sum(a['cached_decode_seconds'])/sum(b['cached_decode_seconds']))
    fields(data['source_receipts'], 'broad_prepared encrypted restored roundtrip staged_qualification')
    for value in data['source_receipts'].values(): digest(value)
    q = data['staged_qualification']
    fields(q, 'commands generated_tokens source_manifest_sha256 build_receipt_sha256 hardware_inputs_sha256 '
        'host_source_sha256 uart_sha256 receipt_sha256 private_profile_only default_profile_changed browser_started')
    require(q['commands'] == 7 and q['generated_tokens'] == [200, 15, 103, 157]
        and q['source_manifest_sha256'] == STAGED_MANIFEST and q['build_receipt_sha256'] == BUILD_SHA
        and q['hardware_inputs_sha256'] == INVENTORY_SHA and q['private_profile_only'] is True
        and q['default_profile_changed'] is False and q['browser_started'] is False,
        'Wrong staged qualification scope')
    require(set(q['host_source_sha256']) == set(HOST_FILES), 'Qualification source census differs')
    for name, value in q['host_source_sha256'].items():
        require(sha(historical(package,'host-app/'+name)) == value, 'Historical qualified host source changed')
    require(sha(historical(package,'prebuilt/encrypted-memory/BUILD.json')) == BUILD_SHA,
        'Qualified source build differs')
    for key in ('uart_sha256', 'receipt_sha256'): digest(q[key])
    require(q['receipt_sha256'] == data['source_receipts']['staged_qualification'], 'Qualification receipt differs')
    restoration = data['restoration']
    fields(restoration, 'full_flash_readback_passed restored_demo_verified no_irreversible_programming '
        'encrypted_short_kat_steps restored_short_kat_steps')
    require(restoration == dict(full_flash_readback_passed=True, restored_demo_verified=True,
        no_irreversible_programming=True, encrypted_short_kat_steps=6, restored_short_kat_steps=6),
        'Restoration scope differs')
    return dict(passed=True, encrypted_cases=8, restored_cases=3,
        encrypted_long_case_outputs=522, restored_long_case_outputs=260,
        maximum_evaluated_model_positions=2048, maximum_occupied_tape=2049,
        staged_qualification_outputs=4, hardware_access=False,
        private_raw_transcripts_replayed=False, timing_qualified=False, physical_secrecy_qualified=False)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', type=Path, default=ROOT)
    args = parser.parse_args()
    print(json.dumps(validate(json.loads((args.package/'evidence/encrypted-memory/broad-board.json').read_bytes()),
        args.package), indent=2))
