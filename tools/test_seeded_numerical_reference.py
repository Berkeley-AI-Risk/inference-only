"""Mutations of archived numerical evidence; no inference, compiler or hardware."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('numerical_archive_check',HERE/'check_seeded_numerical_reference.py')
check=importlib.util.module_from_spec(spec);spec.loader.exec_module(check)
PACKAGE=HERE.parent

class NumericalArchiveTests(unittest.TestCase):
    def setUp(self):self.data=json.loads((PACKAGE/check.RECORD).read_bytes())
    def test_published_archived_results_and_sources(self):
        result=check.check(PACKAGE);self.assertEqual(result['archived_native_outputs'],2136)
        self.assertFalse(result['integer_model_replayed'])
    def test_reject_missing_case_wrong_origin_engine_head_kv_prng_and_counts(self):
        for mutation in('case','origin','engine','head','kv','prng','count','extra'):
            with self.subTest(mutation=mutation):
                data=copy.deepcopy(self.data);r=data['replays']['native_all48']
                if mutation=='case':r['cases'].pop()
                elif mutation=='origin':r['source_receipt_sha256']='0'*64
                elif mutation=='engine':r['engine']='scalar'
                elif mutation=='head':r['cases'][0]['all_head_digests_match']=False
                elif mutation=='kv':r['cases'][0]['final_kv_matches']=False
                elif mutation=='prng':r['cases'][0]['final_prng_matches']=False
                elif mutation=='count':r['outputs_compared']+=1
                else:data['private_device']='synthetic-only'
                with self.assertRaises(ValueError):check.validate(data,PACKAGE)
    def test_reject_source_rom_test_identity_scope_and_invalid_host_times(self):
        for mutation in('source','rom','roundtrip','methods','test-source','model-replay','portability','nan','zero'):
            with self.subTest(mutation=mutation):
                data=copy.deepcopy(self.data)
                if mutation=='source':data['source_inventory']['sha256']='0'*64
                elif mutation=='rom':data['reconstruction']['files']['weights.i10.lsb0.bin']['sha256']='0'*64
                elif mutation=='roundtrip':data['reconstruction']['full_image_roundtrip_equal']=False
                elif mutation=='methods':data['native_tests']['methods'].pop()
                elif mutation=='test-source':data['native_tests']['test_source_sha256']='0'*64
                elif mutation=='model-replay':data['claims']['checker_replays_model']=True
                elif mutation=='portability':data['claims']['compiler_binary_portability_promised']=True
                elif mutation=='nan':data['replays']['native_all48']['elapsed_seconds']=float('nan')
                else:data['replays']['native_all48']['cases'][0]['seconds']=0
                with self.assertRaises(ValueError):check.validate(data,PACKAGE)

if __name__=='__main__':unittest.main()
