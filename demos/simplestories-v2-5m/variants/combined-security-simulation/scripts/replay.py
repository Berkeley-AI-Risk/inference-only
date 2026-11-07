"""Serial compiler/native replay with retained commands and checked outputs."""
from pathlib import Path
import argparse
import hashlib
import json
import platform
import re
import shutil
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from pin_sources import main as check_pins, sha

# These are the actual testbench cases. Verdicts also require exact public
# tokens, admitted model identities and authorization contexts from the logs.
SPECS = {
    0: ('PASS_COMBINED_A_RENEWAL', ['A'], ['A0', 'A1'], ['A-e1', 'A-e1'], None),
    1: ('PASS_COMBINED_A_EXPIRY', ['A'], [], ['A-e1'], None),
    2: ('PASS_COMBINED_RESET_OLD_GRANT', ['A', 'A'], [], ['A-e1'], 'A-e2'),
    3: ('PASS_COMBINED_RESET_FRESH_GRANT', ['A'], ['A0'], ['A-e2'], None),
    4: ('PASS_COMBINED_MODEL_OLD_GRANT', ['B'], [], [], 'B-e1'),
    5: ('PASS_COMBINED_MODEL_REPLACEMENT', ['A', 'B'], ['A0', 'B0', 'B1'], ['A-e1', 'B-e2'], None),
    6: ('PASS_COMBINED_CROSS_MODEL_KV', ['A', 'B'], ['A0', 'B0'], ['A-e1', 'B-e2'], None),
    7: ('PASS_COMBINED_AFTER_EXPIRY', ['A', 'B'], ['B0', 'B1'], ['A-e1', 'B-e2'], None),
    8: ('PASS_COMBINED_CLEAR_ACTIVE',['A'],['A0'],['A-e1'],None),
    9: ('PASS_COMBINED_CLEAR_HELD_TOKEN',['A'],['A0'],['A-e1'],None),
    10: ('PASS_COMBINED_CLEAR_WRITE_DRAIN',['A'],['A0'],['A-e1'],None),
}
ORDER = (0, 1, 3, 5, 6, 2, 4, 7, 8, 9, 10)


def case_top(number):
    return 'tb_combined_clear' if number>=8 else ('tb_combined' if number in (0,1) else 'tb_combined_extended')


def write(path, value):
    with path.open('x') as stream:
        stream.write(json.dumps(value, indent=2, sort_keys=True) + '\n')


def invoke(command, cwd, directory):
    directory.mkdir(exist_ok=False)
    write(directory / 'COMMAND.json', {'argv': command, 'cwd': str(cwd)})
    start = time.monotonic()
    with (directory / 'stdout.log').open('xb') as stdout, (directory / 'stderr.log').open('xb') as stderr:
        result = subprocess.run(command, cwd=cwd, stdout=stdout, stderr=stderr)
    receipt = {'actual_child_exit': result.returncode, 'wall_seconds': time.monotonic() - start,
               'stdout_sha256': sha(directory / 'stdout.log'), 'stderr_sha256': sha(directory / 'stderr.log'),
               'no_automatic_retry': True}
    write(directory / 'EXIT.json', receipt)
    if result.returncode:
        raise RuntimeError('Child failed; retained evidence: ' + str(directory))
    return receipt


def helper(name, label, *arguments):
    return invoke([sys.executable, '-I', '-B', str(HERE / name), *arguments], HERE, HERE / 'steps' / label)


def verify_source(seal):
    scratch = Path(seal['scratch'])
    for name, row in seal['files'].items():
        if sha(scratch / name) != row['sha256']:
            raise ValueError('Compiler source changed: ' + name)


def verify_fixtures():
    path = HERE / 'fixtures-v1' / 'FIXTURES.json'
    fixtures = json.loads(path.read_text())
    for name, row in fixtures['files'].items():
        if sha(path.parent / name) != row['sha256']:
            raise ValueError('Fixture changed: ' + name)
    return fixtures


def prepare():
    (HERE / 'steps').mkdir(exist_ok=False)
    if sys.version_info < (3, 12):
        raise RuntimeError('Python 3.12 or later is required')
    import numpy
    from reference_check import check_openssl
    crypto = check_openssl()
    versions = {'python': sys.version, 'numpy': numpy.__version__, 'platform': platform.platform(), 'OpenSSL': crypto}
    for tool in ('verilator', 'openssl', 'c++', 'make'):
        binary = shutil.which(tool)
        if not binary:
            raise RuntimeError('Required tool was not found: ' + tool)
        versions[tool] = binary
    versions['verilator_version'] = subprocess.check_output([versions['verilator'], '--version'], text=True).strip()
    versions['openssl_version'] = subprocess.check_output([versions['openssl'], 'version'], text=True).strip()
    write(HERE / 'TOOLS.json', versions)
    check_pins()
    helper('prepare.py', 'prepare-source')
    helper('make_fixtures.py', 'make-fixtures')
    helper('prepare_model_domains.py', 'bind-model-domains')
    verify_fixtures()
    check_pins()
    print('PASS_COMBINED_PREPARATION', flush=True)


def build(top,jobs):
    label = 'build-' + top
    helper('stage_build.py', 'stage-' + top, '--label', label, '--top', top, '--binary', '--prepared', 'prepared-model-domains-v2','--jobs',str(jobs))
    out = HERE / label
    plan = json.loads((out / 'PLAN.json').read_text())
    seal = json.loads((out / 'SOURCE-SEAL.json').read_text())
    verify_source(seal)
    result = invoke(plan['command'], Path(plan['cwd']), out / 'native')
    verify_source(seal)
    from warning_policy import check as check_warnings
    warnings = check_warnings((out / 'native/stderr.log').read_text(), Path(plan['cwd']))
    binary = Path(plan['binary'])
    write(out / 'CHECKED-EXIT.json', {'passed': True, **result, 'binary_sha256': sha(binary),
                                    'source_seal_sha256': sha(out / 'SOURCE-SEAL.json'),
                                    'compiler_warnings': warnings})
    print('PASS_COMBINED_BUILD', top, flush=True)


def lookup():
    from lookup_binding import truth
    output = HERE / 'lookup'
    output.mkdir(exist_ok=False)
    for name, source in [('combined_aes_lookup_sim.sv', HERE / 'rtl/combined_aes_lookup_sim.sv'),
                         ('tb_lookup_public.sv', HERE / 'tests/tb_lookup_public.sv')]:
        shutil.copyfile(source, output / name)
    (output / 'expected.memh').write_text(''.join(f'{truth(i):02x}\n' for i in range(256)))
    pins = {p.name: sha(p) for p in sorted(output.iterdir())}
    command = [shutil.which('verilator'), '--binary', '--timing', '--build-jobs', '1',
               '--top-module', 'tb_lookup_public', '--Mdir', 'obj',
               'combined_aes_lookup_sim.sv', 'tb_lookup_public.sv']
    invoke(command, output, output / 'compile')
    invoke([str(output / 'obj/Vtb_lookup_public')], output, output / 'native')
    marker = 'PASS_LOOKUP_PUBLIC pairs=65536 pre_edge_stability_checks=65535 two_ports=1 latency_edges=1 expected_GF_truth=1'
    log = (output / 'native/stdout.log').read_text()
    if log.splitlines().count(marker) != 1 or any(sha(output / n) != h for n, h in pins.items()):
        raise RuntimeError('The portable two-port lookup check failed')
    write(output / 'RESULT.json', {'passed': True, 'marker': marker, 'input_pins': pins,
                                 'binary_sha256': sha(output / 'obj/Vtb_lookup_public')})
    print('PASS_CHECKED_LOOKUP_PUBLIC', flush=True)


def case(number):
    check_pins()
    fixtures = verify_fixtures()
    top = case_top(number)
    parent = HERE / ('build-' + top)
    accepted = json.loads((parent / 'CHECKED-EXIT.json').read_text())
    plan = json.loads((parent / 'PLAN.json').read_text())
    seal = json.loads((parent / 'SOURCE-SEAL.json').read_text())
    if not accepted['passed'] or sha(Path(plan['binary'])) != accepted['binary_sha256']:
        raise ValueError('Build identity differs')
    verify_source(seal)
    output = HERE / ('case-' + str(number))
    output.mkdir(exist_ok=False)
    expected_marker, models, tokens, contexts, refusal = SPECS[number]
    command = [plan['binary'], '+FIXTURES=' + str(HERE / 'fixtures-v1'), '+SCENARIO=' + str(number)]
    parent_pins = {}
    capture = None
    if number in (3, 5):
        model = 'A' if number == 3 else 'B'
        capture = output / ('actual-' + model + '2-role.memh')
        command += [('+' + ('ROLE_OUTPUT' if number == 3 else 'B2_ROLE_OUTPUT') + '=' + str(capture))]
    if number == 6:
        a2 = HERE / 'case-3'
        result = json.loads((a2 / 'CHECKED-EXIT.json').read_text())
        auth = json.loads((a2 / 'ROLE-AUTHENTICATION.json').read_text())
        role = Path(auth['native_capture'])
        if not result['passed'] or not auth['passed'] or auth['model'] != 'A' or auth['epoch'] != 2 or sha(role) != auth['native_capture_sha256']:
            raise ValueError('The real A2 native capture has not passed independent authentication')
        parent_pins = {str(p): sha(p) for p in (role, a2 / 'CHECKED-EXIT.json', a2 / 'ROLE-AUTHENTICATION.json')}
        command += ['+A2_ROLE=' + str(role)]
    fixture_pin = sha(HERE / 'fixtures-v1/FIXTURES.json')
    write(output / 'PLAN.json', {'scenario': number, 'required_marker': expected_marker,
                              'build_sha256': sha(parent / 'CHECKED-EXIT.json'), 'parent_inputs': parent_pins,
                              'fixture_manifest_sha256': fixture_pin})
    native = invoke(command, Path(plan['cwd']), output / 'native')
    stdout = (output / 'native/stdout.log').read_text()
    stderr = (output / 'native/stderr.log').read_text()
    markers = [line for line in stdout.splitlines() if line.startswith('PASS_COMBINED_')]
    observed_tokens = [int(x) for x in re.findall(r'^NUMERICAL_TOKEN token=(\d+) ', stdout, re.M)]
    expected_tokens = [fixtures['models'][x[0]]['tokens'][int(x[1])] for x in tokens]
    observed_models = re.findall(r'^BOOT_MODEL label=([AB]) model=([a-f0-9]+) ', stdout, re.M)
    if number in (0, 1, 8, 9, 10):
        observed_models = [('A', fixtures['models']['A']['model_commitment'])] if len(re.findall(r'^BOOT_A ', stdout, re.M)) == 1 else []
    observed_contexts = re.findall(r'^LEASE accepted=\d+ cycles=\d+ context=([a-f0-9]+)$', stdout, re.M)
    expected_contexts = [fixtures['contexts'][x] for x in contexts]
    refused = re.findall(r'^OLD_GRANT_REFUSED .* context=([a-f0-9]+)$', stdout, re.M)
    expected_refused = [fixtures['contexts'][refusal]] if refusal else []
    passed = (len(markers) == 1 and markers[0].startswith(expected_marker + ' ')
              and observed_tokens == expected_tokens and [x[0] for x in observed_models] == models
              and all(root == fixtures['models'][model]['model_commitment'] for model, root in observed_models)
              and observed_contexts == expected_contexts and refused == expected_refused
              and not any(x in stdout + stderr for x in ('%Error', '%Fatal', 'Assertion failed')))
    if capture:
        from reference_check import check_role
        auth = check_role(capture, 'A' if number == 3 else 'B', 2, HERE / 'fixtures-v1/FIXTURES.json')
        write(output / 'ROLE-AUTHENTICATION.json', auth)
        passed = passed and auth['passed']
    verify_source(seal)
    verify_fixtures()
    check_pins()
    passed = (passed and fixture_pin == sha(HERE / 'fixtures-v1/FIXTURES.json')
              and all(sha(Path(p)) == h for p, h in parent_pins.items())
              and sha(Path(plan['binary'])) == accepted['binary_sha256'])
    write(output / 'CHECKED-EXIT.json', {'passed': passed, **native, 'scenario': number, 'markers': markers,
                                       'observed_tokens': observed_tokens, 'expected_tokens': expected_tokens,
                                       'boot_models': observed_models, 'contexts': observed_contexts,
                                       'refused_contexts': refused, 'binary_sha256': accepted['binary_sha256']})
    if not passed:
        raise RuntimeError('Native case did not meet its independent acceptance checks: ' + str(number))
    print('PASS_CHECKED_COMBINED_CASE', number, flush=True)


def validate_summary(root=None):
    root = HERE if root is None else root
    check_pins()
    fixtures = verify_fixtures()
    results = {}
    for number in ORDER:
        directory = root / ('case-' + str(number))
        path = directory / 'CHECKED-EXIT.json'
        result = json.loads(path.read_text())
        plan = json.loads((directory / 'PLAN.json').read_text())
        marker, models, tokens, contexts, refusal = SPECS[number]
        if (result.get('passed') is not True or result.get('actual_child_exit') != 0
                or result.get('scenario') != number or plan.get('scenario') != number
                or plan.get('required_marker') != marker):
            raise ValueError('Case identity or acceptance differs: ' + str(number))
        stdout_path, stderr_path = directory / 'native/stdout.log', directory / 'native/stderr.log'
        terminal = json.loads((directory / 'native/EXIT.json').read_text())
        for field, log in [('stdout_sha256', stdout_path), ('stderr_sha256', stderr_path)]:
            if result.get(field) != sha(log) or terminal.get(field) != sha(log):
                raise ValueError('Native log digest differs: case ' + str(number) + ' ' + field)
        if terminal.get('actual_child_exit') != 0:
            raise ValueError('Native child did not exit zero: ' + str(number))
        stdout, stderr = stdout_path.read_text(), stderr_path.read_text()
        markers = [line for line in stdout.splitlines() if line.startswith('PASS_COMBINED_')]
        observed_tokens = [int(x) for x in re.findall(r'^NUMERICAL_TOKEN token=(\d+) ', stdout, re.M)]
        expected_tokens = [fixtures['models'][x[0]]['tokens'][int(x[1])] for x in tokens]
        lease_contexts = re.findall(r'^LEASE accepted=\d+ cycles=\d+ context=([a-f0-9]+)$', stdout, re.M)
        refused = re.findall(r'^OLD_GRANT_REFUSED .* context=([a-f0-9]+)$', stdout, re.M)
        if (len(markers) != 1 or not markers[0].startswith(marker + ' ') or result.get('markers') != markers
                or observed_tokens != expected_tokens or result.get('observed_tokens') != observed_tokens
                or result.get('expected_tokens') != expected_tokens
                or lease_contexts != [fixtures['contexts'][x] for x in contexts]
                or result.get('contexts') != lease_contexts
                or refused != ([fixtures['contexts'][refusal]] if refusal else [])
                or result.get('refused_contexts') != refused
                or any(x in stdout + stderr for x in ('%Error', '%Fatal', 'Assertion failed'))):
            raise ValueError('Case marker or observed behavior differs: ' + str(number))
        top = case_top(number)
        build_directory = root / ('build-' + top)
        build_result = json.loads((build_directory / 'CHECKED-EXIT.json').read_text())
        build_plan = json.loads((build_directory / 'PLAN.json').read_text())
        if (not build_result['passed'] or plan['build_sha256'] != sha(build_directory / 'CHECKED-EXIT.json')
                or result['binary_sha256'] != build_result['binary_sha256']
                or sha(Path(build_plan['binary'])) != build_result['binary_sha256']
                or plan['fixture_manifest_sha256'] != sha(HERE / 'fixtures-v1/FIXTURES.json')):
            raise ValueError('Case build or fixture binding differs: ' + str(number))
        verify_source(json.loads((build_directory / 'SOURCE-SEAL.json').read_text()))
        command = json.loads((directory / 'native/COMMAND.json').read_text())['argv']
        expected_command = [build_plan['binary'], '+FIXTURES=' + str(HERE / 'fixtures-v1'), '+SCENARIO=' + str(number)]
        if number in (3, 5):
            from reference_check import check_role
            model = 'A' if number == 3 else 'B'
            auth = json.loads((directory / 'ROLE-AUTHENTICATION.json').read_text())
            capture = Path(auth['native_capture'])
            checked = check_role(capture, model, 2, HERE / 'fixtures-v1/FIXTURES.json')
            if (not auth['passed'] or auth['model'] != model or auth['epoch'] != 2
                    or auth['native_capture_sha256'] != checked['native_capture_sha256']
                    or auth['plaintext_sha256'] != checked['plaintext_sha256']):
                raise ValueError('Native role authentication binding differs: ' + str(number))
            expected_command += [('+' + ('ROLE_OUTPUT' if number == 3 else 'B2_ROLE_OUTPUT') + '=' + str(capture))]
        if number == 6:
            auth = json.loads((root / 'case-3/ROLE-AUTHENTICATION.json').read_text())
            role = Path(auth['native_capture'])
            expected_parents = {str(p): sha(p) for p in (role, HERE / 'case-3/CHECKED-EXIT.json', HERE / 'case-3/ROLE-AUTHENTICATION.json')}
            if plan['parent_inputs'] != expected_parents:
                raise ValueError('Cross-model case parent capture differs')
            expected_command += ['+A2_ROLE=' + str(role)]
        if command != expected_command:
            raise ValueError('Native command differs: ' + str(number))
        results[str(number)] = {'result_sha256': sha(path), 'marker': result['markers'][0]}
    lookup_result = root / 'lookup/RESULT.json'
    lookup = json.loads(lookup_result.read_text())
    if not lookup['passed']:
        raise ValueError('Portable lookup check has not passed')
    for name, expected in lookup['input_pins'].items():
        if sha(root / 'lookup' / name) != expected:
            raise ValueError('Portable lookup input differs')
    lookup_log = root / 'lookup/native/stdout.log'
    lookup_terminal = json.loads((root / 'lookup/native/EXIT.json').read_text())
    expected_lookup_marker = 'PASS_LOOKUP_PUBLIC pairs=65536 pre_edge_stability_checks=65535 two_ports=1 latency_edges=1 expected_GF_truth=1'
    if (lookup.get('marker') != expected_lookup_marker
            or lookup_terminal['actual_child_exit'] != 0 or sha(lookup_log) != lookup_terminal['stdout_sha256']
            or sha(root / 'lookup/native/stderr.log') != lookup_terminal['stderr_sha256']
            or lookup_log.read_text().splitlines().count(lookup['marker']) != 1
            or sha(root / 'lookup/obj/Vtb_lookup_public') != lookup['binary_sha256']):
        raise ValueError('Portable lookup retained result differs')
    return results


def audit_summary_controls():
    # Use genuine complete replay receipts as the positive control. Counterexamples
    # are thin private copies; existing outputs and native evidence stay untouched.
    output = HERE.parent / 'summary-controls'
    output.mkdir(exist_ok=False)
    validate_summary()
    controls = []
    for name in ('swapped-case-receipts', 'changed-native-log-byte'):
        fixture = output / name
        fixture.mkdir()
        for path in HERE.iterdir():
            if path.name in ('case-0', 'case-1'):
                shutil.copytree(path, fixture / path.name)
            else:
                (fixture / path.name).symlink_to(path, target_is_directory=path.is_dir())
        if name == 'swapped-case-receipts':
            a, b = fixture / 'case-0/CHECKED-EXIT.json', fixture / 'case-1/CHECKED-EXIT.json'
            first, second = a.read_bytes(), b.read_bytes()
            a.write_bytes(second)
            b.write_bytes(first)
        else:
            log = fixture / 'case-0/native/stdout.log'
            data = log.read_bytes()
            log.write_bytes(bytes([data[0] ^ 1]) + data[1:])
        try:
            validate_summary(fixture)
        except ValueError as error:
            controls.append({'control': name, 'refused': True, 'reason': str(error)})
        else:
            raise ValueError('Summary defect control was accepted: ' + name)
        for path in fixture.iterdir():
            if path.is_symlink():
                path.unlink()
    validate_summary()
    write(output / 'RESULT.json', {'passed': True, 'genuine_complete_replay_positive_control': True,
                                  'original_evidence_unchanged': True, 'negative_controls': controls})


def summarize():
    results = validate_summary()
    audit_summary_controls()
    lookup_result = HERE / 'lookup/RESULT.json'
    write(HERE.parent / 'RESULT.json', {'passed': True, 'cases': results, 'lookup_result_sha256': sha(lookup_result),
                                      'summary_controls_sha256': sha(HERE.parent / 'summary-controls/RESULT.json'),
                                      'source_inputs_sha256': sha(HERE / 'SOURCE-INPUTS.json'),
                                      'tools_sha256': sha(HERE / 'TOOLS.json'),
                                      'scope': 'Simulation with explicitly modeled private vault, monotonic epoch/time and deterministic challenges; no FPGA timing, board or physical-security qualification'})
    print('PASS_COMBINED_PUBLIC_REPLAY', flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--phase', choices=('all', 'prepare', 'build', 'case', 'summarize'), required=True)
    parser.add_argument('--case', type=int, choices=range(11))
    parser.add_argument('--build-jobs',type=int,default=1)
    args = parser.parse_args()
    if args.phase in ('all', 'prepare'):
        prepare()
    if args.phase in ('all', 'build'):
        lookup()
        for top in ('tb_combined', 'tb_combined_extended','tb_combined_clear'):
            build(top,args.build_jobs)
    if args.phase in ('all', 'case'):
        if args.phase == 'case' and args.case is None:
            raise ValueError('--phase case requires --case')
        for number in ORDER if args.phase == 'all' else (args.case,):
            case(number)
    if args.phase in ('all', 'summarize'):
        summarize()


if __name__ == '__main__':
    main()
