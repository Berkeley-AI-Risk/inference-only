"""Offline checks of useful-work accounting, not hardware or attack experiments."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

HERE = Path(__file__).resolve().parent


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


COUNTS = load('architecture_counts', 'architecture_work_counts.py')
CAPACITY = load('existing_capacity', 'estimate_training_capacity.py')


class ArchitectureCountsTests(unittest.TestCase):
    def test_tiny_geometry_matches_pinned_model(self):
        source = (HERE.parent / CAPACITY.GEOMETRY_FILE).read_text(encoding='utf-8')
        self.assertEqual(COUNTS.TINY, CAPACITY.model_geometry(source))

    def test_tiny_counts_match_existing_calculator(self):
        for context in (1, 128, 2048):
            new = COUNTS.work_counts(COUNTS.TINY, cached_tokens=context-1)
            old = CAPACITY.model_work_counts(COUNTS.TINY, context)
            self.assertEqual(new['matrix_operations'], old['dominant_matrix_operations_per_decode'])
            self.assertEqual(new['attention_matrix_operations'], 2*old['attention_macs'])
            self.assertEqual(new['fixed_matrix_operations'], 2*old['projection_and_head_macs'])
            self.assertEqual(new['named_dynamic_mac_equivalent_operations'],
                             old['scheduled_dynamic_mac_equivalent_operations_per_decode'])

    def test_llama_example_exact_counts(self):
        row = COUNTS.work_counts(COUNTS.LLAMA_405B, cached_tokens=8191)
        self.assertEqual(row['fixed_matrix_macs_per_layer_position'], 3_187_671_040)
        self.assertEqual(row['fixed_matrix_operations'], 807_495_794_688)
        self.assertEqual(row['attention_matrix_operations'], 67_645_734_912)
        self.assertAlmostEqual(row['attention_fraction'], 0.07729690869877785)

    def test_document_table_reproduces(self):
        COUNTS.check_document(HERE.parent / 'ARCHITECTURE-DEPENDENT-CAPACITY.md')
        self.assertAlmostEqual(COUNTS.cycle_fraction(HERE.parent),
                               801_272 / (0.15292962500825524 * 250_000_000))

    def test_document_table_drift_is_rejected(self):
        original = (HERE.parent / 'ARCHITECTURE-DEPENDENT-CAPACITY.md').read_text(encoding='utf-8')
        for text in (original.replace('7.73%', '7.74%'),
                     original.replace('0.02096.', '0.01451.'),
                     original.replace('Here `u_dynamic` is approximately ', 'Missing cycle fraction '),
                     original+'\nHere `u_dynamic` is approximately 0.02096.', original+COUNTS.END,
                     original+COUNTS.START, COUNTS.START+original, 'missing table',
                     original.replace(COUNTS.END, '| 1 | 0% | 0% |\n'+COUNTS.END),
                     original.replace(COUNTS.START, '').replace(COUNTS.END, COUNTS.END+COUNTS.START)):
            with self.subTest(text=text[:30]), tempfile.TemporaryDirectory() as temporary:
                path = Path(temporary) / 'example.md'
                path.write_text(text, encoding='utf-8')
                with self.assertRaises(ValueError):
                    COUNTS.check_document(path, package=HERE.parent)

    def test_workload_table_drift_is_rejected(self):
        original = (HERE.parent / 'ARCHITECTURE-DEPENDENT-CAPACITY.md').read_text(encoding='utf-8')
        self.assertEqual(original.count('0.001208 |'), 1)
        for text in (original.replace('0.001208 |', '0.001209 |'),
                     original+COUNTS.WORKLOAD_START, original+COUNTS.WORKLOAD_END,
                     original.replace(COUNTS.WORKLOAD_START, ''),
                     original.replace(COUNTS.WORKLOAD_END, '| extra row |\n'+COUNTS.WORKLOAD_END)):
            with self.subTest(text=text[-80:]), tempfile.TemporaryDirectory() as temporary:
                self.assertNotEqual(text, original)
                path = Path(temporary) / 'example.md'
                path.write_text(text, encoding='utf-8')
                with self.assertRaises(ValueError):
                    COUNTS.check_document(path, package=HERE.parent)

    def test_document_and_evidence_are_read_as_utf8(self):
        read_text = Path.read_text

        def require_utf8(path, *args, **kwargs):
            self.assertEqual(kwargs.get('encoding'), 'utf-8')
            return read_text(path, *args, **kwargs)

        with mock.patch.object(Path, 'read_text', autospec=True, side_effect=require_utf8):
            COUNTS.check_document(HERE.parent / 'ARCHITECTURE-DEPENDENT-CAPACITY.md')

    def test_batch_scales_work_not_fraction(self):
        one = COUNTS.work_counts(COUNTS.LLAMA_405B, cached_tokens=2047)
        many = COUNTS.work_counts(COUNTS.LLAMA_405B, cached_tokens=2047, batch=32)
        for field in ('attention_matrix_operations', 'fixed_matrix_operations', 'matrix_operations',
                      'named_dynamic_mac_equivalent_operations', 'matrix_plus_named_extra_operations'):
            self.assertEqual(many[field], 32*one[field])
        self.assertEqual(one['attention_fraction'], many['attention_fraction'])

    def test_causal_prefill_equals_sum_of_decode_work(self):
        for prefix in (0, 17):
            full = COUNTS.work_counts(COUNTS.TINY, cached_tokens=prefix, new_tokens=11)
            steps = [COUNTS.work_counts(COUNTS.TINY, cached_tokens=prefix+i,
                                       logit_positions=int(i == 10)) for i in range(11)]
            for field in ('attention_matrix_operations', 'fixed_matrix_operations',
                          'named_dynamic_mac_equivalent_operations', 'matrix_plus_named_extra_operations'):
                self.assertEqual(full[field], sum(row[field] for row in steps))
            self.assertEqual(full['query_key_pairs_per_sequence'], 11*prefix+66)

    def test_all_position_logits_have_explicit_head_cost(self):
        one = COUNTS.work_counts(COUNTS.TINY, new_tokens=5)
        all_positions = COUNTS.work_counts(COUNTS.TINY, new_tokens=5, logit_positions=5)
        self.assertEqual(all_positions['fixed_matrix_operations']-one['fixed_matrix_operations'],
                         2*4*256*4019)
        self.assertEqual(all_positions['normalization_squares']-one['normalization_squares'], 4*256)
        self.assertEqual(all_positions['attention_matrix_operations'], one['attention_matrix_operations'])

    def test_gqa_does_not_reduce_attention_by_kv_head_ratio(self):
        gqa = COUNTS.work_counts(COUNTS.TINY, cached_tokens=127)
        mha = COUNTS.work_counts(dict(COUNTS.TINY, num_key_value_heads=4), cached_tokens=127)
        self.assertEqual(gqa['attention_matrix_operations'], mha['attention_matrix_operations'])
        self.assertEqual(mha['fixed_matrix_operations']-gqa['fixed_matrix_operations'], 2*6*2*256*2*64)

    def test_head_dimension_can_differ_from_model_width_per_head(self):
        row = COUNTS.work_counts(dict(COUNTS.TINY, head_dim=32), cached_tokens=127)
        self.assertEqual(row['attention_matrix_operations'], 4*6*4*32*128)
        self.assertEqual(row['fixed_matrix_macs_per_layer_position'],
                         2*256*(4+2)*32 + 3*256*682)

    def test_more_total_experts_only_changes_router_in_this_model(self):
        eight = COUNTS.work_counts(COUNTS.TINY, routed_experts=8, active_experts=2)
        sixteen = COUNTS.work_counts(COUNTS.TINY, routed_experts=16, active_experts=2)
        self.assertEqual(sixteen['fixed_matrix_operations']-eight['fixed_matrix_operations'], 2*6*256*8)
        self.assertEqual(sixteen['gate_products'], eight['gate_products'])
        self.assertEqual(sixteen['expert_mix_products'], 6*2*256)

    def test_active_experts_change_ffn_work_and_dynamic_mix(self):
        one = COUNTS.work_counts(COUNTS.TINY, routed_experts=8, active_experts=1)
        two = COUNTS.work_counts(COUNTS.TINY, routed_experts=8, active_experts=2)
        self.assertEqual(two['fixed_matrix_operations']-one['fixed_matrix_operations'], 2*6*3*256*682)
        self.assertEqual(two['gate_products'], 2*one['gate_products'])
        self.assertEqual(two['expert_mix_products'], 2*one['expert_mix_products'])

    def test_batched_chunked_moe_exact_counts(self):
        batch, new, cached, experts, active = 3, 5, 7, 8, 2
        layers, d, f, vocab = 6, 256, 682, 4019
        row = COUNTS.work_counts(COUNTS.TINY, batch=batch, new_tokens=new, cached_tokens=cached,
                                 routed_experts=experts, active_experts=active)
        fixed_macs = 2*d*(4+2)*64 + 3*active*d*f + d*experts
        pairs = new*cached + new*(new+1)//2
        attention = 4*batch*layers*4*64*pairs
        fixed = 2*batch*(new*layers*fixed_macs + d*vocab)
        gates = batch*layers*new*active*f
        squares = batch*(2*layers*new+1)*d
        mixing = batch*layers*new*active*d
        self.assertEqual(row['query_key_pairs_per_sequence'], pairs)
        self.assertEqual(row['fixed_matrix_macs_per_layer_position'], fixed_macs)
        self.assertEqual(row['fixed_matrix_operations'], fixed)
        self.assertEqual(row['gate_products'], gates)
        self.assertEqual(row['normalization_squares'], squares)
        self.assertEqual(row['expert_mix_products'], mixing)
        self.assertEqual(row['named_dynamic_mac_equivalent_operations'], attention+2*(gates+squares+mixing))
        self.assertEqual(row['matrix_plus_named_extra_operations'], attention+fixed+2*(gates+squares+mixing))

    def test_boundary_inputs_are_accepted(self):
        COUNTS.work_counts(COUNTS.TINY, routed_experts=2, active_experts=2)
        one = COUNTS.work_counts(COUNTS.TINY, routed_experts=1)
        dense = COUNTS.work_counts(COUNTS.TINY)
        self.assertEqual(one['fixed_matrix_operations']-dense['fixed_matrix_operations'], 2*6*256)
        no_logits = COUNTS.work_counts(COUNTS.TINY, logit_positions=0)
        self.assertEqual(no_logits['fixed_matrix_operations'], 2*6*720384)
        self.assertEqual(no_logits['normalization_squares'], 12*256)

    def test_proxy_decomposition_matches_saved_scheduled_row(self):
        report = CAPACITY.estimate(HERE.parent)
        row = COUNTS.work_counts(COUNTS.TINY, cached_tokens=127)
        dynamic = row['named_dynamic_mac_equivalent_operations']
        total = row['matrix_plus_named_extra_operations']
        self.assertEqual(dynamic, 801_272)
        self.assertEqual(total, 11_503_608)
        rate = report['measured_reference']['aggregate_tokens_per_second']
        expected = report['scenarios']['fixed_schedule_dynamic_work_allowance']['ratios'][0]['proxy_residual_training_factor']
        self.assertAlmostEqual(dynamic/total, 0.06965397, places=8)
        self.assertAlmostEqual(total*rate/CAPACITY.H100_DENSE_FLOPS, 0.01184148, places=8)
        self.assertAlmostEqual((dynamic/total)*(total*rate/CAPACITY.H100_DENSE_FLOPS), expected, places=15)

    def test_weight_replacement_proxy_equals_matrix_only_reference_efficiency(self):
        report = CAPACITY.estimate(HERE.parent)
        row = COUNTS.work_counts(COUNTS.TINY, cached_tokens=127)
        rate = report['measured_reference']['aggregate_tokens_per_second']
        efficiency = row['matrix_operations']*rate/CAPACITY.H100_DENSE_FLOPS
        expected = report['scenarios']['weight_enforcement_failure_fixed_schedule']['ratios'][0]['proxy_residual_training_factor']
        self.assertAlmostEqual(efficiency, 0.0118262002608871, places=15)
        self.assertAlmostEqual(efficiency, expected, places=15)

    def test_document_worked_decomposition_matches_counts(self):
        report = CAPACITY.estimate(HERE.parent)
        row = COUNTS.work_counts(COUNTS.TINY, cached_tokens=127)
        dynamic = row['named_dynamic_mac_equivalent_operations']
        matrix = row['matrix_operations']
        total = row['matrix_plus_named_extra_operations']
        rate = report['measured_reference']['aggregate_tokens_per_second']
        expected = '\n'.join((
            f'C_dynamic  = {dynamic:,}',
            f'C_total    = {matrix:,} matrix operations + {total-matrix:,} other credited operations',
            f'           = {total:,}',
            f'rho        = {dynamic/total:.8f}',
            f'eta_ref    = {total*rate/CAPACITY.H100_DENSE_FLOPS:.8f}',
            f'φ_schedule = {dynamic*rate/CAPACITY.H100_DENSE_FLOPS:.9f}',
        ))
        text = (HERE.parent / 'ARCHITECTURE-DEPENDENT-CAPACITY.md').read_text(encoding='utf-8')
        self.assertIn(expected, text)

    def test_recorded_workloads_use_fixed_inference_comparison(self):
        report = CAPACITY.estimate(HERE.parent)
        rows = COUNTS.recorded_workload_comparison(HERE.parent)
        expected = ((1, 127, 801_272, 0.15292962500825524, 0.0008248058569414512),
                    (1, 254, 1_581_560, 0.22050779196433723, 0.0011290810669702686),
                    (512, 0, 814_215_680, 106.07435816596262, 0.0012083491531684084),
                    (128, 0, 52_559_360, 12.358556292019784, 0.0006694925077549929))
        self.assertEqual(len(rows), len(expected))
        inference_comparison = (report['inputs']['fpga_inference_rate_proxy'] /
                                report['measured_reference']['aggregate_tokens_per_second'])
        for row, (new, cached, dynamic, seconds, proxy) in zip(rows, expected):
            with self.subTest(label=row['label']):
                self.assertEqual((row['new_tokens'], row['cached_tokens']), (new, cached))
                self.assertEqual(row['credited_dynamic_operations'], dynamic)
                self.assertEqual(row['seconds'], seconds)
                self.assertAlmostEqual(row['credited_operations_per_second'], dynamic/seconds)
                self.assertAlmostEqual(row['conditional_proxy'], proxy, places=15)
                self.assertAlmostEqual(row['conditional_proxy'],
                                       dynamic/seconds/CAPACITY.H100_DENSE_FLOPS/inference_comparison, places=15)
        self.assertGreater(rows[1]['conditional_proxy'], 0.001)
        self.assertGreater(rows[2]['conditional_proxy'], 0.001)

    def test_mismatched_recorded_reference_is_rejected(self):
        report = CAPACITY.estimate(HERE.parent)
        report['inputs']['fpga_context_positions'] = 255
        physical = (HERE.parent / 'evidence/baseline-current/metrics.json').read_text(encoding='utf-8')
        with mock.patch.object(Path, 'read_text', side_effect=[physical, json.dumps(report)]):
            with self.assertRaisesRegex(ValueError, '128-position reference'):
                COUNTS.recorded_workload_comparison(HERE.parent)

    def test_percent_boundaries(self):
        for fraction, expected in ((0, '0.000%'), (0.00131, '0.131%'),
                                   (0.0099996, '1.00%'), (0.01, '1.00%')):
            self.assertEqual(COUNTS.percent(fraction), expected)

    def test_cli_prints_and_checks_both_tables(self):
        for arguments in ([], ['--check']):
            output = io.StringIO()
            with mock.patch.object(sys, 'argv', ['architecture_work_counts.py']+arguments), \
                    contextlib.redirect_stdout(output):
                COUNTS.main()
            if arguments:
                self.assertIn('tables and cycle fraction match the calculations', output.getvalue())
            else:
                self.assertIn(COUNTS.llama_table(), output.getvalue())
                self.assertIn(COUNTS.recorded_workload_table(HERE.parent), output.getvalue())

    def test_cli_checks_selected_package_and_reports_drift(self):
        package = Path('/synthetic/package')
        with mock.patch.object(COUNTS, 'check_document', side_effect=ValueError('table drift')) as checker, \
                mock.patch.object(sys, 'argv', ['counter', '--check', '--package', str(package)]), \
                contextlib.redirect_stderr(io.StringIO()) as errors, self.assertRaises(SystemExit) as result:
            COUNTS.main()
        checker.assert_called_once_with(package / 'ARCHITECTURE-DEPENDENT-CAPACITY.md')
        self.assertEqual(result.exception.code, 2)
        self.assertIn('table drift', errors.getvalue())

    def test_context_changes_arithmetic_mix(self):
        short = COUNTS.work_counts(COUNTS.TINY, cached_tokens=127)
        long = COUNTS.work_counts(COUNTS.TINY, cached_tokens=2047)
        self.assertEqual(COUNTS.percent(short['attention_fraction']), '6.85%')
        self.assertEqual(COUNTS.percent(long['attention_fraction']), '54.04%')

    def test_invalid_geometry_or_workloads_rejected(self):
        for arguments in ({'batch': 0}, {'new_tokens': True}, {'cached_tokens': -1},
                          {'logit_positions': 2}, {'routed_experts': -1}, {'active_experts': 2},
                          {'routed_experts': 2, 'active_experts': 3}, {'logit_positions': -1},
                          {'logit_positions': True}, {'routed_experts': True}, {'routed_experts': 2.0},
                          {'active_experts': True}, {'active_experts': 0}, {'batch': 1.0}, {'cached_tokens': '0'}):
            with self.subTest(arguments=arguments), self.assertRaises(ValueError):
                COUNTS.work_counts(COUNTS.TINY, **arguments)
        for geometry in ({}, None, list(COUNTS.TINY), dict(COUNTS.TINY, rope_theta=10000),
                         dict(COUNTS.TINY, head_dim=0), dict(COUNTS.TINY, hidden_size=1.5),
                         dict(COUNTS.TINY, num_key_value_heads=3)):
            with self.subTest(geometry=geometry), self.assertRaises(ValueError):
                COUNTS.work_counts(geometry)


if __name__ == '__main__':
    unittest.main()
