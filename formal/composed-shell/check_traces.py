"""Real-UART/real-controller directed tests and five connection fault controls."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time

assert sys.flags.isolated and sys.flags.dont_write_bytecode and sys.flags.no_site and not sys.flags.optimize
ROOT = Path(__file__).resolve().parent


def sha(data): return hashlib.sha256(data).hexdigest()
def put(path, obj): path.write_text(json.dumps(obj, indent=2, sort_keys=True) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', type=Path, required=True)
    parser.add_argument('--verilator', default='verilator')
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('trace_source_deriver', ROOT / 'run_proof.py')
    driver = importlib.util.module_from_spec(spec); spec.loader.exec_module(driver)
    files, sources, binding = driver.derive()
    body = (ROOT / 'tb_body.sv').read_bytes()
    declarations = '\n'.join('    ' + ('reg' if direction == 'input' else 'wire') + ' ' + shape + name +
        ('=0;' if direction == 'input' else ';') for name, (direction, shape) in binding['wrapper_ports'].items())
    bench = ('`timescale 1ns/1ps\nmodule tb_connected;\n' + declarations + '\n').encode() + body
    core, shell = [driver.MACHINE_DIR + name + '.sv' for name in (driver.CORE_NAME, driver.SHELL_NAME)]
    variants = {
        'actual': None,
        'wrapper-changes-operand': ('composition.sv', '.append_token_i(append_token)', ".append_token_i(append_token ^ 12'd1)", 'TAPE_CONTENT'),
        'core-changes-operand': (core, '.append_token_i(append_token_i)', ".append_token_i(append_token_i ^ 12'd1)", 'TAPE_CONTENT'),
        'wrapper-drops-clear': ('composition.sv', '.clear_i(clear)', ".clear_i(1'b0)", 'TAPE_COUNT'),
        'tape-wrong-slot': (shell, 'token_tape_q[tape_count_q] <= append_token_i;', "token_tape_q[tape_count_q + 12'd1] <= append_token_i;", 'TAPE_CONTENT'),
        'spontaneous-core-token': (core, 'token_valid_o = machine_active && !aggregate_fail &&\n                        shell_token_valid;', "token_valid_o = 1'b1;", 'UNSOLICITED_CORE_RESULT'),
    }
    run = args.run.absolute(); run.mkdir(parents=True, exist_ok=False)
    assert not any(c.isspace() for c in str(run)), 'Use a whitespace-free work path or existing alias.'
    (run / 'checker.py').write_bytes(Path(__file__).read_bytes())
    (run / 'deriver.py').write_bytes((ROOT / 'run_proof.py').read_bytes())
    (run / 'tb_body.sv').write_bytes(body)
    inventory = {'binding': binding, 'testbench_sha256': sha(bench), 'jobs': {}, 'hardware_access': False,
        'simulator': 'Verilator --timing; assertions enabled for actual design. Fault controls use independent testbench checks with RTL assertions disabled. Two-state finite simulation, not an unbounded proof.'}
    for label, mutation in variants.items():
        job = run / label; job.mkdir()
        inputs = dict(files, **{'tb_connected.sv': bench})
        if mutation:
            name, old, new, expected = mutation
            assert inputs[name].count(old.encode()) == 1, (label, name)
            inputs[name] = inputs[name].replace(old.encode(), new.encode())
        for name, data in inputs.items():
            path = job / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(data)
        inventory['jobs'][label] = {'files': {name: sha(data) for name, data in inputs.items()},
            'mutation': mutation, 'expected_error': mutation[-1] if mutation else None}
    put(run / 'INPUTS.json', inventory)
    print('PUBLIC_SHELL_TRACES_STARTED workers=6 cpb=217 real_serial_output=1', flush=True)
    def check(label):
        job = run / label; start = time.monotonic()
        with (job / 'compile.log').open('w') as log:
            makeflags = 'CURDIR=' + str(job / 'obj_dir')
            assertion_mode = '--assert' if label == 'actual' else '--no-assert'
            # Disable gate optimization to avoid the Verilator 5.050
            # V3Gate.cpp:987 internal error on the dropped-CLEAR control.
            code = subprocess.run([shutil.which(args.verilator), '--binary', '--timing', assertion_mode, '-fno-gate', '-j', '4', '-MAKEFLAGS', makeflags, '-Wno-fatal', '-DSYNTHESIS', '--top-module', 'tb_connected'] + sources + ['tb_connected.sv'], cwd=job, stdout=log, stderr=subprocess.STDOUT, timeout=180).returncode
        assert code == 0, (label, 'compile failed')
        with (job / 'trace.log').open('w') as log:
            try: result = subprocess.run(['obj_dir/Vtb_connected'], cwd=job, stdout=log, stderr=subprocess.STDOUT, timeout=120).returncode
            except subprocess.TimeoutExpired: result = 124
        output = (job / 'trace.log').read_text()
        expected = inventory['jobs'][label]['expected_error']
        if expected is None:
            passed = result == 0 and output.count('PASS_PUBLIC_SHELL cases=13 serial_bytes=60 operations=7 cpb=217') == 1
            passed = passed and 'ERROR:' not in output and 'FATAL:' not in output
        else:
            passed = result not in (0,124) and expected in output and 'GLOBAL_TIMEOUT' not in output and 'PASS_PUBLIC_SHELL' not in output
        unchanged = all(sha((job / name).read_bytes()) == digest for name, digest in inventory['jobs'][label]['files'].items())
        row = {'passed': passed and unchanged, 'compile_exit': code, 'trace_exit': result,
            'seconds': time.monotonic()-start, 'source_unchanged': unchanged,
            'compile_log_sha256': sha((job / 'compile.log').read_bytes()), 'trace_log_sha256': sha(output.encode())}
        put(job / 'FINISHED.json', row)
        print('PUBLIC_SHELL_TRACE ' + label + ' ' + json.dumps(row), flush=True)
        return label, row
    with ThreadPoolExecutor(max_workers=6) as pool: results = dict(pool.map(check, variants))
    record = {'passed': all(row['passed'] for row in results.values()), 'jobs': results,
        'inputs_sha256': sha((run / 'INPUTS.json').read_bytes()), 'hardware_access': False,
        'scope': 'Thirteen reachable serial scenarios, actual TX-pin sampling, actual tape contents, and five faulty controls. Finite simulation, not a numerical model or unbounded serial-waveform proof.'}
    put(run / 'FINISHED.json', record)
    return 0 if record['passed'] else 1


if __name__ == '__main__': raise SystemExit(main())
