# What can 90 mapped multipliers contribute during SimpleStories inference?

On the frozen 25 MHz SimpleStories greedy implementation, the ordinary registered uses of all 90 mapped multipliers admit at most **2.922 billion gross scalar operation credits per second** over a sustained execution. At the measured context-128 inference rating, the normalized ceiling on these routes is **0.88745**. Whether an operator can use those credits for generic training remains open. [Mapped inventory][census] · [Calculation and observed traces](evidence/support-sites/result.json)

## What earns a credit?

The projection and vocabulary head share 64 lanes. An admitted beat can enable 64 product registers one clock later and 64 accumulator updates two clocks later. The longest group earns 682 weight beats after a group start and 64 metadata transfers. Shorter groups, stalls, CLEAR, aborted jobs and in-flight arithmetic are included. On the remaining routes the accepted sinks are the score/value accumulators (8 + 8 sites), the scaled row (2 partial products and their recombination), the layer and final RMSNorm updates (2 sites), the shared RoPE/SiLU result (1), the embedding normalizer input (1), and address descriptors (4). [Projection stages][engine] · [Ownership and induction checks](evidence/joint-cadence/check.py) · [Support-site checks](evidence/support-sites/check.py)

For an interval of N clock edges, let U count edges allotted to any of the smaller routes. Each of the two shifted projection admission windows contains at most B accepted beats. The native control proofs exclude projection credits at the smaller routes' qualified sinks. Allowing all smaller routes to operate concurrently gives

```text
B = min(N − U, floor((682 × (N − U) + C) / 747))
gross scalar credits ≤ 128 B + 31 U
C = 0 from common reset with an empty pipeline, or 44,330 at an arbitrary reachable start
```

Two more smaller-route edges cost at least one 128-credit projection beat and can add at most 62 credits. Thus U = 0 or 1 gives the finite maximum. Counting the two postscale halves as one mathematical multiplication changes 31 to 29. In either convention the 25-million-edge ceilings are **2,921,552,768 from reset** and **2,921,560,448 at an arbitrary reachable start**. The sustained ceiling is T = 128 × 25,000,000 × 682/747. [Finite-window calculation](evidence/support-sites/ledger.py)

## What is observable?

After a verified RTL boot, ordinary APPEND 0 and STEP produced token **15**. A passive internal probe saw the first embedding coefficient −95 multiplied by scale 20,748, yielding −1,971,060. APPEND 1 used the same external cold-page word 171392, a different private product −3,768,870, and yielded token **108**. APPEND 64 moved the external page to 172032 and yielded token **60**. The token client selects a fixed row. The memory observer sees a 640-word stride. Extracting the internal product here required the testbench probe. Across all 1,028,864 coordinates, coefficient −95 and scale 18,189 never occur together, although each occurs individually. [Trace and codebook](evidence/support-sites/result.json)

## How is it rated?

For one next-token evaluation at 128 occupied positions, the two board STEP times give F = 2/(0.101706167 + 0.101874708) = **9.8241 evaluations/s**. The selected H100 FP16 parent run gives R = 9,011,200/3.053264536 = **2,951,332.87 evaluations/s**, using the median of five batch-32,768 trials. The selected H100 run recorded 61 greedy disagreements with eager FP16 in 32,768 comparisons. H = 989 × 10¹² dense operations/s is the theoretical H100 accounting convention. The FPGA uses fixed-point arithmetic. The proxy is **(T/H) × (R/F) = 0.88744743**. [Board capture][board] · [H100 reference][gpu]

The same 0.88745 would bound the device-wide residual training factor under this rating if each useful training operation, including emulated ones, consumed its own counted credit. Establishing that premise remains open. Unrestricted LUT arithmetic, tables and address-based computation, external-memory access, feedback and reuse can implement further work. Debug access, circuit or clock modification can expose different operands or consumers. The calculation assumes intact source-to-device mapping, 25 MHz, the stated digital reset and normal register enables. The release leaves complete mapping equivalence open. [Scope of the release census][census] · [Residual-training methodology][method]

## Replay locally

In a normal Git checkout of this public repository, run the following from **the directory containing this reader and `reproduce.py`**. `PUBLIC-INPUTS.json` pins the build and measurement inputs, including the demo manifest at `159528e36d46fc803326758b160aa5e84aebd72b`. The checker lives in the current checkout and reads those archived public inputs. A shallow clone may first need `git fetch origin 159528e36d46fc803326758b160aa5e84aebd72b`. Use Python 3.12 and Yosys with ABC. The full run also needs Verilator and a C++ toolchain.

```sh
reader_dir=$(pwd -P)
repo_dir=$(git rev-parse --show-toplevel)
pin=159528e36d46fc803326758b160aa5e84aebd72b
frozen_dir=$(mktemp -d)
git -C "$repo_dir" archive "$pin" demos/simplestories-v2-5m evidence/qwen-h100-2026-10-25 | tar -xf - -C "$frozen_dir"
python3.12 -I -S -B "$reader_dir/reproduce.py" records "$frozen_dir"
kept_dir="$frozen_dir/replay-evidence"
python3.12 -I -S -B "$reader_dir/reproduce.py" full "$frozen_dir" --keep "$kept_dir"
```

**Records** reuses retained temporal-proof results and boot traces. It verifies the mapped netlist and board/GPU records, reruns local SAT, decodes the model image and recomputes the ledger. **Full** regenerates every temporal proof, deliberate failing control and boot trace from the pinned inputs as well. Neither mode needs hardware or cloud access. [Input hashes](PUBLIC-INPUTS.json) · [Controls and trust assumptions](evidence/REPLAY.md)

[census]: https://github.com/Berkeley-AI-Risk/inference-only/blob/159528e36d46fc803326758b160aa5e84aebd72b/demos/simplestories-v2-5m/evidence/current-greedy/baseline/analysis/mapped-census.json#L2-L40
[engine]: https://github.com/Berkeley-AI-Risk/inference-only/blob/159528e36d46fc803326758b160aa5e84aebd72b/demos/simplestories-v2-5m/hardware/project/cluster-engine.sv#L195-L243
[board]: https://github.com/Berkeley-AI-Risk/inference-only/blob/159528e36d46fc803326758b160aa5e84aebd72b/demos/simplestories-v2-5m/benchmarks/fpga-speed/captures/baseline-common-speed-20261026-r1/FINISHED.json
[gpu]: https://github.com/Berkeley-AI-Risk/inference-only/blob/159528e36d46fc803326758b160aa5e84aebd72b/evidence/qwen-h100-2026-10-25/computed-results.json#L22-L30
[method]: https://github.com/Berkeley-AI-Risk/inference-only/blob/159528e36d46fc803326758b160aa5e84aebd72b/docs/analysis/RESIDUAL-TRAINING-METHODOLOGY.md#L26-L47

### Inspect the kept replay

The full command writes the actual Verilator build argv and exit status, each C++ compile/link argv and status, and the three native-model invocations under `$kept_dir/support-sites/native-runs/`. Each invocation has a JSON receipt and merged stdout/stderr log. The wrapper verifies argv and log hashes, matches each model executable to the build, and re-extracts all three traces from the native logs byte for byte. A failed command leaves its receipt and partial log in the kept directory. The accelerated run does not invoke the compiler or model.

The review controls exercise all ten executable assertion-based checkers under both Python optimization flags with missing inputs. They also inject a failed build and a failed model into short test fixtures, checking that errors, stderr and successful sibling traces survive.

```sh
SIMPLESTORIES_FROZEN="$frozen_dir" python3.12 -I -S -B -m unittest discover -v -s "$reader_dir/tests"
```
