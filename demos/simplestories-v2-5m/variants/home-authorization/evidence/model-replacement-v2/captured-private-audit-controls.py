"""Negative controls against the actual saved replacement campaign; no hardware."""
from pathlib import Path
import argparse, hashlib, importlib.util, json, shutil, tempfile, unittest

W = Path(__file__).resolve().parents[1]
R = W.parent / 'sawic-model-replacement-20261105'
spec = importlib.util.spec_from_file_location('replacement_auditor', W / 'integration/audit_model_replacement.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
CAMPAIGN = None

class AuditTests(unittest.TestCase):
    def clone(self, root):
        dest = Path(root) / 'campaign'
        shutil.copytree(CAMPAIGN, dest)
        return dest

    def events(self, p):
        return [json.loads(line) for line in (p / 'EVENTS.jsonl').read_text().splitlines()]

    def save_events(self, p, rows):
        (p / 'EVENTS.jsonl').write_text(''.join(json.dumps(row) + '\n' for row in rows))

    def test_original_observations_pass(self):
        self.assertEqual(m.audit(CAMPAIGN)['result'], 'PASS')

    def test_forged_wrong_model_signature_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            p = self.clone(d)
            events = self.events(p)
            e = next(e for e in events if e['event'] == 'wrong-model-grant')
            grant = bytearray.fromhex(e['grant_hex'])
            grant[200] ^= 1
            e['grant_hex'] = grant.hex()
            self.save_events(p, events)
            with self.assertRaises(AssertionError):
                m.audit(p)

    def test_changed_raw_wire_byte_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            p = self.clone(d)
            events = self.events(p)
            e = next(e for e in events if e['event'] == 'serial-read' and e['requested'] == 4)
            raw = bytearray.fromhex(e['data_hex'])
            raw[1] ^= 1
            e['data_hex'] = raw.hex()
            self.save_events(p, events)
            with self.assertRaises(AssertionError):
                m.audit(p)

    def test_falsified_replacement_outputs_are_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            p = self.clone(d)
            f = p / 'model-B-tokens.json'
            record = json.loads(f.read_text())
            record['tokens'][0] = 200
            f.write_text(json.dumps(record))
            with self.assertRaises(AssertionError):
                m.audit(p)

    def test_relabelled_replay_nonce_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            p = self.clone(d)
            events = self.events(p)
            replay = next(e for e in events if e['event'] == 'old-A-grant-replay')
            grant = bytearray.fromhex(replay['grant_hex'])
            grant[32:64] = bytes.fromhex(replay['fresh_request_hex'])[32:64]
            replay['grant_hex'] = grant.hex()
            self.save_events(p, events)
            with self.assertRaises(AssertionError):
                m.audit(p)

    def test_hidden_outside_region_flash_change_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            p = self.clone(d)
            f = p / 'B-readback.bin'
            data = bytearray(f.read_bytes())
            data[12345] ^= 1
            f.write_bytes(data)
            receipt = p / 'B-readback.bin.json'
            record = json.loads(receipt.read_text())
            record.update(status='PASS', expected_array_equal=True, sha256=hashlib.sha256(data).hexdigest())
            receipt.write_text(json.dumps(record))
            with self.assertRaises(AssertionError):
                m.audit(p)

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--campaign', required=True, type=Path)
    a = p.parse_args()
    CAMPAIGN = a.campaign
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(AuditTests))
    target = a.campaign / 'AUDIT-NEGATIVE-CONTROLS.json'
    assert not target.exists(), 'Preserve existing results'
    target.write_text(json.dumps({'result': 'PASS' if result.wasSuccessful() else 'FAIL', 'tests': result.testsRun,
        'hardware_access': False, 'auditor_sha256': hashlib.sha256((W / 'integration/audit_model_replacement.py').read_bytes()).hexdigest(),
        'test_source_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}, indent=2) + '\n')
    raise SystemExit(not result.wasSuccessful())
