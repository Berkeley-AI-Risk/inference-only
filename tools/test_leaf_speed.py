"""Offline mutation controls for current speed evidence and exact history."""
import copy
import hashlib
import json
from pathlib import Path
import unittest
import check_leaf_speed as subject


class LeafEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.package=Path(__file__).resolve().parents[1]
        self.data=json.loads((self.package/'evidence/leaf-speed/physical.json').read_text())

    def test_current_bindings(self):self.assertTrue(subject.check(self.package)['passed'])

    def test_wrong_rate(self):
        self.data['variants']['baseline']['around128']['cached_stream_tokens_per_second']*=2
        with self.assertRaises(ValueError):subject.check_physical(self.data)

    def test_missing_case(self):
        del self.data['variants']['kv-protected']['prefix2047']
        with self.assertRaises(ValueError):subject.check_physical(self.data)

    def test_clock_gap(self):
        self.data['variants']['baseline']['prefix2047']['clock_audit_passed']=False
        with self.assertRaises(ValueError):subject.check_physical(self.data)

    def test_unsupported_security_claims(self):
        for key in ('timing_qualified','configuration_independently_attested','physical_corruption_injection_tested'):
            with self.subTest(key=key):
                changed=copy.deepcopy(self.data);changed[key]=True
                with self.assertRaises(ValueError):subject.check_physical(changed)

    def test_unmatched_token(self):
        self.data['variants']['baseline']['known1']['generated_tokens'][0]+=1
        with self.assertRaises(ValueError):subject.check_physical(self.data)

    def test_reverse_edits_reject_corruption(self):
        before,bafter=b'old\n',b'new\n'
        change=dict(before_sha256=hashlib.sha256(before).hexdigest(),after_sha256=hashlib.sha256(bafter).hexdigest(),
            reverse_edits=[dict(start=0,end=1,before=['old\n'],after=['new\n'])])
        self.assertEqual(subject.restore_revision(bafter,change),before)
        with self.assertRaises(ValueError):subject.restore_revision(bafter+b'junk\n',change)
        change['reverse_edits'][0]['before']=['wrong\n']
        with self.assertRaises(ValueError):subject.restore_revision(bafter,change)

    def test_wrong_app_image_is_rejected(self):
        data=subject.read(self.package/'evidence/leaf-speed/release-rehearsal.json')
        data['trials']['baseline']['image_sha256']=subject.IMAGES['kv-protected']
        with self.assertRaises(ValueError):subject.check_rehearsal(self.package,data)

    def test_wrong_app_token_is_rejected(self):
        data=subject.read(self.package/'evidence/leaf-speed/release-rehearsal.json')
        data['trials']['baseline']['cases'][0]['generated_tokens'][0]+=1
        with self.assertRaises(ValueError):subject.check_rehearsal(self.package,data)

    def test_missing_app_lifecycle_is_rejected(self):
        data=subject.read(self.package/'evidence/leaf-speed/release-rehearsal.json')
        data['trials']['kv-protected']['cases'].pop()
        with self.assertRaises(ValueError):subject.check_rehearsal(self.package,data)

    def test_unknown_is_not_counted_as_proved(self):
        data=subject.read(self.package/'evidence/leaf-speed/release-replay.json')
        data['connected_shell']['unresolved_conclusions']=[39]
        data['connected_shell']['complete_second_solver']=True
        with self.assertRaises(ValueError):subject.check_replay(self.package,data)

    def test_missing_replay_source_is_rejected(self):
        data=subject.read(self.package/'evidence/leaf-speed/release-replay.json')
        del data['source_sha256']['hardware/project/candidate.sv']
        with self.assertRaises(ValueError):subject.check_replay(self.package,data)

    def test_step_rate_cannot_be_replaced_by_streaming_rate(self):
        data=subject.read(self.package/'evidence/leaf-speed/host-timing.json')
        row=data['full_context']['baseline']
        row['step_only_tokens_per_second']=row['streaming_tokens_per_second']
        with self.assertRaises(ValueError):subject.check_host_timing(data,self.data)

    def test_firmware_cause_is_not_established(self):
        data=subject.read(self.package/'evidence/leaf-speed/host-timing.json')
        data['firmware_cause_established']=True
        with self.assertRaises(ValueError):subject.check_host_timing(data,self.data)

    def test_failed_latency_experiment_cannot_be_reported_as_success(self):
        data=subject.read(self.package/'evidence/leaf-speed/host-timing.json')
        data['latency_setting_experiment']['latency_improved']=True
        with self.assertRaises(ValueError):subject.check_host_timing(data,self.data)

    def test_wrong_tool_identity_is_rejected(self):
        native=subject.read(self.package/'evidence/leaf-speed/native.json')['variants']['baseline']
        tool=subject.read(self.package/'evidence/leaf-speed/tool-provenance.json')
        tool['tool_sha256']='0'*64
        with self.assertRaises(ValueError):subject.check_build_provenance(native,tool)

    def test_incomplete_route_is_rejected(self):
        native=subject.read(self.package/'evidence/leaf-speed/native.json')['variants']['baseline']
        tool=subject.read(self.package/'evidence/leaf-speed/tool-provenance.json')
        native['route_completed']=False
        with self.assertRaises(ValueError):subject.check_build_provenance(native,tool)


if __name__=='__main__':unittest.main()
