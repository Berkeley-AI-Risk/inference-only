#!/usr/bin/env python3
"""Portable sealed weight-bank proof, fault sensitivity and source audit."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import runpy
import subprocess
import sys
import time

assert sys.flags.isolated and sys.flags.dont_write_bytecode and not sys.flags.optimize


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', required=True, type=Path)
    parser.add_argument('--work', required=True, type=Path)
    for tool in ('yosys', 'z3', 'cvc5', 'iverilog', 'vvp'):
        parser.add_argument('--'+tool, default=tool)
    args = parser.parse_args()
    package, work = args.package.resolve(strict=True), args.work.resolve()
    assert not work.is_relative_to(package)
    raw_manifest = (package/'MANIFEST.json').read_bytes()
    manifest = json.loads(raw_manifest)['files']
    checked = {}

    def read(name):
        path = package/name
        assert not path.is_symlink()
        data = path.read_bytes()
        assert sha(data) == manifest[name]['sha256'] and len(data) == manifest[name]['bytes']
        checked[name] = sha(data)
        return data

    formal = package/'formal/page-bank'
    for name in ('run_proof.py', 'bank_monitor.inc.sv', 'sha_boundary.sv', 'bank_tb.sv',
                 'check_scenarios.py', 'audit.py', 'expected.json'):
        read('formal/page-bank/'+name)
    expected = json.loads(read('formal/page-bank/expected.json'))
    for name, value in expected['production_sources'].items():
        assert sha(read(name)) == value
    read('tools/replay_diagnostics.py')
    diagnostics = runpy.run_path(str(package/'tools/replay_diagnostics.py'))
    work.mkdir(parents=False, exist_ok=False)
    (work/'wrapper.py').write_bytes(Path(__file__).read_bytes())
    python = [sys.executable, '-I', '-B', '-S']

    def execute(item):
        label, argv = item
        started = time.monotonic()
        with (work/(label+'.log')).open('w') as output:
            result = subprocess.run(argv, stdout=output, stderr=subprocess.STDOUT)
        row = {'exit': result.returncode, 'seconds': time.monotonic()-started,
               'argv': argv, 'log_sha256': sha((work/(label+'.log')).read_bytes())}
        assert result.returncode == 0, diagnostics['stage_failure'](
            label, result.returncode, work/(label+'.log'))
        return label, row

    proof, scenarios, audit = work/'proof', work/'scenarios', work/'audit'
    jobs = [('proof', python+[str(formal/'run_proof.py'), '--package', str(package), '--run', str(proof),
             '--yosys', args.yosys, '--z3', args.z3, '--cvc5', args.cvc5]),
            ('scenarios', python+[str(formal/'check_scenarios.py'), '--package', str(package),
             '--run', str(scenarios), '--iverilog', args.iverilog, '--vvp', args.vvp])]
    with ThreadPoolExecutor(max_workers=2) as pool:
        executions = dict(pool.map(execute, jobs))
    for name, value in expected['generated_sources'].items():
        actual = sha((proof/name).read_bytes())
        assert actual == value, diagnostics['identity_failure'](proof/name, value, actual)
    for name, value in expected['proof_artifacts'].items():
        actual = sha((proof/name).read_bytes())
        assert actual == value, diagnostics['identity_failure'](proof/name, value, actual)
    assert sha((scenarios/'testbench.sv').read_bytes()) == expected['testbench_sha256']
    audit_argv = python+[str(formal/'audit.py'), '--package', str(package), '--proof', str(proof),
        '--scenarios', str(scenarios), '--run', str(audit), '--yosys', args.yosys]
    for item in [('audit', audit_argv), ('audit-verify-only', audit_argv+['--verify-only'])]:
        label, row = execute(item)
        executions[label] = row
    result = json.loads((audit/'FINISHED.json').read_text())
    assert result['passed'] and result['assertions'] == 42 and result['both_solvers_complete']
    assert result['real_ram_bits'] == 32768 and result['sha_replies_unconstrained_bits'] == 258
    assert result['directed_scenarios'] == 10 and result['detected_faulty_variants'] == 5
    assert not result['observer_drives_production']
    assert (package/'MANIFEST.json').read_bytes() == raw_manifest
    assert all(sha((package/name).read_bytes()) == value for name, value in checked.items())
    finished = {'passed': True, 'package_manifest_sha256': sha(raw_manifest), 'assertions': 42,
        'assumption_cells': 0, 'proof_and_complete_second_solver_passed': True,
        'real_ram_bits': 32768, 'sha_replies_unconstrained_bits': 258,
        'historical_generated_source_and_query_match': True, 'source_audit_passed': True,
        'observer_drives_production': False, 'directed_scenarios': 10,
        'simulation_faulty_controls_detected': 5, 'source_files_unchanged': True,
        'executions': executions, 'checked_sources': checked,
        'audit_finished_sha256': sha((audit/'FINISHED.json').read_bytes()),
        'hardware_access': False, 'network_access': False, 'sha_correctness_proved': False,
        'whole_machine_refinement': False, 'scope': result['scope']}
    (work/'FINISHED.json').write_text(json.dumps(finished, indent=2)+'\n')
    print('PAGE_BANK_REPLAY_FINISHED passed=True', flush=True)


if __name__ == '__main__':
    main()
