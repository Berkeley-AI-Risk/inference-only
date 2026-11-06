"""Compare saved install-client JSONL to a source-bound CPU campaign record.

This is an offline comparison tool, not an FPGA driver or an attestation tool.
The operator must preserve the real client exit status and deployment identity.
It runs no SDK operation, model, solver, network request or hardware command.
"""
import argparse
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('qwen8b_campaign', ROOT/'reference/run_campaign.py')
CAMPAIGN = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CAMPAIGN)


def check_rows(text, expected, child_exit_code):
    need = CAMPAIGN.need
    need(type(child_exit_code) is int and child_exit_code == 0,
         'Preserve and supply the actual successful client exit code')
    rows = [json.loads(line) for line in text.splitlines() if line.strip()]
    need(len(rows) == len(expected) and bool(rows), 'Missing or extra captured output')
    keys = {'index', 'token', 'step_ns', 'generation_elapsed_ns', 'prompt_elapsed_ns'}
    for index, row in enumerate(rows):
        need(isinstance(row, dict) and set(row) == keys
             and all(type(row[key]) is int for key in keys), 'Malformed client output row')
        need(row['index'] == index and row['token'] == expected[index],
             'Captured index/token differs from independent software result')
        need(row['step_ns'] > 0 and row['generation_elapsed_ns'] > 0
             and row['prompt_elapsed_ns'] >= row['generation_elapsed_ns'], 'Invalid client timing')
    for previous, row in zip(rows, rows[1:]):
        need(previous['generation_elapsed_ns'] < row['generation_elapsed_ns']
             and previous['prompt_elapsed_ns'] < row['prompt_elapsed_ns'],
             'Client timestamps are not strictly increasing')
    elapsed = rows[-1]['generation_elapsed_ns']-rows[0]['generation_elapsed_ns']
    return dict(output_token_checks=len(rows), first_token_seconds=rows[0]['prompt_elapsed_ns']/1e9,
                cached_intervals=len(rows)-1,
                cached_host_tokens_per_second=(len(rows)-1)*1e9/elapsed if len(rows)>1 else None,
                cached_command_tokens_per_second=(len(rows)-1)*1e9/sum(row['step_ns'] for row in rows[1:]) if len(rows)>1 else None)


def check(capture, reference, case_index, child_exit_code):
    record = json.loads(reference.read_text())
    CAMPAIGN.check_record(record)
    CAMPAIGN.need(type(case_index) is int and 0 <= case_index < len(record['cases']), 'Invalid software case index')
    case = record['cases'][case_index]
    result = check_rows(capture.read_text(), case['tokens'], child_exit_code)
    result.update(recorded_capture_matches_reference=True, name=case['name'],
                  prompt_tokens=case['prompt_tokens'], repetition=case['repetition'],
                  source_bound_software_record_sha256=CAMPAIGN.digest(reference),
                  capture_sha256=CAMPAIGN.digest(capture), actual_client_exit_code=child_exit_code,
                  exit_code_supplied_by_operator=True, fresh_hardware_execution=False,
                  model_image_clock_attestation=False, hardware_qualification=False,
                  scope='Saved client token/timing comparison only. Exit/deployment authenticity and the correct prompt/loaded image require separately preserved operator receipts.')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--capture', type=Path, required=True)
    parser.add_argument('--reference', type=Path, required=True, help='Actual FINISHED.json from the CPU campaign')
    parser.add_argument('--case-index', type=int, default=0)
    parser.add_argument('--child-exit-code', type=int, required=True)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    result = check(args.capture, args.reference, args.case_index, args.child_exit_code)
    if args.output:
        with args.output.open('x') as stream:
            json.dump(result, stream, indent=2, sort_keys=True)
            stream.write('\n')
    print(json.dumps(result, indent=2, sort_keys=True))
