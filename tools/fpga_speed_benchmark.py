#!/usr/bin/env python3
"""Recompute one common FPGA generation benchmark from immutable captures.

Standard library only. No hardware, network, model inference or file writes.
"""
import argparse
import gzip
import hashlib
import importlib.util
import json
import math
from pathlib import Path, PurePosixPath

SELECTION = 'benchmarks/fpga-speed/selection.json'
RESULTS = 'benchmarks/fpga-speed/results.json'
BOUNDARY = 'generation_loop_validated_reply'
PROTOCOL = 'one-token-128-host-v2'
MODEL = 'demos/simplestories-v2-5m'
START, END = '<!-- COMMON-FPGA-SPEED:START -->', '<!-- COMMON-FPGA-SPEED:END -->'


def need(value, message):
    if not value:
        raise ValueError(message)


def positive(value):
    need(type(value) in (int, float) and math.isfinite(value) and value > 0, 'Invalid positive timing')
    return value


def trial(prompt, tokens, expected, arrivals, cached_commands, first_step,
          identity, *, decoding='greedy', temperature=0, clear_before=True,
          stop_at_eos=False, boundary=BOUNDARY, feedback_dependent=True, capture_sha256=None,
          profile='greedy', seed=None):
    need(len(prompt) == 1 and all(type(x) is int and x >= 0 for x in prompt), 'Expected one input token')
    need(len(tokens) == len(expected) == 128, 'Expected exactly 128 outputs and reference IDs')
    need(all(type(x) is int and x >= 0 for x in tokens + expected), 'Invalid token IDs')
    need(tokens == expected, 'Recorded outputs differ from numerical reference IDs')
    if profile == 'greedy':
        need(decoding == 'greedy' and type(temperature) in (int, float) and temperature == 0,
             'Greedy profile requires temperature 0')
    else:
        need(profile == 'seeded-temperature1' and decoding == 'seeded-sampling'
             and type(temperature) in (int, float) and temperature == 1,
             'Unsupported sampled decoding profile')
        need(isinstance(seed, str) and seed.startswith('0x') and len(seed) == 34
             and all(x in '0123456789abcdef' for x in seed[2:]), 'Missing fixed public sampling seed')
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
    result = {'capture_sha256': capture_sha256, 'prompt_tokens': prompt, 'generated_outputs': 128, 'cached_outputs': 127,
            'cached_host_seconds': positive(elapsed), 'cached_command_seconds': command_time,
            'first_step_seconds': positive(first_step), 'identity': identity, 'timestamp_boundary': boundary,
            'greedy': profile == 'greedy', 'clear_before': True, 'stop_at_eos': False}
    if profile != 'greedy':
        result.update(decoding=decoding, temperature=temperature, seed=seed)
    return result


def pool(trials):
    need(len(trials) == 2, 'Exactly two complete trials are required')
    need(trials[0]['identity'] == trials[1]['identity'], 'Mixed image/model/clock identities')
    need(trials[0]['prompt_tokens'] == trials[1]['prompt_tokens'], 'Mixed prompt IDs')
    need(all(x['timestamp_boundary'] == BOUNDARY and x['cached_outputs'] == 127
             and x['generated_outputs'] == 128 for x in trials), 'Mixed boundaries or output counts')
    captures = [x.get('capture_sha256') for x in trials]
    need(not all(captures) or captures[0] != captures[1], 'A capture cannot count twice')
    modes = {(x.get('decoding', 'greedy'), x.get('temperature', 0)) for x in trials}
    need(len(modes) == 1, 'Mixed decoding modes or temperatures')
    mode = next(iter(modes))
    need(mode in {('greedy', 0), ('seeded-sampling', 1)}, 'Unsupported trial decoding mode')
    if mode == ('seeded-sampling', 1):
        need(bool(trials[0].get('seed')) and trials[0]['seed'] == trials[1].get('seed'),
             'Mixed sampling seeds')
    need(all(x['greedy'] == (mode == ('greedy', 0)) and x['clear_before']
             and x['stop_at_eos'] is False for x in trials), 'Changed trial policy')
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
            sampled = row.get('decoding') == 'seeded-sampling'
            code = 2 if sampled else 0
            need(f'-t{code}-' in name and source['image_sha256'] == row['identity']['fpga_image_sha256'],
                 'Wrong temperature or selected seeded image')
            case = source['cases'][name]['summary']
            options = {}
            expected = reference
            if sampled:
                golden = sources[row['reference_source']]
                need(row['temperature'] == 1 and golden['temperature'] == '1'
                     and golden['prompt_tokens'] == row['prompt_tokens']
                     and golden['model_image_sha256'] == source['model_image_sha256'],
                     'Wrong sampled temperature, prompt or numerical reference')
                expected = golden['generated_tokens']
                options = dict(profile='seeded-temperature1', decoding='seeded-sampling',
                               temperature=1, seed=golden['seed'])
            result.append(trial(row['prompt_tokens'], case['generated_tokens'], expected,
                case['step_arrival_elapsed_seconds'], case['cached_step_seconds'],
                case['first_step_seconds'], row['identity'],
                capture_sha256=source['cases'][name]['source_raw']['sha256'], **options))
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


def verify_sampled_wire(root, row, sources):
    """Replay actual mode/seed, prompt, CLEAR and returned IDs from pinned frames."""
    source = sources[row['source']]
    golden = sources[row['reference_source']]
    need(golden['schema'] == 'seeded-exact-model-golden-v1' and golden['output_count'] == 128
         and golden['stop_at_eos'] is False, 'Wrong sampled golden scope')
    need(row['cases'] == ['matched128/around128-t2-run1', 'matched128/around128-t2-run2'],
         'Sampled profile requires both complete temperature-1 trials')
    setting = None
    campaigns = set()
    for name in row['cases']:
        case = source['cases'][name]
        campaigns.add(case['source_campaign']['sha256'])
        pin = case['selected_events']; path = PurePosixPath(pin['path'])
        need(not path.is_absolute() and '..' not in path.parts, 'Unsafe sampled event path')
        # Event paths inside the immutable SimpleStories capture are relative
        # to its model package, as they were at collection time.
        raw = (root / MODEL / path).read_bytes()
        need(len(raw) == pin['bytes'] and hashlib.sha256(raw).hexdigest() == pin['sha256'],
             'Changed sampled event capture')
        need(pin['uncompressed_bytes'] < 1024 * 1024, 'Oversized sampled event capture')
        data = gzip.decompress(raw)
        need(len(data) == pin['uncompressed_bytes']
             and hashlib.sha256(data).hexdigest() == pin['uncompressed_sha256'], 'Changed sampled raw frames')
        events = [json.loads(line) for line in data.decode().splitlines()]
        need(len(events) == pin['events'], 'Changed sampled event count')
        tx = [x for x in events if x['event'] == 'tx_attempt']
        rx = [x for x in events if x['event'] == 'raw_rx']
        need(tx[0]['operation'] == 'initial-clear' and tx[0]['frame_hex'] == 'a502000067'
             and rx[0]['operation'] == 'initial-clear' and rx[0]['frame_hex'] == '5a820000bd',
             'Missing sampled pretrial CLEAR')
        for event in tx:
            if event['operation'] == 'settings':
                frame = bytes.fromhex(event['frame_hex'])
                need(len(frame) == 20 and frame[:2] == bytes.fromhex('a503'), 'Malformed sampled settings')
                setting = (frame[2], int.from_bytes(frame[3:19], 'little'))
                need(any(x['operation'] == 'settings' and x['frame_hex'] == '5a830200fc' for x in rx),
                     'Sampled settings were not acknowledged')
        need(setting == (2, int(golden['seed'], 16)), 'Captured sampling temperature or seed differs')
        prompts = [x for x in tx if x['operation'].startswith('prompt-')]
        need(len(prompts) == 1 and int.from_bytes(bytes.fromhex(prompts[0]['frame_hex'])[2:4], 'little')
             == row['prompt_tokens'][0], 'Different sampled prompt')
        outputs = [x for x in rx if x['role'] == 'main']
        need([x['operation'] for x in outputs] == [f'long-step-{i}' for i in range(1, 129)]
             and all(bytes.fromhex(x['frame_hex'])[:2] == bytes.fromhex('5a81') for x in outputs),
             'Missing or reordered sampled output frames')
        need([int.from_bytes(bytes.fromhex(x['frame_hex'])[2:4], 'little') for x in outputs]
             == case['summary']['generated_tokens'] == golden['generated_tokens'],
             'Sampled raw/reference outputs differ')
    need(len(campaigns) == 1, 'Sampled settings cannot be inherited across different campaigns')


def calculate(root):
    root = Path(root)
    selection = json.loads((root / SELECTION).read_text())
    need(selection['protocol'] == PROTOCOL
         and selection['timestamp_boundary'] == BOUNDARY
         and (selection['repetitions'], selection['generated_outputs'], selection['cached_outputs_per_trial']) == (2, 128, 127),
         'Changed benchmark protocol')
    sources = read_sources(root, selection)
    reference = sources[MODEL+'/tests/reference-cases.json']['around128']
    need(reference['prompt_tokens'] == [378], 'Changed SimpleStories input')
    manifest = json.loads((root / 'MANIFEST.json').read_text())
    rows = []
    for row in selection['rows']:
        if row.get('decoding') == 'seeded-sampling':
            need(row['format'] == 'seeded_timing' and row['temperature'] == 1,
                 'Unsupported sampled row')
            verify_sampled_wire(root, row, sources)
        if row['id'].startswith('qwen') and row['format'] == 'canonical':
            need(row.get('evidence_review') in sources, 'Missing Qwen raw evidence review')
            spec = importlib.util.spec_from_file_location('qwen_common_speed_evidence',
                root / 'tools/qwen_common_speed_evidence.py')
            verifier = importlib.util.module_from_spec(spec); spec.loader.exec_module(verifier)
            verifier.verify(root, row, sources[row['source']], sources[row['evidence_review']])
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


def inference_clock_mhz(row):
    identity = row['identity']
    if 'clock_hz' in identity:
        return identity['clock_hz'] / 1_000_000
    if 'core_clock_mhz' in identity:
        return identity['core_clock_mhz']
    return identity['clocks_mhz']['core']


def table(result):
    lines = ['| Model and platform | Inference clock (MHz) | Common cached generation | Package status |', '| --- | --- | --- | --- |']
    for row in result['rows']:
        speed = f"~**{row['rate']['cached_tokens_per_second']:.1f} tokens/s**" if row['complete'] else '—'
        clock = f"{inference_clock_mhz(row):g}"
        lines.append(f"| {row['label']} | {clock} | {speed} | {row['package_status']} |")
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
