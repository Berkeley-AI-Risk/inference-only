"""Synthetic-only validation tests; these fixtures are not board measurements."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('encrypted_board_summary_check', HERE/'check_encrypted_board_evidence.py')
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)
PACKAGE = HERE.parent


def synthetic_fixture(package):
    """Construct in memory only, using fake timings and transcript hashes."""
    public = json.loads((package/'tests/reference-cases.json').read_bytes())
    cases = {name: {key: value[key] for key in ('prompt_tokens', 'generated_tokens')}
             for name, value in public.items()}
    seed = cases['prefix512']['prompt_tokens']
    cases['prefix512']['generated_tokens'] = [15, 111, 157, 599]
    for name, count, outputs in [('prefix1024', 1024, 4), ('prefix2047', 2047, 2)]:
        cases[name] = dict(prompt_tokens=(seed*4)[:count], generated_tokens=[15]*outputs)
    campaigns = {}
    for variant, names in [('encrypted', checker.ORDER), ('restored', checker.RESTORED)]:
        campaigns[variant] = []
        for name in names:
            p, n = len(cases[name]['prompt_tokens']), len(cases[name]['generated_tokens'])
            scale = 2 if variant == 'encrypted' else 1
            campaigns[variant].append(dict(case=name, prompt_count=p, output_count=n,
                evaluated_positions=p+n-1, maximum_occupied_tape=p+n,
                **checker.timing(float(scale), [.25*scale]*(n-1)),
                known_answer_steps=12, known_answer_passes=3, empty_step_rejections=3,
                boundary_rejections=['input-limit-append-rejected', 'final-slot-append-rejected',
                    'final-slot-step-rejected'] if name == 'prefix2047' else [],
                final_clear_acknowledged=True, receipt_sha256='0'*64, uart_sha256='1'*64,
                command_plan_sha256='2'*64, max_wall_monotonic_discrepancy_seconds=.001))
    return dict(schema='encrypted-memory-broad-board-v1', passed=True, scope=checker.SCOPE,
        reference_cases=cases, reference=dict(model_image_sha256=checker.PLAIN_SHA,
            ciphertext_sha256=checker.CIPHER_SHA, integer_oracle_sha256=checker.ORACLE_SHA,
            receipt_sha256=checker.REFERENCE_SHA, case_set_sha256=checker.CASES_SHA,
            fresh_cases=list(checker.ORDER[:5]), historical_cases_revalidated=list(checker.ORDER[5:]),
            long_references_rerun=False),
        image_sha256=dict(encrypted=checker.ENCRYPTED_SHA, restored=checker.RESTORED_SHA),
        campaigns=campaigns, matched_cases=[dict(case=name, first_step_latency_ratio=2.,
            cached_decode_latency_ratio=2.) for name in checker.RESTORED],
        source_receipts={name:'3'*64 for name in
            ('broad_prepared', 'encrypted', 'restored', 'roundtrip', 'staged_qualification')},
        staged_qualification=dict(commands=7, generated_tokens=[200, 15, 103, 157],
            source_manifest_sha256=checker.STAGED_MANIFEST, build_receipt_sha256=checker.BUILD_SHA,
            hardware_inputs_sha256=checker.INVENTORY_SHA,
            host_source_sha256={name:checker.sha(checker.historical(package,'host-app/'+name)) for name in checker.HOST_FILES},
            uart_sha256='4'*64, receipt_sha256='3'*64, private_profile_only=True,
            default_profile_changed=False, browser_started=False),
        restoration=dict(full_flash_readback_passed=True, restored_demo_verified=True,
            no_irreversible_programming=True, encrypted_short_kat_steps=6, restored_short_kat_steps=6),
        public_test_keys_only=True, timing_qualified=False, physical_secrecy_qualified=False,
        configuration_independently_attested=False, physical_corruption_injection_tested=False, browser_tested=False)


class SyntheticSummaryTests(unittest.TestCase):
    def test_exact_synthetic_summary(self):
        result = checker.validate(synthetic_fixture(PACKAGE), PACKAGE)
        self.assertEqual(result['encrypted_long_case_outputs'], 522)
        self.assertEqual(result['maximum_evaluated_model_positions'], 2048)
        self.assertFalse(result['private_raw_transcripts_replayed'])

    def test_reject_missing_and_extra_case(self):
        for mode in ('missing', 'extra', 'order'):
            with self.subTest(mode=mode):
                data = synthetic_fixture(PACKAGE)
                rows = data['campaigns']['encrypted']
                if mode == 'missing': rows.pop()
                elif mode == 'extra': rows.append(copy.deepcopy(rows[0]))
                else: rows.reverse()
                with self.assertRaises(ValueError): checker.validate(data, PACKAGE)

    def test_reject_wrong_reference_and_claims(self):
        for mode in ('token', 'reference', 'context', 'boundary', 'clear', 'qualification',
                     'browser', 'physical', 'restoration', 'rerun', 'new_field'):
            with self.subTest(mode=mode):
                data = synthetic_fixture(PACKAGE)
                if mode == 'token': data['reference_cases']['prefix2047']['generated_tokens'][0] = 14
                elif mode == 'reference': data['reference']['integer_oracle_sha256'] = '0'*64
                elif mode == 'context': data['campaigns']['encrypted'][-1]['evaluated_positions'] = 2049
                elif mode == 'boundary': data['campaigns']['encrypted'][-1]['boundary_rejections'].pop()
                elif mode == 'clear': data['campaigns']['encrypted'][0]['final_clear_acknowledged'] = False
                elif mode == 'qualification': data['staged_qualification']['commands'] = 6
                elif mode == 'browser': data['browser_tested'] = True
                elif mode == 'physical': data['physical_secrecy_qualified'] = True
                elif mode == 'restoration': data['restoration']['restored_demo_verified'] = False
                elif mode == 'rerun': data['reference']['long_references_rerun'] = True
                else: data['device'] = '/dev/synthetic-not-real'
                with self.assertRaises(ValueError): checker.validate(data, PACKAGE)

    def test_reject_bad_duration_or_clock_and_mixed_speed(self):
        for mode in ('zero', 'nan', 'count', 'arithmetic', 'ratio', 'wall'):
            with self.subTest(mode=mode):
                data = synthetic_fixture(PACKAGE); row = data['campaigns']['encrypted'][0]
                if mode == 'zero': row['first_step_seconds'] = 0
                elif mode == 'nan': row['cached_decode_seconds'][0] = float('nan')
                elif mode == 'count': row['cached_decode_seconds'].pop()
                elif mode == 'arithmetic': row['cached_decode_tokens_per_second'] = row['all_long_steps_tokens_per_second']
                elif mode == 'ratio': data['matched_cases'][0]['first_step_latency_ratio'] = 1.
                else: row['max_wall_monotonic_discrepancy_seconds'] = 4.
                with self.assertRaises(ValueError): checker.validate(data, PACKAGE)

    def test_reject_wrong_host_or_image_binding(self):
        for mode in ('image', 'catalog', 'stage', 'build', 'uart_digest'):
            with self.subTest(mode=mode):
                data = synthetic_fixture(PACKAGE); q = data['staged_qualification']
                if mode == 'image': data['image_sha256']['encrypted'] = '0'*64
                elif mode == 'catalog': q['host_source_sha256']['runtime_profile.py'] = '0'*64
                elif mode == 'stage': q['source_manifest_sha256'] = '0'*64
                elif mode == 'build': q['build_receipt_sha256'] = '0'*64
                else: q['uart_sha256'] = 'not-a-hash'
                with self.assertRaises(ValueError): checker.validate(data, PACKAGE)


if __name__ == '__main__': unittest.main()
