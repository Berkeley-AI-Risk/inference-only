"""Source-bound A -> B -> withdrawn-A board test with exact flash recovery."""
from pathlib import Path
import argparse, datetime, fcntl, hashlib, json, os, re, subprocess, sys, threading, time

W = Path(__file__).resolve().parents[1]
R = W.parent / 'sawic-model-replacement-20261105'
OLD = W.parent / 'simplestories-swic-tang-20261103'
PUB = Path('RELEASE_ROOT')
PROGRAMMER = Path('LOCAL_REPOSITORY/vendor-installers/gowin/programmer-1.9.12.03-2712-macos-arm64/Programmer/bin/programmer_cli')
LOADER = Path('/opt/homebrew/bin/openFPGALoader')
IMAGE = R / 'bitstreams/home_product.fs'
RESTORE = R / 'bitstreams/original_swic_product.fs'
PORT = '/dev/cu.usbserial-20250303171'
sys.path.insert(0, str(W / 'reference'))
from home_auth import HomeBase, policy_for, parse_request
from home_server import make_server
from serial_client import AuthorizedSerial, BackgroundAuthorization, crc8
from usb_debugger import reset_known_debugger
sys.path.insert(0, str(OLD / 'reference'))
import signed_update as su, tang_image as tang

def read(p):
    return json.loads(p.read_text())

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def record(p, d):
    p.write_text(json.dumps(d, indent=2) + '\n')

def safe_command_window(home, now):
    # The request timestamp precedes the HTTP round trip and paced UART write.
    # Settling must start after the complete grant has been transmitted.
    return home['decision'] == 'approved' and home['grant_sent_time'] + .5 <= now < home['time'] + 4.5

def preflight(require_backups=True):
    assert sha(PROGRAMMER) == '41a967c1d18ec73b420801d52bf83ad40b92ca032683231d55a5ef158d523cfb'
    assert sha(LOADER) == 'f880eb583695f8056566da308248ba539a1a1c4cabb6305c3d801acfd58f9e1b'
    assert sha(IMAGE) == 'cb0f7d60bbedca7ec504973d26f5093445049a4dbac3435df591231c2ae1922e'
    assert sha(RESTORE) == '4545bd0b0c4076eaea8358d547b19ff0176952417daa0e0f07d1c346aee5fee2'
    native = W / 'evidence/native-v132'
    native_root = Path(read(native / 'RESULT.json')['directory'])
    for n, digest in read(native / 'INPUTS.json').items():
        assert sha(native_root / n) == digest, n
    assert read(native / 'SIMULATION-QUALIFICATION.json')['result'] == 'PASS'
    timing = read(native / 'TIMING-REVIEW.json')
    assert timing['bitstream_sha256'] == sha(IMAGE) and timing['functional_board_test_allowed']
    assert timing['accepted_synchronizer_entry_exceptions'] == []
    plan = read(R / 'PLAN.json')
    for label in ['A', 'B']:
        d = R / ('model-' + label)
        package = (d / 'package.swic').read_bytes()
        info = tang.validate_tang(package, [su.DemoAuthority(i).public_key for i in range(3)])
        assert info['model_root'] == plan['models'][label]['model_root']
        assert sha(d / 'package.swic') == plan['models'][label]['package_sha256']
        assert sha(d / 'model.bin') == plan['models'][label]['image_sha256']
        ref = read(d / 'reference.json')
        assert ref['image_sha256'] == sha(d / 'model.bin') and ref['prompt_tokens'] == [378] and len(ref['generated_tokens']) == 128
    assert read(R / 'model-A/reference.json')['generated_tokens'] != read(R / 'model-B/reference.json')['generated_tokens']
    for before, after, name in [('A', 'B', 'A-to-B'), ('B', 'A', 'B-to-A')]:
        blockplan = read(R / name / 'BLOCK-PLAN.json')
        start = (R / ('model-' + before) / 'array.bin').read_bytes()
        expected = (R / ('model-' + after) / 'array.bin').read_bytes()
        assert len(start) == len(expected) == 16777216
        assert hashlib.sha256(start).hexdigest() == blockplan['before_sha256']
        assert hashlib.sha256(expected).hexdigest() == blockplan['candidate_sha256']
        assert [(r['address'], r['bytes']) for r in blockplan['writes']] == [(0xe80000, 65536), (0xf00000, 65536)]
        replay = bytearray(start)
        for row in blockplan['writes']:
            data = (R / name / row['file']).read_bytes()
            assert len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256']
            replay[row['address']:row['address'] + len(data)] = data
        assert replay == expected
    if require_backups:
        assert read(R / 'backups/RESULT.json')['result'] == 'PASS'
        assert read(R / 'backups/RESTORED.json')['result'] == 'PASS'
        copies = [R / 'backups/read1.bin', R / 'backups/read2.bin', Path(read(R / 'backups/BACKUPS.json')['durable_copy']), R / 'model-A/array.bin']
        assert all(p.read_bytes() == copies[0].read_bytes() for p in copies)
    state = read(R / 'home-signer-state.json')
    assert 18 <= state['next_leaf'] <= 24, 'Insufficient remaining demo signing capacity for this run'
    return plan

class Campaign:
    def __init__(self, output):
        self.out = output
        self.out.mkdir(mode=0o700, exist_ok=False)
        self.plan = preflight()
        recovery_tests = read(R / 'harness-checks-settle-v1/RESULT.json')
        assert recovery_tests['result'] == 'PASS' and recovery_tests['tests'] == 9
        assert recovery_tests['runner_sha256'] == sha(Path(__file__)), 'Recovery checks concern a different runner'
        self.lock = open('/tmp/inference-only-tang-mega-2025030317.lock', 'a+')
        fcntl.flock(self.lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        self.require_idle()
        self.client = self.relay = None
        self.session = None
        self.server = None
        self.flash_touched = False
        self.flash_start_verified = True
        self.sram_touched = False
        self.phase = 'preflight'
        self.events = []
        self.journal_lock = threading.Lock()
        self.state = R / 'home-signer-state.json'
        self.policy = self.out / 'policy.json'
        self.policy_update(['A'])
        self.initial_signer = read(self.state)
        record(self.out / 'STARTED.json', {'pid': os.getpid(), 'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'signer_start': self.initial_signer, 'image_sha256': sha(IMAGE)})
        (self.out / 'RUNNER.py').write_bytes(Path(__file__).read_bytes())
        record(self.out / 'HOST-SOURCES.json', {n: sha(W / 'reference' / n) for n in ['home_auth.py', 'home_server.py', 'serial_client.py', 'usb_debugger.py']})
        names = ['PLAN.json', 'model-A/package.swic', 'model-B/package.swic', 'model-A/model.bin', 'model-B/model.bin',
                 'model-A/array.bin', 'model-B/array.bin', 'model-A/reference.json', 'model-B/reference.json',
                 'A-to-B/BLOCK-PLAN.json', 'B-to-A/BLOCK-PLAN.json']
        for direction in ['A-to-B', 'B-to-A']:
            names.extend(direction + '/' + row['file'] for row in read(R / direction / 'BLOCK-PLAN.json')['writes'])
        record(self.out / 'INPUTS.json', {name: sha(R / name) for name in names})

    def require_idle(self):
        assert not subprocess.run(['/usr/sbin/lsof', PORT, '/dev/cu.usbserial-20250303170'], capture_output=True, text=True).stdout.strip(), 'Board UART owned'

    def event(self, d):
        d.setdefault('time', time.monotonic())
        d.setdefault('phase', self.phase)
        with self.journal_lock:
            self.events.append(d)
            with (self.out / 'EVENTS.jsonl').open('a') as f:
                f.write(json.dumps(d) + '\n')

    def set_phase(self, name):
        self.phase = name
        record(self.out / 'STATUS.json', {'phase': name, 'flash_touched': self.flash_touched, 'flash_start_verified': self.flash_start_verified})
        self.event({'event': 'phase', 'name': name})
        print(name, flush=True)

    def run(self, cmd, name):
        record(self.out / (name + '.STARTED.json'), {'command': cmd, 'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat()})
        with (self.out / (name + '.log')).open('xb') as log:
            child = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT)
            awake = subprocess.Popen(['/usr/bin/caffeinate', '-i', '-w', str(child.pid)])
            code = child.wait()
            awake.wait()
        text = (self.out / (name + '.log')).read_text(errors='replace')
        record(self.out / (name + '.RESULT.json'), {'exit_code': code, 'log_sha256': sha(self.out / (name + '.log'))})
        assert code == 0, name
        return text

    def location(self, name):
        text = self.run([str(PROGRAMMER), '--scan-cables'], name)
        found = re.findall(r'USB Debugger A/0/(\d+)/', text)
        assert len(found) == 1, text
        return found[0]

    def load(self, image, name):
        loc = self.location(name + '-cables')
        self.sram_touched = True
        text = self.run([str(PROGRAMMER), '--device', 'GW5AST-138C', '--cable-index', '4', '--location', loc, '--frequency', '0.9MHz', '--operation_index', '2', '--fsFile', str(image)], name)
        assert 'Finished' in text and '0001081B' in text.upper()
        self.event({'event': 'sram-load', 'image_sha256': sha(image), 'name': name})

    def policy_update(self, labels):
        roots = [bytes.fromhex(self.plan['models'][label]['model_root']) for label in labels]
        temporary = self.policy.with_name('policy-next.json')
        record(temporary, policy_for(roots))
        os.replace(temporary, self.policy)
        if hasattr(self, 'journal_lock'):
            self.event({'event': 'policy', 'allowed_models': labels})

    def open(self, label, session):
        assert self.relay is None
        self.session = session
        root = self.plan['models'][label]['model_root']
        self.client = AuthorizedSerial(PORT, f'http://127.0.0.1:{self.server.server_port}/authorize', root, grant_chunk_bytes=16, grant_chunk_pause=.003)
        campaign = self
        class Journal(list):
            def append(self, event):
                event.update(session=session, admitted_model=label)
                if event['event'] == 'home-request' and event['decision'] == 'approved':
                    event['grant_sent_time'] = time.monotonic()
                super().append(event)
                campaign.event(event)
        self.client.events = Journal()
        original_read, original_write = self.client.read, self.client.write
        def traced_read(n, deadline):
            data = original_read(n, deadline)
            self.event({'event': 'serial-read', 'session': session, 'requested': n, 'data_hex': data.hex()})
            return data
        def traced_write(data):
            original_write(data)
            self.event({'event': 'serial-write', 'session': session, 'data_hex': data.hex()})
        self.client.read, self.client.write = traced_read, traced_write
        self.relay = BackgroundAuthorization(self.client)

    def close(self):
        if self.relay is not None:
            relay, client = self.relay, self.client
            self.relay = self.client = None
            self.session = None
            try:
                relay.close()
            except BaseException:
                # Preserve the failure while releasing only this runner's
                # descriptor so flash/SRAM recovery can still proceed.
                try:
                    client.close()
                except OSError:
                    pass
                raise

    def home_after(self, cutoff, timeout=90):
        end = time.monotonic() + timeout
        while True:
            event = self.relay.next_home(max(.001, end - time.monotonic()))
            if event['time'] > cutoff:
                return event
            if time.monotonic() >= end:
                raise TimeoutError('No fresh home request')

    def boot(self, label, session, approved):
        self.open(label, session)
        started = time.monotonic()
        self.load(IMAGE, session + '-load')
        event = self.home_after(started)
        assert event['decision'] == ('approved' if approved else 'denied')
        assert event['nonce'] not in {e['nonce'] for e in self.events if e.get('event') == 'home-request' and e is not event}
        return event

    def window(self):
        end = time.monotonic() + 15
        while time.monotonic() < end:
            if self.relay.failure:
                raise RuntimeError('Reader failed') from self.relay.failure
            homes = [e for e in self.client.events if e['event'] == 'home-request']
            if homes:
                latest = homes[-1]
                assert latest['decision'] == 'approved'
                now = time.monotonic()
                if safe_command_window(latest, now):
                    return
            time.sleep(.005)
        raise TimeoutError('No safe command window')

    def command(self, op, token=0, expected=0):
        self.window()
        self.event({'event': 'application-command', 'session': self.session, 'op': op, 'input_token': token, 'expected': expected})
        return self.relay.command(op, token, expected=expected)

    def check_tokens(self, label, split_renewal=False):
        self.command(2)
        self.command(0, 1)
        for token in ([108, 32] if label == 'A' else [0, 0]):
            self.command(1, expected=token)
        self.command(2)
        self.command(0, 378)
        expected = read(R / ('model-' + label) / 'reference.json')['generated_tokens'][:32]
        result = []
        for i, token in enumerate(expected):
            if split_renewal and i == 16:
                event = self.home_after(result[-1]['time'], 15)
                assert event['decision'] == 'approved' and event['model_root'] == self.plan['models'][label]['model_root']
            result.append(self.command(1, expected=token))
        self.command(2)
        record(self.out / ('model-' + label + '-tokens.json'), {'result': 'PASS', 'prompt': [378], 'tokens': [e['token'] for e in result], 'smoke_prompt': [1], 'smoke_tokens': [108, 32] if label == 'A' else [0, 0], 'renewal_between_outputs_16_17': split_renewal})

    def challenge_closed(self, name, wait=4.5):
        time.sleep(wait)
        self.event({'event': 'closed-gate-challenge', 'session': self.session, 'name': name, 'wait_seconds': wait})
        for op, token in [(2, 0), (0, 1), (1, 0)]:
            payload = bytes([0xa5, op, token & 255, token >> 8])
            frame = payload + bytes([crc8(payload)])
            self.event({'event': 'closed-gate-command', 'session': self.session, 'name': name, 'frame_hex': frame.hex()})
            self.client.write(frame)
        self.relay.expect_quiet(1)
        self.event({'event': 'closed-gate-pass', 'session': self.session, 'name': name, 'observation_seconds': 1})

    def install(self, direction, name):
        assert self.relay is None
        self.require_idle()
        loc = self.location(name + '-cables')
        text = self.run([str(PROGRAMMER), '--device', 'GW5AST-138C', '--cable-index', '4', '--location', loc, '--frequency', '0.9MHz', '--operation_index', '51'], name + '-flash-id')
        assert '0B4018' in text.upper() and '0001081B' in text.upper() and 'Finished' in text
        rows = read(R / direction / 'BLOCK-PLAN.json')['writes']
        for i, row in enumerate(rows):
            path = R / direction / row['file']
            assert sha(path) == row['sha256'] and path.stat().st_size == row['bytes']
            self.flash_touched = True
            self.flash_start_verified = False
            self.sram_touched = True
            text = self.run([str(LOADER), '-b', 'tangmega138k', '--ftdi-serial', '2025030317', '--ftdi-channel', '0', '--freq', '900000', '-v', '-f', '--verify', '--offset', str(row['address']), str(path)], name + '-block-' + str(i))
            plain = re.sub(r'\x1b\[[0-9;]*m', '', text)
            assert not re.search(r'\b(?:ERROR|FAILED|FAILURE)\b', plain, re.I)
            assert re.search(r'idcode\s+0x0*1081b', plain, re.I)
            for pattern, expected in [(r'Jedec ID\s*:\s*([0-9a-f]{2})', '0b'), (r'memory type\s*:\s*([0-9a-f]{2})', '40'), (r'memory capacity\s*:\s*([0-9a-f]{2})', '18')]:
                match = re.search(pattern, plain, re.I)
                assert match and match.group(1).lower() == expected
            self.event({'event': 'flash-block-written', 'direction': direction, 'address': row['address'], 'bytes': row['bytes'], 'sha256': row['sha256']})

    def full_read(self, label, name):
        array = R / ('model-' + label) / 'array.bin'
        dest = self.out / (name + '.bin')
        self.sram_touched = True
        self.run([sys.executable, str(OLD / 'tools/read_flash_jtag.py'), '--openloader', str(LOADER), '--tool-sha256', sha(LOADER), '--serial', '2025030317', '--output', str(dest), '--expected-array', str(array)], name)
        assert dest.read_bytes() == array.read_bytes()
        self.event({'event': 'complete-array-verified', 'model': label, 'sha256': sha(dest), 'bytes': dest.stat().st_size, 'capture': dest.name})
        if label == 'A':
            assert dest.read_bytes() == (R / 'backups/read1.bin').read_bytes()
            self.flash_start_verified = True

    def restore(self):
        try:
            self.close()
        except BaseException as exc:
            record(self.out / 'SERIAL-CLEANUP-FAILURE.json', {'type': type(exc).__name__, 'message': str(exc)})
        if self.flash_touched and not self.flash_start_verified:
            self.set_phase('Recover exact starting flash')
            self.install('B-to-A', 'recovery-A')
            self.full_read('A', 'recovery-A-readback')
        if self.sram_touched:
            self.set_phase('Restore original signed-update SRAM image')
            self.load(RESTORE, 'restore-original')
            record(self.out / 'USB-RESET.json', reset_known_debugger())
            time.sleep(45)
            self.run([sys.executable, str(OLD / 'tools/uart_check.py'), '--device', PORT, '--expected', '108,32', '--output', str(self.out / 'baseline-after.json')], 'baseline-after')
        assert not self.flash_touched or self.flash_start_verified
        record(self.out / 'RESTORED.json', {'result': 'PASS', 'starting_array_restored_exactly': True, 'array_sha256': sha(R / 'backups/read1.bin'), 'original_sram_image_sha256': sha(RESTORE), 'baseline_tokens': [108, 32], 'clear_after_baseline': True})

    def execute(self):
        passed = False
        try:
            self.server = make_server(self.policy, self.state)
            threading.Thread(target=self.server.serve_forever, daemon=True).start()
            self.set_phase('A approved: verify base-model outputs')
            first = self.boot('A', 'A-approved', True)
            old_A_grant = bytes.fromhex(first['grant_hex'])
            self.check_tokens('A')
            self.set_phase('Withdraw A and authorize only replacement B')
            self.policy_update(['B'])
            withdrew = time.monotonic()
            while True:
                denial = self.relay.next_home(15)
                if denial['decision'] == 'denied':
                    break
                assert denial['time'] <= withdrew, 'A approved after withdrawal'
            self.challenge_closed('A-revoked', 10.5)
            self.close()
            self.set_phase('Install signed model B, preserving all other flash bytes')
            self.install('A-to-B', 'install-B')
            self.full_read('B', 'B-readback')
            self.set_phase('B requires its own approval; reject a valid wrong-model grant')
            self.policy_update([])
            request = self.boot('B', 'B-withheld', False)
            actual = bytes.fromhex(request['request_hex'])
            wrong = actual[:64] + bytes.fromhex(self.plan['models']['A']['model_root']) + actual[96:]
            fixture_policy = self.out / 'wrong-model-fixture-policy.json'
            record(fixture_policy, policy_for([bytes.fromhex(self.plan['models']['A']['model_root'])]))
            fixture_home = HomeBase(fixture_policy, self.state)
            wrong_grant = fixture_home.authorize(wrong)
            assert wrong[:64] == actual[:64] and wrong[96:] == actual[96:] and wrong[64:96] != actual[64:96]
            assert su.lms_verify(fixture_home.public_key, wrong, wrong_grant[128:])
            self.event({'event': 'wrong-model-grant', 'session': self.session, 'actual_request_hex': actual.hex(), 'grant_hex': wrong_grant.hex(), 'actual_model': 'B', 'signed_model': 'A', 'same_fresh_nonce_and_device': True, 'valid_lms_signature': True, 'fixture_only_not_live_policy_approval': True})
            self.client.write_grant(wrong_grant)
            self.challenge_closed('B-rejects-A-grant')
            self.close()
            self.set_phase('Authorize B: verify replacement outputs across renewal')
            self.policy_update(['B'])
            self.boot('B', 'B-approved', True)
            self.check_tokens('B', split_renewal=True)
            self.close()
            self.set_phase('Reinstall revoked A while only B stays authorized')
            self.install('B-to-A', 'rollback-A')
            self.full_read('A', 'A-restored-readback')
            self.set_phase('A remains denied after restart; reject captured A approval')
            denied = self.boot('A', 'A-rollback-denied', False)
            assert denied['nonce'] != first['nonce']
            self.event({'event': 'old-A-grant-replay', 'session': self.session, 'fresh_request_hex': denied['request_hex'], 'grant_hex': old_A_grant.hex()})
            self.client.write_grant(old_A_grant)
            self.challenge_closed('A-rollback-old-grant')
            self.close()
            self.set_phase('A remains denied after a second SRAM restart')
            self.boot('A', 'A-second-restart-denied', False)
            self.challenge_closed('A-second-restart-denied')
            self.close()
            passed = True
        finally:
            failure = sys.exc_info()[1]
            try:
                if failure is not None:
                    record(self.out / 'FAILURE.json', {'result': 'FAIL', 'phase': self.phase, 'type': type(failure).__name__, 'message': str(failure)})
            finally:
                try:
                    self.restore()
                finally:
                    if self.server is not None:
                        self.server.shutdown()
                        self.server.server_close()
        if passed:
            record(self.out / 'RESULT.json', {'result': 'PASS', 'models': self.plan['models'], 'fpga_image_sha256': sha(IMAGE), 'model_A_reference_outputs': 34, 'model_B_reference_outputs': 34, 'B_renewal_preserves_context': True, 'A_revocation': True, 'same_nonce_wrong_model_grant_rejected': True, 'A_denied_after_rollback_and_two_restarts': True, 'captured_A_grant_replay_rejected': True, 'starting_flash_restored_exactly': True, 'original_sram_restored': True, 'electrical_power_cycles_tested': False, 'signer_start_leaf': self.initial_signer['next_leaf'], 'signer_end_leaf': read(self.state)['next_leaf'], 'fixture_scope': 'Synthetic changed normalization weights; public demo signing keys; finite board evidence, not entropy or physical-security qualification.'})
            self.set_phase('Complete model-replacement campaign PASS; original setup restored')

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--preflight-only', action='store_true')
    p.add_argument('--output', type=Path)
    a = p.parse_args()
    if a.preflight_only:
        preflight(require_backups=False)
        print('Offline source/package/reference/block-plan preflight PASS; no hardware access.')
    else:
        assert a.output is not None
        Campaign(a.output.resolve()).execute()
