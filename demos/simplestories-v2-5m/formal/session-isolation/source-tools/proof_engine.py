"""SMTBMC driver retaining separate state cells in relational models.

Derived from authentication-access/engine.py by adding hierarchy/proc and keep
attributes before preparation/optimization. No transition, assertion or solver
policy changes. Explicit unequal-old-state covers check that independence.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import shutil
import subprocess
import sys
import time


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def check(run, files, *, top, reset_constraints, assertions, covers, binding,
          scope, cuts, depth=14, timeout=90, mutant=None, induction_depth=None,
          cover_constraints=None, cover_depth=None, secondary_cover_witness=False,
          source_list=None, observer_constants=0, expected_memories=None, solver_cli=None,
          secondary_base_only=False, multiclock=False, expected_register_memories=None,
          expected_assumptions=0, constraint_scope_description=None, map_literal_roms=False, optimize_full=False,
          solver_order=('z3','cvc5'), induction_first=False, primary_only=False):
    run = Path(run).absolute()
    run.mkdir(parents=True, exist_ok=False)
    sources = source_list if source_list is not None else [name for name in files if name.endswith('.sv') and not name.startswith('production-') and not name.endswith('.inc.sv')]
    files = dict(files)
    if primary_only:solver_order=('z3',)
    files['engine.py'] = Path(__file__).read_bytes()
    if secondary_cover_witness:
        files['check_qspi_witness.py'] = (Path(__file__).parent/'check_qspi_witness.py').read_bytes()
    files['prove.ys'] = ('\n'.join([
        'read_verilog -formal -sv -nosynthesis -D SYNTHESIS -defer ' + ' '.join(sources),
        f'hierarchy -check -top {top}', 'proc', 'opt_clean',
        'setattr -set keep 1 t:$dff t:$adff t:$dffe t:$adffe t:$sdff t:$sdffe t:$dlatch t:$adlatch',
        f'prep -top {top} -flatten', 'memory_map -rom-only' if map_literal_roms else 'opt_clean', 'clk2fflogic' if multiclock else 'async2sync', 'opt -full' if optimize_full else 'opt_clean', 'chformal -lower', 'opt_clean',
        'dffunmap', f'select -assert-count {assertions} t:$assert',
        f'select -assert-count {covers} t:$cover',
        f'select -assert-count {expected_assumptions} t:$assume' if expected_assumptions else 'select -assert-none t:$assume',
        'select -assert-none t:$anyseq', f'select -assert-count {observer_constants} t:$anyconst', 'check -assert',
        'write_json elaborated.json', 'write_rtlil elaborated.il', 'write_smt2 -wires design.smt2',
    ]) + '\n').encode()
    files['reset.smtc'] = reset_constraints.encode()
    if cover_constraints is not None:
        files['cover.smtc'] = (reset_constraints+cover_constraints).encode()
    tools = {}
    for tool in ('yosys', 'yosys-smtbmc', 'z3', 'cvc5'):
        path = shutil.which(tool)
        if not path:
            raise ValueError('Missing tool: ' + tool)
        row = dict(path=str(Path(path).resolve()), sha256=sha(Path(path).read_bytes()))
        if tool != 'yosys-smtbmc':
            result = subprocess.run([path, '-V' if tool == 'yosys' else '--version'],
                                    capture_output=True, text=True, timeout=10, check=True)
            row['version'] = result.stdout.strip()
        tools[tool] = row
    induction_depth = depth if induction_depth is None else induction_depth
    inputs = dict(schema='current-rtl-implementation-proof-inputs-v1', top=top,
        binding=binding, tools=tools, mutant=mutant, assertion_cells=assertions,
        cover_cells=covers, assumption_cells=expected_assumptions, internal_cuts=cuts,
        observer_constants=observer_constants,compile_sources=sources,
        solver_cli=solver_cli or {},
        solver_order=list(solver_order),induction_first=induction_first,
        multiclock=multiclock,
        literal_roms_mapped=map_literal_roms,
        full_constant_optimization=optimize_full,
        expected_register_memories=expected_register_memories or {},
        secondary_induction_requested=not secondary_base_only and not primary_only,
        secondary_backend_requested=not primary_only,
        changed_production_parameters=[], induction_depth=induction_depth, base_depth=depth,
        cover_depth=cover_depth or depth, directed_cover_inputs=cover_constraints is not None, scope=scope,
        secondary_cover_policy='check complete primary state/input/output witness against every transition and safety property' if secondary_cover_witness else 'independent search',
        semantics=('two-state digital RTL; original synthesis dimensions; simulation-only X detectors excluded' +
            '; arbitrary independent source/destination clock levels with explicit edge sampling through clk2fflogic; digital CDC only, no metastability or physical skew theorem' if multiclock else
            'two-state digital RTL; original synthesis dimensions; simulation-only X detectors excluded'),
        reset_constraints=constraint_scope_description or 'Only base/cover states 0 and 1 are constrained; no reset constraints in induction.',
        files={name: dict(bytes=len(raw), sha256=sha(raw)) for name,raw in files.items()})
    for name,raw in files.items():
        (run/name).parent.mkdir(parents=True,exist_ok=True)
        (run / name).write_bytes(raw)
    (run / 'INPUTS.json').write_text(json.dumps(inputs,indent=2,sort_keys=True)+'\n')
    begin = time.monotonic()
    with (run / 'yosys.log').open('w') as out:
        compile_result = subprocess.run(['yosys','-Q','prove.ys'],cwd=run,stdout=out,
                                        stderr=subprocess.STDOUT,timeout=60)
    results = {}
    if compile_result.returncode == 0:
        design = json.loads((run/'elaborated.json').read_text())
        cells = [c['type'] for m in design['modules'].values() for c in m.get('cells',{}).values()]
        if cells.count('$assert') != assertions or cells.count('$cover') != covers:
            raise ValueError('Elaborated property count changed')
        if cells.count('$assume')!=expected_assumptions or '$anyseq'in cells or cells.count('$anyconst') != observer_constants:
            raise ValueError('Unexpected formal assumption or abstraction cell')
        if expected_memories is not None and cells.count('$mem_v2') != expected_memories:
            raise ValueError('Actual memory inventory changed')
        if expected_register_memories:
            names=design['modules'][top]['netnames']
            for prefix,geometry in expected_register_memories.items():
                rows=[names.get(prefix+'['+str(i)+']',{}).get('bits',[]) for i in range(geometry['size'])]
                bits=[b for row in rows for b in row]
                if (any(len(row)!=geometry['width']for row in rows)or
                        any(not isinstance(b,int)for b in bits)or
                        len(set(bits))!=geometry['width']*geometry['size']):
                    raise ValueError('Lowered register-memory geometry changed: '+prefix)
        if (primary_only and solver_order!=('z3',))or(not primary_only and(set(solver_order)!={'z3','cvc5'}or len(solver_order)!=2)):
            raise ValueError('Unexpected requested solver inventory')
        for solver in solver_order:
            phases=('bmc',)if mutant else(('induction','bmc','cover')if covers else('induction','bmc'))if induction_first else('bmc','induction','cover')if covers else('bmc','induction')
            for phase in phases:
                if solver == 'cvc5' and phase == 'induction' and secondary_base_only:
                    continue
                label = solver+'-'+phase
                if phase == 'cover' and solver == 'cvc5' and secondary_cover_witness:
                    # A concrete SAT witness can be verified without repeating
                    # the primary solver's reachability search. All safety
                    # induction queries above remain unrestricted.
                    command = [sys.executable,'-I','-S','-B','check_qspi_witness.py',
                               '--proof','.', '--out','secondary-complete-witness']
                    started = time.monotonic()
                    with (run/(label+'.log')).open('w') as out:
                        cp = subprocess.run(command,cwd=run,stdout=out,stderr=subprocess.STDOUT,timeout=150)
                    result_path = run/'secondary-complete-witness/FINISHED.json'
                    result = json.loads(result_path.read_text()) if result_path.is_file() else {}
                    passed = cp.returncode == 0 and result.get('passed') is True and result.get('answers') == ['sat']
                    results[label] = dict(command=command,exit=cp.returncode,timed_out=False,
                        status=['PASSED'] if passed else ['FAILED'],passed=passed,
                        verification_mode='complete state/input/output witness, not an independent search',
                        log_sha256=sha((run/(label+'.log')).read_bytes()),
                        witness_result_sha256=sha(result_path.read_bytes()) if result_path.is_file() else None,
                        seconds=time.monotonic()-started)
                    print(label,passed,results[label]['status'],flush=True)
                    continue
                phase_depth = induction_depth if phase == 'induction' else (cover_depth or depth) if phase == 'cover' else depth
                command = ['yosys-smtbmc','-s',solver,'--timeout',str(timeout),'-t',str(phase_depth),
                    '-m',top,'--dump-smt2',label+'.smt2','--dump-yw',label+'-%.yw',
                    '--dump-vcd',label+'-%.vcd','--dummy',label+'.responses','--noprogress']
                command += (solver_cli or {}).get(solver,[])
                if phase != 'induction':
                    constraints = 'cover.smtc' if phase == 'cover' and cover_constraints is not None else 'reset.smtc'
                    command += ['--smtc',constraints,'--presat']
                if phase == 'induction':
                    command += ['-i']
                if phase == 'cover':
                    command += ['-c']
                command += ['design.smt2']
                started = time.monotonic()
                timed_out = False
                with (run/(label+'.log')).open('w') as out:
                    try:
                        cp = subprocess.Popen(command,cwd=run,stdout=out,stderr=subprocess.STDOUT,
                                              start_new_session=True)
                        code = cp.wait(timeout=timeout+20)
                    except subprocess.TimeoutExpired:
                        code,timed_out = None,True
                        # Only this explicitly created child process group is
                        # terminated. Solver descendants cannot outlive a timeout.
                        try:
                            os.killpg(cp.pid,signal.SIGTERM)
                        except ProcessLookupError:
                            pass
                        try:
                            cp.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            os.killpg(cp.pid,signal.SIGKILL)
                            cp.wait()
                raw = (run/(label+'.log')).read_bytes()
                text = raw.decode(errors='replace')
                statuses = re.findall(r'Status: (\w+)',text)
                expected = 'FAILED' if mutant else 'PASSED'
                traces = sorted(run.glob(label+'-*.yw'))
                query = run/(label+'.smt2')
                passed = (not timed_out and statuses == [expected] and
                    code == (1 if mutant else 0) and query.is_file())
                if mutant:
                    passed = passed and bool(traces) and 'BMC failed!' in text and 'Assert failed in ' in text
                if phase == 'induction':
                    passed = passed and 'Temporal induction successful.' in text
                if phase == 'cover':
                    passed = passed and len(re.findall('Reached cover statement',text)) == covers
                row = dict(command=command,exit=code,timed_out=timed_out,status=statuses,passed=passed,
                    seconds=time.monotonic()-started,log_sha256=sha(raw),
                    query_sha256=sha(query.read_bytes()) if query.is_file() else None,
                    solver_responses_sha256=sha((run/(label+'.responses')).read_bytes()) if (run/(label+'.responses')).is_file() else None,
                    traces={p.name:sha(p.read_bytes()) for p in sorted(run.glob(label+'-*')) if p.suffix in ('.yw','.vcd')})
                results[label] = row
                print(label,passed,statuses,flush=True)
    unchanged = all(sha((run/name).read_bytes()) == row['sha256'] for name,row in inputs['files'].items())
    passed = compile_result.returncode == 0 and bool(results) and all(r['passed'] for r in results.values()) and unchanged
    finished = dict(schema='current-rtl-implementation-proof-result-v1',passed=passed,top=top,mutant=mutant,
        mutation_detected=bool(mutant and passed),binding=binding,assertion_cells=assertions,cover_cells=covers,
        yosys_exit=compile_result.returncode,results=results,scope=scope,internal_cuts=cuts,
        source_files_unchanged=unchanged,inputs_sha256=sha((run/'INPUTS.json').read_bytes()),
        yosys_log_sha256=sha((run/'yosys.log').read_bytes()),seconds=time.monotonic()-begin,
        unbounded_inductive_result=bool(not mutant and passed),whole_machine_theorem=False,
        physical_transport_composed=False,hardware_access=False)
    (run/'FINISHED.json').write_text(json.dumps(finished,indent=2,sort_keys=True)+'\n')
    print('FINISHED',passed,'seconds',finished['seconds'],flush=True)
    return 0 if passed else 1
