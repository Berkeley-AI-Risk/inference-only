# Residual training capacity across the demonstrations

Residual training analysis asks how much useful training arithmetic an adversary could obtain per unit of inference service. The estimates here are conditional engineering proxies; none of the demonstrations has a certified residual training factor or a demonstrated general training interface.

## Model assessments

| Demonstration | Detailed assessment | Scope |
| --- | --- | --- |
| SimpleStories-V2-5M on Tang Mega | [Training capacity](demos/simplestories-v2-5m/TRAINING-CAPACITY.md) | Arithmetic and hypothetical access scenarios for the baseline without K/V integrity checks. |
| Qwen3-1.7B on AWS F2 | [Training capacity](demos/qwen3-1.7b/TRAINING-CAPACITY.md) | Mapped arithmetic inventory, workload-dependent counts and measured H100 parent-model references. |
| Qwen3-8B on AWS F2 | [Demonstration and limitations](demos/qwen3-8b/README.md) | A corresponding residual-training assessment has not been completed. |

## Method and reference measurements

The [shared methodology](docs/analysis/RESIDUAL-TRAINING-METHODOLOGY.md) defines the access assumptions, workload, operation counts, reference measurement and evidence needed for an assessment. The [architecture-dependent analysis](docs/analysis/ARCHITECTURE-DEPENDENT-CAPACITY.md) explains scheduled work, utilization and context effects, using SimpleStories measurements and a larger-model example.

The [H100 benchmark report](docs/benchmarks/H100-BENCHMARK.md) specifies the software, workloads and acceptance policies for each reference implementation. At 128 input positions, the selected repeated FP16 references are 61,655.709 evaluations/s for Qwen and 2,951,332.875/s for SimpleStories. The compiled references use the stated logit-tolerance policy and retain greedy disagreements; GPU parents differ from the FPGA numerical functions.

## Conditional comparison

These alternative access assumptions overlap and must not be added. They grant useful access that has not been demonstrated, and use identified single FPGA steps rather than licensed peak ratings.

| Hypothetical access and schedule | Qwen `phi_proxy` | SimpleStories `phi_proxy` |
| --- | ---: | ---: |
| Named dynamic work on the same decode schedule | 0.00199995 | 0.00239112 |
| Useful MAC every cycle from all named runtime/square units | 0.235071 | 0.288571 |
| Useful MAC every cycle from all functional multipliers | 0.974066 | 1.36691 |
| Chosen accepted weights make all counted matrix work useful | 0.216341 | 0.0342843 |

With these grants, Qwen's scheduled-work proxy is about 16% lower and its full-use-of-runtime-units proxy is about 19% lower. The assumed access and schedule therefore determine the ordering. The [benchmark report](docs/benchmarks/H100-BENCHMARK.md#conditional-capacity-comparison) gives the inputs, numerical acceptance policies and remaining qualifications. The SimpleStories assessment uses a Transformers 4.48.3 reference; this comparison uses Transformers 5.17.0 for both models. Those reference rates are implementation-specific.

## Reproduce the calculations

Run these commands from the repository root; they require no hardware or network:

```sh
python3 -I -S -B tools/estimate_training_capacity.py --check
python3 -I -S -B tools/architecture_work_counts.py --check
python3 -I -S -B tools/qwen_h100_results.py --check
```

The per-model assessments distinguish measured rates, hypothetical arithmetic allowances and the execution, numerical-equivalence and physical-security evidence still needed for a whole-system bound.
