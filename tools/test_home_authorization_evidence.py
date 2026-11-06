"""Reject altered home-authorization wire, signature and timing evidence."""
from pathlib import Path
import hashlib
import importlib.util
import json
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
TARGET=ROOT/'demos/simplestories-v2-5m/variants/home-authorization'
spec=importlib.util.spec_from_file_location('home_evidence_test',TARGET/'tools/check_evidence.py')
evidence=importlib.util.module_from_spec(spec);spec.loader.exec_module(evidence)


class HomeEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.capture=Path(self.temp.name)/'capture'
        shutil.copytree(TARGET/'evidence/repair-board-2026-11-05',self.capture)
        self.baseline=evidence.verify(TARGET,self.capture)

    def test_actual_record_passes(self):
        result=self.baseline
        self.assertEqual(result['distinct_nonces'],10)
        self.assertEqual(result['benchmark_counted_outputs'],254)

    def test_raw_time_cannot_be_replaced_by_capture_self_agreement(self):
        raw=self.capture/'common-trial-1-raw.json'
        data=json.loads(raw.read_text())
        data['events'][5]['validated_return_monotonic_ns']+=100
        raw.write_text(json.dumps(data,indent=2)+'\n')
        capture=self.capture/'COMMON-SPEED.json'
        data=json.loads(capture.read_text())
        data['cases'][0]['raw_capture_sha256']=hashlib.sha256(raw.read_bytes()).hexdigest()
        capture.write_text(json.dumps(data,indent=2)+'\n')
        with self.assertRaisesRegex(ValueError,re.escape("assert case['reply_monotonic_ns']==")):
            evidence.verify(TARGET,self.capture)

    def test_corrupt_home_signature_is_rejected(self):
        path=self.capture/'TRANSCRIPT.json'
        events=json.loads(path.read_text())
        event=next(e for e in events if e.get('decision')=='approved')
        grant=bytearray.fromhex(event['grant_hex']);grant[-1]^=1;event['grant_hex']=grant.hex()
        path.write_text(json.dumps(events,indent=2)+'\n')
        (self.capture/'EVENTS.jsonl').write_text(''.join(json.dumps(e)+'\n'for e in events))
        with self.assertRaisesRegex(ValueError,re.escape('assert h.su.lms_verify(key,request,grant[128:])')):
            evidence.verify(TARGET,self.capture)

    def test_old_grant_cannot_be_substituted_for_renewal(self):
        path=self.capture/'TRANSCRIPT.json'
        events=json.loads(path.read_text())
        grants=[e for e in events if e.get('decision')=='approved']
        grants[1]['grant_hex']=grants[0]['grant_hex']
        path.write_text(json.dumps(events,indent=2)+'\n')
        (self.capture/'EVENTS.jsonl').write_text(''.join(json.dumps(e)+'\n'for e in events))
        with self.assertRaisesRegex(ValueError,re.escape('grant[:128]==request')):
            evidence.verify(TARGET,self.capture)


    def test_historical_capture_is_rejected_by_current_identity(self):
        refusal="assert recovery['candidate_sha256']==review['sha256']==sha(a.candidate)"
        with self.assertRaisesRegex(ValueError,re.escape(refusal)):
            evidence.verify(TARGET,TARGET/'evidence/board-25mhz-v9')


class ReplacementEvidenceTests(unittest.TestCase):
    def test_public_model_replacement_replay_and_controls(self):
        result=subprocess.run([sys.executable,'-I','-S','-B',str(TARGET/'tests/test_model_replacement_evidence.py')],capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

if __name__=='__main__':unittest.main()
