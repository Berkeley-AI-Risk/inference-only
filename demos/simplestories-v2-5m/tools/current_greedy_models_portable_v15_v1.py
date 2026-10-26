"""Portable byte-only validation of recorded greedy model transcripts.

The original scalar full-head algorithms are retained verbatim. Native source,
scientific role files and original provenance are resolved by the caller's
bounded capsule reader; no compiler, model, OpenSSL or original-path IO runs.
"""
import hashlib
import json
from pathlib import PurePosixPath
import re

CAPTURE_CONTRACT_SHA256 = '778cf4bd13e6abef38c3d8bf92267fdd8f00206de332116c9f4e00ce33b311f9'
SOURCE_REFERENCE_SHA256 = 'bc5e2dce531cf10b05590dee483f9f561f5fd8b5bfa82f73022ef93952667897'
GOLDEN_INDEX_SHA256 = 'a66052169a9abc7f6a509413e798d4d61fd2bcb4beac06b1a7dc7d9987f0477b'
FATAL = r'%Error|%Fatal|%Warning-MULTIDRIVEN|Assertion failed|Aborting|GLOBAL_TIMEOUT'
HEALTHY = {'greedy-zero','greedy-stalled','prefix16-zero','prefix16-stalled','prefix32-zero','prefix32-stalled'}
NEGATIVE = {'bad-kv-padding-zero','bad-kv-padding-stalled','active-kv-clear-zero','active-kv-clear-stalled','corrupt-boot','corrupt-runtime'}

def need(ok, message):
    if not ok:
        raise ValueError(message)

def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(',', ':')) + '\n').encode()

def greedy_token(rows):
    """Compare exact signed integer multiples of powers of two; ties choose first."""
    need(len(rows) == 4019, 'Fixed vocabulary required')
    common = min(exponent for _, exponent in rows)
    values = [raw << (exponent - common) for raw, exponent in rows]
    return max(range(len(rows)), key=values.__getitem__)

def check_capture(text, expected):
    rows = []
    ordinal = 0
    opened = False
    results = []
    for line in text.splitlines():
        fields = line.split()
        need(fields, 'Empty transcript line')
        if fields[0] == 'CLEAR':
            need(len(fields) == 1 and not opened, 'CLEAR inside uncommitted head')
        elif fields[0] == 'HEAD':
            need(len(fields) == 2 and not opened and int(fields[1]) == ordinal + 1,
                 'Missing/repeated head ordinal')
            ordinal += 1
            need(ordinal <= len(expected), 'Unexpected head')
            opened = True
            rows = []
        elif fields[0] == 'ROW':
            need(len(fields) == 4 and opened and int(fields[1]) == len(rows) < 4019,
                 'Row order/count changed')
            raw, exponent = int(fields[2]), int(fields[3])
            need(-(1 << 49) <= raw < (1 << 49) and -128 <= exponent < 128,
                 'Invalid arithmetic width')
            rows.append((raw, exponent))
        elif fields[0] == 'PICK':
            need(len(fields) == 3 and opened and int(fields[1]) == ordinal and len(rows) == 4019,
                 'Incomplete committed head')
            want = expected[ordinal - 1]
            digest = hashlib.sha256(canonical(rows)).hexdigest()
            need(digest == want['head_rows_sha256'], 'Exact scalar-model logit rows differ')
            token = greedy_token(rows)
            need(int(fields[2]) == token == want['token'], 'Exact greedy token/tie differs')
            results.append(dict(head=ordinal, token=token, head_rows_sha256=digest))
            opened = False
            rows = []
        else:
            raise ValueError('Unexpected greedy transcript record: ' + fields[0])
    need(not opened and len(results) == len(expected), 'Missing numerical head')
    return dict(passed=True, heads=len(results), head_rows_compared=4019 * len(results),
                results=results)


def identity(raw):
    return dict(bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest())


def equal_pin(row, raw):
    return {key: row[key] for key in ('bytes', 'sha256')} == identity(raw)


def references(reader, spec):
    need(set(spec) == {'source', 'index', 'a', 'b'}, 'Complete independent greedy reference inputs required')
    source = reader.read(spec['source'])
    index_raw = reader.read(spec['index'])
    need(identity(source)['sha256'] == SOURCE_REFERENCE_SHA256
         and identity(index_raw)['sha256'] == GOLDEN_INDEX_SHA256, 'Original scalar reference/index differs')
    index = json.loads(index_raw)
    results = []
    for suffix in ('a', 'b'):
        raw = reader.read(spec[suffix])
        name = 'around128-t0-seed-' + suffix + '.json'
        need(index['files'][name] == identity(raw), 'Original independent T0 golden differs')
        results.append(json.loads(raw))
    need(results[0]['generated_tokens'] == results[1]['generated_tokens']
         and results[0]['head_rows_sha256'] == results[1]['head_rows_sha256'], 'T0 seed independence changed')
    return results[0]


def plans_from_golden(gold):
    def head(index):
        return dict(token=gold['generated_tokens'][index], head_rows_sha256=gold['head_rows_sha256'][index])
    cases = {}
    around = [head(index) for index in range(4)] + [head(0)]
    for name, extra in [('greedy-zero', ['+ZERO_STALL']), ('greedy-stalled', [])]:
        cases[name] = dict(flags=['+PROFILE_CASE=0', *extra], heads=around,
            pass_marker='PASS selective_reads_model case=0', kind='positive')
    for length in (16, 32):
        for schedule, extra in [('zero', ['+ZERO_STALL']), ('stalled', [])]:
            cases[f'prefix{length}-{schedule}'] = dict(flags=[f'+INTEGRATION_PREFIX={length}', *extra],
                heads=[head(index) for index in (length - 1, length, 0)],
                pass_marker=f'PASS long_context_integration_prefill prompt={length}',
                kind='positive', prompt_tokens=[378] + gold['generated_tokens'][:length - 1])
    for name, flag, mode in [('corrupt-boot', '+CORRUPT_BOOT', 'boot_corruption'),
                             ('corrupt-runtime', '+CORRUPT_RUNTIME', 'post_boot_corruption')]:
        cases[name] = dict(flags=['+ZERO_STALL', flag, '+PROFILE_CASE=0'], heads=[],
            kind='negative', pass_marker='PASS booted_semantic_negative mode=' + mode)
    for schedule, extra in [('zero', ['+ZERO_STALL']), ('stalled', [])]:
        cases[f'active-kv-clear-{schedule}'] = dict(flags=['+INTEGRATION_CLEAR_KV', *extra],
            heads=[head(index) for index in (0, 1, 0)], kind='ownership',
            pass_marker='PASS long_context_integration_kv_clear')
        cases[f'bad-kv-padding-{schedule}'] = dict(flags=['+INTEGRATION_BAD_KV_PADDING', *extra],
            heads=[head(0)], kind='negative', pass_marker='PASS long_context_integration_bad_kv_padding')
    need(set(cases) == HEALTHY | NEGATIVE and sum(len(row['heads']) for row in cases.values()) == 30,
         'Exact original finite case census differs')
    return cases


SUMMARY = re.compile(r'^COORDINATE_PHASE_MONITOR uses=(\d+) coverage=([0-9a-fA-F]+) '
                     r'reset_cycles=(\d+) clear_cycles=(\d+) fault_entries=(\d+) '
                     r'abort_states=([0-9a-fA-F]+) original_updates=25$')
USE = re.compile(r'^COORDINATE_PHASE_USE kind=(\d+) count=(\d+)$')


def phase_log(text, case, protected=True):
    """The frozen 221 parser's exact count, mask and healthy/CLEAR conditions."""
    healthy = case in HEALTHY if protected else not case.startswith('corrupt-')
    rows = [line for line in text.splitlines() if line.startswith('COORDINATE_PHASE_MONITOR')]
    need(len(rows) == 1 and SUMMARY.fullmatch(rows[0]), 'Exactly one canonical coordinate summary required')
    values = SUMMARY.fullmatch(rows[0]).groups()
    uses, coverage, reset, clear, faults, aborted = (
        int(values[0]), int(values[1], 16), int(values[2]), int(values[3]), int(values[4]), int(values[5], 16))
    need(coverage & ~0x7fff == 0, 'Unknown coordinate coverage bit')
    counts = {}
    for line in text.splitlines():
        if not line.startswith('COORDINATE_PHASE_USE'):
            continue
        match = USE.fullmatch(line)
        need(match is not None, 'Malformed coordinate-use record')
        kind, count = map(int, match.groups())
        need(0 <= kind < 15 and kind not in counts, 'Duplicate/unknown coordinate-use kind')
        counts[kind] = count
    need(set(counts) == set(range(15)), 'All15 coordinate-use records required')
    need(coverage == sum(1 << kind for kind, count in counts.items() if count > 0), 'Coverage/count mismatch')
    need(all(count <= uses for count in counts.values()) and uses <= sum(counts.values()) <= 15 * uses,
         'Coordinate use totals differ')
    if healthy:
        need(coverage == 0x7fff and uses > 0 and reset > 0 and clear > 0
             and all(count > 0 for count in counts.values()), 'Healthy coordinate/CLEAR coverage incomplete')
    result = dict(summary_uses=uses, coverage_mask=coverage, reset_cycles=reset, clear_cycles=clear,
        fault_entries=faults, abort_states_mask=aborted, original_updates=25,
        per_kind_counts={str(kind): counts[kind] for kind in range(15)},
        all15_use_and_CLEAR_coverage_required=healthy, attention_abort_coverage_required=False)
    if protected:
        result.update(case=case, healthy_full_use_and_CLEAR_required=healthy,
                      negative_actual_phase_coverage_reported_without_attention_abort_claim=not healthy)
    else:
        result['boot_corruption_attention_coverage_not_claimed'] = not healthy
    return result


def parse_case_bytes(stdout, capture, plan, kind_major):
    need(any(line.startswith(plan['pass_marker']) for line in stdout.splitlines()), 'Finite case marker missing')
    need(re.search(FATAL, stdout) is None, 'Fatal model output')
    numerical = check_capture(capture.decode(), plan['heads'])
    lines = [line for line in stdout.splitlines() if line.startswith('INTEGRATION_KV_MONITOR ')]
    need(len(lines) == 1, 'Exactly one independent ownership monitor required')
    owner = {key: int(value) for key, value in re.findall(r'(\w+)=(\d+)', lines[0])}
    need(owner['independently_owned'] == 1 and owner['kind_major'] == int(kind_major), 'Actual layout/ownership differs')
    retained = owner['accepted'] - owner['returned']
    semantic = owner['semantic_accepted'] - owner['semantic_replies']
    need(retained == owner['retained_terminal_reads'] and 0 <= retained <= 8, 'K/V ownership mismatch')
    need(semantic == owner['semantic_retained'] and semantic in (0, 1), 'Semantic ownership mismatch')
    if retained or semantic or owner['retained_terminal_writes']:
        need(plan['kind'] == 'negative' and owner['terminal_closed'] == 1, 'Healthy case retained work')
    return dict(passed=True, numerical=numerical, ownership=owner,
                capture=identity(capture), pass_marker=plan['pass_marker'])


def check_compile(reader, files, metadata, require_phase):
    need(set(files) == {'result', 'stdout', 'stderr'}, 'Actual compile artifact origins required')
    compiled = reader.json(files['result'])
    for name in ('stdout', 'stderr'):
        raw = reader.read(files[name], compiled[name])
        need(re.search(FATAL, raw.decode()) is None, 'Fatal compiler log')
    need(compiled['exit_code'] == 0 and compiled['timed_out'] is False and not compiled['fatal_lines'], 'Failed model compile')
    argv = compiled['argv']
    obj = str(PurePosixPath(files['result']).parent / 'obj')
    expected = [argv[0], '--binary', '--build-jobs', '4', '-MAKEFLAGS',
        'CURDIR=' + obj + ' OPT_FAST=-O3 OPT_SLOW=-O3', '--timing', '-Wall', '-Wno-fatal',
        '-Wno-DECLFILENAME', '-Wno-TIMESCALEMOD', '-Wno-WIDTHEXPAND', '-Wno-WIDTHTRUNC',
        '-Wno-UNUSEDSIGNAL', '-Wno-UNUSEDPARAM', '-Wno-SYNCASYNCNET', '-Wno-BLKSEQ',
        '-Wno-VARHIDDEN', '-Wno-PINCONNECTEMPTY', '-Wno-PROCASSINIT', '-DSYNTHESIS']
    if require_phase:
        expected += ['-DBOARD1_ATTENTION_COORDINATE_PHASE_CHECK']
    expected += ['-GAUTH_BANKS=4', '--top-module', 'tb_board1_booted_shared_semantic',
        '--Mdir', obj, '-f', 'production_sources.f', *metadata['reference_sources'], 'tb.sv',
        '-CFLAGS', '-O3 -std=c++17']
    need(type(argv) is list and argv == expected, 'Actual full model compile recipe/macro differs')
    need(metadata['auth_banks'] == 4 and len(metadata['reference_sources']) == 5, 'Actual model scope differs')
    return compiled


def _validate_greedy_models(variant, reader, completion, spec, protected_v7=False, protected_v8=False, protected_v9=False, protected_v15=False):
    """Validate baseline24 or a typed protected fresh12 plus exact old12 controls."""
    need(variant in ('baseline', 'kv-protected'), 'Greedy full-row adapter supports baseline/protected only')
    metadata = reader.json(spec['metadata'])
    plans = plans_from_golden(references(reader, spec['goldens']))
    need(metadata['schema'] == 'greedy-speed-paired-model-packet-v1' and metadata['cases'] == plans
         and metadata['flavors'] == ['control', 'optimized'], 'Actual case/reference packet differs')
    need(len(metadata['production_compile_order']) == len(set(metadata['production_compile_order'])) == (64 if variant == 'baseline' else 66), 'Production model count differs')
    need(set(spec['packet_files']) == set(metadata['files']), 'Complete actual packet snapshot required')
    for name, wanted in metadata['files'].items():
        reader.read(spec['packet_files'][name], wanted)
    for flavor in ('control', 'optimized'):
        name = flavor + '/production_sources.f'
        need(reader.read(spec['packet_files'][name]) == ('\n'.join(metadata['production_compile_order']) + '\n').encode(),
             'Actual model compiler list differs from complete metadata production order')
    raw = reader.json(spec['raw_result'])
    need(raw['passed'] is True and raw['complete'] is True and raw['all_expected_cases_passed'] is True
         and raw['original_sources_and_packet_unchanged'] is True
         and equal_pin(raw['assembled'], reader.read(spec['metadata'])), 'Closed model/packet association differs')
    if variant == 'baseline':
        need(raw == completion and raw['schema'] == 'greedy-speed-paired-model-result-v1'
             and (raw['case_count'], raw['heads'], raw['head_rows_compared']) == (24, 60, 241140), 'Baseline full24 scope differs')
    else:
        need(raw['schema'] == ('greedy-speed-candidate-only-model-result-v15-compact-prefix' if protected_v15 else ('greedy-speed-candidate-only-model-result-v9-dense-sha' if protected_v9 else ('greedy-speed-candidate-only-model-result-v8-sha-direct-add' if protected_v8 else ('greedy-speed-candidate-only-model-result-v7-projection-fourway' if protected_v7 else 'greedy-speed-candidate-only-model-result-v6-four-lane-coordinate'))))
             and (raw['case_count'], raw['heads'], raw['head_rows_compared']) == (12, 30, 120570)
             and completion['schema'] == ('protected-cache-compact-prefix-paired-model-join-v15' if protected_v15 else ('protected-dense-sha-paired-model-join-v9' if protected_v9 else ('protected-sha-direct-add-paired-model-join-v8' if protected_v8 else ('protected-projection-fourway-paired-model-join-v7' if protected_v7 else 'protected-four-lane-coordinate-paired-model-join-v6'))))
             and (completion['new_candidate_cases_executed'], completion['old_control_cases_reused'],
                  completion['paired_cases_covered'], completion['paired_heads'], completion['paired_head_rows']) == (12, 12, 24, 60, 241140)
             and equal_pin(completion['candidate_result'], reader.read(spec['raw_result']))
             and equal_pin(completion['selected_packet'], reader.read(spec['metadata'])), 'Protected fresh/control association differs')
        old = reader.json(spec['control_metadata'], completion['old_control_packet'])
        need({n: p for n, p in old['files'].items() if n.startswith('control/')} ==
             {n: p for n, p in metadata['files'].items() if n.startswith('control/')} and old['cases'] == plans,
             'Reused control packet bytes or plans changed')
    need(set(spec['case_files']) == {flavor + '/' + name for flavor in ('control', 'optimized') for name in plans}, 'Exact24 raw case artifact sets required')
    for flavor in ('control', 'optimized'):
        compiled = check_compile(reader, spec['compile'][flavor], metadata, variant == 'kv-protected' and flavor == 'optimized')
        if flavor in raw['builds']:
            need(compiled == raw['builds'][flavor], 'Raw compile result differs')
    heads = rows = healthy = 0
    for name, files in spec['case_files'].items():
        flavor, label = name.split('/', 1)
        need(set(files) == {'execution', 'stdout', 'stderr', 'capture'}, 'Exact raw case artifact roles required')
        execution = reader.json(files['execution'])
        stdout = reader.read(files['stdout'], execution['stdout']).decode()
        stderr = reader.read(files['stderr'], execution['stderr']).decode()
        capture = reader.read(files['capture'])
        need(execution['exit_code'] == 0 and execution['timed_out'] is False and not execution['fatal_lines']
             and re.search(FATAL, stdout + '\n' + stderr) is None, 'Failed/fatal actual model case')
        major = metadata['candidate_kind_major'] if flavor == 'optimized' else metadata['control_kind_major']
        checked = parse_case_bytes(stdout, capture, plans[label], major)
        actual = raw['cases'][name] if name in raw['cases'] else completion['control_cases'][label]
        for field, value in checked.items():
            need(actual[field] == value, 'Raw numerical/ownership result differs: ' + name + '/' + field)
        if name in raw['cases']:
            need(actual['execution'] == execution, 'Raw case execution record differs')
        else:
            closed = completion['closed_control_receipts'][label]
            need(equal_pin(closed['execution'], reader.read(files['execution'])) and closed['capture'] == identity(capture),
                 'Reused control terminal receipt/capture differs')
        argv = execution['argv']
        need(argv[0] == str(PurePosixPath(spec['compile'][flavor]['result']).parent / 'obj/Vtb_board1_booted_shared_semantic'), 'Actual case executable origin differs')
        flags = list(plans[label]['flags'])
        if label.startswith('active-kv-clear'):
            flags += ['+EXPECTED_KV_OUTSTANDING=' + ('2' if major else '1')]
        need(argv[1:] == ['+IMAGE_MEMH=image.memh', '+GREEDY_LOG=' + files['capture'], *flags], 'Actual case argv/flags/capture origin differs')
        if variant == 'kv-protected' and flavor == 'optimized':
            phase = phase_log(stdout, label)
            need(phase == actual['coordinate_phase_observer'] == completion['candidate_phase_cases'][label], 'Raw actual phase rows differ')
            if not protected_v15:
                scope = actual['four_lane_checker']
                witness = label in HEALTHY and all(phase['per_kind_counts'][str(k)] > 0 for k in (10, 11, 14))
                need(scope['source'] == completion['four_lane_checker'] and scope['enabled_by_candidate_macro'] is True
                     and scope['fatal_assertions_enforced'] is True and scope['healthy_score_and_PV_use_witness'] is witness
                     and scope['negative_half_branch_coverage_claimed'] is False and scope['separate_half_counts_observed'] is False,
                     'Four-lane checker scope/witness differs')
            healthy += int(label in HEALTHY)
        heads += checked['numerical']['heads']
        rows += checked['numerical']['head_rows_compared']
    need((heads, rows) == (60, 241140), 'Complete full-row numerical census differs')
    if variant == 'kv-protected':
        if protected_v15:
            for item in(completion,raw):
                need(item['all_healthy_cases_have_all15_use_and_CLEAR_coverage']is True
                    and item['healthy_phase_case_count']==6 and item['prior_V14_candidate_results_reused']is False
                    and item['negative_cases_report_actual_phase_coverage_without_abort_claim']is True,
                    'Fresh eight-lane phase-only coverage and no prior candidate reuse required')
        else:
            for item in (completion, raw):
                need(item['all_healthy_cases_have_all15_use_and_CLEAR_coverage'] is True and item['healthy_phase_case_count'] == 6
                     and item['all_candidate_models_enable_four_lane_checker'] is True
                     and item['all_healthy_cases_have_score_and_PV_use_witness'] is True
                     and item['negative_four_lane_branch_coverage_claimed'] is False and item['prior_V8_candidate_results_reused' if protected_v9 else ('prior_V7_candidate_results_reused' if protected_v8 else ('prior_V6_candidate_results_reused' if protected_v7 else 'prior_V5_candidate_results_reused'))] is False,
                     'Declared protected source epoch differs from actual full-case replay')
        need(healthy == 6, 'Six healthy protected phase cases required')
    return dict(passed=True, actual_case_artifacts=24, fresh_candidate_cases=12, control_cases=12,
                full_vocabulary_heads=heads, exact_head_rows=rows, all_raw_numerical_and_ownership_reparsed=True,
                phase_healthy_cases=healthy, no_model_or_compiler_executed=True,
                whole_machine_refinement=False, native_or_board_authority=False)


ENCRYPTED_CASE_PINS = {
    'around': 'c7f55ba151733b9f1e1c324cef38c30d8a4d1ae16472dd098571861b3fd93b0f',
    'fox': '35ac2d47dde50a038881b2eff3a27a909a990afd593559f1bf20aa2d120ca089',
    'help': 'b3954bbe040783fbc7b730fae8f181f95a0000d7a9435233575a1c24962da668',
}
ENCRYPTED_CASES = {'around-zero', 'around-stalled', 'fox-zero', 'help-zero', 'corrupt-boot', 'corrupt-runtime'}
SEMANTIC = re.compile(r'^SEMANTIC_STEP banks=(\d+) zero_stall=(\d+) ordinal=(\d+) token=(\d+) '
                      r'core_cycles=(\d+) tape=(\d+) prefixes=([0-9a-fA-F]+)$')


def encrypted_reference(raw, family):
    need(identity(raw)['sha256'] == ENCRYPTED_CASE_PINS[family], 'Frozen independent encrypted-case reference differs')
    values = [int(line) for line in raw.decode().splitlines()]
    need(len(values) >= 3, 'Encrypted case reference truncated')
    prompt, generated, replay = values[:3]
    need(1 <= prompt <= 32 and 1 <= generated <= 4 and 1 <= replay <= generated
         and len(values) == 3 + prompt + generated + replay
         and all(0 <= token < 4019 for token in values[3:]), 'Encrypted case reference shape/bounds differ')
    return dict(prompt=values[3:3 + prompt], generated=values[3 + prompt:3 + prompt + generated],
                replay=values[3 + prompt + generated:])



ENCRYPTED_FATAL = r'%Error|%Fatal|%Warning|Assertion failed|Aborting|GLOBAL_TIMEOUT'
ENCRYPTED_DRIVERS = {
    'control': '601ebaf70eda6528988ac952d44963349152d92b782768aae601c5330841bda7',
    'candidate': '9f30aeaa98843f065f4cf04ef70828224fd47345584bbc1a9b2b7a0e0f4a6134',
}


def encrypted_original_check_log(text, code, case, plan):
    # Same acceptance body as the original driver; names only separate its
    # all-warning predicate from the greedy full-head driver's predicate.
    if code or re.search(ENCRYPTED_FATAL,text): return False
    steps=[dict(re.findall(r'(\w+)=([^ ]+)',line)) for line in text.splitlines() if line.startswith('SEMANTIC_STEP ')]
    passed=[line for line in text.splitlines() if line.startswith('PASS ')]
    boots=[line for line in text.splitlines() if line.startswith('BOOT_AUTHENTICATED ')]
    if len(passed)!=1: return False
    if case in ('corrupt-boot','corrupt-runtime'):
        expected=('PASS booted_semantic_negative mode=boot_corruption fixed_words=227062 public_tokens=0 actual_boot_sha=1'
                  if case=='corrupt-boot' else 'PASS booted_semantic_negative mode=post_boot_corruption fixed_words=227062 public_tokens=0 actual_boot_sha=1 live_page_sha=1')
        return passed==[expected] and not steps and len(boots)==int(case=='corrupt-runtime')
    label=case.split('-')[0];p=plan[label]
    tokens=p['generated_tokens']+p['replay_tokens']
    if len(boots)!=1 or len(steps)!=len(tokens): return False
    for i,(step,expected) in enumerate(zip(steps,tokens)):
        if int(step['token'])!=expected or int(step['ordinal'])!=i+1 or int(step['banks'])!=4 or int(step['core_cycles'])<=0:
            return False
    counts={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',passed[0])}
    return (passed[0].startswith('PASS confidential_system ') and counts['prompt']==len(p['prompt_tokens'])
            and counts['outputs']==len(p['generated_tokens']) and counts['replay']==len(p['replay_tokens'])
            and counts['actual_ciphertext_boot']==1 and counts['boot_words']==227062
            and counts['model_reads']>0 and counts['kv_reads']>0 and counts['kv_writes']>0)


def encrypted_check_log(text, code, case, plan):
    if not encrypted_original_check_log(text,code,case,plan):return False
    records=[s for s in text.splitlines() if s.startswith('KV_CIPHERTEXT_ORACLE ')]
    if case.startswith('corrupt'):return not records
    label=case.split('-')[0];p=plan[label]
    positions=2*len(p['prompt_tokens'])+len(p['generated_tokens'])+len(p['replay_tokens'])-2
    expected=f'KV_CIPHERTEXT_ORACLE logical_words={positions*108} cipher_words={positions*120} epochs=2 native_openssl=1 guard_plaintext_sha=1'
    return records==[expected]


def encrypted_suite(reader, spec, *, candidate):
    """Reparse one actual encrypted suite, including every source snapshot."""
    metadata = reader.json(spec['metadata'])
    raw = reader.json(spec['raw_result'])
    need(raw['schema'] == ('tang-encrypted-coordinate-v5-model-tests-v1' if candidate else
                          'tang-encrypted-attention-model-tests-v1') and raw['passed'] is True
         and raw['full_initial_suite'] is True and raw['failures'] == []
         and raw['source_identities_rechecked'] is True and raw['hardware_context_positions'] == 2048
         and raw['auth_banks'] == 4 and raw['candidate_manifest_sha256'] == identity(reader.read(spec['metadata']))['sha256'],
         'Closed encrypted six-case source/geometry receipt required')
    need(len(metadata['files']) == 166 and len(metadata['compile_order']) == 71
         and set(spec['packet_files']) == set(metadata['files']), 'Complete166/71 encrypted packet required')
    for name, wanted in metadata['files'].items():
        need(identity(reader.read(spec['packet_files'][name]))['sha256'] == wanted, 'Encrypted packet file differs: ' + name)
    need(reader.read(spec['packet_files']['production_sources.f']) == ('\n'.join(metadata['compile_order']) + '\n').encode()
         and len(set(metadata['compile_order'])) == 71 and set(metadata['native_source_mapping']) == set(metadata['compile_order'])
         and len(set(metadata['native_source_mapping'].values())) == 71,
         'Actual encrypted .f/order/production mapping differs')
    need(set(spec['snapshots']) == set(raw['sources']), 'Every actual run snapshot required')
    for name, wanted in raw['sources'].items():
        need(identity(reader.read(spec['snapshots'][name]))['sha256'] == wanted, 'Encrypted execution snapshot differs: ' + name)
    refs = {family: encrypted_reference(reader.read(spec['references'][family]), family) for family in ENCRYPTED_CASE_PINS}
    plan = {family: {'prompt_tokens': row['prompt'], 'generated_tokens': row['generated'], 'replay_tokens': row['replay']}
            for family, row in refs.items()}
    need(set(raw['tests']) == set(spec['logs']) == ENCRYPTED_CASES, 'Exact encrypted six-case set required')
    need(raw['runner_sha256'] == ENCRYPTED_DRIVERS['candidate' if candidate else 'control']
         and identity(reader.read(spec['driver']))['sha256'] == raw['runner_sha256'], 'Encrypted acceptance driver differs')
    macro = '-DBOARD1_ATTENTION_COORDINATE_PHASE_CHECK'
    argv = raw['build']['command']
    need(raw['build']['exit_code'] == 0 and argv.count(macro) == int(candidate)
         and argv.count('-GAUTH_BANKS=4') == 1 and argv.count('simulation_defines.vh') == 1
         and reader.read(spec['snapshots']['simulation_defines.vh']) == b'`define SYNTHESIS 1\n',
         'Encrypted actual synthesis/model-only phase compile recipe differs')
    # SYNTHESIS is in this pinned header, not a command-line -DSYNTHESIS flag.
    need(identity(reader.read(spec['binary']))['sha256'] == raw['build']['binary_sha256'], 'Compiled simulation binary differs')
    for key in ('build', 'reference', 'kv_reference'):
        log = reader.read(spec[key + '_log'])
        need(raw[key]['exit_code'] == 0 and identity(log)['sha256'] == raw[key]['log_sha256'],
             'Actual encrypted build/integer/OpenSSL execution log differs')
        if key == 'build':
            need(re.search(ENCRYPTED_FATAL, log.decode()) is None, 'Encrypted compiler failed/warned')
    reference_lines = [json.loads(line[len('PASS_REFERENCE '):]) for line in reader.read(spec['reference_log']).decode().splitlines()
                       if line.startswith('PASS_REFERENCE ')]
    need(reference_lines == [dict(case=family, **row) for family, row in plan.items()], 'Actual independent integer-reference output differs')
    total = healthy = 0
    cases = {}
    for case, row in raw['tests'].items():
        log_bytes = reader.read(spec['logs'][case])
        text = log_bytes.decode()
        need(row['exit_code'] == 0 and row['passed'] is True and identity(log_bytes)['sha256'] == row['log_sha256']
             and encrypted_check_log(text, row['exit_code'], case, plan), 'Original encrypted numerical/oracle acceptance failed')
        marker_prefixes = ('BOOT_AUTHENTICATED ', 'SEMANTIC_STEP ', 'PASS ', 'KV_CIPHERTEXT_ORACLE ')
        if candidate:
            marker_prefixes += ('COORDINATE_PHASE_MONITOR ', 'COORDINATE_PHASE_USE ')
        markers = [line for line in text.splitlines() if line.startswith(marker_prefixes)]
        need(markers == row['markers'], 'Actual encrypted marker records differ')
        phase = phase_log(text, case, protected=False) if candidate else None
        if candidate:
            need(phase == row['coordinate_phase_observer'], 'Actual encrypted phase rows differ')
        flags = [] if case == 'around-stalled' else ['+ZERO_STALL']
        if case.startswith('corrupt-'):
            flags += ['+CORRUPT_BOOT' if case == 'corrupt-boot' else '+CORRUPT_RUNTIME']
        elif candidate:
            flags += ['+COORDINATE_PHASE_REQUIRE_COVERAGE', '+COORDINATE_PHASE_REQUIRE_CLEAR']
        family = 'around' if case.startswith('corrupt-') else case.split('-', 1)[0]
        need(row['command'] == [spec['binary'], '+IMAGE_MEMH=plaintext.memh', '+CIPHER_MEMH=ciphertext.memh',
             '+CASE=' + family + '.txt', '+KV_PLAIN_ORACLE=' + family + '-kv-plain.txt',
             '+KV_CIPHER_ORACLE=' + family + '-kv-cipher.txt', *flags], 'Actual encrypted case argv differs')
        observed = []
        for line in text.splitlines():
            if not line.startswith('SEMANTIC_STEP'):
                continue
            match = SEMANTIC.fullmatch(line)
            need(match is not None, 'Malformed encrypted semantic output record')
            banks, zero, ordinal, token, cycles, tape, prefixes = match.groups()
            need(int(banks) == 4 and int(zero) == int(case.endswith('-zero'))
                 and int(ordinal) == len(observed) + 1 and int(cycles) > 0 and 0 <= int(token) < 4019,
                 'Encrypted output order/schedule/bounds differ')
            observed.append(int(token))
        if not case.startswith('corrupt-'):
            need(observed == refs[family]['generated'] + refs[family]['replay'], 'Exact independent encrypted token/replay window differs')
            healthy += 1
        total += len(observed)
        cases[case] = dict(outputs=observed, phase=phase, markers=markers)
    need((healthy, total) == (4, 18), 'Full encrypted healthy/token census differs')
    need(raw['real_ciphertext_boot'] is True and raw['boot_bypassed'] is False
         and raw['physical_spi_tested'] is False and raw['vendor_phy_tested'] is False
         and raw['real_secret_provisioned'] is False and raw['board_ready'] is False,
         'Encrypted model/physical scope differs')
    return raw, metadata, cases


def validate_encrypted_models(reader, completion, spec):
    need(completion['schema'] == 'encrypted-memory-selected-v5-coordinate-model-completion-v1'
         and completion['passed'] is True and completion['full_six_case_candidate_suite_passed'] is True
         and completion['original_six_case_control_results_reused_without_relabeling'] is True,
         'Encrypted fresh/control model completion required')
    before, old, control = encrypted_suite(reader, spec['control'], candidate=False)
    after, new, candidate = encrypted_suite(reader, spec['candidate'], candidate=True)
    need(equal_pin(completion['candidate_receipt'], reader.read(spec['candidate']['raw_result']))
         and equal_pin(completion['original_control_receipt'], reader.read(spec['control']['raw_result'])),
         'Original six-case receipt or fresh candidate receipt differs')
    join = reader.json(completion['control_join']['path'], completion['control_join'])
    mirror = reader.json(spec['control_mirror_metadata'])
    need(join['schema'] == 'encrypted-attention-v5-coordinate-reused-published-control-input-join-v1'
         and old['files'] == mirror['files'] == join['input_file_sha256'] and len(old['files']) == 166
         and identity(reader.read(spec['control']['metadata']))['sha256'] == join['v1_parent_manifest_sha256']
         and identity(reader.read(spec['control_mirror_metadata']))['sha256'] == join['v5_coordinate_parent_manifest_sha256']
         and set(spec['control_mirror_files']) == set(old['files']), 'Reused166-file control metadata join differs')
    for name, wanted in old['files'].items():
        need(identity(reader.read(spec['control_mirror_files'][name]))['sha256'] == wanted, 'Control mirror input bytes differ')
    for key in ('compile_order', 'reference_sources', 'simulation_only_sources', 'layers', 'context_positions',
                'auth_banks', 'required_test_auth_banks', 'native_source_mapping'):
        need(old[key] == mirror[key], 'Control geometry changed: ' + key)
    need(before['build']['command'] == [arg for arg in after['build']['command']
         if arg != '-DBOARD1_ATTENTION_COORDINATE_PHASE_CHECK'], 'Compiler command differs beyond candidate observer macro')
    for case in ENCRYPTED_CASES:
        a, b = control[case], candidate[case]
        need(a['outputs'] == b['outputs'], 'Original/fresh exact token window differs')
        oracle = lambda rows: [line for line in rows if line.startswith('KV_CIPHERTEXT_ORACLE ')]
        need(oracle(a['markers']) == oracle(b['markers']), 'Original/fresh exact ciphertext-oracle work differs')
        pa = [line for line in a['markers'] if line.startswith('PASS ')]
        pb = [line for line in b['markers'] if line.startswith('PASS ')]
        if case.startswith('corrupt-'):
            need(pa == pb, 'Original/fresh corruption refusal differs')
        else:
            ca, cb = [{key: int(value) for key, value in re.findall(r'(\w+)=(\d+)', lines[0])} for lines in (pa, pb)]
            stable = {'prompt', 'outputs', 'replay', 'actual_ciphertext_boot', 'boot_words', 'model_reads', 'kv_writes'}
            need(set(ca) == set(cb) == stable | {'kv_reads', 'core_cycles'} and all(ca[key] == cb[key] for key in stable),
                 'Unchanged model/boot/write work differs')
    for key in ('native_image_qualified', 'board_speed_measured', 'physical_security_qualified',
                'whole_machine_proved', 'source_proof_claimed_by_model_record', 'full_context_workload_tested'):
        need(completion[key] is False, 'Finite model completion scope overclaim')
    need(completion['all_four_healthy_cases_have_all15_use_and_CLEAR_coverage'] is True
         and completion['negative_cases_report_actual_phase_coverage_without_abort_claim'] is True,
         'Actual encrypted phase scope differs')
    return dict(passed=True, actual_candidate_cases=6, original_control_cases=6, healthy_cases_per_suite=4,
                exact_generated_and_replay_tokens_per_suite=18, cases=candidate,
                all166_control_and_mirror_inputs_rehashed=True, all_snapshot_sources_and_binaries_rehashed=True,
                integer_and_OpenSSL_execution_logs_rechecked=True, integer_or_OpenSSL_or_model_reexecuted=False,
                full_context_or_native_or_board_authority=False)


# Explicit legacy entry point: V7 cannot enter by changing supplied records.
def validate_greedy_models(variant, reader, completion, spec):
    return _validate_greedy_models(variant, reader, completion, spec, protected_v7=False)


V7_IDENTITIES = {
    'candidate': (73961, '82e0d1fc4b4cfcfb0c7b74d5557a5e3ee7d8fe0291c570bb7fd397da9bc68b4e'),
    'completion': (35708, '2ce930ce30c0a1daa254e02fc570f638931b256f9de0fb801a70f4fca6950032'),
    'raw': (54873, '6e2aa4ceed98fa597c6e2b5fba662d1477e866ffaaf47fcc210dd0d50afdb735'),
    'metadata': (168983, '3560d618378de8795f7ba5bd1b4d3c2f2d849c0cad5c52806416cf6ceecece54'),
    'finite': (3187, '581580bf67e9af0ed2921e90a3180b837f0f375c9747f622fedd29499cb2f46c'),
    'bridge': (19110, '93199183dde6c247cf9284d37d51e0d2f59bf1d82f401a7ec139b57b78ff9c80'),
    'engine': (12710, 'd329b95e9208694cbe224e6218b646adf5ba7ffeb1ba76022c2259aa26e21829'),
    'tile': (7717, 'abf9a54465be769f37f6ed06499749db7a4bf03fcc7f8ea996aef602efa98d63'),
}

def v7_identity(raw, name):
    size, sha = V7_IDENTITIES[name]
    need(identity(raw) == dict(bytes=size, sha256=sha), 'Known actual V7 ' + name + ' identity required')
    return json.loads(raw)


def v7_static_scope(candidate, metadata, raw, completion, finite, bridge):
    """Pure recorded-source contract; this function alone is not model replay."""
    need(candidate['schema'] == 'protected-projection-fourway-source-candidate-v7'
         and completion['schema'] == 'protected-projection-fourway-paired-model-join-v7'
         and raw['schema'] == 'greedy-speed-candidate-only-model-result-v7-projection-fourway',
         'No V6 schema relabelling or candidate-result reuse')
    need(raw['passed'] is True and raw['complete'] is True
         and (raw['case_count'],raw['heads'],raw['head_rows_compared']) == (12,30,120570)
         and raw['control_cases_executed_by_this_run'] == 0
         and (completion['new_candidate_cases_executed'],completion['old_control_cases_reused'],
              completion['paired_cases_covered'],completion['paired_heads'],completion['paired_head_rows']) == (12,12,24,60,241140),
         'Actual V7 fresh twelve and original twelve-control scope required')
    need(metadata['schema'] == 'greedy-speed-paired-model-packet-v1'
         and len(metadata['production_compile_order']) == len(set(metadata['production_compile_order'])) == 66
         and {'cluster-engine.sv', 'cluster-tile.sv'} <= set(metadata['production_compile_order'])
         and metadata['control_kind_major'] is metadata['candidate_kind_major'] is False,
         'Actual protected66 compiler entries and unchanged head-major layout required')
    projection=candidate['projection_fourway_sources']
    need(set(projection) == {'engine','tile'}, 'Both exact changed projection sources required')
    for kind, name in [('engine','cluster-engine.sv'),('tile','cluster-tile.sv')]:
        size, sha=V7_IDENTITIES[kind]
        need({k:projection[kind][k] for k in ('bytes','sha256')} == dict(bytes=size,sha256=sha)
             and projection[kind]['path'] == candidate['candidate'] + '/project/' + name
             and metadata['files']['optimized/' + name] == dict(bytes=size,sha256=sha),
             'Actual candidate/model projection bytes differ')
    for item in (metadata,raw,completion,bridge):
        need(item['projection_fourway_sources'] == projection, 'Projection source object differs by role')
    need(metadata['prior_V6_candidate_results_reused'] is False
         and metadata['all_current_projection_production_sources_recompiled'] is False
         and metadata['all_current_projection_production_sources_must_be_recompiled'] is True,
         'Source preparation must not claim execution')
    phase=metadata['coordinate_phase_observer']
    need(candidate['coordinate_phase_observer'] == phase
         and phase['required_model_define'] == 'BOARD1_ATTENTION_COORDINATE_PHASE_CHECK'
         and phase['native_define_added'] is False and phase['candidate_only_model_define_added'] is True
         and phase['model_define_enables_coordinate_phase_and_four_lane_checks'] is True
         and phase['source']['sha256'] == '8bff05ff67e55faa8afcfe7a2204b259c0827c11d4cada8ad5b3ad8e3e82585a'
         and phase['seam']['sha256'] == '91c161f012830a52b136b419310a209081eda9d56c2efb5cf4eb192d0f8eb31d'
         and phase['checks']['sha256'] == '1635e472db5dee1512419954f97ddbce24970dbfd52ca7fed2ad9af4d2ddf635'
         and phase['four_lane_checker']['sha256'] == '67bb334543befc846ecbd8ef06198671de3076cc4a268f5f65263a9a1d1dd6cc',
         'Unchanged V6 attention checker/seam with candidate-only macro required')
    for item in (raw,completion):
        need(item['coordinate_phase_observer'] == phase
             and item['simulation_seam'] == phase['seam'] and item['four_lane_checker'] == phase['four_lane_checker']
             and item['prior_V6_candidate_results_reused'] is False
             and item['all_current_projection_production_sources_recompiled'] is True
             and item['candidate_only_phase_observer_macro'] == phase['required_model_define']
             and item['native_phase_observer_macro_added'] is False
             and item['candidate_parent_compiler_macros_identical'] is False
             and item['projection_finite_source_completion'] == candidate['projection_finite_source_completion'],
             'Fresh exact V7 projection/phase compile scope required')
    need(finite['schema'] == 'protected-projection-fourway-finite-source-completion-v7'
         and finite['passed'] is True and finite['hardware_access'] is False
         and finite['semantic_done_read_after_observed_completion'] is True
         and finite['all16_initialized_payload_and_metadata_rows'] is True
         and finite['distinct_mutants_rejected'] == 9 and finite['whole_machine_claim'] is False,
         'Separate initialized finite projection receipt required')
    need(bridge['schema'] == 'protected-v7-unchanged-v6-attention-control-scope-association-v1'
         and bridge['passed'] is True and bridge['additional_assertions_or_queries_claimed'] == 0
         and bridge['projection_arithmetic_covered_by_this_proof'] is False
         and bridge['solver_or_auditor_executed'] is False and bridge['whole_machine_refinement'] is False,
         'Attention source bridge must not claim projection arithmetic or new proof execution')
    need(completion['whole_old_machine_miter'] is False and completion['native_or_board_authority'] is False,
         'Finite model does not qualify a native image or a whole-machine miter')
    return projection, phase


def validate_protected_v7_models(reader, completion, spec):
    """Exact V7 twelve fresh cases + original twelve controls; callbacks only."""
    need(reader.variant == 'kv-protected', 'V7 protected model variant required')
    origins=reader.data['roles']
    selected=v7_identity(reader.read(origins['model_complete']), 'completion')
    need(selected == completion, 'Completion detached from actual current role')
    candidate=v7_identity(reader.read(origins['source_candidate']), 'candidate')
    metadata=v7_identity(reader.read(spec['metadata']), 'metadata')
    raw=v7_identity(reader.read(spec['raw_result']), 'raw')
    finite_pin=candidate['projection_finite_source_completion']
    finite=v7_identity(reader.read(finite_pin['path'],finite_pin), 'finite')
    bridge=v7_identity(reader.read(spec['attention_bridge']), 'bridge')
    projection,phase=v7_static_scope(candidate,metadata,raw,completion,finite,bridge)
    need(completion['source_candidate'] == reader.pin(origins['source_candidate'])
         and bridge['source_candidate'] == reader.pin(origins['source_candidate'])
         and bridge['projection_finite_source_completion'] == finite_pin,
         'Candidate/model/finite/attention bridge cross-binding differs')
    for kind,name in [('engine','cluster-engine.sv'),('tile','cluster-tile.sv')]:
        reader.read(projection[kind]['path'],projection[kind])
        need(identity(reader.read(spec['packet_files']['optimized/'+name])) ==
             {k:projection[kind][k]for k in ('bytes','sha256')}, 'Actual compiled projection snapshot differs')
    for key in ('source','seam','checks','four_lane_checker'):
        row=phase[key];reader.read(row['path'],row)
    for item in (completion,raw):
        for key,sha in [('runner','7440b328b6728c00a260a356854b00d4d5999d45eaf2faf24c16bbf903b45a2b'),
                        ('phase_gate','421536df542338a7c79cef63cdc877baef1ed7a2747e0fcc78ba807609f54ba7')]:
            row=item[key]
            origin=row['path'] if 'path' in row else completion[key]['path']
            need(row['sha256'] == sha and equal_pin(row,reader.read(origin,row)), 'V7 actual driver/gate source differs')
    result=_validate_greedy_models('kv-protected',reader,completion,spec,protected_v7=True)
    return dict(result, source_epoch='v7-projection-fourway', prior_V6_candidate_results_reused=False,
                actual_projection_sources_recompiled_and_byte_joined=True,
                initialized_projection_finite_receipt_pinned=True,
                unchanged_attention_bridge_pinned_separate_from_model=True,
                source_proof_or_native_or_board_qualification_claimed=False)


V8_IDENTITIES = {'candidate': (71108, 'c0929b466a40c3541d0b5ad797f62430e8802d405ada9afb1b1e23bb0dc43951'), 'completion': (36633, '3f2a23dbce240ea9692f6175ffad4f7e823cf05b325fd1c7c77461e5447e167c'), 'raw': (55706, '4229d0740b75f6bf46e7dc5e406385d1c2053b8b9b7b2bfbaeced8cdd8483ed7'), 'metadata': (169651, '4e69920fd5359da140b2953cd9a84848ac09b9defe05a09bbfb75668dd3088dc'), 'finite': (3187, '581580bf67e9af0ed2921e90a3180b837f0f375c9747f622fedd29499cb2f46c'), 'bridge': (19793, 'e8305992f202e546ac32c630dff6da5c8469da60b8684301b701b8faa535f1a4'), 'sha_finite': (21265, '567a96144bd5e5244e599dae5ea9b4142da298c08cdaa49202e385cd14737f17'), 'sha': (29648, 'a6fc9c042784f9d48731acafcbb3c6366a5746c458fa6aa9abe1aac59c25df92'), 'engine': (12710, 'd329b95e9208694cbe224e6218b646adf5ba7ffeb1ba76022c2259aa26e21829'), 'tile': (7717, 'abf9a54465be769f37f6ed06499749db7a4bf03fcc7f8ea996aef602efa98d63')}

def v8_identity(raw,name):
    size,sha=V8_IDENTITIES[name]
    need(identity(raw)==dict(bytes=size,sha256=sha),'Known actual V8 '+name+' identity required')
    return json.loads(raw)

def pin2_local(row):
    return {k:row[k]for k in ('bytes','sha256')}

def v8_static_scope(candidate, metadata, raw, completion, finite, bridge, sha_finite):
    """Pure recorded-source contract; this function alone is not model replay."""
    need(candidate['schema'] == 'protected-sha-direct-add-source-candidate-v8'
         and completion['schema'] == 'protected-sha-direct-add-paired-model-join-v8'
         and raw['schema'] == 'greedy-speed-candidate-only-model-result-v8-sha-direct-add',
         'No V7 schema relabelling or candidate-result reuse')
    need(raw['passed'] is True and raw['complete'] is True
         and (raw['case_count'],raw['heads'],raw['head_rows_compared']) == (12,30,120570)
         and raw['control_cases_executed_by_this_run'] == 0
         and (completion['new_candidate_cases_executed'],completion['old_control_cases_reused'],
              completion['paired_cases_covered'],completion['paired_heads'],completion['paired_head_rows']) == (12,12,24,60,241140),
         'Actual V8 fresh twelve and original twelve-control scope required')
    need(metadata['schema'] == 'greedy-speed-paired-model-packet-v1'
         and len(metadata['production_compile_order']) == len(set(metadata['production_compile_order'])) == 66
         and {'cluster-engine.sv', 'cluster-tile.sv'} <= set(metadata['production_compile_order'])
         and metadata['control_kind_major'] is metadata['candidate_kind_major'] is False,
         'Actual protected66 compiler entries and unchanged head-major layout required')
    projection=candidate['projection_fourway_sources']
    need(set(projection) == {'engine','tile'}, 'Both exact changed projection sources required')
    for kind, name in [('engine','cluster-engine.sv'),('tile','cluster-tile.sv')]:
        size, sha=V8_IDENTITIES[kind]
        need({k:projection[kind][k] for k in ('bytes','sha256')} == dict(bytes=size,sha256=sha)
             and projection[kind]['path'] == candidate['candidate'] + '/project/' + name
             and metadata['files']['optimized/' + name] == dict(bytes=size,sha256=sha),
             'Actual candidate/model projection bytes differ')
    for item in (metadata,raw,completion,bridge):
        need(item['projection_fourway_sources'] == projection, 'Projection source object differs by role')
    need(metadata['prior_V7_candidate_results_reused'] is False
         and metadata['all_current_projection_production_sources_recompiled'] is False
         and metadata['all_current_projection_production_sources_must_be_recompiled'] is True,
         'Source preparation must not claim execution')
    phase=metadata['coordinate_phase_observer']
    need(candidate['coordinate_phase_observer'] == phase
         and phase['required_model_define'] == 'BOARD1_ATTENTION_COORDINATE_PHASE_CHECK'
         and phase['native_define_added'] is False and phase['candidate_only_model_define_added'] is True
         and phase['model_define_enables_coordinate_phase_and_four_lane_checks'] is True
         and phase['source']['sha256'] == '8bff05ff67e55faa8afcfe7a2204b259c0827c11d4cada8ad5b3ad8e3e82585a'
         and phase['seam']['sha256'] == '91c161f012830a52b136b419310a209081eda9d56c2efb5cf4eb192d0f8eb31d'
         and phase['checks']['sha256'] == '1635e472db5dee1512419954f97ddbce24970dbfd52ca7fed2ad9af4d2ddf635'
         and phase['four_lane_checker']['sha256'] == '67bb334543befc846ecbd8ef06198671de3076cc4a268f5f65263a9a1d1dd6cc',
         'Unchanged V6 attention checker/seam with candidate-only macro required')
    for item in (raw,completion):
        need(item['coordinate_phase_observer'] == phase
             and item['simulation_seam'] == phase['seam'] and item['four_lane_checker'] == phase['four_lane_checker']
             and item['prior_V7_candidate_results_reused'] is False
             and item['all_current_projection_production_sources_recompiled'] is True
             and item['candidate_only_phase_observer_macro'] == phase['required_model_define']
             and item['native_phase_observer_macro_added'] is False
             and item['candidate_parent_compiler_macros_identical'] is False
             and item['projection_finite_source_completion'] == candidate['projection_finite_source_completion'],
             'Fresh exact V8 projection/phase compile scope required')
    need(finite['schema'] == 'protected-projection-fourway-finite-source-completion-v7'
         and finite['passed'] is True and finite['hardware_access'] is False
         and finite['semantic_done_read_after_observed_completion'] is True
         and finite['all16_initialized_payload_and_metadata_rows'] is True
         and finite['distinct_mutants_rejected'] == 9 and finite['whole_machine_claim'] is False,
         'Separate initialized finite projection receipt required')
    need(bridge['schema'] == 'protected-v8-unchanged-v6-attention-control-scope-association-v1'
         and bridge['passed'] is True and bridge['additional_assertions_or_queries_claimed'] == 0
         and bridge['projection_arithmetic_covered_by_this_proof'] is False
         and bridge['solver_or_auditor_executed'] is False and bridge['whole_machine_refinement'] is False,
         'Attention source bridge must not claim projection arithmetic or new proof execution')
    need(completion['whole_old_machine_miter'] is False and completion['native_or_board_authority'] is False,
         'Finite model does not qualify a native image or a whole-machine miter')
    sha_source=candidate['sha_direct_add_source']
    need(pin2_local(sha_source)==dict(bytes=V8_IDENTITIES['sha'][0],sha256=V8_IDENTITIES['sha'][1])
         and sha_source['path']==candidate['candidate']+'/project/sha.sv'
         and 'sha.sv' in metadata['production_compile_order']
         and metadata['files']['optimized/sha.sv']==pin2_local(sha_source)
         and candidate['changed_from_v7']==['project/sha.sv']
         and candidate['all_other_native_input_bytes_unchanged_count']==92
         and candidate['guard_cache_RTL_unchanged']is True
         and candidate['compact_boot_KV_SHA_modules_unchanged']is True
         and candidate['weight_page_SHA_arithmetic_mapping_changed']is True,
         'Exact sole SHA delta and compiled source snapshot required')
    finite_pin=candidate['sha_direct_add_finite_source_completion']
    need(pin2_local(finite_pin)==dict(bytes=V8_IDENTITIES['sha_finite'][0],sha256=V8_IDENTITIES['sha_finite'][1])
         and sha_finite['schema']=='source-only-sha-direct-add-check-result-v8'
         and sha_finite['passed']is True and sha_finite['source_unchanged']is True
         and sha_finite['solver_word_domain_all_32bit_pairs']is True
         and sha_finite['native_primitive_finite_scope_only']is True
         and sha_finite['source_compressor_REGISTER_RESULT']==0
         and sha_finite['hardware_access']is False and sha_finite['native_build']is False
         and sha_finite['full_model']is False and sha_finite['whole_machine_claim']is False,
         'Separately scoped exact R5 source/normalized relation/vendor finite completion required')
    clock=sha_finite['compressor_clock_event_model']
    need(clock['asynchronous_input_negative_holdtime_model']is True
         and clock['explicit_input_assumptions_added']is False
         and clock['physical_async_reset_theorem']is False and clock['metastability_theorem']is False,
         'Normalized binary clock-event and negative-hold scope required')
    macro='Native SYNTHESIS without VERILATOR selects exact DSP helper; fresh Verilator model uses portable modulo32 helper. Primitive finite evidence is separate.'
    need(candidate['sha_model_native_macro_elaboration_identical']is False,
         'Candidate native/model SHA macro branches are distinct')
    for item in (metadata,raw,completion):
        need(item['sha_direct_add_source']==sha_source
             and item['sha_direct_add_finite_source_completion']==finite_pin
             and item['sha_model_native_macro_elaboration_identical']is False
             and item['sha_macro_scope']==macro,'Exact SHA source/finite/macro disclosure differs')
    need(metadata['all_current_SHA_production_source_recompiled']is False
         and metadata['all_current_SHA_production_source_must_be_recompiled']is True
         and all(item['all_current_SHA_production_source_recompiled']is True for item in (raw,completion)),
         'SHA source preparation versus fresh execution flags differ')
    need(bridge['sha_direct_add_source']==sha_source
         and bridge['sha_direct_add_finite_source_completion']==finite_pin
         and bridge['sha_arithmetic_covered_by_this_proof']is False,
         'Attention source association does not prove changed SHA arithmetic')
    return projection, phase


def validate_protected_v8_models(reader, completion, spec):
    """Exact V8 twelve fresh cases + original twelve controls; callbacks only."""
    need(reader.variant == 'kv-protected', 'V8 protected model variant required')
    origins=reader.data['roles']
    selected=v8_identity(reader.read(origins['model_complete']), 'completion')
    need(selected == completion, 'Completion detached from actual current role')
    candidate=v8_identity(reader.read(origins['source_candidate']), 'candidate')
    metadata=v8_identity(reader.read(spec['metadata']), 'metadata')
    raw=v8_identity(reader.read(spec['raw_result']), 'raw')
    finite_pin=candidate['projection_finite_source_completion']
    finite=v8_identity(reader.read(finite_pin['path'],finite_pin), 'finite')
    bridge=v8_identity(reader.read(spec['attention_bridge']), 'bridge')
    sha_pin=candidate['sha_direct_add_finite_source_completion']
    sha_finite=v8_identity(reader.read(sha_pin['path'],sha_pin),'sha_finite')
    projection,phase=v8_static_scope(candidate,metadata,raw,completion,finite,bridge,sha_finite)
    sha_source=candidate['sha_direct_add_source'];reader.read(sha_source['path'],sha_source)
    need(identity(reader.read(spec['packet_files']['optimized/sha.sv']))==pin2_local(sha_source), 'Actual compiled SHA snapshot differs')
    reader.read(sha_finite['plan']['path'],sha_finite['plan'])
    need(sha_finite['plan']['sha256']=='03285601173d51afd305511d0d44453421503f958565fe9629af434d84185554','Exact corrected R5 plan required')
    need(completion['source_candidate'] == reader.pin(origins['source_candidate'])
         and bridge['source_candidate'] == reader.pin(origins['source_candidate'])
         and bridge['projection_finite_source_completion'] == finite_pin,
         'Candidate/model/finite/attention bridge cross-binding differs')
    for kind,name in [('engine','cluster-engine.sv'),('tile','cluster-tile.sv')]:
        reader.read(projection[kind]['path'],projection[kind])
        need(identity(reader.read(spec['packet_files']['optimized/'+name])) ==
             {k:projection[kind][k]for k in ('bytes','sha256')}, 'Actual compiled projection snapshot differs')
    for key in ('source','seam','checks','four_lane_checker'):
        row=phase[key];reader.read(row['path'],row)
    for item in (completion,raw):
        for key,sha in [('runner','deefd6b1b385a33d7eda7bc07b1084499db6643aaab8c228e91f861065818c47'),
                        ('phase_gate','421536df542338a7c79cef63cdc877baef1ed7a2747e0fcc78ba807609f54ba7')]:
            row=item[key]
            origin=row['path'] if 'path' in row else completion[key]['path']
            need(row['sha256'] == sha and equal_pin(row,reader.read(origin,row)), 'V8 actual driver/gate source differs')
    producer=completion['producer'];need(producer['sha256']=='0822b60ca0db8dfa2e8266c177b1d981d0f0a1e0e159c30c84fca6c5e1b507a3' and equal_pin(producer,reader.read(producer['path'],producer)), 'Exact corrected V8 completion producer required')
    result=_validate_greedy_models('kv-protected',reader,completion,spec,protected_v8=True)
    return dict(result, source_epoch='v8-sha-direct-add', prior_V7_candidate_results_reused=False,
                actual_projection_sources_recompiled_and_byte_joined=True,
                initialized_projection_finite_receipt_pinned=True,
                unchanged_attention_bridge_pinned_separate_from_model=True,
                actual_SHA_production_source_recompiled_and_byte_joined=True,
                sha_component_completion_pinned_separately=True,
                sha_model_native_macro_elaboration_identical=False,
                source_proof_or_native_or_board_qualification_claimed=False)


# Actual V9 terminal identities from its fresh twelve-case campaign and once-only original-control join.
V9_IDENTITIES = {'candidate': (71528, 'e2f8ca8e8d0414310ea99272922f3ac11659adfc3c676df9bddec5fcc8c59151'), 'metadata': (168995, '4a49bbbbddbb98f4e131ddad3732a2a6a08d5c3c54fc724f6201c928da153eaf'), 'finite': (3534, 'b758877e03a33aa86f81450d62ffeab86002cfa74f13ba71552a0feeb1ccc675'), 'bridge': (19990, '321481baae967d3a956c03fa7053130f4148308ed746857c953c2d4681c2c425'), 'sha_finite': (21265, '567a96144bd5e5244e599dae5ea9b4142da298c08cdaa49202e385cd14737f17'), 'sha': (29648, 'a6fc9c042784f9d48731acafcbb3c6366a5746c458fa6aa9abe1aac59c25df92'), 'engine': (12136, '97a3edaccef6dba1f095f82706c260cb0520fae49751ba34d76dda0ad314ec88'), 'tile': (5635, '19bcb21499706281f7f1505b905e56656c833901d7978d7ae94b3bc2ad361908'), 'completion': (36839, '46d2a129081049ec78746bef74ff4d3fd6bec5a188d60fb38e0a6c23c7346d02'), 'raw': (55815, '265db2eaea290c7617824e8f7ac2b78a257be3629e248a454e7a063d41512e2e')}

def v9_identity(raw,name):
    expected=V9_IDENTITIES[name]
    need(expected is not None, "Actual V9 terminal identity is still pending")
    size,sha=expected
    need(identity(raw)==dict(bytes=size,sha256=sha),"Known actual V9 "+name+" identity required")
    return json.loads(raw)

def v9_static_scope(candidate, metadata, raw, completion, finite, bridge, sha_finite):
    """Pure recorded-source contract; this function alone is not model replay."""
    need(candidate['schema'] == 'protected-dense-sha-source-candidate-v9'
         and completion['schema'] == 'protected-dense-sha-paired-model-join-v9'
         and raw['schema'] == 'greedy-speed-candidate-only-model-result-v9-dense-sha',
         'No V8 schema relabelling or candidate-result reuse')
    need(raw['passed'] is True and raw['complete'] is True
         and (raw['case_count'],raw['heads'],raw['head_rows_compared']) == (12,30,120570)
         and raw['control_cases_executed_by_this_run'] == 0
         and (completion['new_candidate_cases_executed'],completion['old_control_cases_reused'],
              completion['paired_cases_covered'],completion['paired_heads'],completion['paired_head_rows']) == (12,12,24,60,241140),
         'Actual V9 fresh twelve and original twelve-control scope required')
    need(metadata['schema'] == 'greedy-speed-paired-model-packet-v1'
         and len(metadata['production_compile_order']) == len(set(metadata['production_compile_order'])) == 66
         and {'cluster-engine.sv', 'cluster-tile.sv'} <= set(metadata['production_compile_order'])
         and metadata['control_kind_major'] is metadata['candidate_kind_major'] is False,
         'Actual protected66 compiler entries and unchanged head-major layout required')
    projection=candidate['projection_dense_sources']
    need(set(projection) == {'engine','tile'}, 'Both exact changed projection sources required')
    for kind, name in [('engine','cluster-engine.sv'),('tile','cluster-tile.sv')]:
        size, sha=V9_IDENTITIES[kind]
        need({k:projection[kind][k] for k in ('bytes','sha256')} == dict(bytes=size,sha256=sha)
             and projection[kind]['path'] == candidate['candidate'] + '/project/' + name
             and metadata['files']['optimized/' + name] == dict(bytes=size,sha256=sha),
             'Actual candidate/model projection bytes differ')
    for item in (metadata,raw,completion,bridge):
        need(item['projection_dense_sources'] == projection, 'Projection source object differs by role')
    need(metadata['prior_V8_candidate_results_reused'] is False
         and metadata['all_current_projection_production_sources_recompiled'] is False
         and metadata['all_current_projection_production_sources_must_be_recompiled'] is True,
         'Source preparation must not claim execution')
    phase=metadata['coordinate_phase_observer']
    need(candidate['coordinate_phase_observer'] == phase
         and phase['required_model_define'] == 'BOARD1_ATTENTION_COORDINATE_PHASE_CHECK'
         and phase['native_define_added'] is False and phase['candidate_only_model_define_added'] is True
         and phase['model_define_enables_coordinate_phase_and_four_lane_checks'] is True
         and phase['source']['sha256'] == '8bff05ff67e55faa8afcfe7a2204b259c0827c11d4cada8ad5b3ad8e3e82585a'
         and phase['seam']['sha256'] == '91c161f012830a52b136b419310a209081eda9d56c2efb5cf4eb192d0f8eb31d'
         and phase['checks']['sha256'] == '1635e472db5dee1512419954f97ddbce24970dbfd52ca7fed2ad9af4d2ddf635'
         and phase['four_lane_checker']['sha256'] == '67bb334543befc846ecbd8ef06198671de3076cc4a268f5f65263a9a1d1dd6cc',
         'Unchanged V6 attention checker/seam with candidate-only macro required')
    for item in (raw,completion):
        need(item['coordinate_phase_observer'] == phase
             and item['simulation_seam'] == phase['seam'] and item['four_lane_checker'] == phase['four_lane_checker']
             and item['prior_V8_candidate_results_reused'] is False
             and item['all_current_projection_production_sources_recompiled'] is True
             and item['candidate_only_phase_observer_macro'] == phase['required_model_define']
             and item['native_phase_observer_macro_added'] is False
             and item['candidate_parent_compiler_macros_identical'] is False
             and item['projection_dense_finite_source_completion'] == candidate['projection_dense_finite_source_completion'],
             'Fresh exact V9 projection/phase compile scope required')
    geometry=dict(tiles=4,rows_per_tile=16,physical_projection_lanes=64,
        contexts_per_physical_multiplier=1,minimum_weight_accept_spacing=1)
    for item in (candidate,metadata,raw,completion,bridge):
        need(item['projection_dense_geometry']==geometry
             and item['dense_projection_cancel_payload_erasure_claimed'] is False
             and 'projection_fourway_sources'not in item and 'projection_finite_source_completion'not in item,
             'Direct dense64/non-erasure scope required; old fourway fields cannot be relabelled')
    need(finite['schema']=='protected-dense-donor-initialized-component-completion-v1'
         and finite['passed']is True and finite['source_only']is True and finite['source_inputs_unchanged']is True
         and finite['new_semantic_mutants_refused']==9
         and finite['source_geometry']==dict(tiles=4,physical_projection_lanes=64,physical_lanes_per_tile=16,
             accumulator_contexts_per_multiplier=1,minimum_weight_accept_spacing_clocks=1)
         and finite['pending_payload_write_at_cancel_edge_observed']is True
         and all(finite[k]is True for k in ('initialized_payload_and_metadata_all16_checked',
             'semantic_DONE_immediate_last_row_checked','full_first_overwrite_recovery_checked',
             'engine_CLEAR_lock_fault_public_gates_checked','tile_kill_begin_reset_control_revocation_checked',
             'initialized_dense_busy_read_before_write_checked','adjacent_dense_accepts_legal_checked'))
         and all(finite[k]is False for k in ('payload_erasure_claimed','fourway_V7_finite_reused',
             'hardware_access','native_build','full_model','vendor_primitive_tested','whole_machine_claim')),
         'Exact initialized dense donor finite scope required; pending cancellation writes do not imply erasure')
    for kind in ('engine','tile'):
        need(pin2_local(finite['sources'][kind])==pin2_local(projection[kind]),
             'Dense component donor source differs from actual candidate/model')
    need(pin2_local(finite['sources']['multiplier'])==metadata['files']['optimized/cluster-mul.sv']
         and finite['producer']['sha256']=='311488a9fd8c814e671de331a6273c85b9670aea26aac762debbc1aa23633208',
         'Dense component multiplier or exact source producer differs')
    need(bridge['schema'] == 'protected-v9-unchanged-v6-attention-control-scope-association-v1'
         and bridge['passed'] is True and (bridge['assertions'],bridge['queries'])==(66,136)
         and bridge['additional_assertions_or_queries_claimed'] == 0
         and bridge['projection_arithmetic_covered_by_this_proof'] is False
         and bridge['solver_or_auditor_executed'] is False and bridge['whole_machine_refinement'] is False,
         'Attention source bridge must not claim projection arithmetic or new proof execution')
    need(completion['whole_old_machine_miter'] is False and completion['native_or_board_authority'] is False,
         'Finite model does not qualify a native image or a whole-machine miter')
    sha_source=candidate['sha_direct_add_source']
    need(pin2_local(sha_source)==dict(bytes=V9_IDENTITIES['sha'][0],sha256=V9_IDENTITIES['sha'][1])
         and sha_source['path']==candidate['candidate']+'/project/sha.sv'
         and 'sha.sv' in metadata['production_compile_order']
         and metadata['files']['optimized/sha.sv']==pin2_local(sha_source)
         and candidate['changed_from_v8']==['project/cluster-engine.sv','project/cluster-tile.sv']
         and candidate['all_other_native_input_bytes_unchanged_count']==91
         and candidate['guard_cache_RTL_unchanged_from_v8']is True
         and candidate['compact_boot_KV_SHA_modules_unchanged']is True
         and candidate['weight_page_SHA_arithmetic_mapping_retained_from_v8']is True,
         'Exact V9 two-donor delta, retained A6 SHA and current compiled snapshot required')
    finite_pin=candidate['sha_direct_add_finite_source_completion']
    need(pin2_local(finite_pin)==dict(bytes=V9_IDENTITIES['sha_finite'][0],sha256=V9_IDENTITIES['sha_finite'][1])
         and sha_finite['schema']=='source-only-sha-direct-add-check-result-v8'
         and sha_finite['passed']is True and sha_finite['source_unchanged']is True
         and sha_finite['solver_word_domain_all_32bit_pairs']is True
         and sha_finite['native_primitive_finite_scope_only']is True
         and sha_finite['source_compressor_REGISTER_RESULT']==0
         and sha_finite['hardware_access']is False and sha_finite['native_build']is False
         and sha_finite['full_model']is False and sha_finite['whole_machine_claim']is False,
         'Separately scoped exact R5 source/normalized relation/vendor finite completion required')
    clock=sha_finite['compressor_clock_event_model']
    need(clock['asynchronous_input_negative_holdtime_model']is True
         and clock['explicit_input_assumptions_added']is False
         and clock['physical_async_reset_theorem']is False and clock['metastability_theorem']is False,
         'Normalized binary clock-event and negative-hold scope required')
    macro='Native SYNTHESIS without VERILATOR selects exact DSP helper; fresh Verilator model uses portable modulo32 helper. Primitive finite evidence is separate.'
    need(candidate['sha_model_native_macro_elaboration_identical']is False,
         'Candidate native/model SHA macro branches are distinct')
    for item in (metadata,raw,completion):
        need(item['sha_direct_add_source']==sha_source
             and item['sha_direct_add_finite_source_completion']==finite_pin
             and item['sha_model_native_macro_elaboration_identical']is False
             and item['sha_macro_scope']==macro,'Exact SHA source/finite/macro disclosure differs')
    need(metadata['all_current_SHA_production_source_recompiled']is False
         and metadata['all_current_SHA_production_source_must_be_recompiled']is True
         and all(item['all_current_SHA_production_source_recompiled']is True for item in (raw,completion)),
         'SHA source preparation versus fresh execution flags differ')
    need(bridge['sha_direct_add_source']==sha_source
         and bridge['sha_direct_add_finite_source_completion']==finite_pin
         and bridge['sha_arithmetic_covered_by_this_proof']is False,
         'Attention source association does not prove changed SHA arithmetic')
    return projection, phase


def validate_protected_v9_models(reader, completion, spec):
    """Exact V9 twelve fresh cases + original twelve controls; callbacks only."""
    need(reader.variant == 'kv-protected', 'V9 protected model variant required')
    origins=reader.data['roles']
    selected=v9_identity(reader.read(origins['model_complete']), 'completion')
    need(selected == completion, 'Completion detached from actual current role')
    candidate=v9_identity(reader.read(origins['source_candidate']), 'candidate')
    metadata=v9_identity(reader.read(spec['metadata']), 'metadata')
    raw=v9_identity(reader.read(spec['raw_result']), 'raw')
    finite_pin=candidate['projection_dense_finite_source_completion']
    finite=v9_identity(reader.read(finite_pin['path'],finite_pin), 'finite')
    bridge=v9_identity(reader.read(spec['attention_bridge']), 'bridge')
    sha_pin=candidate['sha_direct_add_finite_source_completion']
    sha_finite=v9_identity(reader.read(sha_pin['path'],sha_pin),'sha_finite')
    projection,phase=v9_static_scope(candidate,metadata,raw,completion,finite,bridge,sha_finite)
    for key in ('plan','execution','producer'):
        row=finite[key];reader.read(row['path'],row)
    for row in finite['sources'].values():reader.read(row['path'],row)
    sha_source=candidate['sha_direct_add_source'];reader.read(sha_source['path'],sha_source)
    need(identity(reader.read(spec['packet_files']['optimized/sha.sv']))==pin2_local(sha_source), 'Actual compiled SHA snapshot differs')
    reader.read(sha_finite['plan']['path'],sha_finite['plan'])
    need(sha_finite['plan']['sha256']=='03285601173d51afd305511d0d44453421503f958565fe9629af434d84185554','Exact corrected R5 plan required')
    need(completion['source_candidate'] == reader.pin(origins['source_candidate'])
         and bridge['source_candidate'] == reader.pin(origins['source_candidate'])
         and bridge['projection_dense_finite_source_completion'] == finite_pin,
         'Candidate/model/finite/attention bridge cross-binding differs')
    for kind,name in [('engine','cluster-engine.sv'),('tile','cluster-tile.sv')]:
        reader.read(projection[kind]['path'],projection[kind])
        need(identity(reader.read(spec['packet_files']['optimized/'+name])) ==
             {k:projection[kind][k]for k in ('bytes','sha256')}, 'Actual compiled projection snapshot differs')
    for key in ('source','seam','checks','four_lane_checker'):
        row=phase[key];reader.read(row['path'],row)
    for item in (completion,raw):
        for key,sha in [('runner','01d2f91b3d4adea4cf723b6f8c68752f1feecb66582d580100e4955f24f544a2'),
                        ('phase_gate','421536df542338a7c79cef63cdc877baef1ed7a2747e0fcc78ba807609f54ba7')]:
            row=item[key]
            origin=row['path'] if 'path' in row else completion[key]['path']
            need(row['sha256'] == sha and equal_pin(row,reader.read(origin,row)), 'V9 actual driver/gate source differs')
    producer=completion['producer'];need(producer['sha256']=='2c325f93fbf768fa7ba2d95ace7c8099892cb2e671827cfd19ed0f59eb2b0794' and equal_pin(producer,reader.read(producer['path'],producer)), 'Exact corrected V9 completion producer required')
    result=_validate_greedy_models('kv-protected',reader,completion,spec,protected_v9=True)
    return dict(result, source_epoch='v9-dense-sha', prior_V8_candidate_results_reused=False,
                actual_projection_sources_recompiled_and_byte_joined=True,
                initialized_projection_finite_receipt_pinned=True,
                dense_projection_cancel_payload_erasure_claimed=False,
                unchanged_attention_bridge_pinned_separate_from_model=True,
                actual_SHA_production_source_recompiled_and_byte_joined=True,
                sha_component_completion_pinned_separately=True,
                sha_model_native_macro_elaboration_identical=False,
                source_proof_or_native_or_board_qualification_claimed=False)


V15_SCOPE_HELPER_SHA256 = '68a4c48b986a31f402b446a03f2f19953a552cca7828105088cf97c8f4643b17'


def v15_scope_helper():
    """Load installed reviewed pure code only, never captured source bytes."""
    import importlib.util
    from pathlib import Path
    path=Path(__file__).resolve().parent/'current_greedy_v15_scope_portable_v1.py'
    need(type(V15_SCOPE_HELPER_SHA256)is str and hashlib.sha256(path.read_bytes()).hexdigest()==V15_SCOPE_HELPER_SHA256,
        'Reviewed V15 scope-helper source contract pending')
    spec=importlib.util.spec_from_file_location('_portable_current_v15_model_scope',path)
    helper=importlib.util.module_from_spec(spec);spec.loader.exec_module(helper);return helper


def validate_protected_v15_models(reader,completion,spec):
    """Fresh12+original12 full raw rows/ownership/phase replay for the V15 packet."""
    helper=v15_scope_helper();helper.finalized()
    candidate=reader.role('source_candidate');metadata=reader.json(spec['metadata']);raw=reader.json(spec['raw_result'])
    need(identity(reader.read(spec['metadata']))==helper.PACKET_PIN
        and reader.pin(reader.data['roles']['model_complete'])==helper.FINAL_MODEL_COMPLETION_PIN
        and reader.pin(spec['raw_result'])==helper.FINAL_RAW_MODEL_PIN,
        'Exact current model packet/completion/raw roles required')
    scope=helper.source_scope(reader,candidate,metadata,raw,completion,omissions=spec['omitted_inputs'])
    result=_validate_greedy_models('kv-protected',reader,completion,spec,protected_v15=True)
    return dict(result,**scope,attention_phase_only=True,four_lane_checker_inherited=False,
        component_finite_counts_are_not_added_to_attention_or_cache_proof=True)
