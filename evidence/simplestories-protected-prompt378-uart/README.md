# Protected SimpleStories prompt 378 to digital UART

For one authenticated four-bank c070 simulation with ordered, zero-stall modeled memory, the independent fixed-point SimpleStories-V2-5M reference agrees with four generated positions. Prompt token 378 gives `200, 15, 103, 157`. CLEAR, a fresh append of 378 and two more STEP commands reproduce `200, 15`.

The six STEP observations contain 1,536 final normalized activation pairs and 24,114 accepted vocabulary score pairs in row order. The nine replies include two APPEND acknowledgments and one CLEAR acknowledgment. The checker decodes all nine from 450 sampled digital TX bits and checks response kind, within-byte sample spacing, framing and CRC. The three changed-record controls cover one non-winning score, one normalization exponent and one pin data bit. These observations qualify this fixed command history. The separate K/V certifications and physical implementation checks address their respective scopes. [Retained result](RESULT.json) · [Trace origin](ORIGIN.json)

## CPU replay

From the public repository root, use a Python environment with [NumPy 1.26.4](requirements.txt) and local Git objects for `b12eadcffd05a6052d648ec23869bc369c4cd16a`.

```sh
python -I -B evidence/simplestories-protected-prompt378-uart/replay.py --public-git .
```

The checker reconstructs and hashes the eight ROM files and the 7,265,984-byte image. It computes the expected six STEP results from the fixed command list and its own greedy outputs, then reads the retained observations. The result includes the per-command normalization and vocabulary hashes, nine decoded frames and three refusal controls. [Retained CPU and build provenance](PROVENANCE.json)

## Native replay

Use Verilator 5.050 with its standard files, a compatible host C++ toolchain and Make. `prompt378-build` must be a fresh directory. The same recipe stages and hashes all inputs before invoking the simulator.

```sh
python -I -B evidence/simplestories-protected-prompt378-uart/stage_rtl.py --public-git . --out prompt378-build --execute
```

Omit `--execute` for an input-only check. The 106-input manifest binds 88 direct public blobs, nine decoded public evidence objects and nine included testbench files. The native recipe runs the command schedule and compares the exact 26,131 selected lines to the retained trace. The [provenance record](PROVENANCE.json) identifies `obj/Vconfidential_system_tb__verFiles.dat`, the input and timestamp inventory, and `obj/Vconfidential_system_tb__ver.d`, the Make dependency list, by their separate hashes. Both original files enumerate 97 project inputs and three Verilator dependencies. Nine additional local files supply runtime data. [Complete input manifest](SIMULATION-INPUTS.json)

An independent fresh build and simulation both exited zero. The reduced event stream matched all 26,131 lines byte for byte. [Fresh replay receipt](PROVENANCE.json)

## Attribution

The model, fixed-point reference, compatible RTL and simulation support are resolved from the pinned public repository. Retain the upstream [SimpleStories MIT notice](../../LICENSES/SimpleStories-MIT.txt) and [model card](../../LICENSES/SimpleStories-MODEL-CARD.md) with the image and model-derived data. The project's [license scope](../../LICENSE-SCOPE.md), [NOTICE](../../NOTICE) and [third-party notices](../../THIRD-PARTY-NOTICES.md) describe the source and tool boundaries. This packet adds the filtered observations, replay scripts and testbench files. [Packet hashes](SHA256SUMS)
