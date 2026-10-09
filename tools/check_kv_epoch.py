#!/usr/bin/env python3
"""Portable local K/V proof, second solver, sensitivity and source audit."""
import argparse
import hashlib
import json
from pathlib import Path
import runpy
import subprocess
import sys
import time

assert sys.flags.isolated and sys.flags.dont_write_bytecode and not sys.flags.optimize


def sha(data): return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', required=True, type=Path)
    parser.add_argument('--work', required=True, type=Path)
    parser.add_argument('--yosys', default='yosys')
    parser.add_argument('--z3', default='z3')
    parser.add_argument('--cvc5', default='cvc5')
    args = parser.parse_args()
    package, work = args.package.resolve(strict=True), args.work.resolve()
    assert work != package and not work.is_relative_to(package)
    raw_manifest = (package / 'MANIFEST.json').read_bytes()
    manifest = json.loads(raw_manifest)['files']
    def read(name):
        path = package / name
        assert not path.is_symlink()
        data = path.read_bytes()
        assert sha(data) == manifest[name]['sha256'] and len(data) == manifest[name]['bytes']
        return data
    formal = package / 'formal/kv-epoch'
    for name in ('sources.json', 'epoch_monitor.inc.sv', 'proof_driver.py', 'checks.py', 'audit.py'):
        read('formal/kv-epoch/' + name)
    sources = json.loads(read('formal/kv-epoch/sources.json'))
    for row in sources.values(): assert sha(read(row['package_source'])) == row['sha256']
    read('tools/replay_diagnostics.py')
    diagnostics = runpy.run_path(str(package / 'tools/replay_diagnostics.py'))
    work.mkdir(parents=False, exist_ok=False)
    (work / 'wrapper.py').write_bytes(Path(__file__).read_bytes())
    python = [sys.executable, '-I', '-B', '-S']
    executions = {}
    def execute(label, argv):
        started = time.monotonic()
        with (work / (label + '.log')).open('w') as output:
            result = subprocess.run(argv, stdout=output, stderr=subprocess.STDOUT)
        executions[label] = {'exit': result.returncode, 'seconds': time.monotonic() - started,
                             'log_sha256': sha((work / (label + '.log')).read_bytes())}
        assert result.returncode == 0, diagnostics['stage_failure'](
            label, result.returncode, work / (label + '.log'),
            work / 'checks' if label == 'checks' else None)
    proof, checks, audit = work / 'proof', work / 'checks', work / 'audit'
    execute('proof', python + [str(formal / 'proof_driver.py'), '--run', str(proof),
        '--split-induction', '--jobs', '12', '--yosys', args.yosys, '--z3', args.z3])
    inputs = json.loads((proof / 'INPUTS.json').read_text())
    assert inputs['origins'] == sources and inputs['source_package_sha256'] == sha(raw_manifest)
    assert (proof / 'monitor.inc.sv').read_bytes() == read('formal/kv-epoch/epoch_monitor.inc.sv')
    execute('checks', python + [str(formal / 'checks.py'), '--proof', str(proof), '--run', str(checks),
        '--yosys', args.yosys, '--z3', args.z3, '--cvc5', args.cvc5])
    audit_argv = python + [str(formal / 'audit.py'), '--package', str(package), '--proof', str(proof),
        '--checks', str(checks), '--run', str(audit), '--yosys', args.yosys]
    execute('audit', audit_argv)
    execute('audit-verify-only', audit_argv + ['--verify-only'])
    receipt = json.loads((audit / 'FINISHED.json').read_text())
    assert receipt['audit_passed'] and receipt['assertions'] == 59 and receipt['assumption_cells'] == 0
    assert receipt['second_solver_all_60_queries_passed'] and not receipt['observer_drives_production']
    assert receipt['reset_reachable_faulty_controls_detected'] == 5 and receipt['retained_staging_reuse_witnesses'] == 2
    assert (package / 'MANIFEST.json').read_bytes() == raw_manifest
    finished = {'passed': True, 'assertions': 59, 'assumption_cells': 0,
                'proof_and_complete_second_solver_passed': True, 'observer_drives_production': False,
                'bounded_faulty_controls_detected': 5, 'retained_staging_reuse_witnesses': 2,
                'source_audit_passed': True, 'audit_finished_sha256': sha((audit / 'FINISHED.json').read_bytes()),
                'executions': executions, 'hardware_access': False, 'network_access': False,
                'whole_machine_refinement': False, 'scope': receipt['scope']}
    (work / 'FINISHED.json').write_text(json.dumps(finished, indent=2) + '\n')
    print('KV_EPOCH_REPLAY_FINISHED passed=True', flush=True)


if __name__ == '__main__': main()
