"""Current-revision boundaries and historical archive fixtures; no hardware."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

HERE=Path(__file__).resolve().parent
PACKAGE=HERE.parent


def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path);value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value


compat=module('_current_v4_compat_fixture',HERE/'seeded_release_compat.py')
browser=module('_current_v4_browser_fixture',HERE/'check_long_context_browser.py')


class CurrentBrowserBoundaryTests(unittest.TestCase):
    def candidate(self):
        return dict(image_sha256='1'*64,model_image_sha256=compat.MODEL,hardware_inputs_sha256='2'*64,
                    host_source_inputs={'host-app/UNIT-ONLY.py':dict(bytes=4,sha256='3'*64)})

    def test_pending_status_credits_no_archive_output_or_origin_receipt(self):
        candidate=self.candidate();row=browser.pending_status(candidate)
        self.assertEqual(browser.status_binding(row,candidate),'pending')
        self.assertEqual(row['credited_cases'],0);self.assertIsNone(row['archive'])
        self.assertIsNone(row['source_inputs_receipt_sha256']);self.assertIsNone(row['source_finished_receipt_sha256'])

    def test_pending_cannot_inherit_old_browser_counts_or_passes(self):
        candidate=self.candidate();base=browser.pending_status(candidate)
        changes=[('credited_cases',10),('credited_cases',104),('archive',{'path':'old-browser.json'}),
                 ('source_inputs_receipt_sha256','4'*64),('source_finished_receipt_sha256','5'*64),
                 ('image_sha256',compat.OLD_IMAGE),('hardware_inputs_sha256','9'*64)]
        for key,value in changes:
            with self.subTest(field=key,value=value):
                row=dict(base,**{key:value})
                with self.assertRaises(ValueError):browser.status_binding(row,candidate)
        for flag in('passed','actual_browser_test_passed','release_qualified'):
            with self.subTest(extra=flag),self.assertRaises(ValueError):
                browser.status_binding(dict(base,**{flag:True}),candidate)

    def test_historical_image_never_becomes_current_browser_evidence(self):
        candidate=dict(self.candidate(),image_sha256=compat.OLD_IMAGE)
        with self.assertRaises(ValueError):browser.status_binding(browser.pending_status(candidate),candidate)
        with self.assertRaisesRegex(ValueError,'Historical image'):
            browser.validate_complete({},Path('/UNIT-ONLY-NOT-READ'),candidate)

    def test_case_types_include_full_window_and_dynamic_stop(self):
        self.assertEqual(len(browser.CASES),12)
        self.assertEqual(browser.CASES[-2],('prefix2048-greedy','0',None,1))
        self.assertEqual(browser.CASES[-1],('prefix2047-stop','1','A',2))
        self.assertEqual(browser.CASES[-4],('stopped-t1-b','1','B',128))
        self.assertNotIn('104',repr(browser.CASES));self.assertNotIn('75',repr(browser.CASES))

    def test_full_prompt_commands_upload_every_actual_input(self):
        row=dict(temperature='0',seed=None,prompt_tokens=[7,8,9],generated=[200])
        commands=browser.case_commands(row)
        self.assertEqual([r[0]for r in commands],['clear','settings','append','append','append','step','clear'])
        self.assertEqual([r[4]for r in commands if r[0]=='append'],[7,8,9])


class HistoricalArchiveBoundaryTests(unittest.TestCase):
    def make_zip(self,folder,extra=None,duplicate=False,symlink=False):
        payload=b'UNIT-ONLY historical payload, never a qualified image\n';image=hashlib.sha256(payload).hexdigest()
        name='prebuilt/seeded-sampling/project/impl/pnr/shared_product.fs'
        files={name:dict(bytes=len(payload),sha256=image)};members={name:payload}
        if extra:files[extra]=dict(bytes=1,sha256=hashlib.sha256(b'x').hexdigest());members[extra]=b'x'
        raw=(json.dumps(dict(files=files),sort_keys=True)+'\n').encode();path=folder/'UNIT-ONLY.zip'
        with zipfile.ZipFile(path,'w')as z:
            for member,data in dict(members,**{'MANIFEST.json':raw}).items():
                info=zipfile.ZipInfo(member);info.external_attr=(0o120777 if symlink and member==name else 0o100644)<<16;z.writestr(info,data)
            if duplicate:z.writestr(name,payload)
        return path,image,hashlib.sha256(raw).hexdigest()

    def test_exact_member_validation_and_unsafe_archive_refusals(self):
        for kind in('valid','escape','backslash','duplicate','symlink'):
            with self.subTest(kind=kind),tempfile.TemporaryDirectory()as directory:
                path,image,manifest=self.make_zip(Path(directory),extra='../escape'if kind=='escape'else'a\\b'if kind=='backslash'else None,
                    duplicate=kind=='duplicate',symlink=kind=='symlink')
                # The fixture image identity is intentionally synthetic and is
                # patched only in this unit process, never written as a gate.
                with patch.object(compat,'OLD_IMAGE',image):
                    if kind=='valid':self.assertEqual(set(compat.archive_files(path,manifest)),{'MANIFEST.json','prebuilt/seeded-sampling/project/impl/pnr/shared_product.fs'})
                    else:
                        with self.assertRaises(ValueError):compat.archive_files(path,manifest)

    def test_record_pins_are_not_a_source_of_default_current_authority(self):
        with tempfile.TemporaryDirectory()as directory:
            package=Path(directory)
            self.assertFalse(compat.is_current(package))
            (package/'CANDIDATE.json').write_text(json.dumps(dict(schema='long-context-private-recipient-v1',image_sha256='1'*64)))
            self.assertTrue(compat.is_current(package))
            with patch.object(compat,'EXPECTED_IMAGE',None),self.assertRaisesRegex(ValueError,'not reviewed/materialized'):
                compat.check_current(package,'context')


@unittest.skipUnless((PACKAGE/'CANDIDATE.json').is_file(),'No actual exported current recipient in this source-only preparation tree')
class ActualCurrentRecipientTests(unittest.TestCase):
    def test_actual_current_status_and_raw_numerical_record(self):
        result=compat.check_current(PACKAGE,'numerical')
        self.assertEqual(result['current_model_cases'],30);self.assertEqual(result['current_heads'],108)
        self.assertEqual(result['current_head_rows'],434052);self.assertFalse(result['integer_model_inference_replayed'])

    def test_actual_browser_phase_is_explicit(self):
        row=browser.check(PACKAGE)
        if row['state']=='pending':
            self.assertFalse(row['passed']);self.assertEqual(row['credited_cases'],0)
            with self.assertRaisesRegex(ValueError,'pending'):browser.check(PACKAGE,True)
        else:
            self.assertTrue(row['passed']);self.assertEqual(row['credited_cases'],12)
            self.assertTrue(browser.check(PACKAGE,True)['passed'])


if __name__=='__main__':unittest.main(verbosity=2)
