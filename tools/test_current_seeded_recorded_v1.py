"""Recorded seeded host source routing and wire refusal controls; no FPGA/network."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
def module(name):
    spec=importlib.util.spec_from_file_location(name,ROOT/'tools'/(name+'.py'))
    value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value

host=module('seeded_recorded_host_context_v1')
browser=module('check_seeded_browser_recorded_v1')

class RecordedSeededContextTests(unittest.TestCase):
    def setUp(self):
        temporary=tempfile.TemporaryDirectory();self.addCleanup(temporary.cleanup)
        self.package=Path(temporary.name)
        names=[host.CONTEXT_PATH,*[host.PREFIX+name for name in host.ORIGINAL_SOURCES],host.TOKENIZER[0]]
        for name in names:
            path=self.package/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes((ROOT/name).read_bytes())
        self.candidate=json.loads((ROOT/'CANDIDATE.json').read_bytes())

    def test_exact_source_context_does_not_execute_or_require_live_host(self):
        for name in host.ORIGINAL_SOURCES:
            path=self.package/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text('raise RuntimeError("must never execute")\n')
        result=host.check(self.package,self.candidate)
        self.assertEqual(result['recorded_host_sources'],3)
        self.assertFalse(result['host_snapshots_executed'])
        self.assertFalse(result['current_shared_host_physical_qualification_inherited'])

    def test_only_three_literal_names_are_routed(self):
        expected=self.package.resolve()
        for name in host.ORIGINAL_SOURCES:self.assertEqual(host.source_path(self.package,name),expected/(host.PREFIX+name))
        for name in ('hardware/project/bank.sv','host-app/token_machine_uart.py'):
            self.assertEqual(host.source_path(self.package,name),expected/name)

    def test_changed_original_source_refused(self):
        path=self.package/(host.PREFIX+next(iter(host.ORIGINAL_SOURCES)))
        path.write_bytes(path.read_bytes()+b'\n// changed\n')
        with self.assertRaises(ValueError):host.check(self.package,self.candidate)

    def test_changed_context_metadata_refused(self):
        path=self.package/host.CONTEXT_PATH;path.write_bytes(path.read_bytes()+b' ')
        with self.assertRaises(ValueError):host.check(self.package,self.candidate)

    def test_extra_context_file_refused(self):
        (self.package/host.CONTEXT_PATH).with_name('extra.py').write_text('pass\n')
        with self.assertRaises(ValueError):host.check(self.package,self.candidate)

    def test_linked_snapshot_refused(self):
        path=self.package/(host.PREFIX+next(iter(host.ORIGINAL_SOURCES)))
        raw=path.read_bytes();other=self.package/'source-copy';other.write_bytes(raw)
        path.unlink();path.symlink_to(other)
        with self.subTest(kind='required-source-symlink'),self.assertRaises(ValueError):host.check(self.package,self.candidate)
        path.unlink();path.write_bytes(raw)
        directory=self.package/'other-directory';directory.mkdir()
        extra=(self.package/host.CONTEXT_PATH).with_name('extra-linked-directory')
        extra.symlink_to(directory,target_is_directory=True)
        with self.subTest(kind='extra-symlink-to-directory'),self.assertRaisesRegex(ValueError,'Linked'):
            host.check(self.package,self.candidate)

    def test_unsafe_source_name_refused(self):
        for name in ('../escape','/absolute','a/../b','a\\b','./name'):
            with self.subTest(name=name),self.assertRaises(ValueError):host.source_path(self.package,name)

    def test_wrong_seeded_image_refused(self):
        self.candidate['image_sha256']='0'*64
        with self.assertRaises(ValueError):host.check(self.package,self.candidate)

    def test_changed_candidate_host_map_refused(self):
        self.candidate['host_source_inputs'][next(iter(host.ORIGINAL_SOURCES))]['sha256']='0'*64
        with self.assertRaises(ValueError):host.check(self.package,self.candidate)

    def test_changed_tokenizer_refused(self):
        (self.package/host.TOKENIZER[0]).write_bytes(b'{}')
        with self.assertRaises(ValueError):host.check(self.package,self.candidate)

    def test_pending_status_cannot_credit_recorded_cases(self):
        row=browser.pending_status(self.candidate);row['credited_cases']=1
        with self.assertRaises(ValueError):browser.status_binding(row,self.candidate)

    def test_raw_reply_crc_mutation_refused(self):
        # Deliberately malformed reply is rejected before any synthetic command
        # timing/source result could be used as evidence.
        result=dict(temperature='0',seed=None,seed_used=False,step_seconds=[])
        command=('clear',browser.legacy(2),0x82,0,0)
        wire=[dict(sequence=1,elapsed_ns=0,event='command_intent',label='clear',hex=command[1]),
              dict(sequence=2,elapsed_ns=1,event='raw_chunk',direction='tx',hex=command[1]),
              dict(sequence=3,elapsed_ns=2,event='raw_chunk',direction='rx',hex='5a82000000')]
        with self.assertRaisesRegex(ValueError,'CRC'):browser.validate_wire(wire,[command],result)

if __name__=='__main__':unittest.main()
