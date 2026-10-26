"""Replay scoped seeded formal checks from the supplied public RTL only.

Default: complete primary checks, both component solvers, source/observer audits,
and negative controls. --secondary additionally attempts every connected
cvc5 conclusion with bounded supplements. Unknowns remain explicitly unresolved.
No installation, hardware, network, programming or publication is performed.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import time

assert sys.flags.isolated and sys.flags.no_site and sys.flags.dont_write_bytecode and not sys.flags.optimize
HERE = Path(__file__).resolve().parent


def sha(raw): return hashlib.sha256(raw).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', type=Path, required=True, help='New directory under this formal lane')
    parser.add_argument('--secondary', action='store_true', help='Attempt all connected cvc5 conclusions and bounded supplements')
    parser.add_argument('--require-recorded-model', action='store_true', help='Require exact recorded Yosys model digests')
    args = parser.parse_args()
    run = args.run.absolute()
    if HERE not in run.parents: parser.error('--run must be below formal/seeded-sampling/')
    spec = importlib.util.spec_from_file_location('public_seeded_sources', HERE / 'source_provider.py')
    provider = importlib.util.module_from_spec(spec); spec.loader.exec_module(provider)
    binding = provider.source_binding()
    run.mkdir(parents=True, exist_ok=False)
    (run / 'runner.py').write_bytes(Path(__file__).read_bytes())
    (run / 'SOURCE-BINDING.json').write_text(json.dumps(binding, indent=2, sort_keys=True) + '\n')
    rows = []
    started = time.monotonic()
    def step(label, script, *arguments, allow_incomplete_secondary=False):
        command = [sys.executable, '-I', '-S', '-B', str(HERE / script), *map(str, arguments)]
        print('REPLAY_STEP ' + label, flush=True)
        begin = time.monotonic()
        with (run / (label + '.log')).open('w') as stream:
            result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT)
        row = dict(label=label, script=script, arguments=[str(arg.relative_to(HERE)) if isinstance(arg, Path) else str(arg) for arg in arguments],
                   exit=result.returncode, seconds=time.monotonic() - begin,
                   log_sha256=sha((run / (label + '.log')).read_bytes()),
                   incomplete_secondary_allowed=allow_incomplete_secondary)
        rows.append(row)
        (run / 'STEPS.json').write_text(json.dumps(rows, indent=2, sort_keys=True) + '\n')
        if result.returncode and not allow_incomplete_secondary:
            (run / 'FINISHED.json').write_text(json.dumps(dict(passed=False, failed_step=label,
                steps=rows, seconds=time.monotonic() - started, hardware_access=False), indent=2) + '\n')
            raise RuntimeError('Replay failed: ' + label + '; inspect preserved log')
    for case in ('selector', 'selector-buffer', 'uart', 'shell'):
        target = run / case
        arguments = ['--case', case, '--run', target, '--induction', '2' if case == 'shell' else '3',
                     '--timeout', '60', '--solvers', 'z3,cvc5']
        if case in ('uart', 'shell'): arguments.append('--cvc5-base-only')
        step(case, 'run_proof.py', *arguments)
        step('audit-' + case, 'audit_components.py', '--proof', target, '--run', run / ('audit-' + case))
        if case in ('uart', 'shell'):
            step('conclusions-' + case, 'check_conclusions.py', '--proof', target,
                 '--run', run / ('conclusions-' + case), '--timeout', '60', '--workers', '2')
    step('selector-controls', 'check_selector_faults.py', '--run', run / 'selector-controls')
    step('buffer-controls', 'check_selector_faults.py', '--buffer-ownership', '--run', run / 'buffer-controls')
    step('uart-controls', 'check_uart_faults.py', '--run', run / 'uart-controls')
    primary, audit = run / 'connected-primary', run / 'connected-audit'
    step('connected-primary', 'connected/run_connected.py', '--run', primary, '--induction', '2', '--solvers', 'z3', '--timeout', '120')
    step('connected-audit', 'connected/audit_connected.py', '--proof', primary, '--run', audit)
    secondary = []
    if args.secondary:
        for label, extra in (
            ('connected-secondary', ['--mode', 'arrays', '--timeout', '60', '--workers', '2']),
            ('connected-supplement-0-8', ['--only', '0,8', '--mode', 'arrays', '--timeout', '300', '--workers', '2']),
            ('connected-supplement-0-8-38-66', ['--only', '0,8,38,66', '--mode', 'ho-elim', '--timeout', '120', '--workers', '2']),
            ('connected-supplement-72-73', ['--only', '72,73', '--mode', 'ho-elim', '--timeout', '120', '--workers', '2'])):
            destination = run / label
            step(label, 'connected/check_connected_conclusions.py', '--proof', primary, '--run', destination,
                 *extra, allow_incomplete_secondary=True)
            secondary += ['--secondary', destination]
    step('connected-summary', 'connected/summarize_connected.py', '--proof', primary, '--audit', audit,
         *secondary, '--output', run / 'CONNECTED.json')
    step('receipt', 'check_replay.py', '--run', run, '--output', run / 'RESULTS.json',
         *(['--require-recorded-model'] if args.require_recorded_model else []))
    result = json.loads((run / 'RESULTS.json').read_text())
    final = dict(passed=result['primary_scoped_checks_passed'], steps=rows,
        results_sha256=sha((run / 'RESULTS.json').read_bytes()), seconds=time.monotonic() - started,
        connected_secondary_attempted=result['connected']['secondary']['attempted_conclusions'],
        connected_secondary_passed=result['connected']['secondary']['passed_conclusions'],
        connected_secondary_complete=result['connected']['secondary']['complete'],
        hardware_access=False, network_access=False, vendor_logic_elaborated=False)
    (run / 'FINISHED.json').write_text(json.dumps(final, indent=2, sort_keys=True) + '\n')
    print('PUBLIC_SEEDED_FORMAL_REPLAY_PASS secondary=' + str(final['connected_secondary_passed']) + '/196 complete=' + str(final['connected_secondary_complete']), flush=True)


if __name__ == '__main__': main()
