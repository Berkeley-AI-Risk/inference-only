# Qwen3-8B protected K/V component simulation

This opt-in same-clock component checks a protected K/V writer, committed
roots, AXI transport and an attention consumer using deterministic test values.
The deployed Qwen3-8B F2 image uses plain K/V. This package does not produce an
FPGA image or execute the complete model.

## Reconstruct the tested package

From a clean repository checkout, use Python 3.12 and its standard library:

```sh
python3.12 -I -S -B tools/stage_source_map.py \
  --map demos/qwen3-8b/variants/protected-kv-simulation/SOURCE-MAP.json \
  --output /absolute/fresh-component
```

Choose a new directory outside the repository, with no whitespace in its path
if you intend to compile the component. The command uses no network, compiler,
simulator, model download or FPGA. It checks every input's byte count and SHA-256
before creating the output, then rechecks the bytes copied there. Changed or
missing inputs are errors; an existing output is preserved.

The [source map](SOURCE-MAP.json) reconstructs all 143 tested package members.
It reuses 79 exact sources from the canonical 8B hardware tree and two from the
1.7B component. The [capsule](capsule/README.md) retains 14 distinct source
files and the original fixtures, tools, notices and evidence. Shared sources
are copied into the reconstructed directory; they are not modified or linked.
Its original source manifest, completion record and evidence remain unchanged.
If shared source bytes change, staging refuses the substitution rather than
silently extending the qualification to another RTL selection.

Check the reconstructed source, logs and independent oracle without compiling:

```sh
python3.12 -S -B /absolute/fresh-component/check_recorded.py
```

This checker imports local package modules, so omit Python's `-I` option for
that command. For a fresh native replay, follow `README.md` inside the
reconstructed directory: run its plain, protected and bounds cases explicitly
into fresh result directories. Those optional runs need Verilator, a C++17
compiler and make. The retained capsule alone is not a complete build tree.

## Evidence and scope

The honest case checks 36 ordered layer commits and 9,216 consumed BF16 values
at position zero through the first attention grouped-query pair. Separate
layer-35 K and V corruption cases block the affected operands; plain controls
consume changed values. The transport case checks the final legal digest beat
and nine typed refusals. The independent checker reconstructs all 36 SHA roots
and checks actual consumed operands.

First-position protected writes total 2,377,728 bytes versus 147,456 plain
bytes (16.125 times). This is whole-page publication traffic for that fixture,
not whole-model overhead, sustained decoding speed or physical HBM measurement.
See the [recorded evidence](capsule/EVIDENCE.md).

The result does not cover all heads or a generated token. Later positions,
partial-page updates, longer contexts, complete-model numerical integration,
CDC/reset, vendor HBM, physical fit/timing and board qualification remain open.
There is no formal-proof claim for this component.

## Licenses

The [dependency notice](capsule/NOTICES.md) retains complete project Apache,
HardFloat, AWS and Qwen licenses. ASL-marked platform files retain their Amazon
platform restrictions. No vendor IP, static shell, model image, credentials or
simulator binary is included.
