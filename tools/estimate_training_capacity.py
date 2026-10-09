#!/usr/bin/env python3
"""Reproduce the explicitly conditional scenarios in TRAINING-CAPACITY.md.

Offline arithmetic only: reads saved GPU measurements but starts no benchmark,
attack, proof or hardware access. Explicit rate overrides are sensitivity inputs.
"""
import argparse
import ast
import hashlib
import importlib.util
import json
import math
from pathlib import Path

H100_DENSE_FLOPS = 989e12
H100_MEMORY_BYTES_PER_SECOND = 3.35e12
ILLUSTRATIVE_TARGETS = (0.01, 0.001, 0.0001)
REFERENCE_FILE = 'evidence/h100/h100-compiled-fp16-repeat/ctx128-batch32768-float16-compile-graph.json'
GEOMETRY_FILE = 'reference/reference/model.py'
ROUNDING_FILE = 'evidence/h100/correctness/compiled-rounding-batch1024.json'


def positive(value):
    value = float(value)
    if not math.isfinite(value) or value <= 0:
        raise ValueError('Rates and capacities must be finite and positive')
    return value


def token_channel_ceiling(tape_slots, combined_tokens_per_second):
    """Paper's explicit-matrix, 16-bit-per-token communication model only."""
    return (2.0 / 3.0) * math.sqrt(positive(tape_slots) / 3.0) * positive(combined_tokens_per_second)


def proxy_residual_training_factor(operation_rate, fpga_tps, reference_tps):
    """One H100-equivalent reference; not a certified licensed rating."""
    return positive(operation_rate) / H100_DENSE_FLOPS * positive(reference_tps) / positive(fpga_tps)


def model_geometry(source):
    """Read pinned dataclass constants without importing NumPy or model code."""
    expected = {'num_hidden_layers': 6, 'hidden_size': 256, 'intermediate_size': 682,
                'num_attention_heads': 4, 'num_key_value_heads': 2,
                'head_dim': 64, 'vocab_size': 4019}
    classes = [node for node in ast.parse(source).body
               if isinstance(node, ast.ClassDef) and node.name == 'SimpleStoriesConfig']
    if len(classes) != 1:
        raise ValueError('Expected the pinned model configuration')
    found = {node.target.id: ast.literal_eval(node.value) for node in classes[0].body
             if isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name)
             and node.target.id in expected}
    if found != expected:
        raise ValueError('Model geometry changed; re-audit the work-count model')
    return found


def model_work_counts(geometry, context):
    """Model-level useful work, not a mapped RTL instruction/traffic census."""
    if type(context) is not int or not 1 <= context <= 2048:
        raise ValueError('Expected an integer context between 1 and 2048')
    layers, dim, ff = (geometry[key] for key in
                       ('num_hidden_layers', 'hidden_size', 'intermediate_size'))
    q_heads, kv_heads, head_dim, vocab = (geometry[key] for key in
                                        ('num_attention_heads', 'num_key_value_heads', 'head_dim', 'vocab_size'))
    # Q/O, K/V and gate/up/down projections, then one tied vocabulary head.
    # The input embedding is a lookup, not a second vocabulary matmul.
    projection_macs = layers * (2 * dim * dim + 2 * dim * kv_heads * head_dim + 3 * dim * ff) + dim * vocab
    attention_macs = 2 * layers * q_heads * head_dim * context
    gate_products = layers * ff
    norm_squares = (2 * layers + 1) * dim
    return {
        'context_positions': context,
        'projection_and_head_macs': projection_macs,
        'attention_macs': attention_macs,
        'gate_products': gate_products,
        'normalization_squares': norm_squares,
        'dominant_matrix_operations_per_decode': 2 * (projection_macs + attention_macs),
        'scheduled_dynamic_mac_equivalent_operations_per_decode': 2 * (attention_macs + gate_products + norm_squares),
        'minimum_fp16_kv_bytes_per_decode': 2 * layers * kv_heads * head_dim * context * 2,
        'scope': 'Logical model work for one cached decode; not a complete RTL execution count. Matrix count omits nonlinearities, normalization, rotary operations, padding and implementation overhead. Dynamic count grants a full MAC to each gate product and square.',
    }


def estimate(package, reference_rates=None):
    package = Path(package)
    spec = importlib.util.spec_from_file_location('h100_reference_check', package / 'tools/check_h100_reference.py')
    checker = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(checker)
    verified_reference = checker.verify(package)
    relative_inputs = ('evidence/baseline-current/metrics.json', 'evidence/baseline-current/implementation.json',
                       'hardware/project/uart_core.sv', REFERENCE_FILE, 'evidence/h100/IMPORT.json',
                       GEOMETRY_FILE, ROUNDING_FILE, 'tools/estimate_training_capacity.py')
    raw = {name: (package / name).read_bytes() for name in relative_inputs}
    physical = json.loads(raw[relative_inputs[0]])
    implementation = json.loads(raw[relative_inputs[1]])
    benchmark = json.loads(raw[REFERENCE_FILE])
    rounding = json.loads(raw[ROUNDING_FILE])
    geometry = model_geometry(raw[GEOMETRY_FILE].decode())
    counts = model_work_counts(geometry, 128)
    if counts['projection_and_head_macs'] + counts['normalization_squares'] != benchmark['model']['parameters']:
        raise ValueError('Tied model parameter census changed')
    measured_reference_rate = positive(benchmark['timing']['aggregate_tokens_per_second'])
    if measured_reference_rate != verified_reference['selected_reference_tps']:
        raise ValueError('Reference identity/rate mismatch')
    if '.CLKS_PER_BIT(217)' not in raw[relative_inputs[2]].decode():
        raise ValueError('UART contract changed; re-audit this calculation')
    core_hz = implementation['nominal_inference_clock_hz']
    if core_hz != 25_000_000:
        raise ValueError('Clock changed; re-audit this calculation')
    measured = physical['metrics']['around128']
    if (measured['prompt_tokens'], measured['generated_tokens'], measured['occupied_tape']) != (1, 128, 129):
        raise ValueError('Expected last STEP at 128 input positions')
    seconds = positive(measured['last_step_seconds'])
    fpga_tps = 1.0 / seconds
    uart_baud = core_hz / 217.0
    # Five bytes/frame, one token at most. Each accepted RX byte needs eight
    # CLKS_PER_BIT data intervals; TX needs at least those too. Deliberately
    # omit start/stop and all controller/ACK waits, and saturate both directions.
    wire_token_rate = 2.0 * uart_baud / (8 * 5)
    tape_slots = 2049  # Includes the last output beyond the 2048-input limit.
    dynamic_lanes = 5  # Two attention, one gate product, two RMSNorm square lanes.
    primitives = implementation['mapped_multiplier_primitives']
    if primitives != {'MULTALU27X18': 73, 'MULT12X12': 3}:
        raise ValueError('Mapped census changed; re-audit this calculation')
    scenarios = {
        'token_channel_wire_ceiling': {
            'operation_rate_proxy': token_channel_ceiling(tape_slots, wire_token_rate),
            'access_model': 'software_token_interface',
            'access_assumption': 'Host software and token interface; unchanged implementation, protocol and nominal clock. Only explicit matrix I/O is counted.',
            'kind': 'Conditional communication ceiling for explicit dense matrix I/O through tokens only.',
        },
        'five_dynamic_lanes_full_credit': {
            'operation_rate_proxy': 2.0 * dynamic_lanes * core_hz,
            'access_model': 'physical_dynamic_unit_stress',
            'access_assumption': 'Accepted weights remain fixed; useful access to every named dynamic unit is granted, not software-exposed or established by DDR access alone.',
            'kind': 'MAC-equivalent over-credit of five internal integer multipliers at nominal clock; not demonstrated GEMM access.',
        },
        'all_mapped_multipliers_full_credit': {
            'operation_rate_proxy': 2.0 * sum(primitives.values()) * core_hz,
            'access_model': 'internal_circuit_full_access_stress',
            'access_assumption': 'Hypothetical defeat of operand, readout and scheduling restrictions; no concrete all-unit access method established.',
            'kind': 'Stress proxy crediting every mapped multiplier, including fixed-operand and small units; not a whole-chip tamper bound.',
        },
        'fixed_schedule_dynamic_work_allowance': {
            'operation_rate_proxy': counts['scheduled_dynamic_mac_equivalent_operations_per_decode'] * fpga_tps,
            'access_model': 'physical_fixed_schedule_stress',
            'access_assumption': 'Physical-memory access plus assumed complete immutable execution/rate bound; not a certified consequence of interface proofs.',
            'operations_per_decode_credited': counts['scheduled_dynamic_mac_equivalent_operations_per_decode'],
            'kind': 'Conditional model-operation allowance if a verified, unaccelerated schedule limits the named dynamic work; that premise and useful result recovery are not established.',
            'fixed_operation_count_premise_certified': False,
        },
        'weight_enforcement_failure_fixed_schedule': {
            'operation_rate_proxy': counts['dominant_matrix_operations_per_decode'] * fpga_tps,
            'access_model': 'weight_enforcement_compromise',
            'access_assumption': 'Hypothetical compromise of hardware weight acceptance by an unspecified cause; not a public weight-update command.',
            'operations_per_decode_credited': counts['dominant_matrix_operations_per_decode'],
            'kind': 'Counterfactual changeable, usable weights at unchanged decode rate: credits dominant matrix work, ignoring replacement/restart costs. No enforcement failure or usable generic-model service demonstrated; not a whole-device bound.',
            'weight_enforcement_failure_demonstrated': False,
        },
    }
    custom_rates = reference_rates is not None
    rates = [positive(rate) for rate in reference_rates] if custom_rates else [measured_reference_rate]
    if not rates:
        raise ValueError('Specify at least one reference rate')
    for scenario in scenarios.values():
        scenario['ratios'] = [
            {'reference_tps': rate,
             'reference_kind': 'user_supplied_sensitivity' if custom_rates else 'measured_fp16_parent_model',
             'proxy_residual_training_factor': proxy_residual_training_factor(scenario['operation_rate_proxy'], fpga_tps, rate),
             'illustrative_target_comparisons': [
                 {'target': target,
                  'proxy_over_target': proxy_residual_training_factor(scenario['operation_rate_proxy'], fpga_tps, rate) / target}
                 for target in ILLUSTRATIVE_TARGETS]}
            for rate in rates
        ]

    def headroom_row(rate, kind):
        return {'reference_tps': rate, 'multiple_of_measured_reference': rate / measured_reference_rate,
                'kind': kind, 'measured': False,
                'scenario_proxy_residual_training_factors': {
                    name: proxy_residual_training_factor(row['operation_rate_proxy'], fpga_tps, rate)
                    for name, row in scenarios.items()}}

    matrix_ops = counts['dominant_matrix_operations_per_decode']
    kv_bytes = counts['minimum_fp16_kv_bytes_per_decode']
    compute_roof = H100_DENSE_FLOPS / matrix_ops
    kv_roof = H100_MEMORY_BYTES_PER_SECOND / kv_bytes
    reference_for_unit_proxy = H100_DENSE_FLOPS * fpga_tps / scenarios['all_mapped_multipliers_full_credit']['operation_rate_proxy']
    return {
        'schema': 'conditional-training-capacity-v4',
        'source_sha256': {name: hashlib.sha256(data).hexdigest() for name, data in raw.items()},
        'inputs': {
            'core_clock_hz': core_hz, 'uart_clocks_per_bit': 217, 'uart_frame_bytes': 5,
            'uart_data_bits_per_byte_credited': 8, 'uart_framing_bits_omitted': True,
            'uart_directions_credited': 2,
            'tape_slots': tape_slots, 'dynamic_multiplier_instances': dynamic_lanes,
            'mapped_multiplier_primitives': primitives, 'credited_operations_per_multiply': 2,
            'h100_dense_flops_per_second': H100_DENSE_FLOPS,
            'h100_memory_bytes_per_second': H100_MEMORY_BYTES_PER_SECOND,
            'illustrative_paper_targets_not_certification_thresholds': list(ILLUSTRATIVE_TARGETS),
            'model_geometry': geometry,
            'fpga_context_positions': 128, 'measured_single_step_seconds': seconds,
            'fpga_inference_rate_proxy': fpga_tps,
            'fpga_rate_scope': 'Reciprocal of one measured last STEP, including host overhead; not sustained peak or a licensed rating.',
            'reference_tps_are_sensitivity_inputs_not_measurements': custom_rates,
        },
        'measured_reference': {
            'file': REFERENCE_FILE, 'aggregate_tokens_per_second': measured_reference_rate,
            'context_positions': 128, 'batch': benchmark['workload']['batch'],
            'mode': benchmark['workload']['mode'], 'precision': benchmark['model']['dtype'],
            'model_revision': benchmark['model']['revision'], 'fpga_bit_exact': False,
            'kind': 'Repeated fixed-context cached-decode evaluation; not an autoregressive stream or certified peak rating.',
            'greedy_agreement_with_eager_fp16': benchmark['checks']['optimized_vs_eager']['comparison']['argmax_agreement_fraction'],
            'numerical_acceptance': 'Original logit tolerances with explicitly reported FP16 greedy rounding differences.',
            'strict_alternative_tps': verified_reference['strict_reference_tps'],
            'strict_alternative_mode': 'uncompiled_cuda_graph',
            'fpga_integer_model_agreement_measured': False,
            'rounding_diagnostic': {
                'file': ROUNDING_FILE, 'batch': rounding['batch'], 'seed': rounding['seed'],
                'mismatching_rows_investigated': rounding['greedy_mismatch_count'],
                'covers_selected_reference_disagreements': False,
            },
            'timing_scope': 'Median host-wall time, launches and synchronization included; model/prefill/compile/warmup/host-token-transfer/text/network excluded.',
        },
        'uart_baud': uart_baud, 'combined_wire_token_rate_ceiling': wire_token_rate,
        'model_work_counts': counts,
        'scenarios': scenarios,
        'reference_performance_models': {
            'hardware_specification': 'https://www.nvidia.com/en-us/data-center/h100/',
            'scope': 'Idealized models for this independent-cache FP16 workload, not achieved rates, forecasts or a standardized peak rating. Assume the stated useful-work count and no cross-row cache sharing; omit overhead.',
            'measured_useful_matrix_flops_fraction_of_dense_peak': matrix_ops * measured_reference_rate / H100_DENSE_FLOPS,
            'measured_minimum_kv_bytes_fraction_of_peak_bandwidth': kv_bytes * measured_reference_rate / H100_MEMORY_BYTES_PER_SECOND,
            'fractions_are_profiled_hardware_utilization': False,
            'arithmetic_only_roof': headroom_row(compute_roof, 'Ideal dense matrix-work roof ignoring memory and all other operations.'),
            'minimum_kv_traffic_only_roof': headroom_row(kv_roof, 'Ideal KV-bandwidth roof: each FP16 K/V element read from HBM once; no extra copies, writes, weights or other traffic.'),
            'combined_ideal_roof_reference_tps': min(compute_roof, kv_roof),
            'combined_roof_rule': 'min(arithmetic rate, bandwidth rate), equivalently max of their per-step time floors; no assumption that these times add.',
            'unmeasured_speedup_sensitivities_not_forecasts': [
                headroom_row(measured_reference_rate * multiple, 'Unmeasured sensitivity example, not a predicted kernel speedup.')
                for multiple in (3, 6)],
            'all_mapped_proxy_equals_one_at_reference_tps': reference_for_unit_proxy,
            'all_mapped_proxy_equals_one_at_multiple_of_measured': reference_for_unit_proxy / measured_reference_rate,
        },
        'scope': 'Conditional arithmetic scenarios using a measured FP16 parent-model reference by default; not exact FPGA-model inference, a measured training attack or a certified residual training factor.',
        'h100_inference_benchmark_measured': True, 'training_attack_demonstrated': False,
        'certified_residual_training_factor': None, 'hardware_access': False, 'network_access': False,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--reference-tps', nargs='+', type=float,
                        help='Optional sensitivity inputs; default reads the measured FP16 reference')
    parser.add_argument('--output', type=Path, help='Write a new JSON file; never overwrite an existing result')
    parser.add_argument('--check', action='store_true', help='Compare default calculation with the packaged JSON')
    args = parser.parse_args()
    if args.output and args.check:
        parser.error('--output and --check are mutually exclusive')
    if args.check and args.reference_tps is not None:
        parser.error('--check compares the default measured-reference calculation; omit --reference-tps')
    try:
        result = estimate(args.package, args.reference_tps)
    except ValueError as error:
        parser.error(str(error))
    encoded = json.dumps(result, indent=2, sort_keys=True) + '\n'
    if args.check:
        expected = args.package / 'evidence/training-capacity-estimates.json'
        if expected.read_text() != encoded:
            parser.error('Packaged estimates do not match these inputs')
        print('Conditional capacity calculations match the packaged evidence; no hardware accessed.')
    elif args.output:
        with args.output.open('x') as stream:
            stream.write(encoded)
        print('Wrote conditional estimates from saved evidence; no new GPU or hardware run was performed.')
    else:
        print(encoded, end='')


if __name__ == '__main__':
    main()
