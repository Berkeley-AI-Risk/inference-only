"""Recompute token agreement and timing from packaged FPGA captures, offline."""
import argparse
import json
from pathlib import Path


def check(path):
    record = json.loads(path.read_text())
    if record['image_sha256'] != 'a1e8a91912dfa79fb602601e256a4a07da64c57dda146529c08886532d42f833':
        raise ValueError('Different measured model')
    results, tokens = [], 0
    for campaign in record['campaigns']:
        if campaign['final_clear_status'] != 0:
            raise ValueError('Final CLEAR failed')
        for case in campaign['cases']:
            rows = case['rows']
            if len(rows) < 2 or [r['token'] for r in rows] != case['expected_tokens']:
                raise ValueError('Token mismatch or incomplete timing')
            if [r['index'] for r in rows] != list(range(len(rows))):
                raise ValueError('Missing/repeated token index')
            intervals = [b['generation_elapsed_ns'] - a['generation_elapsed_ns']
                         for a, b in zip(rows, rows[1:])]
            if any(t <= 0 for t in intervals) or any(r['step_ns'] <= 0 for r in rows):
                raise ValueError('Invalid monotonic timing')
            tokens += len(rows)
            results.append(dict(campaign=campaign['name'], name=case['name'],
                prompt_tokens=len(case['prompt_tokens']), generated_tokens=len(rows),
                first_token_seconds=rows[0]['prompt_elapsed_ns'] / 1e9,
                cached_host_tokens_per_second=(len(rows)-1)*1e9/sum(intervals),
                cached_command_tokens_per_second=(len(rows)-1)*1e9/sum(r['step_ns'] for r in rows[1:])))
    if tokens != 212:
        raise ValueError('Incomplete measured suite')
    return dict(passed=True, output_token_checks=tokens, cases=results,
                new_hardware_test=False, scope='Recomputed saved captures, not an independent FPGA rerun.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('measurements', nargs='?', type=Path,
                        default=Path(__file__).resolve().parents[1] / 'measurements.json')
    print(json.dumps(check(parser.parse_args().measurements), indent=2, sort_keys=True))
