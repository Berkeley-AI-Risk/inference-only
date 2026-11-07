"""Small driver refusal tests; these synthetic records are NOT RTL results."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location('fresh_rtl_ci_runner', Path(__file__).with_name('runner.py'))
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)


class CoverageTests(unittest.TestCase):
    def qwen(self):
        return dict(passed=True, schedules=3, commands_sent=138, results_checked=129,
                    held_checks=4182, fabric_resets=6, active_clear_cancellations=3,
                    pending_clear_replacements=3)

    def tang(self):
        return dict(passed=True, schedules=3, words_sent=3396, words_checked=3360,
                    reset_discarded_words=36, coordinated_resets=12,
                    held_checks=10042, full_checks=6149, capacity_words=4)

    def test_complete_qwen_counts(self):
        RUNNER.validate_result('qwen', self.qwen())

    def test_complete_tang_counts(self):
        RUNNER.validate_result('tang', self.tang())

    def test_missing_cancellation_is_not_a_pass(self):
        row = self.qwen(); row['active_clear_cancellations'] = 0
        with self.assertRaisesRegex(ValueError, 'Incomplete Qwen'):
            RUNNER.validate_result('qwen', row)

    def test_missing_stalls_are_not_a_pass(self):
        row = self.tang(); row['full_checks'] = 0
        with self.assertRaisesRegex(ValueError, 'Incomplete Tang'):
            RUNNER.validate_result('tang', row)

    def test_nonconservation_is_not_a_pass(self):
        row = self.tang(); row['words_checked'] += 1
        with self.assertRaisesRegex(ValueError, 'Incomplete Tang'):
            RUNNER.validate_result('tang', row)

    def test_one_clock_schedule_is_not_complete(self):
        row = self.qwen(); row['schedules'] = 1
        with self.assertRaisesRegex(ValueError, 'behavioral completion'):
            RUNNER.validate_result('qwen', row)

    def test_boolean_counter_is_refused(self):
        row = self.qwen(); row['held_checks'] = True
        with self.assertRaisesRegex(ValueError, 'nonnegative integers'):
            RUNNER.validate_result('qwen', row)


class WarningTests(unittest.TestCase):
    def check(self, text, family='qwen'):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            (folder/'stdout.log').write_text('')
            (folder/'stderr.log').write_text(text)
            return RUNNER.warnings(folder, family)

    def test_clean_is_clean(self):
        self.assertTrue(self.check('', 'tang')['warning_free'])

    def test_known_metadata_parameter(self):
        row = "%Warning-UNUSEDPARAM: /source/qwen_async_stream_fifo.sv:18:15: Parameter is not used: 'MEMORY_STYLE'\n"
        self.assertFalse(self.check(row)['warning_free'])

    def test_known_reset_warning_remains_visible(self):
        row = "%Warning-SYNCASYNCNET: /source/qwen_async_stream_fifo.sv:33:58: Signal flopped as both synchronous and async: 'qwen_token_command_cdc.results.source_reset_release'\n"
        result = self.check(row)
        self.assertEqual(result['counts'], {'SYNCASYNCNET': 1})
        self.assertTrue(result['enforced'])

    def test_other_reset_signal_is_not_whitelisted(self):
        row = "%Warning-SYNCASYNCNET: /source/qwen_async_stream_fifo.sv:33:58: Signal flopped as both synchronous and async: 'other_reset'\n"
        with self.assertRaisesRegex(ValueError, 'Unrecognized warning'):
            self.check(row)

    def test_other_parameter_is_not_whitelisted(self):
        row = "%Warning-UNUSEDPARAM: /source/qwen_async_stream_fifo.sv:18:15: Parameter is not used: 'SECURITY_GATE'\n"
        with self.assertRaisesRegex(ValueError, 'Unrecognized warning'):
            self.check(row)

    def test_other_file_is_not_whitelisted(self):
        row = "%Warning-UNUSEDPARAM: /source/unrelated.sv:18:15: Parameter is not used: 'MEMORY_STYLE'\n"
        with self.assertRaisesRegex(ValueError, 'Unrecognized warning'):
            self.check(row)

    def test_width_warning_is_not_globally_suppressed(self):
        with self.assertRaisesRegex(ValueError, 'Unexpected lint'):
            self.check('%Warning-WIDTH: /source/changed.sv:1:1: Wrong width\n')

    def test_unknown_warning_format_is_refused(self):
        with self.assertRaisesRegex(ValueError, 'Unclassified compiler warning'):
            self.check('%Warning: Unexpected warning shape\n')

    def test_no_tang_warning_exception(self):
        with self.assertRaisesRegex(ValueError, 'Unexpected lint'):
            self.check('%Warning-WIDTHEXPAND: /source/fifo.sv:1:1: Arithmetic changed\n', 'tang')


class SourceSelectionTests(unittest.TestCase):
    def test_arguments_come_from_selected_paths(self):
        selected = dict(ordered_local_verilog=['project/defines.v', 'project/path/fifo.sv'],
                        headers=[], defines=[], top_source='project/path/fifo.sv')
        args = RUNNER.source_arguments(selected, Path('/staged'))
        self.assertEqual(args[-2:], ['/staged/project/defines.v', '/staged/project/path/fifo.sv'])
        self.assertNotIn('/staged/historical', args)

    def test_mutant_failures_are_named_behavior_checks(self):
        self.assertEqual(RUNNER.MUTANTS['qwen'][2], 'FAIL qwen_command_cdc cancelled_response')
        self.assertEqual(RUNNER.MUTANTS['tang'][2], 'FAIL tang_fifo data_order')


class ElaborationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.stage = self.root/'selected'
        self.stage.mkdir()
        self.selected = dict(top='qwen_token_command_cdc', family='qwen',
                             top_source='top.sv', source_identities={'top.sv': {}, 'fifo.sv': {}})
        def parameter(name, value):
            return dict(varType='GPARAM', name=name,
                        valuep=[dict(type='CONST', name="32'sh"+format(value, 'x'))])
        def fifo(width):
            return dict(type='MODULE', name='fifo'+str(width), origName='qwen_async_stream_fifo',
                        stmtsp=[parameter('WIDTH', width), parameter('ADDRESS_BITS', 2),
                                parameter('ZERO_WHEN_INVALID', 1), parameter('REFRESH_FREE_WRITE_SLOT', 0)])
        self.tree = dict(type='NETLIST', modulesp=[
            dict(type='MODULE', name='qwen_token_command_cdc', origName='qwen_token_command_cdc', stmtsp=[]),
            fifo(68), fifo(72)])
        self.metadata = dict(files={n: dict(realpath=str(self.stage/n)) for n in ('top.sv', 'fifo.sv')})

    def check(self):
        tree, metadata = self.root/'tree.json', self.root/'meta.json'
        tree.write_text(json.dumps(self.tree)); metadata.write_text(json.dumps(self.metadata))
        return RUNNER.elaboration(tree, metadata, self.selected, self.stage)

    def test_expected_actual_modules_and_parameters(self):
        result = self.check()
        self.assertEqual(result['parsed_selected_files'], ['fifo.sv', 'top.sv'])
        self.assertFalse(result['vendor_blackboxes_used'])

    def test_missing_dependency_refused(self):
        self.tree['modulesp'] = self.tree['modulesp'][:1]
        with self.assertRaisesRegex(ValueError, 'Unexpected/missing elaborated'):
            self.check()

    def test_extra_module_refused(self):
        self.tree['modulesp'].append(dict(type='MODULE', name='other', origName='other', stmtsp=[]))
        with self.assertRaisesRegex(ValueError, 'Unexpected/missing elaborated'):
            self.check()

    def test_different_fifo_parameter_refused(self):
        self.tree['modulesp'][1]['stmtsp'][0]['valuep'][0]['name'] = "32'sh801"
        with self.assertRaisesRegex(ValueError, 'Different actual production FIFO'):
            self.check()

    def test_unselected_input_refused(self):
        self.metadata['files']['extra'] = dict(realpath=str(self.stage/'old_alternative.sv'))
        with self.assertRaisesRegex(ValueError, 'Unselected compiler input'):
            self.check()

    def test_external_hdl_refused(self):
        self.metadata['files']['extra'] = dict(realpath=str(self.root/'fake_vendor.sv'))
        with self.assertRaisesRegex(ValueError, 'Unexpected external HDL'):
            self.check()

    def test_absent_compiled_top_refused(self):
        del self.metadata['files']['top.sv']
        with self.assertRaisesRegex(ValueError, 'did not read coverage top'):
            self.check()

    def test_non_netlist_parser_record_refused(self):
        self.tree['type'] = 'INVENTORY'
        with self.assertRaisesRegex(ValueError, 'actual Verilator netlist'):
            self.check()


if __name__ == '__main__':
    unittest.main()
