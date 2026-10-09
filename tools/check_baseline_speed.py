#!/usr/bin/env python3
"""Check current baseline measurements and exact recorded source associations.

Offline consistency and arithmetic only: no UART replay, physical attestation,
new solver execution, DDR timing certification, or security certification.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIRECTORY = 'evidence/baseline-current'
IMAGE = '6ba3caa4f88ac58dd30336c3ff4478f836779db0d04309ff457ca065ec1f7f09'
RESTORED = 'e22079c855cdf6cfb983c73850db15b1b5010f0511fa62f98f3d040ae0654ea2'
INPUTS = '8955cde51f78b582612ca4ee61d146b6128a85a535b3d492d325a4168f77e334'
ORDER = ['around128', 'prefix128', 'prefix512', 'around128-repeat', 'prefix2047', 'prefix2048']
FIRST_RUN = '68ad49d877302a80a6ef06ed744e3e389690cf890f37ad9375ced0973988c7c3'
FINAL_RUN = '76e9ff26075cefba9b9e1b28dc24fb0b367efce0038b41155ec6c35534556c64'


def need(ok, why):
    if not ok: raise ValueError(why)


def close(a, b):
    need(type(a) in (int, float) and math.isfinite(a) and a > 0 and
         math.isclose(a, b, rel_tol=1e-10, abs_tol=1e-10), 'Incorrect measurement arithmetic')


def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def read(path): return json.loads(Path(path).read_bytes())
def digest(value):
    return isinstance(value, str) and len(value) == 64 and all(c in '0123456789abcdef' for c in value)


def replay_sources(package):
    selected = ('hardware/', 'simulation/model/', 'formal/page-bank/', 'formal/token-shell/', 'formal/composed-shell/')
    replayers = {f'tools/check_{n}.py' for n in ('model_rtl', 'page_bank', 'token_shell', 'composed_shell')}
    return {n: r['sha256'] for n, r in read(Path(package)/'MANIFEST.json')['files'].items()
            if n.startswith(selected) or n in replayers}


def validate_replay(package, data):
    need(data['schema'] == 'tang-baseline-speed-replay-v3' and data['passed'] is True and
         data['image_sha256'] == IMAGE, 'Wrong recorded replay')
    need(data['run_manifest_sha256'] == dict(model=FIRST_RUN, bank=FINAL_RUN, token=FIRST_RUN, composed=FIRST_RUN),
         'Wrong numerical/formal source association')
    for key in ('hardware_access', 'network_access', 'whole_machine_refinement',
                'sha_compression_correctness_proved', 'mapped_equivalence_proved'):
        need(data[key] is False, 'Unsupported replay qualification')
    need(data['model'] == dict(production_sources=64, cases=4, exact_positive_steps=10, weight_corruption_rejections=2) and
         data['page_bank'] == dict(assertions=42, both_solvers_complete=True, directed_scenarios=10, negative_controls=5) and
         data['token_shell'] == dict(assertions=48, both_solvers_complete=True, negative_controls=5), 'Wrong replay census')
    composed = data['composed']; conclusions = set(range(134)) - {39}
    need(composed['assertions'] == 134 and composed['primary_joint_induction_passed'] is True and
         composed['serial_scenarios'] == 13 and composed['negative_controls'] == 5 and
         composed['complete_second_solver'] is False and composed['secondary_unresolved'] == [39] and
         composed['secondary_conclusions'] == sorted(conclusions), 'Wrong composed-proof scope')
    runs = composed['secondary_runs']
    need(len(runs) == 2 and runs[0]['conclusions_checked'] == 134 and runs[1]['conclusions_checked'] == 7 and
         runs[0]['unresolved'] == [39,45,49,50,52,54,58,123] and runs[1]['unresolved'] == [] and
         runs[1]['proved'] == [45,49,50,52,54,58,123] and
         runs[0]['proved'] == sorted(set(range(134)) - set(runs[0]['unresolved'])) and
         set(runs[0]['proved']) | set(runs[1]['proved']) == conclusions,
         'Wrong secondary-solver record')
    need(composed['secondary_reused_for_identical_queries'] is True and
         digest(composed['previous_replay_sha256']) and
         composed['query_artifacts_sha256'] == read(Path(package)/'formal/composed-shell/expected.json')['proof_artifacts'],
         'Wrong secondary query association')
    need(set(data['receipt_sha256']) == {'model', 'bank', 'token', 'composed'} and
         all(digest(h) for h in data['receipt_sha256'].values()), 'Missing replay receipts')
    need(data['source_sha256'] == replay_sources(package), 'Changed replay input census')
    for name, pin in data['source_sha256'].items():
        need(not Path(name).is_absolute() and '..' not in Path(name).parts and sha(Path(package)/name) == pin,
             'Changed replay input')
    return dict(recorded_model_cases=4, recorded_scoped_assertions=[42,48,134],
                composed_second_solver_conclusions=133, second_solver_complete=False,
                solver_execution_repeated_by_this_check=False)


def validate(data, references):
    need(data['image_sha256'] == IMAGE and data['restored_image_sha256'] == RESTORED and
         data['restoration_checked'] is True and data['full_context_board_test_of_this_image'] is True,
         'Wrong measured image or incomplete board evidence')
    rows = data['cases']
    need([r['label'] for r in rows] == ORDER, 'Missing or reordered board cases')
    count = 0
    for row in rows:
        name = row['case']; reference = references[name]; n = len(reference['generated_tokens'])
        need(name == row['label'].removesuffix('-repeat') and
             row['prompt_tokens'] == len(reference['prompt_tokens']) and row['outputs'] == n and
             row['long_generated_tokens'] == reference['generated_tokens'], 'Different reference tokens')
        need(row['image_sha256'] == IMAGE, 'Wrong measured image')
        need(row['final_clear_acknowledged'] is True and row['clear_replay_outputs'] == 12 and
             row['negative_controls_rejected'] == 4 and
             row['expected_rejections'] == (6 if name in ('prefix2047', 'prefix2048') else 3),
             'Missing CLEAR/replay or rejection controls')
        times = [row['first_step_seconds']] + row['cached_decode_seconds']
        elapsed = row['reply_elapsed_seconds']
        need(len(times) == len(elapsed) == n and n >= 1 and elapsed[0] == 0 and
             all(type(t) in (int,float) and math.isfinite(t) and t > 0 for t in times) and
             all(type(t) in (int,float) and math.isfinite(t) for t in elapsed) and
             all(b > a for a, b in zip(elapsed, elapsed[1:])), 'Invalid duration census')
        if n > 1:
            close(row['cached_command_tokens_per_second'], (n-1)/sum(times[1:]))
            close(row['cached_stream_tokens_per_second'], (n-1)/elapsed[-1])
            need(elapsed[-1] >= sum(times[1:]), 'Stream omits command time')
        else:
            need(row['cached_command_tokens_per_second'] is None and row['cached_stream_tokens_per_second'] is None,
                 'No cached rate exists for a single reply')
        if name == 'around128': close(row['first_six_step_tokens_per_second'], 6/sum(times[:6]))
        else: need(row['first_six_step_tokens_per_second'] is None, 'Unexpected short-test claim')
        for key in ('private_uart_sha256', 'private_receipt_sha256', 'reference_receipt_sha256'):
            need(digest(row[key]), 'Invalid evidence hash')
        count += n
    need(data['reference_matching_outputs'] == count == 391 and data['clear_replay_outputs'] == 72,
         'Incorrect output census')
    need(data['repeated_cached_tokens_per_second'] == [rows[i]['cached_command_tokens_per_second'] for i in (0,3)],
         'Different repeated measurements')
    return dict(passed=True, current_baseline_outputs=391, current_baseline_clear_replay_outputs=72,
                full_context_board_test=True, private_uart_replayed=False, timing_qualified=False)


def check(package):
    package = Path(package); directory = package/DIRECTORY
    references = read(package/'evidence/read-window/references.json')
    old = read(package/'evidence/encrypted-memory/broad-board.json')['reference_cases']
    canonical = (json.dumps(old, sort_keys=True, separators=(',',':'))+'\n').encode()
    need(hashlib.sha256(canonical).hexdigest() == '00e4e7ef40f965b3c5a0fbf035ce2ee01b4bd85c187a3cfd2e91c0ad124e2a6f' and
         all(old[n] == r for n,r in references.items() if n in old), 'Changed established integer references')
    board = read(directory/'board.json'); result = validate(board, references)
    all_board = read(package/'evidence/read-window/board.json')
    need(all_board['schema'] == 'tang-current-board-v1' and all_board['variants']['baseline'] == board and
         all_board['measured_on_physical_board'] is True and all_board['private_raw_records_rechecked'] is True,
         'Different source board evidence')
    for key in ('timing_qualified', 'physical_security_qualified', 'configuration_independently_attested',
                'public_summary_replays_private_transcripts', 'flash_modified'):
        need(all_board[key] is False, 'Unsupported physical qualification')
    metrics = read(directory/'metrics.json'); native = read(directory/'native.json')
    implementation = read(directory/'implementation.json'); build = read(package/'prebuilt/inference/BUILD.json')
    need(metrics['source_physical_sha256'] == sha(directory/'board.json') and
         implementation['source_native_sha256'] == sha(directory/'native.json'), 'Changed evidence source')
    need(all(r['image_sha256'] == IMAGE for r in (metrics,native,implementation,build)) and
         sha(package/'prebuilt/inference/project/impl/pnr/shared_product.fs') == IMAGE, 'Selected image changed')
    inventory = read(package/'host-app/hardware-inputs.json')
    canonical = (json.dumps(inventory, sort_keys=True, separators=(',',':'))+'\n').encode()
    need(hashlib.sha256(canonical).hexdigest() == INPUTS == native['hardware_inputs_sha256'] == build['hardware_inputs_sha256'],
         'Changed selected source inventory')
    for name, pin in inventory.items():
        if not name.startswith('project/official/'):
            need(sha(package/'hardware'/name) == pin, 'Changed production source')
    need(native['input_files'] == 90 and native['inference_clock_mhz'] == 25 and
         native['global_violated_endpoints'] == dict(setup=145,hold=10) and
         native['timing_qualified'] is False and native['physical_security_qualified'] is False and
         native['kv_integrity'] is False and native['weight_encryption'] is False, 'Wrong native scope')
    close(native['inference_setup_slack_ns'], .018); close(native['inference_hold_slack_ns'], .144)
    need(implementation['mapped_multiplier_primitives'] == native['mapped_multiplier_primitives'] ==
         dict(MULTALU27X18=73,MULT12X12=3) and implementation['resources'] == native['resources'],
         'Changed resource census')
    need(set(metrics['metrics']) == set(ORDER), 'Wrong metric workload census')
    for row in board['cases']:
        need(metrics['metrics'][row['label']] == dict(prompt_tokens=row['prompt_tokens'], generated_tokens=row['outputs'],
            occupied_tape=row['prompt_tokens']+row['outputs'], all_tokens_match_integer_reference=True,
            first_step_seconds_including_prompt_evaluation=row['first_step_seconds'],
            last_step_seconds=row['cached_decode_seconds'][-1] if row['cached_decode_seconds'] else None,
            streaming_tokens_per_second_excluding_first=row['cached_stream_tokens_per_second']),
            'Different selected capacity metric')
    result.update(validate_replay(package, read(directory/'replay.json')))
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument('--package', type=Path, default=ROOT)
    print(json.dumps(check(parser.parse_args().package), indent=2))
