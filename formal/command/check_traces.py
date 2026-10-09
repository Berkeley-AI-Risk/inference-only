"""Directed reachable serial traces for the exact frontend and five faulty controls."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

assert sys.flags.isolated and sys.flags.dont_write_bytecode and sys.flags.no_site and not sys.flags.optimize


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--run', required=True, type=Path)
    parser.add_argument('--iverilog', default='iverilog')
    parser.add_argument('--vvp', default='vvp')
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    spec = importlib.util.spec_from_file_location('frontend_source_derivation', here / 'run_proof.py')
    proof = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(proof)
    shared, origins, _ = proof.sources()
    sha = proof.sha
    changes = {
        'actual': None,
        'append-xor': ('board1_fixed_command_adapter.sv', 'append_token_o = cmd_token_i;', "append_token_o = cmd_token_i ^ 12'd1;", 'WRONG_APPEND_OPERAND'),
        'append-as-step': ('board1_fixed_command_adapter.sv', 'append_valid_o = cmd_valid_i;', 'step_valid_o = cmd_valid_i;', 'WRONG_STEP_OPERATION'),
        'drop-clear': ('frontend.sv', '.clear_command_o(clear)', '.clear_command_o()', 'TRACE_TIMEOUT'),
        'return-xor': ('board1_fixed_command_adapter.sv', "token_valid_i ? token_i : 12'd0", "token_valid_i ? (token_i ^ 12'd1) : 12'd0", 'WRONG_REPLY_BYTE'),
        'drop-token-ready': ('board1_fixed_command_adapter.sv', 'token_ready_o = result_ready_i;', "token_ready_o = 1'b0;", 'TOKEN_READY_MISMATCH'),
    }
    run = args.run.absolute()
    run.mkdir(parents=True, exist_ok=False)
    (run / 'checker.py').write_bytes(Path(__file__).read_bytes())
    (run / 'deriver.py').write_bytes((here / 'run_proof.py').read_bytes())
    tb = (here / 'tb_frontend.sv').read_bytes()
    jobs = {}
    for name, change in changes.items():
        directory = run / name
        directory.mkdir()
        files = dict(shared, **{'tb_frontend.sv': tb})
        if change:
            filename, before, after, _ = change
            text = files[filename].decode()
            assert text.count(before) == 1
            text = text.replace(before, after)
            if name == 'drop-clear':
                assert text.count('    wire decoded_clear;') == 1
                text = text.replace('    wire decoded_clear;', "    wire decoded_clear;\n    assign clear = 1'b0;")
            files[filename] = text.encode()
        for filename, data in files.items(): (directory / filename).write_bytes(data)
        jobs[name] = {'files': {filename: sha(data) for filename, data in files.items()},
                      'expected_error': None if not change else change[-1]}
    inputs = {'jobs': jobs, 'origins': origins, 'checker_sha256': sha(Path(__file__).read_bytes()),
              'deriver_sha256': sha((here / 'run_proof.py').read_bytes()), 'testbench_sha256': sha(tb),
              'hardware_access': False, 'workers': 6, 'scope': 'Reachable serial simulation, not bounded SAT. No internal forced DUT values.'}
    (run / 'INPUTS.json').write_text(json.dumps(inputs, indent=2, sort_keys=True) + '\n')
    def execute(name):
        directory = run / name
        compile_argv = [shutil.which(args.iverilog), '-g2012', '-gno-assertions', '-DSYNTHESIS', '-s', 'tb_frontend', '-o', 'sim.vvp',
                       'fixed_uart_rx.sv', 'fixed_uart_tx.sv', 'token_only_model0_uart_bridge.sv', 'board1_fixed_command_adapter.sv', 'frontend.sv', 'tb_frontend.sv']
        with (directory / 'compile.log').open('w') as log:
            build = subprocess.run(compile_argv, cwd=directory, stdout=log, stderr=subprocess.STDOUT)
        code = None
        if build.returncode == 0:
            with (directory / 'trace.log').open('w') as log:
                child = subprocess.run([shutil.which(args.vvp), 'sim.vvp'], cwd=directory, stdout=log, stderr=subprocess.STDOUT, timeout=60)
            code = child.returncode
        log = (directory / 'trace.log').read_text() if code is not None else ''
        expected = jobs[name]['expected_error']
        lines = [line for line in log.splitlines() if not re.fullmatch(r'tb_frontend\.sv:\d+: \$finish called at \d+ \(1ps\)', line)]
        passed = (code == 0 and lines == ['PASS_COMMAND_FRONTEND cases=10 bytes=45 operations=5 cpb=217']) if expected is None else (code not in (None, 0) and expected in log and 'GLOBAL_TIMEOUT' not in log and 'PASS_COMMAND_FRONTEND' not in log)
        unchanged = all(sha((directory / filename).read_bytes()) == digest for filename, digest in jobs[name]['files'].items())
        return name, {'passed': passed and unchanged, 'compile_exit': build.returncode, 'trace_exit': code,
                      'source_unchanged': unchanged, 'trace_log_sha256': sha(log.encode()), 'compile_log_sha256': sha((directory / 'compile.log').read_bytes())}
    with ThreadPoolExecutor(max_workers=6) as pool: results = dict(pool.map(execute, jobs))
    passed = all(row['passed'] for row in results.values())
    result = {'passed': passed, 'jobs': results, 'inputs_sha256': sha((run / 'INPUTS.json').read_bytes()),
              'hardware_access': False, 'scope': inputs['scope']}
    (run / 'FINISHED.json').write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(json.dumps(result, indent=2), flush=True)
    return 0 if passed else 1


if __name__ == '__main__': raise SystemExit(main())
