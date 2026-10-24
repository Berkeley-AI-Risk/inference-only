"""Frozen seeded UART/core/token-shell composition at the baseline private seams.

No hardware, network, production edits or additional internal assumptions/cuts.
"""
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
HERE = Path(__file__).resolve().parent
FORMAL = HERE.parent
import importlib.util
_spec = importlib.util.spec_from_file_location('seeded_public_sources', FORMAL / 'source_provider.py')
provider = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(provider)
SOURCE, PUBLIC = provider.SOURCE, provider.PUBLIC
TOP = 'board1_seeded_shell_composition'
ASSEMBLY_SHA = provider.ASSEMBLY_SHA
INVENTORY_SHA = provider.INVENTORY_SHA
IMAGE = provider.IMAGE
CORE_NAME = 'board1_context2048_token_machine_core'
SHELL_NAME = 'board1_context2048_token_shell'
LAYER_NAME = 'board1_context2048_semantic_layer'
MACHINE_DIR = 'fpga/token_only_model0_ddr_board1/context2048_token_machine2/rtl/'
UART_DIR = 'fpga/token_only_model0_mac_uart0/rtl/'
PUBLIC_PINS = {
 'formal/token-shell/control_monitor.inc.sv': 'e2583f8131396d62b3184449dbe44d6cf5a5eb5e688b34de24747d2ee6dac407',
 'formal/token-shell/tape_monitor.inc.sv': '768a06ba76c4f00a4157b07dd28af99fe5f9f84c9dd933a267c9435114ddc276',
 'formal/command/monitor.inc.sv': 'd14f348cf635d8d5bdfc09a29685c7a085bcd3126c0a0e49b6ad882f76291e41',
 'formal/composed-shell/core_monitor.inc.sv': '773d6a69eda28119d113e051f19facc6dc9592f474656c26d9061d777b2f87fc',
 'formal/composed-shell/connection_monitor.inc.sv': '1cb7629ad9a8334c78d2d2dfc815fd66b588cb2043516dfa8dae51304f0308aa',
 'formal/composed-shell/run_proof.py': '73b1c5462659037fd98712a6705e1f7ca61a37a6aff561ade80cf5ba8b731282',
}


def sha(data): return hashlib.sha256(data).hexdigest()
def encoded(obj): return (json.dumps(obj, indent=2, sort_keys=True) + '\n').encode()


def ports(source):
    """Strict parser for these pinned ANSI headers, not a general SV parser."""
    header = source.split('\n);', 1)[0].split(') (', 1)[1]
    header = re.sub(r'//[^\n]*', '', header)
    result = {}
    for item in header.split(','):
        match = re.fullmatch(r'\s*(input|output)\s+(?:wire|logic)\s*(signed\s+)?(\[[^\]]+\]\s*)?(\w+)\s*', item)
        if match:
            direction, signed, width, name = match.groups()
        else:
            continuation = re.fullmatch(r'\s*(\w+)\s*', item)
            assert continuation and result, item
            name = continuation[1]
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
        raw = path.read_bytes()
        if expected is not None: assert sha(raw) == expected, path
        checked[str(path.relative_to(PUBLIC))] = sha(raw)
        return raw
    inventory = provider.source_inputs()
    production = {}
    for native, digest in inventory.items():
        raw = read(SOURCE / native, digest)
        if native.startswith('project/'):
            production[native[len('project/'):]] = raw
    image_raw = read(provider.IMAGE_PATH, IMAGE)
    baseline_inventory = json.loads(read(PUBLIC / 'host-app/hardware-inputs.json'))
    def packaged(name):
        return read(PUBLIC / name, PUBLIC_PINS[name])
    for name in PUBLIC_PINS: packaged(name)
    files, compile_sources, origins = {}, [], {}
    def add(name):
        assert name in production, name
        raw = production[name]
        files[name] = raw
        origins[name] = dict(native_path='project/' + name, sha256=sha(raw), bytes=len(raw))
        if name.endswith(('.sv', '.v')): compile_sources.append(name)
    # Same exact full shell dependency set as the freshly source-bound component.
    basenames = ('board1_seeded_head_selector.sv', 'board1_context2048_token_shell.sv',
        'board0_exact_isqrt_u45_iterative.sv', 'board0_exact_rne_div_signed64_iterative.sv',
        'board1_private_ddr256_to_w640.sv', 'board1_fixed_elementwise_dsp_lane.sv',
        'board1_fixed_group_ddr_stream.sv', 'board1_fixed_head_argmax.sv',
        'board1_fixed_head_logit_greater.sv', 'board1_fixed_projection_metadata_reader.sv',
        'board1_fixed_embedding_lookup.sv', 'normalizer_pipeline.sv',
        'board1_fixed_rmsnorm_arithmetic.sv', 'board1_fixed_rmsnorm_rom.sv',
        'board1_fixed_vector_rmsnorm_service.sv', 'candidate.sv',
        'norm_rom34.memh', 'exp_neg_q30.memh', 'fixed_uart_rx.sv', 'fixed_uart_tx.sv',
        'token_only_model0_uart_bridge.sv', 'board1_fixed_command_adapter.sv',
        'board1_ddr_request_fifo2.sv', 'board1_fixed_private_ddr_arbiter.sv')
    for basename in basenames:
        matches = [name for name in production if Path(name).name == basename]
        assert len(matches) == 1, basename
        add(matches[0])
    monitors = {}
    for basename, count in (('uart-monitor.inc.sv', 47), ('selector-monitor.inc.sv', 35),
                            ('shell-settings-monitor.inc.sv', 11)):
        raw = read(FORMAL / basename)
        assert raw.count(b'assert(') == count and b'assume(' not in raw
        monitors[basename] = raw
        files[basename] = raw
    shell_monitor = packaged('formal/token-shell/control_monitor.inc.sv') + b'\n' + packaged('formal/token-shell/tape_monitor.inc.sv')
    assert shell_monitor.count(b'assert(') == 48
    shell_monitor += b'\n' + monitors['shell-settings-monitor.inc.sv']
    files['shell-monitor.inc.sv'] = shell_monitor
    shell_path = MACHINE_DIR + SHELL_NAME + '.sv'
    shell_ports = ports(files[shell_path].decode())
    link_names = ('clear_i', 'append_valid_i', 'append_token_i', 'step_valid_i', 'token_ready_i',
        'settings_valid_i', 'settings_ready_o', 'settings_temperature_i', 'settings_seed_i',
        'settings_accepted_o', 'settings_rejected_o')
    shell_links = {name: shell_ports[name][1] for name in link_names}
    shell_links.update({'append_transfer': '', 'step_transfer': ''})
    shell_observed = files[shell_path].decode().replace('\n);', ''.join(
        ',\n    output wire ' + shape + 'f_link_' + name + '_o' for name, shape in shell_links.items()) + '\n);', 1)
    shell_observed = shell_observed.replace('\nendmodule', '\n' + '\n'.join(
        '    assign f_link_' + name + '_o = ' + name + ';' for name in shell_links) + '\n' + shell_monitor.decode() + '\nendmodule')
    files[shell_path] = shell_observed.encode()
    for basename, monitor in (('board1_seeded_head_selector.sv', monitors['selector-monitor.inc.sv']),
                              ('token_only_model0_uart_bridge.sv', monitors['uart-monitor.inc.sv'])):
        name = next(name for name in files if Path(name).name == basename)
        assert files[name].count(b'\nendmodule') == 1
        files[name] = files[name].replace(b'\nendmodule', b'\n' + monitor + b'\nendmodule')
    uart, shared = (production[name].decode() for name in ('uart_core.sv', 'shared_token_probe.sv'))
    core_path = MACHINE_DIR + CORE_NAME + '.sv'
    core = production[core_path].decode()
    layer_path = 'fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/' + LAYER_NAME + '.sv'
    layer = production[layer_path].decode()
    _, uart_bindings = instance(uart, 'board1_context2048_shared_token_probe', 'u_machine')
    public = {'clear_i': 'clear', 'append_valid_i': 'append_valid', 'append_ready_o': 'append_ready',
        'append_token_i': 'append_token', 'step_valid_i': 'step_valid', 'step_ready_o': 'step_ready',
        'token_valid_o': 'token_valid', 'token_ready_i': 'token_ready', 'token_o': 'token',
        'settings_valid_i': 'settings_valid', 'settings_ready_o': 'settings_ready',
        'settings_temperature_i': 'settings_temperature', 'settings_seed_i': 'settings_seed',
        'settings_accepted_o': 'settings_accepted', 'settings_rejected_o': 'settings_rejected'}
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
    assert len(cuts) == 37
    # Assert the declaration and binding boundary matches the source used by
    # the baseline proof byte-for-byte. The same 37 outputs remain arbitrary.
    old_core = read(PUBLIC / 'hardware/project' / core_path, baseline_inventory['project/' + core_path]).decode()
    old_layer = read(PUBLIC / 'hardware/project' / layer_path, baseline_inventory['project/' + layer_path]).decode()
    _, old_layer_bindings = instance(old_core, LAYER_NAME, 'u_six_layers')
    assert ports(old_layer) == layer_ports and old_layer_bindings == layer_bindings
    core = core.replace(layer_instance, '\n'.join('    assign ' + net + ' = ' + row['verification_input'] + ';'
                                                for net, row in cuts.items()))
    added_ports = ''.join(',\n    input wire ' + row['shape'] + row['verification_input'] for row in cuts.values())
    core_links = {name: core_ports[name][1] for name in link_names}
    added_ports += ''.join(',\n    output wire ' + shape + 'f_link_' + name + '_o' for name, shape in core_links.items())
    core = core.replace('\n);', added_ports + '\n);', 1)
    shell_instance, shell_bindings = instance(core, SHELL_NAME, 'u_token_shell')
    expected_shell = {'clear_i': 'clear_i && machine_active', 'append_valid_i': 'append_valid_i && machine_active',
        'append_token_i': 'append_token_i', 'step_valid_i': 'step_valid_i && machine_active',
        'token_ready_i': 'token_ready_i && machine_active',
        'settings_valid_i': 'settings_valid_i && machine_active && !root_terminal',
        'settings_ready_o': 'shell_settings_ready', 'settings_temperature_i': 'settings_temperature_i',
        'settings_seed_i': 'settings_seed_i', 'settings_accepted_o': 'settings_accepted_o',
        'settings_rejected_o': 'settings_rejected_o'}
    assert all(shell_bindings[name] == value for name, value in expected_shell.items())
    observed_shell_instance = shell_instance[:-2] + ',\n' + ',\n'.join(
        '        .f_link_' + name + '_o(f_shell_' + name + ')' for name in shell_links) + '\n    );'
    core = core.replace(shell_instance, '\n'.join('    wire ' + shape + 'f_shell_' + name + ';'
        for name, shape in shell_links.items()) + '\n' + observed_shell_instance)
    core = core.replace('\nendmodule', '\n' + '\n'.join('    assign f_link_' + name + '_o = ' + name + ';'
        for name in core_links) + '\nendmodule')
    core_monitor = packaged('formal/composed-shell/core_monitor.inc.sv') + b'\n' + (HERE / 'core-settings-monitor.inc.sv').read_bytes()
    assert b'assume(' not in core_monitor
    core = core.replace('\nendmodule', '\n' + core_monitor.decode() + '\nendmodule')
    files[core_path] = core.encode(); compile_sources.append(core_path)
    origins[core_path] = dict(native_path='project/' + core_path, sha256=sha(production[core_path]), bytes=len(production[core_path]))
    files['core-monitor.inc.sv'] = core_monitor
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
        wrapper_instance, count = re.subn(r'\.' + port + r'\(\s*' + port + r'\s*\)', '.' + port + '(' + net + ')', wrapper_instance)
        assert count == 1, port
    extra_bindings = ['        .' + row['verification_input'] + '(' + row['verification_input'] + ')' for row in cuts.values()]
    extra_bindings += ['        .f_link_' + name + '_o(f_core_' + name + ')' for name in core_links]
    wrapper_instance = wrapper_instance[:-2] + ',\n' + ',\n'.join(extra_bindings) + '\n    );'
    start, stop = '    wire settings_valid,settings_ready,settings_accepted,settings_rejected;', '    board1_context2048_shared_token_probe '
    assert uart.count(start) == uart.count(stop) == 1
    front = start + uart.split(start, 1)[1].split(stop, 1)[0]
    front_monitor = packaged('formal/command/monitor.inc.sv')
    connection_monitor = packaged('formal/composed-shell/connection_monitor.inc.sv') + b'\n' + (HERE / 'connection-settings-monitor.inc.sv').read_bytes()
    assert front_monitor.count(b'assert(') == 14 and b'assume(' not in connection_monitor
    wrapper = '`timescale 1ns/1ps\n`default_nettype none\nmodule ' + TOP + ' (\n' + ',\n'.join(
        '    ' + direction + ' wire ' + shape + name for name, (direction, shape) in top_ports.items()) + '\n);\n'
    wrapper += front + '\n'.join('    wire ' + shape + 'f_core_' + name + ';' for name, shape in core_links.items()) + '\n'
    wrapper += wrapper_instance + '\n' + front_monitor.decode() + connection_monitor.decode() + '\nendmodule\n`default_nettype wire\n'
    files['composition.sv'] = wrapper.encode(); compile_sources.append('composition.sv')
    files['connection-monitor.inc.sv'] = connection_monitor
    files['front-monitor.inc.sv'] = front_monitor
    transformations = {}
    for name in compile_sources:
        if name in production:
            original = production[name]
            files['original/' + name] = original
            transformed = b'`undef FORMAL\n' + files[name]
            changes = list(difflib.unified_diff(original.decode().splitlines(keepends=True), transformed.decode().splitlines(keepends=True),
                fromfile='original/' + name, tofile=name))
            delta_name = 'transformations/' + name + '.diff'
            files[delta_name] = ''.join(changes).encode()
            transformations[name] = dict(original_sha256=sha(original), transformed_sha256=sha(transformed),
                diff=delta_name, diff_sha256=sha(files[delta_name]))
            files[name] = transformed
    for name in ('uart_core.sv', 'shared_token_probe.sv', layer_path):
        files['original/' + name] = production[name]
    # Existing source FORMAL assertions are disabled; only inserted monitors count.
    count = (47 + 35 + shell_monitor.count(b'assert(') + core_monitor.count(b'assert(') +
             front_monitor.count(b'assert(') + connection_monitor.count(b'assert('))
    binding = {'schema': 'seeded-connected-formal-inputs-v1', 'top': TOP, 'checked_sha256': checked,
        'candidate_image_sha256': IMAGE, 'candidate_image_bytes': len(image_raw),
        'source_binding': provider.source_binding(),
        'frozen_assembly_sha256': ASSEMBLY_SHA, 'frozen_inventory_sha256': INVENTORY_SHA,
        'assertions': count, 'baseline_unchanged_assertions_reproved_jointly': 88,
        'baseline_uart_assertions_replaced': 46, 'extended_seeded_uart_assertions': 47,
        'private_semantic_output_cuts': cuts, 'wrapper_ports': top_ports,
        'public_binding_chain': {'uart_to_shared': {p: uart_bindings[p] for p in public},
            'shared_to_core': {p: bindings[p] for p in public}, 'core_to_shell': expected_shell},
        'read_only_connection_observers': {'shell': shell_links, 'core': core_links},
        'core_parameters': {'ADDR_W': 19, 'MODEL_WORDS': 227062}, 'origins': origins,
        'transformations': transformations, 'shell_internal_cuts': [], 'additional_assumptions': [],
        'production_parameters_changed': [], 'hardware_access': False, 'network_access': False,
        'whole_machine_refinement': False}
    return files, compile_sources, binding

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', type=Path, required=True)
    parser.add_argument('--induction', type=int, default=2)
    parser.add_argument('--timeout', type=int, default=180)
    parser.add_argument('--solvers', default='z3')
    args = parser.parse_args()
    assert 2 <= args.induction <= 8 and 1 <= args.timeout <= 900
    solvers = args.solvers.split(',')
    assert 'z3' in solvers and all(s in ('z3', 'cvc5') and shutil.which(s) for s in solvers)
    files, sources, binding = derive()
    k, count = args.induction, binding['assertions']
    commands = ['read_verilog -formal -sv -nosynthesis -D SYNTHESIS -defer ' + ' '.join(sources),
        'prep -top ' + TOP + ' -flatten', 'async2sync', 'chformal -lower', 'opt_clean', 'dffunmap',
        f'select -assert-count {count} t:$assert', 'select -assert-none t:$assume',
        'select -assert-none t:$anyseq', 'select -assert-count 1 t:$anyconst',
        'check -assert', 'write_json elaborated.json', 'write_rtlil elaborated.il', 'write_smt2 -wires design.smt2']
    files['prove.ys'] = ('\n'.join(commands) + '\n').encode()
    files['runner.py'] = Path(__file__).read_bytes()
    for basename in ('core-settings-monitor.inc.sv', 'connection-settings-monitor.inc.sv'):
        files[basename] = (HERE / basename).read_bytes()
    files['baseline-driver.py'] = (PUBLIC / 'formal/composed-shell/run_proof.py').read_bytes()
    inputs = dict(binding, files={name: {'sha256': sha(data), 'bytes': len(data)} for name, data in files.items()},
        induction_length=k, solvers=solvers, solver_timeout_seconds=args.timeout,
        environment='Reset low in base states 0 and 1 only; all 37 private semantic-layer output cuts and all external service/lock/fault inputs unrestricted; no induction reset constraint. Original FORMAL blocks disabled; original simulation-only X checks excluded by SYNTHESIS.')
    run = args.run.absolute(); run.mkdir(parents=True, exist_ok=False)
    assert HERE.parent in run.parents
    for name, data in files.items():
        path = run / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(data)
    (run / 'INPUTS.json').write_bytes(encoded(inputs))
    (run / 'STARTED.json').write_bytes(encoded({'pid': os.getpid(), 'utc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'hardware_access': False}))
    started = time.monotonic()
    print('CONNECTED_STARTED assertions=' + str(count) + ' private_service_cut_outputs=' + str(len(binding['private_semantic_output_cuts'])), flush=True)
    with (run / 'yosys.log').open('w') as log:
        elaboration = subprocess.run(['yosys', '-Q', 'prove.ys'], cwd=run, stdout=log, stderr=subprocess.STDOUT)
    results, memory_rows = {}, {}
    if elaboration.returncode == 0:
        design = json.loads((run / 'elaborated.json').read_text())
        for module in design['modules'].values():
            for name, cell in module.get('cells', {}).items():
                if cell['type'] == '$mem_v2':
                    memory_rows[name] = {key: cell['parameters'][key] for key in ('SIZE', 'WIDTH', 'ABITS', 'INIT')}
        assert len(memory_rows) >= 20
        (run / 'MEMORIES.json').write_bytes(encoded(memory_rows))
        smt = (run / 'design.smt2').read_text()
        assert len(re.findall(r'^; yosys-smt2-assert ', smt, re.M)) == count
        assert '; yosys-smt2-assume ' not in smt
        def chain(initial):
            rows = ['(set-option :produce-models true)', smt]
            for step in range(k+1):
                rows += [f'(declare-fun s{step} () {TOP}_s)', f'(assert ({TOP}_h s{step}))',
                    f'(assert ({TOP}_u s{step}))', f'(assert (= ({TOP}_is s{step}) {"true" if initial and step == 0 else "false"}))']
                if step: rows.append(f'(assert ({TOP}_t s{step-1} s{step}))')
            if initial:
                rows += [f'(assert ({TOP}_i s0))', f'(assert (not (|{TOP}_n reset_n_i| s0)))',
                    f'(assert (not (|{TOP}_n reset_n_i| s1)))', '(check-sat)',
                    '(assert (not (and ' + ' '.join(f'({TOP}_a s{step})' for step in range(k+1)) + ')))']
            else:
                rows += [f'(assert ({TOP}_a s{step}))' for step in range(k)]
                rows.append(f'(assert (not ({TOP}_a s{k})))')
            return '\n'.join(rows + ['(check-sat)']) + '\n'
        jobs = []
        for solver in solvers:
            for phase in ('base', 'induction'):
                prefix = (f'(set-option :timeout {args.timeout * 1000})\n' if solver == 'z3' else
                    f'(set-logic HO_ALL)\n(set-option :tlimit-per {args.timeout * 1000})\n')
                label = solver + '-' + phase
                path = run / (label + '.smt2')
                query = chain(phase == 'base')
                if solver == 'cvc5':
                    query = query.replace('(set-option :produce-models true)', '(set-option :produce-models false)')
                    if phase == 'base': query = query.replace('(check-sat)\n', '', 1)
                path.write_text(prefix + query)
                jobs.append((solver, phase, label, path))
        def solve(job):
            solver, phase, label, query = job
            command = ([solver, '-smt2', str(query)] if solver == 'z3' else
                       [solver, '--lang=smt2', '--incremental', str(query)])
            begin = time.monotonic()
            code, timed_out = None, False
            with (run / (label + '.log')).open('w') as stream:
                try:
                    child = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT,
                        timeout=args.timeout * 2 + 20)
                    code = child.returncode
                except subprocess.TimeoutExpired: timed_out = True
            output = (run / (label + '.log')).read_text()
            answers = [line for line in output.splitlines() if line in ('sat', 'unsat', 'unknown')]
            expected = ['sat', 'unsat'] if phase == 'base' and solver == 'z3' else ['unsat']
            row = {'passed': code == 0 and answers == expected and '(error' not in output,
                'exit': code, 'timed_out': timed_out, 'answers': answers, 'expected': expected,
                'seconds': time.monotonic()-begin,
                'query_sha256': sha(query.read_bytes()), 'log_sha256': sha(output.encode())}
            if answers and answers[-1] == 'sat':
                diagnostic = query.read_text() + '(get-value (' + ' '.join(f'(|{TOP}_a {n}| s{k})' for n in range(count)) + '))\n'
                diagnostic_path = run / (label + '-countermodel.smt2')
                diagnostic_path.write_text(diagnostic)
                diag_cmd = ([solver, '-smt2', str(diagnostic_path)] if solver == 'z3' else
                    [solver, '--lang=smt2', '--incremental', str(diagnostic_path)])
                with (run / (label + '-countermodel.log')).open('w') as stream:
                    try: subprocess.run(diag_cmd, stdout=stream, stderr=subprocess.STDOUT, timeout=args.timeout*2+20)
                    except subprocess.TimeoutExpired: pass
            print('CONNECTED_' + label + ' ' + json.dumps(row), flush=True)
            return label, row
        with ThreadPoolExecutor(max_workers=2) as pool: results = dict(pool.map(solve, jobs))
    unchanged = all(sha((run / name).read_bytes()) == row['sha256'] for name, row in inputs['files'].items())
    result = {'schema': 'seeded-connected-formal-result-v1',
        'passed': elaboration.returncode == 0 and len(results) == len(solvers)*2 and all(r['passed'] for r in results.values()) and unchanged,
        'elaboration_exit': elaboration.returncode, 'seconds': time.monotonic()-started, 'assertions': count,
        'memory_cells': len(memory_rows), 'assertion_cells': count, 'assumption_cells': 0,
        'proof_artifacts_sha256': {name: sha((run / name).read_bytes()) for name in ('design.smt2', 'elaborated.json', 'elaborated.il', 'MEMORIES.json') if (run / name).is_file()},
        'inputs_sha256': sha((run / 'INPUTS.json').read_bytes()),
        'yosys_log_sha256': sha((run / 'yosys.log').read_bytes()),
        'solver_results': results, 'input_hashes_unchanged': unchanged, 'hardware_access': False,
        'whole_machine_refinement': False,
        'scope': 'Joint frozen CPB217 UART/adapter/seeded settings/core-gates/real-token-shell safety at exactly the baseline 37 unrestricted private semantic output cuts. Complete fixed-dimension sampler and actual shell memories retained. No complete numerical/private-memory/physical refinement.'}
    (run / 'FINISHED.json').write_bytes(encoded(result))
    print(json.dumps(result, indent=2), flush=True)
    return 0 if result['passed'] else 1


if __name__ == '__main__': raise SystemExit(main())
