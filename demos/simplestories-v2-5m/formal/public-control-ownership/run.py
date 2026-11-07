"""Verify the recorded packet, or recompile and replay its complete scoped proof."""
from pathlib import Path, PurePosixPath
import argparse, gzip, hashlib, json, os, re, shutil, signal, subprocess, tarfile, time
HERE = Path(__file__).resolve().parent
if not __debug__:
    raise SystemExit('Verification requires Python assertions; do not use -O')
sha = lambda raw: hashlib.sha256(raw).hexdigest()


def read(path):
    return json.loads(path.read_text())


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
ORDER = [
    'native-reset-base',
    'native-base-through-release',
    'native-joint-three-step',
    'phase-reset-base',
    'phase-one-step',
    'history-reset-base',
    'history-base-through-release',
    'history-joint-three-step',
    'actual-successful-commit',
    'actual-STEP-snapshot',
    'actual-token-message-bytes',
    'actual-publication-once',
    'reset-release-context',
    'original-capture-context',
    'original-capture-consumer',
    'CLEAR-CRC-result-race-context',
    'CLEAR-CRC-result-race-priority',
    'stale-capture-consumer',
]


def check_model(raw, netlist, top):
    cells = list(netlist['modules'][top]['cells'].values())
    assert sum((c['type'] == '$assert' for c in cells)) == 142
    assert not any((c['type'] in ['$assume', '$anyseq', '$anyconst'] for c in cells))
    memories = [(int(c['parameters']['SIZE'], 2), int(c['parameters']['WIDTH'], 2)) for c in cells if c['type'] == '$mem_v2']
    assert (2049, 12) in memories, 'Native full token tape missing'
    return {
        'SMT_sha256': sha(raw),
        'assertions': 142,
        'assumption_cells': 0,
        'memories': memories,
    }


def body(project, row, native):
    raw = b'(set-option :produce-models true)\n' + native + b'\n' + (project / 'STATEMENT.smt2').read_bytes() + b'\n'
    for name in row.get('extra_inputs', []):
        raw += (project / name).read_bytes() + b'\n'
    return raw + (project / row['tail']).read_bytes()


def load_packet(output, repository):
    source = read(HERE / 'SOURCE.json')
    archive = HERE / 'project.tar.gz'
    assert sha(archive.read_bytes()) == source['archive_sha256']
    project = output / 'project'
    project.mkdir()
    with tarfile.open(archive, 'r:gz') as t:
        members = t.getmembers()
        assert len(members) == source['members']
        names = []
        for member in members:
            path = PurePosixPath(member.name)
            assert member.isfile() and (not path.is_absolute()) and ('..' not in path.parts)
            assert '\\' not in member.name
            names.append(member.name)
        assert len(names) == len(set(names))
        t.extractall(project)
    inventory = read(project / 'INVENTORY.json')
    assert sha((project / 'INVENTORY.json').read_bytes()) == source['inventory_sha256']
    actual = {str(f.relative_to(project)) for f in project.rglob('*') if f.is_file()}
    assert actual == set(inventory) | {'INVENTORY.json'}
    for name, row in inventory.items():
        raw = (project / name).read_bytes()
        assert sha(raw) == row['sha256'] and len(raw) == row['bytes'], name
    for row in source['production_sources']:
        raw = (project / row['file']).read_bytes()
        assert sha(raw) == row['sha256']
        assert (repository / row['repository_path']).read_bytes() == raw, row['repository_path']
    assert (HERE / 'STATEMENT.smt2').read_bytes() == (project / 'STATEMENT.smt2').read_bytes()
    assert (HERE / 'PHASE-SUPPORT.smt2').read_bytes() == (project / 'PHASE-SUPPORT.smt2').read_bytes()
    plan = read(project / 'QUERY-PLAN.json')
    assert read(HERE / 'CONTRACT-GRAPH.json') == plan['dependency_graph']
    assert set(plan['rules']) == set(ORDER)
    for name, row in plan['rules'].items():
        assert sha((project / row['tail']).read_bytes()) == row['tail_sha256']
    for name in ['phase-reset-base', 'phase-one-step']:
        assert not any(('PC-I ' in premise for premise in plan['rules'][name]['assumptions']))
    for state in ['a', 'b', 'c', 'd']:
        assert '(PHASE-I ' + state + ' p' + state + ' A)' in plan['rules']['history-joint-three-step']['assumptions']
    original = (project / 'sources/front/bridge.sv').read_text()
    mutant = (project / 'stale-bridge.sv').read_text()
    before = "prepare_response(8'h81, out_token_i);"
    after = "prepare_response(8'h81, response_token_q);"
    assert original.count(before) == 1 and original.replace(before, after, 1) == mutant
    return (project, plan)


def recorded(project, plan):
    models = {}
    bindings = {}
    for role in ['original', 'stale-capture']:
        directory = project / 'recorded/models' / role
        raw = gzip.decompress((directory / 'native.smt2.gz').read_bytes())
        netlist = json.loads(gzip.decompress((directory / 'native.json.gz').read_bytes()))
        bindings[role] = check_model(raw, netlist, plan['top'])
        models[role] = raw
    outcomes = {}
    for name in ORDER:
        row = plan['rules'][name]
        receipt = read(project / 'recorded' / name / 'RESULT.json')
        raw = body(project, row, models[row['model_role']])
        log = (project / 'recorded' / name / 'tool.log').read_bytes()
        assert sha(raw) == receipt['query_sha256'] and sha(log) == receipt['raw_log_sha256']
        assert (
            receipt['expected_result_matched']
            and receipt['exit_code'] == 0
            and receipt['stop_reason'] is None
        )
        assert row['expected'] == receipt['expected'] == receipt['answer'] == log.strip().decode()
        outcomes[name] = {
            'expected': row['expected'],
            'query_sha256': sha(raw),
            'passed': True,
        }
    witness = read(project / 'witness/PLAN.json')
    for tag, markers in [('r5', [witness['expected_marker'], witness['actual_reset_marker']]), ('r2', [witness['guard_marker']])]:
        for stage in ['compile', 'simulation']:
            directory = project / 'recorded/witness' / tag / stage
            r = read(directory / 'RESULT.json')
            log = (directory / 'tool.log').read_bytes()
            assert (
                r['expected_result_matched']
                and r['exit_code'] == 0
                and r['stop_reason'] is None
                and sha(log) == r['raw_log_sha256']
            )
            if stage == 'simulation':
                assert (
                    all((m in log.decode() for m in markers))
                    and 'FATAL:' not in log.decode()
                    and 'ERROR:' not in log.decode()
                )
    return {
        'passed': True,
        'mode': 'recorded-only',
        'solver_checks': outcomes,
        'model_bindings': bindings,
        'operating_witness_recorded': True,
        'new_engine_jobs': 0,
        'whole_device_theorem': False,
    }


def process_tree_RSS(pid):
    raw = subprocess.run(
        ['ps', '-axo', 'pid=,ppid=,rss='],
        capture_output=True,
        text=True,
        check=True,
        timeout=5,
    ).stdout
    table = {}
    for line in raw.splitlines():
        parts = line.split()
        if len(parts) == 3 and all((x.isdigit() for x in parts)):
            table[int(parts[0])] = (int(parts[1]), int(parts[2]) * 1024)
    owned = {pid}
    while True:
        more = {p for p, (parent, _) in table.items() if parent in owned}
        if more <= owned:
            break
        owned |= more
    return sum((table.get(p, (0, 0))[1] for p in owned))


def execute(output, name, command, cwd, seconds, expected=None):
    directory = output / 'fresh' / name
    directory.mkdir(parents=True)
    started = time.monotonic()
    peak = 0
    reason = None
    with (directory / 'tool.log').open('w') as log:
        process = subprocess.Popen(command, cwd=cwd, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            while process.poll() is None:
                peak = max(peak, process_tree_RSS(process.pid))
                if peak > 4 * 1024 ** 3:
                    reason = 'owned-process-tree-RSS-cap'
                if time.monotonic() - started > seconds:
                    reason = 'timeout'
                if reason:
                    os.killpg(process.pid, signal.SIGKILL)
                    break
                time.sleep(0.1)
            code = process.wait()
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
    raw = (directory / 'tool.log').read_bytes()
    result = {
        'command': command,
        'exit_code': code,
        'stop_reason': reason,
        'seconds': time.monotonic() - started,
        'peak_RSS_bytes': peak,
        'log_sha256': sha(raw),
        'answer': raw.strip().decode() if expected else None,
        'passed': code == 0 and reason is None and (expected is None or raw.strip().decode() == expected),
    }
    save(directory / 'RESULT.json', result)
    assert result['passed'], name + ' failed; see ' + str(directory)
    return result


def select_tools(receipt):
    selected = {}
    managed = read(receipt) if receipt else None
    for name, version_args in [('yosys', ['-V']), ('z3', ['--version']), ('iverilog', ['-V']), ('vvp', ['-V'])]:
        if managed:
            if name in managed['executables']:
                row = managed['executables'][name]
                path = Path(row['path'])
                assert sha(path.read_bytes()) == row['sha256']
            else:
                path = Path(managed['executables']['yosys']['path']).parent / name
        else:
            found = shutil.which(name)
            assert found, 'Missing ' + name
            path = Path(found)
        result = subprocess.run([str(path), *version_args], capture_output=True, text=True, timeout=10, check=True)
        version = (result.stdout + result.stderr).strip()
        if managed and name in ['yosys', 'z3']:
            assert version == managed['versions'][name]
        selected[name] = {
            'path': str(path),
            'sha256': sha(path.read_bytes()),
            'version': version,
        }
    return selected


def fresh(output, project, plan, tool_receipt):
    tools = select_tools(tool_receipt)
    save(output / 'TOOLS.json', tools)
    models = {}
    for role in ['original', 'stale-capture']:
        directory = output / 'fresh-models' / role
        shutil.copytree(project / 'sources', directory)
        if role == 'stale-capture':
            shutil.copy2(project / 'stale-bridge.sv', directory / 'front/bridge.sv')
        execute(output, 'compile-' + role, [tools['yosys']['path'], '-Q', 'compile.ys'], directory, 60)
        raw = (directory / 'native.smt2').read_bytes()
        check_model(raw, read(directory / 'native.json'), plan['top'])
        models[role] = raw
    outcomes = {}
    for name in ORDER:
        row = plan['rules'][name]
        query = output / 'queries' / (name + '.smt2')
        query.parent.mkdir(exist_ok=True)
        query.write_bytes(body(project, row, models[row['model_role']]))
        outcomes[name] = execute(
            output,
            name,
            [tools['z3']['path'], '-memory:4096', '-T:120', str(query)],
            project,
            120,
            row['expected'],
        )
        outcomes[name]['query_sha256'] = sha(query.read_bytes())
    directory = project / 'witness'
    w = read(directory / 'PLAN.json')
    command = list(w['compile_command'])
    command[0] = tools['iverilog']['path']
    execute(output, 'witness-compile', command, directory, 60)
    execute(output, 'witness-simulation', [tools['vvp']['path'], 'witness.vvp'], directory, 60)
    log = (output / 'fresh/witness-simulation/tool.log').read_text()
    assert (
        w['expected_marker'] in log
        and w['actual_reset_marker'] in log
        and 'FATAL:' not in log
        and 'ERROR:' not in log
    )
    execute(
        output,
        'guard-compile',
        [tools['iverilog']['path'], '-g2012', '-s', 'unknown_guard_case', '-o', 'guard.vvp', 'guard-validation.sv'],
        directory,
        60,
    )
    execute(output, 'guard-simulation', [tools['vvp']['path'], 'guard.vvp'], directory, 60)
    assert w['guard_marker'] in (output / 'fresh/guard-simulation/tool.log').read_text()
    return {
        'passed': True,
        'mode': 'fresh-recompute',
        'native_compiles': 2,
        'solver_checks': outcomes,
        'operating_witness': True,
        'guard_validation': True,
        'compiler_byte_identity_assumed': False,
        'whole_device_theorem': False,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--recorded', action='store_true')
    mode.add_argument('--fresh', action='store_true')
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--repository-root', type=Path, default=HERE.parents[3])
    parser.add_argument('--tool-receipt', type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    assert not output.exists(), 'Use a new output directory'
    output.mkdir(parents=True)
    try:
        project, plan = load_packet(output, args.repository_root.resolve())
        result = recorded(project, plan)
        save(output / 'RECORDED-RESULT.json', result)
        if args.fresh:
            result = fresh(output, project, plan, args.tool_receipt)
        save(output / 'RESULT.json', result)
        print(json.dumps({
            'passed': True,
            'mode': result['mode'],
            'solver_checks': 18,
            'whole_device_theorem': False,
        }))
    except Exception as error:
        save(output / 'FAILURE.json', {
            'passed': False,
            'error': str(error),
            'whole_device_theorem': False,
        })
        raise
if __name__ == '__main__':
    main()
