"""File-only regression tests for the archived receipts and reusable helpers."""
from pathlib import Path
import shutil,tempfile,types,unittest
from unittest.mock import patch

def module(name):
    p=Path(__file__).resolve().with_name(name+'.py')
    m=types.ModuleType(name);m.__file__=str(p)
    exec(compile(p.read_bytes(),str(p),'exec'),m.__dict__)
    return m

build=module('build_outputs')
bounded=module('bounded_process')
recorded=module('check_recorded_rom16')

def ar_bytes(members):
    raw=b'!<arch>\n'
    for name,payload in members:
        head=(name+'/').ljust(16)+'0'.ljust(12)+'0'.ljust(6)+'0'.ljust(6)+'100644'.ljust(8)+str(len(payload)).ljust(10)+chr(96)+'\n'
        assert len(head)==60
        raw+=head.encode()+payload+(b'\n' if len(payload)&1 else b'')
    return raw

class Tools(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='hwic-checkpoint-')
        self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
        (self.root/'a.o').write_bytes(b'one')
        (self.root/'b.o').write_bytes(b'two!')
        self.members=[('a.o',b'one'),('b.o',b'two!')]
    def archive(self,members):
        p=self.root/'design.a';p.write_bytes(ar_bytes(members));return p
    def test_archive_wrapper_and_bytes(self):
        self.archive(self.members)
        r=build.verify_design_archive(self.root,['a','b'],'design.a')
        self.assertEqual(r['actual_design_object_count'],2)
    def test_wrong_object_bytes(self):
        p=self.archive([('a.o',b'bad'),self.members[1]])
        with self.assertRaises(AssertionError):
            build.verify_archive(p,[build.pin(self.root/'a.o'),build.pin(self.root/'b.o')])
    def test_missing_duplicate_and_unexpected_objects(self):
        for members in [self.members[:1],self.members+[self.members[0]],self.members+[('c.o',b'extra')]]:
            with self.subTest(members=members):
                p=self.archive(members)
                with self.assertRaises(AssertionError):
                    build.verify_archive(p,[build.pin(self.root/'a.o'),build.pin(self.root/'b.o')])
    def test_duplicate_expected_basename(self):
        p=self.archive(self.members[:1]);item=build.pin(self.root/'a.o')
        with self.assertRaisesRegex(AssertionError,'DUPLICATE_EXPECTED'):
            build.verify_archive(p,[item,item])
    def test_raw_source_and_stale_bytecode_ignored(self):
        p=self.root/'input.py';p.write_text('value=37\n')
        (self.root/'input.pyc').write_bytes(b'not valid bytecode')
        self.assertEqual(bounded.load_source(bounded.pin(p),'hwic_test_raw_good').value,37)
    def test_same_bytes_hashed_and_compiled(self):
        p=self.root/'input.py';p.write_text('value=37\n');desc=bounded.pin(p)
        original=Path.read_bytes
        def poisoned(path):
            return b'raise RuntimeError("unverified source executed")\n' if path.resolve()==p.resolve() else original(path)
        with patch.object(Path,'read_bytes',poisoned):
            with self.assertRaises(AssertionError):
                bounded.load_source(desc,'hwic_test_raw_bad')
    def test_receipt_and_changed_excerpt(self):
        source=Path(__file__).resolve().parents[1]/'evidence/rom16-2026-11-03'
        self.assertEqual(recorded.verify(source)['recorded_rows'],68544)
        dest=self.root/'evidence';shutil.copytree(source,dest)
        with (dest/'normal-seed-1.log').open('ab') as f:f.write(b'changed')
        with self.assertRaises(AssertionError):recorded.verify(dest)

if __name__=='__main__':
    unittest.main()

