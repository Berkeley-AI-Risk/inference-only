"""Recompile and reprove CLEAR using fresh native semantics, without model identity."""

if not __debug__:
    raise SystemExit("Verification requires Python assertions; do not use -O or -OO")
import argparse, concurrent.futures, copy, importlib.util, json, os, shutil, subprocess, sys, time
from pathlib import Path
sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec); spec.loader.exec_module(result); return result
runner = module('epoch_recorded_runner', HERE / 'run.py')
ROLES = ['original', 'omit-increment', 'suppress-exhaustion-fault']

def select_tools(receipt_path, out):
    receipt_path = receipt_path.resolve(); raw = receipt_path.read_bytes(); receipt = json.loads(raw)
    assert receipt['passed'] is True
    entries = [str(Path(p).resolve()) for p in receipt['path_entries']]
    assert entries and all(Path(p).is_dir() and Path(p).is_relative_to(receipt_path.parent) for p in entries)
    ambient = {name: shutil.which(name) for name in ['yosys', 'z3', 'cvc5']}
    os.environ['PATH'] = os.pathsep.join(entries + [os.environ.get('PATH', '')])
    selected = {}
    for name, flag in [('yosys', '-V'), ('z3', '--version'), ('cvc5', '--version')]:
        expected = receipt['executables'][name]; binary = Path(shutil.which(name)).resolve()
        assert binary == Path(expected['path']).resolve() and binary.is_relative_to(receipt_path.parent), ('Wrong tool selected', name)
        assert runner.sha(binary.read_bytes()) == expected['sha256'], ('Tool binary changed', name)
        version = subprocess.run([str(binary), flag], capture_output=True, text=True, timeout=10, check=True).stdout.strip()
        assert version == receipt['versions'][name], ('Tool version differs from install receipt', name)
        selected[name] = {'path': str(binary), 'sha256': expected['sha256'], 'version': version}
    result = {'passed': True, 'install_receipt_sha256': runner.sha(raw), 'ambient_executables': ambient, 'selected_executables': selected}
    runner.save(out / 'TOOL-SELECTION.json', result)
    return selected

def check_native(raw, source):
    modules = json.loads(raw)['modules']; top = modules[source['top']]
    expected = sorted([(640, 32), (13824, 32), (64, 32)] + [(4096, 32)] * 6)
    memories = sorted((int(c['parameters']['SIZE'], 2), int(c['parameters']['WIDTH'], 2))
                      for c in top['cells'].values() if c['type'] == '$mem_v2')
    assert memories == expected, 'Changed full native memory geometry'
    assert int(top['parameter_default_values']['DDR_TIMEOUT_CYCLES'], 2) == 50000000
    assert len(top['netnames']['epoch_q']['bits']) == 64, 'Changed native epoch width'
    assert not any(c['type'] in ['$assert', '$assume', '$anyconst', '$anyseq'] for c in top['cells'].values())
    assert not any(m.get('attributes', {}).get('blackbox') in ['1', 1, '00000000000000000000000000000001'] for m in modules.values())
    return {'memory_geometry': memories, 'native_epoch_bits': 64, 'DDR_TIMEOUT_CYCLES': 50000000}

def compile_models(project, out, source, core, deadline):
    overrides, receipts = {}, []
    for role in ROLES:
        assert time.monotonic() < deadline - 60, 'Insufficient compiler budget'
        old = project / 'models' / role; target = out / 'fresh-models' / role
        target.mkdir(parents=True)
        for name in ['native.sv', 'compile.ys']:
            (target / name).write_bytes((old / name).read_bytes())
        command = ['yosys', '-Q', 'compile.ys']; started = time.monotonic()
        with (target / 'compile.log').open('w') as log:
            result = subprocess.run(command, cwd=target, stdout=log, stderr=subprocess.STDOUT, timeout=60)
        assert result.returncode == 0, ('Compile failed', role)
        smt = (target / 'native.smt2').read_bytes(); circuit = (target / 'native.json').read_bytes()
        shape = check_native(circuit, source)
        assert not any(x[0] in ['assert', 'check-sat', 'assume'] for x in core.parse(smt.decode()))
        receipt = {'role': role, 'command': command, 'exit_code': result.returncode,
                   'seconds': time.monotonic() - started,
                   'source_sha256': runner.sha((target / 'native.sv').read_bytes()),
                   'recipe_sha256': runner.sha((target / 'compile.ys').read_bytes()),
                   'native_smt_sha256': runner.sha(smt), 'native_json_sha256': runner.sha(circuit),
                   'old_smt_sha256': runner.sha((old / 'native.smt2').read_bytes()),
                   'raw_SMT_identical_to_recorded': smt == (old / 'native.smt2').read_bytes(),
                   'model_identity_required': False, 'fresh_semantics_reproved': True, **shape}
        runner.save(target / 'RESULT.json', receipt); receipts.append(receipt)
        overrides['models/' + role + '/native.smt2'] = target / 'native.smt2'
    return overrides, receipts

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, required=True); parser.add_argument('--model', type=Path, required=True)
    parser.add_argument('--tool-receipt', type=Path, required=True, help='TOOLS.json from the pinned installer; selected tools and versions must match')
    parser.add_argument('--timeout', type=int, default=120); parser.add_argument('--total-timeout', type=int, default=900)
    parser.add_argument('--workers', type=int, default=2); parser.add_argument('--memory-mb', type=int, default=4096)
    args = parser.parse_args()
    assert 0 < args.timeout <= 600 and 1 <= args.workers <= 2 and args.memory_mb >= 256 and args.total_timeout > 0
    out = args.out.resolve(); assert not out.exists(), 'Use a new output directory'; out.mkdir(parents=True)
    started = time.monotonic()
    try:
        selected = select_tools(args.tool_receipt, out)
        project, package = runner.unpack(out)
        core = module('epoch_graph_check', project / 'check.py')
        source = json.loads((HERE / 'SOURCE.json').read_text())
        result, graph = core.validate(project, source, args.model.resolve(), HERE / 'THEOREM.smt2')
        versions = {}
        for name, flag in [('yosys', '-V'), ('z3', '--version'), ('cvc5', '--version')]:
            version = subprocess.run([name, flag], capture_output=True, text=True, timeout=10, check=True)
            versions[name] = version.stdout.strip()
        runner.save(out / 'TOOL-VERSIONS.json', {'python': sys.version, 'tools': versions})
        overrides, compiled = compile_models(project, out, source, core, started + args.total_timeout)
        fresh_graph = copy.deepcopy(graph); queries = out / 'fresh-queries'; queries.mkdir()
        native_bindings = {}
        for name, node in fresh_graph['nodes'].items():
            bindings = []
            for path in node['inputs']:
                if path.startswith('models/'):
                    assert path in overrides, ('Unreplaced model', name, path)
                    bindings.append({'role_input': path, 'fresh_model_sha256': runner.sha(overrides[path].read_bytes())})
            raw = core.build_query(project, node, overrides)
            path = queries / (name + '.smt2'); path.write_bytes(raw)
            node['query'] = '../fresh-queries/' + path.name; node['query_sha256'] = runner.sha(raw)
            native_bindings[name] = bindings
        runner.save(out / 'FRESH-GRAPH.json', fresh_graph)
        runner.save(out / 'FRESH-BINDINGS.json', native_bindings)
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
            futures = [pool.submit(runner.solve, project, out, name, row, args, started + args.total_timeout, core)
                       for name, row in fresh_graph['nodes'].items()]
            replies = [f.result() for f in futures]
        assert all(r['expected_result_matched'] for r in replies), 'Unresolved fresh query; no qualification'
        assert len(compiled) == 3 and len(replies) == 26
        result.update(passed=True, mode='fresh-recomputed', source_files_checked=len(source['production_files']),
                      package_archive_sha256=runner.sha((HERE / 'project.tar.gz').read_bytes()),
                      fresh_native_compilations=3, fresh_solver_queries=26,
                      all_fresh_expected_results_matched=True, recorded_model_identity_required=False,
                      installed_tool_receipt_validated=True,
                      fresh_graph_sha256=runner.sha((out / 'FRESH-GRAPH.json').read_bytes()),
                      fresh_binding_sha256=runner.sha((out / 'FRESH-BINDINGS.json').read_bytes()),
                      seconds=time.monotonic() - started)
        runner.save(out / 'RESULT.json', result); print(json.dumps(result, indent=2))
    except Exception as error:
        runner.save(out / 'FAILURE.json', {'passed': False, 'error': str(error), 'seconds': time.monotonic() - started})
        raise
if __name__ == '__main__': main()
