"""Audit the complete primary controller proof and join its exact source scope.

The secondary induction timeout stays explicit. This does not turn a failed
two-solver campaign into a two-solver proof or inherit a numerical theorem.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent


def sha(raw): return hashlib.sha256(raw).hexdigest()


def load(name):
    spec = importlib.util.spec_from_file_location('_control_audit_'+name,HERE/(name+'.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def normalized(s):
    return [line.strip() for line in s.splitlines() if line.strip() and not line.startswith((';','(set-option ','(set-logic '))]


def inspect(run,files,sources,binding,mutant=None):
    inp_raw,fin_raw = (run/'INPUTS.json').read_bytes(),(run/'FINISHED.json').read_bytes()
    inp,fin = json.loads(inp_raw),json.loads(fin_raw)
    if fin['inputs_sha256'] != sha(inp_raw) or inp['mutant'] != mutant:
        raise ValueError('Control proof receipt identity changed')
    if inp['assertion_cells'] != 134 or inp['observer_constants'] != 1 or inp['internal_cuts'] != binding['private_semantic_output_cuts']:
        raise ValueError('Control proof scope changed')
    if inp['compile_sources'] != sources or inp['binding']['native_inventory_sha256'] != binding['native_binding']['native_inventory_sha256']:
        raise ValueError('Compiled source selection changed')
    for key,value in binding['native_binding'].items():
        if inp['binding'].get(key) != value:
            raise ValueError('Current native/image binding changed: '+key)
    for name,row in inp['files'].items():
        raw = (run/name).read_bytes()
        if len(raw) != row['bytes'] or sha(raw) != row['sha256']:
            raise ValueError('Frozen control proof input changed: '+name)
    for name,raw in files.items():
        if (run/name).read_bytes() != raw:
            raise ValueError('Control instrumentation/source could not be reproduced: '+name)
    design = json.loads((run/'elaborated.json').read_text())
    cells = [(n,c) for m in design['modules'].values() for n,c in m.get('cells',{}).items()]
    kinds = [c['type'] for _,c in cells]
    if kinds.count('$assert') != 134 or kinds.count('$anyconst') != 1 or kinds.count('$mem_v2') != 17 or '$assume' in kinds or '$anyseq' in kinds:
        raise ValueError('Unexpected elaborated controller geometry or formal cuts')
    smt = (run/'design.smt2').read_text()
    if len(re.findall(r'^; yosys-smt2-assert ',smt,re.M)) != 134:
        raise ValueError('Missing SMT assertion')
    primary = {}
    for phase in (('bmc',) if mutant else ('bmc','induction')):
        label = 'z3-'+phase
        row = fin['results'][label]
        raw = (run/(label+'.log')).read_bytes()
        query = (run/(label+'.smt2')).read_bytes()
        if sha(raw) != row['log_sha256'] or sha(query) != row['query_sha256'] or row['timed_out']:
            raise ValueError('Primary proof bytes changed or timed out')
        status = re.findall(r'Status: (\w+)',raw.decode())
        if status != (['FAILED'] if mutant else ['PASSED']) or row['exit'] != (1 if mutant else 0):
            raise ValueError('Primary controller safety result is incomplete')
        if not mutant and phase == 'induction' and b'Temporal induction successful.' not in raw:
            raise ValueError('No unbounded controller proof')
        if mutant and (b'BMC failed!' not in raw or b'Assert failed in ' not in raw or not row['traces']):
            raise ValueError('Fault-gate mutant lacks a semantic counterexample')
        d,q = normalized(smt),normalized(query.decode())
        if q[:len(d)] != d:
            raise ValueError('Primary query is not the emitted actual RTL')
        if phase == 'induction':
            if '--smtc' in row['command']:
                raise ValueError('Induction was externally constrained')
            tail = '\n'.join(q[len(d):])
            if re.search(r'^\(assert .*_n \w*reset_n\w*\| s\d+\) false',tail,re.M):
                raise ValueError('Reset constrained during induction')
            if re.search(r'^\(assert \(\|\w+_i\| s\d+\)\)',tail,re.M):
                raise ValueError('Initial state constrained during induction')
        for name,digest in row.get('traces',{}).items():
            if sha((run/name).read_bytes()) != digest:
                raise ValueError('Counterexample trace changed')
        primary[phase] = dict(status=status,log_sha256=sha(raw),query_sha256=sha(query))
    memories = {n:{k:int(c['parameters'][k],2) for k in ('WIDTH','SIZE','ABITS')}
                for n,c in cells if c['type'] == '$mem_v2'}
    secondary = {}
    for label,row in fin['results'].items():
        if not label.startswith('cvc5-'):continue
        raw = (run/(label+'.log')).read_bytes()
        if sha(raw) != row['log_sha256']:
            raise ValueError('Secondary result bytes changed')
        secondary[label] = {key:row.get(key) for key in ('status','exit','passed','timed_out')}
        secondary[label]['raw_log_sha256'] = sha(raw)
    return dict(run=run.name,primary_unbounded_safety_proved=not mutant,
        semantic_mutant_detected=bool(mutant),primary=primary,secondary=secondary,
        complete_two_solver_induction=all(fin['results'].get(s+'-induction',{}).get('passed') is True for s in ('z3','cvc5')),
        memories=memories,
        inputs_sha256=sha(inp_raw),finished_sha256=sha(fin_raw),
        exact_current_source_instrumentation_reproduced=True)


def main():
    common,model = load('run_handoff'),load('control_model')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package',type=Path,default=common.DEFAULT_PACKAGE)
    parser.add_argument('--out',type=Path,required=True)
    args = parser.parse_args()
    package = args.package.resolve()
    baseline_files,baseline_sources,baseline_binding = model.derive(package,'baseline',common)
    proof = inspect(HERE/'runs/control-baseline-r3',baseline_files,baseline_sources,baseline_binding)
    mutants = []
    for lane in ('write','read'):
        mutant = 'bypass-kv-'+lane+'-fault-gate'
        files = dict(baseline_files)
        key = model.MACHINE_DIR+model.CORE_NAME+'.sv'
        old = f'assign kv_{lane}_req_valid_o = !root_terminal && child_kv_{lane}_req_valid;'.encode()
        new = f'assign kv_{lane}_req_valid_o = child_kv_{lane}_req_valid;'.encode()
        if files[key].count(old) != 1:raise ValueError('Mutation site changed')
        files[key] = files[key].replace(old,new)
        mutants.append(inspect(HERE/('runs/control-baseline-mutant-'+mutant+'-r1'),files,baseline_sources,baseline_binding,mutant))
    # Protected wrappers connect an additional integrity fault. They receive
    # fresh proofs of their actual compositions rather than a byte-equality
    # claim about the entire baseline wrapper.
    scope_names = set(baseline_sources)|{name for name in baseline_files if name.endswith('.memh')}
    joins = {}
    for variant in ('baseline','kv-protected','encrypted-memory'):
        files,sources,binding = model.derive(package,variant,common)
        run = HERE/('runs/control-baseline-r3' if variant == 'baseline' else 'runs/control-'+variant+'-r1')
        actual_proof = proof if variant == 'baseline' else inspect(run,files,sources,binding)
        shared_names = scope_names-{'composition.sv'}
        if sources != baseline_sources or any(files[name] != baseline_files[name] for name in shared_names):
            raise ValueError('Core/shell/component scope is different: '+variant)
        joins[variant] = dict(native_binding=binding['native_binding'],
            compiled_scope_sha256={name:sha(files[name]) for name in sorted(scope_names)},
            actual_public_bindings=binding['public_binding_chain'],
            private_semantic_output_cuts=binding['private_semantic_output_cuts'],
            current_composition_proof=actual_proof,only_composition_wrapper_may_differ=True)
    report = dict(schema='current-greedy-connected-controller-audit-v1',passed=True,
        primary_assertions_proved=134,primary_solver='z3',primary_proof=proof,
        secondary_induction_complete=False,secondary_limit='cvc5 induction timed out; no secondary induction theorem credited',
        mutant_checks=mutants,current_proofs_and_shared_component_source_joins=joins,
        private_backend_outputs_unrestricted=37,actual_memory_cells=17,
        constant_tape_slot_observers=1,assumption_cells=0,
        numerical_inference_theorem=False,private_authentication_composition=False,
        physical_transport_composed=False,source_to_bitstream_equivalence=False,
        checker_sha256=sha(Path(__file__).read_bytes()))
    with args.out.open('x') as out:
        json.dump(report,out,indent=2,sort_keys=True);out.write('\n')
    print('CONTROL AUDIT PASS: 134 primary inductive assertions in each of 3 actual current compositions, 17 memories, 2 fault-gate mutants')


if __name__ == '__main__':
    main()
