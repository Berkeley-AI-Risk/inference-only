#!/usr/bin/env python3
"""Replay the actual UART/adapter component proof, serial controls and two solvers."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time

assert sys.flags.isolated and sys.flags.dont_write_bytecode and sys.flags.no_site
assert not sys.flags.optimize


def sha(data): return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', required=True, type=Path)
    parser.add_argument('--work', required=True, type=Path)
    for name in ('yosys', 'z3', 'cvc5', 'iverilog', 'vvp'):
        parser.add_argument('--' + name, default=name)
    args = parser.parse_args()
    package, work = args.package.resolve(strict=True), args.work.resolve()
    assert work != package and not work.is_relative_to(package)
    raw_manifest = (package / 'MANIFEST.json').read_bytes()
    manifest = json.loads(raw_manifest)['files']
    consumed = {}

    def read(name):
        path = package / name
        assert path.is_file() and not path.is_symlink()
        data = path.read_bytes()
        assert sha(data) == manifest[name]['sha256'] and len(data) == manifest[name]['bytes']
        consumed[name] = sha(data)
        return data

    formal = package / 'formal/command'
    for name in ('sources.json', 'monitor.inc.sv', 'tb_frontend.sv',
                 'run_proof.py', 'check_traces.py', 'audit_proof.py'):
        read('formal/command/' + name)
    sources = json.loads(read('formal/command/sources.json'))
    for name, row in sources.items():
        assert sha(read(name)) == row['sha256'] and manifest[name] == row
    work.mkdir(parents=False, exist_ok=False)
    (work / 'wrapper.py').write_bytes(Path(__file__).read_bytes())
    python = [sys.executable, '-I', '-B', '-S']
    executions = {}

    def execute(label, argv):
        started = time.monotonic()
        with (work / (label + '.log')).open('w') as output:
            result = subprocess.run(argv, stdout=output, stderr=subprocess.STDOUT)
        executions[label] = {'exit': result.returncode, 'argv': argv,
                             'seconds': time.monotonic() - started,
                             'log_sha256': sha((work / (label + '.log')).read_bytes())}
        assert result.returncode == 0, (label, result.returncode)

    proof, traces, audit = work / 'proof', work / 'traces', work / 'audit'
    execute('proof', python + [str(formal / 'run_proof.py'), '--run', str(proof), '--yosys', args.yosys])
    inputs = json.loads((proof / 'INPUTS.json').read_text())
    assert inputs['origins'] == sources and inputs['assertions'] == 60
    assert inputs['bridge_assertions'] == 46 and inputs['connection_assertions'] == 14
    assert not inputs['retained_component_internal_cuts'] and inputs['assumption_cells_expected'] == 0
    execute('traces', python + [str(formal / 'check_traces.py'), '--run', str(traces),
        '--iverilog', args.iverilog, '--vvp', args.vvp])
    audit_argv = python + [str(formal / 'audit_proof.py'), '--proof', str(proof),
        '--traces', str(traces), '--run', str(audit), '--z3', args.z3, '--cvc5', args.cvc5]
    execute('audit', audit_argv)
    execute('audit-verify-only', audit_argv + ['--verify-only'])
    receipt = json.loads((audit / 'FINISHED.json').read_text())
    assert receipt['audit_passed'] and receipt['assertions'] == 60
    assert receipt['five_faulty_controls_detected'] and receipt['ten_reachable_serial_scenarios_pass']
    assert not receipt['whole_machine_refinement'] and not receipt['hardware_access']
    expected_queries = {'z3-base', 'z3-induction', 'cvc5-base'} | {
        f'cvc5-induction-{index:02}' for index in range(60)}
    assert set(receipt['solver_results']) == expected_queries
    assert all(row['passed'] for row in receipt['solver_results'].values())
    assert (package / 'MANIFEST.json').read_bytes() == raw_manifest
    assert all(sha((package / name).read_bytes()) == digest for name, digest in consumed.items())
    finished = {'passed': True, 'assertions': 60, 'bridge_assertions': 46,
        'connection_assertions': 14, 'assumption_cells': 0,
        'proof_and_complete_second_solver_passed': True,
        'source_and_operation_bindings_checked': True, 'backend_excluded': True,
        'serial_scenarios': 10, 'simulation_faulty_controls_detected': 5,
        'source_audit_passed': True, 'executions': executions,
        'audit_finished_sha256': sha((audit / 'FINISHED.json').read_bytes()),
        'package_manifest_sha256': sha(raw_manifest), 'consumed_sha256': consumed,
        'hardware_access': False, 'network_access': False, 'whole_machine_refinement': False,
        'scope': receipt['scope']}
    (work / 'FINISHED.json').write_text(json.dumps(finished, indent=2, sort_keys=True) + '\n')
    print('PUBLIC_COMMAND_REPLAY_FINISHED passed=True', flush=True)


if __name__ == '__main__': main()
