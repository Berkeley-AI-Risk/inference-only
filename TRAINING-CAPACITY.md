# Residual training capacity across the demonstrations

Residual training analysis asks how much useful training arithmetic an adversary could obtain per unit of inference service. The estimates here are conditional engineering proxies; none of the demonstrations has a certified residual training factor or a demonstrated general training interface.

## Model assessments

| Demonstration | Detailed assessment | Scope |
| --- | --- | --- |
| SimpleStories-V2-5M on Tang Mega | [Training capacity](demos/simplestories-v2-5m/TRAINING-CAPACITY.md) | Arithmetic and hypothetical access scenarios for the baseline without K/V integrity checks. |
| Qwen3-1.7B on AWS F2 | [Training capacity](demos/qwen3-1.7b/TRAINING-CAPACITY.md) | Mapped arithmetic inventory, workload-dependent counts and measured H100 parent-model references. |
| Qwen3-8B on AWS F2 | [Conditional arithmetic accounting](demos/qwen3-8b/TRAINING-CAPACITY.md) | Released arithmetic inventory and workload counts; the 8B H100 reference, useful access and certified residual factor remain unestablished. |

The [worked SimpleStories example](demos/simplestories-v2-5m/analysis/registered-credits/README.md)
counts updates on the registered paths of 90 mapped multipliers and uses the
measured rate of 9.8241 next-token evaluations/s at 128 occupied positions.
It gives an upper bound for those paths. How much of that arithmetic someone
with physical possession of the chip could use for training remains open.

The [TLM26 MoE Tang demonstration](demos/tlm26-moe/README.md) has separate board evidence; no residual-training assessment is supplied for that circuit.

## Method and reference measurements

The [shared methodology](docs/analysis/RESIDUAL-TRAINING-METHODOLOGY.md) defines the access assumptions, workload, operation counts, reference measurement and evidence needed for an assessment. The [architecture-dependent analysis](docs/analysis/ARCHITECTURE-DEPENDENT-CAPACITY.md) explains scheduled work, utilization and context effects, using SimpleStories measurements and a larger-model example.

The [H100 benchmark report](docs/benchmarks/H100-BENCHMARK.md) specifies the software, workloads and acceptance policies for each reference implementation. At 128 input positions, the selected repeated FP16 references are 61,655.709 evaluations/s for Qwen and 2,951,332.875/s for SimpleStories. The compiled references use the stated logit-tolerance policy and retain greedy disagreements; GPU parents differ from the FPGA numerical functions.

## Conditional comparison

These alternative access assumptions overlap and must not be added. They grant useful access that has not been demonstrated, and use identified single FPGA steps rather than licensed peak ratings.

<!-- capacity-comparison-table:start -->
| Hypothetical access and schedule | Qwen `phi_proxy` | SimpleStories `phi_proxy` |
| --- | ---: | ---: |
| Named dynamic work on the same decode schedule | 0.002 | 0.0024 |
| Useful MAC every cycle from all named runtime/square units | 0.24 | 0.29 |
| Useful MAC every cycle from all functional multipliers | 0.97 | 1.4 |
| Chosen accepted weights make all counted matrix work useful | 0.22 | 0.034 |
<!-- capacity-comparison-table:end -->

<!-- capacity-comparison-summary:start -->
With the selected shared references, Qwen's named scheduled-work proxy is
about **16% lower** and its hypothetical every-cycle runtime-unit proxy
is about **19% lower** than SimpleStories'. These are conditional calculations,
not demonstrated training capabilities or certified residual training factors.
The GPU parent models and FPGA numerical functions differ.
<!-- capacity-comparison-summary:end -->

Both current assessments use the selected shared-method references. The older
SimpleStories campaign is retained as an explicitly identified sensitivity, not
a second current reference. Displayed proxies are rounded;
[the calculation record](evidence/qwen-h100-2026-10-25/computed-results.json) retains full precision.

## Reproduce the calculations

Run these commands from the repository root; they require no hardware or network:

```sh
python3 -I -S -B demos/simplestories-v2-5m/tools/estimate_training_capacity.py --check
python3 -I -S -B tools/architecture_work_counts.py --check
python3 -I -S -B tools/qwen_h100_results.py --check
```

The per-model assessments distinguish measured rates, hypothetical arithmetic allowances and the execution, numerical-equivalence and physical-security evidence still needed for a whole-system bound.
