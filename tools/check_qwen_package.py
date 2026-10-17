"""Offline Qwen source/report/reference checks; no hardware or cloud access."""
import hashlib
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def need(condition, message):
    if not condition:
        raise ValueError(message)


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def check_installation(demo, deployment, installation, controller, measurements):
    """Check recorded evidence, without contacting AWS or claiming attestation."""
    need(deployment['public_load_permission_verified'] is True
         and deployment['load_permissions'] == [{'Group': 'all'}]
         and deployment['image_state'] == 'available', 'Public image observation is missing')
    need(deployment['fpga_image_global_id'] == 'agfi-026c1333e063cf04f'
         and deployment['fpga_image_id'] == 'afi-0dcab1e1ac1a1dade'
         and deployment['region'] == 'us-east-1'
         and deployment['shell_version'] == '0x10212415', 'Unexpected deployment image')
    measured = measurements['implementation']
    need(deployment['routed_checkpoint_sha256'] == measured['checkpoint_sha256']
         and deployment['model_sha256'] == measured['model_image_sha256']
         and deployment['core_clock_mhz'] == measured['core_clock_mhz'],
         'Deployment does not match measured implementation')
    need(installation['passed'] is True and installation['fresh_model_upload'] is True
         and installation['slot_reloaded'] is True
         and installation['controller_suite_passed'] is True, 'Installation did not pass')
    for key in ('fpga_image_global_id', 'shell_version', 'model_sha256', 'model_bytes'):
        need(installation[key] == deployment[key], 'Installation/deployment mismatch: '+key)
    need(installation['model_bytes'] == 2354380800
         and installation['empty_status']['received_bytes'] == 0
         and not installation['empty_status']['flags'] & 0x10
         and installation['model_upload']['model_ready'] is True
         and installation['model_upload']['image_bytes'] == installation['model_bytes']
         and installation['final_status']['received_bytes'] == installation['model_bytes']
         and installation['final_status']['flags'] & 0x10
         and not installation['final_status']['flags'] & 0xe0
         and installation['final_clear']['status'] == 0, 'Missing fresh upload/readiness evidence')
    need([(r['index'], r['token']) for r in installation['self_test']]
         == [(0, 25), (1, 358), (2, 1184)], 'Installation self-test disagrees')
    for name, identity in installation['source_sha256'].items():
        need(sha(demo/name) == identity, 'Installation source changed: '+name)
    for name, identity in installation['host_source_sha256'].items():
        need(sha(demo/'host'/name) == identity, 'Recipient host source changed')
    need(installation['controller_record'] == 'installation-controller.json'
         and sha(demo/'evidence/installation-controller.json') == installation['controller_record_sha256'],
         'Installation controller record changed')
    need(controller['passed'] is True and controller['stop_at_end'] is False
         and controller['expected_ids_source_sha256'] == sha(demo/'measurements.json')
         and controller['final_clear']['status'] == 0, 'Controller check did not pass')
    expected = next(c for c in measurements['campaigns'] if c['name'] == 'sustained-128-run2')['cases']
    need(len(controller['cases']) == len(expected), 'Incomplete controller cases')
    count = 0
    for actual, target in zip(controller['cases'], expected):
        need(actual['name'] == target['name'] and actual['state'] == 'complete'
             and actual['matched'] is True and not actual['error']
             and actual['prompt_tokens'] == target['prompt_tokens']
             and actual['expected_tokens'] == target['expected_tokens']
             and [r['index'] for r in actual['steps']] == list(range(len(target['expected_tokens'])))
             and [r['token'] for r in actual['steps']] == target['expected_tokens'],
             'Controller output differs from the packaged reference')
        count += len(actual['steps'])
    need(count == controller['compared_tokens'] == installation['controller_compared_tokens'] == 390,
         'Incorrect controller comparison count')
    return count


def check(package=ROOT):
    demo = package/'demos/qwen3-1.7b'
    builder = module('qwen_package_build', demo/'tools/prepare_hardware.py')
    inputs, implementation = builder.verify(demo)
    report_root = demo/'evidence/implementation'
    reports = json.loads((report_root/'REPORTS.json').read_text())
    for name, row in reports['reports'].items():
        path = builder.checked_path(report_root, name)
        need(path.stat().st_size == row['public']['bytes'] and sha(path) == row['public']['sha256'],
             'Changed implementation report: '+name)
    timing = module('qwen_package_timing', demo/'tools/check_routed_reports.py').check(report_root)
    reference = json.loads((demo/'evidence/reference/CHECKS.json').read_text())
    need(reference['passed'] is True and reference['tensors_compared'] == 507
         and reference['all_tensor_values_equal'] is True, 'Missing complete loader comparison')
    for name, expected in reference['source_sha256'].items():
        need(sha(builder.checked_path(demo, name)) == expected, 'Changed verified reference source: '+name)
    measurements = json.loads((demo/'measurements.json').read_text())
    cases = {}
    for campaign in measurements['campaigns']:
        for row in campaign['cases']:
            key = tuple(row['prompt_tokens'])
            old = cases.get(key, [])
            n = min(len(old), len(row['expected_tokens']))
            need(old[:n] == row['expected_tokens'][:n], 'Inconsistent recorded reference prefixes')
            if len(row['expected_tokens']) > len(old):
                cases[key] = row['expected_tokens']
    token_counts = {}
    for name, identity in reference['token_runs'].items():
        path = builder.checked_path(demo/'evidence/reference', name)
        need(sha(path) == identity['sha256'] and path.stat().st_size == identity['bytes'],
             'Changed reference result')
        record = json.loads(path.read_text())
        need(record['passed'] is True and record['hardware_access'] is False
             and record['software_reference_only'] is True
             and record['measurements_sha256'] == sha(demo/'measurements.json'),
             'Reference result scope or input mismatch')
        seen, count = set(), 0
        for row in record['cases']:
            key = tuple(row['prompt_tokens'])
            need(key in cases and row['tokens'] == cases[key][:len(row['tokens'])],
                 'Numerical reference result disagrees')
            seen.add(key)
            count += len(row['tokens'])
        need(count == record['compared_tokens'], 'Wrong reference token count')
        if record['campaign'] == 'all':
            need(seen == set(cases) and count == sum(map(len, cases.values())),
                 'Incomplete distinct-prompt regeneration')
        token_counts[record['backend']] = count
    need(token_counts == {'cpu': 15, 'mps': 435}, 'Missing CPU or full reference result')
    installation_count = check_installation(demo,
        json.loads((demo/'deployment.json').read_text()),
        json.loads((demo/'evidence/installation.json').read_text()),
        json.loads((demo/'evidence/installation-controller.json').read_text()), measurements)
    return dict(passed=True, frozen_inputs=len(inputs), implementation_reports=len(reports['reports']),
                reference_tensors=507, regenerated_reference_tokens=token_counts,
                recorded_installation_comparisons=installation_count,
                setup_slack_ns=timing['setup_slack_ns'], hold_slack_ns=timing['hold_slack_ns'],
                hardware_access=False, network_access=False,
                scope='Checks packaged evidence; does not rerun inference, implementation tools or formal proofs.')


if __name__ == '__main__':
    print(json.dumps(check(), indent=2, sort_keys=True))
