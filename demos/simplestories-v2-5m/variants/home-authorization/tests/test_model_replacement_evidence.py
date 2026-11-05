"""Public replay controls rebind capture hashes before testing the semantics."""
from pathlib import Path
import hashlib, importlib.util, json, re, shutil, tempfile, unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('replacement_public_evidence', ROOT / 'tools/check_model_replacement.py')
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)

class ReplacementEvidenceTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.capture = Path(temp.name) / 'capture'
        shutil.copytree(ROOT / 'evidence/model-replacement-v2', self.capture)

    def events(self):
        return [json.loads(line) for line in (self.capture / 'EVENTS.jsonl').read_text().splitlines()]

    def save_events(self, events):
        (self.capture / 'EVENTS.jsonl').write_text(''.join(json.dumps(e) + '\n' for e in events))

    def rebind(self):
        path = self.capture / 'PUBLIC-COPIES.json'
        copies = json.loads(path.read_text())
        raw = {name: (self.capture / name).read_bytes() for name in copies['files']}
        mapping = {copies['files'][name]['public_sha256']: hashlib.sha256(b).hexdigest() for name, b in raw.items()}
        for _ in range(20):
            rebound = {name: re.sub(r'(?<![0-9a-f])[0-9a-f]{64}(?![0-9a-f])', lambda m: mapping.get(m.group(), m.group()), b.decode()).encode() for name, b in raw.items()}
            updated = {copies['files'][name]['public_sha256']: hashlib.sha256(b).hexdigest() for name, b in rebound.items()}
            if mapping == updated:
                break
            mapping = updated
        else:
            raise AssertionError('Control receipt dependencies did not settle')
        for name, b in rebound.items():
            (self.capture / name).write_bytes(b)
            copies['files'][name]['public_sha256'] = hashlib.sha256(b).hexdigest()
        path.write_text(json.dumps(copies))

    def rejected(self):
        self.rebind()
        # A hash mismatch alone must not be what makes a negative control fail.
        checker.capture_integrity(self.capture)
        with self.assertRaises((AssertionError, ValueError)):
            checker.audit(self.capture)

    def test_actual_public_capture_passes_without_private_arrays(self):
        result = checker.audit(self.capture)
        self.assertEqual(result['matched_board_outputs'], 68)
        self.assertEqual(result['distinct_nonces'], 7)
        self.assertFalse(result['full_private_arrays_replayed'])

    def test_corrupt_real_signature_is_rejected_after_rebinding(self):
        events = self.events()
        wrong = next(e for e in events if e['event'] == 'wrong-model-grant')
        grant = bytearray.fromhex(wrong['grant_hex'])
        grant[200] ^= 1
        wrong['grant_hex'] = grant.hex()
        self.save_events(events)
        self.rejected()

    def test_corrupt_raw_wire_byte_is_rejected_after_rebinding(self):
        events = self.events()
        event = next(e for e in events if e['event'] == 'serial-read' and e['requested'] == 4)
        raw = bytearray.fromhex(event['data_hex'])
        raw[1] ^= 1
        event['data_hex'] = raw.hex()
        self.save_events(events)
        self.rejected()

    def test_false_B_output_claim_is_rejected_after_rebinding(self):
        path = self.capture / 'model-B-tokens.json'
        data = json.loads(path.read_text())
        data['tokens'][0] = 200
        path.write_text(json.dumps(data))
        self.rejected()

    def test_relabelled_old_approval_is_rejected_after_rebinding(self):
        events = self.events()
        event = next(e for e in events if e['event'] == 'old-A-grant-replay')
        grant = bytearray.fromhex(event['grant_hex'])
        grant[32:64] = bytes.fromhex(event['fresh_request_hex'])[32:64]
        event['grant_hex'] = grant.hex()
        self.save_events(events)
        self.rejected()

    def test_early_command_is_rejected_after_rebinding(self):
        events = self.events()
        command = next(e for e in events if e['event'] == 'application-command')
        home = next(e for e in events if e['event'] == 'home-request' and e['decision'] == 'approved')
        command['time'] = home['grant_sent_time'] + .02
        self.save_events(events)
        self.rejected()

    def test_changed_signed_replacement_prefix_is_rejected(self):
        path = self.capture / 'model-B-signed-prefix.bin'
        data = bytearray(path.read_bytes())
        data[200] ^= 1
        path.write_bytes(data)
        with self.assertRaises((AssertionError, ValueError)):
            checker.audit(self.capture)

if __name__ == '__main__':
    unittest.main()
