#!/usr/bin/env python3
"""Validate the bounded seeded-sampling board record, without hardware access.

Raw wire frames, operation order, fixed known answers, CLEAR replay, rejection
behavior and host timing arithmetic are checked. Historical private simulations
are summarized, not rerun. Local hashes do not attest physical configuration.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = 'evidence/seeded-sampling/'
VARIANT = 'variants/seeded-sampling/hardware'
IMAGE = 'prebuilt/seeded-sampling/project/impl/pnr/shared_product.fs'
IMAGE_SHA = '0e6d30b68bd8757657bc1c3b949ac5b9571a0a8d1f8bb1a6e6018b241f733033'
INVENTORY_SHA = '26a0885f9ffefaeea68b948295635fcfb37367254b549c48e75e0d7093e96831'
ASSEMBLY_SHA = '0dd7a437353ddd8c77728b820f752764c924ca7768dca80939384e5614d82112'
AUDIT_SHA = 'd7018586d6dbaf2f84c2296af493bcd2cc6c574d09bcdc7284ad274266ba382d'
NATIVE_RECEIPT_SHA = '375fb79369dae1e0c2b4f738ce3b3c2690141d7af5e8317e0c68200748fd838a'
TRANSCRIPT_SHA = '867781ff037306d787423d96a676ef7dd84007d256bf96a9aaf59e3d10461e73'
SUMMARY_SHAS = {'native.json': 'a7816ecfe4051e78cf9c5a40f1edd9823ff43128137339ffbc59bebc264c77b4',
    'historical-tests.json': '0be1585a361e7f4b0873a7eb9d0ea3312ab5301bb38daedcd26d1f2890033b37'}
APP_SHA = 'd84248475fd3468df96fb2ae32b91bb908c9bf2167bbf294983557efa12f893c'
APP_STOP_WIRE_SHA = 'ecd49132cb1e536ef520f57f55ad6b572fb93d503d1a9734a0af43262829f1bc'
APP_SOURCES = {
    'host-app/streamlit_app.py': '49342547979bc8f4e4f805b81fdfb99771c45bf8445a91ca9fc7a3e3ee95effa',
    'host-app/fpga_backend.py': 'cd8a3c64dd6211d5d866666cda57132fa0f140723ceee013849c894fa3457171',
    'host-app/runtime_profile.py': 'ef74d1c2a15c83814553377592b2a1db84e6ab5bfdd1fb54c87f6ffb49fa7e32',
    'host-app/qualify_board.py': '9e590c6ec49fe2ce02b3c6eb711e2971d53186d36dbbb9205e32f888a96cc6ee',
    'host-app/sampling_protocol.py': 'e754440e991e3a84ea246292080be9a955957be6bedbc6a82ed38a67c54fae75',
    'host-app/token_machine_uart.py': '00d18e9411d52f7d7414b96cbf28d29db38d1c5008705dfb4194f268cbb11cbf',
    'host-app/uart_channel.py': 'b56f591d546bbc55ad0b8de3d6a5aa179206a3b5c813a6da1ce86aca4a2e3c0e'}
# Preserve the exact frontend used by the historical AppTest. The later copies
# clarify protection and qualification labels; the ordinary-browser campaign
# records their current revisions separately. The five other app sources are exact.
APP_FRONTEND_ARCHIVE = 'evidence/seeded-sampling/app-tested-sources/streamlit_app.py.txt'
APP_PROFILE_ARCHIVE = 'evidence/seeded-sampling/app-tested-sources/runtime_profile.py.txt'
APP_CURRENT_PROFILE_SHA = '8921585f9d3b2b3643f099797d884eb4f315ee19ecf3bb409c9be8c5ede8d7f2'
APP_CURRENT_FRONTEND_SHA = '1755664f718fe29b91b510b5aa6b95ad79c9a8dbf05289e44005495f174ca844'

SEED_A = 0x99aabbccddeeff001122334455667788
SEED_B = 0xfefdfcfbfaf9f8f70102030405060708
TEMPERATURES = ('0', '0.5', '1', '2')
GOLDENS = ((200, 15, 103), (247, 130, 32), (357, 3898, 104), (3436, 4007, 141))
# The tail is a frozen board observation; only its first three tokens were
# checked against an independent model reference during the board campaign.
PERFORMANCE_TOKENS = [357,3898,104,98,15,3,164,1612,295,646,14,585,3734,823,2,3,
    85,1362,474,94,196,120,127,1197,15,140,111,1655,85,1259,109,65,62,81,390,145,
    13,111,229,32,3640,136,115,342,2543,444,98,15,282,1627,139,120,860,93,2925,
    222,32,1246,1482,13,94,85,1362,609]
SCOPE = ('One Tang Mega 138K non-Pro Dock bounded UART campaign, one prompt token, fixed public seeds. '
    'Source and local image hashes plus SRAM loader receipt identify artifacts; no independent '
    'physical configuration attestation.')


def require(ok, message):
    if not ok:
        raise ValueError(message)


def fields(value, names):
    require(type(value) is dict and set(value) == set(names.split()), 'Unexpected evidence fields')


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(',', ':')) + '\n').encode()


def positive(value):
    require(type(value) in (int, float) and math.isfinite(value) and value > 0, 'Invalid duration')


def equal_number(value, expected):
    positive(value)
    require(math.isclose(value, expected, rel_tol=1e-12, abs_tol=1e-12), 'Timing arithmetic differs')


def crc8(data):
    crc = 0
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = ((crc << 1) ^ (7 if crc & 128 else 0)) & 255
    return crc


def frame(body):
    return (body + bytes([crc8(body)])).hex()


def legacy(opcode, token=0):
    return frame(bytes([0xa5, opcode, token & 255, token >> 8]))


def settings(code, seed):
    return frame(bytes([0xa5, 3, code]) + seed.to_bytes(16, 'little'))


def reply(kind, operand=0):
    return frame(bytes([0x5a, kind, operand & 255, operand >> 8]))


def expected_trace():
    """The complete finite wire plan, including the two deliberately overlapping sends."""
    rows = []
    def wire(event, label, raw):
        rows.append(dict(event=event, label=label, frame_hex=raw))
    def operation(label, kind, operand=0):
        rows.append(dict(event='operation', label=label, response_kind=kind, operand=operand))
    def transact(label, raw, kind, operand=0):
        wire('tx', label, raw); wire('rx', label, reply(kind, operand)); operation(label, kind, operand)
    def clear(label): transact(label, legacy(2), 0x82)
    def append(label): transact(label, legacy(0, 378), 0x80)
    def step(label, token): transact(label, legacy(1), 0x81, token)
    def configure(label, code, seed): transact(label, settings(code, seed), 0x83, code)
    def begin(label, code, seed):
        clear(label + '/clear'); configure(label + '/settings', code, seed); append(label + '/append')
    def quiet(label): rows.append(dict(event='wire_quiet', label=label, requested_seconds=.1))
    label = 'owner-loaded-reset-default'
    clear(label + '/clear'); append(label + '/append')
    for i, token in enumerate(GOLDENS[0], 1): step(f'{label}/step-{i}', token)
    clear(label + '/final-clear')
    for code, temperature in enumerate(TEMPERATURES):
        label = 'seed-a/T=' + temperature
        begin(label, code, SEED_A)
        for i, token in enumerate(GOLDENS[code], 1): step(f'{label}/step-{i}', token)
        clear(label + '/replay-clear'); append(label + '/replay-append')
        for i, token in enumerate(GOLDENS[code], 1): step(f'{label}/replay-{i}', token)
    for name, seed in [('zero', 0), ('all-ones', (1 << 128)-1)]:
        label = 'greedy-seed-' + name
        begin(label, 0, seed)
        for i, token in enumerate(GOLDENS[0], 1): step(f'{label}/step-{i}', token)
    for code, token in [(1, 13), (2, 13), (3, 2)]:
        label = 'seed-b/T=' + TEMPERATURES[code]
        begin(label, code, SEED_B); step(label + '/step-1', token)
    label = 'invalid-settings'
    clear(label + '/clear'); configure(label + '/valid-settings', 2, SEED_A)
    bad = bytearray.fromhex(settings(0, 0)); bad[-1] ^= 1
    transact(label + '/bad-crc', bad.hex(), 0xcf)
    transact(label + '/invalid-temperature', settings(255, 0), 0xc3)
    append(label + '/append')
    transact(label + '/nonempty-rejection', settings(0, 0), 0xc3)
    step(label + '/preserved-first', 357); step(label + '/preserved-second', 3898)
    label = 'settings-behind-step'
    begin(label, 2, SEED_A)
    wire('tx', label + '/step', legacy(1)); wire('tx', label + '/settings', settings(0, 0))
    wire('rx', label + '/step', reply(0x81, 357)); operation(label + '/step', 0x81, 357)
    quiet(label + '/no-deferred-settings')
    rows.append(dict(event='settings_race', outcome='discarded_or_no_reply',
        wire_completion_during_model_busy_observed=False))
    step(label + '/preserved-continuation', 3898)
    label = 'step-clear'
    begin(label, 2, SEED_A)
    wire('tx', label + '/step', legacy(1)); wire('tx', label + '/clear', legacy(2))
    wire('rx', label, reply(0x82))
    rows.append(dict(event='step_clear_race', completed_before_clear=[], internal_owned_read_at_clear_observed=False))
    quiet(label + '/drained-wire'); append(label + '/drain-and-replay-append')
    for i, token in enumerate(GOLDENS[2], 1): step(f'{label}/replay-{i}', token)
    quiet('kat/final-no-extra-replies')
    label = 'performance/T=1'
    begin(label, 2, SEED_A)
    for i, token in enumerate(PERFORMANCE_TOKENS, 1): step(f'{label}/step-{i}', token)
    quiet('performance/final-no-extra-replies')
    return rows


def validate_transcript(rows):
    """Semantic validation is separate from its fixed archive hash for mutation tests."""
    expected = expected_trace()
    require(type(rows) is list and len(rows) == len(expected) == 493, 'Wire event census differs')
    previous = -1
    sends = {}
    perf_seconds = []
    for index, (row, want) in enumerate(zip(rows, expected), 1):
        dynamic = {'sequence', 'elapsed_ns'}
        if want['event'] in ('operation', 'wire_quiet', 'step_clear_race'): dynamic.add('seconds')
        if want['event'] in ('settings_race', 'step_clear_race'): dynamic.add('queued_after_step_seconds')
        require(set(row) == set(want) | dynamic, 'Unexpected transcript fields')
        require({k: v for k, v in row.items() if k not in dynamic} == want,
            'Command/reply plan, seed, temperature, token, replay or rejection differs')
        require(type(row['sequence']) is int and row['sequence'] == index, 'Wire event order differs')
        ns = row['elapsed_ns']
        require(type(ns) is int and ns > previous and (index != 1 or ns == 0), 'Invalid monotonic timeline')
        previous = ns
        if row['event'] in ('tx', 'rx'):
            packet = bytes.fromhex(row['frame_hex'])
            require(packet[0] == (0xa5 if row['event'] == 'tx' else 0x5a), 'Frame magic differs')
            require(len(packet) == (20 if row['event'] == 'tx' and packet[1] == 3 else 5), 'Frame length differs')
            crc_ok = crc8(packet[:-1]) == packet[-1]
            require(crc_ok == (row['label'] != 'invalid-settings/bad-crc' or row['event'] == 'rx'), 'Frame CRC differs')
            if row['event'] == 'tx': sends[row['label']] = ns
        if 'seconds' in dynamic:
            positive(row['seconds'])
        if row['event'] == 'operation':
            measured = (ns - sends[row['label']]) / 1e9
            # Recorder timestamps bracket slightly different statements than
            # time.monotonic(); retain a 1ms cross-check, not clock equality.
            require(abs(row['seconds'] - measured) < .001, 'Operation duration disagrees with timeline')
            if row['label'].startswith('performance/T=1/step-'): perf_seconds.append(row['seconds'])
        if row['event'] == 'wire_quiet':
            require(.1 <= row['seconds'] < .2, 'Quiet observation duration differs')
        if 'queued_after_step_seconds' in dynamic:
            positive(row['queued_after_step_seconds'])
            require(row['queued_after_step_seconds'] < .001, 'Host overlap sequencing differs')
    require(len(perf_seconds) == 64, 'Performance duration count differs')
    return perf_seconds


def check_bindings(package):
    """Hash all distributable native inputs, plus any separately fetched vendor files."""
    package = Path(package)
    inventory = json.loads((package/'host-app/hardware-inputs-seeded-sampling.json').read_bytes())
    require(type(inventory) is dict and len(inventory) == 91 and sha(canonical(inventory)) == INVENTORY_SHA,
        'Frozen 91-input inventory differs')
    vendor = 0
    for name, digest in inventory.items():
        path = PurePosixPath(name)
        require(not path.is_absolute() and '..' not in path.parts, 'Unsafe input path')
        target = package/VARIANT/name
        if name.startswith('project/official/'):
            vendor += 1
            if not target.exists(): continue
        require(target.is_file() and not target.is_symlink() and sha(target.read_bytes()) == digest,
            'Frozen native input differs: ' + name)
    require(vendor == 4, 'Vendor dependency census differs')
    image = package/IMAGE
    require(image.is_file() and not image.is_symlink() and image.stat().st_size == 41202015
        and sha(image.read_bytes()) == IMAGE_SHA, 'Tested prebuilt image differs')
    build = json.loads((package/'prebuilt/seeded-sampling/BUILD.json').read_bytes())
    for key, want in dict(schema='fixed-fpga-local-build-v1', variant='seeded-sampling',
        hardware_inputs_sha256=INVENTORY_SHA, image_sha256=IMAGE_SHA, image_bytes=41202015,
        image_relative_path='project/impl/pnr/shared_product.fs', exit=0, flow_completed=True,
        source_inputs_verified=True, source_inputs_unchanged=True, timing_qualified=False,
        original_build_receipt_sha256=NATIVE_RECEIPT_SHA, native_timing_inspection_sha256=AUDIT_SHA).items():
        require(build.get(key) == want, 'Build/source evidence binding differs: ' + key)


def qualifier_plan():
    """Independent literal fixture plan for the later 45-operation host qualifier."""
    plan = [('clear',0,None,None), ('settings',0,None,0), ('append',378,None,None)]
    plan += [('step',0,t,None) for t in (200,15,103,157)]
    plan += [('clear',0,None,None)]
    for code in (1,2,3):
        plan += [('settings',code,None,SEED_A), ('append',378,None,None)]
        plan += [('step',0,t,None) for t in GOLDENS[code]]
        plan += [('clear',0,None,None)]
        if code == 2:
            plan += [('append',378,None,None)] + [('step',0,t,None) for t in GOLDENS[2]]
            plan += [('clear',0,None,None)]
    for code, token in ((1,13),(2,13),(3,2)):
        plan += [('settings',code,None,SEED_B), ('append',378,None,None),
                 ('step',0,token,None), ('clear',0,None,None)]
    return plan + [('settings',0,None,0), ('clear',0,None,None)]


def transaction(operation, operand, token=None, seed=None):
    if operation == 'settings':
        tx, rx = settings(operand, seed), reply(0x83, operand)
    else:
        opcode = {'append':0,'step':1,'clear':2}[operation]
        tx, rx = legacy(opcode, operand), reply(0x80+opcode, token if operation == 'step' else 0)
    return dict(tx_hex=tx,rx_hex=rx)


def validate_app_stop(supplement, package, wire_rows=None):
    fields(supplement, 'schema passed image_sha256 source_sha256 before_stop stopped resumed '
        'wire source_receipts counts claims')
    require(supplement['schema'] == 'seeded-app-stop-after-output-v1'
        and supplement['passed'] is True and supplement['image_sha256'] == IMAGE_SHA
        and supplement['source_sha256'] == APP_SOURCES, 'Stop supplement source/image differs')
    def result(state, generated, *, code=2, requested=64, clear=True):
        return dict(state=state,prompt_tokens=[378],uploaded=1,requested=requested,generated=generated,
            temperature=TEMPERATURES[code],seed=f'0x{SEED_A:032x}' if code else None,
            seed_used=bool(code),sampling_settings_applied=True,clear_acknowledged=clear)
    stopped_tokens = [357,3898,104,98,15,3,164,1612,295,646,14,585,3734]
    require(supplement['before_stop'] == result('generating',[357],clear=False),
        'Stop was not observed after output while generating')
    require(supplement['stopped'] == result('stopped',stopped_tokens)
        and 0 < len(stopped_tokens) < 64 and stopped_tokens[:3] == list(GOLDENS[2]),
        'Stopped positive-temperature output or final CLEAR differs')
    require(supplement['resumed'] == result('complete',[200,15,103],code=0,requested=3),
        'Greedy restart after generation Stop differs')
    require(supplement['wire'] == dict(path=EVIDENCE+'app-stop.jsonl',sha256=APP_STOP_WIRE_SHA,
        records=48,elapsed_time_rebased=True,raw_frames_preserved=True), 'Stop wire archive identity differs')
    if wire_rows is None:
        raw = (Path(package)/(EVIDENCE+'app-stop.jsonl')).read_bytes()
        require(sha(raw) == APP_STOP_WIRE_SHA, 'Stop wire archive hash differs')
        wire_rows = [json.loads(line) for line in raw.splitlines()]
    expected = []
    for name,code,tokens in [('stopped',2,stopped_tokens),('resumed',0,[200,15,103])]:
        commands = [transaction('clear',0),transaction('settings',code,seed=SEED_A if code else 0),
                    transaction('append',378)] + [transaction('step',0,t) for t in tokens]
        commands += [transaction('clear',0)]
        for command in commands:
            expected += [dict(run=name,event='tx',frame_hex=command['tx_hex']),
                         dict(run=name,event='rx',frame_hex=command['rx_hex'])]
    require(type(wire_rows) is list and len(wire_rows) == len(expected) == 48, 'Stop wire census differs')
    previous = -1
    for i,(row,want) in enumerate(zip(wire_rows,expected),1):
        fields(row,'sequence run event frame_hex elapsed_ns')
        require({k:v for k,v in row.items() if k not in ('sequence','elapsed_ns')} == want,
            'Stop/resume command sequence, token, explicit greedy SETTINGS or final CLEAR differs')
        require(type(row['sequence']) is int and row['sequence'] == i
            and type(row['elapsed_ns']) is int and row['elapsed_ns'] > previous
            and (i != 1 or row['elapsed_ns'] == 0), 'Stop wire timeline differs')
        previous = row['elapsed_ns']
        packet = bytes.fromhex(row['frame_hex'])
        require(crc8(packet[:-1]) == packet[-1], 'Stop wire CRC differs')
    fields(supplement['source_receipts'],'stop_receipt_sha256 stopped_uart_sha256 resumed_uart_sha256')
    for value in supplement['source_receipts'].values():
        require(type(value) is str and len(value) == 64 and all(c in '0123456789abcdef' for c in value),
            'Invalid Stop provenance digest')
    require(supplement['counts'] == dict(stopped_outputs=13,resumed_outputs=3,
        stopped_known_answer_prefix=3,resumed_known_answers=3,supplementary_exact_checks=6),
        'Supplementary known-answer scope differs')
    require(supplement['claims'] == dict(ui_rendered_with_streamlit_apptest=True,
        physical_fpga_backend=True,mocked_uart=False,listening_server_started=False,
        browser_automation=False,software_inference=False,stop_requested_after_output_observed=True,
        internal_inflight_command_at_click_observed=False,stop_final_clear_acknowledged=True,
        stop_released_connection=True,disconnect_released_connection=True,flash_modified=False),
        'Unsupported generation Stop claim')


def validate_app(app, package):
    fields(app, 'schema passed scope image_sha256 source_sha256 codec_source source_receipts '
        'qualification cases stop resume counts lifecycle claims stopped_after_generation')
    require(app['schema'] == 'seeded-sampling-physical-app-v1' and app['passed'] is True
        and app['image_sha256'] == IMAGE_SHA and app['scope'] ==
        'Streamlit AppTest rendered form and real FPGA backend using the qualified seeded image; no mocked UART, listening server or browser automation.',
        'App rehearsal identity or scope differs')
    require(app['source_sha256'] == APP_SOURCES, 'App-qualified seven-source inventory differs')
    codec = dict(path='variants/seeded-sampling/tools/settings_codec.py',
        sha256='6e2f5cf5310700888187d3d4d9af1921e2150adbe865773874bdbe7eaecc326a')
    require(app['codec_source'] == codec, 'App settings codec identity differs')
    for path, digest in dict(APP_SOURCES, **{codec['path']:codec['sha256']}).items():
        target = Path(package)/path
        if path in ('host-app/streamlit_app.py', 'host-app/runtime_profile.py'):
            current_digest = APP_CURRENT_FRONTEND_SHA if path.endswith('/streamlit_app.py') else APP_CURRENT_PROFILE_SHA
            archive = APP_FRONTEND_ARCHIVE if path.endswith('/streamlit_app.py') else APP_PROFILE_ARCHIVE
            require(target.is_file() and not target.is_symlink()
                and sha(target.read_bytes()) == current_digest,
                'Current app copy revision changed without its browser qualification: '+path)
            target = Path(package)/archive
        require(target.is_file() and not target.is_symlink() and sha(target.read_bytes()) == digest,
            'Historical AppTest source bytes changed: '+path)
    fields(app['source_receipts'], 'app_sha256 runner_sha256 profile_sha256')
    for value in app['source_receipts'].values():
        require(type(value) is str and len(value) == 64 and all(c in '0123456789abcdef' for c in value),
            'Invalid app provenance digest')
    qual = app['qualification']
    fields(qual, 'operations exact_token_checks generated_tokens known_answer transactions '
        'build_receipt_sha256 hardware_inputs_sha256 source_uart_sha256')
    plan = qualifier_plan()
    output = [token for op,operand,token,seed in plan if op == 'step']
    require(len(plan) == 45 and len(output) == 19 and qual['operations'] == 45
        and qual['exact_token_checks'] == 19 and qual['generated_tokens'] == output,
        'Separate qualifier output census differs')
    require(type(qual['transactions']) is list and len(qual['transactions']) == 45, 'Qualifier sequence truncated')
    for row, (operation,operand,token,seed) in zip(qual['transactions'],plan):
        want = dict(operation=operation,operand=operand,token=token,
                    **transaction(operation,operand,token,seed))
        if operation == 'settings': want['seed'] = f'0x{seed:032x}'
        require(row == want, 'Qualifier operation, seed, temperature, token, replay or raw frame differs')
        for field in ('tx_hex','rx_hex'):
            packet = bytes.fromhex(row[field])
            require(crc8(packet[:-1]) == packet[-1], 'Qualifier frame CRC differs')
    require(qual['hardware_inputs_sha256'] == INVENTORY_SHA
        and qual['build_receipt_sha256'] == sha((Path(package)/'prebuilt/seeded-sampling/BUILD.json').read_bytes())
        and qual['source_uart_sha256'] == 'b4d7520027b0ee0925087db97ffdc49fac58bb382e1cd8c95576ba6d70d69db5',
        'Qualifier build/source binding differs')
    require(qual['known_answer'] == dict(protocol='seeded-sampling-v1',prompt_tokens=[378],
        greedy_generated_tokens=[200,15,103,157],seed_a=f'0x{SEED_A:032x}',seed_b=f'0x{SEED_B:032x}',
        positive_generated_tokens={t:list(GOLDENS[c]) for c,t in enumerate(TEMPERATURES) if c},
        clear_replay_temperature='1',clear_replay_generated_tokens=[357,3898,104],
        changed_seed_first_tokens={'0.5':13,'1':13,'2':2},initial_clear_acknowledged=True,
        final_clear_acknowledged=True,final_greedy_settings_acknowledged=True,exact_token_checks=19),
        'Qualifier known-answer scope differs')
    specs = [('seed-a-temperature-1',2,SEED_A,[357,3898,104],[357,3898,104]),
        ('seed-a-repeat-temperature-1',2,SEED_A,[357,3898,104],[357,3898,104]),
        ('greedy-after-sampling',0,None,[200,15,103],[200,15,103]),
        ('seed-a-temperature-0.5',1,SEED_A,[247,130,32],[247,130,32]),
        ('seed-a-temperature-2',3,SEED_A,[3436,4007,141],[3436,4007,141]),
        ('changed-seed',2,SEED_B,[13],[13]),
        ('automatic-seed-1',2,0x2afbb0c0eb4cf96777809d822953c152,[14],None),
        ('automatic-seed-2',2,0x1ee736c4ad172c246ac7a50de1bc69ac,[15],None)]
    require(type(app['cases']) is list and len(app['cases']) == 8, 'UI case census differs')
    def check_case(row, label, code, seed, tokens, expected, stopped=False):
        fields(row, 'label prompt_tokens generated_tokens expected_tokens temperature seed seed_used '
            'sampling_settings_applied requested uploaded state clear_acknowledged commands source_log_sha256')
        want = dict(label=label,prompt_tokens=[378],generated_tokens=tokens,expected_tokens=expected,
            temperature=TEMPERATURES[code],seed=None if seed is None else f'0x{seed:032x}',
            seed_used=code != 0,sampling_settings_applied=True,requested=64 if stopped else len(tokens),
            uploaded=0 if stopped else 1,state='stopped' if stopped else 'complete',clear_acknowledged=True)
        require(all(row[key] == value for key,value in want.items()), 'UI case, replay, automatic seed or Stop result differs')
        commands = [transaction('clear',0),transaction('settings',code,seed=seed or 0)]
        if not stopped:
            commands += [transaction('append',378)] + [transaction('step',0,t) for t in tokens]
        commands += [transaction('clear',0)]
        require(row['commands'] == commands, 'UI wire sequence or explicit greedy SETTINGS differs')
        digest = row['source_log_sha256']
        require(type(digest) is str and len(digest) == 64 and all(c in '0123456789abcdef' for c in digest), 'Invalid UI log digest')
    for row,spec in zip(app['cases'],specs): check_case(row,*spec)
    check_case(app['stop'],'stop',2,SEED_A,[],None,True)
    check_case(app['resume'],'greedy-resume',0,None,[200,15,103],[200,15,103])
    require(app['cases'][6]['seed'] != app['cases'][7]['seed'], 'Blank-seed runs did not choose distinct seeds')
    require(app['counts'] == dict(ui_returned_tokens=21,ui_exact_token_checks=19,
        automatic_seed_observed_tokens=2,separate_qualifier_exact_token_checks=19), 'UI model-check census differs')
    require(app['lifecycle'] == dict(connection_retained_between_complete_cases=True,
        stop_released_connection=True,disconnect_released_connection=True,stop_before_prompt_upload=True),
        'Stop/Disconnect scope differs')
    require(app['claims'] == dict(ui_rendered_with_streamlit_apptest=True,physical_fpga_backend=True,
        mocked_uart=False,listening_server_started=False,browser_automation=False,software_inference=False,
        flash_modified=False,timing_qualified=False,full_context_qualified=False,
        physical_configuration_attested=False,inflight_step_stop_tested=False), 'Unsupported app rehearsal claim')
    validate_app_stop(app['stopped_after_generation'],package)


def validate(data, package):
    package = Path(package)
    fields(data, 'schema passed scope campaign_started_utc campaign_finished_utc image source load '
        'reference counts transcript performance observations limits summaries')
    require(data['schema'] == 'seeded-sampling-board-v1' and data['passed'] is True
        and data['scope'] == SCOPE, 'Wrong trial scope')
    require(data['campaign_started_utc'] == '2026-10-23T04:10:44.015232+00:00'
        and data['campaign_finished_utc'] == '2026-10-23T04:10:55.188459+00:00', 'Trial identity differs')
    require(data['image'] == dict(path=IMAGE, sha256=IMAGE_SHA, bytes=41202015), 'Image identity differs')
    require(data['source'] == dict(inventory_path='host-app/hardware-inputs-seeded-sampling.json',
        inventory_sha256=INVENTORY_SHA, native_inputs=91, distributable_inputs=87,
        separately_acquired_vendor_inputs=4, assembly_receipt_sha256=ASSEMBLY_SHA,
        frozen_manifest_sha256='8d290b723afe8d569e1570dc8fa3fa7527e6e2feff180f1a2f9b013e9114303c'), 'Source identity differs')
    require(data['load'] == dict(sram_load_reported=True, flash_modified=False,
        configuration_independently_attested=False, image_sha256=IMAGE_SHA, programmer_exit=0,
        seconds=21.848207500006538, load_finished_utc='2026-10-23T04:09:33.340866+00:00',
        source_receipt_sha256='5f81743b6447bf59b3475927fd6bfd77040d5d906a86af9c00eacf4607103afe',
        programmer_stdout_sha256='d771a5bcb072cdbeb965b422100c743f741d2aecc2ccbbe33f178deaccca61eb'), 'SRAM load receipt differs')
    require(data['reference'] == dict(prompt_tokens=[378], seed_a=f'0x{SEED_A:032x}',
        seed_b=f'0x{SEED_B:032x}', seed_a_goldens={t:list(g) for t,g in zip(TEMPERATURES,GOLDENS)},
        seed_b_first={'0.5':13,'1':13,'2':2},
        model_image_sha256='cad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0',
        performance_reference_checked_prefix=3, performance_tail_is_observation_only=True), 'Reference scope differs')
    require(data['counts'] == dict(exact_token_checks=46, startup_exact_checks=3, kat_exact_checks=40,
        performance_exact_checks=3, returned_tokens=107, performance_outputs=64, prompt_fixtures=1,
        tx_frames=164, rx_frames=162), 'Trial census differs')
    require(data['transcript'] == dict(path=EVIDENCE+'uart.jsonl', sha256=TRANSCRIPT_SHA, records=493,
        source_acceptance_sha256='3aad5712d4555d76409de2f9fcce770d7b4a4b5779b58571ca798dc44ed141fa',
        source_runner_sha256='aef09046e68c32920dba58c6f05b8ce22e83ed6a74dfa3787d3b4381b2fcde9e',
        source_transport_sha256='00d18e9411d52f7d7414b96cbf28d29db38d1c5008705dfb4194f268cbb11cbf',
        elapsed_time_rebased=True, raw_frames_preserved=True), 'Transcript provenance differs')
    raw = (package/(EVIDENCE+'uart.jsonl')).read_bytes()
    require(sha(raw) == TRANSCRIPT_SHA, 'Frozen UART archive differs')
    rows = [json.loads(line) for line in raw.splitlines()]
    durations = validate_transcript(rows)
    perf = data['performance']
    fields(perf, 'temperature seed generated_tokens first_step_seconds cached_steps cached_command_seconds '
        'cached_command_tokens_per_second scope command_seconds')
    require(perf['temperature'] == '1' and perf['seed'] == f'0x{SEED_A:032x}'
        and perf['generated_tokens'] == PERFORMANCE_TOKENS and perf['cached_steps'] == 63
        and perf['command_seconds'] == durations
        and perf['scope'] == 'Host command/reply wall times, including evidence recording; one fixture.',
        'Performance workload differs')
    equal_number(perf['first_step_seconds'], durations[0])
    equal_number(perf['cached_command_seconds'], sum(durations[1:]))
    equal_number(perf['cached_command_tokens_per_second'], 63/sum(durations[1:]))
    equal_number(perf['first_step_seconds'], .08538200000475626)
    equal_number(perf['cached_command_seconds'], 6.097466498045833)
    require(data['observations'] == dict(startup_settings_sent=False, harness_reset=False,
        clear_rewinds_seed_without_settings=True, greedy_seed_zero_and_all_ones=True,
        bad_crc_rejected=True, invalid_temperature_rejected=True, nonempty_settings_rejected=True,
        settings_queued_behind_step_outcome='discarded_or_no_reply', step_clear_completed_tokens=[],
        no_extra_reply_quiet_intervals=4), 'Wire observation scope differs')
    require(data['limits'] == {key:False for key in ('full_context_qualified', 'timing_qualified',
        'formal_extension_proved', 'browser_qualified', 'physical_fault_injection',
        'internal_busy_edges_observed', 'internal_clear_owned_reads_observed', 'logic_reset_tested',
        'independent_physical_randomness', 'feature_complete')}, 'Unsupported qualification claim')
    require(data['summaries'] == SUMMARY_SHAS, 'Historical summary identities differ')
    for name, digest in SUMMARY_SHAS.items():
        require(sha((package/(EVIDENCE+name)).read_bytes()) == digest, 'Historical summary changed: ' + name)
    check_bindings(package)
    app_raw = (package/(EVIDENCE+'app.json')).read_bytes()
    require(sha(app_raw) == APP_SHA, 'Frozen app rehearsal archive differs')
    validate_app(json.loads(app_raw),package)
    return dict(passed=True, hardware_access=False, wire_frames_checked=326, returned_tokens=107,
        exact_token_checks=46, prompt_fixtures=1, performance_outputs=64,
        cached_command_tokens_per_second=63/sum(durations[1:]), timing_qualified=False,
        physical_configuration_attested=False, historical_simulations_rerun=False,
        separate_app_exact_token_checks=19,separate_qualifier_exact_token_checks=19,
        app_stop_supplementary_exact_checks=6,app_stop_observed_outputs=13,
        app_listening_server_tested=False,app_browser_automation=False)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', type=Path, default=ROOT)
    args = parser.parse_args()
    print(json.dumps(validate(json.loads((args.package/(EVIDENCE+'receipt.json')).read_bytes()), args.package), indent=2))
