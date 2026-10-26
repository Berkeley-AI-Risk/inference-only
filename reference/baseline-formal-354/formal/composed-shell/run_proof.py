"""Exact-image UART/core/token-shell composition at explicit private seams."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import datetime
import difflib
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

assert sys.flags.isolated and sys.flags.dont_write_bytecode and sys.flags.no_site and not sys.flags.optimize
ROOT = Path(__file__).resolve().parent
PACKAGE = ROOT.parents[1]
TOP = 'board1_public_shell_composition'
IMAGE = '6ba3caa4f88ac58dd30336c3ff4478f836779db0d04309ff457ca065ec1f7f09'
CORE_NAME = 'board1_context2048_token_machine_core'
SHELL_NAME = 'board1_context2048_token_shell'
LAYER_NAME = 'board1_context2048_semantic_layer'
MACHINE_DIR = 'fpga/token_only_model0_ddr_board1/context2048_token_machine2/rtl/'
UART_DIR = 'fpga/token_only_model0_mac_uart0/rtl/'


def sha(data): return hashlib.sha256(data).hexdigest()
def encoded(obj): return (json.dumps(obj, indent=2, sort_keys=True) + '\n').encode()


def ports(source):
    """Strict parser for these pinned ANSI headers, not a general SV parser."""
    header = source.split('\n);', 1)[0].split(') (', 1)[1]
    header = re.sub(r'//[^\n]*', '', header)
    result = {}
    for item in header.split(','):
        match = re.fullmatch(r'\s*(input|output)\s+(?:wire|logic)\s*(signed\s+)?(\[[^\]]+\]\s*)?(\w+)\s*', item)
        assert match, item
        direction, signed, width, name = match.groups()
        assert name not in result
        result[name] = (direction, (signed or '') + (width or ''))
    return result


def instance(source, module, name):
    marker = '    ' + module + ' '
    assert source.count(marker) == 1, (module, name)
    start = source.index(marker)
    match = re.search(r'\b' + name + r'\s*\(', source[start:])
    assert match
    opening = start + match.end() - 1
    depth, cursor = 1, opening + 1
    while depth:
        if source[cursor] == '(': depth += 1
        if source[cursor] == ')': depth -= 1
        cursor += 1
    assert source[cursor:cursor+1] == ';'
    raw = source[start:cursor+1]
    body = source[opening+1:cursor-1]
    matches = list(re.finditer(r'\.(\w+)\s*\(([^()]*)\)', body))
    assert re.sub(r'[\s,]', '', re.sub(r'\.(\w+)\s*\(([^()]*)\)', '', body)) == ''
    bindings = {m[1]: re.sub(r'\s+', ' ', m[2]).strip() for m in matches}
    assert len(matches) == len(bindings)
    return raw, bindings


def derive():
    checked = {}
    def read(path, expected=None):
        assert path.is_file() and not path.is_symlink(), path
        data = path.read_bytes()
        if expected is not None: assert sha(data) == expected, path
        checked[path.relative_to(PACKAGE).as_posix()] = sha(data)
        return data
    manifest_raw = read(PACKAGE / 'MANIFEST.json')
    manifest_record = json.loads(manifest_raw)
    assert manifest_record['prebuilt_image_sha256'] == IMAGE
    manifest = manifest_record['files']
    def packaged(name):
        data = read(PACKAGE / name, manifest[name]['sha256'])
        assert len(data) == manifest[name]['bytes']
        return data
    hardware_inventory = packaged('host-app/hardware-inputs.json')
    assert sha(hardware_inventory) == '502451a0a484c424b8b210792568f268d01b70d0ff7913d423a7160a0d2ed678'
    hardware = json.loads(hardware_inventory)
    assert len(hardware) == 90
    production = {}
    for name, digest in hardware.items():
        if name.startswith('project/official/'):
            continue
        data = packaged('hardware/' + name)
        assert sha(data) == digest, name
        production[name.removeprefix('project/')] = data
    assert len(production) == 86
    previous_sources = json.loads(packaged('formal/token-shell/sources.json'))
    files, compile_sources = {}, []
    for name, row in previous_sources.items():
        assert sha(production[name]) == row['sha256']
        files[name] = production[name]
        if name.endswith('.sv'): compile_sources.append(name)
    monitor = packaged('formal/token-shell/control_monitor.inc.sv') + b'\n' + packaged('formal/token-shell/tape_monitor.inc.sv')
    assert monitor.count(b'assert(') == 48 and b'assume(' not in monitor
    shell_path = MACHINE_DIR + SHELL_NAME + '.sv'
    assert files[shell_path].count(b'\nendmodule') == 1
    shell_ports = ports(files[shell_path].decode())
    shell_links = {name: shell_ports[name][1] for name in
        ('clear_i', 'append_valid_i', 'append_token_i', 'step_valid_i', 'token_ready_i')}
    shell_links.update({'append_transfer': '', 'step_transfer': ''})
    shell_observed = files[shell_path].decode().replace('\n);', ''.join(
        ',\n    output wire ' + shape + 'f_link_' + name + '_o' for name, shape in shell_links.items()) + '\n);', 1)
    shell_observed = shell_observed.replace('\nendmodule', '\n' + '\n'.join(
        '    assign f_link_' + name + '_o = ' + name + ';' for name in shell_links) + '\n' + monitor.decode() + '\nendmodule')
    files[shell_path] = shell_observed.encode()
    files['shell_monitor.inc.sv'] = monitor
    for name in ('fixed_uart_rx.sv', 'fixed_uart_tx.sv'):
        assert production[UART_DIR + name] == packaged('formal/frame/' + name)
        files[UART_DIR + name] = production[UART_DIR + name]
        compile_sources.append(UART_DIR + name)
    bridge = packaged('formal/frame/token_only_model0_uart_bridge.sv')
    before = production[UART_DIR + 'token_only_model0_uart_bridge.sv'].decode().splitlines(keepends=True)
    after = bridge.decode().splitlines(keepends=True)
    delta = [row for row in difflib.SequenceMatcher(a=before, b=after, autojunk=False).get_opcodes() if row[0] != 'equal']
    assert len(delta) == 1 and delta[0][0] == 'insert'
    added = ''.join(after[delta[0][3]:delta[0][4]])
    assert added.count('assert(') == 46 and 'assume(' not in added
    files[UART_DIR + 'token_only_model0_uart_bridge.sv'] = bridge
    compile_sources.append(UART_DIR + 'token_only_model0_uart_bridge.sv')
    more = ['fpga/token_only_model0_ddr_board1/product_top0/rtl/board1_fixed_command_adapter.sv',
        'fpga/token_only_model0_ddr_board1/ddr_preboard_closure0/rtl/board1_ddr_request_fifo2.sv',
        'fpga/token_only_model0_ddr_board1/fixed_token_machine0/rtl/board1_fixed_private_ddr_arbiter.sv']
    for name in more:
        files[name] = production[name]; compile_sources.append(name)
    uart, shared = (production[name].decode() for name in ('uart_core.sv', 'shared_token_probe.sv'))
    core = production[MACHINE_DIR + CORE_NAME + '.sv'].decode()
    layer = production['fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/' + LAYER_NAME + '.sv'].decode()
    _, uart_bindings = instance(uart, 'board1_context2048_shared_token_probe', 'u_machine')
    public = {'clear_i': 'clear', 'append_valid_i': 'append_valid', 'append_ready_o': 'append_ready',
        'append_token_i': 'append_token', 'step_valid_i': 'step_valid', 'step_ready_o': 'step_ready',
        'token_valid_o': 'token_valid', 'token_ready_i': 'token_ready', 'token_o': 'token'}
    assert all(uart_bindings[port] == net for port, net in public.items())
    assert uart_bindings['core_clk_i'] == 'core_clk_i' and uart_bindings['reset_n_i'] == 'reset_n_i'
    actual_instance, bindings = instance(shared, CORE_NAME, 'u_machine')
    assert all(bindings[port] == port for port in public)
    assert bindings['clk'] == 'core_clk_i' and bindings['reset_n'] == 'reset_n_i'
    assert '.ADDR_W(19), .MODEL_WORDS(227062)' in actual_instance
    layer_instance, layer_bindings = instance(core, LAYER_NAME, 'u_six_layers')
    layer_ports, core_ports = ports(layer), ports(core)
    assert set(layer_bindings) == set(layer_ports) and set(bindings) == set(core_ports)
    cuts = {}
    for port, (direction, shape) in layer_ports.items():
        if direction != 'output': continue
        net = layer_bindings[port]
        assert re.fullmatch(r'\w+', net) and net not in cuts, (port, net)
        cuts[net] = {'port': port, 'shape': shape, 'verification_input': 'f_cut_' + net}
    # Only the complete declared private-service output boundary is replaced.
    # Actual core gates, queues, arbiter, shell and local arithmetic are retained.
    core = core.replace(layer_instance, '\n'.join('    assign ' + net + ' = ' + row['verification_input'] + ';'
                                                for net, row in cuts.items()))
    added_ports = ''.join(',\n    input wire ' + row['shape'] + row['verification_input'] for row in cuts.values())
    core_links = {name: core_ports[name][1] for name in
        ('clear_i', 'append_valid_i', 'append_token_i', 'step_valid_i', 'token_ready_i')}
    added_ports += ''.join(',\n    output wire ' + shape + 'f_link_' + name + '_o' for name, shape in core_links.items())
    core = core.replace('\n);', added_ports + '\n);', 1)
    shell_instance, shell_bindings = instance(core, SHELL_NAME, 'u_token_shell')
    expected_shell = {'clear_i': 'clear_i && machine_active', 'append_valid_i': 'append_valid_i && machine_active',
        'append_token_i': 'append_token_i', 'step_valid_i': 'step_valid_i && machine_active',
        'token_ready_i': 'token_ready_i && machine_active'}
    assert all(shell_bindings[name] == value for name, value in expected_shell.items())
    observed_shell_instance = shell_instance[:-2] + ',\n' + ',\n'.join(
        '        .f_link_' + name + '_o(f_shell_' + name + ')' for name in shell_links) + '\n    );'
    core = core.replace(shell_instance, '\n'.join('    wire ' + shape + 'f_shell_' + name + ';'
        for name, shape in shell_links.items()) + '\n' + observed_shell_instance)
    core += '\n' if not core.endswith('\n') else ''
    core = core.replace('\nendmodule', '\n' + '\n'.join('    assign f_link_' + name + '_o = ' + name + ';'
        for name in core_links) + '\nendmodule')
    core_monitor = (ROOT / 'core_monitor.inc.sv').read_text()
    assert 'assume(' not in core_monitor
    core = core.replace('\nendmodule', '\n' + core_monitor + '\nendmodule')
    core_path = MACHINE_DIR + CORE_NAME + '.sv'
    files[core_path] = core.encode(); compile_sources.append(core_path)
    files['production_core.sv'] = production[core_path]
    files['production_layer.sv'] = layer.encode()
    files['production_shared.sv'] = shared.encode()
    files['production_uart.sv'] = uart.encode()
    files['core_monitor.inc.sv'] = core_monitor.encode()
    top_ports = {'core_clk_i': ('input', ''), 'reset_n_i': ('input', ''), 'uart_rx_i': ('input', ''), 'uart_tx_o': ('output', '')}
    for port, (direction, shape) in core_ports.items():
        if port in public or port in ('clk', 'reset_n'): continue
        expression = bindings[port]
        names = expression.split(' || ')
        for name in names:
            assert re.fullmatch(r'\w+', name), (port, expression)
            row = (direction, shape.replace('ADDR_W', '19'))
            if name in top_ports: assert top_ports[name] == row
            top_ports[name] = row
    for net, row in cuts.items(): top_ports[row['verification_input']] = ('input', row['shape'].replace('ADDR_W', '19'))
    wrapper_instance = actual_instance
    for port, net in public.items():
        pattern = r'\.' + port + r'\(\s*' + port + r'\s*\)'
        wrapper_instance, count = re.subn(pattern, '.' + port + '(' + net + ')', wrapper_instance)
        assert count == 1, port
    extra_bindings = ['        .' + row['verification_input'] + '(' + row['verification_input'] + ')' for row in cuts.values()]
    extra_bindings += ['        .f_link_' + name + '_o(f_core_' + name + ')' for name in core_links]
    wrapper_instance = wrapper_instance[:-2] + ',\n' + ',\n'.join(extra_bindings) + '\n    );'
    start, stop = '    wire cmd_valid,cmd_ready,result_valid,result_ready;', '    board1_context2048_shared_token_probe '
    assert uart.count(start) == uart.count(stop) == 1
    front = start + uart.split(start, 1)[1].split(stop, 1)[0]
    front_monitor = packaged('formal/command/monitor.inc.sv').decode()
    connection_monitor = (ROOT / 'connection_monitor.inc.sv').read_text()
    assert front_monitor.count('assert(') == 14 and 'assume(' not in connection_monitor
    wrapper = '`timescale 1ns/1ps\n`default_nettype none\nmodule ' + TOP + ' (\n' + ',\n'.join(
        '    ' + direction + ' wire ' + shape + name for name, (direction, shape) in top_ports.items()) + '\n);\n'
    wrapper += front + '\n'.join('    wire ' + shape + 'f_core_' + name + ';' for name, shape in core_links.items()) + '\n'
    wrapper += wrapper_instance + '\n' + front_monitor + connection_monitor + '\nendmodule\n`default_nettype wire\n'
    files['composition.sv'] = wrapper.encode(); compile_sources.append('composition.sv')
    files['connection_monitor.inc.sv'] = connection_monitor.encode()
    for name in compile_sources: files[name] = b'`undef FORMAL\n' + files[name]
    count = 108 + core_monitor.count('assert(') + connection_monitor.count('assert(')
    binding = {'checked_sha256': checked, 'candidate_image_sha256': IMAGE,
        'hardware_input_inventory_sha256': sha(hardware_inventory),
        'earlier_assertions_reproved_jointly': 108, 'assertions': count,
        'private_semantic_output_cuts': cuts, 'wrapper_ports': top_ports,
        'public_binding_chain': {'uart_to_shared': {p: uart_bindings[p] for p in public},
            'shared_to_core': {p: bindings[p] for p in public}, 'core_to_shell': expected_shell},
        'read_only_connection_observers': {'shell': shell_links, 'core': core_links},
        'core_parameters': {'ADDR_W': 19, 'MODEL_WORDS': 227062},
        'shell_internal_cuts': [], 'hardware_access': False, 'network_access': False,
        'whole_machine_refinement': False}
    return files, compile_sources, binding


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', type=Path, required=True)
    parser.add_argument('--induction', type=int, default=2)
    parser.add_argument('--yosys', default='yosys')
    parser.add_argument('--z3', default='z3')
    args = parser.parse_args()
    assert 2 <= args.induction <= 8
    files, sources, binding = derive()
    k, count = args.induction, binding['assertions']
    commands = ['read_verilog -formal -sv -nosynthesis -D SYNTHESIS -defer ' + ' '.join(sources),
        'prep -top ' + TOP + ' -flatten', 'async2sync', 'chformal -lower', 'opt_clean', 'dffunmap',
        f'select -assert-count {count} t:$assert', 'select -assert-none t:$assume',
        'select -assert-none t:$anyseq', 'select -assert-count 1 t:$anyconst',
        'check -assert', 'write_json elaborated.json', 'write_rtlil elaborated.il', 'write_smt2 -wires design.smt2']
    files['prove.ys'] = ('\n'.join(commands) + '\n').encode()
    files['runner.py'] = Path(__file__).read_bytes()
    inputs = dict(binding, files={name: {'sha256': sha(data), 'bytes': len(data)} for name, data in files.items()},
        induction_length=k, environment='Reset low in base states 0 and 1 only; all private service/lock/fault inputs unrestricted; no induction reset constraint.')
    run = args.run.absolute(); run.mkdir(parents=True, exist_ok=False)
    for name, data in files.items():
        path = run / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(data)
    (run / 'INPUTS.json').write_bytes(encoded(inputs))
    (run / 'STARTED.json').write_bytes(encoded({'pid': os.getpid(), 'utc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'hardware_access': False}))
    started = time.monotonic()
    print('PUBLIC_SHELL_STARTED assertions=' + str(count) + ' private_service_cut_outputs=' + str(len(binding['private_semantic_output_cuts'])), flush=True)
    with (run / 'yosys.log').open('w') as log:
        elaboration = subprocess.run([shutil.which(args.yosys), '-Q', 'prove.ys'], cwd=run, stdout=log, stderr=subprocess.STDOUT)
    results = {}
    if elaboration.returncode == 0:
        smt = (run / 'design.smt2').read_text()
        assert len(re.findall(r'^; yosys-smt2-assert ', smt, re.M)) == count
        assert '; yosys-smt2-assume ' not in smt
        def chain(initial):
            rows = ['(set-option :produce-models true)', '(set-option :timeout 180000)', smt]
            for i in range(k+1):
                rows += [f'(declare-fun s{i} () {TOP}_s)', f'(assert ({TOP}_h s{i}))',
                    f'(assert ({TOP}_u s{i}))', f'(assert (= ({TOP}_is s{i}) {"true" if initial and i == 0 else "false"}))']
                if i: rows.append(f'(assert ({TOP}_t s{i-1} s{i}))')
            if initial:
                rows += [f'(assert ({TOP}_i s0))', f'(assert (not (|{TOP}_n reset_n_i| s0)))',
                    f'(assert (not (|{TOP}_n reset_n_i| s1)))', '(check-sat)',
                    '(assert (not (and ' + ' '.join(f'({TOP}_a s{i})' for i in range(k+1)) + ')))']
            else:
                rows += [f'(assert ({TOP}_a s{i}))' for i in range(k)]
                rows.append(f'(assert (not ({TOP}_a s{k})))')
            return '\n'.join(rows + ['(check-sat)']) + '\n'
        for phase in ('base', 'induction'): (run / (phase + '.smt2')).write_text(chain(phase == 'base'))
        def solve(phase):
            query = run / (phase + '.smt2'); begin = time.monotonic()
            with (run / (phase + '.log')).open('w') as output:
                try:
                    child = subprocess.run([shutil.which(args.z3), '-T:190', '-smt2', str(query)], stdout=output, stderr=subprocess.STDOUT, timeout=210)
                    code = child.returncode
                except subprocess.TimeoutExpired: code = 124
            text = (run / (phase + '.log')).read_text()
            answers = [line for line in text.splitlines() if line in ('sat', 'unsat', 'unknown')]
            expected = ['sat', 'unsat'] if phase == 'base' else ['unsat']
            row = {'passed': code == 0 and answers == expected and '(error' not in text,
                'exit': code, 'answers': answers, 'seconds': time.monotonic()-begin,
                'query_sha256': sha(query.read_bytes()), 'log_sha256': sha(text.encode())}
            if answers and answers[-1] == 'sat':
                diagnostic = query.read_text() + '(get-value (' + ' '.join(f'(|{TOP}_a {n}| s{k})' for n in range(count)) + '))\n'
                (run / (phase + '-countermodel.smt2')).write_text(diagnostic)
                with (run / (phase + '-countermodel.log')).open('w') as output:
                    subprocess.run([shutil.which(args.z3), '-T:190', '-smt2', str(run / (phase + '-countermodel.smt2'))], stdout=output, stderr=subprocess.STDOUT, timeout=210)
            print('PUBLIC_SHELL_' + phase + ' ' + json.dumps(row), flush=True)
            return phase, row
        with ThreadPoolExecutor(max_workers=2) as pool: results = dict(pool.map(solve, ('base', 'induction')))
    unchanged = all(sha((run / name).read_bytes()) == row['sha256'] for name, row in inputs['files'].items())
    result = {'passed': elaboration.returncode == 0 and len(results) == 2 and all(r['passed'] for r in results.values()) and unchanged,
        'elaboration_exit': elaboration.returncode, 'seconds': time.monotonic()-started, 'assertions': count,
        'inputs_sha256': sha((run / 'INPUTS.json').read_bytes()), 'yosys_log_sha256': sha((run / 'yosys.log').read_bytes()),
        'solver_results': results, 'input_hashes_unchanged': unchanged, 'hardware_access': False,
        'whole_machine_refinement': False, 'second_solver_and_sensitivity_checks_pending': True,
        'scope': 'Joint UART/adapter/core-gates/real-token-shell safety at explicit private service boundaries. No complete numerical/private-memory/physical refinement.'}
    (run / 'FINISHED.json').write_bytes(encoded(result))
    print(json.dumps(result, indent=2), flush=True)
    return 0 if result['passed'] else 1


if __name__ == '__main__': raise SystemExit(main())
