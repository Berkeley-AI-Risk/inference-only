#!/usr/bin/env python3
"""Recompute one common FPGA generation benchmark from immutable captures.

Standard library only. No hardware, network, model inference or file writes.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path, PurePosixPath

SELECTION = 'benchmarks/fpga-speed/selection.json'
RESULTS = 'benchmarks/fpga-speed/results.json'
BOUNDARY = 'generation_loop_validated_reply'
START, END = '<!-- COMMON-FPGA-SPEED:START -->', '<!-- COMMON-FPGA-SPEED:END -->'


def need(value, message):
    if not value:
        raise ValueError(message)


def positive(value):
    need(type(value) in (int, float) and math.isfinite(value) and value > 0, 'Invalid positive timing')
    return value


def trial(prompt, tokens, expected, arrivals, cached_commands, first_step,
          identity, *, decoding='greedy', temperature=0, clear_before=True,
          stop_at_eos=False, boundary=BOUNDARY, feedback_dependent=True, capture_sha256=None):
    need(len(prompt) == 1 and all(type(x) is int and x >= 0 for x in prompt), 'Expected one input token')
    need(len(tokens) == len(expected) == 128, 'Expected exactly 128 outputs and reference IDs')
    need(all(type(x) is int and x >= 0 for x in tokens + expected), 'Invalid token IDs')
    need(tokens == expected, 'Recorded outputs differ from numerical reference IDs')
    need(decoding == 'greedy' and type(temperature) in (int, float) and temperature == 0,
         'Common headline requires greedy temperature 0')
    need(clear_before is True and stop_at_eos is False and feedback_dependent is True,
         'CLEAR, feedback or full-output policy changed')
    need(boundary == BOUNDARY, 'Different timestamp boundary cannot be substituted')
    need(len(arrivals) == 128 and len(cached_commands) == 127, 'Missing receipt or command timings')
    need(all(type(t) in (int, float) and math.isfinite(t) and t >= 0 for t in arrivals), 'Invalid reply timestamps')
    need(all(b > a for a, b in zip(arrivals, arrivals[1:])), 'Nonmonotonic reply timestamps')
    elapsed = arrivals[-1] - arrivals[0]
    command_time = math.fsum(positive(x) for x in cached_commands)
    need(elapsed + 1e-6 >= command_time, 'Reply interval shorter than counted command durations')
    need(isinstance(identity, dict) and identity, 'Missing model/image/clock identity')
    if capture_sha256 is not None:
        need(isinstance(capture_sha256, str) and len(capture_sha256) == 64
             and all(x in '0123456789abcdef' for x in capture_sha256), 'Invalid capture identity')
    return {'capture_sha256': capture_sha256, 'prompt_tokens': prompt, 'generated_outputs': 128, 'cached_outputs': 127,
            'cached_host_seconds': positive(elapsed), 'cached_command_seconds': command_time,
            'first_step_seconds': positive(first_step), 'identity': identity, 'timestamp_boundary': boundary,
            'greedy': True, 'clear_before': True, 'stop_at_eos': False}


def pool(trials):
    need(len(trials) == 2, 'Exactly two complete trials are required')
    need(trials[0]['identity'] == trials[1]['identity'], 'Mixed image/model/clock identities')
    need(trials[0]['prompt_tokens'] == trials[1]['prompt_tokens'], 'Mixed prompt IDs')
    need(all(x['timestamp_boundary'] == BOUNDARY and x['cached_outputs'] == 127
             and x['generated_outputs'] == 128 for x in trials), 'Mixed boundaries or output counts')
    captures = [x.get('capture_sha256') for x in trials]
    need(not all(captures) or captures[0] != captures[1], 'A capture cannot count twice')
    need(all(x['greedy'] and x['clear_before'] and x['stop_at_eos'] is False for x in trials), 'Changed trial policy')
    wall = math.fsum(positive(x['cached_host_seconds']) for x in trials)
    command = math.fsum(x['cached_command_seconds'] for x in trials)
    return {'counted_cached_outputs': 254, 'cached_host_seconds': wall,
            'cached_tokens_per_second': 254 / wall,
            'command_only_diagnostic_tokens_per_second': 254 / command,
            'first_step_seconds': [x['first_step_seconds'] for x in trials]}


def read_sources(root, selection):
    result = {}
    for name, expected in selection['sources'].items():
        path = PurePosixPath(name)
        need(not path.is_absolute() and '..' not in path.parts and str(path) == name, 'Unsafe source path')
        raw = (root / name).read_bytes()
        need({'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()} == expected,
             'Changed benchmark source: ' + name)
        result[name] = json.loads(raw)
    return result


def selected_trials(row, sources, reference):
    need(len(row['cases']) == len(set(row['cases'])), 'A selected case cannot count twice')
    kind = row['format']
    if kind == 'pending':
        need(not row['cases'], 'Pending row cannot contain unvalidated cases')
        return []
    source = sources[row['source']]
    result = []
    for name in row['cases']:
        if kind == 'tang_board':
            data = source['variants'][row['variant']] if row['variant'] else source
            case = next(c for c in data['cases'] if c['label'] == name)
            need(data['image_sha256'] == case['image_sha256'] == row['identity']['fpga_image_sha256'],
                 'Selected FPGA image differs')
            need(case['prompt_tokens'] == 1 and case['final_clear_acknowledged'] is True,
                 'Prompt length or CLEAR evidence changed')
            result.append(trial(row['prompt_tokens'], case['long_generated_tokens'], reference,
                case['reply_elapsed_seconds'], case['cached_decode_seconds'],
                case['first_step_seconds'], row['identity'], capture_sha256=case['private_uart_sha256']))
        elif kind == 'seeded_timing':
            need('-t0-' in name and source['image_sha256'] == row['identity']['fpga_image_sha256'],
                 'Wrong temperature or selected seeded image')
            case = source['cases'][name]['summary']
            result.append(trial(row['prompt_tokens'], case['generated_tokens'], reference,
                case['step_arrival_elapsed_seconds'], case['cached_step_seconds'],
                case['first_step_seconds'], row['identity'], capture_sha256=source['cases'][name]['source_raw']['sha256']))
        elif kind == 'canonical':
            need(source['schema'] == 'fpga-common-speed-capture-v1'
                 and source['protocol'] == 'greedy-one-token-128-host-v1'
                 and source['identity'] == row['identity'], 'Changed canonical capture contract')
            case = next(c for c in source['cases'] if c['name'] == name)
            need(case['prompt_tokens'] == row['prompt_tokens'], 'Canonical prompt differs from selected workload')
            need(case['raw_capture_sha256'] is not None, 'Missing canonical raw capture identity')
            result.append(trial(case['prompt_tokens'], case['generated_tokens'], case['expected_tokens'],
                case['reply_elapsed_seconds'], case['cached_command_seconds'], case['first_step_seconds'],
                source['identity'], decoding=case['decoding'], temperature=case['temperature'],
                clear_before=case['clear_before'], stop_at_eos=case['stop_at_eos'],
                boundary=source['timestamp_boundary'], feedback_dependent=case['feedback_dependent'],
                capture_sha256=case['raw_capture_sha256']))
        elif kind == 'qwen_rows':
            need(source['image_sha256'] == row['identity']['model_image_sha256']
                 and source['checkpoint_sha256'] == row['identity']['checkpoint_sha256'], 'Changed Qwen identity')
            case = next(c for campaign in source['campaigns'] for c in campaign['cases'] if c['name'] == name)
            rows = case['rows']
            need(case['prompt_tokens'] == row['prompt_tokens'] and [r['index'] for r in rows] == list(range(len(rows))),
                 'Prompt or output ordering changed')
            result.append(trial(case['prompt_tokens'], [r['token'] for r in rows], case['expected_tokens'],
                [r['generation_elapsed_ns'] / 1e9 for r in rows],
                [r['step_ns'] / 1e9 for r in rows[1:]], rows[0]['step_ns'] / 1e9, row['identity'],
                capture_sha256=case['raw_capture_sha256']))
        else:
            raise ValueError('Unknown capture format')
    return result


def calculate(root):
    root = Path(root)
    selection = json.loads((root / SELECTION).read_text())
    need(selection['protocol'] == 'greedy-one-token-128-host-v1'
         and selection['timestamp_boundary'] == BOUNDARY
         and (selection['repetitions'], selection['generated_outputs'], selection['cached_outputs_per_trial']) == (2, 128, 127),
         'Changed benchmark protocol')
    sources = read_sources(root, selection)
    reference = sources['tests/reference-cases.json']['around128']
    need(reference['prompt_tokens'] == [378], 'Changed SimpleStories input')
    manifest = json.loads((root / 'MANIFEST.json').read_text())
    rows = []
    for row in selection['rows']:
        if row.get('artifact'):
            need(manifest['files'][row['artifact']]['sha256'] == row['identity']['fpga_image_sha256'],
                 'Benchmark does not describe the selected published FPGA image')
        trials = selected_trials(row, sources, reference['generated_tokens'])
        need(len(trials) <= 2, 'Unexpected repetition count')
        complete = len(trials) == 2
        need(complete or bool(row.get('missing')), 'Incomplete benchmark must identify missing evidence')
        rows.append({'id': row['id'], 'label': row['label'], 'package_status': row['status'],
                     'identity': row['identity'], 'eligible_trials': len(trials), 'complete': complete,
                     'rate': pool(trials) if complete else None, 'missing': None if complete else row['missing'],
                     'trials': trials})
    return {'schema': 'fpga-common-speed-results-v1', 'protocol': selection['protocol'],
            'timestamp_boundary': BOUNDARY, 'complete_rows': sum(x['complete'] for x in rows),
            'total_rows': len(rows), 'rows': rows, 'source_sha256': selection['sources'],
            'scope': 'Recomputed recorded output/timing evidence; no fresh hardware or numerical-model replay.'}


def table(result):
    lines = ['| Model and platform | Common cached generation | Package status |', '| --- | --- | --- |']
    for row in result['rows']:
        speed = f"About **{row['rate']['cached_tokens_per_second']:.1f} tokens/s**" if row['complete'] else '—'
        lines.append(f"| {row['label']} | {speed} | {row['package_status']} |")
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--table', action='store_true')
    args = parser.parse_args()
    result = calculate(args.package)
    if args.check:
        need(result == json.loads((args.package / RESULTS).read_text()), 'Saved benchmark calculations differ')
        readme = (args.package / 'README.md').read_text()
        need(readme.count(START) == readme.count(END) == 1, 'Missing benchmark table markers')
        need(readme.split(START, 1)[1].split(END, 1)[0].strip() == table(result), 'Overview common benchmark differs')
        print(json.dumps({'passed': True, 'complete_rows': result['complete_rows'], 'total_rows': result['total_rows'],
                          'hardware_access': False, 'network_access': False}))
    elif args.table:
        print(table(result))
    else:
        print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
