"""Source-derived UART/adapter component proof, without the machine backend."""
import argparse
import difflib
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

assert sys.flags.isolated and sys.flags.dont_write_bytecode and sys.flags.no_site and not sys.flags.optimize
ROOT = Path(__file__).resolve().parent
PACKAGE = ROOT.parents[1]
TOP = 'board1_public_command_frontend'


def sha(data): return hashlib.sha256(data).hexdigest()


def sources():
    raw = (PACKAGE / 'MANIFEST.json').read_bytes()
    manifest = json.loads(raw)['files']
    origins = {}
    def read(name):
        path = PACKAGE / name
        assert not path.is_symlink()
        data = path.read_bytes()
        assert sha(data) == manifest[name]['sha256'] and len(data) == manifest[name]['bytes']
        origins[name] = manifest[name]
        return data
    uart_dir = 'hardware/project/fpga/token_only_model0_mac_uart0/rtl/'
    original_bridge = read(uart_dir + 'token_only_model0_uart_bridge.sv')
    bridge = read('formal/frame/token_only_model0_uart_bridge.sv')
    before, after = [data.decode().splitlines(keepends=True) for data in (original_bridge, bridge)]
    delta = [row for row in difflib.SequenceMatcher(a=before, b=after, autojunk=False).get_opcodes() if row[0] != 'equal']
    assert len(delta) == 1 and delta[0][0] == 'insert'
    inserted = ''.join(after[delta[0][3]:delta[0][4]])
    assert inserted.count('assert(') == 46 and 'assume(' not in inserted
    adapter = read('hardware/project/fpga/token_only_model0_ddr_board1/product_top0/rtl/board1_fixed_command_adapter.sv')
    core = read('hardware/project/uart_core.sv').decode()
    start, stop = '    wire cmd_valid,cmd_ready,result_valid,result_ready;', '    board1_context2048_shared_token_probe #(.AUTH_BANKS(4)) u_machine ('
    assert core.count(start) == core.count(stop) == 1
    body = start + core.split(start, 1)[1].split(stop, 1)[0]
    for old, new in [
        ('    wire clear,decoded_clear,append_valid,append_ready,step_valid,step_ready,token_valid,token_ready;', '    wire decoded_clear;'),
        ('    wire [11:0] append_token,token;\n', '')]:
        assert body.count(old) == 1
        body = body.replace(old, new)
    backend = core.split(stop, 1)[1].split(');', 1)[0]
    bindings = dict(re.findall(r'\.(\w+)\(([^()]*)\)', backend))
    expected = {'clear_i': 'clear', 'append_valid_i': 'append_valid', 'append_ready_o': 'append_ready',
        'append_token_i': 'append_token', 'step_valid_i': 'step_valid', 'step_ready_o': 'step_ready',
        'token_valid_o': 'token_valid', 'token_ready_i': 'token_ready', 'token_o': 'token'}
    assert all(bindings.get(port) == net for port, net in expected.items())
    header = '''`timescale 1ns/1ps
`default_nettype none
module board1_public_command_frontend (
    input wire core_clk_i, reset_n_i, uart_rx_i,
    output wire uart_tx_o,
    input wire append_ready, step_ready, token_valid,
    input wire [11:0] token,
    output wire append_valid, step_valid, clear, token_ready,
    output wire [11:0] append_token
);
'''
    monitor = (ROOT / 'monitor.inc.sv').read_text()
    assert monitor.count('assert(') == 14 and 'assume(' not in monitor
    wrapper = header + body + monitor + '\nendmodule\n`default_nettype wire\n'
    result = {'frontend.sv': wrapper.encode(), 'production_bridge.sv': original_bridge,
        'production_uart_core.sv': core.encode(), 'production_adapter.sv': adapter,
        'monitor.inc.sv': monitor.encode(), 'token_only_model0_uart_bridge.sv': b'`undef FORMAL\n' + bridge,
        'board1_fixed_command_adapter.sv': b'`undef FORMAL\n' + adapter}
    for name in ('fixed_uart_rx.sv', 'fixed_uart_tx.sv'):
        data = read(uart_dir + name)
        assert data == read('formal/frame/' + name)
        result[name] = b'`undef FORMAL\n' + data
    assert origins == json.loads((ROOT / 'sources.json').read_text())
    return result, origins, expected


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--run', required=True, type=Path)
    parser.add_argument('--yosys', default='yosys')
    args = parser.parse_args()
    files, origins, bindings = sources()
    yosys = shutil.which(args.yosys)
    assert yosys
    script = '''read_verilog -formal -sv -D SYNTHESIS fixed_uart_rx.sv fixed_uart_tx.sv token_only_model0_uart_bridge.sv board1_fixed_command_adapter.sv frontend.sv
prep -top board1_public_command_frontend -flatten
async2sync
chformal -lower
dffunmap
select -assert-count 60 t:$assert
select -assert-none t:$assume
select -assert-none t:$anyseq
select -assert-none t:$anyconst
check -assert
write_json elaborated.json
write_rtlil elaborated.il
write_smt2 -wires design.smt2
sat -seq 3 -prove-asserts -verify -set-at 1 reset_n_i 0 -set-at 2 reset_n_i 0
sat -tempinduct -seq 3 -maxsteps 30 -timeout 120 -prove-asserts -verify -set-at 1 reset_n_i 0 -set-at 2 reset_n_i 0
'''
    files['prove.ys'] = script.encode()
    files['runner.py'] = Path(__file__).read_bytes()
    run = args.run.absolute()
    run.mkdir(parents=True, exist_ok=False)
    for name, data in files.items(): (run / name).write_bytes(data)
    inputs = {'files': {name: {'sha256': sha(data), 'bytes': len(data)} for name, data in files.items()},
        'origins': origins, 'backend_operation_bindings': bindings,
        'assertions': 60, 'bridge_assertions': 46, 'connection_assertions': 14,
        'backend_excluded': 'uart_core.u_machine; ready, token-valid and token-value are arbitrary component inputs',
        'retained_component_internal_cuts': [], 'assumption_cells_expected': 0,
        'environment': 'Two-state synchronous reasoning; reset initializes first two base steps, no other primary input restrictions; actual RX/TX and 217 clocks/bit retained.',
        'hardware_access': False, 'network_access': False}
    (run / 'INPUTS.json').write_text(json.dumps(inputs, indent=2, sort_keys=True) + '\n')
    started = time.monotonic()
    print('COMMAND_COMPOSITION_STARTED assertions=60 backend_excluded=1', flush=True)
    with (run / 'yosys.log').open('w') as log:
        child = subprocess.run([yosys, '-Q', 'prove.ys'], cwd=run, stdout=log, stderr=subprocess.STDOUT)
    log = (run / 'yosys.log').read_text()
    unchanged = all(sha((run / name).read_bytes()) == row['sha256'] for name, row in inputs['files'].items())
    success = 'Induction step proven: SUCCESS!' in log and child.returncode == 0 and unchanged
    result = {'passed': success, 'exit': child.returncode, 'seconds': time.monotonic()-started,
        'inputs_sha256': sha((run / 'INPUTS.json').read_bytes()), 'yosys_log_sha256': sha(log.encode()),
        'input_hashes_unchanged': unchanged, 'assertions': 60, 'hardware_access': False,
        'whole_machine_refinement': False,
        'scope': 'Joint actual UART/adapter front-end proof at the explicit backend operation boundary. No backend computation, token-vocabulary guarantee for arbitrary returns, whole-machine composition, mapped correspondence or physical signoff.'}
    (run / 'FINISHED.json').write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(json.dumps(result), flush=True)
    return 0 if success else 1


if __name__ == '__main__': raise SystemExit(main())
