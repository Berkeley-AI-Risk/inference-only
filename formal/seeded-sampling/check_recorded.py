"""Stdlib-only validation of the released seeded formal package and receipts.

This checks files/provenance/recorded outcomes; it does not rerun a solver or
reinterpret an unresolved result as a proof. Generated run directories are
explicitly excluded from release inventory and may exist locally.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path, PurePosixPath

HERE = Path(__file__).resolve().parent


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
    parser.add_argument('--list-files', action='store_true', help='Print exact package-root-relative distributable paths')
    args = parser.parse_args()
    inventory = json.loads((HERE / 'SOURCE.json').read_text())
    files = check_files(HERE, inventory)
    spec = importlib.util.spec_from_file_location('seeded_recorded_source', HERE / 'source_provider.py')
    provider = importlib.util.module_from_spec(spec); spec.loader.exec_module(provider)
    binding = provider.source_binding()
    assert inventory['distributed87_inventory_sha256'] == binding['distributed_inventory_sha256']
    assert inventory['historical_native91_inventory_sha256'] == binding['historical_native_inventory_sha256']
    assert inventory['exact_candidate_image_sha256'] == binding['image_sha256']
    recorded = json.loads((HERE / 'recorded/RESULTS.json').read_text())
    assert recorded['schema'] == 'seeded-portable-formal-recorded-v1'
    assert recorded['exact_candidate_image_sha256'] == binding['image_sha256']
    assert recorded['distributed87_inventory_sha256'] == binding['distributed_inventory_sha256']
    assert recorded['historical_native91_inventory_sha256'] == binding['historical_native_inventory_sha256']
    assert recorded['source_assembly_receipt_sha256'] == binding['source_assembly_receipt_sha256']
    expected = {'selector_lifecycle': (35, 3), 'sampler_buffer_ownership': (57, 3), 'uart': (63, 0), 'shell': (94, 20)}
    assert set(recorded['component_lanes']) == set(expected)
    for name, (count, memories) in expected.items():
        row = recorded['component_lanes'][name]
        assert row['assertions'] == count and row['memories'] == memories
        assert row['secondary_base_passed'] and row['secondary_all_conclusions_passed']
        for phase, answers in [('z3-base', ['sat', 'unsat']), ('z3-induction', ['unsat'])]:
            result = row['primary'][phase]
            assert result['passed'] and result['exit'] == 0 and not result['timed_out'] and result['answers'] == answers
    connected = recorded['connected']
    assert connected['primary_passed'] and connected['assertions'] == 196 and connected['memories'] == 20
    assert connected['assumptions'] == 0 and connected['private_output_cuts'] == 37
    assert connected['secondary_base_passed'] and connected['secondary_attempted'] == 196
    assert connected['secondary_passed'] == 194 and connected['secondary_complete'] is False
    assert {row['assertion'] for row in connected['unresolved_conclusions']} == {38, 73}
    assert recorded['lean']['passed'] and recorded['lean']['theorems'] == 15
    assert recorded['lean']['source_sha256'] == sha((HERE / 'SeededPublicSurface.lean').read_bytes())
    assert recorded['lean']['toolchain'] == 'leanprover/lean4:v4.33.1'
    assert not recorded['lean']['rtl_refinement'] and not recorded['lean']['numerical_sampler']
    assert recorded['sensitivity'] == dict(selector_reset_reachable_mutants=7,
        buffer_reset_reachable_mutants=2, uart_serial_mutants=5, actual_uart_cases=284, uart_formal_proof=False)
    fresh = json.loads((HERE / 'recorded/PUBLIC-REPLAY.json').read_text())
    assert fresh['schema'] == 'seeded-portable-formal-public-replay-v1'
    assert fresh['source_binding'] == binding and fresh['primary_scoped_checks_passed']
    assert fresh['all_models_match_recorded'] and fresh['lean_theorems'] == 15
    assert fresh['model_sha256'] == {name: row['model_sha256'] for name, row in recorded['component_lanes'].items()} | {'connected': connected['model_sha256']}
    assert fresh['connected_secondary']['complete'] == (fresh['connected_secondary']['base_passed'] and fresh['connected_secondary']['passed_conclusions'] == 196)
    assert not fresh['vendor_logic_elaborated'] and not fresh['reran_hardware']
    if args.list_files:
        print('formal/seeded-sampling/SOURCE.json')
        for name in sorted(files): print('formal/seeded-sampling/' + name)
    else:
        print('SEEDED_FORMAL_RECORDED_PASS release_files=' + str(len(files) + 1)
              + ' distributed_inputs=87 vendor_bytes_verified=0 solver_replay=false')


if __name__ == '__main__': main()
