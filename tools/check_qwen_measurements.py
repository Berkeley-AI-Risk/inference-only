"""Recompute the packaged Qwen hardware measurements, without device access.

Checks recorded host replies against packaged expected token IDs. This is not
a fresh model-oracle run, FPGA test, timing audit or physical attestation.
"""
import argparse
import hashlib
import json
from pathlib import Path

MODEL_SHA = '90d82ed9b90c58607f924190be0c15f18b70d849c536a2ccbddd259858979cd1'
PACKAGE_SHA = '10cea9c0f7275fe37791d5d2bf40c045854ca992ca28d9b06c80fd33e1e83c10'
CHECKPOINT_SHA = 'e8a1143e44bdc65fd1da76d7faeac236e59c49ccd4d5ce004a3b962ce6b5c98d'
HOST_SHA = '10286666d2263700fad870a29fa3aabb9ade49f81bfa42e249a288752357210c'
ORACLES = {
    'first-smoke': '30ce20b70da9e9b42beaeb8ccb615b3284581388cdbc16e36f057b06a1852e4d',
    'full-smoke': '30ce20b70da9e9b42beaeb8ccb615b3284581388cdbc16e36f057b06a1852e4d',
    'sustained-128-run1': 'fcb5413ecff8d1407cd5e8516edf2379efbe8d1350e762328f0b69a48f4c9011',
    'sustained-128-run2': 'fcb5413ecff8d1407cd5e8516edf2379efbe8d1350e762328f0b69a48f4c9011',
    'prefill-64-256-512': 'e3beb35c57820fac85f4c768ad4b0d49065504f379d1e113f2044c7f7c22721b',
}
NAMES = ['original_smoke', 'raw_story', 'raw_geography', 'chat_greeting', 'original_smoke_replay']
PREFILL = ['original_smoke', 'prefill_64', 'prefill_256', 'prefill_512', 'original_smoke_replay']


def need(condition, message):
    if not condition:
        raise ValueError(message)


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def sha_string(value):
    return isinstance(value, str) and len(value) == 64 and all(c in '0123456789abcdef' for c in value)


def token_list(values):
    return isinstance(values, list) and values and all(type(x) is int and 0 <= x < 151936 for x in values)


def measure(case):
    need(set(case) == {'name', 'prompt_tokens', 'expected_tokens', 'stdout',
                      'stdout_sha256', 'raw_capture_sha256'}, 'Unexpected case fields')
    need(token_list(case['prompt_tokens']) and token_list(case['expected_tokens']), 'Invalid token IDs')
    need(sha_string(case['raw_capture_sha256']), 'Invalid raw-capture identity')
    need(isinstance(case['stdout'], str) and digest(case['stdout'].encode()) == case['stdout_sha256'],
         'Changed recorded transcript')
    rows = [json.loads(line) for line in case['stdout'].splitlines() if line.strip()]
    need(len(rows) == len(case['expected_tokens']) and len(rows) >= 2, 'Missing or extra replies')
    for i, (row, expected) in enumerate(zip(rows, case['expected_tokens'])):
        need(set(row) == {'index', 'token', 'step_ns', 'generation_elapsed_ns', 'prompt_elapsed_ns'},
             'Unexpected reply fields')
        need(all(type(value) is int and value >= 0 for value in row.values()), 'Invalid reply values')
        need(row['index'] == i and row['token'] == expected, 'Disordered or nonmatching token')
        need(row['prompt_elapsed_ns'] >= row['generation_elapsed_ns'] >= row['step_ns'] > 0,
             'Inconsistent timing')
        if i:
            need(row['generation_elapsed_ns'] > rows[i - 1]['generation_elapsed_ns']
                 and row['prompt_elapsed_ns'] > rows[i - 1]['prompt_elapsed_ns'], 'Nonmonotonic timing')
    elapsed = (rows[-1]['generation_elapsed_ns'] - rows[0]['generation_elapsed_ns']) / 1e9
    return dict(name=case['name'], prompt_tokens=len(case['prompt_tokens']), generated_tokens=len(rows),
                cached_tokens=len(rows) - 1, prompt_to_first_token_seconds=rows[0]['prompt_elapsed_ns'] / 1e9,
                cached_decode_elapsed_seconds=elapsed, cached_tokens_per_second=(len(rows) - 1) / elapsed)


def validate(data):
    need(set(data) == {'schema', 'recorded_date', 'implementation', 'campaigns', 'scope'},
         'Unexpected evidence fields')
    need(data['schema'] == 'qwen-public-hardware-measurements-v1' and data['recorded_date'] == '2026-10-19',
         'Unexpected measurement version')
    implementation = data['implementation']
    need(set(implementation) == {'model_image_sha256', 'package_sha256', 'checkpoint_sha256', 'host_sha256',
                                'core_clock_mhz', 'weight_authentication', 'kv_integrity', 'weight_encryption',
                                'full_context_qualified', 'production_security_certified'}, 'Unexpected implementation fields')
    need(implementation['model_image_sha256'] == MODEL_SHA and implementation['package_sha256'] == PACKAGE_SHA
         and implementation['checkpoint_sha256'] == CHECKPOINT_SHA and implementation['host_sha256'] == HOST_SHA,
         'Changed implementation identity')
    need(implementation['core_clock_mhz'] == 100 and implementation['weight_authentication'] is True,
         'Wrong clock or authentication status')
    for key in ('kv_integrity', 'weight_encryption', 'full_context_qualified', 'production_security_certified'):
        need(implementation[key] is False, 'Unsupported qualification: ' + key)
    need([run['name'] for run in data['campaigns']] == list(ORACLES), 'Missing or different campaigns')
    output = {}
    total = 0
    for run in data['campaigns']:
        need(set(run) == {'name', 'receipt_sha256', 'oracle_sha256', 'final_clear_status', 'cases'},
             'Unexpected campaign fields')
        name = run['name']
        need(sha_string(run['receipt_sha256']) and run['oracle_sha256'] == ORACLES[name], 'Changed reference binding')
        need(type(run['final_clear_status']) is int and run['final_clear_status'] == 0, 'Final CLEAR did not pass')
        expected_names = NAMES[:1] if name == 'first-smoke' else PREFILL if name.startswith('prefill') else NAMES
        need([case['name'] for case in run['cases']] == expected_names, 'Missing, extra or reordered cases')
        results = [measure(case) for case in run['cases']]
        expected_lengths = ([3] if name == 'first-smoke' else [3, 16, 16, 16, 3]
                            if name.startswith('prefill') else [3, 128, 128, 128, 3]
                            if name.startswith('sustained') else [3] * 5)
        prompt_lengths = ([1] if name == 'first-smoke' else [1, 64, 256, 512, 1]
                          if name.startswith('prefill') else [1, 4, 5, 15, 1])
        need([row['generated_tokens'] for row in results] == expected_lengths
             and [row['prompt_tokens'] for row in results] == prompt_lengths, 'Changed workload lengths')
        if name != 'first-smoke':
            need(all(run['cases'][0][key] == run['cases'][-1][key]
                     for key in ('prompt_tokens', 'expected_tokens')), 'CLEAR/replay workload changed')
        output[name] = results
        total += sum(row['generated_tokens'] for row in results)
    left, right = data['campaigns'][2]['cases'], data['campaigns'][3]['cases']
    need(all(all(a[key] == b[key] for key in ('name', 'prompt_tokens', 'expected_tokens'))
             for a, b in zip(left, right)), 'Repeated suites have different workloads')
    need(total == 852, 'Changed comparison count')
    sustained = [row['cached_tokens_per_second'] for name, rows in output.items()
                 if name.startswith('sustained') for row in rows if row['generated_tokens'] == 128]
    return dict(passed=True, compared_tokens=total, campaigns=len(output), cases=sum(map(len, output.values())),
                sustained_cached_tokens_per_second=[min(sustained), max(sustained)], measurements=output,
                hardware_access=False, network_access=False,
                scope='Recorded transcript/reference-ID agreement and timing arithmetic, not fresh inference or physical attestation.')


def check(package):
    package = Path(package)
    data = json.loads((package / 'demos/qwen3-1.7b/measurements.json').read_text())
    result = validate(data)
    low, high = result['sustained_cached_tokens_per_second']
    headline = f'{low:.3f}–{high:.3f}'
    need(headline in (package / 'README.md').read_text(), 'Overview rate differs from evidence')
    guide = (package / 'demos/qwen3-1.7b/README.md').read_text()
    need(headline in guide and '852' in guide, 'Qwen guide summary differs from evidence')
    for row in result['measurements']['prefill-64-256-512'][1:4]:
        text = f"| {row['prompt_tokens']} | 16 | {row['prompt_to_first_token_seconds']:.3f} s | {row['cached_tokens_per_second']:.3f} |"
        need(text in guide, 'Qwen prompt measurement differs from evidence')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', type=Path, default=Path(__file__).resolve().parents[1])
    print(json.dumps(check(parser.parse_args().package), indent=2))
