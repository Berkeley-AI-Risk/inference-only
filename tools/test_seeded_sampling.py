"""Offline mutation tests of published evidence; no board access or new measurements."""
import copy
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('seeded_sampling_check', HERE/'check_seeded_sampling.py')
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)
PACKAGE = HERE.parent


class SeededSamplingEvidenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.receipt = json.loads((PACKAGE/(checker.EVIDENCE+'receipt.json')).read_bytes())
        cls.rows = [json.loads(line) for line in (PACKAGE/(checker.EVIDENCE+'uart.jsonl')).read_bytes().splitlines()]
        # Copy only checker inputs. Mutations never touch the release tree.
        cls.scratch = tempfile.TemporaryDirectory(prefix='seeded-evidence-test-')
        cls.package = Path(cls.scratch.name)
        for relative in ('host-app/hardware-inputs-seeded-sampling.json',
                         'prebuilt/seeded-sampling/BUILD.json', checker.IMAGE, *checker.APP_SOURCES,
                         'variants/seeded-sampling/tools/settings_codec.py'):
            target = cls.package/relative; target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(PACKAGE/relative, target)
        shutil.copytree(PACKAGE/checker.VARIANT, cls.package/checker.VARIANT)
        shutil.copytree(PACKAGE/checker.EVIDENCE, cls.package/checker.EVIDENCE)

    @classmethod
    def tearDownClass(cls):
        cls.scratch.cleanup()

    def row(self, rows, event, label):
        return next(row for row in rows if row['event'] == event and row.get('label') == label)

    def reframed(self, row, byte_index, value):
        packet = bytearray.fromhex(row['frame_hex']); packet[byte_index] = value
        packet[-1] = checker.crc8(packet[:-1]); row['frame_hex'] = packet.hex()

    def test_published_evidence_and_complete_bindings(self):
        result = checker.validate(copy.deepcopy(self.receipt), self.package)
        self.assertEqual(result['wire_frames_checked'], 326)
        self.assertEqual(result['returned_tokens'], 107)
        self.assertEqual(result['exact_token_checks'], 46)
        self.assertFalse(result['physical_configuration_attested'])

    def test_valid_crc_cannot_hide_changed_token_seed_temperature_or_rejection(self):
        for change in ('token', 'seed', 'temperature', 'rejection', 'crc', 'bad-crc-fixed', 'length'):
            with self.subTest(change=change):
                rows = copy.deepcopy(self.rows)
                if change == 'token':
                    self.reframed(self.row(rows, 'rx', 'seed-a/T=1/step-1'), 2, 102)
                elif change == 'seed':
                    self.reframed(self.row(rows, 'tx', 'seed-a/T=1/settings'), 3, 0)
                elif change == 'temperature':
                    self.reframed(self.row(rows, 'tx', 'seed-a/T=1/settings'), 2, 3)
                elif change == 'rejection':
                    self.reframed(self.row(rows, 'rx', 'invalid-settings/nonempty-rejection'), 1, 0x83)
                elif change == 'crc':
                    row = self.row(rows, 'rx', 'seed-a/T=1/step-1')
                    row['frame_hex'] = row['frame_hex'][:-2] + '00'
                elif change == 'bad-crc-fixed':
                    row = self.row(rows, 'tx', 'invalid-settings/bad-crc')
                    packet = bytes.fromhex(row['frame_hex']); row['frame_hex'] = checker.frame(packet[:-1])
                else:
                    self.row(rows, 'tx', 'seed-a/T=1/settings')['frame_hex'] += '00'
                with self.assertRaises(ValueError): checker.validate_transcript(rows)

    def test_replay_overlap_sequence_and_finite_census(self):
        for change in ('missing', 'extra', 'reorder', 'replay-token', 'replay-settings', 'race-claim', 'sequence'):
            with self.subTest(change=change):
                rows = copy.deepcopy(self.rows)
                if change == 'missing': rows.pop()
                elif change == 'extra': rows.append(copy.deepcopy(rows[-1]))
                elif change == 'reorder': rows[40], rows[41] = rows[41], rows[40]
                elif change == 'replay-token':
                    self.reframed(self.row(rows, 'rx', 'seed-a/T=0.5/replay-1'), 2, 13)
                elif change == 'replay-settings':
                    self.row(rows, 'tx', 'seed-a/T=1/replay-clear')['frame_hex'] = checker.settings(2, checker.SEED_A)
                elif change == 'race-claim':
                    next(row for row in rows if row['event'] == 'settings_race')['wire_completion_during_model_busy_observed'] = True
                else: rows[40]['sequence'] += 1
                with self.assertRaises(ValueError): checker.validate_transcript(rows)

    def test_duration_and_monotonic_clock_mutations(self):
        for change in ('zero', 'nan', 'timeline', 'duration', 'quiet', 'overlap'):
            with self.subTest(change=change):
                rows = copy.deepcopy(self.rows)
                row = self.row(rows, 'operation', 'performance/T=1/step-5')
                if change == 'zero': row['seconds'] = 0
                elif change == 'nan': row['seconds'] = float('nan')
                elif change == 'timeline': row['elapsed_ns'] = 0
                elif change == 'duration': row['seconds'] += .01
                elif change == 'quiet': next(r for r in rows if r['event'] == 'wire_quiet')['seconds'] = .01
                else: next(r for r in rows if r['event'] == 'settings_race')['queued_after_step_seconds'] = .1
                with self.assertRaises(ValueError): checker.validate_transcript(rows)

    def test_summary_timing_reference_and_qualification_mutations(self):
        for change in ('rate', 'sum', 'count', 'tail-reference', 'golden', 'image', 'source', 'claim', 'private-field'):
            with self.subTest(change=change):
                data = copy.deepcopy(self.receipt)
                if change == 'rate': data['performance']['cached_command_tokens_per_second'] += 1
                elif change == 'sum': data['performance']['cached_command_seconds'] += .01
                elif change == 'count': data['counts']['exact_token_checks'] = 107
                elif change == 'tail-reference': data['reference']['performance_reference_checked_prefix'] = 64
                elif change == 'golden': data['reference']['seed_a_goldens']['2'][0] = 1
                elif change == 'image': data['image']['sha256'] = '0'*64
                elif change == 'source': data['source']['inventory_sha256'] = '0'*64
                elif change == 'claim': data['limits']['full_context_qualified'] = True
                else: data['device_port'] = '/dev/synthetic-only'
                with self.assertRaises(ValueError): checker.validate(data, self.package)

    def test_file_hash_and_build_binding_mutations(self):
        inventory = json.loads((self.package/'host-app/hardware-inputs-seeded-sampling.json').read_bytes())
        native_input = next(name for name in inventory if not name.startswith('project/official/'))
        for change in ('transcript', 'native-summary', 'input', 'inventory', 'image', 'build'):
            with self.subTest(change=change):
                relative = {'transcript': checker.EVIDENCE+'uart.jsonl',
                    'native-summary': checker.EVIDENCE+'native.json', 'input': checker.VARIANT+'/'+native_input,
                    'inventory': 'host-app/hardware-inputs-seeded-sampling.json', 'image': checker.IMAGE,
                    'build': 'prebuilt/seeded-sampling/BUILD.json'}[change]
                path = self.package/relative; original = path.read_bytes()
                try:
                    if change == 'build':
                        data = json.loads(original); data['source_inputs_verified'] = False
                        path.write_bytes(checker.canonical(data))
                    elif change == 'inventory':
                        data = json.loads(original); data[native_input] = '0'*64
                        path.write_bytes(checker.canonical(data))
                    else:
                        altered = bytearray(original); altered[len(altered)//2] ^= 1; path.write_bytes(altered)
                    with self.assertRaises(ValueError): checker.validate(copy.deepcopy(self.receipt), self.package)
                finally:
                    path.write_bytes(original)

    def test_physical_app_qualifier_fixtures_and_scope_mutations(self):
        original = json.loads((self.package/(checker.EVIDENCE+'app.json')).read_bytes())
        checker.validate_app(copy.deepcopy(original),self.package)
        for change in ('source','qualifier-count','qualifier-token','qualifier-seed','qualifier-replay',
                       'repeat','greedy','auto-seed','auto-reference','stop','stop-wire','resume',
                       'disconnect','mocked','browser','server','inflight','inference','codec'):
            with self.subTest(change=change):
                app = copy.deepcopy(original)
                if change == 'source': app['source_sha256']['host-app/sampling_protocol.py'] = '0'*64
                elif change == 'qualifier-count': app['qualification']['operations'] = 44
                elif change == 'qualifier-token': app['qualification']['transactions'][3]['token'] = 15
                elif change == 'qualifier-seed': app['qualification']['transactions'][8]['seed'] = '0x'+'0'*32
                elif change == 'qualifier-replay': app['qualification']['transactions'][20]['operation'] = 'settings'
                elif change == 'repeat': app['cases'][1]['generated_tokens'][0] = 13
                elif change == 'greedy': app['cases'][2]['commands'][1] = checker.transaction('settings',2,seed=checker.SEED_A)
                elif change == 'auto-seed': app['cases'][7]['seed'] = app['cases'][6]['seed']
                elif change == 'auto-reference': app['cases'][6]['expected_tokens'] = [14]
                elif change == 'stop': app['stop']['uploaded'] = 1
                elif change == 'stop-wire': app['stop']['commands'].pop()
                elif change == 'resume': app['resume']['generated_tokens'][1] = 14
                elif change == 'disconnect': app['lifecycle']['disconnect_released_connection'] = False
                elif change == 'mocked': app['claims']['mocked_uart'] = True
                elif change == 'browser': app['claims']['browser_automation'] = True
                elif change == 'server': app['claims']['listening_server_started'] = True
                elif change == 'inflight': app['claims']['inflight_step_stop_tested'] = True
                elif change == 'inference': app['claims']['software_inference'] = True
                else: app['codec_source']['sha256'] = '0'*64
                with self.assertRaises(ValueError): checker.validate_app(app,self.package)

    def test_app_source_bytes_must_match_physically_tested_sources(self):
        app = json.loads((self.package/(checker.EVIDENCE+'app.json')).read_bytes())
        for relative in ('host-app/sampling_protocol.py', 'host-app/streamlit_app.py',
                         'host-app/runtime_profile.py', checker.APP_FRONTEND_ARCHIVE, checker.APP_PROFILE_ARCHIVE,
                         'variants/seeded-sampling/tools/settings_codec.py'):
            with self.subTest(path=relative):
                path = self.package/relative; original = path.read_bytes()
                try:
                    path.write_bytes(original+b'\n# synthetic mutation\n')
                    with self.assertRaises(ValueError): checker.validate_app(app,self.package)
                finally:
                    path.write_bytes(original)


    def test_stop_after_generation_supplement_mutations(self):
        original = json.loads((self.package/(checker.EVIDENCE+'app.json')).read_bytes())['stopped_after_generation']
        raw_rows = [json.loads(line) for line in (self.package/(checker.EVIDENCE+'app-stop.jsonl')).read_bytes().splitlines()]
        checker.validate_app_stop(copy.deepcopy(original),self.package)
        for change in ('not-generating','no-upload','no-output','too-many','golden','greedy-resume',
                       'no-clear','no-release','inflight','source','inflated-checks','crc','wire-greedy','wire-missing'):
            with self.subTest(change=change):
                data = copy.deepcopy(original); rows = copy.deepcopy(raw_rows)
                if change == 'not-generating': data['before_stop']['state'] = 'complete'
                elif change == 'no-upload': data['stopped']['uploaded'] = 0
                elif change == 'no-output': data['stopped']['generated'] = []
                elif change == 'too-many': data['stopped']['generated'] *= 5
                elif change == 'golden': data['stopped']['generated'][0] = 13
                elif change == 'greedy-resume': data['resumed']['generated'][0] = 357
                elif change == 'no-clear': data['stopped']['clear_acknowledged'] = False
                elif change == 'no-release': data['claims']['stop_released_connection'] = False
                elif change == 'inflight': data['claims']['internal_inflight_command_at_click_observed'] = True
                elif change == 'source': data['source_sha256']['host-app/fpga_backend.py'] = '0'*64
                elif change == 'inflated-checks': data['counts']['stopped_known_answer_prefix'] = 13
                elif change == 'crc': rows[-1]['frame_hex'] = rows[-1]['frame_hex'][:-2]+'00'
                elif change == 'wire-greedy':
                    next(row for row in rows if row['run'] == 'resumed' and row['event'] == 'tx'
                        and row['frame_hex'].startswith('a503'))['frame_hex'] = checker.settings(2,checker.SEED_A)
                else: rows.pop()
                with self.assertRaises(ValueError): checker.validate_app_stop(data,self.package,rows)


if __name__ == '__main__':
    unittest.main()
