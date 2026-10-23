"""Fresh source-bound seeded component proofs; no hardware/network/vendor tools.

Production logic, dimensions and memories are retained. Only read-only monitors
are inserted. Every assumption/cut boundary is recorded explicitly.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import time

HERE = Path(__file__).resolve().parent
import importlib.util
_spec = importlib.util.spec_from_file_location('seeded_public_sources', HERE / 'source_provider.py')
provider = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(provider)
SOURCE, PUBLIC = provider.SOURCE, provider.PUBLIC
ASSEMBLY_SHA, INVENTORY_SHA = provider.ASSEMBLY_SHA, provider.INVENTORY_SHA


def sha(data): return hashlib.sha256(data).hexdigest()
def source_inputs(): return provider.source_inputs()


def prepare(case):
    inventory = source_inputs()
    files, origins, sources = {}, {}, []
    def add(basename, monitor=None):
        matches = [name for name in inventory if Path(name).name == basename]
        if len(matches) != 1: raise ValueError('Ambiguous native input: ' + basename)
        name = matches[0]
        raw = (SOURCE / name).read_bytes()
        relative = name[len('project/'):] if name.startswith('project/') else name
        origins[relative] = dict(native_path=name, sha256=sha(raw), bytes=len(raw))
        data = raw
        if monitor is not None:
            files['production-' + basename] = raw
            if data.count(b'\nendmodule') != 1: raise ValueError('Unexpected module boundary')
            data = data.replace(b'\nendmodule', b'\n' + monitor + b'\nendmodule')
        if basename.endswith(('.sv', '.v')):
            data = b'`undef FORMAL\n' + data
            sources.append(relative)
        files[relative] = data
    if case in ('selector', 'selector-buffer'):
        top, reset = 'board1_seeded_head_selector', 'reset_n'
        monitor = (HERE / 'selector-monitor.inc.sv').read_bytes()
        add('board1_seeded_head_selector.sv', monitor)
        add('board1_fixed_head_argmax.sv')
        add('board1_fixed_head_logit_greater.sv')
        add('exp_neg_q30.memh')
        scope = 'Actual fixed-dimension selector and original argmax, all three sampler memories and numerical logic retained. Safety of configuration/seed/PRNG commitment, accepted-start winner ownership, stalls, CLEAR/fault/reset. Not a numerical CDF-equivalence, per-row memory-initialization or whole-machine theorem.'
        if case == 'selector-buffer':
            argmax = next(name for name in sources if Path(name).name == 'board1_fixed_head_argmax.sv')
            child_monitor = (HERE / 'argmax-row-ownership-monitor.inc.sv').read_bytes()
            child = files[argmax]
            port = b'    output logic                   fail_closed_o\n'
            if child.count(port) != 1: raise ValueError('Argmax observation boundary changed')
            child = child.replace(port, port.rstrip(b'\n') + b',\n    output wire [12:0] f_observed_rows_o\n')
            child = child.replace(b'\nendmodule', b'\n' + child_monitor + b'\nendmodule')
            files[argmax] = child
            native = next(name for name in sources if Path(name).name == 'board1_seeded_head_selector.sv')
            parent = files[native]
            link = b'        .busy_o(greedy_busy), .fail_closed_o(greedy_fault)\n'
            if parent.count(link) != 1: raise ValueError('Argmax instance boundary changed')
            parent = parent.replace(link, link.rstrip(b'\n') + b',\n        .f_observed_rows_o(f_child_rows)\n')
            parent = parent.replace(b'    wire greedy_busy, greedy_fault;', b'    wire greedy_busy, greedy_fault;\n    wire [12:0] f_child_rows;')
            buffer_monitor = (HERE / 'sampler-buffer-monitor.inc.sv').read_bytes()
            parent = parent.replace(b'\nendmodule', b'\n' + buffer_monitor + b'\nendmodule')
            files[native] = parent
            files['argmax-row-ownership-monitor.inc.sv'] = child_monitor
            files['sampler-buffer-monitor.inc.sv'] = buffer_monitor
            monitor += b'\n' + child_monitor + b'\n' + buffer_monitor
            scope = 'Actual full selector, all 4019-row logits/mass RAM entries and every exponential ROM word retained. A read-only child row-count output and unconstrained constant slot observe complete accepted-head ownership, per-slot writes before healthy sampling reads, captured memory payload, and mass-pass ownership. No production feedback, parameters, assumptions or input cuts. Not mathematical CDF equivalence, whole-machine, physical-memory clearing or four-state simulation theorem.'
    elif case == 'uart':
        top, reset = 'board1_seeded_command_frontend', 'reset_n_i'
        monitor = (HERE / 'uart-monitor.inc.sv').read_bytes()
        add('token_only_model0_uart_bridge.sv', monitor)
        add('fixed_uart_rx.sv')
        add('fixed_uart_tx.sv')
        add('board1_fixed_command_adapter.sv')
        core = (SOURCE / 'project/uart_core.sv').read_text()
        start = '    wire settings_valid,settings_ready,settings_accepted,settings_rejected;'
        stop = '    board1_context2048_shared_token_probe #(.AUTH_BANKS(4)) u_machine ('
        if core.count(start) != 1 or core.count(stop) != 1:
            raise ValueError('Frozen UART instance boundaries changed')
        body = start + core.split(start, 1)[1].split(stop, 1)[0]
        for old, new in ((start + '\n', ''),
                         ('    wire [2:0] settings_temperature;\n', ''),
                         ('    wire [127:0] settings_seed;\n', ''),
                         ('    wire clear,decoded_clear,append_valid,append_ready,step_valid,step_ready,token_valid,token_ready;', '    wire decoded_clear;'),
                         ('    wire [11:0] append_token,token;\n', '')):
            if body.count(old) != 1: raise ValueError('Unexpected connection declaration: ' + old)
            body = body.replace(old, new)
        bindings = dict(re.findall(r'\.(\w+)\(([^()]*)\)', core.split(stop, 1)[1].split(');', 1)[0]))
        expected = {'clear_i': 'clear', 'append_valid_i': 'append_valid', 'append_ready_o': 'append_ready',
                    'append_token_i': 'append_token', 'step_valid_i': 'step_valid', 'step_ready_o': 'step_ready',
                    'token_valid_o': 'token_valid', 'token_ready_i': 'token_ready', 'token_o': 'token',
                    'settings_valid_i': 'settings_valid', 'settings_ready_o': 'settings_ready',
                    'settings_temperature_i': 'settings_temperature', 'settings_seed_i': 'settings_seed',
                    'settings_accepted_o': 'settings_accepted', 'settings_rejected_o': 'settings_rejected'}
        if any(bindings.get(key) != value for key, value in expected.items()):
            raise ValueError('Frozen backend-boundary wiring changed')
        connection_monitor = (PUBLIC / 'formal/command/monitor.inc.sv').read_bytes()
        connection_monitor += b'''\n    always_comb if (reset_n_i) begin
        if (settings_valid) assert(!append_valid && !step_valid && !clear);
        if (settings_valid) assert(settings_temperature <= 3);
    end\n'''
        header = '''`timescale 1ns/1ps
`default_nettype none
module board1_seeded_command_frontend (
    input wire core_clk_i, reset_n_i, uart_rx_i,
    output wire uart_tx_o,
    input wire append_ready, step_ready, token_valid,
    input wire [11:0] token,
    output wire append_valid, step_valid, clear, token_ready,
    output wire [11:0] append_token,
    input wire settings_ready,settings_accepted,settings_rejected,
    output wire settings_valid,
    output wire [2:0] settings_temperature,
    output wire [127:0] settings_seed
);
'''
        files['frontend.sv'] = header.encode() + body.encode() + connection_monitor + b'\nendmodule\n'
        sources.append('frontend.sv')
        files['production-uart_core.sv'] = core.encode()
        files['connection-monitor.inc.sv'] = connection_monitor
        origins['uart_core.sv'] = dict(native_path='project/uart_core.sv', sha256=sha(core.encode()),
                                       bytes=len(core.encode()), backend_boundary_bindings=expected)
        monitor += connection_monitor
        scope = 'Actual CPB217 RX/TX, extended bridge and unchanged operation adapter; actual frontend instances extracted from frozen uart_core. Independent admitted-byte history, complete SETTINGS/legacy provenance, timeout ownership, atomic settings payload, operation authorization and reply framing. Backend readiness/model outputs/settings feedback are unrestricted component input ports. No backend, whole-machine, TX-waveform or UART-authentication theorem.'
    elif case == 'shell':
        top, reset = 'board1_context2048_token_shell', 'rst_n'
        selector_monitor = (HERE / 'selector-monitor.inc.sv').read_bytes()
        shell_monitor = ((PUBLIC / 'formal/token-shell/control_monitor.inc.sv').read_bytes() + b'\n' +
                         (PUBLIC / 'formal/token-shell/tape_monitor.inc.sv').read_bytes() + b'\n' +
                         (HERE / 'shell-settings-monitor.inc.sv').read_bytes())
        add('board1_seeded_head_selector.sv', selector_monitor)
        add('board1_context2048_token_shell.sv', shell_monitor)
        for basename in ('board0_exact_isqrt_u45_iterative.sv', 'board0_exact_rne_div_signed64_iterative.sv',
                         'board1_private_ddr256_to_w640.sv', 'board1_fixed_elementwise_dsp_lane.sv',
                         'board1_fixed_group_ddr_stream.sv', 'board1_fixed_head_argmax.sv',
                         'board1_fixed_head_logit_greater.sv', 'board1_fixed_projection_metadata_reader.sv',
                         'board1_fixed_embedding_lookup.sv', 'normalizer_pipeline.sv',
                         'board1_fixed_rmsnorm_arithmetic.sv', 'board1_fixed_rmsnorm_rom.sv',
                         'board1_fixed_vector_rmsnorm_service.sv', 'candidate.sv',
                         'norm_rom34.memh', 'exp_neg_q30.memh'):
            add(basename)
        monitor = shell_monitor + b'\n' + selector_monitor
        files['shell-monitor.inc.sv'] = shell_monitor
        files['selector-monitor.inc.sv'] = selector_monitor
        scope = 'Actual seeded token shell with original embedding/normalizer/arithmetic children and complete fixed-dimension sampler, actual RAMs retained. Original 48 controller/tape assertions plus settings-boundary and sampler lifecycle assertions jointly proved. One unconstrained constant tape-slot observer never drives production logic. External private model/layer/head service ports remain arbitrary; not numerical fixed-model, whole-private-memory, core/UART composition or mapped-implementation refinement.'
    else:
        raise ValueError('Unimplemented proof case: ' + case)
    if b'assume(' in monitor: raise ValueError('Monitors must not add assumptions')
    files['monitor.inc.sv'] = monitor
    return files, origins, sources, top, reset, monitor.count(b'assert('), scope


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--case', choices=('selector', 'selector-buffer', 'uart', 'shell'), required=True)
    parser.add_argument('--run', type=Path, required=True)
    parser.add_argument('--induction', type=int, default=3)
    parser.add_argument('--timeout', type=int, default=120)
    parser.add_argument('--solvers', default='z3,cvc5')
    parser.add_argument('--cvc5-base-only', action='store_true',
                        help='Check cvc5 induction with check_conclusions.py separately')
    args = parser.parse_args()
    if not 2 <= args.induction <= 8 or not 1 <= args.timeout <= 600:
        parser.error('induction 2..8 and solver timeout 1..600 required')
    solvers = args.solvers.split(',')
    if any(solver not in ('z3', 'cvc5') or shutil.which(solver) is None for solver in solvers):
        parser.error('choose locally available z3 and/or cvc5')
    files, origins, sources, top, reset, count, scope = prepare(args.case)
    if count != {'selector': 35, 'selector-buffer': 57, 'uart': 63, 'shell': 94}[args.case]:
        raise ValueError('Reviewed assertion inventory changed')
    observers = 1 if args.case in ('shell', 'selector-buffer') else 0
    run = args.run.absolute()
    run.mkdir(parents=True, exist_ok=False)
    script = ['read_verilog -formal -sv -nosynthesis -D SYNTHESIS -defer ' + ' '.join(sources),
              f'prep -top {top} -flatten', 'async2sync', 'chformal -lower', 'opt_clean', 'dffunmap',
              f'select -assert-count {count} t:$assert', 'select -assert-none t:$assume',
              'select -assert-none t:$anyseq', f'select -assert-count {observers} t:$anyconst', 'check -assert',
              'write_json elaborated.json', 'write_rtlil elaborated.il', 'write_smt2 -wires design.smt2']
    files['prove.ys'] = ('\n'.join(script) + '\n').encode()
    files['runner.py'] = Path(__file__).read_bytes()
    for name, data in files.items():
        destination = run / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
    inputs = dict(schema='seeded-component-formal-inputs-v1', case=args.case,
        frozen_assembly_sha256=ASSEMBLY_SHA, frozen_inventory_sha256=INVENTORY_SHA,
        source_binding=provider.source_binding(),
        origins=origins, files={name: dict(bytes=len(data), sha256=sha(data)) for name, data in files.items()},
        top=top, reset=reset, assertion_cells_expected=count, assumption_cells_expected=0,
        observer_constants_expected=observers,
        cvc5_induction_separate_conclusions=args.cvc5_base_only,
        internal_value_or_handshake_cuts=[], production_parameters_changed=[],
        environment='All production input ports arbitrary. Two-state synchronous digital model; reset asserted at SMT base states 0 and 1 only, unrestricted in induction. Original simulation-only X checks excluded by SYNTHESIS, original FORMAL blocks explicitly disabled.',
        induction_length=args.induction, scope=scope, hardware_access=False, network_access=False)
    (run / 'INPUTS.json').write_text(json.dumps(inputs, indent=2, sort_keys=True) + '\n')
    started = time.monotonic()
    print(f'PROOF_STARTED case={args.case} assertions={count} run={run}', flush=True)
    with (run / 'yosys.log').open('w') as stream:
        result = subprocess.run(['yosys', '-Q', 'prove.ys'], cwd=run, stdout=stream, stderr=subprocess.STDOUT)
    solver_results = {}
    memories = 0
    if result.returncode == 0:
        elaborated = json.loads((run / 'elaborated.json').read_text())
        cells = [cell['type'] for module in elaborated['modules'].values() for cell in module.get('cells', {}).values()]
        memories = cells.count('$mem_v2')
        if cells.count('$assert') != count or '$assume' in cells or '$anyseq' in cells or cells.count('$anyconst') != observers:
            raise ValueError('Unexpected elaborated formal cells')
        if memories != {'selector': 3, 'selector-buffer': 3, 'uart': 0, 'shell': 20}[args.case]:
            raise ValueError('Reviewed actual memory inventory changed')
        smt = (run / 'design.smt2').read_text()
        if len(re.findall(r'^; yosys-smt2-assert ', smt, re.M)) != count:
            raise ValueError('SMT assertion inventory mismatch')
        k = args.induction
        def chain(last, initial):
            parts = ['(set-option :produce-models true)', smt]
            for step in range(last + 1):
                parts += [f'(declare-fun s{step} () {top}_s)', f'(assert ({top}_h s{step}))',
                          f'(assert ({top}_u s{step}))',
                          f'(assert (= ({top}_is s{step}) {"true" if initial and step == 0 else "false"}))']
                if step: parts.append(f'(assert ({top}_t s{step-1} s{step}))')
            if initial:
                parts += [f'(assert ({top}_i s0))', f'(assert (not (|{top}_n {reset}| s0)))',
                          f'(assert (not (|{top}_n {reset}| s1)))']
            return parts
        base = chain(k, True) + ['(check-sat)', '(assert (not (and ' + ' '.join(
            f'({top}_a s{step})' for step in range(k + 1)) + ')))', '(check-sat)']
        induction = chain(k, False) + [f'(assert ({top}_a s{step}))' for step in range(k)]
        induction += [f'(assert (not ({top}_a s{k})))', '(check-sat)']
        queries = dict(base='\n'.join(base) + '\n', induction='\n'.join(induction) + '\n')
        jobs = []
        for solver in solvers:
            for phase, query in queries.items():
                if solver == 'cvc5' and phase == 'induction' and args.cvc5_base_only:
                    continue
                label = solver + '-' + phase
                prefix = (f'(set-option :timeout {args.timeout * 1000})\n' if solver == 'z3' else
                          f'(set-logic QF_AUFBV)\n(set-option :tlimit-per {args.timeout * 1000})\n')
                path = run / (label + '.smt2')
                path.write_text(prefix + query)
                jobs.append((solver, phase, label, path))
        def solve(job):
            solver, phase, label, path = job
            command = ([solver, '-smt2', str(path)] if solver == 'z3' else
                       [solver, '--lang=smt2', '--incremental', str(path)])
            begin = time.monotonic()
            code, timed_out = None, False
            with (run / (label + '.log')).open('w') as stream:
                try:
                    child = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT,
                                           timeout=args.timeout * 2 + 20)
                    code = child.returncode
                except subprocess.TimeoutExpired:
                    timed_out = True
            output = (run / (label + '.log')).read_text()
            answers = [line for line in output.splitlines() if line in ('sat', 'unsat', 'unknown')]
            expected = ['sat', 'unsat'] if phase == 'base' else ['unsat']
            row = dict(passed=code == 0 and answers == expected and '(error ' not in output,
                       exit=code, timed_out=timed_out, answers=answers, expected=expected,
                       seconds=time.monotonic() - begin, query_sha256=sha(path.read_bytes()),
                       log_sha256=sha((run / (label + '.log')).read_bytes()))
            print(label + ' ' + json.dumps(row), flush=True)
            return label, row
        with ThreadPoolExecutor(max_workers=2) as pool:
            solver_results = dict(pool.map(solve, jobs))
    unchanged = all(sha((run / name).read_bytes()) == row['sha256'] for name, row in inputs['files'].items())
    passed = result.returncode == 0 and bool(solver_results) and all(row['passed'] for row in solver_results.values()) and unchanged
    finished = dict(schema='seeded-component-formal-result-v1', passed=passed,
        yosys_exit=result.returncode, assertion_cells=count, memory_cells=memories,
        assumption_cells=0, source_files_unchanged=unchanged, solver_results=solver_results,
        seconds=time.monotonic() - started, inputs_sha256=sha((run / 'INPUTS.json').read_bytes()),
        yosys_log_sha256=sha((run / 'yosys.log').read_bytes()), scope=scope,
        whole_machine_refinement=False, numerical_sampler_equivalence=False,
        hardware_access=False, network_access=False)
    (run / 'FINISHED.json').write_text(json.dumps(finished, indent=2, sort_keys=True) + '\n')
    print(json.dumps(finished), flush=True)
    return 0 if passed else 1


if __name__ == '__main__': raise SystemExit(main())
