#!/usr/bin/env python3
"""Offline replay of the published physical model-replacement observations.

Reconstruct signed models and programmed blocks from public model data; check
raw UART frames, real LMS grants, model/nonce bindings, numerical fixtures and
recorded readback receipts. Full flash arrays are private. Optional arguments
recompute numerical references or compare original private full-array captures.
No network, programming, solver, simulator or hardware access is performed.
"""
from pathlib import Path
import argparse, hashlib, json, sys

ROOT = Path(__file__).resolve().parents[1]
DEMO = ROOT.parents[1]
SIGNED = ROOT.parent / 'signed-update/tang'
sys.path.insert(0, str(SIGNED / 'reference'))
import signed_update as su, tang_image as tang
sys.path.insert(0, str(ROOT / 'reference'))
from home_auth import parse_request, DEVICE_ID, GRANT_BYTES, REQUEST_BYTES
from serial_client import crc8

IMAGE_SHA = {'A': 'cad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0',
             'B': '1ada1d7dfbbae137f8747945a7144a84428f2d1d6135afa13c071ab67e7f05ce'}
PACKAGE_SHA = {'A': '05fd261a9fc79a9fd3acaedc53e7b996e0f402e97363281b017632dc837d6342',
               'B': 'c9b863b0f054fb71b7265260ebc809b926b9e151365851f111132e425edc064b'}
ARRAY_SHA = {'A': '42dd0490e2f34317d3749aa24409a53ef1da4e2fa57e0d47c685be2440306854',
             'B': '90ef4eaaaec1543997dfa6fbca3f899f147a89cbf9f5de59d69ff2ae6d7afe6c'}
FPGA_SHA = 'cb0f7d60bbedca7ec504973d26f5093445049a4dbac3435df591231c2ae1922e'
RESTORE_SHA = '4545bd0b0c4076eaea8358d547b19ff0176952417daa0e0f07d1c346aee5fee2'

def read(p):
    return json.loads(p.read_text())

def digest(data):
    return hashlib.sha256(data).hexdigest()

def sha(p):
    return digest(p.read_bytes())

def member(root, name):
    path = Path(name)
    assert not path.is_absolute() and '..' not in path.parts
    return root / path

def verify_grant(grant, key):
    assert len(grant) == GRANT_BYTES
    fields = parse_request(grant[:REQUEST_BYTES])
    assert su.lms_verify(key, grant[:REQUEST_BYTES], grant[REQUEST_BYTES:])
    return fields, int.from_bytes(grant[REQUEST_BYTES:REQUEST_BYTES + 4], 'big')

def capture_integrity(out):
    copies = read(out / 'PUBLIC-COPIES.json')['files']
    for name, row in copies.items():
        assert sha(member(out, name)) == row['public_sha256'], name
    for name, expected in read(out / 'EVIDENCE-AUDIT.json')['source_hashes'].items():
        assert sha(member(out, name)) == expected, name
    for name, expected in read(out / 'HOST-SOURCES.json').items():
        assert sha(member(ROOT / 'reference', name)) == expected, name

def signed_models(out):
    base = (DEMO / 'assets/board1-real-semantic-image2048.bin').read_bytes()
    assert digest(base) == IMAGE_SHA['A'] and len(base) == su.IMAGE_BYTES
    changed = bytearray(base)
    changed[214250 * 32:214260 * 32] = bytes(320)
    images = {'A': base, 'B': bytes(changed)}
    roots, blocks, slots = {}, {}, {}
    for label, image in images.items():
        assert digest(image) == IMAGE_SHA[label]
        prefix = (out / ('model-' + label + '-signed-prefix.bin')).read_bytes()
        assert len(prefix) == 115396
        package = prefix + image
        assert digest(package) == PACKAGE_SHA[label]
        info = tang.validate_tang(package, [su.DemoAuthority(i).public_key for i in range(3)])
        assert info['version'] == {'A': 1, 'B': 2}[label] and info['signers'] == 2
        roots[label] = info['model_root']
        slots[label] = prefix.ljust(tang.SLOT_BYTES, b'\xff')
        blocks[label] = {0xe80000: image[0xe80000 - tang.MODEL_BASE:0xe90000 - tang.MODEL_BASE],
                         0xf00000: slots[label][:65536]}
        ref = read(out / ('model-' + label + '-reference.json'))
        assert ref['image_sha256'] == IMAGE_SHA[label] and ref['prompt_tokens'] == [378]
        assert ref['output_count'] == 128 and ref['decoding'] == 'greedy'
        expected = read(DEMO / 'tests/reference-cases.json')['around128']['generated_tokens'] if label == 'A' else [0] * 128
        assert ref['generated_tokens'] == expected
    return roots, images, slots, blocks

def installation_receipts(out, images, slots, blocks, private_workspace=None):
    for name in ['backup-read1.json', 'backup-read2.json']:
        receipt = read(out / name)
        assert receipt['status'] == 'PASS' and receipt['array_write'] is False
        assert receipt['bytes'] == 16777216 and receipt['sha256'] == ARRAY_SHA['A']
    backups = read(out / 'BACKUPS.json')
    assert backups['result'] == 'PASS' and backups['independently_initiated_reads'] == 2
    assert backups['sha256'] == ARRAY_SHA['A']
    for label, name in [('B', 'B-readback'), ('A', 'A-restored-readback')]:
        receipt = read(out / (name + '.bin.json'))
        assert receipt['status'] == 'PASS' and receipt['bytes'] == 16777216
        assert receipt['array_write'] is False and receipt['expected_array_equal'] is True
        assert receipt['sha256'] == ARRAY_SHA[label]
        assert receipt['log_sha256'] == sha(out / (name + '.bin.log'))
        assert receipt['tool_sha256'] == 'f880eb583695f8056566da308248ba539a1a1c4cabb6305c3d801acfd58f9e1b'
        cmd = receipt['command']
        assert '--dump-flash' in cmd and '-f' not in cmd and cmd[cmd.index('--ftdi-serial') + 1] == '2025030317'
    wanted, blockpins = [], {}
    for before, after, direction in [('A', 'B', 'A-to-B'), ('B', 'A', 'B-to-A')]:
        plan = read(out / (direction + '-BLOCK-PLAN.json'))
        assert plan['before_sha256'] == ARRAY_SHA[before] and plan['candidate_sha256'] == ARRAY_SHA[after]
        assert [(r['address'], r['bytes']) for r in plan['writes']] == [(0xe80000, 65536), (0xf00000, 65536)]
        for row in plan['writes']:
            expected = digest(blocks[after][row['address']])
            assert row['sha256'] == expected
            wanted.append((direction, row['address'], expected))
            blockpins[direction + '/' + row['file']] = expected
    writes, sram = [], []
    for path in sorted(out.glob('*.STARTED.json')):
        cmd = read(path)['command']
        terminal = read(path.with_name(path.name.replace('.STARTED.json', '.RESULT.json')))
        assert terminal['exit_code'] == 0
        assert terminal['log_sha256'] == sha(path.with_name(path.name.replace('.STARTED.json', '.log')))
        if cmd[0].endswith('openFPGALoader'):
            assert '-f' in cmd and '--verify' in cmd
            assert cmd[cmd.index('--ftdi-serial') + 1] == '2025030317' and cmd[cmd.index('--ftdi-channel') + 1] == '0'
            assert not any(x in cmd for x in ['--unprotect-flash', '--bulk-erase', '--quad-enable'])
            address = int(cmd[cmd.index('--offset') + 1])
            name = Path(cmd[-1])
            pin = blockpins[name.parent.name + '/' + name.name]
            writes.append((name.parent.name, address, pin))
        if '--operation_index' in cmd:
            operation = cmd[cmd.index('--operation_index') + 1]
            assert operation in ['2', '51']
            if operation == '2':
                name = Path(cmd[cmd.index('--fsFile') + 1]).name
                assert name in ['home_product.fs', 'original_swic_product.fs']
                sram.append(name)
    assert sorted(writes) == sorted(wanted) and len(writes) == 4
    assert sram.count('home_product.fs') == 5 and sram.count('original_swic_product.fs') == 1
    assert sha(ROOT / 'prebuilt/home_product.fs') == FPGA_SHA
    assert sha(SIGNED / 'prebuilt/swic_product.fs') == RESTORE_SHA
    inputs = read(out / 'INPUTS.json')
    for label in ['A', 'B']:
        assert inputs['model-' + label + '/package.swic'] == PACKAGE_SHA[label]
        assert inputs['model-' + label + '/model.bin'] == IMAGE_SHA[label]
        assert inputs['model-' + label + '/array.bin'] == ARRAY_SHA[label]
        assert inputs['model-' + label + '/reference.json'] == sha(out / ('model-' + label + '-reference.json'))
    for direction in ['A-to-B', 'B-to-A']:
        assert inputs[direction + '/BLOCK-PLAN.json'] == sha(out / (direction + '-BLOCK-PLAN.json'))
    for name, pin in blockpins.items():
        assert inputs[name] == pin
    if private_workspace is not None:
        private_workspace = Path(private_workspace)
        base = (private_workspace / 'backups/read1.bin').read_bytes()
        assert len(base) == 16777216 and digest(base) == ARRAY_SHA['A']
        assert base == (private_workspace / 'backups/read2.bin').read_bytes()
        candidate = bytearray(base)
        candidate[tang.MODEL_BASE:tang.MODEL_BASE + su.IMAGE_BYTES] = images['B']
        candidate[tang.SLOT_BASE:tang.SLOT_BASE + tang.SLOT_BYTES] = slots['B']
        assert digest(candidate) == ARRAY_SHA['B']
        assert base == (private_workspace / 'model-A/array.bin').read_bytes()
        assert candidate == (private_workspace / 'model-B/array.bin').read_bytes()
        assert candidate == (private_workspace / 'campaign-v2/B-readback.bin').read_bytes()
        assert base == (private_workspace / 'campaign-v2/A-restored-readback.bin').read_bytes()
    return len(writes)

def numerical_recompute(out, images):
    sys.path.insert(0, str(DEMO / 'reference'))
    from quantization.oracle import IntegerLlama
    for label, image in images.items():
        model = tang.integer_model(image, DEMO)
        oracle = IntegerLlama(model)
        first, _ = oracle.forward_token(1)
        second, _ = oracle.forward_token(first)
        assert [int(first), int(second)] == ([108, 32] if label == 'A' else [0, 0])
        oracle = IntegerLlama(model)
        token, actual = 378, []
        for _ in range(128):
            token, _ = oracle.forward_token(token)
            actual.append(int(token))
        assert actual == read(out / ('model-' + label + '-reference.json'))['generated_tokens']

def audit(out=None, *, recompute_reference=False, private_workspace=None):
    out = Path(out) if out is not None else ROOT / 'evidence/model-replacement-v2'
    capture_integrity(out)
    result = read(out / 'RESULT.json')
    assert result['result'] == 'PASS' and result['fpga_image_sha256'] == FPGA_SHA
    roots, images, slots, blocks = signed_models(out)
    written = installation_receipts(out, images, slots, blocks, private_workspace)
    if recompute_reference:
        numerical_recompute(out, images)
    events = [json.loads(line) for line in (out / 'EVENTS.jsonl').read_text().splitlines()]
    homes = [e for e in events if e['event'] == 'home-request']
    assert len({e['nonce'] for e in homes}) == len(homes)
    key = su.DemoAuthority(17).public_key
    leaves = []
    for e in homes:
        request = bytes.fromhex(e['request_hex'])
        fields = parse_request(request)
        assert request[16:32] == DEVICE_ID
        assert fields['model_root'] == roots[e['admitted_model']] == e['model_root']
        if e['decision'] == 'approved':
            grant = bytes.fromhex(e['grant_hex'])
            assert grant[:128] == request
            _, q = verify_grant(grant, key)
            leaves.append(q)
        else:
            assert e['decision'] == 'denied'
    wrong = [e for e in events if e['event'] == 'wrong-model-grant']
    replay = [e for e in events if e['event'] == 'old-A-grant-replay']
    assert len(wrong) == len(replay) == 1
    wrong = wrong[0]
    request = bytes.fromhex(wrong['actual_request_hex'])
    grant = bytes.fromhex(wrong['grant_hex'])
    fields, q = verify_grant(grant, key)
    leaves.append(q)
    assert parse_request(request)['model_root'] == roots['B'] and fields['model_root'] == roots['A']
    assert grant[:64] == request[:64] and grant[96:128] == request[96:] and grant[64:96] != request[64:96]
    replay = replay[0]
    fresh = bytes.fromhex(replay['fresh_request_hex'])
    old = bytes.fromhex(replay['grant_hex'])
    assert old.hex() == next(e['grant_hex'] for e in homes if e['session'] == 'A-approved')
    assert parse_request(fresh)['model_root'] == roots['A'] and old[32:64] != fresh[32:64]
    assert len(leaves) == len(set(leaves))
    assert sorted(leaves) == list(range(result['signer_start_leaf'], result['signer_end_leaf']))
    withdrawn = next(e['time'] for e in events if e['event'] == 'policy' and e['allowed_models'] == ['B'])
    assert not any(e['decision'] == 'approved' and e['admitted_model'] == 'A' and e['time'] > withdrawn for e in homes)
    for session in ['B-withheld', 'A-rollback-denied', 'A-second-restart-denied']:
        selected = [e for e in homes if e['session'] == session]
        assert len(selected) == 1 and selected[0]['decision'] == 'denied'

    wire_replies = 0
    wire_commands = 0
    wire_grants = 0
    sessions = {e['session'] for e in events if e['event'] == 'serial-read'}
    for session in sessions:
        rx = b''.join(bytes.fromhex(e['data_hex']) for e in events if e['event'] == 'serial-read' and e['session'] == session)
        parsed_homes, parsed_replies = [], []
        while rx:
            if rx[0] == 0xa6:
                assert len(rx) >= 129
                parse_request(rx[1:129])
                parsed_homes.append(rx[1:129].hex())
                rx = rx[129:]
            else:
                assert rx[0] == 0x5a and len(rx) >= 5 and rx[4] == crc8(rx[:4])
                parsed_replies.append(rx[:5].hex())
                rx = rx[5:]
        assert parsed_homes == [e['request_hex'] for e in homes if e['session'] == session]
        replies = [e for e in events if e['event'] == 'token-reply' and e['session'] == session]
        assert parsed_replies == [e['frame_hex'] for e in replies]
        commands = [e for e in events if e['event'] == 'application-command' and e['session'] == session]
        assert len(commands) == len(replies)
        for command, reply in zip(commands, replies):
            latest = [e for e in homes if e['session'] == session and e['time'] <= command['time']][-1]
            assert latest['decision'] == 'approved' and command['time'] >= latest['grant_sent_time'] + .5
            assert command['time'] < latest['time'] + 4.5
            frame = bytes.fromhex(reply['frame_hex'])
            assert frame[1] == 0x80 + command['op'] and int.from_bytes(frame[2:4], 'little') == command['expected']
        tx = b''.join(bytes.fromhex(e['data_hex']) for e in events if e['event'] == 'serial-write' and e['session'] == session)
        parsed_commands, parsed_grants = [], []
        while tx:
            if tx[0] == 0xa5:
                assert len(tx) >= 5 and tx[4] == crc8(tx[:4])
                parsed_commands.append(tx[:5].hex())
                tx = tx[5:]
            else:
                assert len(tx) >= GRANT_BYTES
                verify_grant(tx[:GRANT_BYTES], key)
                parsed_grants.append(tx[:GRANT_BYTES].hex())
                tx = tx[GRANT_BYTES:]
        wanted_commands = []
        wanted_grants = []
        for e in events:
            if e.get('session') != session:
                continue
            if e['event'] == 'application-command':
                frame = bytes([0xa5, e['op'], e['input_token'] & 255, e['input_token'] >> 8])
                wanted_commands.append((frame + bytes([crc8(frame)])).hex())
            if e['event'] == 'closed-gate-command':
                wanted_commands.append(e['frame_hex'])
            if e['event'] == 'home-request' and e['decision'] == 'approved':
                wanted_grants.append(e['grant_hex'])
            if e['event'] in ['wrong-model-grant', 'old-A-grant-replay']:
                wanted_grants.append(e['grant_hex'])
        assert parsed_commands == wanted_commands
        assert parsed_grants == wanted_grants
        wire_replies += len(parsed_replies)
        wire_commands += len(parsed_commands)
        wire_grants += len(parsed_grants)
    for name in ['A-revoked', 'B-rejects-A-grant', 'A-rollback-old-grant', 'A-second-restart-denied']:
        start = next(e for e in events if e['event'] == 'closed-gate-challenge' and e['name'] == name)
        finish = next(e for e in events if e['event'] == 'closed-gate-pass' and e['name'] == name)
        assert finish['time'] - start['time'] >= 1
        assert not any(e['event'] == 'serial-read' and e['session'] == start['session'] and start['time'] <= e['time'] <= finish['time'] for e in events)
    for label in ['A', 'B']:
        tokens = read(out / ('model-' + label + '-tokens.json'))
        assert tokens['tokens'] == read(out / ('model-' + label + '-reference.json'))['generated_tokens'][:32]
        assert tokens['smoke_tokens'] == ([108, 32] if label == 'A' else [0, 0])
    B_steps = [e for e in events if e['event'] == 'token-reply' and e['session'] == 'B-approved' and e['status'] == 0x81]
    assert len(B_steps) == 34
    assert any(e['session'] == 'B-approved' and e['decision'] == 'approved'
               and B_steps[17]['time'] < e['time'] and e['grant_sent_time'] < B_steps[18]['time'] for e in homes)
    restored = read(out / 'RESTORED.json')
    baseline_check = read(out / 'baseline-after.json')
    assert restored['result'] == 'PASS' and restored['array_sha256'] == ARRAY_SHA['A']
    assert baseline_check['result'] == 'PASS' and baseline_check['expected'] == [108, 32]
    for transaction in baseline_check['transactions']:
        frame = bytes.fromhex(transaction['response_hex'])
        assert len(frame) == 5 and frame[4] == crc8(frame[:4])
    assert baseline_check['transactions'][-1]['opcode'] == 2
    return {'result': 'PASS', 'models': roots, 'fpga_image_sha256': FPGA_SHA,
            'matched_board_outputs': 68, 'raw_wire_reply_frames': wire_replies,
            'raw_wire_command_frames': wire_commands, 'raw_wire_grants': wire_grants,
            'distinct_nonces': len(homes), 'unique_new_signing_leaves': sorted(leaves),
            'written_blocks_checked': written, 'wrong_model_same_nonce_signature_checked': True,
            'revocation_rollback_and_replay_checked': True,
            'full_private_arrays_replayed': private_workspace is not None,
            'numerical_reference_recomputed': recompute_reference,
            'electrical_power_cycles_tested': False,
            'B_renewal_scope': 'Generation across renewal; constant-zero B outputs do not independently establish context preservation.',
            'scope': 'Replay of published host observations, signed numerical fixtures, actual wire bytes and recorded installation receipts. Complete-array bytes are compared only when the original private workspace is supplied. Not physical attestation, entropy qualification or a universal command-stream proof.'}

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--evidence', type=Path)
    p.add_argument('--recompute-reference', action='store_true', help='Requires NumPy; recompute both 128-output references and two-token smoke cases')
    p.add_argument('--private-workspace', type=Path, help='Original private workspace containing full flash captures; never uploaded')
    a = p.parse_args()
    print(json.dumps(audit(a.evidence, recompute_reference=a.recompute_reference, private_workspace=a.private_workspace), indent=2))
