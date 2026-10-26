"""Exact-source token-shell control proof, with its real arithmetic children.

No private value cutpoints, hierarchy stubs, hardware, network or production
edits. Existing unqualified `ifdef FORMAL checks are not enabled; the explicit
monitor defines this proof's obligations and all of its assertions are counted.
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


def sha(data): return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--run', required=True, type=Path)
    parser.add_argument('--yosys', default='yosys')
    parser.add_argument('--z3', default='z3')
    parser.add_argument('--induction', type=int, default=2)
    parser.add_argument('--tape', action='store_true',
                        help='Add the symbolic-slot tape observer; no production value cutpoints.')
    args = parser.parse_args()
    assert 1 <= args.induction <= 8
    here = Path(__file__).absolute().parent
    package = here.parents[1]
    manifest_raw = (package / 'MANIFEST.json').read_bytes()
    manifest = json.loads(manifest_raw)['files']
    basenames = ('board0_exact_isqrt_u45_iterative.sv', 'board0_exact_rne_div_signed64_iterative.sv',
        'board1_private_ddr256_to_w640.sv', 'board1_fixed_elementwise_dsp_lane.sv',
        'board1_fixed_group_ddr_stream.sv', 'board1_fixed_head_argmax.sv',
        'board1_fixed_head_logit_greater.sv', 'board1_fixed_projection_metadata_reader.sv',
        'board1_fixed_embedding_lookup.sv', 'normalizer_pipeline.sv',
        'board1_fixed_rmsnorm_arithmetic.sv', 'board1_fixed_rmsnorm_rom.sv',
        'board1_fixed_vector_rmsnorm_service.sv', 'candidate.sv',
        'board1_context2048_token_shell.sv', 'norm_rom34.memh')
    monitor = (here / 'control_monitor.inc.sv').read_bytes()
    if args.tape:
        monitor += b'\n' + (here / 'tape_monitor.inc.sv').read_bytes()
    assert b'assume(' not in monitor
    count = monitor.count(b'assert(')
    run = args.run.absolute()
    run.mkdir(parents=True, exist_ok=False)
    files = {'monitor.inc.sv': monitor, 'runner.py': Path(__file__).read_bytes()}
    sources = []
    origin = {}
    for basename in basenames:
        matches = [name for name in manifest if name.startswith('hardware/project/') and Path(name).name == basename]
        assert len(matches) == 1, (basename, matches)
        name = matches[0]
        data = (package / name).read_bytes()
        assert sha(data) == manifest[name]['sha256']
        relative = name.removeprefix('hardware/project/')
        origin[relative] = {'package_source': name, 'sha256': sha(data)}
        if basename == 'board1_context2048_token_shell.sv':
            files['production_shell.sv'] = data
            assert data.count(b'\nendmodule') == 1
            data = data.replace(b'\nendmodule', b'\n' + monitor + b'\nendmodule')
        if basename.endswith('.sv'):
            # -formal still defines FORMAL with -nosynthesis in this Yosys
            # build. Explicitly use the production macro environment for
            # each file, leaving the selected unconditional monitor active.
            data = b'`undef FORMAL\n' + data
        files[relative] = data
        if basename.endswith('.sv'): sources.append(relative)
    assert origin == json.loads((here / 'sources.json').read_text())
    commands = ['read_verilog -formal -sv -nosynthesis -D SYNTHESIS -defer ' + ' '.join(sources),
        'prep -top board1_context2048_token_shell -flatten', 'async2sync',
        'chformal -lower', 'opt_clean', 'dffunmap',
        f'select -assert-count {count} t:$assert', 'select -assert-none t:$assume',
        'select -assert-none t:$anyseq',
        f'select -assert-count {1 if args.tape else 0} t:$anyconst', 'check -assert',
        'write_json elaborated.json', 'write_rtlil elaborated.il',
        'write_smt2 -wires design.smt2']
    files['prove.ys'] = ('\n'.join(commands) + '\n').encode()
    for name, data in files.items():
        path = run / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    inputs = {'source_package_sha256': sha(manifest_raw), 'origins': origin,
              'files': {name: {'sha256': sha(data), 'bytes': len(data)} for name, data in files.items()},
              'assertions': count, 'cutpoints': [], 'macros': ['SYNTHESIS'],
              'verification_prefix': '`undef FORMAL\\n on each SystemVerilog file',
              'legacy_formal_blocks_enabled': False, 'hardware_access': False,
              'environment': 'Unconstrained public and private input ports; reset at SMT base states 0 and 1 only; no reset constraint in induction.',
              'induction_length': args.induction,
              'observer': {'name': 'f_tape_slot', 'width': 12, 'kind': '$anyconst',
                           'meaning': 'Universally checked constant observation index; no fanout into production control/data.'} if args.tape else None,
              'scope': ('Token-shell control plus per-slot transaction contents, tape overwrite-before-read after reset/CLEAR, and published-token/tape agreement. No numerical fixed-model or whole-private-memory noninterference proof.' if args.tape else
                        'Token-shell command/tape-register/STEP-credit/CLEAR control safety, not numerical refinement or post-CLEAR value noninterference.')}
    (run / 'INPUTS.json').write_text(json.dumps(inputs, indent=2) + '\n')
    print(f'CONTROL_PROOF_STARTED sources={len(sources)} assertions={count} run={run}', flush=True)
    start = time.time()
    yosys = shutil.which(args.yosys)
    with (run / 'yosys.log').open('w') as log:
        result = subprocess.run([yosys, '-Q', 'prove.ys'], cwd=run, stdout=log, stderr=subprocess.STDOUT)
    log = (run / 'yosys.log').read_text()
    cells = []
    if (run / 'elaborated.json').is_file():
        design = json.loads((run / 'elaborated.json').read_text())
        cells = [cell['type'] for module in design['modules'].values() for cell in module.get('cells', {}).values()]
    solver_records = {}
    if result.returncode == 0:
        assert cells.count('$assert') == count and '$assume' not in cells
        assert '$anyseq' not in cells and cells.count('$anyconst') == (1 if args.tape else 0)
        assert '$mem_v2' in cells, 'Actual memories must remain in the SMT array model.'
        smt = (run / 'design.smt2').read_text()
        top = 'board1_context2048_token_shell'
        assert len(re.findall(r'^; yosys-smt2-assert ', smt, re.M)) == count
        assert '; yosys-smt2-assume ' not in smt
        k = args.induction
        def state_chain(last, initial):
            parts = ['(set-option :produce-models true)', '(set-option :timeout 120000)', smt]
            for step in range(last + 1):
                parts += [f'(declare-fun s{step} () {top}_s)', f'(assert ({top}_h s{step}))',
                          f'(assert ({top}_u s{step}))',
                          f'(assert (= ({top}_is s{step}) {"true" if initial and step == 0 else "false"}))']
                if step: parts.append(f'(assert ({top}_t s{step-1} s{step}))')
            if initial:
                parts += [f'(assert ({top}_i s0))',
                          f'(assert (not (|{top}_n rst_n| s0)))',
                          f'(assert (not (|{top}_n rst_n| s1)))']
            return parts
        base = state_chain(max(k, 2), True)
        base += ['(check-sat)', '(assert (not (and ' + ' '.join(
                 f'({top}_a s{step})' for step in range(max(k, 2) + 1)) + ')))', '(check-sat)']
        induction = state_chain(k, False)
        induction += [f'(assert ({top}_a s{step}))' for step in range(k)]
        induction += [f'(assert (not ({top}_a s{k})))', '(check-sat)']
        queries = {'base': '\n'.join(base) + '\n', 'induction': '\n'.join(induction) + '\n'}
        for label, query in queries.items(): (run / (label + '.smt2')).write_text(query)
        def solve(label):
            query = run / (label + '.smt2')
            started = time.time()
            with (run / (label + '.log')).open('w') as output:
                child = subprocess.run([shutil.which(args.z3), '-smt2', str(query)], stdout=output, stderr=subprocess.STDOUT)
            output = (run / (label + '.log')).read_text()
            answers = [line for line in output.splitlines() if line in ('sat', 'unsat', 'unknown')]
            expected = ['sat', 'unsat'] if label == 'base' else ['unsat']
            row = {'passed': child.returncode == 0 and answers == expected and '(error ' not in output,
                   'exit': child.returncode, 'answers': answers, 'seconds': time.time() - started,
                   'query_sha256': sha(query.read_bytes()), 'log_sha256': sha(output.encode())}
            if answers and answers[-1] == 'sat':
                # Preserve an explicit diagnostic model; an inductive SAT
                # witness is not claimed to be reset-reachable.
                signals = ['state_q', 'tape_count_q', 'committed_count_q', 'replay_position_q',
                           'rst_n', 'clear_i', 'fail_q', 'f_pending_step', 'f_result_committed',
                           'f_seen_edge', 'f_expected_count', 'f_expected_prefix',
                           'f_store_result', 'token_valid_o', 'generated_token_q',
                           'model_lock_i', 'upstream_fault_i', 'child_fault', 'ddr_owner_q']
                if args.tape:
                    signals += ['f_tape_slot', 'f_slot_live', 'f_slot_written', 'f_slot_is_result',
                                'f_slot_expected', 'f_slot_observed', 'f_read_is_selected',
                                'f_read_expected', 'tape_read_q', 'append_transfer', 'append_token_i',
                                'generated_commit', 'completing_winner', 'f_add_append']
                model_query = query.read_text() + '(get-value (' + ' '.join(
                    f'(|{top}_n {signal}| s{step})' for step in range((max(k, 2) if label == 'base' else k) + 1)
                    for signal in signals) + ' ' + ' '.join(
                    f'(|{top}_a {index}| s{max(k, 2) if label == "base" else k})'
                    for index in range(count)) + '))\n'
                (run / (label + '-model.smt2')).write_text(model_query)
                with (run / (label + '-model.log')).open('w') as output:
                    subprocess.run([shutil.which(args.z3), '-smt2', str(run / (label + '-model.smt2'))],
                                   stdout=output, stderr=subprocess.STDOUT)
            print('CONTROL_SMT_' + label + ' ' + json.dumps(row), flush=True)
            return label, row
        with ThreadPoolExecutor(max_workers=2) as pool:
            solver_records = dict(pool.map(solve, queries))
    unchanged = all(sha((run / name).read_bytes()) == row['sha256'] for name, row in inputs['files'].items())
    passed = (result.returncode == 0 and len(solver_records) == 2 and all(row['passed'] for row in solver_records.values()) and cells.count('$assert') == count and
              '$assume' not in cells and '$anyseq' not in cells and cells.count('$anyconst') == (1 if args.tape else 0) and unchanged)
    record = {'passed': passed, 'exit': result.returncode, 'seconds': time.time() - start,
              'assertion_cells': cells.count('$assert'), 'assumption_cells': cells.count('$assume'),
              'observer_constant_cells': cells.count('$anyconst'),
              'source_unchanged': unchanged, 'hardware_access': False,
              'inputs_sha256': sha((run / 'INPUTS.json').read_bytes()),
              'log_sha256': sha((run / 'yosys.log').read_bytes()),
              'induction_length': args.induction, 'solver_results': solver_records,
              'scope': inputs['scope'],
              'failure_classification': None if passed else ('BOUNDED_COUNTEREXAMPLE' if solver_records.get('base', {}).get('answers') == ['sat', 'sat'] else 'UNRESOLVED_OR_SETUP_FAILURE')}
    (run / 'FINISHED.json').write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps(record, indent=2), flush=True)
    raise SystemExit(0 if passed else 1)


if __name__ == '__main__': main()
