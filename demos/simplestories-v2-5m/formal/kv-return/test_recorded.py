"""Refusal controls for the portable normal-word evidence entrypoint."""
import copy,gzip,hashlib,importlib.util,json,tempfile,unittest
from pathlib import Path

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('guard_word_replay',HERE/'replay.py')
subject=importlib.util.module_from_spec(spec);spec.loader.exec_module(subject)


class RecordedReplayTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        packet=HERE.parents[1]/'evidence/kv-return'
        cls.index=json.loads((packet/'INDEX.json').read_text())
        cls.report=json.loads((packet/'REPLAY.json').read_text())
        cls.script=hashlib.sha256((HERE/'replay.py').read_bytes()).hexdigest()

    def test_named_complete_replay(self):
        subject.admit_replay(self.index,self.report,self.script)

    def test_missing_query(self):
        report=copy.deepcopy(self.report);report['independently_reconstructed_and_freshly_solved_queries'].pop()
        with self.assertRaises(ValueError):subject.admit_replay(self.index,report,self.script)

    def test_promoted_whole_device_claim(self):
        report=copy.deepcopy(self.report);report['whole_device_session_theorem']=True
        with self.assertRaises(ValueError):subject.admit_replay(self.index,report,self.script)

    def test_missing_native_normal_word_defect(self):
        report=copy.deepcopy(self.report);report['native_replays'].pop()
        with self.assertRaises(ValueError):subject.admit_replay(self.index,report,self.script)

    def test_changed_replay_entrypoint(self):
        with self.assertRaises(ValueError):subject.admit_replay(self.index,self.report,'0'*64)

    def test_changed_compressed_object(self):
        raw=b'proof fixture\n';packed=gzip.compress(raw,mtime=0);digest=subject.sha(raw)
        with tempfile.TemporaryDirectory()as folder:
            root=Path(folder);(root/'objects').mkdir();name='objects/'+digest+'.gz'
            row=dict(bytes=len(raw),sha256=digest,object=name,compressed_bytes=len(packed),compressed_sha256=subject.sha(packed))
            (root/'INDEX.json').write_text(json.dumps(dict(schema='closed-native-guard-returned-word-local-capsule-v3',
                recorded_workspace='/recorded/proof',files={'claim.txt':row})))
            (root/name).write_bytes(packed);self.assertEqual(subject.Packet(root).raw('claim.txt'),raw)
            broken=bytearray(packed);broken[-1]^=1;(root/name).write_bytes(broken)
            with self.assertRaises(ValueError):subject.Packet(root).raw('claim.txt')


if __name__=='__main__':unittest.main()
