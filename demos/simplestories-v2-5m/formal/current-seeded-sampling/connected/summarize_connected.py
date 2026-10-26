"""Verify and consolidate connected primary/audit and bounded cvc5 receipts."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

assert sys.flags.isolated and sys.flags.dont_write_bytecode and sys.flags.no_site and not sys.flags.optimize
HERE = Path(__file__).resolve().parent

def sha(raw): return hashlib.sha256(raw).hexdigest()
def read(path): return json.loads(path.read_text())
def canonical(query):
    return '\n'.join(line for line in query.splitlines() if not (
        line.startswith('(set-option :timeout ') or line.startswith('(set-option :tlimit-per ')
        or line.startswith('(set-option :produce-models ') or line.startswith('(set-logic '))) + '\n'

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--proof', type=Path, required=True)
    parser.add_argument('--audit', type=Path, required=True)
    parser.add_argument('--secondary', type=Path, action='append', default=[])
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    proof, audit, output = args.proof.absolute(), args.audit.absolute(), args.output.absolute()
    assert all(HERE.parent in path.parents for path in (proof, audit, output))
    inputs, result = read(proof / 'INPUTS.json'), read(proof / 'FINISHED.json')
    assert result['passed'] and result['inputs_sha256'] == sha((proof / 'INPUTS.json').read_bytes())
    for name, row in inputs['files'].items(): assert sha((proof / name).read_bytes()) == row['sha256']
    for name, digest in result['proof_artifacts_sha256'].items(): assert sha((proof / name).read_bytes()) == digest
    for label, row in result['solver_results'].items():
        assert row['passed'] and sha((proof / (label + '.smt2')).read_bytes()) == row['query_sha256']
        assert sha((proof / (label + '.log')).read_bytes()) == row['log_sha256']
    assert (proof / 'runner.py').read_bytes() == (HERE / 'run_connected.py').read_bytes()
    audit_result = read(audit / 'FINISHED.json')
    assert audit_result['passed'] and audit_result['proof_inputs_sha256'] == result['inputs_sha256']
    assert (audit / 'auditor.py').read_bytes() == (HERE / 'audit_connected.py').read_bytes()
    for name, digest in audit_result['replay_artifacts_sha256'].items():
        assert sha((audit / 'elaboration-replay' / name).read_bytes()) == digest
    smt_sha = result['proof_artifacts_sha256']['design.smt2']
    top, k, count = inputs['top'], inputs['induction_length'], inputs['assertions']
    smt = (proof / 'design.smt2').read_text()
    locations = dict(re.findall(r'^; yosys-smt2-assert (\d+) ([^\n]+)', smt, re.M))
    assert set(map(int, locations)) == set(range(count))
    base = canonical((proof / 'z3-base.smt2').read_text()).replace('(check-sat)\n', '', 1)
    induction = canonical((proof / 'z3-induction.smt2').read_text())
    goal = f'(assert (not ({top}_a s{k})))'
    assert induction.count(goal) == 1
    passed, base_passed, attempted = set(), False, set()
    receipts, resolved_by = [], {}
    for supplied in args.secondary:
        path = supplied.absolute()
        assert HERE.parent in path.parents
        secondary_inputs, secondary_result = read(path / 'INPUTS.json'), read(path / 'FINISHED.json')
        assert secondary_result['inputs_sha256'] == sha((path / 'INPUTS.json').read_bytes())
        assert secondary_inputs['primary_design_sha256'] == smt_sha
        assert secondary_inputs['top'] == top and secondary_inputs['induction_length'] == k
        assert secondary_inputs['same_joint_prior_assertions'] and secondary_inputs['added_assumptions'] == 0
        # The earlier primary receipt differs only in corrected descriptive
        # assertion-family metadata. Verify the actual queries identically.
        for name, row in secondary_result['results'].items():
            raw = (path / (name + '.smt2')).read_bytes()
            assert sha(raw) == row['query_sha256'] == secondary_inputs['query_files'][name + '.smt2']
            log = (path / (name + '.log')).read_bytes()
            assert sha(log) == row['log_sha256']
            if name == 'base':
                assert canonical(raw.decode()) == base
                if row['passed']:
                    assert row['exit'] == 0 and log.decode().splitlines() == ['unsat']
                    base_passed = True
            else:
                index = int(name.removeprefix('conclusion-'))
                assert index in secondary_inputs['conclusions'] and 0 <= index < count
                attempted.add(index)
                expected = induction.replace(goal, f'(assert (not (|{top}_a {index}| s{k})))')
                assert canonical(raw.decode()) == expected
                if row['passed']:
                    assert row['exit'] == 0 and log.decode().splitlines() == ['unsat']
                    passed.add(index)
                    resolved_by[str(index)] = str(path.relative_to(HERE.parent))
        receipts.append(dict(path=str(path.relative_to(HERE.parent)),
            inputs_sha256=sha((path / 'INPUTS.json').read_bytes()),
            result_sha256=sha((path / 'FINISHED.json').read_bytes()),
            checker_sha256=sha((path / 'checker.py').read_bytes()),
            conclusions=secondary_result['conclusions'], passed_conclusions=secondary_result['passed_conclusions']))
    summary = dict(schema='seeded-connected-qualification-summary-v1',
        scope=result['scope'], primary_passed=True, audit_passed=True,
        frozen_assembly_sha256=inputs['frozen_assembly_sha256'],
        frozen_inventory_sha256=inputs['frozen_inventory_sha256'],
        source_binding=inputs['source_binding'],
        exact_candidate_image_sha256=inputs['candidate_image_sha256'],
        primary=dict(path=str(proof.relative_to(HERE.parent)), inputs_sha256=result['inputs_sha256'],
            finished_sha256=sha((proof / 'FINISHED.json').read_bytes()), assertions=count,
            memories=result['memory_cells'], assumptions=result['assumption_cells'],
            induction_length=k, phase_results=result['solver_results'], design_sha256=smt_sha),
        assertion_families=dict(unchanged_baseline=88, extended_uart_replacing_baseline_46=47,
            selector_lifecycle=35, shell_settings=11, core_settings_connection=7, frontend_settings_connection=8),
        audit=dict(path=str(audit.relative_to(HERE.parent)), finished_sha256=sha((audit / 'FINISHED.json').read_bytes()),
            exact_original_source_reversal=True, byte_identical_yosys_replay=True,
            entire_external_boundary_identical_to_baseline=True, unrestricted_private_output_cuts=37,
            observer_has_no_production_fanout=True, exact_rom_words_checked=3328+4097),
        secondary=dict(base_passed=base_passed, attempted_conclusions=len(attempted),
            passed_conclusions=len(passed), total_conclusions=count,
            complete=base_passed and len(passed)==count,
            unresolved_conclusions=[dict(assertion=i, source=locations[str(i)]) for i in range(count) if i not in passed],
            passed_conclusion_indexes=sorted(passed), resolved_by=resolved_by,
            same_joint_prior_assertions=True, no_query_premise_changes=True, receipts=receipts),
        implementation_files_sha256={path.name:sha(path.read_bytes()) for path in HERE.iterdir() if path.suffix in ('.py','.sv')},
        hardware_access=False, network_access=False, production_files_edited=False,
        whole_machine_refinement=False, numerical_cdf_equivalence=False, mapped_implementation_equivalence=False)
    assert sum(summary['assertion_families'].values()) == count
    output.write_text(json.dumps(summary, indent=2, sort_keys=True) + '\n')
    print(json.dumps({key:summary[key] for key in ('primary_passed','audit_passed')}, sort_keys=True)
          + f' secondary={len(passed)}/{count} base={base_passed}', flush=True)
    return 0

if __name__ == '__main__': raise SystemExit(main())
