"""Offline regression tests for the narrow Qwen disclosure checker."""
import hashlib
import importlib.util
from pathlib import Path
import unittest

TOOLS = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location('qwen_disclosures', TOOLS/'check_qwen_disclosures.py')
CHECKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKER)


class DisclosureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = (TOOLS.parent/'demos/qwen3-1.7b/hardware/design/cl_qwen.sv').read_text()

    def test_fields_cover_all_bits(self):
        self.assertEqual(CHECKER.management_bits(self.source), [
            ('15:12', 'lifecycle_error_code'), ('11:8', 'clock_error_code'),
            ('7:6', "2'b0"), ('5', 'clock_failed'), ('4', 'pcis_guard_error'),
            ('3', 'hbm_ready'), ('2', 'clock_ready'), ('1', 'lifecycle_failed'), ('0', 'online'),
        ])

    def test_comments_do_not_change_shape(self):
        self.assertEqual(CHECKER.management_bits('/* example attention state */\n'+self.source),
                         CHECKER.management_bits(self.source))

    def test_attention_substitution_is_not_the_recorded_display(self):
        with self.assertRaises(ValueError):
            CHECKER.management_bits(self.source.replace('clock_failed,pcis_guard_error,hbm_ready,clock_ready,lifecycle_failed,online}',
                                                        'attention_state,attention_valid}'))

    def test_second_driver_rejected(self):
        with self.assertRaises(ValueError):
            CHECKER.management_bits(self.source+'\nassign cl_sh_status_vled=16\'b0;\n')

    def test_second_clocked_update_rejected(self):
        with self.assertRaises(ValueError):
            CHECKER.management_bits(self.source+'\nalways @(posedge clk_main_a0) management_status<=0;\n')

    def test_extra_indexed_update_rejected(self):
        with self.assertRaises(ValueError):
            CHECKER.management_bits(self.source+'\nalways @(posedge clk_main_a0) management_status[0]<=0;\n')

    def test_reset_change_rejected(self):
        with self.assertRaises(ValueError):
            CHECKER.management_bits(self.source.replace("management_status<=16'b0", "management_status<=16'b1"))

    def test_clock_change_rejected(self):
        with self.assertRaises(ValueError):
            CHECKER.management_bits(self.source.replace('always @(posedge clk_main_a0) begin', 'always @(posedge core_clk) begin', 1))

    def test_width_change_rejected(self):
        with self.assertRaises(ValueError):
            CHECKER.management_bits(self.source.replace('[3:0] clock_error_code', '[4:0] clock_error_code'))

    def test_identity_checks_size_and_hash(self):
        data = b'test source'
        expected = dict(bytes=len(data), sha256=hashlib.sha256(data).hexdigest())
        CHECKER.verify_identity(data, expected, 'test')
        for altered in (dict(expected, bytes=len(data)+1), dict(expected, sha256='0'*64)):
            with self.assertRaises(ValueError):
                CHECKER.verify_identity(data, altered, 'test')

    def test_cdc_uses_summary_not_individual_rows(self):
        self.assertEqual(CHECKER.critical_cdc_counts(
            'CDC-1   Critical      1  unknown\n 1 CDC-1 Critical unknown\n'
            'CDC-10  Critical     35  logic\n'), [('CDC-1', 1), ('CDC-10', 35)])

    def test_ambiguous_cdc_summary_rejected(self):
        with self.assertRaises(ValueError):
            CHECKER.critical_cdc_counts('CDC-1 Critical 1 unknown\nCDC-1 Critical 2 other\n')

    def test_missing_cdc_summary_rejected(self):
        with self.assertRaises(ValueError):
            CHECKER.critical_cdc_counts('no summary')

    def test_generated_disclosure_checked_exactly(self):
        block = CHECKER.display_block(CHECKER.management_bits(self.source))
        CHECKER.check_block('intro\n'+block+'\nend', 'MANAGEMENT DISPLAY', block)
        for altered in ('', block+block, block.replace('remains unverified', 'is verified')):
            with self.assertRaises(ValueError):
                CHECKER.check_block(altered, 'MANAGEMENT DISPLAY', block)

    def test_generated_cdc_disclosure_checked(self):
        block = CHECKER.cdc_block([('CDC-1', 1), ('CDC-7', 1), ('CDC-10', 35), ('CDC-13', 2)])
        self.assertIn('**39 critical', block)
        CHECKER.check_block(block, 'CDC DISCLOSURE', block)

    def test_both_packaged_designs_without_overclaiming(self):
        result = CHECKER.check()
        self.assertTrue(result['passed'])
        self.assertEqual(set(result['models']), set(CHECKER.MODELS))
        for key in ('routed_display_correspondence_verified', 'authenticated_operand_use_proved',
                    'full_cdc_signoff', 'hardware_access', 'cloud_actions'):
            self.assertIs(result[key], False)


if __name__ == '__main__':
    unittest.main(verbosity=2)
