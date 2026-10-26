#!/usr/bin/env python3
"""Offline integrity, provenance and timing-accounting check for saved GPU runs.

Does not install packages, download a model, access a GPU or certify performance.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import statistics

SELECTED = 'evidence/h100/h100-compiled-fp16-repeat/ctx128-batch32768-float16-compile-graph.json'
STRICT = 'evidence/h100/h100-repeat-and-plateau/ctx128-batch32768-float16-graph.json'
REVISION = 'c4b3a4bb81297f5316697098e1d4b65c1249daf8'


def identity(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError('Expected regular evidence file')
    raw = path.read_bytes()
    return {'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()}


def close(actual, expected):
    if not math.isfinite(actual) or not math.isclose(actual, expected, rel_tol=1e-10, abs_tol=1e-12):
        raise ValueError('Inconsistent saved timing/accounting')


def validate_result(result):
    if result['status'] != 'pass':
        raise ValueError('Reference result did not pass its stated policy')
    model, workload = result['model'], result['workload']
    gpu = result['environment']['gpu']
    if (model['revision'] != REVISION or model['parameters'] != 5_354_496
            or model['dtype'] != 'float16' or model['fpga_bit_exact']
            or 'H100' not in gpu['name'] or gpu['multiprocessor_count'] != 132):
        raise ValueError('Wrong model, precision or GPU')
    if (workload['kind'] != 'fixed_context_cached_decode'
            or workload['context_including_current_input'] != 128
            or workload['cached_prefix_positions'] != 127
            or not workload['repeated_fixed_tapes_not_autoregressive_stream']
            or not workload['includes_argmax'] or workload['includes_prefill']):
        raise ValueError('Different workload cannot silently replace this reference')
    timing = result['timing']
    durations = [sample['wall_seconds'] for sample in timing['samples']]
    if not durations or any(not math.isfinite(value) or value <= 0 for value in durations):
        raise ValueError('Invalid timing duration')
    batch, iterations = workload['batch'], workload['iterations_per_trial']
    if batch <= 0 or iterations <= 0 or timing['tokens_counted_per_trial'] != batch * iterations:
        raise ValueError('Invalid token accounting')
    median = statistics.median(durations)
    close(timing['aggregate_tokens_per_second'], batch * iterations / median)
    close(timing['tokens_per_second_per_sequence'], iterations / median)
    close(timing['milliseconds_per_decode_step'], 1000 * median / iterations)
    close(timing['aggregate_tps_min'], batch * iterations / max(durations))
    close(timing['aggregate_tps_max'], batch * iterations / min(durations))
    comparison = result['checks']['optimized_vs_eager']['comparison']
    allow = workload.get('allow_greedy_rounding', False)
    if not allow and comparison['argmax_agreement_fraction'] != 1:
        raise ValueError('Strict result has greedy disagreement')
    if allow:
        if (comparison['acceptance_policy'] != 'logit_tolerance_with_reported_greedy_rounding'
                or comparison['logit_rtol'] != 0.005 or comparison['logit_atol'] != 0.05
                or comparison['batch_rows'] != batch):
            raise ValueError('Incorrect numerical acceptance policy')
        close(comparison['argmax_agreement_fraction'], 1 - comparison['greedy_mismatch_count'] / batch)
    return timing['aggregate_tokens_per_second']


def verify(package):
    package = Path(package).resolve(strict=True)
    evidence = package / 'evidence/h100'
    provenance = json.loads((evidence / 'IMPORT.json').read_text())
    for name, record in provenance['files'].items():
        relative = Path(name)
        if relative.is_absolute() or '..' in relative.parts:
            raise ValueError('Unsafe evidence path')
        if identity(package / relative) != record['released']:
            raise ValueError('Changed imported evidence: ' + name)
        if record['redaction'] is None and record['released']['sha256'] != record['source_sha256']:
            raise ValueError('Unexplained source transformation')
    passed, failed = [], []
    summaries = sorted(evidence.glob('h100-*/summary.json'))
    for path in summaries:
        summary = json.loads(path.read_text())
        if summary['status'] not in ('pass', 'partial_or_failed'):
            raise ValueError('Incomplete benchmark sweep')
        version = 'fp16-reference' if summary.get('allow_greedy_rounding') else 'strict'
        for source, digest in summary['source_sha256'].items():
            source_name = 'README.txt' if source == 'README.md' else source
            snapshot = package / 'benchmarks/h100/source-versions' / version / source_name
            if identity(snapshot)['sha256'] != digest:
                raise ValueError('Incorrect benchmark source provenance')
        for case in summary['cases']:
            stem = f"ctx{case['context']}-batch{case['batch']}-float16-{case['mode']}"
            if not (path.parent / (stem + '.txt')).is_file():
                raise ValueError('Missing worker record')
            if case['status'] == 'pass':
                result_path = path.parent / case['result']
                result = json.loads(result_path.read_text())
                rate = validate_result(result)
                if result['timing'] != case['timing']:
                    raise ValueError('Per-case/summary disagreement')
                passed.append({'file': result_path.relative_to(package).as_posix(),
                               'aggregate_tps': rate})
            elif case['status'] == 'failed':
                failed.append({'sweep': path.parent.name, **case})
            else:
                raise ValueError('Unrun case in completed record')
    if len(summaries) != 6 or len(passed) != 28 or len(failed) != 2:
        raise ValueError('Unexpected measurement inventory')
    selected = json.loads((package / SELECTED).read_text())
    strict = json.loads((package / STRICT).read_text())
    if (selected['workload']['batch'] != 32768 or selected['workload']['seed'] != 20260918
            or selected['workload']['mode'] != 'compile-graph'
            or not selected['workload']['allow_greedy_rounding']):
        raise ValueError('Selected comparison is not the documented repeat')
    for mode in ('graph', 'compile-graph'):
        replay = json.loads((evidence / 'correctness' / f'replay-{mode}.json').read_text())
        if (replay['status'] != 'pass' or replay['cuda_visible_devices'] != '0'
                or not replay['checks']['key_and_value_prefix_unchanged']
                or not replay['checks']['repeated_and_restored_outputs_exact']):
            raise ValueError('GPU replay check did not pass')
    return {'passed': True, 'sweeps': len(summaries), 'passed_cases': len(passed),
            'preserved_failed_cases': len(failed), 'imported_files': len(provenance['files']),
            'selected_reference_file': SELECTED,
            'selected_reference_tps': validate_result(selected),
            'strict_reference_file': STRICT, 'strict_reference_tps': validate_result(strict),
            'hardware_access': False, 'network_access': False,
            'scope': 'Saved-evidence integrity and accounting, not a new GPU run or an independently certified rating.'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', type=Path, default=Path(__file__).resolve().parents[1])
    print(json.dumps(verify(parser.parse_args().package), indent=2, sort_keys=True))
