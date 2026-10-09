import importlib.util
import hashlib
import json
import math
from pathlib import Path
import unittest

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location('capacity', HERE / 'estimate_training_capacity.py')
CAPACITY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CAPACITY)


class CapacityTests(unittest.TestCase):
    def test_paper_example(self):
        self.assertAlmostEqual(CAPACITY.token_channel_ceiling(1e9, 1e6), 12_171_612_389.00369, places=4)

    def test_invalid_rates(self):
        for value in (0, -1, math.inf, -math.inf, math.nan):
            with self.subTest(value=value), self.assertRaises(ValueError):
                CAPACITY.positive(value)

    def test_ratio_scales_with_reference_rate(self):
        a = CAPACITY.proxy_residual_training_factor(250e6, 5, 1e4)
        b = CAPACITY.proxy_residual_training_factor(250e6, 5, 1e5)
        self.assertAlmostEqual(b, 10 * a)

    def test_ratio_scales_inversely_with_inference(self):
        a = CAPACITY.proxy_residual_training_factor(250e6, 5, 1e5)
        b = CAPACITY.proxy_residual_training_factor(250e6, 10, 1e5)
        self.assertAlmostEqual(b, a / 2)

    def test_arithmetic_and_wire_inputs(self):
        result = CAPACITY.estimate(HERE.parent)
        self.assertAlmostEqual(result['combined_wire_token_rate_ceiling'], 2 * 25e6 / 217 / 40)
        scenarios = result['scenarios']
        self.assertEqual(scenarios['five_dynamic_lanes_full_credit']['operation_rate_proxy'], 250e6)
        self.assertEqual(scenarios['all_mapped_multipliers_full_credit']['operation_rate_proxy'], 3.8e9)
        self.assertGreater(scenarios['token_channel_wire_ceiling']['operation_rate_proxy'], 100_000)
        self.assertLess(scenarios['token_channel_wire_ceiling']['operation_rate_proxy'], 101_000)

    def test_measured_context_is_not_a_peak_claim(self):
        result = CAPACITY.estimate(HERE.parent)
        self.assertEqual(result['inputs']['fpga_context_positions'], 128)
        self.assertAlmostEqual(result['inputs']['fpga_inference_rate_proxy'], 1 / 0.15292962500825524)
        self.assertTrue(result['h100_inference_benchmark_measured'])
        self.assertFalse(result['inputs']['reference_tps_are_sensitivity_inputs_not_measurements'])
        self.assertFalse(result['measured_reference']['fpga_bit_exact'])
        self.assertFalse(result['training_attack_demonstrated'])
        self.assertIsNone(result['certified_residual_training_factor'])

    def test_saved_result_reproduces(self):
        saved = json.loads((HERE.parent / 'evidence/training-capacity-estimates.json').read_text())
        self.assertEqual(saved, CAPACITY.estimate(HERE.parent))

    def test_no_empty_reference_grid(self):
        with self.assertRaises(ValueError):
            CAPACITY.estimate(HERE.parent, ())

    def test_measured_reference_is_default_and_reproducible(self):
        result = CAPACITY.estimate(HERE.parent)
        reference = result['measured_reference']
        self.assertAlmostEqual(reference['aggregate_tokens_per_second'], 1018047.5450472439)
        self.assertEqual(reference['context_positions'], 128)
        self.assertEqual(reference['batch'], 32768)
        ratio = result['scenarios']['five_dynamic_lanes_full_credit']['ratios'][0]
        self.assertEqual(ratio['reference_kind'], 'measured_fp16_parent_model')
        self.assertAlmostEqual(ratio['proxy_residual_training_factor'], 0.03935531579996204)

    def test_overrides_are_labelled_sensitivity_not_measurements(self):
        result = CAPACITY.estimate(HERE.parent, (1e6, 1e7))
        self.assertTrue(result['inputs']['reference_tps_are_sensitivity_inputs_not_measurements'])
        ratios = result['scenarios']['five_dynamic_lanes_full_credit']['ratios']
        self.assertTrue(all(row['reference_kind'] == 'user_supplied_sensitivity' for row in ratios))
        self.assertAlmostEqual(ratios[1]['proxy_residual_training_factor'], 10 * ratios[0]['proxy_residual_training_factor'])

    def test_pinned_geometry_and_changed_geometry_rejection(self):
        source = (HERE.parent / CAPACITY.GEOMETRY_FILE).read_text()
        geometry = CAPACITY.model_geometry(source)
        self.assertEqual(geometry['num_key_value_heads'], 2)
        self.assertEqual(geometry['num_attention_heads'], 4)
        with self.assertRaises(ValueError):
            CAPACITY.model_geometry(source.replace('intermediate_size: int = 682', 'intermediate_size: int = 688'))
        with self.assertRaises(ValueError):
            CAPACITY.model_geometry('class MissingConfig: pass')

    def test_work_counts_and_grouped_query_cache(self):
        result = CAPACITY.estimate(HERE.parent)
        counts = result['model_work_counts']
        self.assertEqual(counts['projection_and_head_macs'], 5_351_168)
        self.assertEqual(counts['attention_macs'], 393_216)
        self.assertEqual(counts['gate_products'], 4_092)
        self.assertEqual(counts['normalization_squares'], 3_328)
        self.assertEqual(counts['dominant_matrix_operations_per_decode'], 11_488_768)
        self.assertEqual(counts['scheduled_dynamic_mac_equivalent_operations_per_decode'], 801_272)
        # FP16 K and V have two heads, not the four query heads.
        self.assertEqual(counts['minimum_fp16_kv_bytes_per_decode'], 393_216)
        geometry = result['inputs']['model_geometry']
        short = CAPACITY.model_work_counts(geometry, 1)
        long = CAPACITY.model_work_counts(geometry, 2048)
        self.assertEqual(short['attention_macs'], 3_072)
        self.assertEqual(long['attention_macs'], 3_072 * 2048)
        self.assertEqual(long['minimum_fp16_kv_bytes_per_decode'], 393_216 * 16)
        for context in (0, -1, 2049, 1.5, True):
            with self.subTest(context=context), self.assertRaises(ValueError):
                CAPACITY.model_work_counts(geometry, context)

    def test_new_scenarios_are_conditional_not_certified_or_demonstrated(self):
        result = CAPACITY.estimate(HERE.parent)
        scenarios = result['scenarios']
        self.assertEqual(set(scenarios), {
            'token_channel_wire_ceiling', 'five_dynamic_lanes_full_credit',
            'all_mapped_multipliers_full_credit', 'fixed_schedule_dynamic_work_allowance',
            'weight_enforcement_failure_fixed_schedule',
        })
        schedule = scenarios['fixed_schedule_dynamic_work_allowance']
        failure = scenarios['weight_enforcement_failure_fixed_schedule']
        self.assertFalse(schedule['fixed_operation_count_premise_certified'])
        self.assertFalse(failure['weight_enforcement_failure_demonstrated'])
        self.assertAlmostEqual(schedule['ratios'][0]['proxy_residual_training_factor'], 0.0008248058569414511)
        self.assertAlmostEqual(failure['ratios'][0]['proxy_residual_training_factor'], 0.011826200260887092)

    def test_software_and_physical_access_assumptions_are_distinct(self):
        scenarios = CAPACITY.estimate(HERE.parent)['scenarios']
        expected = {
            'token_channel_wire_ceiling': 'software_token_interface',
            'five_dynamic_lanes_full_credit': 'physical_dynamic_unit_stress',
            'all_mapped_multipliers_full_credit': 'internal_circuit_full_access_stress',
            'fixed_schedule_dynamic_work_allowance': 'physical_fixed_schedule_stress',
            'weight_enforcement_failure_fixed_schedule': 'weight_enforcement_compromise',
        }
        self.assertEqual({name: row['access_model'] for name, row in scenarios.items()}, expected)
        self.assertTrue(all(row['access_assumption'] for row in scenarios.values()))

    def test_rate_cancels_only_when_credited_work_tracks_inference(self):
        result = CAPACITY.estimate(HERE.parent)
        reference = result['measured_reference']['aggregate_tokens_per_second']
        for name in ('fixed_schedule_dynamic_work_allowance', 'weight_enforcement_failure_fixed_schedule'):
            count = result['scenarios'][name]['operations_per_decode_credited']
            with self.subTest(name=name):
                slow = CAPACITY.proxy_residual_training_factor(count * 5, 5, reference)
                fast = CAPACITY.proxy_residual_training_factor(count * 10, 10, reference)
                self.assertAlmostEqual(slow, fast)
                self.assertAlmostEqual(slow, count * reference / CAPACITY.H100_DENSE_FLOPS)

    def test_explicit_illustrative_target_comparisons(self):
        result = CAPACITY.estimate(HERE.parent)
        self.assertEqual(result['inputs']['illustrative_paper_targets_not_certification_thresholds'], [0.01, 0.001, 0.0001])
        for scenario in result['scenarios'].values():
            row = scenario['ratios'][0]
            comparisons = row['illustrative_target_comparisons']
            self.assertEqual([item['target'] for item in comparisons], [0.01, 0.001, 0.0001])
            for item in comparisons:
                self.assertAlmostEqual(item['proxy_over_target'], row['proxy_residual_training_factor'] / item['target'])
                self.assertNotIn('certified_compliance', item)

    def test_documented_comparison_table_matches_calculator(self):
        text = (HERE.parent / 'TRAINING-CAPACITY.md').read_text()
        header = '| Scenario | Assumed operation rate `T` | Calculated `φ_proxy` |'
        self.assertEqual(text.count(header), 1)
        table = text[text.index(header):].split('\n\n', 1)[0].splitlines()
        self.assertIn('`φ_proxy / 0.0001`', table[0])
        names = ('token_channel_wire_ceiling', 'five_dynamic_lanes_full_credit',
                 'all_mapped_multipliers_full_credit', 'fixed_schedule_dynamic_work_allowance',
                 'weight_enforcement_failure_fixed_schedule')
        self.assertEqual(len(table), len(names) + 2)
        scenarios = CAPACITY.estimate(HERE.parent)['scenarios']
        for line, name in zip(table[2:], names):
            with self.subTest(scenario=name):
                cells = [cell.strip() for cell in line.strip('|').split('|')]
                self.assertEqual(len(cells), 6)
                row = scenarios[name]
                ratio = row['ratios'][0]
                expected = [row['operation_rate_proxy'], ratio['proxy_residual_training_factor']]
                expected += [item['proxy_over_target'] for item in ratio['illustrative_target_comparisons']]
                observed = [float(cell.removesuffix('/s').replace(',', '')) for cell in cells[1:]]
                for actual, wanted in zip(observed, expected):
                    self.assertTrue(math.isclose(actual, wanted, rel_tol=0.005), (actual, wanted))

    def test_ideal_headroom_is_not_profiled_utilization_or_a_forecast(self):
        result = CAPACITY.estimate(HERE.parent)
        models = result['reference_performance_models']
        self.assertFalse(models['fractions_are_profiled_hardware_utilization'])
        self.assertAlmostEqual(models['measured_useful_matrix_flops_fraction_of_dense_peak'], 0.011826200260887092)
        self.assertAlmostEqual(models['measured_minimum_kv_bytes_fraction_of_peak_bandwidth'], 0.11949629357411852)
        compute = models['arithmetic_only_roof']
        memory = models['minimum_kv_traffic_only_roof']
        self.assertFalse(compute['measured'])
        self.assertFalse(memory['measured'])
        self.assertAlmostEqual(compute['reference_tps'], 989e12 / 11_488_768)
        self.assertAlmostEqual(memory['reference_tps'], 3.35e12 / 393_216)
        self.assertEqual(models['combined_ideal_roof_reference_tps'], min(compute['reference_tps'], memory['reference_tps']))
        self.assertGreater(models['combined_ideal_roof_reference_tps'],
                           1 / (1 / compute['reference_tps'] + 1 / memory['reference_tps']))
        examples = models['unmeasured_speedup_sensitivities_not_forecasts']
        self.assertEqual([row['multiple_of_measured_reference'] for row in examples], [3, 6])
        base = result['scenarios']['five_dynamic_lanes_full_credit']['ratios'][0]['proxy_residual_training_factor']
        for row in examples:
            self.assertFalse(row['measured'])
            self.assertAlmostEqual(row['scenario_proxy_residual_training_factors']['five_dynamic_lanes_full_credit'],
                                   base * row['multiple_of_measured_reference'])

    def test_all_mapped_proxy_crossover(self):
        result = CAPACITY.estimate(HERE.parent)
        rate = result['reference_performance_models']['all_mapped_proxy_equals_one_at_reference_tps']
        self.assertAlmostEqual(CAPACITY.proxy_residual_training_factor(3.8e9, result['inputs']['fpga_inference_rate_proxy'], rate), 1)
        self.assertAlmostEqual(result['reference_performance_models']['all_mapped_proxy_equals_one_at_multiple_of_measured'],
                               1.6716794757437565)

    def test_rounding_diagnostic_scope_is_separate(self):
        reference = CAPACITY.estimate(HERE.parent)['measured_reference']
        self.assertEqual(reference['strict_alternative_mode'], 'uncompiled_cuda_graph')
        self.assertFalse(reference['fpga_integer_model_agreement_measured'])
        diagnostic = reference['rounding_diagnostic']
        self.assertEqual((diagnostic['batch'], diagnostic['seed'], diagnostic['mismatching_rows_investigated']),
                         (1024, 20260916, 4))
        self.assertFalse(diagnostic['covers_selected_reference_disagreements'])

    def test_calculator_geometry_and_measurement_provenance(self):
        result = CAPACITY.estimate(HERE.parent)
        self.assertEqual(result['schema'], 'conditional-training-capacity-v4')
        for name in ('tools/estimate_training_capacity.py', CAPACITY.GEOMETRY_FILE,
                     CAPACITY.REFERENCE_FILE, CAPACITY.ROUNDING_FILE):
            self.assertEqual(result['source_sha256'][name], hashlib.sha256((HERE.parent / name).read_bytes()).hexdigest())


if __name__ == '__main__':
    unittest.main()
