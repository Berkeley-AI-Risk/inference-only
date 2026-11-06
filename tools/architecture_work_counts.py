#!/usr/bin/env python3
"""Useful matrix-work counts, not hardware throughput or training-access bounds.

Standard full causal GQA + SwiGLU only, with identical layer geometry and
equal-length independent sequences. Zero routed_experts selects a dense FFN.
Source dimensions and counting limitations: docs/analysis/ARCHITECTURE-DEPENDENT-CAPACITY.md.
No network, model inference, solver, vendor tool or hardware access.
"""
import argparse
import json
from pathlib import Path

TINY = dict(num_hidden_layers=6, hidden_size=256, intermediate_size=682,
            num_attention_heads=4, num_key_value_heads=2, head_dim=64, vocab_size=4019)
LLAMA_405B = dict(num_hidden_layers=126, hidden_size=16384, intermediate_size=53248,
                 num_attention_heads=128, num_key_value_heads=8, head_dim=128, vocab_size=128256)
# Eight-K/V-head configuration: The Llama 3 Herd of Models, Table 3, and
# meta-llama/llama-models@0e0b8c519242d5833d8c11bffc1232b77ad7f301/models/sku_list.py.
CONTEXTS = (128, 2048, 8192, 32768, 131072)
START = '<!-- architecture-work-table:start -->'
END = '<!-- architecture-work-table:end -->'
WORKLOAD_START = '<!-- architecture-workload-table:start -->'
WORKLOAD_END = '<!-- architecture-workload-table:end -->'
SUMMARY_START = '<!-- architecture-summary:start -->'
SUMMARY_END = '<!-- architecture-summary:end -->'
CYCLE_START = '<!-- architecture-cycle-budget:start -->'
CYCLE_END = '<!-- architecture-cycle-budget:end -->'
REFERENCE_START = '<!-- architecture-reference:start -->'
REFERENCE_END = '<!-- architecture-reference:end -->'


def integer(value, minimum, name):
    if type(value) is not int or value < minimum:
        raise ValueError(f'{name} must be an integer >= {minimum}')
    return value


def work_counts(geometry, *, batch=1, new_tokens=1, cached_tokens=0,
                logit_positions=1, routed_experts=0, active_experts=1):
    """Return logical useful work, excluding padding and masked-out products.

    Final normalization is counted only at logit_positions. Other nonlinear
    work is not complete; the named scalar products/squares receive the same
    two-operation allowance as TRAINING-CAPACITY.md, not a measured training rate.
    """
    if not isinstance(geometry, dict) or set(geometry) != set(TINY):
        raise ValueError('Expected the seven documented model-geometry fields')
    for name, value in geometry.items():
        integer(value, 1, name)
    for name, value in (('batch', batch), ('new_tokens', new_tokens), ('active_experts', active_experts)):
        integer(value, 1, name)
    for name, value in (('cached_tokens', cached_tokens), ('logit_positions', logit_positions),
                        ('routed_experts', routed_experts)):
        integer(value, 0, name)
    if logit_positions > new_tokens:
        raise ValueError('Logit positions must be among the newly processed positions')
    if active_experts > (routed_experts or 1):
        raise ValueError('Active experts exceed available experts (dense uses one)')
    layers, d, f = (geometry[k] for k in ('num_hidden_layers', 'hidden_size', 'intermediate_size'))
    hq, hkv, h, vocab = (geometry[k] for k in
        ('num_attention_heads', 'num_key_value_heads', 'head_dim', 'vocab_size'))
    if hq % hkv:
        raise ValueError('Standard GQA requires query heads divisible by K/V heads')
    pairs = new_tokens * cached_tokens + new_tokens * (new_tokens + 1) // 2
    fixed_macs = 2*d*(hq+hkv)*h + 3*active_experts*d*f + d*routed_experts
    attention = 4*batch*layers*hq*h*pairs
    fixed = 2*batch*(new_tokens*layers*fixed_macs + logit_positions*d*vocab)
    gates = batch*layers*new_tokens*active_experts*f
    squares = batch*(2*layers*new_tokens + logit_positions)*d
    mixing = batch*layers*new_tokens*active_experts*d if routed_experts else 0
    named_extra = 2*(gates+squares+mixing)
    return {
        'query_key_pairs_per_sequence': pairs,
        'fixed_matrix_macs_per_layer_position': fixed_macs,
        'attention_matrix_operations': attention,
        'fixed_matrix_operations': fixed,
        'matrix_operations': attention+fixed,
        'attention_fraction': attention/(attention+fixed),
        'gate_products': gates,
        'normalization_squares': squares,
        'expert_mix_products': mixing,
        'named_dynamic_mac_equivalent_operations': attention+named_extra,
        'matrix_plus_named_extra_operations': attention+fixed+named_extra,
    }


def percent(fraction):
    value = 100*fraction
    return f'{value:.3f}%' if round(value, 3) < 1 else f'{value:.2f}%'


def llama_table():
    rows = ['| Context/prompt length | Decode attention share | Causal prefill attention share |',
            '| ---: | ---: | ---: |']
    for context in CONTEXTS:
        decode = work_counts(LLAMA_405B, cached_tokens=context-1)
        prefill = work_counts(LLAMA_405B, new_tokens=context)
        rows.append(f'| {context:,} | {percent(decode["attention_fraction"])} | '
                    f'{percent(prefill["attention_fraction"])} |')
    return '\n'.join(rows)


def recorded_workload_comparison(package):
    """Count named work in saved intervals, not sustained or usable attack rates.

    Keep the 128-position inference comparison fixed while changing the
    workload credited in the numerator. No extrapolation or new measurements.
    """
    package = Path(package)
    model = package / 'demos/simplestories-v2-5m'
    metrics = json.loads((model / 'evidence/current-greedy/baseline/analysis/metrics.json').read_text(encoding='utf-8'))['metrics']
    capacity = json.loads((model / 'evidence/training-capacity-estimates.json').read_text(encoding='utf-8'))
    inputs = capacity['inputs']
    reference = capacity['measured_reference']
    baseline = metrics['around128']
    repeated = metrics['around128-repeat']
    if (repeated['prompt_tokens'], repeated['generated_tokens'], repeated['occupied_tape']) != (1, 128, 129):
        raise ValueError('Repeated measurement does not match the128-position reference')
    paired_last_seconds = (baseline['last_step_seconds'] + repeated['last_step_seconds']) / 2
    baseline_positions = baseline['prompt_tokens'] + baseline['generated_tokens'] - 1
    if (inputs['model_geometry'] != TINY or inputs['fpga_context_positions'] != 128
            or reference['context_positions'] != 128 or baseline_positions != 128
            or inputs['measured_single_step_seconds'] != paired_last_seconds
            or inputs['fpga_inference_rate_proxy'] != 1 / paired_last_seconds):
        raise ValueError('Saved workload comparison does not match the 128-position reference')
    inference_comparison = inputs['fpga_inference_rate_proxy'] / reference['aggregate_tokens_per_second']
    arithmetic_rating = inputs['h100_dense_flops_per_second']
    rows = []
    for case, phase in (('around128', 'last'), ('prefix128', 'last'),
                        ('prefix512', 'first'), ('prefix128', 'first')):
        measured = metrics[case]
        if phase == 'last':
            positions = measured['prompt_tokens'] + measured['generated_tokens'] - 1
            new_tokens, cached_tokens = 1, positions - 1
            seconds = paired_last_seconds if case == 'around128' else measured['last_step_seconds']
            label = f'`{case}`, last STEP: {positions:,}-position decode'
        else:
            positions = measured['prompt_tokens']
            new_tokens, cached_tokens = positions, 0
            seconds = measured['first_step_seconds_including_prompt_evaluation']
            label = f'`{case}`, first STEP: {positions:,}-token prefill'
        count = work_counts(TINY, new_tokens=new_tokens, cached_tokens=cached_tokens)
        dynamic = count['named_dynamic_mac_equivalent_operations']
        rate = dynamic / seconds
        rows.append(dict(label=label, new_tokens=new_tokens, cached_tokens=cached_tokens,
                         credited_dynamic_operations=dynamic, seconds=seconds,
                         credited_operations_per_second=rate,
                         conditional_proxy=(rate / arithmetic_rating) / inference_comparison))
    return rows


def recorded_workload_table(package):
    rows = ['| Recorded workload | Credited dynamic operations | Time (s) | Credited rate (million/s) | Proxy using the 128-position inference comparison |',
            '| --- | ---: | ---: | ---: | ---: |']
    for row in recorded_workload_comparison(package):
        rows.append(f'| {row["label"]} | {row["credited_dynamic_operations"]:,} | '
                    f'{row["seconds"]:.4f} | {row["credited_operations_per_second"]/1e6:.3f} | '
                    f'{row["conditional_proxy"]:.6f} |')
    return '\n'.join(rows)


def check_table(text, start, end, expected):
    if text.count(start) != 1 or text.count(end) != 1:
        raise ValueError('Missing or duplicate architecture table markers: ' + start)
    if text.index(end) < text.index(start):
        raise ValueError('Architecture table markers are out of order: ' + start)
    recorded = text.split(start, 1)[1].split(end, 1)[0].strip()
    if recorded != expected:
        raise ValueError('Architecture table differs from the calculation: ' + start)


def cycle_fraction(package):
    """Counted dynamic work divided by the named scheduled units' credited nominal cycle budget."""
    package = Path(package)
    row = recorded_workload_comparison(package)[0]
    inputs = json.loads((package / 'demos/simplestories-v2-5m/evidence/training-capacity-estimates.json').read_text(encoding='utf-8'))['inputs']
    peak = (inputs['core_clock_hz'] * inputs['dynamic_multiplier_instances']
            * inputs['credited_operations_per_multiply'])
    return row['credited_operations_per_second'] / peak


def capacity_facts(package):
    package = Path(package)
    saved = json.loads((package / 'demos/simplestories-v2-5m/evidence/training-capacity-estimates.json').read_text(encoding='utf-8'))
    row = recorded_workload_comparison(package)[0]
    counts = work_counts(TINY, cached_tokens=127)
    inputs = saved['inputs']
    reference = saved['measured_reference']['aggregate_tokens_per_second']
    peak = inputs['core_clock_hz'] * inputs['dynamic_multiplier_instances'] * inputs['credited_operations_per_multiply']
    dynamic = counts['named_dynamic_mac_equivalent_operations']
    total = counts['matrix_plus_named_extra_operations']
    return dict(dynamic=dynamic, matrix=counts['matrix_operations'], total=total,
                rho=dynamic/total, eta=total*reference/inputs['h100_dense_flops_per_second'],
                matrix_eta=counts['matrix_operations']*reference/inputs['h100_dense_flops_per_second'],
                proxy=row['conditional_proxy'], units=inputs['dynamic_multiplier_instances'],
                peak=peak, cycle_budget=peak*row['seconds'], occupancy=row['credited_operations_per_second']/peak,
                reference=reference)


def summary_text(package):
    f = capacity_facts(package)
    return (
        f"- At the measured 128-position workload, the scheduled estimate is about\n"
        f"  **{100*f['rho']:.2g}% credited dynamic work × {100*f['eta']:.3g}% reference arithmetic efficiency ≈ {f['proxy']:.2g}**.\n"
        f"  Both factors matter; this is not an architecture-only result.\n"
        f"- The roughly **{1/f['occupancy']:.0f}-fold** gap to the every-clock estimate compares the\n"
        f"  counted operations with **{100*f['occupancy']:.3g}% of {f['units']} units' credited cycle capacity**."
    )


def cycle_budget_text(package):
    f = capacity_facts(package)
    return (
        f"At 128 input positions, the calculation credits **{f['dynamic']:,}** dynamic\n"
        f"MAC-equivalent operations per decode. The **{f['units']}** named units, credited with a\n"
        f"useful MAC on every clock, would supply **{f['cycle_budget']:,.0f}** operations over\n"
        f"the measured interval. The counted work occupies **{100*f['occupancy']:.3g}%** of that allowance,\n"
        f"explaining the approximately **{1/f['occupancy']:.0f}-fold** difference.\n\n"
        f"This is not the dynamic fraction of the model's arithmetic or a measured\n"
        f"utilization trace. It compares model work with hypothetical multiplier-cycle\n"
        f"capacity; it does not establish attacker access. The remaining time includes\n"
        f"fixed-coefficient work, other stages, waits and host overhead."
    )


def reference_text(package):
    f = capacity_facts(package)
    return (
        '```text\n'
        f"C_dynamic  = {f['dynamic']:,}\n"
        f"C_total    = {f['matrix']:,} matrix operations + {f['total']-f['matrix']:,} other credited operations\n"
        f"           = {f['total']:,}\n"
        f"rho        = {f['rho']:.8f}\n"
        f"eta_ref    = {f['eta']:.8f}\n"
        f"φ_schedule = {f['proxy']:.9f}\n"
        '```\n\n'
        f"These use the selected H100 reference, about **{f['reference']/1e6:.3g} million evaluations/s**,\n"
        f"and the 989e12 operations/s reference rating. The matrix-only and expanded\n"
        f"useful-work efficiencies both round to **{100*f['eta']:.3g}%**. This bookkeeping\n"
        f"does not change the measurement or the\n"
        f"scheduled proxy. Product/square credits remain hypothetical allowances.\n\n"
        f"The proxy combines roughly **{100*f['rho']:.2g}% credited dynamic work with {100*f['eta']:.3g}%\n"
        f"effective reference arithmetic throughput**. It is not an architecture-only\n"
        f"number. A faster reference increases it; GPU/FPGA numerical and timing\n"
        f"differences still apply."
    )


def check_document(path, *, package=None):
    package = package or Path(__file__).resolve().parents[1]
    text = path.read_text(encoding='utf-8')
    check_table(text, START, END, llama_table())
    check_table(text, WORKLOAD_START, WORKLOAD_END, recorded_workload_table(package))
    for start, end, expected in (
        (SUMMARY_START, SUMMARY_END, summary_text(package)),
        (CYCLE_START, CYCLE_END, cycle_budget_text(package)),
        (REFERENCE_START, REFERENCE_END, reference_text(package)),
    ):
        check_table(text, start, end, expected)
    expected = f'Here `u_dynamic` is approximately {cycle_fraction(package):.5f}.'
    if text.count(expected) != 1 or text.count('Here `u_dynamic` is approximately ') != 1:
        raise ValueError('Architecture cycle fraction differs from the calculation')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', type=Path, default=Path(__file__).resolve().parents[1],
                        help='Release containing the document and saved measurements')
    parser.add_argument('--check', action='store_true', help='Compare the documented tables and cycle fraction without writing files')
    args = parser.parse_args()
    try:
        if args.check:
            check_document(args.package / 'docs/analysis/ARCHITECTURE-DEPENDENT-CAPACITY.md', package=args.package)
            print('Architecture-work tables and cycle fraction match the calculations; no hardware accessed.')
        else:
            print(llama_table())
            print('\n' + recorded_workload_table(args.package))
            print('\nUseful work counts and conditional interval estimates; not measured training rates or certified residual training factors.')
    except (OSError, ValueError) as error:
        parser.error(str(error))


if __name__ == '__main__':
    main()
