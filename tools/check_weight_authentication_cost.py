#!/usr/bin/env python3
"""Replay the sanitized authentication-cost transcripts; never access hardware.

Checks recorded UART bytes, reference answers, CLEAR/replay, timings, source
delta and workload census. This is not independent attestation of the board,
a new numerical-model execution, timing signoff or a security certification.
"""
import argparse
import hashlib
import importlib.util
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIRECTORY = 'evidence/weight-authentication-cost'
BASELINE = '6ba3caa4f88ac58dd30336c3ff4478f836779db0d04309ff457ca065ec1f7f09'
DIAGNOSTIC = '3b59c439ec0ccfdfbac460b63811ac0c10ef0b095a1068aec50d987f16b1702a'
RESTORE = '72d5a54e06ed2017e653122f3daecf073f239a917b79f24d1e7b886d68a21a2f'
BANK = '46015eec480c0549d6f6117e96ec3d59f5849ed257da687bd3f424c910572046'
MODEL = 'cad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0'
ORDER = [('baseline-1', ['around128', 'prefix128', 'prefix512', 'prefix2047']),
         ('candidate-1', ['around128', 'prefix128', 'prefix512', 'prefix2047']),
         ('candidate-2', ['around128', 'prefix128']), ('baseline-2', ['around128', 'prefix128']),
         ('baseline-3', ['around128', 'prefix128']), ('candidate-3', ['around128', 'prefix128']),
         ('restore-1', ['around128'])]
FIELDS = {
    'open_intent': {'initial_driver_buffer_flush', 'automatic_retries', 'configuration_independently_attested'},
    'command_intent': {'hex', 'label'}, 'raw_chunk': {'direction', 'hex'},
    'decoded': {'frame_hex', 'kind', 'response', 'token'},
    'command_result': {'expected_kind', 'expected_token', 'label', 'operand', 'operation',
                       'received', 'seconds', 'timeout'},
    'waiting': {'label', 'seconds'},
}


def need(ok, message):
    if not ok:
        raise ValueError(message)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(path):
    return json.loads(Path(path).read_text())


def positive(value):
    return type(value) in (int, float) and math.isfinite(value) and value > 0


def module(path):
    spec = importlib.util.spec_from_file_location('authentication_cost_uart_replay', path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def diagnostic_bank(text):
    changes = [('state_q<=valid_words_q==128 ? READ0 : ZERO;',
                'state_q<=valid_words_q==128 ? READY : ZERO;'),
               ('if(fill_count_q==127) state_q<=READ0;', 'if(fill_count_q==127) state_q<=READY;'),
               ('.start_i(state_q==LAUNCH && !fault_o)', ".start_i(1'b0)")]
    for before, after in changes:
        need(text.count(before) == 1 and after not in text, 'Different bank source seam')
        text = text.replace(before, after, 1)
    return '// PRIVATE BOARD DIAGNOSTIC: NO RUNTIME WEIGHT INTEGRITY. NOT A RELEASE.\n' + text


def diagnostic_build_inputs(package, directory, expected, native):
    """Separate the original recipe from the actual expanded-report run."""
    executed = native['executed_input_sha256']
    extra = {'project/impl/gwsynthesis/shared_product.vg', 'project/prior_auth_off.pr'}
    need(set(executed) == set(expected) | extra and len(executed) == 92, 'Different executed build input census')
    sdc = 'project/constraints/product.sdc'
    need(all(executed[n] == h for n, h in expected.items() if n not in ('run.tcl', sdc)),
         'Unreviewed executed design change')
    before = (package / 'hardware' / sdc).read_text()
    after = (directory / 'build-record/product.sdc').read_text()
    need(before.count('-max_paths 256') == 8 and after == before.replace('-max_paths 256', '-max_paths 1024')
         and sha(directory / 'build-record/product.sdc') == executed[sdc], 'Changed timing policy beyond report limits')
    before = (package / 'hardware/run.tcl').read_text()
    removed = ('if {[catch {run syn} result options]} {puts stderr $result; exit 1}\n'
               'puts "LOCAL_KV_SYN_COMPLETE hardware_access=0"\nflush stdout\n')
    need(before.count(removed) == 1, 'Changed original build recipe')
    expected_recipe = ('set work_root [pwd]\n' + before.replace(removed, '', 1)).replace(
        'if {[catch {run pnr}', 'set_option -inc [file join $work_root project prior_auth_off.pr]\nif {[catch {run pnr}', 1)
    need((directory / 'build-record/run.tcl').read_text() == expected_recipe
         and sha(directory / 'build-record/run.tcl') == executed['run.tcl'], 'Changed executed build recipe')
    need(native['derived_inputs_included'] is False and native['exact_netlist_or_route_reuse_claimed'] is False,
         'Unsupported complete-build/reuse claim')


def replay_case(replayer, reference, events):
    need(events and events[0]['monotonic_ns'] == 0, 'Transcript must start at relative time zero')
    for event in events:
        kind = event['event']
        need(kind in FIELDS and set(event) == FIELDS[kind] | {'event', 'monotonic_ns'},
             'Unknown, missing or unsanitized transcript fields')
        need(type(event['monotonic_ns']) is int and event['monotonic_ns'] >= 0, 'Invalid timestamp')
        if kind == 'command_result':
            need(positive(event['seconds']), 'Invalid measured duration')
        if kind == 'open_intent':
            need(event['automatic_retries'] is False and event['initial_driver_buffer_flush'] is True
                 and event['configuration_independently_attested'] is False, 'Different session policy')
    plan = replayer.commands(reference['prompt_tokens'], reference['generated_tokens'])
    result = replayer.replay(plan, events)
    need(result['long_generated_tokens'] == reference['generated_tokens']
         and result['all_generated_tokens'] == len(reference['generated_tokens']) + 12
         and result['final_clear_acknowledged'], 'Different model answers or missing CLEAR/replay')
    return result


def compare(before, after):
    a, b = before['measured'], after['measured']
    need(before['case'] == after['case'] and a['long_generated_tokens'] == b['long_generated_tokens'],
         'Unmatched workloads or outputs')
    x, y = a['cached_decode_seconds'], b['cached_decode_seconds']
    need(len(x) == len(y) > 0 and all(positive(v) for v in x + y), 'Incomplete cached timing samples')
    ratio = sum(x) / sum(y)
    return dict(pair=int(before['trial'].split('-')[-1]), case=before['case'],
        prompt_tokens=before['prompt_tokens'], outputs=len(x) + 1, cached_samples=len(x),
        baseline_cached_tokens_per_second=len(x) / sum(x),
        diagnostic_cached_tokens_per_second=len(y) / sum(y),
        extra_time_per_token_fraction=ratio - 1,
        throughput_loss_fraction=1 - 1 / ratio,
        baseline_first_step_seconds=a['first_step_seconds'], diagnostic_first_step_seconds=b['first_step_seconds'],
        baseline_prompt_to_first_token_seconds=a['first_append_to_first_reply_seconds'],
        diagnostic_prompt_to_first_token_seconds=b['first_append_to_first_reply_seconds'])


def check(package=ROOT):
    package = Path(package)
    directory = package / DIRECTORY
    board, native = read(directory / 'board.json'), read(directory / 'native.json')
    need(board['schema'] == 'tang-runtime-weight-authentication-cost-v1'
         and board['inference_clock_hz'] == 25000000 and board['model_image_sha256'] == MODEL
         and board['startup_authentication_retained'] is True
         and board['comparison_kv_integrity'] is False and board['comparison_weight_encryption'] is False,
         'Different experiment scope')
    for key in ('timing_qualified', 'physical_security_qualified', 'configuration_independently_attested',
                'unauthenticated_redesign_speed_limit', 'host_selectable_authentication_switch'):
        need(board[key] is False, 'Unsupported qualification: ' + key)
    need(board['images'] == dict(baseline=BASELINE, candidate=DIAGNOSTIC, restore=RESTORE), 'Different image selection')
    need(sha(package / 'assets/board1-real-semantic-image2048.bin') == MODEL
         and sha(package / 'prebuilt/inference/project/impl/pnr/shared_product.fs') == BASELINE
         and sha(package / 'prebuilt/kv-protected/project/impl/pnr/shared_product.fs') == RESTORE, 'Changed release assets')
    inventory = read(package / 'host-app/hardware-inputs.json')
    expected = dict(inventory); expected['project/bank.sv'] = BANK
    need(native['baseline_inputs'] == inventory and native['diagnostic_original_recipe_inputs'] == expected and len(inventory) == 90,
         'Different native input/source census')
    diagnostic_build_inputs(package, directory, expected, native)
    for name, pin in inventory.items():
        if not name.startswith('project/official/'):
            need(sha(package / 'hardware' / name) == pin, 'Changed baseline source: ' + name)
    bank = (directory / 'bank-diagnostic.sv').read_text()
    need(bank == diagnostic_bank((package / 'hardware/project/bank.sv').read_text())
         and sha(directory / 'bank-diagnostic.sv') == BANK, 'Diagnostic changes beyond the selected runtime bank')
    need(native['diagnostic_image_sha256'] == DIAGNOSTIC and native['timing_qualified'] is False
         and native['diagnostic_negative_endpoints'] == dict(setup_recovery=224, hold_removal=7)
         and native['diagnostic_negative_paths_vendor_ddr_only'] is True,
         'Changed native association or overstated timing')
    references = read(package / 'evidence/read-window/references.json')
    need(sha(package / 'evidence/read-window/references.json') == board['reference_file_sha256'], 'Changed reference tokens')
    replayer = module(directory / 'uart_replay.py')
    wanted = [(trial, case) for trial, cases in ORDER for case in cases]
    need([(r['trial'], r['case']) for r in board['cases']] == wanted, 'Missing, reordered or selected-away trial')
    checked = {}; main = auxiliary = 0
    for row in board['cases']:
        trial, case = row['trial'], row['case']
        relative = f'transcripts/{trial}/{case}.jsonl'
        need(row['transcript'] == relative and row['image_sha256'] == board['images'][trial.split('-')[0]]
             and row['transcript_sha256'] == sha(directory / relative), 'Changed transcript/image association')
        events = [json.loads(line) for line in (directory / relative).read_text().splitlines()]
        measured = replay_case(replayer, references[case], events)
        need(row['prompt_tokens'] == len(references[case]['prompt_tokens']) and row['measured'] == measured,
             'Saved measurements do not match transcript')
        checked[(trial, case)] = row
        main += len(measured['long_generated_tokens']); auxiliary += 12
    comparisons = [compare(checked[(f'baseline-{pair}', case)], checked[(f'candidate-{pair}', case)])
                   for pair in (1, 2, 3) for case in ORDER[0][1] if pair == 1 or case in ORDER[2][1]]
    need(board['comparisons'] == comparisons and main == 1676 and auxiliary == 204, 'Wrong results or output census')
    return dict(passed=True, board_cases=17, comparisons=8, main_outputs=main, auxiliary_outputs=auxiliary,
        comparisons_recomputed=comparisons, sanitized_uart_transcripts_replayed=True,
        numerical_reference_rerun=False, hardware_access=False, network_access=False,
        physical_attestation=False, timing_qualified=False)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', type=Path, default=ROOT)
    print(json.dumps(check(parser.parse_args().package), indent=2))
