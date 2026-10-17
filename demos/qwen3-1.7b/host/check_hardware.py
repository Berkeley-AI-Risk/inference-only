"""Exercise the browser's actual controller against an already configured FPGA.

This sends CLEAR/APPEND/STEP and changes the token tape. It does not configure
an FPGA, upload a model, provision AWS resources, or run a software model.
The expected IDs come from the packaged numerical-reference records.
"""
import argparse
from dataclasses import asdict
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shlex
import subprocess

from qwen_backend import Controller, load_connection
from qwen_text import END_TOKENS, encode_prompt, summarize

DEMO = Path(__file__).resolve().parents[1]
PROMPTS = {
    'original_smoke': ('Hello', True),
    'raw_story': ('Once upon a time', True),
    'raw_geography': ('The capital of France is', True),
    'chat_greeting': ('Say hello.', False),
    'original_smoke_replay': ('Hello', True),
}


def clear(config):
    argv = (['sudo', '-n'] if config['sudo'] else []) + [
        config['host_client'], '--slot', str(config['slot']), 'clear']
    if config['ssh_argv']:
        argv = config['ssh_argv'] + [shlex.join(argv)]
    reply = subprocess.run(argv, check=True, capture_output=True, text=True,
                           timeout=60, shell=False)
    data = json.loads(reply.stdout)
    if (set(data) != {'id', 'status', 'token', 'elapsed_ns'}
            or any(type(value) is not int or value < 0 for value in data.values())
            or data['status'] != 0):
        raise ValueError('Final CLEAR did not return a successful reply')
    return data


def expected_prefix(tokens, stop_at_end):
    if stop_at_end:
        for index, token in enumerate(tokens):
            if token in END_TOKENS:
                return tokens[:index + 1]
    return list(tokens)


def exercise(config, report, stop_at_end=False):
    source = (DEMO / 'measurements.json').read_bytes()
    measurements = json.loads(source)
    campaign = next(c for c in measurements['campaigns'] if c['name'] == 'sustained-128-run2')
    report.update(schema='qwen-browser-backend-hardware-check-v1',
                  started_utc=datetime.now(timezone.utc).isoformat(),
                  expected_ids_source_sha256=hashlib.sha256(source).hexdigest(),
                  reference_regenerated=False, physical_attestation=False,
                  browser_rendering_tested=False, model_uploaded=False,
                  fpga_reconfigured=False, stop_at_end=stop_at_end, cases=[], passed=False)
    controller = Controller(config, stop_at_end=stop_at_end)
    for case in campaign['cases']:
        prompt, raw = PROMPTS[case['name']]
        requested = len(case['expected_tokens'])
        expected = expected_prefix(case['expected_tokens'], stop_at_end)
        ids = encode_prompt(controller.tokenizer, prompt, requested, raw)
        if ids != case['prompt_tokens']:
            raise ValueError('Text encoding differs from the qualified prompt: ' + case['name'])
        print('Running ' + case['name'] + ' (' + str(len(expected)) + ' outputs)', flush=True)
        controller.start('hardware-check', prompt, requested, raw)
        # Wait for the owned controller. The C++ host client has bounded device
        # waits; this script never resets hardware to recover a failed request.
        controller.worker.join()
        result = controller.snapshot('hardware-check')
        record = asdict(result)
        record.pop('owner')
        record.update(name=case['name'], expected_tokens=expected)
        actual = [s['token'] for s in result.steps]
        record['matched'] = result.state == 'complete' and actual == expected
        report['cases'].append(record)
        if not record['matched']:
            raise ValueError('FPGA output or controller failure in ' + case['name'])
        record['timing'] = summarize(result.steps, requested)
        print(json.dumps(dict(name=case['name'], matched=len(actual),
                              first_token_seconds=result.first_token_seconds,
                              cached_tokens_per_second=result.streaming_tps)), flush=True)
    report['final_clear'] = clear(config)
    report['compared_tokens'] = sum(len(c['steps']) for c in report['cases'])
    report['completed_utc'] = datetime.now(timezone.utc).isoformat()
    report['passed'] = True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--connection', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True, help='New JSON record; never overwritten')
    parser.add_argument('--stop-at-end', action='store_true',
                        help='Check chat stopping against the same recorded reference prefixes')
    parser.add_argument('--exercise-fpga', action='store_true', required=True,
                        help='Confirm exclusive use of the configured FPGA and token tape')
    args = parser.parse_args()
    config = load_connection(args.connection)
    report = dict(passed=False)
    # Reserve the result before touching the device. No connection credentials,
    # destination, or SSH command are copied into this shareable report.
    with args.output.open('x') as output:
        try:
            exercise(config, report, args.stop_at_end)
        except (Exception, KeyboardInterrupt):
            report['passed'] = False
            report['failure'] = 'Hardware check did not complete; inspect the operator terminal. No recovery was attempted.'
            raise
        finally:
            json.dump(report, output, indent=2)
            output.write('\n')
    print(json.dumps(dict(passed=True, compared_tokens=report['compared_tokens'])))


if __name__ == '__main__':
    main()
