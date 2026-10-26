"""Check fresh portable replay receipts and preserve secondary-solver limits."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys

assert sys.flags.isolated and sys.flags.no_site and sys.flags.dont_write_bytecode and not sys.flags.optimize
HERE = Path(__file__).resolve().parent


def sha(raw): return hashlib.sha256(raw).hexdigest()
def read(path): return json.loads(path.read_text())
def pin(path): return dict(sha256=sha(path.read_bytes()), bytes=path.stat().st_size)
def module(name):
    spec = importlib.util.spec_from_file_location('seeded_' + name.replace('/', '_'), HERE / (name + '.py'))
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value); return value


def check_phase(proof, result, label, expected):
    row = result['solver_results'][label]
    assert row['passed'] and row['exit'] == 0 and not row['timed_out']
    query, log = proof / (label + '.smt2'), proof / (label + '.log')
    assert sha(query.read_bytes()) == row['query_sha256'] and sha(log.read_bytes()) == row['log_sha256']
    text = log.read_text()
    assert '(error ' not in text
    assert [line for line in text.splitlines() if line in ('sat', 'unsat', 'unknown')] == row['answers'] == expected
    return row


def options_removed(text):
    return '\n'.join(line for line in text.splitlines() if not line.startswith(('(set-option ', '(set-logic '))) + '\n'


def check_split(proof, run, count):
    inputs, result = read(run / 'INPUTS.json'), read(run / 'FINISHED.json')
    assert result['passed'] and result['passed_conclusions'] == result['conclusions'] == count
    assert result['inputs_sha256'] == sha((run / 'INPUTS.json').read_bytes())
    assert inputs['parent_inputs_sha256'] == sha((proof / 'INPUTS.json').read_bytes())
    assert inputs['parent_finished_sha256'] == sha((proof / 'FINISHED.json').read_bytes())
    assert inputs['design_sha256'] == sha((proof / 'design.smt2').read_bytes())
    parent = read(proof / 'INPUTS.json'); top, k = parent['top'], parent['induction_length']
    query = options_removed((proof / 'z3-induction.smt2').read_text())
    goal = f'(assert (not ({top}_a s{k})))'; assert query.count(goal) == 1
    assert {row['assertion'] for row in result['results'].values()} == set(range(count))
    for name, row in result['results'].items():
        assert row['passed'] and row['exit'] == 0 and not row['timed_out'] and row['answers'] == ['unsat']
        q, log = run / (name + '.smt2'), run / (name + '.log')
        assert sha(q.read_bytes()) == row['query_sha256'] == inputs['query_files'][q.name]
        assert sha(log.read_bytes()) == row['log_sha256'] and log.read_text().splitlines() == ['unsat']
        assert options_removed(q.read_text()) == query.replace(goal,
            f'(assert (not (|{top}_a {row["assertion"]}| s{k})))')
    return dict(passed=True, conclusions=count, same_joint_prior_assertions=True,
                inputs=pin(run / 'INPUTS.json'), result=pin(run / 'FINISHED.json'))


def bounded_query(smt, top, actual):
    labels = re.findall(r'^; yosys-smt2-assert (\d+) ([^\n]+)', smt, re.M)
    parts = [smt]
    for step in range(5):
        parts += [f'(declare-fun s{step} () {top}_s)', f'(assert ({top}_h s{step}))',
                  f'(assert ({top}_u s{step}))',
                  f'(assert (= ({top}_is s{step}) {"true" if step == 0 else "false"}))']
        if step: parts.append(f'(assert ({top}_t s{step-1} s{step}))')
    parts += [f'(assert ({top}_i s0))', f'(assert (not (|{top}_n reset_n| s0)))',
              f'(assert (not (|{top}_n reset_n| s1)))', '(check-sat)',
              '(assert (not (and ' + ' '.join(f'({top}_a s{step})' for step in range(5)) + ')))', '(check-sat)']
    if not actual:
        values = [f'(|{top}_a {index}| s{step})' for step in range(5) for index, _ in labels]
        for step in range(5):
            values += [f'(|{top}_n {signal}| s{step})' for signal in
                       ('reset_n','clear_i','model_locked_i','upstream_fail_closed_i',
                        'settings_valid_i','settings_empty_boundary_i','settings_temperature_i','settings_seed_i',
                        'state_q','fail_q','temperature_q','seed_q','rng_lo_q','rng_hi_q')]
        parts.append('(get-value (' + ' '.join(values) + '))')
    return '\n'.join(parts) + '\n'


def check_bounded_query(query, smt, top, actual):
    assert options_removed(query) == bounded_query(smt, top, actual)


def selector_control_inputs(buffer):
    driver = module('run_proof')
    files, origins, sources, top, reset, count, _ = driver.prepare('selector-buffer' if buffer else 'selector')
    edits = {
        'settings-ignores-empty-boundary': [('if (!settings_empty_boundary_i || settings_temperature_i > 3)', 'if (settings_temperature_i > 3)')],
        'settings-accepts-invalid-temperature': [('if (!settings_empty_boundary_i || settings_temperature_i > 3)', 'if (!settings_empty_boundary_i || settings_temperature_i > 7)')],
        'settings-drops-high-seed-word': [("seed_q <= settings_seed_i == 0 ? 128'd1 : settings_seed_i;", "seed_q <= settings_seed_i == 0 ? 128'd1 : {64'd0,settings_seed_i[63:0]};")],
        'settings-loses-start-priority': [('!settings_valid_i && greedy_start_ready;', 'greedy_start_ready;')],
        'greedy-idle-advances-random': [('IDLE: begin\n                        if (settings_valid_i', "IDLE: begin\n                        rng_lo_q <= rng_lo_q + 64'd1;\n                        if (settings_valid_i")],
        'clear-reseed-wrong-word': [('rng_lo_q <= seed_q[63:0]; rng_hi_q <= seed_q[127:64];', "rng_lo_q <= seed_q[63:0] ^ 64'd1; rng_hi_q <= seed_q[127:64];")],
        'clear-revives-terminal-fault': [
            ('if (fail_q || greedy_fault || upstream_fail_closed_i || settings_x_fault ||\n                (state_q != IDLE && !model_locked_i)) begin', 'if ((fail_q || greedy_fault || upstream_fail_closed_i || settings_x_fault ||\n                (state_q != IDLE && !model_locked_i)) && !clear_i) begin'),
            ('end else if (clear_i) begin\n                state_q <= IDLE;', "end else if (clear_i) begin\n                fail_q <= 0;\n                state_q <= IDLE;")]}
    if buffer:
        anchor = 'state_q <= COLLECT;\n                            cursor_q <= 0;'
        edits = {'positive-start-reads-logits-before-head': [(anchor, 'state_q <= greedy_mode ? COLLECT : ROW_READ;\n                            cursor_q <= 0;')],
                 'positive-start-reads-mass-before-pass': [(anchor, 'state_q <= greedy_mode ? COLLECT : CDF_READ;\n                            cursor_q <= 0;')]}
    variants = {'actual-bmc': (files['board1_seeded_head_selector.sv'], [])}
    for name, changes in edits.items():
        text = files['board1_seeded_head_selector.sv'].decode()
        for old, new in changes: assert text.count(old) == 1; text = text.replace(old, new)
        variants[name] = (text.encode(), [dict(old=old, new=new) for old, new in changes])
    commands = ['read_verilog -formal -sv -nosynthesis -D SYNTHESIS -defer ' + ' '.join(sources),
        f'prep -top {top} -flatten', 'async2sync', 'chformal -lower', 'opt_clean', 'dffunmap',
        f'select -assert-count {count} t:$assert', 'select -assert-none t:$assume',
        'select -assert-none t:$anyseq', 'select -assert-count ' + ('1' if buffer else '0') + ' t:$anyconst',
        'check -assert', 'write_json elaborated.json', 'write_smt2 -wires design.smt2']
    return files, origins, variants, '\n'.join(commands) + '\n'


def serial_control_inputs():
    provider = module('source_provider'); inventory = provider.source_inputs()
    prefix = 'project/fpga/token_only_model0_mac_uart0/rtl/'
    files = {name: (provider.SOURCE / (prefix + name)).read_bytes()
             for name in ('fixed_uart_rx.sv', 'fixed_uart_tx.sv', 'token_only_model0_uart_bridge.sv')}
    source = files['token_only_model0_uart_bridge.sv'].decode()
    edits = {
        'settings-crc-bypass': ("else if (request_unknown || rx_byte != request_crc_q)\n                            prepare_response(8'hcf,12'd0);", "else if (request_unknown)\n                            prepare_response(8'hcf,12'd0);"),
        'settings-seed-corruption': ('settings_seed_q <= request_seed_q;', "settings_seed_q <= request_seed_q ^ 128'd1;"),
        'settings-invalid-temperature-truncation': ('else if (request_token_low_q > 3)', 'else if (request_token_low_q[1:0] > 3)'),
        'settings-overtakes-busy-step': ('if (state_q != BRIDGE_IDLE) begin end', "if (1'b0) begin end"),
        'settings-timeout-keeps-frame': ('if (settings_timed_out) begin\n                request_index_q <= 0;', 'if (settings_timed_out) begin\n                request_index_q <= request_index_q;')}
    variants = {'actual': (source.encode(), None)}
    for name, (old, new) in edits.items():
        assert source.count(old) == 1
        variants[name] = (source.replace(old, new).encode(), dict(old=old, new=new))
    return files, variants, {prefix + name: inventory[prefix + name] for name in files}


def check_controls(run, count, formal, expected_model=None):
    inputs, result = read(run / 'INPUTS.json'), read(run / 'FINISHED.json')
    assert result['passed'] and result['inputs_sha256'] == sha((run / 'INPUTS.json').read_bytes())
    assert result['bounded_fault_controls' if formal else 'faulty_controls'] == count
    assert len(result['results']) == count + 1
    if formal:
        buffer = count == 2
        files, origins, variants, commands = selector_control_inputs(buffer)
        assert (run / 'checker.py').read_bytes() == (HERE / 'check_selector_faults.py').read_bytes()
        assert inputs['original_source_sha256'] == origins['board1_seeded_head_selector.sv']['sha256']
        assert inputs['monitor_sha256'] == sha(files['monitor.inc.sv'])
        assert inputs['reset_at_states'] == [0, 1] and inputs['bounded_last_state'] == 4
    else:
        files, variants, production_sources = serial_control_inputs()
        assert (run / 'checker.py').read_bytes() == (HERE / 'check_uart_faults.py').read_bytes()
        assert inputs['production_sources'] == production_sources
        assert inputs['testbench_sha256'] == sha((HERE / 'test_settings_uart.sv').read_bytes())
        assert inputs['clocks_per_bit'] == 217
    assert set(inputs['variants']) == set(result['results']) == set(variants)
    for name, row in result['results'].items():
        assert row['passed'] and not row.get('timed_out', False)
        path = run / name
        if formal:
            changed, edits = variants[name]
            assert inputs['variants'][name]['edits'] == edits
            assert inputs['variants'][name]['mutated_source_sha256'] == sha(changed)
            for path_name, data in files.items():
                assert (path / path_name).read_bytes() == (changed if path_name == 'board1_seeded_head_selector.sv' else data)
            assert (path / 'prove.ys').read_text() == commands
            assert row['yosys_exit'] == 0 and row['exit'] == 0 and row['memory_cells'] == 3
            assert sha((path / 'query.smt2').read_bytes()) == row['query_sha256']
            smt = (path / 'design.smt2').read_text()
            check_bounded_query((path / 'query.smt2').read_text(), smt, 'board1_seeded_head_selector', name == 'actual-bmc')
            raw = (path / 'z3.log').read_text(); assert sha(raw.encode()) == row['log_sha256']
            assert '(error ' not in raw
            assert [line for line in raw.splitlines() if line in ('sat', 'unsat', 'unknown')] == (['sat', 'unsat'] if name == 'actual-bmc' else ['sat', 'sat'])
            actual = (path / 'board1_seeded_head_selector.sv').read_bytes()
            assert sha(actual) == inputs['variants'][name]['mutated_source_sha256']
            design = read(path / 'elaborated.json')
            types = [cell['type'] for value in design['modules'].values() for cell in value['cells'].values()]
            assert types.count('$mem_v2') == 3 and not {'$assume', '$anyseq'} & set(types)
            if name == 'actual-bmc': assert sha((path / 'design.smt2').read_bytes()) == expected_model
            else: assert row['reset_reachable_counterexample'] and row['violated_assertions']
        else:
            changed, edit = variants[name]
            assert inputs['variants'][name]['edit'] == edit
            assert inputs['variants'][name]['mutated_source_sha256'] == sha(changed)
            for path_name, data in files.items():
                assert (path / path_name).read_bytes() == (changed if path_name == 'token_only_model0_uart_bridge.sv' else data)
            assert (path / 'test_settings_uart.sv').read_bytes() == (HERE / 'test_settings_uart.sv').read_bytes()
            assert row['build_exit'] == 0
            build, simulation = (path / 'build.log').read_bytes(), (path / 'simulation.log').read_bytes()
            assert sha(build) == row['build_log_sha256'] and sha(simulation) == row['simulation_log_sha256']
            assert sha((path / 'token_only_model0_uart_bridge.sv').read_bytes()) == inputs['variants'][name]['mutated_source_sha256']
            if name == 'actual': assert row['exit'] == 0 and b'PASS_SETTINGS_UART cases=284' in simulation
            else: assert row['deliberately_faulty_copy_detected'] and row['exit'] != 0 and b'FATAL:' in simulation
    return dict(passed=True, faulty_controls=count, formal_bounded_counterexamples=formal,
                inputs=pin(run / 'INPUTS.json'), result=pin(run / 'FINISHED.json'))


def check_connected(run, summary, binding, auditor):
    proof, audit = run / 'connected-primary', run / 'connected-audit'
    inputs, result = read(proof / 'INPUTS.json'), read(proof / 'FINISHED.json')
    connected_driver, connected_auditor = module('connected/run_connected'), module('connected/audit_connected')
    files, compile_sources, derived = connected_driver.derive()
    assert {key: inputs[key] for key in derived} == json.loads(json.dumps(derived))
    assert inputs['source_binding'] == binding and inputs['induction_length'] == 2
    assert result['passed'] and result['input_hashes_unchanged'] and result['elaboration_exit'] == 0
    assert result['assertions'] == result['assertion_cells'] == 196 and result['memory_cells'] == 20
    assert result['assumption_cells'] == 0 and len(inputs['private_semantic_output_cuts']) == 37
    assert result['inputs_sha256'] == sha((proof / 'INPUTS.json').read_bytes())
    assert set(inputs['files']) == set(files) | {'prove.ys', 'runner.py', 'core-settings-monitor.inc.sv', 'connection-settings-monitor.inc.sv', 'baseline-driver.py'}
    assert (proof / 'prove.ys').read_bytes() == auditor.expected_recipe(compile_sources, inputs['top'], 196, 1)
    for name, row in inputs['files'].items(): assert pin(proof / name) == row, name
    for name, data in files.items(): assert (proof / name).read_bytes() == data, name
    assert (proof / 'runner.py').read_bytes() == (HERE / 'connected/run_connected.py').read_bytes()
    for name, digest in result['proof_artifacts_sha256'].items(): assert sha((proof / name).read_bytes()) == digest
    smt = (proof / 'design.smt2').read_text(); top = inputs['top']
    for label in ('z3-base', 'z3-induction'):
        check_phase(proof, result, label, ['sat', 'unsat'] if label.endswith('base') else ['unsat'])
        assert options_removed((proof / (label + '.smt2')).read_text()) == options_removed(
            auditor.canonical_query(smt, top, 'reset_n_i', 2, label.split('-')[-1]))
    audited = read(audit / 'FINISHED.json')
    assert audited['passed'] and audited['proof_inputs_sha256'] == result['inputs_sha256']
    assert audited['exact_baseline_private_output_cuts'] == 37 and audited['no_extra_cuts']
    assert (audit / 'auditor.py').read_bytes() == (HERE / 'connected/audit_connected.py').read_bytes()
    for name, digest in audited['replay_artifacts_sha256'].items():
        assert sha((proof / name).read_bytes()) == digest == sha((audit / 'elaboration-replay' / name).read_bytes())
    model = read(proof / 'elaborated.json')['modules'][top]
    assert connected_auditor.observer_cone(model) == audited['observer_cone']
    baseline_path = connected_driver.PUBLIC / 'formal/composed-shell/run_proof.py'
    spec = importlib.util.spec_from_file_location('unchanged_baseline_driver', baseline_path)
    baseline = importlib.util.module_from_spec(spec); spec.loader.exec_module(baseline)
    _, _, original = baseline.derive()
    assert original['wrapper_ports'] == derived['wrapper_ports']
    assert original['private_semantic_output_cuts'] == derived['private_semantic_output_cuts']
    assert summary['primary_passed'] and summary['audit_passed'] and summary['source_binding'] == binding
    primary = summary['primary']
    assert primary['path'] == str(proof.relative_to(HERE))
    assert primary['inputs_sha256'] == result['inputs_sha256']
    assert primary['finished_sha256'] == sha((proof / 'FINISHED.json').read_bytes())
    assert primary['phase_results'] == result['solver_results'] and primary['assertions'] == 196
    assert primary['memories'] == 20 and primary['assumptions'] == 0
    assert primary['design_sha256'] == sha(smt.encode())
    assert summary['audit']['path'] == str(audit.relative_to(HERE))
    assert summary['audit']['finished_sha256'] == sha((audit / 'FINISHED.json').read_bytes())
    assert summary['audit']['unrestricted_private_output_cuts'] == 37
    prior = options_removed((proof / 'z3-induction.smt2').read_text())
    base = options_removed((proof / 'z3-base.smt2').read_text()).replace('(check-sat)\n', '', 1)
    goal = f'(assert (not ({top}_a s2)))'; assert prior.count(goal) == 1
    passed, attempted, base_passed = set(), set(), False
    locations = dict(re.findall(r'^; yosys-smt2-assert (\d+) ([^\n]+)', smt, re.M))
    for receipt in summary['secondary']['receipts']:
        path = (HERE / receipt['path']).absolute(); assert HERE in path.parents
        second_inputs, second = read(path / 'INPUTS.json'), read(path / 'FINISHED.json')
        assert receipt['inputs_sha256'] == sha((path / 'INPUTS.json').read_bytes()) == second['inputs_sha256']
        assert receipt['result_sha256'] == sha((path / 'FINISHED.json').read_bytes())
        assert receipt['checker_sha256'] == sha((path / 'checker.py').read_bytes())
        assert (path / 'checker.py').read_bytes() == (HERE / 'connected/check_connected_conclusions.py').read_bytes()
        assert second_inputs['primary_design_sha256'] == sha(smt.encode())
        assert second_inputs['same_joint_prior_assertions'] and second_inputs['added_assumptions'] == 0
        for name, row in second['results'].items():
            q, log = (path / (name + '.smt2')).read_bytes(), (path / (name + '.log')).read_bytes()
            assert sha(q) == row['query_sha256'] == second_inputs['query_files'][name + '.smt2']
            assert sha(log) == row['log_sha256'] and b'(error' not in log
            answers = [line for line in log.decode().splitlines() if line in ('sat', 'unsat', 'unknown')]
            assert answers == row['answers'] and 'sat' not in answers
            assert answers in (['unsat'], ['unknown']) or (not answers and row['timed_out'])
            if name == 'base':
                assert options_removed(q.decode()) == base
                if row['passed']: assert row['exit'] == 0 and not row['timed_out'] and answers == ['unsat']; base_passed = True
            else:
                index = int(name[len('conclusion-'):]); assert 0 <= index < 196
                attempted.add(index)
                assert options_removed(q.decode()) == prior.replace(goal, f'(assert (not (|{top}_a {index}| s2)))')
                if row['passed']: assert row['exit'] == 0 and not row['timed_out'] and answers == ['unsat']; passed.add(index)
    secondary = summary['secondary']
    assert secondary['base_passed'] == base_passed
    assert secondary['attempted_conclusions'] == len(attempted) and secondary['passed_conclusions'] == len(passed)
    assert secondary['passed_conclusion_indexes'] == sorted(passed)
    assert secondary['unresolved_conclusions'] == [dict(assertion=i, source=locations[str(i)]) for i in range(196) if i not in passed]
    assert secondary['complete'] == (base_passed and len(passed) == 196)
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--require-recorded-model', action='store_true', help='Require exact recorded Yosys model digests')
    args = parser.parse_args(); run = args.run.absolute()
    provider, driver, auditor = module('source_provider'), module('run_proof'), module('audit_components')
    binding = provider.source_binding()
    assert read(run / 'SOURCE-BINDING.json') == binding
    recorded = read(HERE / 'recorded/RESULTS.json')
    lanes, all_match = {}, True
    names = {'selector': 'selector_lifecycle', 'selector-buffer': 'sampler_buffer_ownership', 'uart': 'uart', 'shell': 'shell'}
    for case, expected_count in [('selector', 35), ('selector-buffer', 57), ('uart', 63), ('shell', 94)]:
        proof, audit = run / case, run / ('audit-' + case)
        inputs, result = read(proof / 'INPUTS.json'), read(proof / 'FINISHED.json')
        assert result['passed'] and result['yosys_exit'] == 0 and result['assertion_cells'] == expected_count
        assert result['assumption_cells'] == 0 and result['source_files_unchanged']
        assert result['inputs_sha256'] == sha((proof / 'INPUTS.json').read_bytes())
        assert inputs['source_binding'] == binding and inputs['internal_value_or_handshake_cuts'] == []
        files, origins, compile_sources, top, reset, count, _ = driver.prepare(case)
        assert count == expected_count and origins == inputs['origins']
        assert set(inputs['files']) == set(files) | {'prove.ys', 'runner.py'}
        assert (proof / 'runner.py').read_bytes() == (HERE / 'run_proof.py').read_bytes()
        assert (proof / 'prove.ys').read_bytes() == auditor.expected_recipe(compile_sources, top, count, 1 if case in ('shell', 'selector-buffer') else 0)
        for name, row in inputs['files'].items(): assert pin(proof / name) == row, name
        for name, data in files.items(): assert (proof / name).read_bytes() == data, name
        smt = (proof / 'design.smt2').read_text()
        phases = ['z3-base', 'z3-induction', 'cvc5-base']
        if case not in ('uart', 'shell'): phases.append('cvc5-induction')
        for label in phases:
            check_phase(proof, result, label, ['sat', 'unsat'] if label.endswith('base') else ['unsat'])
            assert options_removed((proof / (label + '.smt2')).read_text()) == options_removed(
                auditor.canonical_query(smt, top, reset, inputs['induction_length'], label.split('-')[-1]))
        audited = read(audit / 'FINISHED.json')
        assert audited['passed'] and audited['proof_inputs_sha256'] == result['inputs_sha256']
        assert audited['proof_finished_sha256'] == sha((proof / 'FINISHED.json').read_bytes())
        assert (audit / 'auditor.py').read_bytes() == (HERE / 'audit_components.py').read_bytes()
        for name, digest in audited['replay_artifacts_sha256'].items():
            assert sha((proof / name).read_bytes()) == digest == sha((audit / 'elaboration-replay' / name).read_bytes())
        model_sha = sha(smt.encode()); matched = model_sha == recorded['component_lanes'][names[case]]['model_sha256']
        all_match &= matched
        lane = dict(assertions=expected_count, memories=result['memory_cells'], primary_passed=True,
                    second_solver_complete=True, matches_recorded_model=matched, model_sha256=model_sha,
                    result=pin(proof / 'FINISHED.json'), audit=pin(audit / 'FINISHED.json'))
        if case in ('uart', 'shell'): lane['second_solver_conclusions'] = check_split(proof, run / ('conclusions-' + case), expected_count)
        lanes[case] = lane
    controls = dict(selector=check_controls(run / 'selector-controls', 7, True, lanes['selector']['model_sha256']),
        buffers=check_controls(run / 'buffer-controls', 2, True, lanes['selector-buffer']['model_sha256']),
        serial=check_controls(run / 'uart-controls', 5, False))
    connected = check_connected(run, read(run / 'CONNECTED.json'), binding, auditor)
    matched = connected['primary']['design_sha256'] == recorded['connected']['model_sha256']; all_match &= matched
    assert connected['secondary']['complete'] == (connected['secondary']['base_passed'] and connected['secondary']['passed_conclusions'] == 196)
    if args.require_recorded_model: assert all_match, 'Yosys models differ from recorded digests; inspect the fresh source-bound results'
    result = dict(schema='seeded-public-rtl-formal-replay-result-v2', primary_scoped_checks_passed=True,
        source_binding=binding, component_lanes=lanes, connected=connected,
        sensitivity=controls, all_models_match_recorded=all_match, require_recorded_model=args.require_recorded_model,
        recorded_result_sha256=sha((HERE / 'recorded/RESULTS.json').read_bytes()),
        assertion_counts_overlap=True, whole_machine_refinement=False, numerical_cdf_equivalence=False,
        mapped_implementation_equivalence=False, vendor_logic_elaborated=False, hardware_access=False, network_access=False)
    with args.output.open('x') as stream: json.dump(result, stream, indent=2, sort_keys=True); stream.write('\n')
    print('PUBLIC_REPLAY_RECEIPT_PASS models_match_recorded=' + str(all_match), flush=True)


if __name__ == '__main__': main()
