"""Reset-reachable bounded sensitivity controls on full actual selector RTL.

No short vocabulary, internal initialization/cut or changed monitor premises.
Deliberate faults exist only in the isolated negative-control copies.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import time

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('seeded_component_proof_driver', HERE / 'run_proof.py')
driver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(driver)


def sha(data): return hashlib.sha256(data).hexdigest()


def replace_once(source, old, new):
    if source.count(old) != 1: raise ValueError('Expected exact source mutation anchor: ' + old)
    return source.replace(old, new)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', type=Path, required=True)
    parser.add_argument('--buffer-ownership', action='store_true',
                        help='Use full 57-assertion RAM ownership model and two early-read faults')
    args = parser.parse_args()
    files, origins, sources, top, reset, count, scope = driver.prepare(
        'selector-buffer' if args.buffer_ownership else 'selector')
    source = files['board1_seeded_head_selector.sv'].decode()
    variants = {'actual-bmc': (source, [])}
    def mutant(name, edits):
        changed = source
        for old, new in edits: changed = replace_once(changed, old, new)
        variants[name] = (changed, [dict(old=old, new=new) for old, new in edits])
    mutant('settings-ignores-empty-boundary', [
        ('if (!settings_empty_boundary_i || settings_temperature_i > 3)',
         'if (settings_temperature_i > 3)')])
    mutant('settings-accepts-invalid-temperature', [
        ('if (!settings_empty_boundary_i || settings_temperature_i > 3)',
         'if (!settings_empty_boundary_i || settings_temperature_i > 7)')])
    mutant('settings-drops-high-seed-word', [
        ('seed_q <= settings_seed_i == 0 ? 128\'d1 : settings_seed_i;',
         'seed_q <= settings_seed_i == 0 ? 128\'d1 : {64\'d0,settings_seed_i[63:0]};')])
    mutant('settings-loses-start-priority', [
        ('!settings_valid_i && greedy_start_ready;', 'greedy_start_ready;')])
    mutant('greedy-idle-advances-random', [
        ('IDLE: begin\n                        if (settings_valid_i',
         "IDLE: begin\n                        rng_lo_q <= rng_lo_q + 64'd1;\n                        if (settings_valid_i")])
    mutant('clear-reseed-wrong-word', [
        ('rng_lo_q <= seed_q[63:0]; rng_hi_q <= seed_q[127:64];',
         "rng_lo_q <= seed_q[63:0] ^ 64'd1; rng_hi_q <= seed_q[127:64];")])
    mutant('clear-revives-terminal-fault', [
        ('if (fail_q || greedy_fault || upstream_fail_closed_i || settings_x_fault ||\n                (state_q != IDLE && !model_locked_i)) begin',
         'if ((fail_q || greedy_fault || upstream_fail_closed_i || settings_x_fault ||\n                (state_q != IDLE && !model_locked_i)) && !clear_i) begin'),
        ('end else if (clear_i) begin\n                state_q <= IDLE;',
         "end else if (clear_i) begin\n                fail_q <= 0;\n                state_q <= IDLE;")])
    if args.buffer_ownership:
        variants = {'actual-bmc': variants['actual-bmc']}
        mutant('positive-start-reads-logits-before-head', [
            ('state_q <= COLLECT;\n                            cursor_q <= 0;',
             'state_q <= greedy_mode ? COLLECT : ROW_READ;\n                            cursor_q <= 0;')])
        mutant('positive-start-reads-mass-before-pass', [
            ('state_q <= COLLECT;\n                            cursor_q <= 0;',
             'state_q <= greedy_mode ? COLLECT : CDF_READ;\n                            cursor_q <= 0;')])
    run = args.run.absolute()
    run.mkdir(parents=True, exist_ok=False)
    (run / 'checker.py').write_bytes(Path(__file__).read_bytes())
    inventory = dict(schema='seeded-selector-formal-fault-controls-v1',
        original_source_sha256=origins['board1_seeded_head_selector.sv']['sha256'],
        frozen_assembly_sha256=driver.ASSEMBLY_SHA, frozen_inventory_sha256=driver.INVENTORY_SHA,
        assertions=count, reset_at_states=[0, 1], bounded_last_state=4,
        production_parameters_changed=[], internal_cuts=[], added_assumptions=0,
        monitor_sha256=sha(files['monitor.inc.sv']), variants={}, hardware_access=False)
    for name, (changed, edits) in variants.items():
        job = run / name
        job.mkdir()
        for path, data in files.items():
            destination = job / path
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(changed.encode() if path == 'board1_seeded_head_selector.sv' else data)
        script = ['read_verilog -formal -sv -nosynthesis -D SYNTHESIS -defer ' + ' '.join(sources),
                  f'prep -top {top} -flatten', 'async2sync', 'chformal -lower', 'opt_clean', 'dffunmap',
                  f'select -assert-count {count} t:$assert', 'select -assert-none t:$assume',
                  'select -assert-none t:$anyseq',
                  'select -assert-count ' + ('1' if args.buffer_ownership else '0') + ' t:$anyconst',
                  'check -assert', 'write_json elaborated.json', 'write_smt2 -wires design.smt2']
        (job / 'prove.ys').write_text('\n'.join(script) + '\n')
        inventory['variants'][name] = dict(edits=edits, mutated_source_sha256=sha(changed.encode()),
                                          expected=['sat', 'unsat'] if name == 'actual-bmc' else ['sat', 'sat'])
    (run / 'INPUTS.json').write_text(json.dumps(inventory, indent=2, sort_keys=True) + '\n')
    start = time.monotonic()
    def solve(name):
        job = run / name
        begin = time.monotonic()
        with (job / 'yosys.log').open('w') as stream:
            elaboration = subprocess.run(['yosys', '-Q', 'prove.ys'], cwd=job, stdout=stream, stderr=subprocess.STDOUT)
        row = dict(yosys_exit=elaboration.returncode, passed=False)
        if elaboration.returncode == 0:
            smt = (job / 'design.smt2').read_text()
            labels = re.findall(r'^; yosys-smt2-assert (\d+) ([^\n]+)', smt, re.M)
            if len(labels) != count: raise ValueError('Mutant changed assertion inventory')
            parts = ['(set-option :produce-models true)', '(set-option :timeout 60000)', smt]
            for step in range(5):
                parts += [f'(declare-fun s{step} () {top}_s)', f'(assert ({top}_h s{step}))',
                          f'(assert ({top}_u s{step}))',
                          f'(assert (= ({top}_is s{step}) {"true" if step == 0 else "false"}))']
                if step: parts.append(f'(assert ({top}_t s{step-1} s{step}))')
            parts += [f'(assert ({top}_i s0))', f'(assert (not (|{top}_n {reset}| s0)))',
                      f'(assert (not (|{top}_n {reset}| s1)))', '(check-sat)',
                      '(assert (not (and ' + ' '.join(f'({top}_a s{step})' for step in range(5)) + ')))', '(check-sat)']
            if name != 'actual-bmc':
                values = [f'(|{top}_a {index}| s{step})' for step in range(5) for index, _ in labels]
                for step in range(5):
                    values += [f'(|{top}_n {signal}| s{step})' for signal in
                               ('reset_n','clear_i','model_locked_i','upstream_fail_closed_i',
                                'settings_valid_i','settings_empty_boundary_i','settings_temperature_i','settings_seed_i',
                                'state_q','fail_q','temperature_q','seed_q','rng_lo_q','rng_hi_q')]
                parts.append('(get-value (' + ' '.join(values) + '))')
            query = '\n'.join(parts) + '\n'
            (job / 'query.smt2').write_text(query)
            with (job / 'z3.log').open('w') as stream:
                child = subprocess.run(['z3', '-smt2', str(job / 'query.smt2')], stdout=stream,
                                       stderr=subprocess.STDOUT, timeout=130)
            data = (job / 'z3.log').read_bytes()
            output = data.decode()
            answers = [line for line in output.splitlines() if line in ('sat', 'unsat', 'unknown')]
            expected = inventory['variants'][name]['expected']
            false = [(int(index), int(step)) for index, step in re.findall(
                r'\(\(\|' + top + r'_a (\d+)\| s(\d+)\) false\)', output)]
            row.update(passed=child.returncode == 0 and answers == expected and '(error ' not in output
                       and (not args.buffer_ownership or name == 'actual-bmc' or any(index >= 35 for index, _ in false)),
                       exit=child.returncode, answers=answers, expected=expected,
                       reset_reachable_counterexample=name != 'actual-bmc' and answers == ['sat', 'sat'],
                       violated_assertions=[dict(assertion=index, state=step, source=labels[index][1]) for index, step in false],
                       query_sha256=sha(query.encode()), log_sha256=sha(data),
                       memory_cells=sum(cell['type'] == '$mem_v2' for module in json.loads((job / 'elaborated.json').read_text())['modules'].values()
                                        for cell in module.get('cells', {}).values()))
        row['seconds'] = time.monotonic() - begin
        (job / 'FINISHED.json').write_text(json.dumps(row, indent=2, sort_keys=True) + '\n')
        print(name + ' ' + json.dumps({key: value for key, value in row.items() if key != 'violated_assertions'}), flush=True)
        return name, row
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = dict(pool.map(solve, variants))
    record = dict(passed=all(row['passed'] for row in results.values()), actual_plus_mutants=len(results),
        bounded_fault_controls=len(variants) - 1, buffer_ownership=args.buffer_ownership,
        reset_reachable_counterexamples=sum(row.get('reset_reachable_counterexample', False) for row in results.values()),
        seconds=time.monotonic() - start, results=results, inputs_sha256=sha((run / 'INPUTS.json').read_bytes()),
        hardware_access=False, scope='Four post-reset transition steps on full fixed-dimension component. Sensitivity controls are not exhaustive numerical/long-head proofs and do not create production variants.')
    (run / 'FINISHED.json').write_text(json.dumps(record, indent=2, sort_keys=True) + '\n')
    print(json.dumps({key: value for key, value in record.items() if key != 'results'}), flush=True)
    return 0 if record['passed'] else 1


if __name__ == '__main__': raise SystemExit(main())
