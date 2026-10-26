#!/usr/bin/env python3
"""Verify saved H100 evidence and reproduce conditional comparison arithmetic.

Standard library only. No GPU/model execution, network access or file writes.
"""
import argparse
import hashlib
import importlib.util
import json
import math
from pathlib import Path, PurePosixPath
import statistics
import tarfile

EVIDENCE = 'evidence/qwen-h100-2026-10-25'
MODELS = {'qwen_fixed': 'Qwen/Qwen3-1.7B',
          'qwen_primary': 'Qwen/Qwen3-1.7B',
          'small_fixed': 'SimpleStories/SimpleStories-V2-5M'}
H = 989_000_000_000_000


def require(condition, message):
    if not condition:
        raise ValueError(message)


def positive(value):
    require(isinstance(value, (int, float)) and math.isfinite(value) and value > 0,
            'Expected a finite positive measurement')
    return value


def checked_case(source, inventory, entry, role):
    raw = source.extractfile(entry['member']).read()
    require(hashlib.sha256(raw).hexdigest() == entry['sha256'], 'Selected case identity changed')
    case = json.loads(raw)
    require(case['status'] == 'pass', 'Selected reference must pass its stated policy')
    require(case['model']['repository'] == MODELS[role], 'Wrong model for reference role')
    require(case['model']['dtype'] == 'float16', 'This recorded comparison uses FP16')
    gpu = case['environment']['gpu']
    require('H100' in gpu['name'] and gpu['compute_capability'] == [9, 0]
            and 79e9 < gpu['total_memory_bytes'] < 87e9
            and gpu['multiprocessor_count'] == 132 and gpu['mig.mode.current'] == 'Disabled'
            and gpu['cuda_visible_devices'] == '0'
            and not gpu['other_compute_processes_on_selected_gpu'], 'Wrong single-H100 configuration')
    w, t = case['workload'], case['timing']
    require(w['independent_kv_storage'] and w['argmax_included']
            and w['host_launches_and_sync_included'], 'Changed counted workload/timing boundary')
    if role == 'qwen_primary':
        require(w['kind'] == 'continuation' and w['prompt'] == 'single_token'
                and w['tokens_per_call_in_timing'] == 127, 'Wrong one-token continuation workload')
        require(case['checks']['optimized']['greedy_mismatch_count'] == 0,
                'Primary continuation must retain exact trajectory agreement')
    else:
        require(w['kind'] == 'fixed' and w['context'] == 128
                and w['tokens_per_call_in_timing'] == 1, 'Fixed and growing contexts cannot be substituted')
    count = w['batch'] * w['tokens_per_call_in_timing'] * w['iterations']
    require(count == t['counted_tokens_per_trial'], 'Incorrect token accounting')
    samples = t['samples']
    require(len(samples) == 5, 'Expected five retained trials')
    rate = count / statistics.median(positive(s['wall_seconds']) for s in samples)
    require(math.isclose(rate, positive(t['aggregate_tokens_per_second']), rel_tol=1e-12),
            'Reported rate does not reproduce from host-wall samples')
    for name, digest in case['execution']['source_sha256'].items():
        require(PurePosixPath(name).name == name, 'Unexpected source snapshot path')
        member = str(PurePosixPath(entry['member']).parent / 'sources' / name)
        require(inventory['files'].get(member, {}).get('sha256') == digest,
                'Selected case source binding changed: ' + name)
    return case, rate


def analyze(package_root, evidence_root=None):
    package = Path(package_root)
    evidence = Path(evidence_root) if evidence_root else package / EVIDENCE
    selection_raw = (evidence / 'SELECTED-REFERENCES.json').read_bytes()
    selection = json.loads(selection_raw)
    require(set(selection['cases']) == set(MODELS), 'Missing or extra reference role')
    receipt = json.loads((evidence / 'REMOTE-ARCHIVE.json').read_text())
    archive = evidence / 'raw-evidence.tar.gz'
    require(hashlib.sha256(archive.read_bytes()).hexdigest() == receipt['sha256'],
            'Raw archive differs from independently recorded remote identity')
    with tarfile.open(archive) as source:
        members = source.getmembers()
        require(len({m.name for m in members}) == len(members), 'Duplicate archive member')
        for m in members:
            path = PurePosixPath(m.name)
            require(m.isfile() and not path.is_absolute() and '..' not in path.parts
                    and str(path) == m.name, 'Unsafe archive path/type')
        inventory = json.load(source.extractfile(receipt['inventory']))
        require({m.name for m in members} == set(inventory['files']) | {receipt['inventory']},
                'Archive membership differs from remote inventory')
        for name, expected in inventory['files'].items():
            raw = source.extractfile(name).read()
            require(len(raw) == expected['bytes'] and hashlib.sha256(raw).hexdigest() == expected['sha256'],
                    'Changed archived evidence: ' + name)
        cases, rates = {}, {}
        for role, entry in selection['cases'].items():
            cases[role], rates[role] = checked_case(source, inventory, entry, role)
        all_cases = []
        for m in members:
            if m.name.startswith('results/') and m.name.endswith('/result.json'):
                case = json.load(source.extractfile(m))
                all_cases.append({'member': m.name, 'status': case['status'], 'error': case.get('error'),
                                  'model': case.get('model', {}).get('repository'),
                                  'workload': case.get('workload'),
                                  'rate': case.get('timing', {}).get('aggregate_tokens_per_second')})
    spec = importlib.util.spec_from_file_location('qwen_capacity',
                Path(__file__).with_name('estimate_qwen_training_capacity.py'))
    capacity = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(capacity)
    baseline = capacity.estimate(package)
    q_coefficients = baseline['phi_proxy_coefficient_per_reference_tps']
    q = {name: value * rates['qwen_fixed'] for name, value in q_coefficients.items()
         if name != 'named_schedule_story_continuation'}
    small_metrics_path = package / 'evidence/baseline-current/metrics.json'
    small_metrics_raw = small_metrics_path.read_bytes()
    small_metrics = json.loads(small_metrics_raw)['metrics']['around128']
    require((small_metrics['prompt_tokens'], small_metrics['generated_tokens'], small_metrics['occupied_tape'])
            == (1, 128, 129), 'Changed historical SmallStories hardware workload')
    fs = 1 / positive(small_metrics['last_step_seconds'])
    rs = rates['small_fixed']
    small = {'named_schedule_context128': 801272 * rs / H,
             'named167_every_cycle': 250e6 * rs / (H * fs),
             'all692_every_cycle': 3.8e9 * rs / (H * fs),
             'matrix_schedule_context128': 11488768 * rs / H}
    comparison = {}
    for label, key in [('named_schedule', 'named_schedule_context128'),
                       ('all_named_runtime_units_every_cycle', 'named167_every_cycle'),
                       ('all_functional_multipliers_every_cycle', 'all692_every_cycle'),
                       ('replace_accepted_weights_same_schedule', 'matrix_schedule_context128')]:
        comparison[label] = {'qwen_phi_proxy': q[key], 'simplestories_phi_proxy': small[key],
                             'qwen_divided_by_simplestories': q[key] / small[key]}
    references = {}
    for role, case in cases.items():
        check = case['checks']['optimized']
        references[role] = {'rate': rates[role], 'batch': case['workload']['batch'],
                            'mode': case['workload']['mode'], 'dtype': case['model']['dtype'],
                            'main_greedy_disagreements': check['greedy_mismatch_count'],
                            'main_greedy_comparisons': check['token_comparisons'],
                            'member': selection['cases'][role]['member'],
                            'sha256': selection['cases'][role]['sha256']}
    primary_named_mean = sum(capacity.work_counts(n)['named_dynamic_mac_equivalent_operations']
                             for n in range(2, 129)) / 127
    return {'schema': 'qwen-h100-conditional-comparison-v1',
            'selection_sha256': hashlib.sha256(selection_raw).hexdigest(),
            'archive_sha256': receipt['sha256'], 'verified_payload_files': len(inventory['files']),
            'case_counts': {'total': len(all_cases), 'pass': sum(c['status'] == 'pass' for c in all_cases),
                            'failed': sum(c['status'] == 'failed' for c in all_cases)},
            'references': references, 'fixed_context_conditional_comparison': comparison,
            'qwen_fixed_context_phi_proxy': q,
            'qwen_one_token_named_schedule': {'mean_ops_per_cached_token': primary_named_mean,
                                             'conditional_phi_proxy': primary_named_mean * rates['qwen_primary'] / H,
                                             'matching_128_output_fpga_measurement_pending': True},
            'small_fpga_context128_single_step_tps': fs,
            'small_fpga_metrics_sha256': hashlib.sha256(small_metrics_raw).hexdigest(),
            'qwen_fpga_measured_rates': baseline['fpga_measured_rates'],
            'all_cases': all_cases,
            'limitations': ['Achieved parent-model FP16 reference scores, not proven maxima or licensed ratings.',
                            'The conditional arithmetic access is hypothetical; no useful training attack is demonstrated.',
                            'Both historical FPGA fixed-context rates are single host-timed steps, not measured peaks.',
                            'Compiled scores use the explicit logit-tolerance policy and retain greedy disagreements.',
                            'The upstream floating-point parents differ from the FPGA numerical functions.']}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--package-root', type=Path, default=Path(__file__).resolve().parents[1])
    p.add_argument('--evidence-root', type=Path)
    p.add_argument('--check', action='store_true')
    args = p.parse_args()
    result = analyze(args.package_root, args.evidence_root)
    if args.check:
        evidence = args.evidence_root or args.package_root / EVIDENCE
        require(result == json.loads((evidence / 'computed-results.json').read_text()),
                'Saved conditional calculations differ from the evidence')
        print(json.dumps({'passed': True, 'verified_payload_files': result['verified_payload_files'],
                          'case_counts': result['case_counts'], 'references': result['references']}))
    else:
        print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
