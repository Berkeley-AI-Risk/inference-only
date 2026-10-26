"""Exact recorded-protocol replay and command plan; offline only."""
import copy
KNOWN = [200, 15, 103, 157]

def require(ok, message):
    if not ok:
        raise ValueError(message)

def commands(prompt, generated):
    require(1 <= len(prompt) <= 2048 and 1 <= len(generated)
            and len(prompt) + len(generated) <= 2049, 'Illegal case dimensions.')
    require(all(type(token) is int and 0 <= token < 4019 for token in prompt + generated),
            'Illegal token.')
    rows = []

    def add(label, operation, operand=0, kind=None, token=0, timeout=10):
        if kind is None:
            kind = {'append': 0x80, 'step': 0x81, 'clear': 0x82}[operation]
        rows.append({'label': label, 'operation': operation, 'operand': operand,
                     'expected_kind': kind, 'expected_token': token, 'timeout': timeout})

    def known(label):
        add(label + '-clear', 'clear')
        add(label + '-empty-step', 'step', kind=0xc1)
        add(label + '-append', 'append', operand=378)
        for index, token in enumerate(KNOWN):
            add(label + f'-step-{index}', 'step', token=token)

    known('before')
    add('long-clear', 'clear')
    for index, token in enumerate(prompt):
        add(f'prompt-{index}', 'append', operand=token)
    tape = len(prompt)
    for index, token in enumerate(generated):
        if tape == 2048:
            add('input-limit-append-rejected', 'append', operand=378, kind=0xc0)
        add(f'long-step-{index}', 'step', token=token, timeout=14400 if index == 0 else 60)
        tape += 1
    if tape == 2049:
        add('final-slot-append-rejected', 'append', operand=378, kind=0xc0)
        add('final-slot-step-rejected', 'step', kind=0xc1)
    # Two clean replays after the long case check state reuse without reloading.
    known('after-1')
    known('after-2')
    add('final-clear', 'clear')
    return rows

def frame(magic, kind, token):
    body = bytes([magic, kind, token & 255, token >> 8])
    crc = 0
    for byte in body:
        crc ^= byte
        for _ in range(8):
            crc = ((crc << 1) ^ (7 if crc & 128 else 0)) & 255
    return body + bytes([crc])

def replay(plan, events):
    index = 0
    active = None
    received = bytearray()
    sent, decoded = False, False
    completed = []
    opened = False
    previous_clock = -1
    for event in events:
        require(event['monotonic_ns'] >= previous_clock, 'Log clock is not monotonic.')
        previous_clock = event['monotonic_ns']
        kind = event['event']
        if kind == 'open_intent':
            require(not opened and not completed and active is None, 'Repeated/late session opening.')
            opened = True
        elif kind == 'command_intent':
            require(opened and active is None and index < len(plan), 'Unexpected command intent.')
            active = plan[index]
            opcode = {'append': 0, 'step': 1, 'clear': 2}[active['operation']]
            require(event['label'] == active['label']
                    and event['hex'] == frame(0xa5, opcode, active['operand']).hex(), 'Request differs.')
            sent, decoded = False, False
            received = bytearray()
        elif kind == 'raw_chunk':
            require(active is not None, 'Unsolicited UART bytes.')
            data = bytes.fromhex(event['hex'])
            require(data, 'Empty raw chunk.')
            if event['direction'] == 'tx':
                opcode = {'append': 0, 'step': 1, 'clear': 2}[active['operation']]
                require(not sent and data == frame(0xa5, opcode, active['operand']), 'Raw request differs.')
                sent = True
            else:
                require(event['direction'] == 'rx' and sent and not decoded, 'Unexpected received bytes.')
                received.extend(data)
                require(len(received) <= 5, 'Extra response bytes.')
        elif kind == 'decoded':
            require(active is not None and sent and not decoded, 'Unexpected decoded event.')
            expected = frame(0x5a, active['expected_kind'], active['expected_token'])
            require(bytes(received) == expected and event['frame_hex'] == expected.hex()
                    and event['kind'] == 'normal' and event['response'] == active['expected_kind']
                    and event['token'] == active['expected_token'], 'Decoded reply differs from raw expected frame.')
            decoded = True
        elif kind == 'command_result':
            require(active is not None and decoded, 'Completion without decoded bytes.')
            require(all(event[key] == value for key, value in active.items()), 'Completed command differs.')
            expected = frame(0x5a, active['expected_kind'], active['expected_token'])
            require(event['received'] == {'kind': 'normal', 'response': active['expected_kind'],
                    'token': active['expected_token'], 'frame_hex': expected.hex()}, 'Recorded response differs.')
            require(0 <= event['seconds'] <= active['timeout'] + 1, 'Command duration exceeds bound.')
            completed.append(event)
            index += 1
            active = None
        elif kind == 'waiting':
            require(active is not None and sent and not decoded and event['label'] == active['label'],
                    'Unexpected waiting event.')
        else:
            raise ValueError('Unexpected event: ' + kind)
    require(opened and active is None and index == len(plan), 'Incomplete transcript.')
    require(completed[-1]['label'] == 'final-clear' and completed[-1]['received']['response'] == 0x82,
            'No final CLEAR acknowledgment.')
    steps = [row for row in completed if row['label'].startswith('long-step-')]
    cached = [row['seconds'] for row in steps[1:]]
    stream_seconds = ((steps[-1]['monotonic_ns'] - steps[0]['monotonic_ns']) / 1e9
                      if len(steps) > 1 else None)
    first_append = next(row['monotonic_ns'] for row in events
                        if row['event'] == 'command_intent' and row['label'] == 'prompt-0')
    first_step = next(row['monotonic_ns'] for row in events
                      if row['event'] == 'command_intent' and row['label'] == 'long-step-0')
    return {'passed': True, 'commands': len(completed),
            'all_generated_tokens': sum(row['received']['response'] == 0x81 for row in completed),
            'clear_acknowledgments': sum(row['received']['response'] == 0x82 for row in completed),
            'expected_rejections': sum(row['received']['response'] in (0xc0, 0xc1) for row in completed),
            'long_generated_tokens': [row['received']['token'] for row in steps],
            'first_step_seconds': steps[0]['seconds'], 'cached_decode_seconds': cached,
            'prompt_upload_until_first_step_seconds': (first_step - first_append) / 1e9,
            'first_append_to_first_reply_seconds': (steps[0]['monotonic_ns'] - first_append) / 1e9,
            'cached_command_tokens_per_second': len(cached) / sum(cached) if cached else None,
            'cached_stream_tokens_per_second': (len(steps) - 1) / stream_seconds if stream_seconds else None,
            'final_clear_acknowledged': True}

def negative_controls(plan, events):
    variants = []
    changed = copy.deepcopy(events)
    next(row for row in changed if row['event'] == 'raw_chunk' and row['direction'] == 'rx')['hex'] = '5a82000000'
    variants.append(changed)
    changed = copy.deepcopy(events)
    changed.pop(next(i for i, row in enumerate(changed) if row['event'] == 'raw_chunk' and row['direction'] == 'rx'))
    variants.append(changed)
    variants.append(events[:-1])
    changed = copy.deepcopy(events)
    row = next(row for row in changed if row['event'] == 'command_result' and row['operation'] == 'step')
    row['received']['response'] ^= 1
    variants.append(changed)
    for changed in variants:
        try:
            replay(plan, changed)
        except ValueError:
            pass
        else:
            raise ValueError('Auditor accepted a negative control.')
    return len(variants)
