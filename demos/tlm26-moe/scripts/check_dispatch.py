"""Check one complete MoE dispatch trace against routes and captured UART frames."""
if not __debug__:
    raise SystemExit('Assertion checks are required; run without -O or -OO. No verification performed.')

import argparse
import hashlib
import json
from pathlib import Path


class CheckError(ValueError):
    """A recorded input or the trace differs from the declared finite case."""


def need(condition, message):
    if not condition:
        raise CheckError(message)


def frame(encoded, magic):
    """Decode the captured five-byte frame, including its CRC-8 check."""
    try:
        data = bytes.fromhex(encoded)
    except (TypeError, ValueError) as error:
        raise CheckError('Malformed captured UART frame') from error
    need(len(data) == 5 and data[0] == magic, 'Wrong captured UART frame length or magic')
    crc = 0
    for byte in data[:4]:
        crc ^= byte
        for _ in range(8):
            crc = ((crc << 1) ^ (7 if crc & 128 else 0)) & 255
    need(data[4] == crc, 'Captured UART frame CRC differs')
    return [data[1], int.from_bytes(data[2:4], 'little')]


def check(text, expected, physical):
    """Verify the complete chronological trace; perform no model or device work.

    ``expected`` contains the fixed 340 reference dispatches. ``physical`` is the
    published physical.json receipt; its first 36 honest frames are the two
    histories. Its later cancellation/recovery frames are outside this replay.
    Source and runtime-file hashes are checked by the reproduction entry point.
    """
    need(isinstance(expected, dict) and isinstance(physical, dict), 'Expected JSON objects')
    for reference_key, physical_value in (
        ('bitstream_sha256', physical.get('bitstream_sha256')),
        ('source_checkpoint_sha256', physical.get('source_checkpoint_sha256')),
        ('staged_model_sha256', physical.get('boot', {}).get('honest', {}).get('sha256')),
    ):
        value = expected.get(reference_key)
        need(isinstance(value, str) and len(value) == 64 and value == physical_value,
             'Reference/physical identity differs: ' + reference_key)

    records = expected.get('expected_dispatches')
    need(isinstance(records, list) and len(records) == 340, 'Expected exactly 340 reference dispatches')
    captured = physical.get('honest')
    need(isinstance(captured, list) and len(captured) >= 36, 'Expected at least 36 captured honest UART frames')
    wire = []
    for row in captured[:36]:
        need(isinstance(row, dict) and 'tx' in row and 'rx' in row, 'Missing captured UART frame')
        wire.append(frame(row['tx'], 0xA5) + frame(row['rx'], 0x5A))

    lines = text.splitlines()
    index = 0
    previous_reads = 0
    replies = []
    dispatches = []

    def take():
        nonlocal index
        need(index < len(lines), 'Trace truncated before line ' + str(index + 1))
        line = lines[index]
        index += 1
        return line

    def exact(wanted):
        line = take()
        need(line == wanted, f'Line {index}: expected {wanted!r}, got {line!r}')

    def reply(wanted):
        nonlocal previous_reads
        line = take()
        fields = line.split()
        need(len(fields) == 6 and all(word.isascii() and word.isdecimal() for word in fields),
             f'Line {index}: expected six unsigned UART fields')
        fields = [int(word) for word in fields]
        need(fields[:4] == wanted, f'Line {index}: UART reply differs from captured frame')
        need(fields[4] > 0, f'Line {index}: UART cycle count is not positive')
        need(fields[5] >= previous_reads, f'Line {index}: cumulative DDR reads decreased')
        previous_reads = fields[5]
        replies.append(fields)

    exact('boot_writes 98304 page_acks 768 changed_bytes 0')
    for history in range(2):
        base = history * 18
        need(wire[base] == [2, 0, 130, 0], 'Captured history must begin with CLEAR')
        exact(f'MOE_CLEAR {history}')
        reply(wire[base])
        for position in range(17):
            wanted_reply = wire[base + position + 1]
            if position < 5:
                need(wanted_reply[0] == 0 and wanted_reply[2:] == [128, 0],
                     'Captured prefix must contain five APPEND replies')
                token = wanted_reply[1]
            else:
                need(wanted_reply[:3] == [1, 0, 129],
                     'Captured continuation must contain twelve STEP replies')
                token = wanted_reply[3]
            need(0 <= token < 512, 'Captured token is outside the fixed vocabulary')
            for layer in range(5):
                pair = []
                for rank in range(2):
                    record = records[len(dispatches)]
                    need(isinstance(record, list) and len(record) == 7
                         and all(type(value) is int for value in record),
                         'Malformed reference dispatch ' + str(len(dispatches)))
                    need(record[:5] == [history, position, token, layer, rank],
                         'Reference history/token/layer/rank order differs')
                    expert, address = record[5:]
                    need(0 <= expert < 8, 'Reference expert is outside the fixed architecture')
                    need(address == 32832 + layer * 307840 + 12928 + expert * 36864,
                         'Reference W1 address differs from the fixed layout')
                    pair.append(expert)
                    suffix = ' '.join(map(str, record))
                    exact('MOE_START ' + suffix)
                    exact('MOE_WEIGHT ' + suffix)
                    dispatches.append(record)
                need(pair[0] != pair[1], 'Top-two reference repeats the same expert')
            reply(wanted_reply)

    need(index == len(lines), f'Extra trace data at line {index + 1}')
    counts = [[sum(row[3] == layer and row[5] == expert for row in dispatches)
               for expert in range(8)] for layer in range(5)]
    need(counts == expected.get('consumed_tokens_34_layer_by_expert_counts'),
         'Reference expert totals differ from the ordered dispatches')
    return {
        'passed': True,
        'trace_lines_checked': index,
        'strictly_ordered_launch_and_first_weight_pairs': len(dispatches),
        'verified_launches': len(dispatches),
        'verified_first_weight_acceptances': len(dispatches),
        'verified_token_commands': 34,
        'verified_UART_replies': len(replies),
        'generated_tokens_matching_board': 24,
        'CLEAR_markers': 2,
        'full_UART_rows': replies,
        'per_layer_expert_counts': counts,
        'distinct_experts_per_layer': [sum(count > 0 for count in row) for row in counts],
        'physical_followup_rows_outside_replay': len(captured) - 36,
        'board_routing_directly_observed': False,
        'scope': 'Finite local RTL dispatch and first-weight evidence for two captured histories; '
                 'not every weight access, direct board routing, formal correctness or physical speed.',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--trace', required=True, type=Path)
    parser.add_argument('--expected', required=True, type=Path)
    parser.add_argument('--physical', required=True, type=Path)
    parser.add_argument('--output', type=Path, help='New JSON result path; existing files are refused')
    args = parser.parse_args()
    try:
        raw = args.trace.read_bytes()
        result = check(raw.decode('utf-8'), json.loads(args.expected.read_bytes()),
                       json.loads(args.physical.read_bytes()))
        result['stdout'] = {'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()}
        rendered = json.dumps(result, indent=2, sort_keys=True) + '\n'
        if args.output:
            with args.output.open('x') as output:
                output.write(rendered)
        print(rendered, end='')
    except (CheckError, OSError, UnicodeError, json.JSONDecodeError) as error:
        parser.exit(1, f'Dispatch check failed: {error}\n')


if __name__ == '__main__':
    main()
