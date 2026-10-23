#!/usr/bin/env python3
"""Check archived 128-output seeded runs and reference bindings; no hardware/model replay."""
import argparse
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RECORD = 'evidence/seeded-sampling/matched128.json'
ARCHIVE_SHA = '71991f5e0bcfc20e45fec2202dcde60ca0ad38bd2270043270850d1ae2687bec'
IMAGE_SHA = '0e6d30b68bd8757657bc1c3b949ac5b9571a0a8d1f8bb1a6e6018b241f733033'
INPUTS_SHA = '26a0885f9ffefaeea68b948295635fcfb37367254b549c48e75e0d7093e96831'
MODEL_SHA = 'cad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0'
SEED = '0x99aabbccddeeff001122334455667788'
TEMPERATURES = ('0', '0.5', '1', '2')
REFERENCE_PINS = {
    '0': 'dd952fe6964055506401e70bf4cc3d5388eef33b9cf2d90f0a68499a131b2bdc',
    '1': '5074b0c9380a445f1eb13eb62d2c10bc0787842c989ec50b47ea8a048a3b22a9',
    '2': '00a90c655ea5b7c89a873a19eeca6282a7da48f15a19e9547d02161cde295d38',
    '3': '1dff92cdddb04276e8d5e94b2705c3ab27c7b8ba48c19bb0d7cd6b0aa78cfc3d'}
PROVENANCE = {
    'source_capture_sha256': '31d8f6e6627a05ca83768c26b294052869b45ca2598712a99da34112d8b8304c',
    'source_comparison_sha256': '3ef998c3c437ca41c3592fe12c6b79b5870778fff0a9c5ccc3fd45869942c76c',
    'source_reference_finished_sha256': '360a36673fe4c662ad5978ac668f86cf35342ffb7ddc5da24f7f750df2443f20',
    'source_comparison_tool_sha256': '8a6137a3df22a886cb1dc5599046664b8311fa0997803cef7fc90db97d2480a4'}


def need(ok, message):
    if not ok:
        raise ValueError(message)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(',', ':')) + '\n').encode()


def crc8(data):
    value = 0
    for byte in data:
        value ^= byte
        for _ in range(8):
            value = ((value << 1) ^ (7 if value & 128 else 0)) & 255
    return value


def frame(body):
    return (body + bytes((crc8(body),))).hex()


def positive(value):
    need(type(value) in (int, float) and math.isfinite(value) and value > 0, 'Invalid duration')


def equal(actual, expected):
    positive(actual)
    need(math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-12), 'Timing arithmetic differs')


def validate(data):
    need(data['schema'] == 'seeded-matched128-public-v1' and data['passed'] is True, 'Wrong record')
    need(data['image_sha256'] == IMAGE_SHA and data['hardware_inputs_sha256'] == INPUTS_SHA, 'Wrong image/source')
    need(all(data[key] == value for key, value in PROVENANCE.items()), 'Changed historical provenance')
    need(data['physical_fpga'] is True and all(data[key] is False for key in (
        'flash_modified', 'configuration_independently_attested', 'whole_model_reference_replayed_by_public_checker',
        'full_context_qualified', 'timing_qualified', 'security_certified')), 'Unsupported qualification claim')
    need(data['total_outputs_compared'] == 1024 and data['positive_temperature_outputs_compared'] == 768, 'Wrong counts')
    need(set(data['references']) == set(REFERENCE_PINS), 'Reference census differs')
    for code, reference in data['references'].items():
        need(sha(canonical(reference)) == REFERENCE_PINS[code], 'Changed independent reference')
        need(reference['model_image_sha256'] == MODEL_SHA and len(reference['generated_tokens']) == 128,
             'Wrong reference model/output count')
    need(len(data['cases']) == 8, 'Missing repetition')
    for index, case in enumerate(data['cases']):
        code, repeat = divmod(index, 2)
        temperature = TEMPERATURES[code]
        tokens = data['references'][str(code)]['generated_tokens']
        need(case['label'] == f'T{temperature}-run{repeat + 1}' and case['temperature'] == temperature,
             'Case order/temperature differs')
        need(case['seed'] == SEED and case['prompt_tokens'] == [378]
             and case['replay_without_settings'] is bool(repeat)
             and case['final_clear_acknowledged'] is True, 'Wrong seed/prompt/replay/CLEAR')
        need(case['generated_tokens'] == tokens, 'Output differs from independent model reference')
        legacy = lambda opcode, operand=0: frame(bytes((0xa5, opcode, operand & 255, operand >> 8)))
        commands = [('clear', legacy(2), 0x82, 0)]
        if not repeat:
            commands.append(('settings', frame(bytes((0xa5, 3, code)) + int(SEED, 0).to_bytes(16, 'little')), 0x83, code))
        commands.append(('append-1', legacy(0, 378), 0x80, 0))
        commands.extend((f'step-{i + 1}', legacy(1), 0x81, token) for i, token in enumerate(tokens))
        commands.append(('clear', legacy(2), 0x82, 0))
        expected = []
        for n, (operation, tx, kind, operand) in enumerate(commands):
            expected.extend([('tx', operation, tx),
                ('rx', operation, frame(bytes((0x5a, kind, operand & 255, operand >> 8)))),
                ('operation', operation, kind, operand)])
            if n in (0, len(commands) - 1):
                expected.append(('wire_quiet', 'initial-clear-drain' if n == 0 else 'final-clear-drain', .1, ''))
        need(len(case['wire']) == len(expected), 'Wire event count differs')
        previous, sends, durations, arrivals, completion_windows = -1, {}, [], [], []
        for sequence, (row, want) in enumerate(zip(case['wire'], expected), 1):
            ns = row['elapsed_ns']
            need(type(ns) is int and ns > previous and (sequence != 1 or ns == 0)
                 and row['sequence'] == sequence, 'Wire timeline/order differs')
            previous = ns
            event, operation = row['event'], row['operation']
            if event in ('tx', 'rx'):
                observed = event, operation, row['frame_hex']
                if event == 'tx':
                    sends[operation] = ns
                    if completion_windows and len(completion_windows[-1]) == 1:
                        completion_windows[-1].append(ns)
                elif operation.startswith('step-'): arrivals.append(ns)
            elif event == 'operation':
                observed = event, operation, row['response_kind'], row['operand']
                positive(row['seconds'])
                need(abs(row['seconds'] - (ns - sends[operation]) / 1e9) < .01,
                     'Command duration disagrees with independently recorded timeline')
                if operation.startswith('step-'):
                    durations.append(row['seconds'])
                    completion_windows.append([ns])
            else:
                observed = event, operation, row['requested_seconds'], row['buffered_hex']
            need(observed == want, 'Frame/CRC/token/seed/temperature/replay/CLEAR differs')
        need(durations == case['step_seconds'] and len(durations) == len(arrivals) == 128, 'Step timing count differs')
        equal(case['first_step_seconds'], durations[0])
        equal(case['cached_command_tokens_per_second'], 127 / sum(durations[1:]))
        elapsed = case['reply_elapsed_seconds']
        need(len(elapsed) == 128 and elapsed[0] == 0, 'Reply timing count differs')
        # The runner samples reply completion after the operation record has
        # been flushed/fsynced, before sending the next command. The raw-frame
        # observer runs earlier. Use these observed brackets rather than assume
        # a fixed logging delay, which can grow under host scheduling pressure.
        need(len(completion_windows) == 128 and all(len(w) == 2 for w in completion_windows),
             'Missing reply completion bracket')
        first_low, first_high = completion_windows[0]
        for actual, (low, high) in zip(elapsed[1:], completion_windows[1:]):
            positive(actual)
            need((low - first_high) / 1e9 - 1e-6 <= actual <= (high - first_low) / 1e9 + 1e-6,
                 'Reply timeline differs from recorded completion brackets')
        need(all(a < b for a, b in zip(elapsed, elapsed[1:])), 'Reply timeline not increasing')
        equal(case['cached_stream_tokens_per_second'], 127 / elapsed[-1])
    return dict(passed=True, cases=8, outputs_compared=1024, positive_temperature_outputs=768,
                full_model_replayed=False, hardware_access=False,
                scope='Archived wire/reference identities and timing, not new model execution or physical attestation.')


def check(package=ROOT):
    package = Path(package)
    raw = (package / RECORD).read_bytes()
    result = validate(json.loads(raw))
    need(sha(raw) == ARCHIVE_SHA, 'Archive bytes changed')
    for name, digest in (
        ('prebuilt/seeded-sampling/project/impl/pnr/shared_product.fs', IMAGE_SHA),
        ('assets/board1-real-semantic-image2048.bin', MODEL_SHA)):
        need(sha((package / name).read_bytes()) == digest, 'Changed image/model asset')
    inputs = json.loads((package / 'host-app/hardware-inputs-seeded-sampling.json').read_text())
    need(len(inputs) == 91 and sha(canonical(inputs)) == INPUTS_SHA, 'Source inventory changed')
    for name, digest in inputs.items():
        path = package / 'variants/seeded-sampling/hardware' / name
        if name.startswith('project/official/') and not path.exists(): continue
        need(path.is_file() and not path.is_symlink() and sha(path.read_bytes()) == digest, 'Source file changed')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', type=Path, default=ROOT)
    print(json.dumps(check(parser.parse_args().package), indent=2, sort_keys=True))
