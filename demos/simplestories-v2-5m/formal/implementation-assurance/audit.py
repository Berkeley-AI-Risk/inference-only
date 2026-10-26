"""Audit current RTL proof inputs, reversible instrumentation and raw outcomes.

This checks recorded evidence. It does not silently run a solver or certify
source-to-bitstream equivalence. The JSON passed flags alone are insufficient.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('_binding',HERE/'run_handoff.py')
common = importlib.util.module_from_spec(spec)
spec.loader.exec_module(common)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def replace_one(source,old,new):
    if source.count(old) != 1:
        raise ValueError('Instrumentation boundary changed: '+repr(old[:100]))
    return source.replace(old,new)


def strip_monitor(source,monitor):
    if not source.startswith('`undef FORMAL\n'):
        raise ValueError('Original FORMAL blocks were not disabled')
    source = source.removeprefix('`undef FORMAL\n')
    return replace_one(source,'\n'+monitor+'\nendmodule','\nendmodule')


def instrumentation(run,inputs,pin,root):
    child = (HERE/'handoff-monitor.inc.sv').read_text().replace('__KV_LIMIT__',str(pin['kv_limit']))
    mutant = inputs.get('mutant')
    kind = run.name.split('-')[0]
    if kind == 'qspi':
        native = 'project/fpga/token_only_model0_ddr_board1/product_top4/rtl/board1_context2048_qspi_read03_master.sv'
        original = (root/native).read_bytes()
        if (run/'production-qspi.sv').read_bytes() != original:
            raise ValueError('Flash production source changed')
        monitor = (HERE/'qspi-monitor.inc.sv').read_text()
        source = strip_monitor((run/'qspi.sv').read_text(),monitor)
        if mutant:
            old,new = (('READ_OPCODE = 8\'h03','READ_OPCODE = 8\'h02') if mutant == 'program-opcode' else
                       ('IMAGE_BASE = 24\'h801000','IMAGE_BASE = 24\'h801020'))
            source = replace_one(source,new,old)
        if source.encode() != original:
            raise ValueError('Flash production logic was changed beyond the declared mutant')
        return
    original = (root/'project/handoff.sv').read_bytes()
    if (run/'production-handoff.sv').read_bytes() != original:
        raise ValueError('Handoff production source changed')
    source = strip_monitor((run/'handoff.sv').read_text(),child)
    if kind == 'handoff' and mutant:
        old,new = common.MUTATIONS[mutant]
        source = replace_one(source,new,old)
    if kind == 'memory':
        source = replace_one(source,'    assign f_runtime_phase_o = runtime_q;\n','')
        source = replace_one(source,'    output logic fault_o,\n    output wire f_runtime_phase_o\n','    output logic fault_o\n')
    if source.encode() != original:
        raise ValueError('Handoff production logic was changed beyond read-only observation')
    if kind != 'memory':
        return
    parent_original = (root/'project/booted_memory.sv').read_bytes()
    adapter_original = (root/'project/adapter.sv').read_bytes()
    if (run/'production-memory.sv').read_bytes() != parent_original or (run/'production-adapter.sv').read_bytes() != adapter_original:
        raise ValueError('Parent/adapter production sources changed')
    if (run/'adapter.sv').read_bytes() != b'`undef FORMAL\n'+adapter_original:
        raise ValueError('Runtime adapter logic changed')
    monitor = (HERE/'memory-monitor.inc.sv').read_text().replace('__KV_LIMIT__',str(pin['kv_limit']))
    parent = strip_monitor((run/'memory.sv').read_text(),monitor)
    if mutant:
        parent = replace_one(parent,'    wire f_unused_checked_command;\n    assign app_cmd_en_o = runtime_cmd_en;\n','')
        parent = replace_one(parent,'.app_cmd_en_o(f_unused_checked_command)','.app_cmd_en_o(app_cmd_en_o)')
        if mutant == 'bypass-handoff-output-and-data':
            parent = replace_one(parent,'    wire f_unused_checked_data,f_unused_checked_end;\n'
                '    assign app_wr_data_en_o = runtime_data_en;\n'
                '    assign app_wr_data_end_o = runtime_data_end;\n','')
            parent = replace_one(parent,'.app_data_en_o(f_unused_checked_data),.app_data_end_o(f_unused_checked_end)',
                '.app_data_en_o(app_wr_data_en_o),.app_data_end_o(app_wr_data_end_o)')
    parent = replace_one(parent,'    wire f_runtime_phase;\n','')
    parent = replace_one(parent,',.f_runtime_phase_o(f_runtime_phase)','')
    cuts = inputs['internal_cuts']
    if len(cuts) != 14 or sum(c['width'] for c in cuts) != 330:
        raise ValueError('Unexpected boot abstraction boundary')
    declarations,assigns = [],[]
    for row in cuts:
        port = 'f_boot_cut_'+row['output']
        declarations.append(f'    input wire [{row["width"]-1}:0] {port}')
        assigns.append(f'    assign {row["connected_net"]} = {port};')
    parent = replace_one(parent,',\n'+',\n'.join(declarations),'')
    original_text = parent_original.decode()
    start = original_text.index('    board1_context2048_ddr_locked_auth_watchdog_cdc_quarantined_payload u_boot (')
    end = original_text.index(');',start)+2
    parent = replace_one(parent,'\n'.join(assigns),original_text[start:end])
    if parent.encode() != parent_original:
        raise ValueError('Parent production logic changed beyond declared output cuts and read-only observation')


def raw_results(run,inputs,finished):
    mutant = inputs.get('mutant')
    count = inputs['assertion_cells']
    design = json.loads((run/'elaborated.json').read_text())
    cells = [c['type'] for m in design['modules'].values() for c in m.get('cells',{}).values()]
    if cells.count('$assert') != count or cells.count('$cover') != inputs['cover_cells']:
        raise ValueError('Elaborated property inventory mismatch')
    if any(t in cells for t in ('$assume','$anyseq','$anyconst','$mem_v2')):
        raise ValueError('Unexpected formal abstraction, memory or assumption')
    smt = (run/'design.smt2').read_text()
    if len(re.findall(r'^; yosys-smt2-assert ',smt,re.M)) != count:
        raise ValueError('SMT assertion count mismatch')
    if re.search(r'^; yosys-smt2-(?:assume|anyseq|anyconst) ',smt,re.M):
        raise ValueError('Unexpected SMT formal cells')
    phases = ('bmc',) if mutant else ('bmc','induction','cover')
    expected = {s+'-'+p for s in ('z3','cvc5') for p in phases}
    if set(finished['results']) != expected:
        raise ValueError('Missing solver phase')
    conclusions = {}
    for label,row in finished['results'].items():
        raw = (run/(label+'.log')).read_bytes()
        if sha(raw) != row['log_sha256'] or row.get('timed_out') or row['passed'] is not True:
            raise ValueError('Solver log is changed, incomplete or failed: '+label)
        text = raw.decode()
        if row.get('verification_mode'):
            if label != 'cvc5-cover' or run.name.split('-')[0] != 'qspi':
                raise ValueError('Unexpected concrete-witness scope')
            target = run/'secondary-complete-witness'
            witness = json.loads((target/'FINISHED.json').read_text())
            if sha((target/'FINISHED.json').read_bytes()) != row['witness_result_sha256']:
                raise ValueError('Secondary witness receipt changed')
            if (witness['passed'] is not True or witness['answers'] != ['sat'] or witness['exit'] != 0 or
                witness['states_checked'] != 163 or witness['cover_goals_checked'] != 2 or
                not witness['all_safety_properties_checked'] or not witness['all_state_transitions_checked']):
                raise ValueError('Secondary witness was not verified')
            for name,key in [('cvc5.log','log_sha256'),('witness.smt2','query_sha256')]:
                if sha((target/name).read_bytes()) != witness[key]:
                    raise ValueError('Secondary witness bytes changed')
            if witness['primary_trace_sha256'] != sha((run/'z3-cover-0.vcd').read_bytes()) or witness['emitted_smt_sha256'] != sha((run/'design.smt2').read_bytes()):
                raise ValueError('Secondary witness refers to a different RTL/trace')
            if (target/'cvc5.log').read_text().strip() != 'sat':
                raise ValueError('Secondary raw SAT answer missing')
            conclusions[label] = 'complete state/input/output witness verified'
            continue
        status = re.findall(r'Status: (\w+)',text)
        if status != (['FAILED'] if mutant else ['PASSED']) or row['exit'] != (1 if mutant else 0):
            raise ValueError('Unexpected raw solver status')
        if mutant:
            if 'BMC failed!' not in text or 'Assert failed in ' not in text or not row.get('traces',row.get('witnesses')):
                raise ValueError('A semantic counterexample is required')
        if label.endswith('induction') and 'Temporal induction successful.' not in text:
            raise ValueError('Unbounded induction did not close')
        if label.endswith('cover') and len(re.findall('Reached cover statement',text)) != inputs['cover_cells']:
            raise ValueError('Legal-traffic covers are incomplete')
        for name,digest in row.get('traces',row.get('witnesses',{})).items():
            if sha((run/name).read_bytes()) != digest:
                raise ValueError('Witness bytes changed')
        query_path = run/(label+'.smt2')
        if 'query_sha256' in row and query_path.is_file():
            query = query_path.read_text()
            if sha(query_path.read_bytes()) != row['query_sha256']:
                raise ValueError('Raw query changed')
            def normalized(value):
                return [s.strip() for s in value.splitlines() if s.strip() and not s.startswith((';','(set-option ','(set-logic '))]
            d,q = normalized(smt),normalized(query)
            if q[:len(d)] != d:
                raise ValueError('Query does not contain the reviewed emitted RTL')
            if label.endswith('induction'):
                tail = '\n'.join(q[len(d):])
                if re.search(r'^\(assert .*_n (?:\w+_)?reset_n(?:_i)?\| s\d+\) false',tail,re.M):
                    raise ValueError('Reset was constrained during induction')
                if re.search(r'^\(assert \(\|\w+_i\| s\d+\)\)',tail,re.M):
                    raise ValueError('Initial state was constrained during induction')
                if '--smtc' in row['command']:
                    raise ValueError('Induction received external constraints')
        conclusions[label] = 'semantic counterexample' if mutant else 'induction' if label.endswith('induction') else 'reachability' if label.endswith('cover') else 'base checked'
    return conclusions


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package',type=Path,default=common.DEFAULT_PACKAGE)
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--without-qspi',action='store_true')
    args = parser.parse_args()
    bindings = {name: common.binding(args.package.resolve(),name) for name in
        ('baseline','kv-protected','encrypted-memory','seeded-sampling')}
    selections = []
    for variant in bindings:
        selections += [(f'handoff-{variant}-r1',variant),(f'memory-{variant}-r1',variant)]
    for variant in ('baseline','encrypted-memory'):
        for mutant in common.MUTATIONS:
            selections.append((f'handoff-{variant}-mutant-{mutant}-r1',variant))
        selections.append((f'memory-{variant}-mutant-bypass-handoff-output-and-data-r1',variant))
    if not args.without_qspi:
        selections.append(('qspi-baseline-r6','baseline'))
        for mutant in ('program-opcode','change-flash-address'):
            selections.append((f'qspi-baseline-mutant-{mutant}-r1','baseline'))
    reports = []
    for name,variant in selections:
        run = HERE/'runs'/name
        input_raw,finished_raw = (run/'INPUTS.json').read_bytes(),(run/'FINISHED.json').read_bytes()
        inputs,finished = json.loads(input_raw),json.loads(finished_raw)
        if finished['passed'] is not True or finished['inputs_sha256'] != sha(input_raw):
            raise ValueError('Proof receipt does not pass: '+name)
        pin,root,bound = bindings[variant]
        for key,value in bound.items():
            if inputs['binding'].get(key) != value:
                raise ValueError('Current source binding changed: '+name+' '+key)
        for filename,row in inputs['files'].items():
            raw = (run/filename).read_bytes()
            if len(raw) != row['bytes'] or sha(raw) != row['sha256']:
                raise ValueError('Frozen proof input changed: '+filename)
        instrumentation(run,inputs,pin,root)
        conclusions = raw_results(run,inputs,finished)
        reports.append(dict(run=name,variant=variant,mutant=inputs.get('mutant'),
            inputs_sha256=sha(input_raw),finished_sha256=sha(finished_raw),
            assertion_cells=inputs['assertion_cells'],cover_cells=inputs['cover_cells'],
            raw_conclusions=conclusions,exact_production_recovered=True,
            internal_cuts=inputs.get('internal_cuts',[])))
    qspi_join = None
    if not args.without_qspi:
        native = 'project/fpga/token_only_model0_ddr_board1/product_top4/rtl/board1_context2048_qspi_read03_master.sv'
        digests = {name:sha((root/native).read_bytes()) for name,(_,root,_) in bindings.items()}
        if len(set(digests.values())) != 1:
            raise ValueError('Flash reader does not have byte-identical implementations')
        qspi_join = digests
    result = dict(schema='current-fixed-model-rtl-assurance-audit-v1',passed=True,
        current_source_bindings_rechecked=True,recorded_only=True,fresh_solver_execution=False,
        proofs=reports,qspi_identical_component_join=qspi_join,property_counts_overlap=True,
        physical_transport_composed=False,whole_machine_theorem=False,
        checker_sha256=sha(Path(__file__).read_bytes()))
    with args.out.open('x') as out:
        json.dump(result,out,indent=2,sort_keys=True)
        out.write('\n')
    print('AUDIT PASS',len(reports),'runs; exact production logic recovered; raw outcomes checked')


if __name__ == '__main__':
    main()
