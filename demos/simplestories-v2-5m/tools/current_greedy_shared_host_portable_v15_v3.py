"""Callback-only all-three final shared-host closure with critical-source census.

Inputs are authenticated Capsule readers and results produced internally by the
pinned primary stages. No original-path IO, imports of captured sources, tools,
UI or device work occurs. This helper never admits a current release.
"""
import ast
from collections import Counter
import hashlib
import json
import math
from pathlib import PurePosixPath
import re

VARIANTS=('baseline','kv-protected','encrypted-memory')
LAYOUT={
 'baseline':dict(hardware='hardware',prebuilt='prebuilt/inference',inventory='hardware-inputs.json',native=90,owned=87),
 'kv-protected':dict(hardware='variants/kv-protected/hardware',prebuilt='prebuilt/kv-protected',inventory='hardware-inputs-kv-protected.json',native=93,owned=89),
 'encrypted-memory':dict(hardware='variants/encrypted-memory/hardware',prebuilt='prebuilt/encrypted-memory',inventory='hardware-inputs-encrypted-memory.json',native=100,owned=96)}
COUNTS={name:row['native']for name,row in LAYOUT.items()}
EPOCHS={'baseline':'baseline-v1','kv-protected':'protected-v15-compact-prefix','encrypted-memory':'encrypted-v5-coordinate'}
POLICIES={'baseline':'root-greedy-sram-selection-v2','kv-protected':'root-greedy-sram-selection-v15-compact-prefix','encrypted-memory':'root-greedy-sram-selection-v5-coordinate'}
BASIS_SHA='4ea07924555fd688562ace7902f5a1facd05b2d44dac7b7f91c7652deeb7c072'
BASIS_DECLARED_MEMBERS=1908
HOST_FIXTURE_BASIS_SHA='2d3d8fc60ef3b4ca06f93e17f380d24f1000101ba6fee756eebeec41a9a8fe5d'
DECLARED_BASIS_OMISSIONS={'history/seeded-sampling-0e6-qualified.zip':dict(bytes=63338547,
    sha256='1691c1263609ef70be3793d84a8a1ee62617bb5509ed627eb81547970d15634f')}
ORIGINAL_MANIFEST_SHA='354b31bb70f1694784cc0264d0e0642495213c5f9c0303d4f04e0c1296980323'
ORIGINAL_RUNTIME_SHA='0708f97a51863eed9f2a1140bfd578e3edc57736d3e3c839be83bec4e04c1fe0'
BACKEND_SHA='478e884fc84503ec434f6b3691041c429808fe6452d3642d8b164f6779800957'
UI_SHA='f24464429901a0ef5b7d8b11925914f59f047d9d891dc0c10ec3114d694bd6c8'
BASELINE_INVENTORY='4f4cbc54676e9d976af7358386c19d8befdab34d819de30e4fb3e42beb3362fd'
MATERIALIZER_SHA = 'a74af57acac5b98792c5f2a3803cb01a060422cc29aefb8a648e627bb372ceb5'
MIXED_SHA = 'cc27000e42b4c65695bec690f7e921286fc90631dc58e5883b6cdcd48e80ce98'
BLUEPRINT_SHA='89ba956f1c9a5000ecfa92a81c05245c16ee5cc46daaf821d59f2e92265853ee'
HOST79_PRODUCER_SHA = '1f7b782871fd55aef006d70621b62333a066276cae83e364ebddbbede4df5a5b'
FINAL_CLI_REVIEW_PINS = {'baseline': {'path': '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-greedy-speed/evidence/baseline-board-complete-independent-raw-review-v2.json', 'bytes': 11730, 'sha256': '1dd51946699d503e94d508c2798ae40beb1c0c79f38fbe0fc5ccd4b68e08fca8'}, 'kv-protected': {'path': '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-greedy-speed/evidence/protected-v15-p3r0-board-full10-r2-independent-review-r1.json', 'bytes': 16112, 'sha256': '2e25e149ac4e82ac86cd04ba314ebb336a1474ad202313c3ae70d02b94ea9f33'}, 'encrypted-memory': {'path': '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-greedy-speed/evidence/encrypted-CFC-board-complete-independent-raw-review-v7.json', 'bytes': 13704, 'sha256': '360fd371dcef9d0287acef4b0cd09bc042bba199ba2282031a0305d59b421cc5'}}
CLI_REVIEWER_PINS={
 'baseline':dict(path='/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-greedy-speed/tools/review_greedy_board_v2.py',bytes=22586,sha256='f72ac560b6d25a7771faec30e9a3bf705bb3a0753acbc5d60f58f142a7ad8959'),
 'kv-protected':dict(path='/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-greedy-speed/tools/review_greedy_board_v15_mixed_r4.py',bytes=33118,sha256='bf60af128f7ea68350ef8c2ee36f5fc4d8f5d4d1b743c78c9a3460727c0d7cc1'),
 'encrypted-memory':dict(path='/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-greedy-speed/tools/review_greedy_board_v7_mixed.py',bytes=30712,sha256='376ccd697e06724216769fd91209f4cb46c1748e8a23bc5d3eb9e366034c3c38')}
CAPTURED_MANIFEST_REFERENCE={'schema': 'captured-original-public-manifest-reference-view-v1', 'logical_manifest_path': '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/fpga-demo/public-release/MANIFEST.json', 'captured_logical_identity': {'bytes': 366488, 'sha256': '354b31bb70f1694784cc0264d0e0642495213c5f9c0303d4f04e0c1296980323'}, 'physical_manifest': {'path': '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-greedy-speed/build/recipient-rtl-v2-minimal-reference-r1/reference/baseline-formal-354/MANIFEST.json', 'bytes': 366488, 'sha256': '354b31bb70f1694784cc0264d0e0642495213c5f9c0303d4f04e0c1296980323'}, 'reference_ledger': {'path': '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-greedy-speed/build/recipient-rtl-v2-minimal-reference-r1/reference/baseline-formal-354/REFERENCE-SOURCES.json', 'bytes': 20657, 'sha256': 'db49aa75151b8b1633779503af8cb5a46f754979cd330db194935e88bc998794'}, 'reference_basis_manifest': {'path': '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-greedy-speed/build/recipient-rtl-v2-minimal-reference-r1/MANIFEST.json', 'bytes': 381738, 'sha256': '4ea07924555fd688562ace7902f5a1facd05b2d44dac7b7f91c7652deeb7c072'}, 'helper': {'path': '/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/inference-only/tang-greedy-speed/tools/captured_original_public_manifest_view_v1.py', 'bytes': 7064, 'sha256': '247018dae33b1ccb374fbac5b3d1ca85dd6a4969304945e1e9e1f761c1fc7fce'}, 'exact_single_logical_path_only': True, 'all_other_paths_read_from_actual_files': True, 'logical_Path_writes_permitted': False, 'original_manifest_provenance_metadata_only': True, 'old_full_release_or_image_substituted': False, 'source_checksum_or_PASS_bypass': False, 'native_model_or_hardware_qualification_granted': False}
REVIEWED_RELEASE_CONTRACT=None
DRAFT_SOURCE_FINALIZED = True
# Exact critical rows of the reviewed baseline/V5/V8 collectors' HOST tuple.
# Required origins are derived from the one shared package; same bytes under an
# unrelated path do not replace a row that the actual browser had to consume.
COMMON_HOST_MEMBERS=(
    'host-app/streamlit_app.py','host-app/fpga_backend.py',
    'host-app/runtime_profile.py','host-app/sampling_protocol.py',
    'host-app/token_machine_uart.py','host-app/uart_channel.py',
    'host-app/qualify_board.py','host-app/start_local_server.py',
    'host-app/requirements.txt','host-app/.streamlit/config.toml',
    'host-app/assets/tokenizer.json')
SETTINGS_MEMBER='variants/seeded-sampling/tools/settings_codec.py'
COMMON_CRITICAL_MEMBERS=COMMON_HOST_MEMBERS+(SETTINGS_MEMBER,)


def need(ok,message):
    if not ok:raise ValueError(message)
def digest(raw):return hashlib.sha256(raw).hexdigest()
def canonical(value):return(json.dumps(value,sort_keys=True,separators=(',',':'),allow_nan=False)+'\n').encode()
def encoded(value):return(json.dumps(value,sort_keys=True,indent=2,allow_nan=False)+'\n').encode()
def json_object(raw):
    def pairs(rows):
        result={}
        for key,value in rows:
            need(key not in result,'Duplicate JSON key');result[key]=value
        return result
    def nonfinite(value):raise ValueError('Nonfinite JSON value: '+value)
    result=json.loads(raw,object_pairs_hook=pairs,parse_constant=nonfinite)
    need(type(result)is dict,'JSON object required');return result
def pin2(row):return {key:row[key]for key in ('bytes','sha256')}
def identity(raw):return dict(bytes=len(raw),sha256=digest(raw))
def child(root,name):
    need(type(root)is str and PurePosixPath(root).is_absolute() and '..'not in PurePosixPath(root).parts and '\x00'not in root,'Absolute unchanged origin required')
    need(type(name)is str and name and '\x00'not in name and str(PurePosixPath(name))==name and not PurePosixPath(name).is_absolute()and '..'not in PurePosixPath(name).parts and '\\'not in name,'Safe relative member required')
    return str(PurePosixPath(root)/name)

class Inputs:
    def __init__(self,readers):
        self.consumed={}
        for reader in readers:
            for origin,wanted in reader.consumed.items():
                if type(wanted)is dict and set(wanted)=={'original','portable','encoding'}:
                    need(wanted['original']['path']==origin and wanted['encoding']in('plain','gzip'),'Captured consumption provenance differs')
                    wanted=wanted['original']
                self.bind(origin,wanted)
    def bind(self,origin,wanted):
        need(type(origin)is str and PurePosixPath(origin).is_absolute()and '..'not in PurePosixPath(origin).parts and '\x00'not in origin,'Absolute original origin required')
        wanted=pin2(wanted)
        need(origin not in self.consumed or self.consumed[origin]==wanted,'Conflicting aggregate original-origin identity')
        self.consumed[origin]=wanted
    def read(self,reader,origin,wanted=None):
        raw=reader.read(origin,wanted);need(type(raw)is bytes,'Authenticated byte reader required')
        if wanted is not None:need(identity(raw)==pin2(wanted),'Pinned source bytes differ')
        self.bind(origin,identity(raw));return raw
    def pin(self,reader,origin):return dict(path=origin,**identity(self.read(reader,origin)))
    def pinned(self,reader,row):
        need(type(row)is dict and set(row)=={'path','bytes','sha256'},'Exact original file pin required')
        return self.read(reader,row['path'],row)
    def json(self,reader,origin,wanted=None):return json_object(self.read(reader,origin,wanted))
    def record(self,reader,row):return json_object(self.pinned(reader,row))
    def role(self,reader,name):
        origin=reader.data['roles'][name];need(type(origin)is str,'Missing actual role: '+name)
        return self.json(reader,origin),self.pin(reader,origin)

def parse_unittest79(raw, expected_test_ids, expected_counts):
    """Pure strict parser; expected IDs/counts are caller-supplied blueprint data.

    The three known fixture/dependency diagnostics may interrupt verbose test
    lines. They are retained in the original log and never count as test status.
    Every expected fully qualified test needs its own exact ``ok`` and summary.
    """
    need(type(raw) in (bytes, str), 'Text or UTF-8 byte log required')
    if type(raw) is bytes:
        need(0 < len(raw) <= 16 * 1024**2, 'Bounded nonempty test log required')
        raw = raw.decode('utf-8')
    need(0 < len(raw.encode('utf-8')) <= 16 * 1024**2 and '\x00' not in raw,
         'Bounded nonempty test log required')
    need(type(expected_test_ids) is list and len(expected_test_ids) == 79
         and len(set(expected_test_ids)) == 79
         and all(type(x) is str and re.fullmatch(r'test_\w+\.\w+\.test_\w+', x)
                 for x in expected_test_ids), 'Exactly 79 unique expected test IDs required')
    need(type(expected_counts) is dict and len(expected_counts) == 12
         and all(type(k) is str and type(v) is int and v > 0 for k, v in expected_counts.items())
         and sum(expected_counts.values()) == 79
         and dict(Counter(x.split('.')[0] for x in expected_test_ids)) == expected_counts,
         'Exact twelve-suite expected census required')
    header = re.compile(r'^(test_\w+) \((test_\w+\.\w+\.test_\w+)\) \.\.\.(?: (.*))?$')
    summary = re.compile(r'^Ran 79 tests in ((?:0|[1-9]\d*)(?:\.\d+)?)s$')
    warning = re.compile(r"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3} "
        r"(?:WARNING streamlit\.runtime\.scriptrunner_utils\.script_run_context: )?"
        r"Thread 'MainThread': missing ScriptRunContext! This warning can be ignored when running in bare mode\.$")
    def diagnostic(line):
        return (re.fullmatch(r'GOWIN offline build started, pid=[1-9]\d*', line) is not None
                or re.fullmatch(r'Previous local profile preserved in /[^\x00\r\n]+/previous-board-profile\.json', line) is not None
                or warning.fullmatch(line) is not None)
    seen = set(); test_ids = []; pending = None; separator = ran = terminal = False; seconds = None
    for line in raw.splitlines():
        if not line:
            continue
        need(not terminal, 'Extra content after final OK')
        match = header.fullmatch(line)
        if match:
            need(pending is None and not separator and not ran, 'Reordered/incomplete verbose test status')
            short, full, tail = match.groups()
            need(short == full.rsplit('.', 1)[1] and full in expected_test_ids and full not in seen,
                 'Unknown, duplicate or inconsistent fully qualified test ID')
            seen.add(full); pending = full
            if tail == 'ok':
                test_ids.append(pending); pending = None
            elif tail:
                need(diagnostic(tail), 'Non-OK test status or unknown test diagnostic')
            continue
        if line == 'ok':
            need(pending is not None and not separator, 'Unowned or repeated ok status')
            test_ids.append(pending); pending = None
            continue
        if diagnostic(line):
            need(not separator and not ran, 'Diagnostic after terminal test census')
            continue
        if line == '-' * 70:
            need(not separator and pending is None and len(test_ids) == 79,
                 'Missing test statuses or duplicate summary separator')
            separator = True
            continue
        match = summary.fullmatch(line)
        if match:
            need(separator and not ran and pending is None and len(test_ids) == 79,
                 'Missing, repeated or reordered Ran79 summary')
            seconds = float(match[1]); need(math.isfinite(seconds) and 0 < seconds <= 600,
                                          'Invalid or out-of-bound unittest elapsed time')
            ran = True
            continue
        if line == 'OK':
            need(ran and separator and pending is None and len(test_ids) == 79,
                 'Bare OK does not establish 79 successful tests')
            terminal = True
            continue
        raise ValueError('Unknown diagnostic, failing/skipped test or malformed unittest summary')
    counts = dict(Counter(x.split('.')[0] for x in test_ids))
    need(terminal and ran and separator and pending is None and set(test_ids) == set(expected_test_ids)
         and counts == expected_counts, 'Incomplete79/twelve-suite terminal success')
    return dict(test_ids=test_ids, per_suite_counts=counts, total=len(test_ids), seconds=seconds)


def one_assignment(tree,name):
    found=[node for node in tree.body if isinstance(node,ast.Assign) and len(node.targets)==1
        and isinstance(node.targets[0],ast.Name) and node.targets[0].id==name]
    need(len(found)==1,'Unique catalog assignment required: '+name);return found[0].value

def member(node,key):
    need(isinstance(node,ast.Dict) and all(isinstance(k,ast.Constant) and type(k.value)is str for k in node.keys),
         'Literal catalog dictionary required')
    keys=[k.value for k in node.keys];need(len(keys)==len(set(keys)),'Duplicate catalog key')
    need(key in keys,'Missing catalog key: '+key);return node.values[keys.index(key)]

def slots(tree):
    variants=one_assignment(tree,'VARIANTS')
    return {'baseline':one_assignment(tree,'HARDWARE_INPUTS_SHA256'),
        'kv-protected':member(member(variants,'kv-protected'),'inputs_sha256'),
        'encrypted-memory':member(member(variants,'encrypted-memory'),'inputs_sha256')}

def span(raw,node):
    need(node.lineno==node.end_lineno,'Single-line inventory literal required')
    lines=raw.splitlines(keepends=True);start=sum(map(len,lines[:node.lineno-1]))+node.col_offset
    end=sum(map(len,lines[:node.end_lineno-1]))+node.end_col_offset
    token=raw[start:end]
    need(isinstance(node,ast.Constant) and type(node.value)is str and re.fullmatch('[0-9a-f]{64}',node.value)
         and token in [("'"+node.value+"'").encode(),('"'+node.value+'"').encode()],
         'Exact quoted hexadecimal inventory token required')
    return start,end,token

def compare_bytes(original,proposed,wanted):
    need(set(wanted)==set(COUNTS) and all(type(value)is str and re.fullmatch('[0-9a-f]{64}',value) for value in wanted.values()),
         'Explicit three inventory digests required')
    first=ast.parse(original);second=ast.parse(proposed);before=slots(first);after=slots(second)
    edits=[];descriptors=[]
    for variant,node in before.items():
        start,end,token=span(original,node);span(proposed,after[variant])
        need(after[variant].value==wanted[variant],'Proposed catalog does not bind supplied inventory: '+variant)
        replacement=token[:1]+wanted[variant].encode()+token[-1:]
        edits.append((start,end,replacement))
        descriptors.append(dict(variant=variant,before=node.value,after=wanted[variant],
            original_literal_start_byte=start,original_literal_end_byte=end,changed=node.value!=wanted[variant]))
    expected=original
    for start,end,replacement in sorted(edits,reverse=True):expected=expected[:start]+replacement+expected[end:]
    need(expected==proposed,'Bytes outside the three permitted inventory literal tokens changed')
    functions=lambda tree:{node.name:ast.dump(node,include_attributes=False) for node in tree.body if isinstance(node,(ast.FunctionDef,ast.AsyncFunctionDef))}
    need(functions(first)==functions(second),'Runtime function AST changed')
    seeded_a=member(one_assignment(first,'VARIANTS'),'seeded-sampling');seeded_b=member(one_assignment(second,'VARIANTS'),'seeded-sampling')
    need(ast.dump(seeded_a,include_attributes=False)==ast.dump(seeded_b,include_attributes=False)
         and ast.get_source_segment(original.decode(),seeded_a)==ast.get_source_segment(proposed.decode(),seeded_b),
         'Seeded mapping source or AST changed')
    baseline=member(member(one_assignment(second,'VARIANTS'),'baseline'),'inputs_sha256')
    need(isinstance(baseline,ast.Name) and baseline.id=='HARDWARE_INPUTS_SHA256','Baseline catalog lost original constant reference')
    return dict(allowed_literal_slots=descriptors,all_other_source_bytes_identical=True,
        all_runtime_function_ASTs_identical=True,runtime_function_names=list(functions(first)),
        seeded_mapping_AST_and_source_identical=True,baseline_mapping_constant_reference_unchanged=True)

def build_record(variant,inventory,image,finished,static,finished_pin,static_pin,stdout,stderr):
 need(variant in LAYOUT and len(inventory)==LAYOUT[variant]['native']and finished['flow_completed']is True
      and finished['exit_code']==0 and finished['source_inputs_unchanged']is True
      and static['passed']is True and static['image_sha256']==image['sha256']==finished['image']['sha256']
      and pin2(image)==finished['image'],'Actual matching completed native/image/static data required')
 return dict(schema='fixed-fpga-local-build-v1',variant=variant,distribution='maintainer-prebuilt',
  flow_completed=True,exit=finished['exit_code'],seconds=finished['seconds'],
  source_inputs_verified=True,source_inputs_unchanged=True,hardware_inputs_sha256=hashlib.sha256(canonical(inventory)).hexdigest(),
  image_relative_path='project/impl/pnr/shared_product.fs',image_sha256=image['sha256'],image_bytes=image['bytes'],
  stdout_sha256=stdout['sha256'],stderr_sha256=stderr['sha256'],original_build_receipt_sha256=finished_pin['sha256'],
  native_timing_inspection_sha256=static_pin['sha256'],timing_qualified=False,
  scope='Source-bound completed native route and exact implemented input inventory. Model, mapped, board and browser evidence remain separate. Complete vendor-DDR timing remains unqualified.')

def fixture_sources(blueprint,manifest):
    host=blueprint['host_file_relative_names'];support=blueprint['sampling_support_relative_names']
    need(len(host)==31 and len(set(host))==31 and len(support)==94 and len(set(support))==94,'Exact125 fixture input slots required')
    names=['host-app/'+name for name in host]+support
    need(len(set(names))==125 and all(name in manifest for name in names),'Complete125 manifested fixture sources required')
    fixtures=blueprint['fixture_source_pins'];need(len(fixtures)==12,'Exact12 fixture files required')
    for name,row in fixtures.items():need(manifest['host-app/'+name+'.py']==pin2(row),'Frozen positive/negative fixture bytes changed')
    return {name:manifest[name]for name in names}


def validate_cli_prerequisite(inputs,reader,variant,row,policy_pin,physical):
    """Join actual materialization prerequisites to independent raw CLI results."""
    need(type(row)is dict and set(row)=={'finished','independent_review','reviewer_source','raw_uart'},
         'Exact closed CLI prerequisite fields required')
    finished,finished_pin=inputs.role(reader,'physical_campaign')
    need(row['finished']==finished_pin and row['raw_uart']==finished['raw_uart']
         and row['independent_review']==FINAL_CLI_REVIEW_PINS[variant]
         and row['reviewer_source']==CLI_REVIEWER_PINS[variant],
         'Materialization prerequisite differs from actual CLI/review/reviewer source selection')
    inputs.pinned(reader,row['reviewer_source']);review=inputs.record(reader,row['independent_review'])
    inputs.pinned(reader,row['raw_uart'])
    need(physical['schema']=='greedy-current-portable-byte-uart-replay-v1'and physical['passed']is True
         and physical['case_count']==10 and physical['main_reference_outputs']==395
         and physical['finished']==pin2(finished_pin)and physical['original_plan']==finished['plan']
         and physical['original_raw_uart']==row['raw_uart']and pin2(physical['image'])==pin2(finished['image']),
         'CLI prerequisite is detached from the internally reparsed complete raw UART result')
    need(finished['schema']=='greedy-selected-physical-campaign-v1'and finished['variant']==variant
         and finished['passed']is finished['complete_campaign']is finished['source_inputs_unchanged']is True
         and finished['case_count']==10 and finished['main_reference_outputs']==395
         and finished['physical_fpga']is finished['final_clear_acknowledged']is finished['usb_released']is True
         and finished['flash_modified']is finished['automatic_retry']is finished['automatic_recovery']is False,
         'Full10/no-retry/no-flash actual CLI prerequisite required')
    schemas={'baseline':'greedy-physical-campaign-independent-raw-review-v1',
        'kv-protected':'greedy-physical-campaign-independent-raw-review-v15-mixed',
        'encrypted-memory':'greedy-physical-campaign-independent-raw-review-v6-mixed'}
    need(review['schema']==schemas[variant]and review['variant']==variant
         and review['checker']==row['reviewer_source']and review['actual_finished']==finished_pin
         and review['policy']==policy_pin and review['physical_plan']==finished['plan']
         and review['image']==finished['image']and review['actual_raw_log_or_closed_prefix']==row['raw_uart']
         and review['passed']is review['complete_campaign']is review['closed_cases_passed']is True
         and review['source_inputs_unchanged']is review['all_consumed_raw_bytes_and_case_results_replayed']is True
         and review['case_count']==10 and review['main_reference_outputs']==395 and review['settings_commands']==0,
         'Exact independent full10 raw CLI review/source/plan/image/policy closure required')
    need(all(review[name]is False for name in('hardware_access','browser_or_server_access',
        'owner_or_programmer_probes','release_qualified')),
        'Recorded independent CLI review grants no hardware/owner/browser/release authority')
    return dict(finished=finished_pin,raw_uart=row['raw_uart'],independent_review=row['independent_review'],
        reviewer_source=row['reviewer_source'],internally_validated_raw_CLI_cross_bound=True)


def validate_host79(inputs,host_reader,receipt_pin,artifact,manifest_pin,manifest,blueprint,basis_pin,materializer_pin,host_fixture_basis_pin,materialization_pin):
    result=inputs.record(host_reader,receipt_pin)
    need(result['schema']=='greedy-final-shared-host79-execution-v1','Concrete final79 producer schema required')
    need(result['captured_manifest_reference']==CAPTURED_MANIFEST_REFERENCE,
         '79 actual materialization reference metadata descriptor differs')
    need(result['artifact']==dict(origin=artifact,manifest=manifest_pin) and result['basis_manifest']==basis_pin
         and result['host_fixture_basis_manifest']==host_fixture_basis_pin
         and result['materialization']==materialization_pin
         and result['materializer']==materializer_pin,'79 run belongs to another shared artifact/source derivation')
    need(result['passed']is True and result['actual_browser_or_native_build']is False and result['release_qualified']is False,'79 receipt scope differs')
    need(result['producer']['sha256']==HOST79_PRODUCER_SHA and HOST79_PRODUCER_SHA is not None,'Reviewed79 producer not frozen')
    inputs.pinned(host_reader,result['producer'])
    need(result['blueprint']['sha256']==BLUEPRINT_SHA and inputs.record(host_reader,result['blueprint'])==blueprint,'Exact79 fixture blueprint required')
    expected=fixture_sources(blueprint,manifest['files'])
    need(result['source_inputs_before']==result['source_inputs_after']==result['source_snapshot_after']==expected
         and result['source_artifact_unchanged']is True and result['test_sources_unchanged']is True,'79 source before/after graph differs')
    need(set(result['source_snapshot'])==set(expected),'Every tested source snapshot required')
    receipt_root=str(PurePosixPath(receipt_pin['path']).parent)
    need(PurePosixPath(receipt_pin['path']).name=='FINISHED.json' and result['work_copy_origin']==child(receipt_root,'work'),'Actual79 receipt/work-copy relationship differs')
    for name,wanted in expected.items():
        snapshot=result['source_snapshot'][name]
        need(snapshot['path']==child(result['work_copy_origin'],name),'79 source snapshot detached from actual work copy')
        inputs.pinned(host_reader,snapshot)
        need(pin2(snapshot)==wanted,'Tested79 source differs from final shared host')
        inputs.read(host_reader,child(artifact,name),wanted)
    need(inputs.record(host_reader,result['copied_manifest'])==manifest and result['copied_manifest']['path']==child(result['work_copy_origin'],'MANIFEST.json'),'79 copied manifest differs')
    fixtures={'host-app/'+name+'.py':pin2(row)for name,row in blueprint['fixture_source_pins'].items()}
    need(result['fixture_file_pins']==fixtures,'79 fixture source declarations differ')
    execution=result['execution'];argv=execution['argv'];interpreter=result['interpreter']
    need(set(interpreter)=={'invoked_path','resolved_executable','invoked_path_is_symlink'}
         and type(interpreter['invoked_path_is_symlink'])is bool
         and PurePosixPath(interpreter['invoked_path']).is_absolute()
         and set(interpreter['resolved_executable'])=={'path','bytes','sha256'}
         and PurePosixPath(interpreter['resolved_executable']['path']).is_absolute()
         and type(interpreter['resolved_executable']['bytes'])is int and interpreter['resolved_executable']['bytes']>0
         and re.fullmatch('[0-9a-f]{64}',interpreter['resolved_executable']['sha256']), 'Explicit recorded executable provenance required')
    # Executable provenance is recorded; the byte consumer makes no independent
    # process/interpreter attestation and does not redistribute omitted tools.
    need(execution['raw_log']['path']==child(receipt_root,'tests.log')
         and type(execution['seconds'])in(int,float) and math.isfinite(execution['seconds'])
         and 0<execution['seconds']<=600,'Actual79 raw log/elapsed scope differs')
    need(type(argv)is list and len(argv)==7 and argv[1:]==['-I','-B','-m','unittest','discover','-v']
         and argv[0]==result['interpreter']['invoked_path']
         and execution['cwd']==child(result['work_copy_origin'],'host-app')
         and execution['exit_code']==0 and execution['timed_out']is False and execution['timeout_seconds']==600,
         'Exact closed dependency-enabled79 unittest argv/cwd/exit required')
    need(result['hardware_access']is False and result['network_access']is False and result['server_access']is False and result['retries']==0,'79 fixture-only no-retry scope differs')
    raw=inputs.pinned(host_reader,execution['raw_log'])
    parsed=parse_unittest79(raw,blueprint['expected_test_ids'],blueprint['expected_suite_method_counts'])
    need(parsed==result['parsed'] and result['expected_test_ids']==blueprint['expected_test_ids']
         and result['expected_per_suite_counts']==blueprint['expected_suite_method_counts'],'Actual79 parsed log/source receipt differs')
    return dict(receipt=receipt_pin,interpreter_provenance=interpreter,interpreter_execution_independently_attested=False,test_ids=parsed['test_ids'],per_suite_counts=parsed['per_suite_counts'],total=parsed['total'],raw_log=execution['raw_log'],source_inputs=expected,argv=argv,cwd=execution['cwd'])


def validate_shared_host(*,host_reader,variant_readers,native_results,physical_results,browser_results,spec):
    need(DRAFT_SOURCE_FINALIZED and all(type(x)is str and len(x)==64 for x in
        (MATERIALIZER_SHA,MIXED_SHA,HOST79_PRODUCER_SHA))
        and all(type(row)is dict and set(row)=={'path','bytes','sha256'}for row in FINAL_CLI_REVIEW_PINS.values()),
        "UNFINALIZED V15 common-host source contract pending")
    need(all(type(mapping)is dict and set(mapping)==set(VARIANTS)for mapping in [variant_readers,native_results,physical_results,browser_results]),'Allthree internally validated variant results required')
    need(spec['schema']=='greedy-final-shared-host-closure-spec-v1','Explicit final shared-host specification required')
    inputs=Inputs([host_reader,*variant_readers.values()])
    for result in browser_results.values():
        for origin,wanted in result['consumed_original_file_identities'].items():inputs.bind(origin,wanted)
    materialized=inputs.record(host_reader,spec['materialization'])
    manifest=inputs.record(host_reader,spec['artifact_manifest']);artifact=materialized['artifact']
    need(materialized['schema']=='root-private-shared-browser-materialization-v1'and materialized['prepared']is True
         and materialized['manifest']==spec['artifact_manifest']
         and spec['artifact_manifest']['path']==child(artifact,'MANIFEST.json'),'Exact materialized browser artifact required')
    need(type(materialized['physical_cli_prerequisites'])is dict
         and set(materialized['physical_cli_prerequisites'])==set(VARIANTS),
         'Materialization must retain exactly allthree actual closed CLI prerequisites')
    need(all(materialized[key]is False for key in ['runtime_registration_performed','host79_fixtures_run','browser_or_hardware_run','release_qualified','PUBLIC_mutated']), 'Materialization cannot supply later qualification')
    need(digest(inputs.pinned(host_reader,spec['materializer_source']))==MATERIALIZER_SHA
         and digest(inputs.pinned(host_reader,spec['mixed_source']))==MIXED_SHA,'ReviewedV15 materializer/mixed source derivation required')
    need(materialized['captured_manifest_reference']==manifest['captured_manifest_reference']==CAPTURED_MANIFEST_REFERENCE,
         'Exact immutable captured metadata reference required in artifact and materialization')
    for key in('physical_manifest','reference_ledger','reference_basis_manifest','helper'):
        inputs.pinned(host_reader,CAPTURED_MANIFEST_REFERENCE[key])
    need(spec['original354_manifest']==CAPTURED_MANIFEST_REFERENCE['physical_manifest'],
         'Original attribution must use the actual immutable fixture, not live public metadata')
    basis=inputs.record(host_reader,spec['basis_manifest'])
    host_fixture_basis=inputs.record(host_reader,spec['host_fixture_basis_manifest'])
    need(spec['basis_manifest']['sha256']==BASIS_SHA and len(basis['files'])==BASIS_DECLARED_MEMBERS
         and spec['host_fixture_basis_manifest']['sha256']==HOST_FIXTURE_BASIS_SHA
         and manifest['schema']=='root-private-shared-greedy-browser-artifact-v1'
         and manifest['release_qualified']is False and manifest['origin_basis_manifest']==spec['basis_manifest']
         and manifest['origin_host_fixture_basis_manifest']==spec['host_fixture_basis_manifest']
         and materialized['origin_host_fixture_basis_manifest']==spec['host_fixture_basis_manifest']
         and manifest['declared_basis_omissions']==materialized['declared_basis_omissions']==DECLARED_BASIS_OMISSIONS
         and all(basis['files'].get(name)==wanted for name,wanted in DECLARED_BASIS_OMISSIONS.items()),
         'Exact registered minimal-reference basis and separate frozen host fixture donor required')
    original_manifest=inputs.record(host_reader,spec['original354_manifest'])
    original=inputs.pinned(host_reader,spec['original354_runtime'])
    need(spec['original354_manifest']['sha256']==ORIGINAL_MANIFEST_SHA and digest(original)==ORIGINAL_RUNTIME_SHA
         and identity(original)==original_manifest['files']['host-app/runtime_profile.py'],'Exact qualified354 runtime context required')
    blueprint=inputs.record(host_reader,spec['fixture_blueprint']);need(spec['fixture_blueprint']['sha256']==BLUEPRINT_SHA,'Exact frozen125source/79fixture blueprint required')
    expected={name:row for name,row in basis['files'].items()if name not in DECLARED_BASIS_OMISSIONS}
    inventories={};variants={};images={};common_critical_sources=None;cli_prerequisites={}
    donor_root=str(PurePosixPath(spec['host_fixture_basis_manifest']['path']).parent)
    basis_root=str(PurePosixPath(spec['basis_manifest']['path']).parent)
    need(len(blueprint['host_file_relative_names'])==31 and len(blueprint['sampling_support_relative_names'])==94,
         'Exact31 host and94 current seeded support source slots required')
    for name in blueprint['host_file_relative_names']:
        member_name='host-app/'+name;wanted=host_fixture_basis['files'][member_name]
        inputs.read(host_reader,child(donor_root,member_name),wanted)
        expected[member_name]=wanted
    for member_name in blueprint['sampling_support_relative_names']:
        wanted=basis['files'][member_name]
        need(wanted==host_fixture_basis['files'][member_name],
             'Current94 seeded support source differs between registered basis and fixture donor')
        inputs.read(host_reader,child(basis_root,member_name),wanted)
        inputs.read(host_reader,child(donor_root,member_name),wanted)
    for variant in VARIANTS:
        reader=variant_readers[variant];layout=LAYOUT[variant];native=native_results[variant];physical=physical_results[variant];browser=browser_results[variant]
        need(reader.variant==variant and native['passed']is True and native['variant']==variant and native['epoch']==EPOCHS[variant]
             and native['native_input_files']==layout['native'],'Internally validated typed native result required')
        policy,policy_pin=inputs.role(reader,'root_policy');plan,plan_pin=inputs.role(reader,'native_plan')
        cli_prerequisites[variant]=validate_cli_prerequisite(inputs,reader,variant,
            materialized['physical_cli_prerequisites'][variant],policy_pin,physical)
        finished,finished_pin=inputs.role(reader,'native_finished');static,static_pin=inputs.role(reader,'native_static');candidate,candidate_pin=inputs.role(reader,'source_candidate')
        need(policy['schema']==POLICIES[variant]and policy['variant']==variant and policy['selected_by']=='/root'
             and policy['ready_for_sram_trial']is True and policy['flash_operations_permitted']is False and policy['automatic_retry']is False
             and policy['native_plan']==plan_pin and policy['source_candidate']==candidate_pin
             and policy['closed_records']['native']==finished_pin and policy['closed_records']['static']==static_pin,'Selected policy/native/source graph differs')
        need(plan['candidate_receipt']==candidate_pin and plan['variant']==variant and len(plan['inputs'])==layout['native']
             and finished['flow_completed']is True and finished['exit_code']==0 and finished['source_inputs_unchanged']is True
             and finished['plan_sha256']==plan_pin['sha256'] and finished['image']==native['image']==pin2(policy['image'])
             and static['passed']is True and static['image_sha256']==native['image']['sha256'],'Actual successful native/plan/image scope differs')
        bindings=materialized['actual_native_bindings'][variant]
        need(bindings==dict(policy=policy_pin,native_plan=plan_pin,image=policy['image'],actual_implemented_run_tcl=plan['inputs']['run.tcl']),'Materialization uses another native policy or Tcl')
        inventory={name:row['sha256']for name,row in plan['inputs'].items()};aggregate=digest(canonical(inventory));inventories[variant]=aggregate
        need(native['inventory_sha256']==aggregate,'Validated inventory differs from implemented Tcl inputs')
        if variant=='baseline':
            owned=inputs.json(reader,child(plan['candidate'],'OWNED-INPUTS.json'))
            need(digest(canonical(owned))==candidate['owned_inventory_sha256'],'Baseline complete owned inventory differs')
        else:owned=candidate['owned_files_after']if variant=='kv-protected'else candidate['owned_files']
        nonvendor={name for name,row in plan['inputs'].items()if not row['vendor']}
        need(len(owned)==layout['owned'] and nonvendor<=set(owned)
             and set(owned)-nonvendor==({'project/constraints/board1_fixed_product.cst.NOTICE'}if variant=='baseline'else set()),'Exact owned/native source overlay differs')
        need(len(plan['inputs'])-len(nonvendor)==4 and all(name.startswith('project/official/')for name,row in plan['inputs'].items()if row['vendor']),'Exactlyfour separately omitted vendor inputs required')
        native_root=str(PurePosixPath(plan_pin['path']).parent)
        for name,wanted in owned.items():
            actual=pin2(plan['inputs'][name])if name in plan['inputs']else wanted
            source=child(native_root,'input/'+name)if name in plan['inputs']else child(plan['candidate'],name)
            inputs.read(reader,source,actual)
            packaged=layout['hardware']+'/'+name;expected[packaged]=actual;inputs.read(reader,child(artifact,packaged),actual)
        inv_path='host-app/'+layout['inventory'];inv_raw=inputs.read(reader,child(artifact,inv_path))
        need(inv_raw==encoded(inventory),'Packaged inventory is not exact implemented source map')
        expected[inv_path]=identity(inv_raw)
        stdout=inputs.pin(reader,child(native_root,'stdout.log'));stderr=inputs.pin(reader,child(native_root,'stderr.log'))
        build=build_record(variant,inventory,policy['image'],finished,static,finished_pin,static_pin,stdout,stderr)
        build_path=layout['prebuilt']+'/BUILD.json';build_raw=inputs.read(reader,child(artifact,build_path));need(build_raw==encoded(build),'BUILD is not reviewed native-fact derivation')
        expected[build_path]=identity(build_raw);image_path=layout['prebuilt']+'/project/impl/pnr/shared_product.fs';expected[image_path]=native['image']
        inputs.read(reader,child(artifact,image_path),native['image']);images[variant]=native['image']['sha256']
        need(materialized['BUILD_files'][variant]==inputs.pin(reader,child(artifact,build_path)),'Materialization BUILD pin detached')
        prepared=inputs.record(reader,browser['prepared_inputs']);completed,completed_pin=inputs.role(reader,'browser_campaign');cli,cli_pin=inputs.role(reader,'physical_campaign')
        need(prepared['captured_manifest_reference']==CAPTURED_MANIFEST_REFERENCE
             and CAPTURED_MANIFEST_REFERENCE['logical_manifest_path']not in prepared['source_pins'],
             'Browser preparation must bind captured metadata with no live manifest unchanged input')
        for key in('physical_manifest','reference_ledger','reference_basis_manifest','helper'):
            row=CAPTURED_MANIFEST_REFERENCE[key]
            need(prepared['source_pins'].get(row['path'])==pin2(row),
                 'Browser omitted an actual physical metadata/helper reference pin')
            inputs.read(reader,row['path'],row)
        need(prepared['schema']=='greedy-browser-prepared-inputs-v2' and prepared['variant']==variant
             and prepared['image']==policy['image'] and prepared['physical_cli_record']==cli_pin
             and completed['schema']=='greedy-browser-actual-seven-case-check-v2' and completed['passed']is True
             and completed['complete']is True and completed['variant']==variant
             and completed['prepared_inputs']==browser['prepared_inputs'] and completed['image']==policy['image']
             and completed['policy']==policy_pin and completed['physical_cli_record']==cli_pin
             and completed['case_count']==7 and completed['source_inputs_unchanged']is True
             and cli['schema']=='greedy-selected-physical-campaign-v1' and cli['variant']==variant
             and cli['image']==policy['image'],'Actual raw browser/CLI identity cross-join differs')
        need(browser['schema']=='greedy-current-portable-callback-browser-replay-v3'and browser['passed']is True and browser['complete']is True
             and browser['variant']==variant and pin2(browser['image'])==native['image']
             and browser['case_count']==7 and browser['independently_checked_outputs']==26
             and browser['completed']==completed_pin and browser['physical_cli_record']==cli_pin
             and prepared['package']==artifact and prepared['policy']==policy_pin
             and prepared['shared_materialization']==spec['materialization']
             and prepared['shared_artifact_manifest']==spec['artifact_manifest']
             and prepared['build']==inputs.pin(reader,child(artifact,build_path)) and prepared['inventory_sha256']==aggregate
             and prepared['selected_hardware_root']==layout['hardware'] and prepared['selected_candidate']==plan['candidate']
             and prepared['selected_native_input_count']==layout['native'] and prepared['selected_packaged_owned_source_count']==layout['owned'],'Actualseven-browser campaign is detached from final shared graph')
        need(physical['schema']=='greedy-current-portable-byte-uart-replay-v1'and physical['passed']is True
             and physical['case_count']==10 and physical['main_reference_outputs']==395
             and physical['finished']==identity(inputs.pinned(reader,cli_pin)) and pin2(physical['image'])==native['image']
             and physical['original_plan']==cli['plan']and physical['original_raw_uart']==cli['raw_uart'],'Browser same-image CLI stage result differs')
        host_sources={name:row for name,row in prepared['source_pins'].items()if name.startswith(child(artifact,'host-app')+'/')}
        need(browser['actual_recorded_host_sources']==host_sources,'Browser recorded host source map differs')
        # Listed-pin verification alone cannot establish a source census. Bind
        # every frozen critical member, including the shared settings codec
        # outside host-app and the selected implemented inventory inside it.
        required_members=COMMON_CRITICAL_MEMBERS+(inv_path,)
        required_origins={child(artifact,name):name for name in required_members}
        need(all(origin in prepared['source_pins'] for origin in required_origins),
             'Browser omitted a required common host/settings/inventory source origin')
        common={}
        for origin,name in required_origins.items():
            wanted=prepared['source_pins'][origin]
            need(name in manifest['files'] and wanted==manifest['files'][name],
                 'Required browser critical source differs from final manifest')
            need(origin in browser['consumed_original_file_identities']
                 and browser['consumed_original_file_identities'][origin]==wanted,
                 'Browser byte replay omitted a required consumed critical source origin')
            if name.startswith('host-app/'):
                need(origin in browser['actual_recorded_host_sources']
                     and browser['actual_recorded_host_sources'][origin]==wanted,
                     'Browser result omitted a required host/inventory source origin')
            inputs.read(reader,origin,wanted);inputs.read(host_reader,origin,wanted)
            if name in COMMON_CRITICAL_MEMBERS:common[origin]=wanted
        need(len(common)==12 and (common_critical_sources is None or common==common_critical_sources),
             'Allthree browser campaigns must bind the same complete critical source graph')
        common_critical_sources=common
        for origin,wanted in host_sources.items():
            relative=str(PurePosixPath(origin).relative_to(PurePosixPath(artifact)))
            need(relative in manifest['files']and manifest['files'][relative]==wanted,'Browser host source outside final manifest')
            inputs.read(reader,origin,wanted);inputs.read(host_reader,origin,wanted)
        variants[variant]=dict(policy=policy_pin,native_plan=plan_pin,image=policy['image'],BUILD=prepared['build'],inventory_sha256=aggregate,browser_prepared=browser['prepared_inputs'],browser_completed=completed_pin,physical_campaign=cli_pin)
    need(inventories['baseline']==BASELINE_INVENTORY,'Qualified baseline implemented inventory changed')
    runtime=inputs.read(host_reader,child(artifact,'host-app/runtime_profile.py'));delta=compare_bytes(original,runtime,inventories)
    backend=inputs.read(host_reader,child(artifact,'host-app/fpga_backend.py'));ui=inputs.read(host_reader,child(artifact,'host-app/streamlit_app.py'))
    need(digest(backend)==BACKEND_SHA and digest(ui)==UI_SHA,'Reviewed shared backend/UI source changed')
    for name,raw in [('runtime_profile.py',runtime),('fpga_backend.py',backend),('streamlit_app.py',ui)]:expected['host-app/'+name]=identity(raw)
    need(manifest['files']==expected and manifest['selected_image_sha256']==images
         and materialized['declared_source_members']==len(expected) and materialized['source_delta']==delta,'Shared artifact is not reviewedV15 materializer/mixed source overlay')
    fixtures=validate_host79(inputs,host_reader,spec['host79_receipt'],artifact,spec['artifact_manifest'],manifest,blueprint,spec['basis_manifest'],spec['materializer_source'],spec['host_fixture_basis_manifest'],spec['materialization'])
    return dict(schema='greedy-current-portable-shared-host-closure-v4',passed=True,materialization=spec['materialization'],artifact_manifest=spec['artifact_manifest'],artifact_origin=artifact,variants=variants,actual_closed_cli_prerequisites=cli_prerequisites,closed_CLI_prerequisites_exact_reviewers_cross_bound=True,captured_manifest_reference=CAPTURED_MANIFEST_REFERENCE,captured_metadata_reference_joined_across_materialization_browser_and79=True,shared_prepared_materialization_context_joined=True,catalog_delta=delta,common_critical_browser_sources=common_critical_sources,required_critical_common_source_count=12,canonical_implemented_inventory_sha256=inventories,host79=fixtures,consumed_original_file_identities=inputs.consumed,release_qualified=False,current_admission=False,actual_UI_or_device_execution=False,original_paths_and_argv_rewritten=False,independent_configuration_attestation=False,unrelated_basis_members_bound_by_manifest_metadata=True,unrelated_basis_member_bytes_replayed_here=False,scope='Scoped callback byte/source/fixture/campaign association. Caller supplies internally validated native/CLI/browser stages and retains all other finalrelease obligations; no current admission follows.')
