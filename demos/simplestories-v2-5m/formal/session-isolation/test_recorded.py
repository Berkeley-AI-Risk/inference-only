"""Refusal checks for evidence corruption and filesystem boundaries."""
import gzip
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec=importlib.util.spec_from_file_location('_recorded_session',Path(__file__).with_name('check_recorded.py'))
c=importlib.util.module_from_spec(spec);spec.loader.exec_module(c)


class RefusalTests(unittest.TestCase):
    def test_unsafe_paths(self):
        with tempfile.TemporaryDirectory()as tmp:
            for name in ('../escape','/etc/passwd','x/../../escape','x\\escape'):
                with self.assertRaises(ValueError):c.safe(Path(tmp),name)

    def test_corrupt_or_oversized_object(self):
        with tempfile.TemporaryDirectory()as tmp:
            root=Path(tmp);(root/'objects').mkdir();raw=b'current writer';packed=gzip.compress(raw,mtime=0)
            name='objects/'+c.sha(raw)+'.gz';p=root/name;p.write_bytes(packed)
            row=dict(bytes=len(raw),sha256=c.sha(raw),object=name,compressed_bytes=len(packed),compressed_sha256=c.sha(packed))
            e=c.Evidence.__new__(c.Evidence);e.root=root;e.index={'files':{'payload':row}}
            self.assertEqual(e.raw('payload'),raw)
            row['bytes']-=1
            with self.assertRaises(ValueError):e.raw('payload')
            row['bytes']+=1;p.write_bytes(packed[:-1]+bytes([packed[-1]^1]))
            with self.assertRaises(ValueError):e.raw('payload')

    def test_index_and_external_path_refusal(self):
        with tempfile.TemporaryDirectory()as tmp:
            model=Path(tmp);(model/'evidence/session-isolation').mkdir(parents=True)
            (model/'evidence/session-isolation/INDEX.json').write_text('{}')
            with self.assertRaises(ValueError):c.Evidence(model)
            e=c.Evidence.__new__(c.Evidence);e.model=model
            e.index=dict(recorded_workspace='/recorded/campaign',recorded_public_model='/recorded/model',files={},external_public_paths={})
            v=c.virtual_path(e)
            with self.assertRaises(ValueError):v('/etc/passwd').read_bytes()


if __name__=='__main__':unittest.main()
