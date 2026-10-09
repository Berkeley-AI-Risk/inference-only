#!/usr/bin/env python3
"""Check two-version evidence arithmetic and protected RTL/source bindings.

Offline only. This does not reproduce private raw UART logs, run a simulation,
prove integrity, program a board, or establish physical timing/security.
"""
import argparse
import hashlib
import importlib.util
import json
import math
from pathlib import Path, PurePosixPath

_spec = importlib.util.spec_from_file_location('leaf_history', Path(__file__).with_name('check_leaf_speed.py'))
_leaf = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_leaf)
historical_source_bytes = _leaf.historical_source_bytes

IMAGE = 'f51dfaa1f84be585db990f1037f5ae9d328b9064f2e26fc514ae41f9a7bcb324'
BASELINE = '344fcaca1ebd40a3bda35c02d8d3fe79e840200f532b6397c01730c9b75604fe'
LABEL_REVISIONS = {
    'host-app/runtime_profile.py': ('Optimized K/V integrity protection', 'K/V integrity protection'),
    'host-app/test_runtime_profile.py': ('Optimized K/V integrity protection', 'K/V integrity protection'),
    'host-app/streamlit_app.py': ('and the optimized protected build', 'and the protected build'),
}


def read(path): return json.loads(path.read_text())


def close(actual, expected):
    if not math.isfinite(actual) or not math.isclose(actual, expected, rel_tol=1e-10, abs_tol=1e-10):
        raise ValueError('Inconsistent measured arithmetic')


def check_physical(data):
    if (data['image_sha256'] != IMAGE or data['baseline_image_sha256'] != BASELINE
            or data['timing_qualified'] is not False
            or data['physical_corruption_injection_tested'] is not False
            or data['configuration_independently_attested'] is not False):
        raise ValueError('Wrong physical evidence scope')
    expected = {'known1': (1, 8), 'known8': (8, 8), 'prefix512': (512, 4), 'prefix2047': (2047, 2)}
    if len(data['cases']) != 4 or {row['case'] for row in data['cases']} != set(expected):
        raise ValueError('Incomplete matched campaigns')
    for row in data['cases']:
        prompt, count = expected[row['case']]
        if (row['prompt_tokens'] != prompt or len(row['generated_tokens']) != count
                or len(row['steps']) != count or not row['final_clear_acknowledged']):
            raise ValueError('Incomplete matched case')
        for ordinal, step in enumerate(row['steps'], 1):
            if step['ordinal'] != ordinal or min(step['baseline_seconds'], step['protected_seconds']) <= 0:
                raise ValueError('Invalid STEP time')
            close(step['latency_ratio'], step['protected_seconds'] / step['baseline_seconds'])
        base = [step['baseline_seconds'] for step in row['steps'][1:]]
        protected = [step['protected_seconds'] for step in row['steps'][1:]]
        if row['cached_decode_seconds'] != protected:
            raise ValueError('Cached times do not match the compared steps')
        close(row['baseline_cached_tokens_per_second'], len(base) / sum(base))
        close(row['protected_cached_tokens_per_second'], len(protected) / sum(protected))
        close(row['cached_latency_ratio'], sum(protected) / sum(base))
        close(row['first_step_seconds'], row['steps'][0]['protected_seconds'])
        close(row['first_step_latency_ratio'], row['steps'][0]['latency_ratio'])
    return len(data['cases'])


def check_sources(package, sources):
    for name, digest in sources.items():
        relative = PurePosixPath(name)
        if relative.is_absolute() or '..' in relative.parts:
            raise ValueError('Unsafe evidence source name')
        path = package / relative
        if path.is_symlink() or hashlib.sha256(historical_source_bytes(package, name, path.read_bytes())).hexdigest() != digest:
            raise ValueError('Changed evidence source: ' + name)


def check_host_source_bytes(name, raw, original_digest):
    """Reconstruct a board-tested file, permitting only the named label edit."""
    if name in LABEL_REVISIONS:
        old, new = (s.encode() for s in LABEL_REVISIONS[name])
        if old in raw or raw.count(new) != 1:
            raise ValueError('Unexpected host label revision: ' + name)
        raw = raw.replace(new, old, 1)
    if hashlib.sha256(raw).hexdigest() != original_digest:
        raise ValueError('Host behavior or unrecorded text changed: ' + name)


def undo_connection_revision(name, raw, record):
    """Recover the prior label-only host bytes from explicit, hash-bound edits."""
    change = record['changes'].get(name)
    if change is None:
        return raw
    if hashlib.sha256(raw).hexdigest() != change['after_sha256']:
        raise ValueError('Changed connection-reuse source')
    lines = raw.decode().splitlines(keepends=True)
    boundary = len(lines)
    for edit in reversed(change['reverse_edits']):
        start, end = edit['start'], edit['end']
        if (type(start) is not int or type(end) is not int
                or not 0 <= start <= end <= boundary
                or lines[start:end] != edit['after']):
            raise ValueError('Invalid host reverse edit')
        lines[start:end] = edit['before']
        boundary = start
    recovered = ''.join(lines).encode()
    if hashlib.sha256(recovered).hexdigest() != change['before_sha256']:
        raise ValueError('Host history reconstruction failed')
    return recovered


def check_connection_reuse(package, data):
    if (data['schema'] != 'host-connection-reuse-v1' or data['passed'] is not True
            or data['tested_variant'] != 'kv-protected' or data['image_sha256'] != IMAGE
            or data['generated_tokens_checked'] != 64
            or set(data['changes']) != {'host-app/fpga_backend.py', 'host-app/streamlit_app.py'}
            or data['added_host_sources'] != ['host-app/test_persistent_uart.py']):
        raise ValueError('Wrong connection-reuse evidence scope')
    for name in ('physical_uart', 'headless_ui_interaction', 'final_clear_acknowledged', 'connection_released'):
        if data[name] is not True: raise ValueError('Missing host physical check')
    for name in ('actual_browser_interaction', 'mocked_controller_or_transport',
                 'fpga_reprogrammed', 'flash_modified', 'timing_qualified', 'configuration_independently_attested'):
        if data[name] is not False: raise ValueError('Unsupported host evidence claim')
    expected = read(package / 'tests/reference-cases.json')['fox128']
    cases = data['cases']
    if data['prompt_tokens'] != expected['prompt_tokens'] or [r['label'] for r in cases] != ['cold', 'warm-1', 'warm-2', 'reopened']:
        raise ValueError('Wrong host workloads')
    for row in cases:
        if (row['commands'] != 26 or row['generated_tokens'] != expected['generated_tokens'][:16]
                or row['final_clear_acknowledged'] is not True
                or row['reused'] is not row['label'].startswith('warm')):
            raise ValueError('Wrong host output or lifecycle check')
        for key in ('first_token_seconds', 'streaming_tokens_per_second'):
            if not math.isfinite(row[key]) or row[key] <= 0: raise ValueError('Invalid host timing')
    close(data['cold_mean_seconds'], sum(r['first_token_seconds'] for r in cases if not r['reused']) / 2)
    close(data['warm_mean_seconds'], sum(r['first_token_seconds'] for r in cases if r['reused']) / 2)
    previous = package / 'evidence/kv-protected/host-label-cleanup.json'
    if hashlib.sha256(previous.read_bytes()).hexdigest() != data['previous_host_revision_sha256']:
        raise ValueError('Changed prior host record')
    files = read(package / 'MANIFEST.json')['files']
    expected_sources = {name for name in files if name.startswith('host-app/')
        and name != 'host-app/hardware-inputs-encrypted-memory.json'
        and (Path(name).suffix in ('.py', '.toml', '.json') or name == 'host-app/requirements.txt')}
    if set(data['current_host_sources']) != expected_sources:
        raise ValueError('Incomplete connection-reuse source binding')
    check_sources(package, data['current_host_sources'])
    return 64


def check_host_revision(package, sources):
    connection = read(package / 'evidence/host-connection-reuse.json')
    check_connection_reuse(package, connection)
    record = read(package / 'evidence/kv-protected/host-label-cleanup.json')
    if (record['passed'] is not True or record['offline_host_tests'] != 47
            or record['hardware_access'] is not False or record['new_physical_test'] is not False
            or record['board_protocol_changed'] is not False
            or set(record['changes']) != set(LABEL_REVISIONS)
            or set(record['current_host_sources']) != set(sources)
            or record['original_rehearsal_sha256'] != hashlib.sha256(
                (package / 'evidence/kv-protected/release-rehearsal.json').read_bytes()).hexdigest()):
        raise ValueError('Wrong label-only revision scope')
    for name, original in sources.items():
        path = package / name
        if path.is_symlink(): raise ValueError('Linked host source')
        raw = undo_connection_revision(name, historical_source_bytes(package, name, path.read_bytes()), connection)
        current = hashlib.sha256(raw).hexdigest()
        if current != record['current_host_sources'][name]: raise ValueError('Host revision hash changed')
        if name in LABEL_REVISIONS:
            old, new = LABEL_REVISIONS[name]
            if record['changes'][name] != dict(before_sha256=original, after_sha256=current,
                    old_text=old, new_text=new):
                raise ValueError('Host revision description changed')
        check_host_source_bytes(name, raw, original)
    return len(LABEL_REVISIONS)


def check_rehearsal(package, data):
    if (data['passed'] is not True or data['offline_host_tests'] != 47
            or data['total_reference_matching_outputs'] != 40
            or any(data[k] is not False for k in ('flash_modified', 'compiler_rerun',
                'physical_corruption_injection_tested', 'timing_qualified'))
            or set(data['trials']) != {'baseline', 'kv-protected'}):
        raise ValueError('Wrong release rehearsal scope')
    files = read(package / 'MANIFEST.json')['files']
    expected_sources = {name for name in files if name.startswith('host-app/')
        and name != 'host-app/hardware-inputs-encrypted-memory.json'
        and (Path(name).suffix in ('.py', '.toml', '.json') or name == 'host-app/requirements.txt')}
    if set(data['unchanged_host_executable_sources']) != expected_sources:
        if set(data['unchanged_host_executable_sources']) != expected_sources - {'host-app/test_persistent_uart.py'}:
            raise ValueError('Incomplete rehearsed host binding')
    check_host_revision(package, data['unchanged_host_executable_sources'])
    expected = read(package / 'tests/reference-cases.json')['fox128']
    for variant, digest in [('baseline', BASELINE), ('kv-protected', IMAGE)]:
        trial = data['trials'][variant]
        if (trial['passed'] is not True or trial['image_sha256'] != digest
                or trial['variant'] != variant or trial['ui_commands'] != 26
                or trial['qualification_commands'] != 7 or trial['qualification_generated_tokens'] != 4
                or trial['prompt_tokens'] != expected['prompt_tokens']
                or trial['ui_generated_tokens'] != expected['generated_tokens'][:16]
                or trial['package_manifest_sha256'] != data['tested_package_manifest_sha256']):
            raise ValueError('Wrong rehearsal outputs or image')
        for key in ('physical_uart', 'headless_ui_interaction', 'displayed_metrics_match',
                    'variant_label_checked', 'final_clear_acknowledged', 'raw_frames_and_crc_rechecked'):
            if trial[key] is not True: raise ValueError('Missing physical rehearsal check')
        for key in ('mocked_controller_or_transport', 'actual_browser_interaction', 'flash_modified', 'timing_qualified'):
            if trial[key] is not False: raise ValueError('Wrong physical rehearsal scope')
        for key in ('first_token_seconds', 'streaming_tokens_per_second'):
            if not math.isfinite(trial[key]) or trial[key] <= 0: raise ValueError('Invalid rehearsal measurement')
        preflight = data['source_build_preflight'][variant]
        if (preflight['passed'] is not True or preflight['writes'] is not False
                or preflight['hardware_access'] is not False
                or preflight['input_files'] != (90 if variant == 'baseline' else 93)):
            raise ValueError('Wrong build preflight scope')
    return 40


def check(package):
    package = Path(package).resolve(strict=True)
    evidence = package / 'evidence/kv-protected'
    cases = check_physical(read(evidence / 'physical-summary.json'))
    simulation = read(evidence / 'simulation-summary.json')
    if simulation['unbounded_guard_proof'] or simulation['physical_weight_authentication_banks'] != 4:
        raise ValueError('Wrong simulation scope')
    for name, count in [('integrated0', 42), ('integrated-clear0', 6), ('integrated-smoke0', 4)]:
        tests = simulation['campaigns'][name]['cases']
        if len(tests) != count or not all(value is True for value in tests.values()):
            raise ValueError('Incomplete simulation summary')
    hardware = package / 'variants/kv-protected/hardware/project'
    sources = simulation['production_sha256']
    if len(sources) != 66: raise ValueError('Incomplete production-source binding')
    for name, digest in sources.items():
        relative = PurePosixPath(name)
        if relative.is_absolute() or '..' in relative.parts: raise ValueError('Unsafe source name')
        source = hardware / name
        public_name = 'variants/kv-protected/hardware/project/' + name
        if source.is_symlink() or hashlib.sha256(historical_source_bytes(package, public_name, source.read_bytes())).hexdigest() != digest:
            raise ValueError('Changed protected model/transport source: ' + name)
    native = read(evidence / 'native-summary.json')
    if (native['image_sha256'] != IMAGE or native['timing_qualified'] is not False
            or native['global_violated_endpoints'] != {'setup': 163, 'hold': 8}
            or not native['endpoint_census_complete'] or not native['nonvendor_screen_clear']):
        raise ValueError('Wrong native timing scope')
    baseline = {'Logic': 80732, 'Register': 49874, 'CLS': 56736, 'BSRAM': 196, 'DSP': 74.5}
    for name, used in baseline.items():
        close(native['resources'][name]['used'] - used, native['resource_change_from_baseline'][name])
    rehearsed = check_rehearsal(package, read(evidence / 'release-rehearsal.json'))
    replay = read(evidence / 'replay-summary.json')
    if (replay['passed'] is not True or replay['hardware_access'] is not False
            or replay['unbounded_proof'] is not False or replay['full_model_replayed'] is not False
            or len(replay['sources']) != 8 or len(replay['runs']) != 5
            or not all(row['passed'] is True for row in replay['runs'].values())
            or replay['runs']['guard-replay0']['commands'] != 5407
            or replay['runs']['geometry-replay0']['commands'] != 275913):
        raise ValueError('Wrong guard replay summary')
    check_sources(package, replay['sources'])
    selected = _leaf.check(package)
    return dict(passed=True, matched_physical_cases=cases, matched_production_sources=len(sources),
        packaged_rehearsal_outputs=rehearsed, guard_replay_runs=len(replay['runs']),
        post_rehearsal_label_only_files=len(LABEL_REVISIONS),
        subsequent_connection_reuse_files=2, connection_reuse_outputs=64,
        selected_leaf_speed=selected, previous_rows_are_historical=True,
        timing_qualified=False, unbounded_guard_proof=False, hardware_access=False, network_access=False,
        scope='Historical summaries with exact old-source reconstruction, plus selected-build evidence checks; not fresh hardware, raw-log replay or a proof.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    print(json.dumps(check(args.package), indent=2, sort_keys=True))


if __name__ == '__main__': main()
