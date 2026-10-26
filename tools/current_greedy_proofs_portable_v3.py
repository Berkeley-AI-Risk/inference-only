"""Recheck archived scoped attention proofs through authenticated byte callbacks.

No Yosys, solver, model, native tool or original-path IO is performed. Queries
are rebuilt from the archived SMT and all original answers are parsed exactly.
Cached elaboration identities are observations, not a fresh elaboration. This
is not a numerical attention, memory, composition or whole-machine theorem.
"""
import hashlib
import json
from pathlib import PurePosixPath
import re

TOP = 'board1_context2048_attention'


def need(ok, message):
    if not ok:
        raise ValueError(message)


def identity(raw):
    return dict(bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest())


def child(root, name):
    p = PurePosixPath(name)
    need(name and str(p) == name and not p.is_absolute() and '..' not in p.parts and '\\' not in name,
         'Safe original proof member required')
    return str(PurePosixPath(root) / p)


def query_prefix(smt, initial):
    rows = ["(set-logic ALL)", "(set-option :produce-models true)", smt]
    for i in range(3):
        rows += [f"(declare-fun s{i} () {TOP}_s)", f"(assert ({TOP}_h s{i}))", f"(assert ({TOP}_u s{i}))",
                 f"(assert (= ({TOP}_is s{i}) {'true' if initial and i == 0 else 'false'}))"]
        if i:
            rows += [f"(assert ({TOP}_t s{i-1} s{i}))"]
    if initial:
        rows += [f"(assert ({TOP}_i s0))", f"(assert (not (|{TOP}_n rst_n| s0)))", f"(assert (not (|{TOP}_n rst_n| s1)))"]
    return rows


def unrestricted_state_predicates(smt):
    for suffix in ('i', 'h', 'u'):
        needle = f'(define-fun |{TOP}_{suffix}| ((state |{TOP}_s|)) Bool true)'
        definitions = re.findall(r'^\(define-fun \|' + re.escape(TOP + '_' + suffix) + r'\| .*', smt, re.M)
        need(definitions == [needle], 'Restricted proof initial/hierarchy/user predicate')
    need('; yosys-smt2-assume ' not in smt, 'Unexpected proof assumption')


def observer_check(module):
    def bits(values):
        return {b for b in values if isinstance(b, int)}
    nets, cells = module['netnames'], module['cells']
    selectors = [tuple(c['connections']['Y']) for c in cells.values() if c['type'] == '$anyconst']
    need(selectors == [tuple(nets['f_att_coordinate']['bits'])], 'Actual coordinate observer differs')
    reached = bits(selectors[0])
    need(len(reached) == 6, 'Six-bit arbitrary coordinate selector required')
    need(not any(c['type'] in ('$assume', '$anyinit', '$mem_v2') for c in cells.values()), 'Unreviewed assumption/state/memory')
    edges = []
    for cell in cells.values():
        ports, directions = cell['connections'], cell['port_directions']
        sources = set().union(*(bits(v) for n, v in ports.items() if directions[n] == 'input'))
        outputs = set().union(*(bits(v) for n, v in ports.items() if directions[n] == 'output'))
        edges.append((sources, outputs))
    while True:
        more = set().union(*(out for source, out in edges if source & reached))
        if more <= reached:
            break
        reached |= more
    protected = {n: bits(v['bits']) for n, v in nets.items() if not v['hide_name'] and not n.startswith('f_att_')}
    protected.update({n: bits(v['bits']) for n, v in module['ports'].items()})
    hits = [n for n, value in protected.items() if value & reached]
    need(not hits, 'Observer reaches production state/ports')
    return {'selector_bits': 6, 'production_signal_hits': []}


def arbitrary_outputs(module):
    nets, cells = module['netnames'], module['cells']
    drivers = [tuple(c['connections']['Y']) for c in cells.values() if c['type'] == '$anyseq']
    need(drivers and len(set(drivers)) == len(drivers), 'Retained arbitrary boundary drivers missing/duplicated')
    outputs, seen = {}, set()
    for driver in drivers:
        matches = []
        for name, row in nets.items():
            match = re.fullmatch(r'(.+)\.f_arbitrary_(\w+)', name)
            if match and tuple(row['bits']) == driver:
                pin = match[1] + '.' + match[2]
                need(pin in nets and tuple(nets[pin]['bits']) == driver, 'Partial arbitrary child output')
                matches.append(pin)
        need(len(matches) == 1 and all(type(bit) is int for bit in driver) and not seen.intersection(driver),
             'Arbitrary boundary output alias/overlap/constant')
        seen.update(driver)
        outputs[matches[0]] = len(driver)
    need(len(outputs) == len(drivers), 'Arbitrary boundary census differs')
    return outputs


def check_queries(reader, directory, count):
    need(type(count) is int and count in (34, 66), 'Explicit reviewed attention assertion epoch required')
    finished = reader.json(child(directory, 'FINISHED.json'))
    need(finished['passed'] is True and finished['source_unchanged'] is True and finished['yosys_exit'] == 0
         and finished['assertions'] == count, 'Closed archived scoped proof required')
    inputs_raw = reader.read(child(directory, 'INPUTS.json'))
    need(finished['inputs_sha256'] == identity(inputs_raw)['sha256'], 'Proof inputs detached')
    inputs = reader.json(child(directory, 'INPUTS.json'))
    need(inputs['assertions'] == count and inputs['induction_length'] == 2, 'Proof assertion/induction scope differs')
    for name, row in inputs['files'].items():
        reader.read(child(directory, name), row)
    smt = reader.read(child(directory, 'design.smt2')).decode()
    unrestricted_state_predicates(smt)
    need(len(re.findall(r'^; yosys-smt2-assert ', smt, re.M)) == count, 'Actual SMT assertion count differs')
    queries = {'reset-witness': (query_prefix(smt, True), ['sat']),
               'base': (query_prefix(smt, True) + [f'(assert (not (and ({TOP}_a s0) ({TOP}_a s1) ({TOP}_a s2))))'], ['unsat'])}
    for i in range(count):
        queries[f'induction-{i:03d}'] = (query_prefix(smt, False) + [f'(assert ({TOP}_a s0))', f'(assert ({TOP}_a s1))',
            f'(assert (not (|{TOP}_a {i}| s2)))'], ['unsat'])
    need(set(finished['solver_results']) == {s + '-' + n for s in ('z3', 'cvc5') for n in queries}, 'Complete two-solver query census required')
    for name, (lines, expected) in queries.items():
        raw = ('\n'.join(lines + ['(check-sat)']) + '\n').encode()
        need(reader.read(child(directory, name + '.smt2')) == raw, 'Archived query differs from exact SMT regeneration')
        for solver in ('z3', 'cvc5'):
            row = finished['solver_results'][solver + '-' + name]
            log = reader.read(child(directory, solver + '-' + name + '.log'))
            answers = [line.strip() for line in log.decode().splitlines() if line.strip()]
            need(row['passed'] is True and row['exit'] == 0 and b'(error ' not in log
                 and row['query_sha256'] == identity(raw)['sha256'] and row['log_sha256'] == identity(log)['sha256']
                 and row['answers'] == row['expected'] == answers == expected, 'Unknown/error/extra/wrong solver answer or detached query/log')
    module = reader.json(child(directory, 'elaborated.json'))['modules'][TOP]
    observer, arbitrary = observer_check(module), arbitrary_outputs(module)
    return dict(passed=True, assertions=count, queries=2 * len(queries), unknowns=0,
                observer=observer, arbitrary_child_replies=arbitrary, inputs=inputs)


def validate_attention_proof(reader, completion, spec, native_inputs):
    """spec is reviewed epoch data; it cannot be inferred from a pass boolean."""
    need(spec['assertions'] in (34, 66) and type(spec['completion_schema']) is str
         and completion['schema'] == spec['completion_schema'] and completion['passed'] is True,
         'Explicit complete scoped-proof epoch required')
    plan_pin = completion[spec['plan_field']]
    plan = reader.json(plan_pin['path'], plan_pin)
    need(plan['assumptions'] == [] and plan['added_internal_cuts'] == [], 'Unreviewed assumptions or internal proof cuts')
    proof_origin = child(spec['proof_directory'], 'FINISHED.json')
    need(completion['proof']['path'] == proof_origin, 'Actual proof directory/receipt differs')
    reader.read(proof_origin, completion['proof'])
    actual = check_queries(reader, spec['proof_directory'], spec['assertions'])
    # The source relation concerns these production files, not every file or
    # every module of the FPGA image. Exact source bytes, not a count, bind it.
    need(type(spec['production_sources']) is dict and len(spec['production_sources']) == 6,
         'Exact six-file attention source association required')
    for relative, original in spec['production_sources'].items():
        need(relative in native_inputs and relative in plan['actual_production'], 'Proof/native source omitted')
        row = plan['actual_production'][relative]
        raw = reader.read(row['path'], row)
        need(row['path'] == original and identity(raw) == {k: native_inputs[relative][k] for k in ('bytes', 'sha256')},
             'Actual proof source differs from selected native source')
    inputs = actual.pop('inputs')
    need(inputs['source_origins'] == {'hardware/' + name: native_inputs[name]['sha256']
         for name in spec['production_sources']} and len(inputs['abstract_children']) == 8, 'Proof source/boundary association differs')
    script = reader.read(child(spec['proof_directory'], 'prove.ys')).decode()
    need(script.splitlines()[0].startswith('read_verilog -formal -sv -nosynthesis -D SYNTHESIS ')
         and 'BOARD1_ATTENTION_COORDINATE_PHASE_CHECK' not in script, 'Proof instrumentation macro/synthesis scope differs')
    need(inputs['files']['attention_monitor.inc.sv']['sha256'] == spec['monitor_sha256'], 'Reviewed monitor source differs')
    audit_pin = completion[spec['audit_field']]
    audit = reader.json(audit_pin['path'], audit_pin)
    need(audit['passed'] is True and audit['assertions'] == actual['assertions']
         and audit['queries_checked'] == actual['queries'] and audit['observers'] == actual['observer']
         and audit['arbitrary_child_replies'] == actual['arbitrary_child_replies']
         and audit['byte_identical_elaboration'] is True and audit['whole_machine_refinement'] is False,
         'Recorded audit differs from rechecked cached proof')
    for name in ('elaborated.json', 'elaborated.il', 'design.smt2'):
        need(reader.read(child(spec['audit_directory'], name)) == reader.read(child(spec['proof_directory'], name)),
             'Cached audit/proof elaboration identity differs')
    if spec['assertions'] == 34:
        need(completion['proof_inputs']['path'] == child(spec['proof_directory'], 'INPUTS.json'),
             'Original34 proof-input path differs')
        reader.read(completion['proof_inputs']['path'], completion['proof_inputs'])
        expected_identity_paths = {child(spec['proof_directory'], name) for name in
            ('prove.ys', 'design.smt2', 'elaborated.json', 'elaborated.il')}
        identity_rows = completion['raw_source_query_identity_files']
        need(len(identity_rows) == 4 and {row['path'] for row in identity_rows} == expected_identity_paths,
             'Exact original34 source/query/observer artifact identities required')
        for row in identity_rows:
            reader.read(row['path'], row)
        need(completion['assertions'] == 34 and completion['queries'] == 72 and completion['unknown_results'] == 0
             and completion['assumptions'] == [] and completion['added_internal_cuts'] == []
             and completion['aggregate_assertion_total'] is None
             and all(completion[key] is False for key in ('whole_machine_claim', 'numerical_attention_claim',
                 'protected_guard_or_cache_claim', 'protected_proof_result_inherited', 'native_or_board_authority'))
             and completion['readonly_observer_selector_bits'] == actual['observer']['selector_bits'] == 6
             and completion['observer_production_signal_hits'] == 0
             and completion['retained_complete_arbitrary_outputs'] == len(actual['arbitrary_child_replies']),
             'Original34 completion count/unknown/source/observer/scientific scope differs')
    if spec['assertions'] == 66:
        fixed = reader.json(completion['audit_shape_fix_plan']['path'], completion['audit_shape_fix_plan'])
        need(len(fixed['all_original_proof_files']) == 234 and completion['all234_solver_source_SMT_query_log_files_unchanged'] is True
             and completion['solver_reexecuted_after_audit_shape_fix'] is False,
             'Preserved initial-proof/audit-only repair epoch differs')
        for name, row in fixed['all_original_proof_files'].items():
            reader.read(child(spec['proof_directory'], name), row)
        for key in ('whole_machine_refinement', 'numerical_attention_theorem', 'concrete_memory_theorem',
                    'guard_cache_SIV_composition_theorem', 'phase_observer_relational_theorem',
                    'model_phase_observer_macro_defined_in_proof', 'aggregate_assertion_total_claimed'):
            need(completion[key] is False, 'Scoped attention proof overclaim')
        need(completion['assertions'] == 66 and completion['queries'] == 136 and completion['unknowns'] == 0
             and completion['retained_abstract_output_count'] == len(actual['arbitrary_child_replies']) == 28,
             'Exact V6 attention scope differs')
    return dict(**actual, cached_queries_rebuilt_and_answers_reparsed=True,
                cached_elaboration_and_source_identity_rechecked=True, fresh_solver_or_elaboration_executed=False,
                whole_machine_refinement=False, numerical_or_concrete_memory_or_composition_theorem=False,
                scope='Scoped actual-source attention controller, with unrestricted child output boundaries; counts are nonadditive.')
