"""Run selected fixed-Qwen8B software cases without changing frozen evidence.

Planning and saved-record checks use only the standard library. Actual model
execution is explicit, CPU-only and requires the pinned model dependencies.
This program never contacts AWS, accesses an FPGA or downloads a model.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path, PurePosixPath
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
MODEL_SHA = 'a1e8a91912dfa79fb602601e256a4a07da64c57dda146529c08886532d42f833'
VOCAB, CAPACITY = 151936, 32768
SCHEMA = 'qwen8b-software-campaign-v1'


def need(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def tokens(value, label):
    need(isinstance(value, list) and bool(value)
         and all(type(n) is int and 0 <= n < VOCAB for n in value),
         label + ' must be a nonempty list of fixed-vocabulary token IDs')
    return list(value)


def parse_prompt(text):
    parts = text.split(',')
    need(all(part and part.isascii() and part.isdecimal() for part in parts),
         'Use comma-separated unsigned decimal token IDs')
    return tokens([int(part) for part in parts], 'Prompt')


def verify_sources(root=ROOT):
    """Bind the old oracle and its numeric dependencies, never repin them."""
    manifest = json.loads((root/'SOURCE-INPUTS.json').read_text())
    reference = json.loads((root/'evidence/reference.json').read_text())
    need(reference['model_sha256'] == manifest['fixed_model_image_sha256'] == MODEL_SHA,
         'Different fixed model identity')
    expected = dict(reference['source_sha256'])
    for name, row in manifest['copied_or_portability_adapted_inputs'].items():
        if name.startswith(('reference/', 'tools/')):
            if name in expected:
                need(expected[name] == row['exported_sha256'], 'Conflicting source binding')
            expected[name] = row['exported_sha256']
    for name, value in expected.items():
        relative = PurePosixPath(name)
        path = root/name
        need(not relative.is_absolute() and '..' not in relative.parts and '\\' not in name
             and not path.is_symlink() and path.resolve().is_relative_to(root.resolve())
             and digest(path) == value, 'Changed bound numerical input: ' + name)
    for name in ('SOURCE-INPUTS.json', 'evidence/reference.json', 'measurements.json'):
        expected[name] = digest(root/name)
    return expected


def select_cases(measurements, campaign='smoke', case=None, prompt=None, steps=None):
    need(measurements['image_sha256'] == MODEL_SHA, 'Different measured model')
    if prompt is not None:
        need(case is None and campaign is None, 'Custom prompt cannot select a recorded campaign/case')
        selected = [dict(name='custom', prompt_tokens=tokens(prompt, 'Prompt'), expected_tokens=None)]
        need(type(steps) is int and steps > 0, 'Custom prompt requires a positive --steps')
    else:
        groups = measurements['campaigns']
        names = [group['name'] for group in groups]
        need(len(names) == len(set(names)), 'Duplicate campaign name')
        need(campaign == 'all' or campaign in names, 'Unknown campaign')
        selected, prefixes = [], {}
        for group in groups:
            case_names = [row['name'] for row in group['cases']]
            need(len(case_names) == len(set(case_names)), 'Duplicate case name')
            for row in group['cases']:
                p, e = tokens(row['prompt_tokens'], 'Recorded prompt'), tokens(row['expected_tokens'], 'Recorded outputs')
                need(len(p)+len(e) <= CAPACITY, 'Recorded case exceeds token tape')
                key = tuple(p)
                previous = prefixes.get(key, [])
                n = min(len(previous), len(e))
                need(previous[:n] == e[:n], 'Recorded deterministic prefixes disagree')
                if len(e) > len(previous):
                    prefixes[key] = e
                if campaign == 'all' or group['name'] == campaign:
                    selected.append(dict(name=group['name']+'/'+row['name'], prompt_tokens=p, expected_tokens=e))
        if case is not None:
            need(campaign != 'all', 'Choose one named campaign with --case')
            selected = [row for row in selected if row['name'] == campaign+'/'+case]
            need(len(selected) == 1, 'Unknown case')
        if campaign == 'all':
            # Deterministic repeated prefixes need only their longest case.
            longest = {}
            for row in selected:
                key = tuple(row['prompt_tokens'])
                if key not in longest or len(row['expected_tokens']) > len(longest[key]['expected_tokens']):
                    longest[key] = row
            selected = list(longest.values())
    for row in selected:
        if row['expected_tokens'] is None:
            row['steps'] = steps
        else:
            n = len(row['expected_tokens']) if steps is None else steps
            need(type(n) is int and 0 < n <= len(row['expected_tokens']),
                 '--steps must fit the recorded expected prefix')
            row['expected_tokens'] = row['expected_tokens'][:n]
            row['steps'] = n
        need(len(row['prompt_tokens'])+row['steps'] <= CAPACITY, 'Prompt/output exceeds fixed token tape')
    need(bool(selected), 'Empty campaign')
    return selected


def execute(machine, cases, repeat, result):
    """Run an existing token machine; unit-test doubles are not CLI engines."""
    need(type(repeat) is int and 1 <= repeat <= 8, 'Use 1–8 deliberate repeats, not automatic retries')
    result.update(cases=[], execution_completed=False, passed=None, final_clear=False)
    try:
        for repetition in range(repeat):
            for case in cases:
                machine.clear()
                row = dict(name=case['name'], repetition=repetition,
                           prompt_tokens=case['prompt_tokens'], tokens=[], elapsed_software_ns=[])
                result['cases'].append(row)
                for token in case['prompt_tokens']:
                    machine.append(token)
                start = time.monotonic_ns()
                for index in range(case['steps']):
                    actual = machine.step()
                    need(type(actual) is int and 0 <= actual < VOCAB, 'Invalid software output token')
                    row['tokens'].append(actual)
                    row['elapsed_software_ns'].append(time.monotonic_ns()-start)
                    expected = case['expected_tokens']
                    need(expected is None or actual == expected[index],
                         f"{case['name']} token {index} disagrees with recorded oracle")
        result['execution_completed'] = True
        result['passed'] = True if all(row['expected_tokens'] is not None for row in cases) else None
    finally:
        failure_active = sys.exc_info()[0] is not None
        try:
            machine.clear()
            result['final_clear'] = True
        except BaseException as error:
            result.update(final_clear=False, passed=False,
                          cleanup_failure=dict(type=type(error).__name__, message=str(error)))
            if not failure_active:
                raise


def check_record(record, root=ROOT):
    need(record.get('schema') == SCHEMA and record.get('execution_completed') is True
         and record.get('final_clear') is True and record.get('failure') is None
         and record.get('software_reference_only') is True
         and record.get('hardware_access') is False
         and record.get('backend') == 'cpu'
         and type(record.get('threads')) is int and 1 <= record['threads'] <= 32
         and record.get('model_sha256') == MODEL_SHA, 'Incomplete or wrong-scope software record')
    need(record['source_sha256'] == verify_sources(root), 'Saved numerical source binding changed')
    need(record['runner_sha256'] == digest(Path(__file__)), 'Saved runner identity changed')
    selection = record['selection']
    cases = select_cases(json.loads((root/'measurements.json').read_text()), **selection)
    repeat = record['repeat']
    need(type(repeat) is int and 1 <= repeat <= 8, 'Invalid repeat count')
    rows = record['cases']
    need(len(rows) == len(cases)*repeat, 'Incomplete software cases')
    compared = 0
    for index, row in enumerate(rows):
        case = cases[index % len(cases)]
        need(row['name'] == case['name'] and row['repetition'] == index//len(cases)
             and row['prompt_tokens'] == case['prompt_tokens'], 'Different case/ownership order')
        actual = tokens(row['tokens'], 'Saved outputs')
        need(len(actual) == case['steps'], 'Incomplete software outputs')
        times = row['elapsed_software_ns']
        need(len(times) == len(actual) and all(type(n) is int and n > 0 for n in times)
             and all(a < b for a, b in zip(times, times[1:])), 'Invalid software timing')
        if case['expected_tokens'] is not None:
            need(actual == case['expected_tokens'], 'Software outputs disagree with recorded oracle')
            compared += len(actual)
    expected_pass = True if all(row['expected_tokens'] is not None for row in cases) else None
    need(record['passed'] is expected_pass, 'Generation is not an oracle comparison pass')
    return dict(record_consistent=True, compared_tokens=compared, software_reference_only=True,
                hardware_qualification=False, fresh_model_execution=False)


def create_machine(model, threads):
    need(model.is_dir(), 'Model directory does not exist')
    need(type(threads) is int and 1 <= threads <= 32, 'Use 1–32 CPU threads')
    # Imports occur only after selection, source binding and output admission.
    sys.path[:0] = [str(ROOT/'reference'), str(ROOT/'tools')]
    import torch
    from prepare_model import check_image
    from dense_qwen_reference import DenseQwenEngine
    check_image(model)
    torch.set_num_threads(threads)
    torch.set_float32_matmul_precision('highest')
    return DenseQwenEngine(model, 'cpu').token_machine(), torch.__version__


def save(directory, name, record):
    with (directory/name).open('x') as stream:
        json.dump(record, stream, indent=2, sort_keys=True)
        stream.write('\n')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    selection = parser.add_mutually_exclusive_group()
    selection.add_argument('--campaign', help='Recorded campaign name, or all (default: smoke)')
    selection.add_argument('--prompt', help='Custom comma-separated token IDs; requires --steps')
    parser.add_argument('--case', help='One case within the selected named campaign')
    parser.add_argument('--steps', type=int, help='Recorded prefix length, or custom output count')
    parser.add_argument('--repeat', type=int, default=1)
    parser.add_argument('--model', type=Path)
    parser.add_argument('--threads', type=int, default=8)
    parser.add_argument('--output', type=Path, help='Fresh result directory for explicit CPU execution')
    action = parser.add_mutually_exclusive_group()
    action.add_argument('--list', action='store_true', help='List packaged cases without importing torch')
    action.add_argument('--plan', action='store_true', help='Inspect selection without executing a model')
    action.add_argument('--check-record', type=Path, help='Check a saved software result without running inference')
    args = parser.parse_args(argv)
    if args.check_record:
        print(json.dumps(check_record(json.loads(args.check_record.read_text())), indent=2))
        return 0
    measured = json.loads((ROOT/'measurements.json').read_text())
    sources = verify_sources()
    if args.list:
        print(json.dumps({group['name']: [row['name'] for row in group['cases']] for group in measured['campaigns']}, indent=2))
        return 0
    choose = dict(campaign=None if args.prompt is not None else args.campaign or 'smoke',
                  case=args.case, prompt=parse_prompt(args.prompt) if args.prompt is not None else None,
                  steps=args.steps)
    cases = select_cases(measured, **choose)
    need(1 <= args.repeat <= 8 and 1 <= args.threads <= 32, 'Invalid repeat/thread count')
    if args.plan:
        print(json.dumps(dict(cases=cases, repeat=args.repeat, threads=args.threads,
                              model_executed=False, hardware_access=False), indent=2))
        return 0
    need(args.model is not None and args.output is not None, 'Execution requires --model and a fresh --output directory')
    args.output.mkdir()
    result = dict(schema=SCHEMA, model_sha256=MODEL_SHA, source_sha256=sources,
                  runner_sha256=digest(Path(__file__)), selection=choose, repeat=args.repeat,
                  threads=args.threads, backend='cpu', software_reference_only=True,
                  hardware_access=False, failure=None, started_utc=datetime.now(timezone.utc).isoformat(),
                  scope='Selected CPU numerical cases only; no FPGA, GPU benchmark or whole-model theorem.')
    save(args.output, 'STARTED.json', result)
    start = time.monotonic()
    try:
        machine, result['torch_version'] = create_machine(args.model, args.threads)
        execute(machine, cases, args.repeat, result)
    except BaseException as error:
        result.update(execution_completed=False, passed=False,
                      failure=dict(type=type(error).__name__, message=str(error)),
                      elapsed_software_seconds=time.monotonic()-start)
        save(args.output, 'FAILED.json', result)
        raise
    result['elapsed_software_seconds'] = time.monotonic()-start
    save(args.output, 'FINISHED.json', result)
    print(json.dumps(check_record(result), indent=2))
    return 0


if __name__ == '__main__':
    sys.exit(main())
