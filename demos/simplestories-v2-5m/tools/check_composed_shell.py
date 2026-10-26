"""Replay the connected UART/core/token-shell lemma, not whole-chip refinement.

The default checks the primary joint induction, exact historical query/source
correspondence, real-serial tests and observer/cut audit. The optional second
solver checks every conclusion and can remain incomplete without invalidating
the separately reported primary result. An unknown is never counted as proved.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import runpy
import subprocess
import sys
import time

assert sys.flags.isolated and sys.flags.no_site and sys.flags.dont_write_bytecode
assert not sys.flags.optimize


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', required=True, type=Path)
    parser.add_argument('--work', required=True, type=Path)
    for tool in ('yosys', 'z3', 'cvc5', 'verilator'):
        parser.add_argument('--' + tool, default=tool)
    parser.add_argument('--second-solver', action='store_true')
    parser.add_argument('--seconds-per-query', type=int, default=900)
    args = parser.parse_args()
    package, work = args.package.resolve(strict=True), args.work.absolute()
    assert not work.resolve().is_relative_to(package)
    # Verilator/GNU Make needs a whitespace-free spelling. An existing alias
    # of the same directory is fine; no copying to another worktree is needed.
    assert not any(c.isspace() for c in str(work)), 'Use a whitespace-free work path or existing alias.'
    manifest = json.loads((package / 'MANIFEST.json').read_text())
    formal = package / 'formal/composed-shell'
    for name, row in manifest['files'].items():
        if name.startswith(('formal/', 'hardware/', 'host-app/hardware-inputs.json',
                            'tools/replay_diagnostics.py')):
            path = package / name
            assert path.is_file() and not path.is_symlink()
            assert sha(path) == row['sha256'] and path.stat().st_size == row['bytes'], name
    diagnostics = runpy.run_path(str(package / 'tools/replay_diagnostics.py'))
    work.mkdir(parents=True, exist_ok=False)
    (work / 'replayer.py').write_bytes(Path(__file__).read_bytes())
    python = [sys.executable, '-I', '-S', '-B']
    records = {}

    def run(label, argv, allowed=(0,)):
        start = time.monotonic()
        with (work / (label + '.log')).open('x') as log:
            code = subprocess.run(argv, stdout=log, stderr=subprocess.STDOUT).returncode
        row = {'exit': code, 'seconds': time.monotonic() - start,
               'argv': argv, 'log_sha256': sha(work / (label + '.log'))}
        records[label] = row
        assert code in allowed, diagnostics['stage_failure'](label, code, work / (label + '.log'))
        return row

    with ThreadPoolExecutor(max_workers=2) as pool:
        jobs = [pool.submit(run, 'proof', python + [str(formal / 'run_proof.py'),
            '--run', str(work / 'proof'), '--yosys', args.yosys, '--z3', args.z3]),
            pool.submit(run, 'traces', python + [str(formal / 'check_traces.py'),
            '--run', str(work / 'traces'), '--verilator', args.verilator])]
        for job in jobs:
            job.result()
    expected = json.loads((formal / 'expected.json').read_text())
    for name, digest in expected['proof_artifacts'].items():
        path = work / 'proof' / name
        actual = sha(path)
        assert actual == digest, diagnostics['identity_failure'](path, digest, actual)
    for name, row in expected['generated_sources'].items():
        path = work / 'proof' / name
        actual = sha(path)
        assert actual == row['sha256'], diagnostics['identity_failure'](path, row['sha256'], actual)
        assert path.stat().st_size == row['bytes'], name
    assert sha(work / 'traces/tb_body.sv') == expected['testbench_body_sha256']
    secondary_args = []
    if args.second_solver:
        run('second-solver', python + [str(formal / 'cross_check.py'),
            '--run', str(work / 'secondary'), '--proof', str(work / 'proof'),
            '--cvc5', args.cvc5, '--seconds', str(args.seconds_per_query)], allowed=(0, 1))
        secondary_args = ['--extra-check', str(work / 'secondary')]
    audit_cmd = python + [str(formal / 'audit_proof.py'), '--run', str(work / 'audit'),
        '--proof', str(work / 'proof'), '--traces', str(work / 'traces'),
        '--yosys', args.yosys] + secondary_args
    run('audit', audit_cmd)
    run('audit-verify', audit_cmd + ['--verify-only'])
    proof = json.loads((work / 'proof/FINISHED.json').read_text())
    traces = json.loads((work / 'traces/FINISHED.json').read_text())
    audit = json.loads((work / 'audit/FINISHED.json').read_text())
    assert proof['passed'] and proof['assertions'] == 134
    assert traces['passed'] and len(traces['jobs']) == 6
    assert audit['source_structure_audit_passed'] and audit['assertions'] == 134
    assert len(audit['memories']) == 17 and len(audit['private_output_cuts']) == 37
    assert audit['observer_cone']['production_net_port_or_memory_hits'] == []
    # Any genuine secondary counterexample or execution/parser error fails
    # this replay. A clean solver unknown is reported as incomplete, not pass.
    if args.second_solver:
        secondary = json.loads((work / 'secondary/FINISHED.json').read_text())
        assert set(secondary['jobs']) == {'base'} | {f'induction-{i:03}' for i in range(134)}
        for name, row in secondary['jobs'].items():
            assert row['exit'] == 0 and row['answers'] in (['unsat'], ['unknown']), (name, row)
    result = {'passed': True, 'primary_joint_induction_passed': True,
        'assertions': 134, 'source_structure_audit_passed': True,
        'historical_generated_source_and_query_match': True,
        'serial_scenarios': 13, 'simulation_faulty_controls_detected': 5,
        'second_solver_executed': args.second_solver,
        'second_solver_conclusions': audit['second_solver_conclusions'],
        'complete_second_solver': audit['complete_second_solver'],
        'hardware_access': False, 'network_access': False,
        'whole_machine_refinement': False, 'records': records,
        'scope': 'Primary joint RTL induction at explicit private-service boundaries, exact query correspondence and serial/source/cut/observer checks. A passing replay is NOT a complete second-solver or whole-machine proof.'}
    (work / 'FINISHED.json').write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print('COMPOSED_SHELL_REPLAY_FINISHED primary_and_structural_checks=True complete_second_solver=' + str(result['complete_second_solver']), flush=True)


if __name__ == '__main__':
    main()
