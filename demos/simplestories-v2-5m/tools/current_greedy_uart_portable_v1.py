"""Pure byte-input replay of a complete current greedy UART campaign.

The caller resolves portable capsule files, validates its closed selection policy
and source graph, and supplies the original unmodified evidence bytes. This module
performs no file, import, serial, process, browser, or parent-benchmark operations.
It preserves original path strings as provenance and verifies supplied byte pins.
The five replay definitions below are source-identical to frozen reviewer0669.
"""
import hashlib
import json
import math
import re

REVIEWER_SHA256 = '0669e12cefa440501b4d1597053882ec7026227e2776f1e70f564b7a6004745e'
PLAN_SHA256 = 'f387b4f4b2f6f46f923266a9cd71591b103fb7a0f5be883480b4419e000f0eba'
MODEL_SHA256 = 'cad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0'
SUITES = ['registration', 'matched128', 'context', 'cancel_recovery']
VARIANTS = ('baseline', 'kv-protected', 'encrypted-memory')
GOLDEN_PINS = {
    'around128': {'bytes': 11047, 'sha256': 'f517af7880aa9160379c71fb1804a234a40e509051b4f629cdea7f78b0e73e6e'},
    'prefix128': {'bytes': 12127, 'sha256': 'e8e13774ee692ce2a7c233f8553508194f1a677436f2f4e454879a8afc6dba6a'},
    'prefix512': {'bytes': 5455, 'sha256': 'e27b7312917709dbc18f2b897da4cf3ac88e2a9188fdec2797d949a280f502f5'},
    'prefix2047': {'bytes': 18600, 'sha256': '76206692eb418e29428166cdd0d3f64b3e8a3f25103fefb9159a54dd05da2271'},
    'prefix2048': {'bytes': 18529, 'sha256': '1d85e9b9c7b0116862a3de3a20cde80b1f3534069bdf04a4feff53ab82fefcca'},
}


def need(ok, message):
    if not ok:
        raise ValueError(message)

def frame(magic, kind, token=0):
    body = bytes((magic, kind, token & 255, token >> 8)); crc = 0
    for value in body:
        crc ^= value
        for _ in range(8):
            crc = ((crc << 1) ^ (7 if crc & 128 else 0)) & 255
    return body + bytes((crc,))

class Trace:
    def __init__(self, rows, sequenced=True):
        self.rows = rows; self.cursor = 0; self.pending = bytearray(); self.rx_ns = None
        previous = -1
        for i, row in enumerate(rows, 1):
            need(type(row['monotonic_ns']) is int and row['monotonic_ns'] >= previous, 'Reordered raw timeline')
            if sequenced:
                need(row['sequence'] == i, 'Missing, duplicate or reordered raw sequence')
            previous = row['monotonic_ns']

    def take(self, event):
        need(self.cursor < len(self.rows) and self.rows[self.cursor]['event'] == event,
             'Raw ownership/order differs at event ' + str(self.cursor) + ': expected ' + event)
        value = self.rows[self.cursor]; self.cursor += 1; return value

    def send(self, operation, operand, label):
        need(not self.pending, 'Unowned buffered bytes before command')
        request = frame(0xa5, {'append': 0, 'step': 1, 'clear': 2}[operation], operand)
        intent = self.take('command_intent'); sent = self.take('raw_chunk')
        need(intent['label'] == label and bytes.fromhex(intent['hex']) == request
             and sent['direction'] == 'tx' and bytes.fromhex(sent['hex']) == request,
             'Request intent/TX/frame CRC differs; no SETTINGS or extra commands permitted')
        return intent, sent

    def receive(self, maximum_pending=5):
        while len(self.pending) < 5:
            row = self.take('raw_chunk'); chunk = bytes.fromhex(row['hex'])
            need(row['direction'] == 'rx' and 0 < len(chunk) <= maximum_pending - len(self.pending),
                 'Noise, empty/extra response bytes or unowned TX')
            self.pending.extend(chunk); self.rx_ns = row['monotonic_ns']
        response = bytes(self.pending[:5]); del self.pending[:5]
        need(response[0] == 0x5a and response == frame(0x5a, response[1], response[2] | response[3] << 8),
             'Bad actual response frame/CRC')
        decoded = self.take('decoded')
        token = response[2] | response[3] << 8
        need(decoded['kind'] == 'normal' and decoded['response'] == response[1]
             and decoded['token'] == token and bytes.fromhex(decoded['frame_hex']) == response,
             'Decoded reply differs from actual raw bytes')
        return response[1], token, self.rx_ns

    def normal(self, row, old=False):
        operation = row['operation']; operand = row['operand']
        intent, sent = self.send(operation, operand, row['label'])
        kind, token, rx_ns = self.receive()
        need(not self.pending and kind == row['expected_kind'] and token == row['expected_token'],
             'Actual normal reply differs from independent planned token/result')
        completed = self.take('command_result'); seconds = completed['seconds']
        deadline = row['timeout'] if old else row['timeout_seconds']
        need(type(seconds) in (int, float) and math.isfinite(seconds) and 0 < seconds <= deadline + 1,
             'Invalid/over-deadline command duration')
        if old:
            need(all(completed[key] == value for key, value in row.items())
                 and completed['received'] == dict(kind='normal', response=kind, token=token,
                                                   frame_hex=frame(0x5a, kind, token).hex()),
                 'Original parent command result differs from actual raw/plan')
            result = completed
        else:
            result = dict(operation=operation, operand=operand, response=kind, token=token,
                          seconds=seconds, metric=row['metric'], label=row['label'])
            need(all(completed[key] == value for key, value in result.items()),
                 'Closed case command result differs from actual raw/plan')
        return result, dict(rx_ns=rx_ns, completed_ns=completed['monotonic_ns'], seconds=seconds,
                            token=token, label=row['label'])

    def quiet(self, seconds):
        need(not self.pending, 'Buffered bytes before quiet interval')
        row = self.take('quiet')
        need(row['seconds'] == seconds and row['bytes_received'] == 0, 'Unexpected bytes or wrong quiet interval')

    def cancel(self, row):
        _, sent = self.send('step', 0, 'cancel-step')
        clear, _ = self.send('clear', 0, 'cancel-clear')
        need((clear['monotonic_ns'] - sent['monotonic_ns']) / 1e9 + 1e-6 >= row['delay_seconds'],
             'CLEAR was sent before its declared cancellation delay')
        completed = []; kind, token, _ = self.receive(10)
        if kind == 0x81:
            need(token == row['expected_first_token'], 'Wrong STEP result before CLEAR ACK')
            completed.append(token); kind, token, _ = self.receive(10)
        need(kind == 0x82 and token == 0 and not self.pending, 'CLEAR ACK missing, duplicated or leaves extra bytes')
        result = self.take('step_clear_result'); seconds = result['clear_ack_seconds']
        need(result['completed_before_clear'] == completed
             and result['requested_delay_seconds'] == row['delay_seconds']
             and type(seconds) in (int, float) and math.isfinite(seconds)
             and 0 < seconds <= row['timeout_seconds'] + 1, 'Cancellation result/timing differs')
        return dict(completed_before_clear=completed, clear_ack_seconds=seconds,
                    requested_delay_seconds=row['delay_seconds'])

def replay_cases(rows, selected):
    trace = Trace(rows); trace.quiet(0.1); cases = []; timings = {}
    for suite, case in selected:
        started = trace.take('case_started')
        need(started['suite'] == suite and started['name'] == case['name'], 'Case start/order differs')
        commands = []; cancellations = []; measured = []
        for row in case['rows']:
            if row['type'] == 'command':
                result, timing = trace.normal(row); commands.append(result)
                if row['metric']:
                    measured.append(timing)
            elif row['type'] == 'quiet':
                trace.quiet(row['seconds'])
            elif row['type'] == 'cancel':
                cancellations.append(trace.cancel(row))
            else:
                raise ValueError('Unknown frozen plan row')
        finished = trace.take('case_finished')
        need(finished['suite'] == suite and finished['name'] == case['name'], 'Case finish/order differs')
        generated = [item['token'] for item in measured]
        need(generated == case['expected_generated_tokens'], 'Actual raw main token census differs from independent golden')
        cases.append(dict(name=case['name'], passed=True, generated_tokens=generated,
            step_seconds=[item['seconds'] for item in measured], commands=commands,
            cancellations=cancellations, no_retries=True, final_clear_acknowledged=True, suite=suite))
        timings[case['name']] = measured
    need(trace.cursor == len(rows) and not trace.pending, 'Unexpected trailing raw event or response bytes')
    return cases, timings

def rates(trials):
    need(len(trials) == 2 and all(len(trial) == 128 for trial in trials), 'Two complete128-output trials required')
    seconds = sum(sum(row['seconds'] for row in trial[1:]) for trial in trials)
    rx = sum((trial[-1]['rx_ns'] - trial[0]['rx_ns']) / 1e9 for trial in trials)
    completed = sum((trial[-1]['completed_ns'] - trial[0]['completed_ns']) / 1e9 for trial in trials)
    need(min(seconds, rx, completed) > 0, 'Nonpositive measured interval')
    return dict(cached_outputs=254, cached_command_seconds=seconds,
        cached_command_tokens_per_second=254 / seconds,
        summed_raw_rx_first_to_last_seconds=rx, raw_rx_stream_tokens_per_second=254 / rx,
        summed_command_result_first_to_last_seconds=completed,
        command_result_stream_tokens_per_second=254 / completed,
        first_step_and_prompt_upload_excluded=True)


def byte_identity(data):
    need(type(data) is bytes and 0 < len(data) <= 128 * 1024 * 1024,
         'Evidence must be nonempty bounded bytes')
    return dict(bytes=len(data), sha256=hashlib.sha256(data).hexdigest())


def object_pairs(pairs):
    result = {}
    for key, value in pairs:
        need(key not in result, 'Duplicate JSON key')
        result[key] = value
    return result


def json_object(data):
    byte_identity(data)
    def bad_constant(value):
        raise ValueError('Nonfinite JSON constant: ' + value)
    value = json.loads(data, object_pairs_hook=object_pairs, parse_constant=bad_constant)
    need(type(value) is dict, 'Evidence JSON object required')
    return value


def supplied_pin(row, data):
    need(type(row) is dict and set(row) == {'path', 'bytes', 'sha256'}
         and type(row['path']) is str and bool(row['path'])
         and type(row['bytes']) is int
         and {key: row[key] for key in ('bytes', 'sha256')} == byte_identity(data),
         'Original evidence pin does not match supplied bytes')
    return dict(row)


def independent_goldens(frozen, supplied):
    need(type(supplied) is dict and set(supplied) == set(GOLDEN_PINS),
         'All five independently pinned T0 golden byte inputs required')
    decoded = {}
    for family, expected in GOLDEN_PINS.items():
        need(byte_identity(supplied[family]) == expected, 'Independent T0 golden bytes changed')
        golden = json_object(supplied[family])
        need(golden['temperature'] == '0' and golden['stop_at_eos'] is False
             and golden['model_image_sha256'] == MODEL_SHA256,
             'Independent golden model/generation mode differs')
        decoded[family] = golden
    for suite in SUITES[:3]:
        for case in frozen['suites'][suite]:
            family = 'around128' if suite in ('registration', 'matched128') else case['name']
            golden = decoded[family]
            count = len(case['expected_generated_tokens'])
            need(case['prompt_tokens'] == golden['prompt_tokens']
                 and case['expected_generated_tokens'] == golden['generated_tokens'][:count],
                 'Frozen prompt/main outputs differ from independent T0 golden')
    for case in frozen['suites']['cancel_recovery']:
        need(case['expected_generated_tokens'] == [] and case['prompt_tokens'] == [378],
             'Cancellation main census changed')
        for row in case['rows']:
            if row['type'] == 'cancel':
                need(row['expected_first_token'] == decoded['around128']['generated_tokens'][0],
                     'Cancellation race token differs from independent golden')
        need([row['expected_token'] for row in case['rows'] if row.get('expected_kind') == 0x81]
             == decoded['around128']['generated_tokens'][:2],
             'Post-cancellation replay differs from independent golden')


def validate_campaign(*, finished_bytes, plan_bytes, raw_uart_bytes, frozen_plan_bytes,
                      goldens, variant, image_sha256):
    """Replay bytes already resolved by a portable capsule checker.

    The caller separately validates the capsule's selection policy, native/model
    closure, source graph, and original per-case receipt files. No original path
    is interpreted here, and no supplied or embedded provenance field is edited.
    """
    need(variant in VARIANTS and type(image_sha256) is str
         and re.fullmatch('[0-9a-f]{64}', image_sha256) is not None,
         'Explicit known variant and image SHA256 required')
    finished = json_object(finished_bytes)
    plan = json_object(plan_bytes)
    need(byte_identity(frozen_plan_bytes)['sha256'] == PLAN_SHA256,
         'Frozen independently reviewed greedy command plan differs')
    frozen = json_object(frozen_plan_bytes)
    need(frozen['schema'] == 'greedy-board-command-plans-v1'
         and frozen['hardware_access'] is False and frozen['settings_commands'] == 0,
         'Wrong frozen greedy command-plan scope')
    independent_goldens(frozen, goldens)
    need(plan['schema'] == 'greedy-selected-physical-plan-v1'
         and plan['suites'] == SUITES and plan['selected_cases'] == frozen['suites']
         and plan['hardware_access'] is True and plan['flash_modified'] is False
         and plan['automatic_retry'] is False and plan['variant'] == variant,
         'Original physical plan scope, cases, or variant differs')
    image = plan['image']
    need(type(image) is dict and set(image) == {'path', 'bytes', 'sha256'}
         and type(image['path']) is str and bool(image['path'])
         and type(image['bytes']) is int and image['bytes'] > 0
         and image['sha256'] == image_sha256,
         'Original physical plan image differs from selected capsule image')
    original_plan = supplied_pin(finished['plan'], plan_bytes)
    original_raw = supplied_pin(finished['raw_uart'], raw_uart_bytes)
    rows = [json_object(line) for line in raw_uart_bytes.splitlines()]
    need(rows and all(type(row.get('sequence')) is int and type(row.get('event')) is str
                      for row in rows), 'Raw events require integer sequence and event name')
    selected = [(suite, case) for suite in SUITES for case in frozen['suites'][suite]]
    need(len(selected) == 10, 'Exactly ten frozen cases required')
    cases, timings = replay_cases(rows, selected)
    main = sum(len(case['generated_tokens']) for case in cases)
    need(finished['schema'] == 'greedy-selected-physical-campaign-v1'
         and finished['passed'] is True and finished['complete_campaign'] is True
         and finished['case_count'] == 10 and finished['cases'] == cases
         and main == finished['main_reference_outputs'] == 395
         and finished['variant'] == variant and finished['image'] == image
         and finished['suites'] == SUITES
         and finished['physical_fpga'] is True and finished['usb_released'] is True
         and finished['source_inputs_unchanged'] is True
         and finished['final_clear_acknowledged'] is True
         and finished['flash_modified'] is False and finished['automatic_retry'] is False
         and finished['automatic_recovery'] is False,
         'Complete FINISHED record disagrees with actual raw replay or required scope')
    current = rates([timings['matched128-trial1'], timings['matched128-trial2']])
    summary = finished['matched128']
    need(summary['cached_outputs'] == current['cached_outputs'] == 254
         and summary['cached_step_seconds'] == current['cached_command_seconds']
         and summary['cached_tokens_per_second'] == current['cached_command_tokens_per_second']
         and summary['first_step_excluded'] is True
         and summary['prompt_upload_excluded'] is True,
         'FINISHED matched timing summary disagrees with raw command/RX replay')
    expected_normal_steps = sum(row.get('type') == 'command' and row.get('expected_kind') == 0x81
                                for _, case in selected for row in case['rows'])
    cancellation_steps = sum(len(item['completed_before_clear']) for case in cases
                             for item in case['cancellations'])
    actual_steps = sum(row['event'] == 'decoded' and row['response'] == 0x81 for row in rows)
    need(expected_normal_steps == 413 and 0 <= cancellation_steps <= 3
         and actual_steps == expected_normal_steps + cancellation_steps,
         'Actual successful STEP reply census differs from mandatory plus cancellation replies')
    return dict(schema='greedy-current-portable-byte-uart-replay-v1', passed=True,
        complete_campaign=True, variant=variant, image=dict(image),
        finished=byte_identity(finished_bytes), original_plan=original_plan,
        original_raw_uart=original_raw, frozen_command_plan=byte_identity(frozen_plan_bytes),
        independent_T0_goldens={key: dict(value) for key, value in GOLDEN_PINS.items()},
        case_count=len(cases), cases=cases, main_reference_outputs=main,
        consumed_raw_bytes=len(raw_uart_bytes), consumed_raw_events=len(rows),
        mandatory_successful_STEP_replies=expected_normal_steps,
        cancellation_race_STEP_replies=cancellation_steps,
        actual_raw_decoded_STEP_replies=actual_steps, settings_commands=0,
        matched128=current, first_step_seconds={name: values[0]['seconds']
            for name, values in timings.items() if values},
        original_reviewer_source_sha256=REVIEWER_SHA256,
        all_supplied_raw_bytes_and_FINISHED_case_results_replayed=True,
        source_input_file_hashes_rechecked_here=False,
        policy_model_native_closure_rechecked_here=False,
        original_per_case_receipt_files_rechecked_here=False,
        configuration_independently_attested=False,
        hardware_access=False, browser_or_server_access=False,
        parent_benchmark_files_accessed=False, release_qualified=False,
        cancellation_scope='At most one exact expected STEP reply before each CLEAR ACK; acceptance-time ordering is not independently established.',
        initial_stock_driver_buffer_flush_outside_strict_trace=True,
        scope='Pure replay of supplied original bytes, CRC, request/reply ownership, cancellation, independent T0 outputs, CLEAR, FINISHED cases and timing. The caller separately checks portable selection/source closure. No new hardware, configuration, browser, or release qualification.')
