"""Independently audit saved replacement arrays, wire bytes and real signatures."""
from pathlib import Path
import argparse, hashlib, json, sys

W = Path(__file__).resolve().parents[1]
R = W.parent / 'sawic-model-replacement-20261105'
OLD = W.parent / 'simplestories-swic-tang-20261103'
sys.path.insert(0, str(OLD / 'reference'))
import signed_update as su, tang_image as tang
sys.path.insert(0, str(W / 'reference'))
from home_auth import parse_request, DEVICE_ID, GRANT_BYTES, REQUEST_BYTES
from serial_client import crc8

def read(p):
    return json.loads(p.read_text())

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def verify_grant(grant, key):
    assert len(grant) == GRANT_BYTES
    fields = parse_request(grant[:REQUEST_BYTES])
    assert su.lms_verify(key, grant[:REQUEST_BYTES], grant[REQUEST_BYTES:])
    return fields, int.from_bytes(grant[REQUEST_BYTES:REQUEST_BYTES + 4], 'big')

def audit(out):
    result = read(out / 'RESULT.json')
    assert result['result'] == 'PASS'
    for name, digest in read(out / 'INPUTS.json').items():
        assert sha(R / name) == digest, name
    plan = read(R / 'PLAN.json')
    roots = {}
    for label in ['A', 'B']:
        package = (R / ('model-' + label) / 'package.swic').read_bytes()
        info = tang.validate_tang(package, [su.DemoAuthority(i).public_key for i in range(3)])
        assert info == {k: plan['models'][label][k] for k in info}
        roots[label] = info['model_root']
    assert roots['A'] != roots['B']
    baseline = (R / 'backups/read1.bin').read_bytes()
    assert len(baseline) == 16777216 and baseline == (R / 'backups/read2.bin').read_bytes()
    assert baseline == Path(read(R / 'backups/BACKUPS.json')['durable_copy']).read_bytes()
    assert baseline == (R / 'model-A/array.bin').read_bytes()
    for label, name in [('B', 'B-readback'), ('A', 'A-restored-readback')]:
        capture = out / (name + '.bin')
        receipt = read(out / (name + '.bin.json'))
        assert capture.read_bytes() == (R / ('model-' + label) / 'array.bin').read_bytes()
        assert receipt['status'] == 'PASS' and receipt['bytes'] == 16777216 and receipt['array_write'] is False
        assert receipt['sha256'] == sha(capture) and receipt['log_sha256'] == sha(out / (name + '.bin.log'))
        assert receipt['tool_sha256'] == 'f880eb583695f8056566da308248ba539a1a1c4cabb6305c3d801acfd58f9e1b'
        cmd = receipt['command']
        assert '--dump-flash' in cmd and '-f' not in cmd and cmd[cmd.index('--ftdi-serial') + 1] == '2025030317'
    writes = []
    sram = []
    for path in sorted(out.glob('*.STARTED.json')):
        cmd = read(path)['command']
        terminal = read(path.with_name(path.name.replace('.STARTED.json', '.RESULT.json')))
        assert terminal['exit_code'] == 0
        logfile = path.with_name(path.name.replace('.STARTED.json', '.log'))
        assert terminal['log_sha256'] == sha(logfile)
        if cmd[0].endswith('openFPGALoader'):
            assert '-f' in cmd and '--verify' in cmd
            assert cmd[cmd.index('--ftdi-serial') + 1] == '2025030317'
            assert cmd[cmd.index('--ftdi-channel') + 1] == '0'
            assert not any(x in cmd for x in ['--unprotect-flash', '--bulk-erase', '--quad-enable'])
            address = int(cmd[cmd.index('--offset') + 1])
            assert address in [0xe80000, 0xf00000]
            data = Path(cmd[-1])
            assert data.stat().st_size == 65536
            writes.append((data.parent.name, address, sha(data)))
        if '--operation_index' in cmd:
            operation = cmd[cmd.index('--operation_index') + 1]
            assert operation in ['2', '51']
            if operation == '2':
                assert '--fsFile' in cmd
                sram.append(sha(Path(cmd[cmd.index('--fsFile') + 1])))
    wanted = []
    for direction in ['A-to-B', 'B-to-A']:
        for row in read(R / direction / 'BLOCK-PLAN.json')['writes']:
            wanted.append((direction, row['address'], row['sha256']))
    assert sorted(writes) == sorted(wanted) and len(writes) == 4
    assert sram.count('cb0f7d60bbedca7ec504973d26f5093445049a4dbac3435df591231c2ae1922e') == 5
    assert sram.count('4545bd0b0c4076eaea8358d547b19ff0176952417daa0e0f07d1c346aee5fee2') == 1

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
        assert tokens['tokens'] == read(R / ('model-' + label) / 'reference.json')['generated_tokens'][:32]
        assert tokens['smoke_tokens'] == ([108, 32] if label == 'A' else [0, 0])
    B_steps = [e for e in events if e['event'] == 'token-reply' and e['session'] == 'B-approved' and e['status'] == 0x81]
    assert len(B_steps) == 34
    assert any(e['session'] == 'B-approved' and e['decision'] == 'approved'
               and B_steps[17]['time'] < e['time'] and e['grant_sent_time'] < B_steps[18]['time'] for e in homes)
    restored = read(out / 'RESTORED.json')
    baseline_check = read(out / 'baseline-after.json')
    assert restored['result'] == 'PASS' and restored['array_sha256'] == sha(out / 'A-restored-readback.bin')
    assert baseline_check['result'] == 'PASS' and baseline_check['expected'] == [108, 32]
    for transaction in baseline_check['transactions']:
        frame = bytes.fromhex(transaction['response_hex'])
        assert len(frame) == 5 and frame[4] == crc8(frame[:4])
    assert baseline_check['transactions'][-1]['opcode'] == 2
    files = ['RESULT.json', 'RESTORED.json', 'EVENTS.jsonl', 'INPUTS.json', 'HOST-SOURCES.json', 'RUNNER.py',
             'model-A-tokens.json', 'model-B-tokens.json', 'baseline-after.json',
             'B-readback.bin.json', 'A-restored-readback.bin.json']
    return {'result': 'PASS', 'models': roots, 'fpga_image_sha256': result['fpga_image_sha256'], 'matched_reference_outputs': 68,
            'raw_wire_reply_frames': wire_replies, 'raw_wire_command_frames': wire_commands, 'raw_wire_grants': wire_grants,
            'distinct_nonces': len(homes), 'unique_new_signing_leaves': sorted(leaves), 'wrong_model_same_nonce_signature_checked': True,
            'revocation_rollback_and_replay_checked': True, 'full_array_B_and_A_readbacks_checked': True, 'written_blocks': len(writes),
            'starting_flash_and_original_sram_restored': True, 'electrical_power_cycles': False,
            'B_renewal_observation': 'Generation succeeds across a fresh approval. The constant-zero B fixture cannot by itself distinguish preserved context from a context reset; the raw runner context-preservation label is limited accordingly.',
            'source_hashes': {name: sha(out / name) for name in files},
            'scope': 'Finite host-observed physical campaign, independently rechecked against saved raw wire bytes, signed packages, actual LMS grants and complete private flash captures. Not physical attestation, entropy certification or a universal command-stream theorem.'}

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--campaign', type=Path, required=True)
    a = p.parse_args()
    result = audit(a.campaign)
    target = a.campaign / 'EVIDENCE-AUDIT.json'
    assert not target.exists(), 'Preserve the previous audit'
    target.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'source_hashes'}, indent=2))
