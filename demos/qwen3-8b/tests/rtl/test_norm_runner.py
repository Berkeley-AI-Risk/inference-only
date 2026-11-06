"""Offline runner controls; not a substitute for native RMSNorm execution."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

HERE=Path(__file__).resolve().parent
SPEC=importlib.util.spec_from_file_location('qwen_rms_regression',HERE/'run_norm.py')
RUNNER=importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)


class NormRunnerTests(unittest.TestCase):
    def summary(self):
        return dict(passed=True,normal_frames=26,head_frames=13,full_frames=13,
                    error_frames=8,cancelled_frames=6,checked_values=54934,
                    clears=4,resets=2,held_checks=1,input_bubbles=1,accepted_inputs=1,cycles=1)

    def test_frozen_widths_and_dependencies(self):
        self.assertEqual(RUNNER.CASE['widths'],[128,4096])
        self.assertIn('divSqrtRecFN_small.v',RUNNER.SOURCES)
        self.assertIn('addRecFN.v',RUNNER.SOURCES)
        self.assertEqual(RUNNER.CASE['top'],'qwen_rms_norm')

    def test_source_hash_binding(self):
        binding=RUNNER.verify_sources()
        self.assertEqual(binding['source_manifest']['sha256'],
                         '83c22320ac4e52947d1d89360c7b68d37c71ff3c45edb0df64459de5c3b8bee2')
        self.assertEqual(binding['files']['qwen_rms_norm.sv']['sha256'],
                         'afe3551f67e10b4aeb66451eb0c18e80606672bd812dde5285654b3302b558d0')

    def test_complete_summary(self):
        RUNNER.validate_summary(self.summary())
        self.assertEqual(13*(128+4096)+2*11,54934)

    def test_missing_or_false_coverage_rejected(self):
        for key in self.summary():
            r=self.summary()
            r.pop(key)
            with self.subTest(missing=key),self.assertRaises(ValueError):
                RUNNER.validate_summary(r)
        r=self.summary();r['passed']=False
        with self.assertRaises(ValueError):RUNNER.validate_summary(r)

    def test_boolean_and_wrong_count_rejected(self):
        for key in ('normal_frames','checked_values','held_checks','error_frames'):
            for value in (True,0,-1,1.5):
                r=self.summary();r[key]=value
                with self.subTest(key=key,value=value),self.assertRaises(ValueError):
                    RUNNER.validate_summary(r)

    def test_changed_helper_rejected(self):
        original=RUNNER.identity

        def altered(path):
            value=copy.deepcopy(original(path))
            if path==HERE/'run.py':value['sha256']='0'*64
            return value

        with patch.object(RUNNER,'identity',altered),self.assertRaisesRegex(ValueError,'helper changed'):
            RUNNER.verify_sources()

    def test_plan_has_no_native_model_or_hardware_action(self):
        child=subprocess.run([sys.executable,'-I','-S','-B',str(HERE/'run_norm.py'),'--plan'],
                             capture_output=True,text=True,check=True,timeout=15)
        record=json.loads(child.stdout)
        for key in ('native_tools_run','model_loaded','hardware_access','network_access'):
            self.assertIs(record[key],False)

    def test_refuses_existing_output_without_mutation(self):
        with tempfile.TemporaryDirectory() as directory:
            child=subprocess.run([sys.executable,'-I','-S','-B',str(HERE/'run_norm.py'),
                                  '--output',directory],capture_output=True,text=True,timeout=15)
            self.assertNotEqual(child.returncode,0)
            self.assertEqual(list(Path(directory).iterdir()),[])

    def test_refuses_missing_output(self):
        with self.assertRaisesRegex(ValueError,'fresh --output'):
            RUNNER.main([])

    def test_bounds_compile_parallelism(self):
        child=subprocess.run([sys.executable,'-I','-S','-B',str(HERE/'run_norm.py'),
                              '--plan','--jobs','8'],capture_output=True,text=True,timeout=15)
        self.assertEqual(child.returncode,2)
        self.assertEqual(child.stdout,'')


if __name__=='__main__':
    unittest.main()
