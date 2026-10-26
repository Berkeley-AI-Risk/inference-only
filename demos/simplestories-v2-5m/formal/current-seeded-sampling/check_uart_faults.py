"""Actual CPB217 serial simulation controls for the formal UART monitor scope.

These are finite directed sensitivity counterexamples, not SAT/unbounded proofs.
No RX/TX/byte/feedback internal cut is introduced into the production bridge.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import time

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('seeded_formal_source_driver', HERE / 'run_proof.py')
driver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(driver)


def sha(data): return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', type=Path, required=True)
    args = parser.parse_args()
    inventory = driver.source_inputs()
    prefix = 'project/fpga/token_only_model0_mac_uart0/rtl/'
    sources = {name: (driver.SOURCE / (prefix + name)).read_bytes()
               for name in ('fixed_uart_rx.sv', 'fixed_uart_tx.sv', 'token_only_model0_uart_bridge.sv')}
    original = sources['token_only_model0_uart_bridge.sv'].decode()
    test = (HERE / 'test_settings_uart.sv').read_bytes()
    variants = {'actual': (original, None)}
    def mutant(name, old, new):
        if original.count(old) != 1: raise ValueError('Unexpected mutation anchor: ' + old)
        variants[name] = (original.replace(old, new), dict(old=old, new=new))
    mutant('settings-crc-bypass',
           'else if (request_unknown || rx_byte != request_crc_q)\n                            prepare_response(8\'hcf,12\'d0);',
           'else if (request_unknown)\n                            prepare_response(8\'hcf,12\'d0);')
    mutant('settings-seed-corruption', 'settings_seed_q <= request_seed_q;',
           "settings_seed_q <= request_seed_q ^ 128'd1;")
    mutant('settings-invalid-temperature-truncation', 'else if (request_token_low_q > 3)',
           'else if (request_token_low_q[1:0] > 3)')
    mutant('settings-overtakes-busy-step', 'if (state_q != BRIDGE_IDLE) begin end',
           "if (1'b0) begin end")
    mutant('settings-timeout-keeps-frame',
           'if (settings_timed_out) begin\n                request_index_q <= 0;',
           'if (settings_timed_out) begin\n                request_index_q <= request_index_q;')
    run = args.run.absolute()
    run.mkdir(parents=True, exist_ok=False)
    (run / 'checker.py').write_bytes(Path(__file__).read_bytes())
    inputs = dict(schema='seeded-uart-formal-sensitivity-controls-v1',
        frozen_assembly_sha256=driver.ASSEMBLY_SHA, frozen_inventory_sha256=driver.INVENTORY_SHA,
        production_sources={prefix + name: inventory[prefix + name] for name in sources},
        testbench_sha256=sha(test), clocks_per_bit=217,
        actual_expected_marker='PASS_SETTINGS_UART cases=284',
        variants={name: dict(mutated_source_sha256=sha(source.encode()), edit=edit)
                  for name, (source, edit) in variants.items()},
        sensitivity_method='Directed real-serial simulation, not SAT/formal proof', hardware_access=False)
    (run / 'INPUTS.json').write_text(json.dumps(inputs, indent=2, sort_keys=True) + '\n')
    start = time.monotonic()
    def solve(name):
        source, edit = variants[name]
        job = run / name
        job.mkdir()
        for path, data in sources.items():
            (job / path).write_bytes(source.encode() if path == 'token_only_model0_uart_bridge.sv' else data)
        (job / 'test_settings_uart.sv').write_bytes(test)
        begin = time.monotonic()
        compiled = subprocess.run(['iverilog', '-g2012', '-DSYNTHESIS', '-s', 'test_settings_uart',
            '-Ptest_settings_uart.CPB=217', '-o', 'test.vvp',
            'fixed_uart_rx.sv', 'fixed_uart_tx.sv', 'token_only_model0_uart_bridge.sv', 'test_settings_uart.sv'],
            cwd=job, capture_output=True)
        (job / 'build.log').write_bytes(compiled.stdout + compiled.stderr)
        exit_code, timed_out, data = None, False, b''
        if compiled.returncode == 0:
            try:
                child = subprocess.run(['vvp', 'test.vvp'], cwd=job, capture_output=True, timeout=120)
                exit_code, data = child.returncode, child.stdout + child.stderr
            except subprocess.TimeoutExpired as error:
                timed_out = True
                data = (error.stdout or b'') + (error.stderr or b'')
        (job / 'simulation.log').write_bytes(data)
        marker = b'PASS_SETTINGS_UART cases=284' in data
        detected = edit is not None and exit_code not in (None, 0) and b'FATAL:' in data and not timed_out
        passed = compiled.returncode == 0 and ((exit_code == 0 and marker) if edit is None else detected)
        result = dict(passed=passed, build_exit=compiled.returncode, exit=exit_code,
            timed_out=timed_out, actual_suite_passed=marker and exit_code == 0,
            deliberately_faulty_copy_detected=detected, seconds=time.monotonic() - begin,
            simulation_log_sha256=sha(data), build_log_sha256=sha(compiled.stdout + compiled.stderr),
            first_fatal=next((line for line in data.decode(errors='replace').splitlines() if 'FATAL:' in line), None))
        (job / 'FINISHED.json').write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
        print(name + ' ' + json.dumps(result), flush=True)
        return name, result
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = dict(pool.map(solve, variants))
    record = dict(passed=all(row['passed'] for row in results.values()), results=results,
        actual_settings_cases=284, faulty_controls=5, clocks_per_bit=217,
        seconds=time.monotonic() - start, inputs_sha256=sha((run / 'INPUTS.json').read_bytes()),
        hardware_access=False, formal_proof=False,
        scope='Finite directed actual serial RX/TX sensitivity checks for the separately proved component invariants.')
    (run / 'FINISHED.json').write_text(json.dumps(record, indent=2, sort_keys=True) + '\n')
    print(json.dumps({key: value for key, value in record.items() if key != 'results'}), flush=True)
    return 0 if record['passed'] else 1


if __name__ == '__main__': raise SystemExit(main())
