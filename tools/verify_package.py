#!/usr/bin/env python3
"""Offline package replay: inventory, model materialization, Lean and UART proof.

Build products and logs go in a fresh sibling work directory, never into the
curated package. There is no network, vendor-tool invocation or board access.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import difflib
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time

if not sys.flags.isolated or not sys.flags.dont_write_bytecode or sys.flags.optimize:
    raise SystemExit('Run with Python -I -B, without -O.')


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def put(path, value):
    with path.open('x') as out:
        json.dump(value, out, indent=2, sort_keys=True); out.write('\n')


def inventory(package):
    # Validate every declared release file, allowing a normal Git checkout's
    # metadata and local app environment/logs. Fresh-export privacy checking is
    # a separate strict audit; local generated files are not release evidence.
    spec = importlib.util.spec_from_file_location('release_inventory', package / 'tools/verify_release.py')
    checker = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(checker)
    return checker.inventory(package)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--upstream', required=True, type=Path)
    parser.add_argument('--rom', required=True, type=Path)
    parser.add_argument('--work', required=True, type=Path)
    parser.add_argument('--yosys', default='yosys')
    parser.add_argument('--lean', default='lean')
    parser.add_argument('--z3', default='z3')
    parser.add_argument('--cvc5', default='cvc5')
    parser.add_argument('--verilator', default='verilator')
    parser.add_argument('--app-python', required=True, type=Path,
                        help='Separate environment with the pinned host requirements installed.')
    options = parser.parse_args()
    package = options.package.resolve(strict=True)
    manifest = inventory(package)
    work = options.work.absolute()
    assert not work.resolve().is_relative_to(package)
    assert not any(c.isspace() for c in str(work)), 'Use a whitespace-free work path or alias.'
    work.mkdir(parents=False, exist_ok=False)
    shutil.copyfile(__file__, work / 'verifier.py')
    records = {}

    def run(name, argv, cwd=work):
        started = time.monotonic()
        with (work / (name + '.log')).open('xb') as output:
            process = subprocess.Popen(argv, cwd=cwd, stdout=output, stderr=subprocess.STDOUT)
            put(work / (name + '-STARTED.json'), {'pid': process.pid, 'argv': argv, 'hardware_access': False})
            code = process.wait()
        text = (work / (name + '.log')).read_text(errors='replace')
        row = {'exit': code, 'argv': argv, 'seconds': time.monotonic() - started,
               'log_sha256': sha(work / (name + '.log'))}
        put(work / (name + '-EXECUTION.json'), row)
        print('PACKAGE_REPLAY ' + name + ' exit=' + str(code), flush=True)
        return row, text

    python = [sys.executable, '-I', '-B']
    upstream = str(options.upstream.resolve(strict=True))
    rom = str(options.rom.resolve(strict=True))
    reference = package / 'reference'
    for name, argv in (
        ('upstream-check', python + [str(reference / 'scripts/fetch_upstream.py'), '--check', upstream]),
        ('quantize-check', python + [str(reference / 'scripts/quantize.py'), upstream, rom, '--check']),
    ):
        row, log = run(name, argv)
        row['passed'] = row['exit'] == 0 and 'PASS' in log and 'FAIL' not in log
        records[name] = row
    materialize = python + [str(package / 'tools/materialize_image.py'),
        '--reference-root', str(reference), '--rom', rom,
        '--hardware-project', str(package / 'hardware/project'), '--output', str(work / 'image')]
    for name, argv in (('materialize', materialize), ('materialize-check', materialize + ['--check'])):
        row, log = run(name, argv)
        row['passed'] = row['exit'] == 0 and 'PASS selected image plus four synthesis ROMs;' in log
        records[name] = row

    uart_source = package / 'hardware/project/fpga/token_only_model0_mac_uart0/rtl'
    uart_proof = package / 'formal/uart/actual'
    for name in ('fixed_uart_rx.sv', 'fixed_uart_tx.sv'):
        assert (uart_source / name).read_bytes() == (uart_proof / name).read_bytes()
    name = 'token_only_model0_uart_bridge.sv'
    original = (uart_source / name).read_text().splitlines(keepends=True)
    instrumented = (uart_proof / name).read_text().splitlines(keepends=True)
    edits = [row for row in difflib.SequenceMatcher(a=original, b=instrumented, autojunk=False).get_opcodes() if row[0] != 'equal']
    assert len(edits) == 1 and edits[0][0] == 'insert'
    inserted = ''.join(instrumented[edits[0][3]:edits[0][4]])
    assert inserted.count('assert(') == 15 and 'assume(' not in inserted

    frame_proof = package / 'formal/frame'
    for name in ('fixed_uart_rx.sv', 'fixed_uart_tx.sv'):
        assert (uart_source / name).read_bytes() == (frame_proof / name).read_bytes()
    frame_lines = (frame_proof / 'token_only_model0_uart_bridge.sv').read_text().splitlines(keepends=True)
    edits = [row for row in difflib.SequenceMatcher(a=original, b=frame_lines, autojunk=False).get_opcodes() if row[0] != 'equal']
    assert len(edits) == 1 and edits[0][0] == 'insert'
    inserted = ''.join(frame_lines[edits[0][3]:edits[0][4]])
    assert inserted.count('assert(') == 46 and 'assume(' not in inserted

    shutil.copytree(package / 'formal/abstract', work / 'abstract')
    expected = json.loads((package / 'formal/uart/expected.json').read_text())
    labels = expected['expected_passing'] + expected['expected_bounded_counterexamples']
    for label in labels: shutil.copytree(package / 'formal/uart' / label, work / label)
    jobs = [('model-rtl', python + ['-S', str(package / 'tools/check_model_rtl.py'),
        '--package', str(package), '--image', str(work / 'image/board1-real-semantic-image2048.bin'),
        '--work', str(work / 'model-rtl'), '--verilator', options.verilator], work),
        ('model-checker-guards', python + ['-S', '-m', 'unittest', 'discover',
         '-s', str(package / 'tools'), '-p', 'test_model_rtl.py', '-v'], work),
        ('lean', [options.lean, 'Board1PublicSurface.lean'], work / 'abstract')]
    jobs += [('uart-' + label, [options.yosys, '-Q', 'prove.ys'], work / label) for label in labels]
    shutil.copytree(frame_proof, work / 'frame')
    jobs.append(('frame-proof', [options.yosys, '-Q', 'prove.ys'], work / 'frame'))
    jobs.append(('frame-traces', python + [str(package / 'tools/check_uart_frames.py'),
        '--package', str(package), '--work', str(work / 'frame-traces')], work))
    jobs.append(('token-shell', python + ['-S', str(package / 'tools/check_token_shell.py'),
        '--package', str(package), '--work', str(work / 'token-shell'),
        '--yosys', options.yosys, '--z3', options.z3, '--cvc5', options.cvc5], work))
    jobs.append(('kv-epoch', python + ['-S', str(package / 'tools/check_kv_epoch.py'),
        '--package', str(package), '--work', str(work / 'kv-epoch'),
        '--yosys', options.yosys, '--z3', options.z3, '--cvc5', options.cvc5], work))
    jobs.append(('public-commands', python + ['-S', str(package / 'tools/check_public_commands.py'),
        '--package', str(package), '--work', str(work / 'public-commands'),
        '--yosys', options.yosys, '--z3', options.z3, '--cvc5', options.cvc5], work))
    jobs.append(('page-bank', python + ['-S', str(package / 'tools/check_page_bank.py'),
        '--package', str(package), '--work', str(work / 'page-bank'),
        '--yosys', options.yosys, '--z3', options.z3, '--cvc5', options.cvc5], work))
    cases = json.loads((package / 'tests/reference-cases.json').read_text())
    assert set(cases) == {'around128', 'fox128', 'help64', 'moon64', 'prefix128', 'prefix512'}
    jobs += [('reference-' + label, python + [str(package / 'tools/check_reference.py'),
        '--reference-root', str(reference), '--rom', rom, '--cases', str(package / 'tests/reference-cases.json'),
        '--case', label], work) for label in sorted(cases)]
    jobs.append(('host', python + [str(package / 'tools/verify_host.py'), '--package', str(package),
        '--app-python', str(options.app_python.absolute()), '--tokenizer', str(Path(upstream) / 'tokenizer.json'),
        '--work', str(work / 'host-replay')], work))
    jobs.append(('photo-metadata', python + ['-S', str(package / 'tools/check_photo_metadata.py'),
        str(package / 'fpga.jpeg')], work))
    jobs.append(('flash-layout-guards', python + ['-S', '-m', 'unittest', 'discover',
        '-s', str(package / 'tools'), '-p', 'test_flash_layout.py', '-v'], work))
    jobs.append(('flash-reader', python + ['-S', str(package / 'maintenance/flash-reader/replay.py'),
        '--work', str(work / 'flash-reader'), '--verilator', options.verilator], work))
    jobs.append(('composed-shell', python + ['-S', str(package / 'tools/check_composed_shell.py'),
        '--package', str(package), '--work', str(work / 'composed-shell'),
        '--yosys', options.yosys, '--z3', options.z3, '--verilator', options.verilator], work))

    def check(job):
        name, argv, cwd = job
        row, log = run(name, argv, cwd)
        if name == 'page-bank':
            passed = row['exit'] == 0 and 'PAGE_BANK_REPLAY_FINISHED passed=True' in log
            if passed:
                bank = json.loads((work / 'page-bank/FINISHED.json').read_text())
                passed = (bank['passed'] and bank['assertions'] == 42
                    and bank['proof_and_complete_second_solver_passed']
                    and bank['historical_generated_source_and_query_match']
                    and bank['source_audit_passed'] and bank['source_files_unchanged']
                    and bank['real_ram_bits'] == 32768 and bank['sha_replies_unconstrained_bits'] == 258
                    and bank['directed_scenarios'] == 10 and bank['simulation_faulty_controls_detected'] == 5
                    and not bank['observer_drives_production'] and not bank['hardware_access']
                    and not bank['network_access'] and not bank['sha_correctness_proved']
                    and not bank['whole_machine_refinement'])
        elif name == 'photo-metadata':
            photo = json.loads(log) if row['exit'] == 0 else {}
            expected_photo = json.loads((package / 'evidence/photo-metadata.json').read_text())
            passed = row['exit'] == 0 and photo == expected_photo and photo['passed']
        elif name in ('flash-layout-guards', 'model-checker-guards'):
            import re
            count = '6' if name == 'flash-layout-guards' else '10'
            passed = row['exit'] == 0 and re.findall(r'^Ran (\d+) tests in ', log, re.M) == [count] and re.search(r'^OK$', log, re.M) is not None
        elif name == 'model-rtl':
            passed = row['exit'] == 0 and 'MODEL_RTL_REPLAY_FINISHED passed=True' in log
            if passed:
                model = json.loads((work / 'model-rtl/FINISHED.json').read_text())
                passed = (model['passed'] and model['source_files_unchanged']
                    and model['production_rtl_byte_identical'] == 64 and model['production_rtl_changes'] == 0
                    and model['positive_exact_tokens'] == {'zero': 5, 'stalled': 5}
                    and model['weight_corruption_rejections'] == 2
                    and set(model['cases']) == {'zero', 'stalled', 'corrupt-boot', 'corrupt-runtime'}
                    and not model['hardware_access'] and not model['network_access']
                    and not model['whole_machine_refinement'])
        elif name == 'flash-reader':
            passed = row['exit'] == 0 and 'FLASH_READER_REPLAY_FINISHED passed=True' in log
            if passed:
                reader = json.loads((work / 'flash-reader/FINISHED.json').read_text())
                passed = (reader['passed'] and reader['source_unchanged'] and len(reader['jobs']) == 4
                    and not reader['hardware_access'] and not reader['network_access'])
        elif name == 'composed-shell':
            passed = row['exit'] == 0 and 'COMPOSED_SHELL_REPLAY_FINISHED primary_and_structural_checks=True' in log
            if passed:
                composed = json.loads((work / 'composed-shell/FINISHED.json').read_text())
                passed = (composed['passed'] and composed['primary_joint_induction_passed']
                    and composed['assertions'] == 134 and composed['source_structure_audit_passed']
                    and composed['historical_generated_source_and_query_match']
                    and composed['serial_scenarios'] == 13 and composed['simulation_faulty_controls_detected'] == 5
                    and not composed['second_solver_executed'] and not composed['complete_second_solver']
                    and not composed['hardware_access'] and not composed['whole_machine_refinement'])
        elif name == 'lean':
            passed = row['exit'] == 0 and 'error:' not in log
        elif name in ('uart-actual', 'frame-proof'):
            passed = (row['exit'] == 0 and 'SAT proof finished - no model found: SUCCESS!' in log
                      and 'Induction step proven: SUCCESS!' in log)
            netlist = json.loads((cwd / 'elaborated.json').read_text())
            cells = [cell['type'] for module in netlist['modules'].values() for cell in module.get('cells', {}).values()]
            passed = passed and cells.count('$assert') == (46 if name == 'frame-proof' else 15) and '$assume' not in cells
        elif name == 'frame-traces':
            passed = row['exit'] == 0 and 'FRAME_TRACE_FINISHED passed=True' in log
            if passed:
                trace_record = json.loads((work / 'frame-traces/FINISHED.json').read_text())
                passed = (trace_record['passed'] and len(trace_record['jobs']) == 6
                    and not trace_record['hardware_access'] and not trace_record['network_access'])
        elif name.startswith('uart-'):
            passed = row['exit'] != 0 and 'SAT proof finished - model found: FAIL!' in log
        elif name == 'host':
            passed = row['exit'] == 0 and 'HOST_REPLAY_FINISHED passed=True' in log
            if passed:
                host_record = json.loads((work / 'host-replay/FINISHED.json').read_text())
                passed = (host_record['passed'] and host_record['tests_expected'] >= 37
                    and host_record['source_files_unchanged'] and not host_record['hardware_access']
                    and not host_record['network_access'] and not host_record['server_started'])
        elif name == 'token-shell':
            passed = row['exit'] == 0 and 'TOKEN_SHELL_REPLAY_FINISHED passed=True' in log
            if passed:
                shell_record = json.loads((work / 'token-shell/FINISHED.json').read_text())
                passed = (shell_record['passed'] and shell_record['assertions'] == 48
                    and shell_record['assumption_cells'] == 0
                    and shell_record['proof_and_complete_second_solver_passed']
                    and shell_record['tape_mutants_detected'] == 5
                    and shell_record['reset_clear_reuse_witnesses'] == 2
                    and not shell_record['observer_drives_production']
                    and not shell_record['hardware_access'] and not shell_record['network_access']
                    and not shell_record['whole_machine_refinement'])
        elif name == 'kv-epoch':
            passed = row['exit'] == 0 and 'KV_EPOCH_REPLAY_FINISHED passed=True' in log
            if passed:
                kv_record = json.loads((work / 'kv-epoch/FINISHED.json').read_text())
                passed = (kv_record['passed'] and kv_record['assertions'] == 59
                    and kv_record['assumption_cells'] == 0
                    and kv_record['proof_and_complete_second_solver_passed']
                    and kv_record['bounded_faulty_controls_detected'] == 5
                    and kv_record['retained_staging_reuse_witnesses'] == 2
                    and kv_record['source_audit_passed'] and not kv_record['observer_drives_production']
                    and not kv_record['hardware_access'] and not kv_record['network_access']
                    and not kv_record['whole_machine_refinement'])
        elif name == 'public-commands':
            passed = row['exit'] == 0 and 'PUBLIC_COMMAND_REPLAY_FINISHED passed=True' in log
            if passed:
                command_record = json.loads((work / 'public-commands/FINISHED.json').read_text())
                passed = (command_record['passed'] and command_record['assertions'] == 60
                    and command_record['bridge_assertions'] == 46
                    and command_record['connection_assertions'] == 14
                    and command_record['assumption_cells'] == 0
                    and command_record['proof_and_complete_second_solver_passed']
                    and command_record['source_and_operation_bindings_checked']
                    and command_record['source_audit_passed'] and command_record['backend_excluded']
                    and command_record['serial_scenarios'] == 10
                    and command_record['simulation_faulty_controls_detected'] == 5
                    and not command_record['hardware_access'] and not command_record['network_access']
                    and not command_record['whole_machine_refinement'])
        else:
            lines = [line for line in log.splitlines() if line.startswith('PASS_REFERENCE ')]
            passed = row['exit'] == 0 and len(lines) == 1
            if passed:
                observed = json.loads(lines[0].removeprefix('PASS_REFERENCE '))
                label = name.removeprefix('reference-')
                passed = observed['case'] == label and observed['generated_tokens'] == cases[label]['generated_tokens']
        row['passed'] = passed
        return name, row

    with ThreadPoolExecutor(max_workers=8) as pool:
        records.update(dict(pool.map(check, jobs)))
    after = inventory(package)
    assert after == manifest
    result = {'passed': all(row['passed'] for row in records.values()),
        'package_manifest_sha256': sha(package / 'MANIFEST.json'), 'records': records,
        'current_uart_rtl_binding_checked': True, 'package_unchanged': True,
        'expanded_uart_rtl_binding_checked': True,
        'token_shell_source_and_observer_binding_checked': True,
        'kv_epoch_source_and_observer_binding_checked': True,
        'public_command_source_and_operation_binding_checked': True,
        'page_bank_source_and_observer_binding_checked': records['page-bank']['passed'],
        'connected_shell_primary_and_structure_checked': records['composed-shell']['passed'],
        'connected_shell_second_solver_replayed': False,
        'full_model_rtl_and_corruption_cases_checked': records['model-rtl']['passed'],
        'model_log_acceptance_negative_controls_checked': records['model-checker-guards']['passed'],
        'sanitized_photo_and_backup_helper_checked': all(records[n]['passed'] for n in ('photo-metadata', 'flash-layout-guards', 'flash-reader')),
        'hardware_access': False, 'network_access': False, 'published': False,
        'full_release_ready': False,
        'scope': 'Package inventory/model reconstruction, six numerical cases, four actual-model RTL inference/corruption simulations and ten checker tests, abstract Lean, complete component two-solver proofs including sealed weight-bank lifecycle with arbitrary SHA replies, connected-shell primary induction/source/serial checks, host tests, sanitized photo and backup-helper checks. Connected-shell secondary solver not replayed. No vendor build, board test, whole-machine refinement or redistribution approval.'}
    put(work / 'FINISHED.json', result)
    print('PACKAGE_REPLAY_FINISHED passed=' + str(result['passed']), flush=True)
    return 0 if result['passed'] else 1


if __name__ == '__main__': raise SystemExit(main())
