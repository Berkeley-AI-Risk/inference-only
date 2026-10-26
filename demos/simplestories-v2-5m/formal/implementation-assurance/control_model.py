"""Current production UART/core/shell composition; structural instrumentation
adapted from the preserved public reference helper. All runtime RTL comes from
the selected native inventory. The earlier reference supplies monitors and a
names-only dependency list, not a numerical backend or inherited proof result.
"""
import difflib
import hashlib
import json
from pathlib import Path
import re
TOP = 'board1_public_shell_composition'
CORE_NAME = 'board1_context2048_token_machine_core'
SHELL_NAME = 'board1_context2048_token_shell'
LAYER_NAME = 'board1_context2048_semantic_layer'
MACHINE_DIR = 'fpga/token_only_model0_ddr_board1/context2048_token_machine2/rtl/'
UART_DIR = 'fpga/token_only_model0_mac_uart0/rtl/'
HERE = Path(__file__).resolve().parent

def sha(raw): return hashlib.sha256(raw).hexdigest()

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


def derive(package, variant, common):
    package = common.model_package(package)
    pin, native_root, native_binding = common.binding(package,variant)
    if variant == 'seeded-sampling':
        raise ValueError('Use the separately qualified seeded controller proof')
    reference = package/'reference/baseline-formal-354'
    ROOT = reference/'formal/composed-shell'
    IMAGE = pin['image_sha256']
    shared_name = 'tang_confidential_context2048_token_probe' if variant == 'encrypted-memory' else 'board1_context2048_shared_token_probe'
    support = json.loads((HERE/'CONTROL-SUPPORT.json').read_text())
    checked = {}
    for name,digest in support.items():
        if sha(common.safe(reference,name).read_bytes()) != digest:
            raise ValueError('Control proof support changed: '+name)
    def packaged(name):
        raw = common.safe(reference,name).read_bytes()
        if sha(raw) != support[name]:
            raise ValueError('Control monitor/support source changed')
        checked['reference/baseline-formal-354/'+name] = sha(raw)
        return raw
    hardware_inventory = common.safe(package,pin['native_inventory']).read_bytes()
    hardware = json.loads(hardware_inventory)
    production = {}
    for name,digest in hardware.items():
        if name in pin['omitted_vendor_inputs']: continue
        raw = common.safe(native_root,name).read_bytes()
        if sha(raw) != digest: raise ValueError('Native source changed')
        checked[pin['hardware_root']+'/'+name] = digest
        production[name.removeprefix('project/')] = raw
    previous_sources = json.loads(packaged('formal/token-shell/sources.json'))
    files, compile_sources = {}, []
    for name in previous_sources:
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
    _, uart_bindings = instance(uart, shared_name, 'u_machine')
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
    start, stop = '    wire cmd_valid,cmd_ready,result_valid,result_ready;', '    '+shared_name+' '
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
    binding['native_binding'] = native_binding
    return files, compile_sources, binding
