# Fixed numerical reference

[Qwen guide](../README.md) · [Installation](../INSTALL.md)

This software computes the same fixed numerical model used to check the FPGA.
It is a verification tool, not a software fallback for the browser app and not
a GPU-speed benchmark. It uses W8×A16 integer projections, specified FP32/BF16
rounding and reduction orders, and the circuit's fixed nonlinear tables.
It does not call a Transformers generation pipeline.

First reconstruct `model-memory.bin` using [the installation guide](../INSTALL.md).
From the Qwen directory, with the model-preparation Python environment active:

```sh
python -B reference/run_reference.py --model-image /path/to/model-memory.bin \
  --campaign full-smoke --backend cpu --threads 8 --output reference-smoke.json
```

The smoke suite regenerates and compares 15 output tokens across four prompts
and a CLEAR/replay case. Use `--campaign all` to regenerate every distinct
recorded prompt at its longest recorded continuation. Identical repeats in the
hardware campaigns are not recomputed. Generation here is fixed-length, even
after an end-of-response token, matching the benchmark protocol.

An Apple Silicon computer may use `--backend mps`. The default memory fraction
is 0.2 of the Metal recommended working-set memory. CPU operation needs no GPU;
allow roughly 16 GB of available RAM for short-prompt reference runs. The full
suite is slower because the reference processes the 512-token prompt serially.
The runner refuses a mismatching model image and does not overwrite results.

The numerical operations and token-machine schedule were copied from the
reference used for hardware qualification. [SOURCE-BINDING.json](SOURCE-BINDING.json)
records the unchanged function bodies and source hashes. The packaging changes
replace private archive paths with a loader for the public fixed memory image.
That source comparison does not prove the new loader correct: loading and
end-to-end token regeneration are checked separately.

The [packaged checks](../evidence/reference/CHECKS.json) record equality of
all 507 loaded tensors (197 quantized matrices with their scales, and 113
normalization vectors) with the qualification reference. A CPU smoke run
regenerated 15 matching tokens; an MPS run regenerated all 435 tokens across
the seven distinct prompts at their longest recorded continuations, including
the 512-token prompt. These are software-reference results, not additional
FPGA measurements. The per-run records include their library versions and
the source hashes; `tools/check_qwen_package.py` at the repository root
checks their association without running the model. These original reference
runs are retained unchanged: the model and expected token IDs have not changed.
The checker compares their regenerated IDs with the current hardware captures;
it does not relabel the older reference runs as new computations.

Agreement on these cases is not a proof of all-prompt equivalence, a model-quality
assessment, or a formal verification of the complete hardware. In particular,
this is not a bit-exact reference for upstream floating-point Qwen3.
