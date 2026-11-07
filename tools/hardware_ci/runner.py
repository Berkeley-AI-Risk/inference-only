#!/usr/bin/env python3
"""Fresh selected-component RTL lint, elaboration and behavioral CI.

The existing selection checkers remain the only build-membership authority.
This adds coverage targets, not an alternative source list or full-chip build.
No vendor models, model weights, network or hardware access are needed.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import re
import shutil
import sys
import time
import traceback

HERE = Path(__file__).resolve().parent
REPOSITORY = HERE.parents[1]
QWEN_TOP = 'qwen_token_command_cdc'
TANG_TOP = 'board1_qspi_async_word_fifo4'


def require(value, message):
    if not value:
        raise ValueError(message)


def identity(path):
    path = Path(path)
    with path.open('rb') as stream:
        return dict(bytes=path.stat().st_size,
                    sha256=hashlib.file_digest(stream, 'sha256').hexdigest())


def save(path, data):
    with Path(path).open('x') as stream:
        json.dump(data, stream, indent=2, sort_keys=True)
        stream.write('\n')


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def authorities(repository):
    tang = load(repository/'demos/simplestories-v2-5m/tools/check_configuration_sources.py',
                'hardware_ci_tang_authority')
    qwen = load(repository/'demos/qwen3-1.7b/tools/check_configuration.py',
                'hardware_ci_qwen_authority')
    return tang, qwen


def selection(repository, name, tang, qwen):
    if name.startswith('tang/'):
        configuration = name.split('/', 1)[1]
        model = repository/'demos/simplestories-v2-5m'
        checked = tang.check_configuration(model, configuration)
        hardware = model/checked['hardware_root']
        lists = tang.source_lists(hardware/'project', configuration)
        ordered = ['project/'+n for n in lists['verilog'] if not n.startswith('official/')]
        headers = []
        excluded = ['project/'+n for n in lists['verilog'] if n.startswith('official/')]
        excluded += ['project/'+n for n in lists['vhdl']]
        top, family, define = TANG_TOP, 'tang', []
        authority_path = model/checked['actual_source_authority']
    else:
        model = repository/'demos'/name
        checked = qwen.verify(model, name)
        hardware = model
        ordered = ['hardware/design/'+n for n in
                   checked['ordered_systemverilog_sources']+checked['ordered_verilog_sources']]
        headers = checked['local_include_files']
        excluded = checked['separately_acquired_shell_includes']
        top, family, define = QWEN_TOP, 'qwen', ['XSDB_SLV_DIS']
        authority_path = model/'hardware/build/scripts/qwen_sources.tcl'
    require(len(ordered) == len(set(ordered)), 'Duplicate selected source')
    top_files = [n for n in ordered if re.search(r'^\s*module\s+'+top+r'\b',
                 (hardware/n).read_text(), re.M)]
    require(len(top_files) == 1, 'Coverage top missing/duplicated in selection: '+name)
    return dict(name=name, family=family, hardware=str(hardware), checked=checked,
                authority=str(authority_path), authority_identity=identity(authority_path),
                ordered_local_verilog=ordered, headers=headers, excluded=excluded,
                top=top, top_source=top_files[0], defines=define,
                source_identities={n: identity(hardware/n) for n in ordered+headers})


def stage_sources(selected, destination):
    destination.mkdir()
    original = Path(selected['hardware'])
    for name, expected in selected['source_identities'].items():
        source, target = original/name, destination/name
        require(not source.is_symlink() and identity(source) == expected,
                'Selected input changed/linked before staging: '+name)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        require(identity(target) == expected, 'Staging changed input: '+name)


def source_arguments(selected, staged):
    # Only selected project directories are visible to compiler library search.
    # Unselected historical alternatives and separately acquired IP are absent.
    directories = list(dict.fromkeys(str((staged/n).parent) for n in
                       selected['ordered_local_verilog']+selected['headers']))
    args = ['+libext+.sv+.v']
    for directory in directories:
        args += ['-I'+directory, '-y', directory]
    args += ['-D'+name for name in selected['defines']]
    if 'project/defines.v' in selected['ordered_local_verilog']:
        args.append(str(staged/'project/defines.v'))
    args.append(str(staged/selected['top_source']))
    return args


def warnings(directory, family, enforce=True):
    text = (directory/'stdout.log').read_text()+(directory/'stderr.log').read_text()
    rows = re.findall(r'^%Warning-([A-Z0-9_]+):([^\n]*)', text, re.M)
    require(len(rows) == len(re.findall(r'^%Warning', text, re.M)),
            'Unclassified compiler warning format')
    counts = {kind: sum(k == kind for k, _ in rows) for kind, _ in rows}
    # Retained source-specific notices, not broad lint suppression. In Qwen,
    # synchronized release registers also feed asynchronous local reset pins;
    # this warning remains OPEN for physical CDC/reset assessment. MEMORY_STYLE
    # is synthesis metadata ignored by this digital simulator.
    allowed = ({} if family == 'tang' else
               {'UNUSEDPARAM': 1, 'SYNCASYNCNET': 5})
    def known_row(kind, row):
        match = re.match(r'\s*(.*?):\d+:\d+: (.*)', row)
        if not match:
            return False
        filename, message = Path(match[1]).name, match[2]
        if family == 'tang':
            return False
        if kind == 'UNUSEDPARAM':
            return (filename == 'qwen_async_stream_fifo.sv'
                    and message == "Parameter is not used: 'MEMORY_STYLE'")
        if kind == 'SYNCASYNCNET':
            signal = re.fullmatch(r"Signal flopped as both synchronous and async: '([^']+)'", message)
            return bool(signal and re.fullmatch(
                r'qwen_token_command_cdc\.(core_reset_release|(?:commands|results)\.(?:source|destination)_reset_release)',
                signal[1]) and filename in {'qwen_token_command_cdc.sv', 'qwen_async_stream_fifo.sv'})
        return False
    if enforce:
        require(all(k in allowed and n <= allowed[k] for k, n in counts.items()),
                'Unexpected lint warning(s): '+json.dumps(counts, sort_keys=True))
        require(all(known_row(k, row) for k, row in rows), 'Unrecognized warning source/signal')
    return dict(counts=counts, rows=rows, policy=allowed,
                enforced=enforce, warning_free=not rows)


def elaboration(tree, metadata, selected, staged):
    root = json.loads(tree.read_text())
    require(root.get('type') == 'NETLIST', 'Expected actual Verilator netlist tree')
    native_modules = root['modulesp']
    require(all(m.get('type') == 'MODULE' for m in native_modules), 'Unexpected elaboration node')
    modules = sorted({m['origName'] for m in native_modules})
    required = {selected['top']}
    if selected['family'] == 'qwen':
        required.add('qwen_async_stream_fifo')
    require(set(modules) == required, 'Unexpected/missing elaborated component: '+str(modules))
    parameters = []
    for module in native_modules:
        values = {}
        for statement in module['stmtsp']:
            if statement.get('varType') != 'GPARAM' or statement['name'] not in {
                    'WIDTH', 'ADDRESS_BITS', 'ZERO_WHEN_INVALID', 'REFRESH_FREE_WRITE_SLOT'}:
                continue
            constants = statement['valuep']
            require(len(constants) == 1 and constants[0]['type'] == 'CONST', 'Nonconstant coverage parameter')
            match = re.fullmatch(r"32'sh([0-9a-f]+)", constants[0]['name'])
            require(match, 'Unexpected parameter encoding')
            values[statement['name']] = int(match[1], 16)
        parameters.append(dict(module=module['name'], original_module=module['origName'], values=values))
    if selected['family'] == 'qwen':
        fifo = [p['values'] for p in parameters if p['original_module'] == 'qwen_async_stream_fifo']
        require(sorted(p['WIDTH'] for p in fifo) == [68, 72] and all(
            p['ADDRESS_BITS'] == 2 and p['ZERO_WHEN_INVALID'] == 1 and p['REFRESH_FREE_WRITE_SLOT'] == 0
            for p in fifo), 'Different actual production FIFO parameterization')
    parsed, builtins = [], []
    for row in json.loads(metadata.read_text())['files'].values():
        name = row['realpath']
        if name.startswith('<'):
            builtins.append(name)
            continue
        path = Path(name).resolve()
        if path.is_relative_to(staged.resolve()):
            rel = str(path.relative_to(staged.resolve()))
            require(rel in selected['source_identities'], 'Unselected compiler input: '+rel)
            parsed.append(rel)
        else:
            require(path.name in {'verilated_std.sv', 'verilated_std_waiver.vlt'},
                    'Unexpected external HDL: '+name)
            builtins.append(dict(path=name, identity=identity(path)))
    require(selected['top_source'] in parsed, 'Compiler did not read coverage top')
    return dict(elaborated_original_module_names=modules, parsed_selected_files=sorted(set(parsed)),
                actual_parameters=parameters, tool_builtins=builtins, vendor_blackboxes_used=False,
                full_selected_top_elaborated=False)


def validate_result(family, result):
    require(result.get('passed') is True and result.get('schedules') == 3,
            'Missing actual behavioral completion')
    require(all(type(v) is int and v >= 0 for k, v in result.items() if k != 'passed'),
            'Behavioral counts must be nonnegative integers')
    if family == 'qwen':
        require(result['commands_sent'] >= 138 and result['results_checked'] == 129
                and result['held_checks'] > 300 and result['fabric_resets'] == 6
                and result['active_clear_cancellations'] == 3
                and result['pending_clear_replacements'] == 3,
                'Incomplete Qwen command/CLEAR coverage')
    else:
        require(result['words_checked'] >= 3300 and result['capacity_words'] == 4
                and result['words_sent'] == result['words_checked']+result['reset_discarded_words']
                and result['coordinated_resets'] == 12
                and result['held_checks'] > 300 and result['full_checks'] > 300
                and result['reset_discarded_words'] == 36,
                'Incomplete Tang FIFO coverage')


def run_case(selected, directory, verilator, command):
    directory.mkdir()
    staged = directory/'selected'
    stage_sources(selected, staged)
    bench = directory/'bench'
    bench.mkdir()
    bench_name = 'qwen_command.cpp' if selected['family'] == 'qwen' else 'tang_fifo.cpp'
    bench_identities = {}
    for name in (bench_name, 'clock.h'):
        shutil.copyfile(HERE/name, bench/name)
        bench_identities[name] = identity(HERE/name)
        require(identity(bench/name) == bench_identities[name], 'Bench changed while staging')
    save(directory/'INPUTS.json', dict(selection=selected, bench=bench_identities))
    flags = [str(verilator), '--Wall', '-Wno-fatal', '--assert',
             '--top-module', selected['top'], '-Mdir', str(directory/'build')]
    sources = source_arguments(selected, staged)
    lint = command(flags+['--lint-only']+sources, directory, directory/'lint', 120)
    lint_warnings = warnings(directory/'lint', selected['family'])
    tree, metadata = directory/'elaborated.tree.json', directory/'elaborated.meta.json'
    command(flags+['--json-only', '--json-only-output', str(tree),
                   '--json-only-meta-output', str(metadata)]+sources,
            directory, directory/'elaborate', 120)
    warnings(directory/'elaborate', selected['family'])
    actual = elaboration(tree, metadata, selected, staged)
    compile_command = flags+['--cc', '--exe', '--build', '-j', '1',
                            '-CFLAGS', '-std=c++17 -O2']+sources+[str(bench/bench_name)]
    build = command(compile_command, directory, directory/'compile', 180)
    warnings(directory/'compile', selected['family'])
    binary = directory/'build'/('V'+selected['top'])
    binary_identity = identity(binary)
    execute = command([str(binary)], directory, directory/'execute', 30)
    result = json.loads((directory/'execute/stdout.log').read_text())
    validate_result(selected['family'], result)
    require(identity(binary) == binary_identity, 'Behavioral binary changed')
    for name, expected in bench_identities.items():
        require(identity(HERE/name) == expected and identity(bench/name) == expected,
                'Behavioral bench changed during check')
    for name, expected in selected['source_identities'].items():
        require(identity(staged/name) == expected and identity(Path(selected['hardware'])/name) == expected,
                'Selected source changed during check: '+name)
    record = dict(passed=True, name=selected['name'], lint=lint,
                  lint_warnings=lint_warnings, elaboration=actual, compile=build,
                  bench=bench_identities, binary=binary_identity, execute=execute, checks=result)
    save(directory/'FINISHED.json', record)
    return record


MUTANTS = {
    'qwen': ('wire discard_response=pending_clear || clear_take;',
             "wire discard_response=1'b0;", 'FAIL qwen_command_cdc cancelled_response'),
    'tang': ('assign read_data_o = read_data_q;',
             "assign read_data_o = read_data_q ^ 256'd1;", 'FAIL tang_fifo data_order'),
}


def run_mutant(selected, baseline, directory, verilator, command):
    require(json.loads((baseline/'FINISHED.json').read_text())['passed'],
            'Mutation requires passing exact production baseline first')
    directory.mkdir()
    staged = directory/'selected'
    shutil.copytree(baseline/'selected', staged)
    bench = directory/'bench'
    shutil.copytree(baseline/'bench', bench)
    old, new, expected = MUTANTS[selected['family']]
    path = staged/selected['top_source']
    before = identity(path)
    require(identity(Path(selected['hardware'])/selected['top_source']) == before,
            'Production source changed before mutation control')
    text = path.read_text()
    require(text.count(old) == 1, 'Mutation source anchor changed')
    path.write_text(text.replace(old, new))
    save(directory/'MUTATION.json', dict(source=selected['top_source'], before=before,
         after=identity(path), old=old, new=new, expected_failure=expected,
         original_production_file_unchanged=identity(Path(selected['hardware'])/selected['top_source']) == before))
    name = 'qwen_command.cpp' if selected['family'] == 'qwen' else 'tang_fifo.cpp'
    compile_command = [str(verilator), '--Wall', '-Wno-fatal', '--assert', '--cc', '--exe',
                       '--build', '-j', '1', '--top-module', selected['top'],
                       '-Mdir', str(directory/'build'), '-CFLAGS', '-std=c++17 -O2']
    compile_command += source_arguments(selected, staged)+[str(bench/name)]
    build = command(compile_command, directory, directory/'compile', 180)
    # The deliberate defect can make a formerly used control unused. Those
    # mutant warnings are recorded, never treated as a production lint pass.
    observed_warnings = warnings(directory/'compile', selected['family'], enforce=False)
    binary = directory/'build'/('V'+selected['top'])
    failed = False
    try:
        command([str(binary)], directory, directory/'execute', 30)
    except ValueError:
        failed = True
    require(failed, 'Broken RTL passed the actual behavioral check')
    receipt = json.loads((directory/'execute/EXIT.json').read_text())
    require(receipt['actual_child_exit'] == 1 and not receipt['interrupted_or_timed_out'],
            'Mutation must fail behaviorally, not timeout/compile/signal')
    stderr = (directory/'execute/stderr.log').read_text()
    require(stderr.strip() == expected, 'Wrong mutation refusal: '+stderr)
    require(identity(Path(selected['hardware'])/selected['top_source']) == before,
            'Production source changed during mutation control')
    record = dict(passed=True, compiled=True, expected_behavioral_refusal=expected,
                  compile=build, mutant_warnings=observed_warnings, actual_execution=receipt,
                  production_behavioral_baseline=str(baseline/'FINISHED.json'))
    save(directory/'FINISHED.json', record)
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', type=Path, default=REPOSITORY)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--configuration', action='append')
    parser.add_argument('--verilator', type=Path)
    parser.add_argument('--plan', action='store_true')
    args = parser.parse_args()
    repository = args.repository.resolve(strict=True)
    tang, qwen = authorities(repository)
    names = ['tang/'+name for name in tang.CONFIGURATIONS]+list(qwen.MODELS)
    selected_names = args.configuration or names
    require(len(set(selected_names)) == len(selected_names) and set(selected_names) <= set(names),
            'Unknown/duplicate selected configuration')
    selections = [selection(repository, name, tang, qwen) for name in selected_names]
    if args.plan:
        print(json.dumps(dict(selections=selections, HDL_compiled=False), indent=2))
        return
    require(args.output is not None, 'Choose a fresh --output outside the repository')
    output = args.output.resolve()
    require(not output.exists() and not output.is_relative_to(repository)
            and not any(c.isspace() for c in str(output)), 'Unsafe/existing build output')
    executable = args.verilator or shutil.which('verilator')
    require(executable, 'Verilator is required; no automatic download or skip')
    verilator = Path(executable).resolve(strict=True)
    common = load(repository/'demos/qwen3-8b/tests/rtl/run.py', 'hardware_ci_native_command')
    command = common.command  # Reuse the existing bounded, owned-child runner.
    output.mkdir(parents=True)
    started = time.monotonic()
    record = dict(started_utc=datetime.now(timezone.utc).isoformat(), runner=identity(Path(__file__)),
                  toolchain=json.loads((HERE/'toolchain.json').read_text()),
                  declared_container_image=os.environ.get('HARDWARE_CI_CONTAINER'),
                  platform=dict(system=platform.system(), machine=platform.machine(),
                                python=platform.python_version()),
                  verilator=identity(verilator), command_runner=identity(Path(common.__file__)),
                  repository=str(repository), selected_configurations=selected_names,
                  compiler_jobs=1, sequential=True, automatic_retry=False,
                  full_chip_compile=False, vendor_simulation=False, physical_CDC_or_timing=False,
                  hardware_access=False, network_access=False, cases=[], mutation_controls=[])
    shutil.copyfile(Path(__file__), output/'runner-source.py')
    shutil.copyfile(HERE/'toolchain.json', output/'toolchain.json')
    require(identity(output/'runner-source.py') == record['runner'], 'Runner snapshot changed')
    save(output/'STARTED.json', record)
    try:
        command([str(verilator), '--version'], output, output/'tool-version', 10)
        version = (output/'tool-version/stdout.log').read_text().strip()
        require(re.match(r'^Verilator 5\.050\b', version), 'Use pinned Verilator5.050, got '+version)
        record['actual_verilator_version'] = version
        compiler = shutil.which('c++')
        require(compiler, 'C++ compiler required')
        command([compiler, '--version'], output, output/'cxx-version', 10)
        record['actual_cxx_version'] = (output/'cxx-version/stdout.log').read_text()
        mutated_families = set()
        for selected in selections:
            folder = output/selected['name'].replace('/', '-')
            record['cases'].append(run_case(selected, folder, verilator, command))
            if selected['family'] not in mutated_families:
                record['mutation_controls'].append(run_mutant(selected, folder,
                    output/('mutant-'+selected['family']), verilator, command))
                mutated_families.add(selected['family'])
        require(len(record['cases']) == len(selected_names), 'A selected case was skipped')
        record.update(passed=True, elapsed_seconds=time.monotonic()-started)
        save(output/'FINISHED.json', record)
    except BaseException as error:
        record.update(passed=False, elapsed_seconds=time.monotonic()-started,
                      error=dict(type=type(error).__name__, message=str(error), traceback=traceback.format_exc()))
        save(output/'FAILED.json', record)
        raise
    print(json.dumps(dict(passed=True, component_cases=len(record['cases']),
         behavioral_mutants=len(record['mutation_controls']), elapsed_seconds=record['elapsed_seconds'],
         full_chip_compile=False, vendor_simulation=False, hardware_access=False), indent=2))


if __name__ == '__main__':
    main()
