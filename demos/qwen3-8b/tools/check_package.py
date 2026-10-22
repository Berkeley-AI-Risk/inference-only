"""Check the packaged 8B sources and recorded evidence without AWS or an FPGA."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))

from check_measurements import check as check_measurements
from prepare_hardware import verify

ROOT = Path(__file__).resolve().parents[1]
MODEL_SHA = 'a1e8a91912dfa79fb602601e256a4a07da64c57dda146529c08886532d42f833'
CHECKPOINT_SHA = 'c16119f03177c4975be4bcc54e93cf54c290bb98079f2f8ddb2cc10bb4d07a9c'
AGFI = 'agfi-0b8b13da723c187a7'


def need(condition, message):
    if not condition:
        raise ValueError(message)


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def check(root=ROOT):
    root = root.resolve()
    source = verify(root)
    measured = json.loads((root / 'measurements.json').read_text())
    timings = check_measurements(root / 'measurements.json')
    need(source['fixed_model_image_sha256'] == measured['image_sha256'] == MODEL_SHA
         and measured['checkpoint_sha256'] == CHECKPOINT_SHA, 'Different model or checkpoint')
    reports = json.loads((root / 'evidence/implementation/REPORTS.json').read_text())
    need(reports['checkpoint_sha256'] == CHECKPOINT_SHA, 'Different implementation evidence')
    for name, row in reports['reports'].items():
        need(Path(name).name == name, 'Escaping report name')
        path = root / 'evidence/implementation' / name
        need(not path.is_symlink() and path.is_file()
             and path.stat().st_size == row['public']['bytes']
             and sha(path) == row['public']['sha256'], 'Changed implementation report')
    deployment = json.loads((root / 'deployment.json').read_text())
    need(deployment['fpga_image_id'] == 'afi-0e6c7942e44ab3234'
         and deployment['fpga_image_global_id'] == AGFI
         and deployment['region'] == 'us-east-1'
         and deployment['shell_version'] == '0x10212415'
         and deployment['image_state'] == 'available'
         and deployment['public_load_permission_verified'] is True
         and deployment['model_sha256'] == MODEL_SHA
         and deployment['routed_checkpoint_sha256'] == CHECKPOINT_SHA,
         'Different or incomplete public deployment')
    installation = json.loads((root / 'evidence/installation.json').read_text())
    need(installation['passed'] is True and installation['fresh_model_upload'] is True
         and installation['fpga_image_global_id'] == AGFI
         and installation['shell_version'] == '0x10212415'
         and installation['model_sha256'] == MODEL_SHA
         and installation['model_bytes'] == measured['image_bytes'] == 8828026880
         and installation['initial_status']['received_bytes'] == 0
         and not installation['initial_status']['flags'] & 0x10
         and installation['model_upload']['model_ready'] is True
         and installation['model_upload']['image_bytes'] == 8828026880
         and installation['final_status']['received_bytes'] == 8828026880
         and installation['final_status']['flags'] & 0x10
         and not installation['final_status']['flags'] & 0xe0
         and installation['final_clear']['status'] == 0,
         'Incomplete fresh installation evidence')
    for name, expected in installation['runtime_sources'].items():
        need(name in source['frozen_hardware_inputs'] and
             sha(root / name) == expected == source['frozen_hardware_inputs'][name]['sha256'],
             'Rehearsed runtime source differs')
    need(set(installation['runtime_sources']) ==
         {'host/Makefile', 'host/qwen_host.cpp', 'host/qwen_host_protocol.h'},
         'Incomplete rehearsed client identity')
    oracle = measured['campaigns'][1]['cases'][0]['expected_tokens']
    count = 0
    for case, expected_name, expected in zip(installation['cases'],
             ('self-test', 'generate-sixteen', 'clear-replay'),
             (oracle[:3], oracle[:16], oracle[:3]), strict=True):
        rows = case['rows']
        need(case['name'] == expected_name and case['expected_tokens'] == expected
             and [row['index'] for row in rows] == list(range(len(expected)))
             and [row['token'] for row in rows] == expected,
             'Installation output differs from measured oracle')
        count += len(rows)
    need(count == installation['output_token_checks'] == 22,
         'Incomplete installation comparison')
    reference = json.loads((root / 'evidence/reference.json').read_text())
    need(reference['passed'] is True and reference['prompt_tokens'] == [9707]
         and reference['expected_tokens'] == [11, 358, 2776]
         and reference['clear_replay_outputs'] == [[11, 358, 2776], [11, 358, 2776]]
         and reference['model_sha256'] == MODEL_SHA
         and reference['hardware_access'] is False, 'Different portable reference result')
    for name, expected in reference['source_sha256'].items():
        need(name.startswith(('reference/', 'tools/')) and '..' not in Path(name).parts
             and sha(root / name) == expected, 'Changed rehearsed reference source')
    return dict(passed=True, frozen_inputs=len(source['frozen_hardware_inputs']),
                implementation_reports=len(reports['reports']),
                original_hardware_output_checks=timings['output_token_checks'],
                installation_output_checks=count, portable_reference_output_checks=6,
                hardware_access=False, network_access=False,
                scope='Checks recorded evidence and exact inputs; does not rerun hardware, vendor tools or formal proofs.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', type=Path, default=ROOT)
    print(json.dumps(check(parser.parse_args().package), indent=2, sort_keys=True))
