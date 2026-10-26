"""Controls for common-workload eligibility and elapsed-time accounting."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('common_speed', Path(__file__).with_name('fpga_speed_benchmark.py'))
bench = importlib.util.module_from_spec(spec);spec.loader.exec_module(bench)


class CommonSpeedTests(unittest.TestCase):
    def make_trial(self, spacing=1, **kwargs):
        values = dict(prompt=[378], tokens=list(range(128)), expected=list(range(128)),
                      arrivals=[i*spacing for i in range(128)], cached_commands=[0.5]*127,
                      first_step=10, identity={'image':'fixed','clock_mhz':25})
        values.update(kwargs)
        return bench.trial(**values)

    def test_host_gaps_are_included_in_headline(self):
        row = bench.pool([self.make_trial(), self.make_trial()])
        self.assertEqual(row['cached_tokens_per_second'], 1)
        self.assertEqual(row['command_only_diagnostic_tokens_per_second'], 2)
        self.assertEqual(row['counted_cached_outputs'], 254)

    def test_pool_elapsed_time_instead_of_averaging_rates(self):
        result = bench.pool([self.make_trial(), self.make_trial(2)])
        self.assertAlmostEqual(result['cached_tokens_per_second'], 254/381)
        self.assertNotEqual(result['cached_tokens_per_second'], (1+0.5)/2)

    def test_excludes_first_output_and_timestamp_origin(self):
        a = self.make_trial()
        b = self.make_trial(arrivals=[1000+i for i in range(128)], first_step=999)
        self.assertEqual(a['cached_host_seconds'], b['cached_host_seconds'])
        self.assertNotEqual(a['first_step_seconds'], b['first_step_seconds'])

    def test_three_output_replay_cannot_count_as_128(self):
        with self.assertRaisesRegex(ValueError, '128 outputs'):
            self.make_trial(tokens=[1,2,3], expected=[1,2,3], arrivals=[0,1,2], cached_commands=[0.5,0.5])

    def test_same_capture_cannot_count_as_two_repetitions(self):
        a=self.make_trial(capture_sha256='a'*64)
        with self.assertRaisesRegex(ValueError, 'cannot count twice'):bench.pool([a,a])

    def test_missing_second_trial_rejected(self):
        with self.assertRaisesRegex(ValueError, 'two complete'):
            bench.pool([self.make_trial()])

    def test_longer_prompt_sampling_early_stop_and_teacher_forcing_rejected(self):
        for values in ({'prompt':[1,2]}, {'temperature':1}, {'decoding':'sample'},
                       {'clear_before':False}, {'stop_at_eos':True}, {'feedback_dependent':False}):
            with self.subTest(values=values), self.assertRaises(ValueError):self.make_trial(**values)

    def test_raw_rx_and_command_duration_cannot_replace_caller_timestamps(self):
        for boundary in ('raw_rx', 'command_only'):
            with self.subTest(boundary=boundary), self.assertRaisesRegex(ValueError, 'boundary'):
                self.make_trial(boundary=boundary)

    def test_nonmonotonic_or_nonfinite_time_rejected(self):
        for value in (0, -1, float('nan'), float('inf')):
            arrivals=list(range(128));arrivals[1]=value
            with self.subTest(value=value), self.assertRaises(ValueError):self.make_trial(arrivals=arrivals)

    def test_wrong_reference_output_rejected(self):
        tokens=list(range(128));tokens[-1]+=1
        with self.assertRaisesRegex(ValueError, 'reference'):self.make_trial(tokens=tokens)

    def test_mixed_model_image_or_prompt_rejected(self):
        for second in (self.make_trial(identity={'image':'different','clock_mhz':25}), self.make_trial(prompt=[379])):
            with self.assertRaises(ValueError):bench.pool([self.make_trial(),second])

    def test_actual_three_output_qwen8b_replay_is_rejected(self):
        name='demos/qwen3-8b/measurements.json'
        data=json.loads((ROOT/name).read_text())
        row={'format':'qwen_rows','source':name,'cases':['single-token-128-output-clear-replay'],
             'prompt_tokens':[9707], 'identity':{'model_image_sha256':data['image_sha256'],
             'checkpoint_sha256':data['checkpoint_sha256'],'core_clock_mhz':100}}
        with self.assertRaisesRegex(ValueError, '128 outputs'):
            bench.selected_trials(row,{name:data},[])

    def canonical_fixture(self):
        identity={'model_image_sha256':'a'*64,'core_clock_mhz':100}
        source={'schema':'fpga-common-speed-capture-v1','protocol':'greedy-one-token-128-host-v1',
                'timestamp_boundary':bench.BOUNDARY,'identity':identity,'cases':[]}
        for i in range(2):
            source['cases'].append({'name':str(i),'prompt_tokens':[9707],
                'generated_tokens':list(range(128)),'expected_tokens':list(range(128)),
                'reply_elapsed_seconds':list(range(128)),'cached_command_seconds':[0.5]*127,
                'first_step_seconds':10,'decoding':'greedy','temperature':0,'clear_before':True,
                'stop_at_eos':False,'feedback_dependent':True,'raw_capture_sha256':str(i)*64})
        row={'format':'canonical','source':'capture.json','identity':identity,
             'cases':['0','1'],'prompt_tokens':[9707]}
        return row,source

    def test_complete_canonical_pair_uses_selected_prompt_and_capture_identities(self):
        row,source=self.canonical_fixture()
        result=bench.pool(bench.selected_trials(row,{'capture.json':source},[]))
        self.assertEqual(result['cached_tokens_per_second'],1)

    def test_canonical_pair_with_same_wrong_single_token_prompt_rejected(self):
        row,source=self.canonical_fixture()
        for case in source['cases']:case['prompt_tokens']=[1]
        with self.assertRaisesRegex(ValueError,'Canonical prompt'):
            bench.selected_trials(row,{'capture.json':source},[])

    def test_canonical_pair_without_raw_capture_identity_rejected(self):
        row,source=self.canonical_fixture()
        source['cases'][0]['raw_capture_sha256']=None
        with self.assertRaisesRegex(ValueError,'raw capture identity'):
            bench.selected_trials(row,{'capture.json':source},[])

    def test_changed_source_identity_rejected(self):
        selection=json.loads((ROOT/bench.SELECTION).read_text())
        name=next(iter(selection['sources']))
        selection['sources'][name]['sha256']='0'*64
        with self.assertRaisesRegex(ValueError, 'Changed benchmark source'):
            bench.read_sources(ROOT,selection)

    def test_saved_results_and_overview_use_same_accounting(self):
        result=bench.calculate(ROOT)
        self.assertEqual(result,json.loads((ROOT/bench.RESULTS).read_text()))
        text=(ROOT/'README.md').read_text()
        self.assertEqual(text.count(bench.START),1)
        self.assertEqual(text.count(bench.END),1)
        self.assertEqual(text.split(bench.START,1)[1].split(bench.END,1)[0].strip(),bench.table(result))


if __name__=='__main__':unittest.main()
