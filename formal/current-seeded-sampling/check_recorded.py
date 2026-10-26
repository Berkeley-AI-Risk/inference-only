"""Check current source association; archived results never grant current PASS.

This read-only source check runs no solver and adds no pre-board solver gate.
A separate current completion record may register fresh same-scope replay.
The construction binding and historical recorded outcomes remain unchanged.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path, PurePosixPath
HERE = Path(__file__).resolve().parent
# No RTL-only completion is invented by this source-only preparation.
COMPLETION_RECORD_SHA='b27e743ffd9d3dafc053473f5eed6dffdcb6a74e5704a8e9caa70f2fcac2d13f'
def sha(raw): return hashlib.sha256(raw).hexdigest()
def generated(parts):
    return '__pycache__' in parts or parts[:1] == ('runs',) or parts[:2] == ('connected', 'runs')


def check_files(root, inventory):
    assert inventory['schema'] == 'seeded-public-formal-package-v1'
    assert inventory['inventory_includes_itself'] is False
    assert inventory['vendor_files_included'] is False and inventory['generated_runs_included'] is False
    files = inventory['files']
    assert files and 'SOURCE.json' not in files
    for name, entry in files.items():
        relative = PurePosixPath(name)
        assert relative.parts and not relative.is_absolute() and '..' not in relative.parts
        assert not generated(relative.parts) and relative.parts[0] != 'official'
        path = root / name
        assert path.is_file() and not path.is_symlink(), name
        raw = path.read_bytes()
        assert len(raw) == entry['bytes'] and sha(raw) == entry['sha256'], name
    actual = {str(path.relative_to(root)) for path in root.rglob('*')
              if path.is_file() and not generated(path.relative_to(root).parts)}
    assert actual == set(files) | {'SOURCE.json'}, ('Unlisted release files', sorted(actual - set(files) - {'SOURCE.json'}))
    return files


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--list-files', action='store_true')
    parser.add_argument('--require-complete', action='store_true')
    args = parser.parse_args()
    for path in HERE.rglob('*'):
        if path.is_symlink(): raise ValueError('Formal packet symlink refused')
    inventory = json.loads((HERE / 'SOURCE.json').read_bytes())
    files = check_files(HERE, inventory)
    spec = importlib.util.spec_from_file_location('current_seeded_sources', HERE / 'source_provider.py')
    provider = importlib.util.module_from_spec(spec); spec.loader.exec_module(provider)
    binding = provider.source_binding()
    assert inventory['exact_candidate_image_sha256'] == binding['image_sha256']
    assert inventory['current_native91_inventory_sha256'] == binding['current_native_inventory_sha256']
    assert inventory['distributed87_inventory_sha256'] == binding['distributed_inventory_sha256']
    status = json.loads((HERE / 'CURRENT-STATUS.json').read_bytes())
    assert status['schema'] == 'current-seeded-formal-status-v1'
    assert status['image_sha256'] == binding['image_sha256']
    assert status['qualification_inherited'] is False and status['sha_compression_arithmetic_proved'] is False
    if status['current_solver_replay_passed'] is True:
        if COMPLETION_RECORD_SHA is None:
            raise ValueError('Actual RTL-only completion registration is pending')
        spec = importlib.util.spec_from_file_location('current_completion_contract', HERE / 'completion_contract.py')
        contract = importlib.util.module_from_spec(spec); spec.loader.exec_module(contract)
        origin = status['current_replay']
        assert origin['path'] == 'CURRENT-REPLAY.json'
        raw = (HERE / origin['path']).read_bytes()
        contract.validate_record_binding(raw, origin, COMPLETION_RECORD_SHA)
        contract.validate_completion(json.loads(raw), binding)
        assert status['completion_registration_pending'] is False
    else:
        assert status['current_solver_replay_passed'] is False
        if args.require_complete:
            raise ValueError('Actual current replay registration is pending; no completed-current receipt exists')
    if args.list_files:
        print('formal/current-seeded-sampling/SOURCE.json')
        for name in sorted(files): print('formal/current-seeded-sampling/' + name)
    else:
        print('CURRENT_FORMAL_SOURCE_ASSOCIATION_PASS current_solver_replay_passed=' + str(status['current_solver_replay_passed']).lower() + ' qualification_inherited=false')


if __name__ == '__main__': main()
