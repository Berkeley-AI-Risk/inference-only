# Reusing the Qwen model-address decoder generator

The private decoder translates the fixed sequencer's tensor region, operation,
layer and tile/token/position index into a model-image byte offset and length.
Invalid requests return an error. The 1.7B decoder uses 32-bit byte offsets;
the 8B decoder uses 34-bit byte offsets.

One [build-time generator](../demos/qwen3-8b/tools/generate_model_address.py)
uses the existing [geometry and layout routines](../demos/qwen3-8b/tools/model_geometry.py)
to emit a private model-address decoder for either of two pinned configurations.
The geometry becomes constants in the generated circuit.

| Profile | Layers | Hidden width | FFN width | Query/KV heads | Tied embeddings | Comparison with released decoder |
| --- | ---: | ---: | ---: | --- | --- | --- |
| Qwen3-1.7B | 28 | 2,048 | 6,144 | 16/8 | Yes | Inductive cycle-level module-output equivalence after reset |
| Qwen3-8B | 36 | 4,096 | 12,288 | 32/8 | No | Byte-identical Verilog |

Both layouts fix the position-address range at 32,768. The included
[configuration snapshots and source pins](../tools/model_size_reuse/SOURCE.json)
make this example specific to these two profiles. Other geometries need their
own validation.

## Run the example

From the repository root, with Python 3.12 and Yosys installed:

```sh
python3.12 -I -S -B tools/model_size_reuse/run.py --output /tmp/qwen-decoder-reuse
```

Use a fresh output directory outside the repository. The runner copies the
released decoders into that directory and checks their original bytes before
and after the comparisons. No model weights or vendor models are needed.

For the digest-pinned Linux tool installation used by the proof workflow:

```sh
MODEL_REUSE_WORK=$(mktemp -d)
python3.12 -I -S -B demos/simplestories-v2-5m/formal/kv-clear-epoch/install_linux.py --out "$MODEL_REUSE_WORK/tools"
python3.12 -I -S -B tools/model_size_reuse/run.py --tool-receipt "$MODEL_REUSE_WORK/tools/TOOLS.json" --output "$MODEL_REUSE_WORK/check"
```

The receipt selects Yosys by its installed path, executable digest and version.
Native runs record their actual tool identity. The installer downloads the
pinned tools; the example itself runs offline.

## What the checks establish

For 1.7B, a Yosys miter compares every module output. The base case samples
`rst_n=0` initially; later inputs, including CLEAR, reset and backpressure,
are arbitrary. Both the base case and the temporal-induction step must pass.
See the [Yosys SAT command reference](https://yosyshq.readthedocs.io/projects/yosys/en/latest/cmd/index_formal.html).

A control flips byte-address bit 5 on accepted weight-code requests in a scratch
copy. It must compile and produce a reachable output mismatch after reset.
`RESULT.json` records the accepted request and mismatching addresses;
`mutant.log` and `counterexample.json` retain the actual witness. A timeout,
syntax error or missing counterexample fails the example.

This is a reuse and regression check for one private digital module. Model
packing correctness, authentication, scheduling, full-chip integration and
physical qualification have separate evidence. The per-demo build recipes
continue to select the released source files.
