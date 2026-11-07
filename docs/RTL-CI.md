# RTL checks for the Tang loader and Qwen command interface

The [RTL workflow](../.github/workflows/rtl-checks.yml) runs on pushes to `main`, on pull requests and on manual request. It compiles two production interfaces across eight FPGA configurations and checks their behavior with Verilator and C++ testbenches.

| Selected configurations | RTL under test | Behavior exercised |
| --- | --- | --- |
| Six SimpleStories Tang images | `board1_qspi_async_word_fifo4`, the four-entry, 256-bit loader FIFO | A stalled reader receives the original word. Words stay in order across full/empty transitions and pointer wrap. A coordinated reset clears queued words. |
| Qwen3-1.7B and Qwen3-8B | `qwen_token_command_cdc` and its `qwen_async_stream_fifo` instances | A 72-bit command retains its owner through the 68-bit result path. A held result stays stable. CLEAR can replace a pending command and suppress a cancelled command’s response. |

Each test uses three clock schedules. Each Tang case checks at least 3,300 words. Each Qwen case checks 129 results, three active-command cancellations and three pending-command replacements. Qwen accepts one ordinary command and one following CLEAR under the protocol exercised here. CLEAR travels through the command interface. Fabric reset acts on both FIFO endpoints together.

Two defect tests check the testbenches themselves. One flips a Tang output bit. The other bypasses Qwen’s discard of a cancelled response. After the matching production baseline passes, CI requires both modified scratch copies to compile and fail the corresponding named behavioral check. Compiler errors, timeouts, signals or unrelated failures do not satisfy these controls. Released RTL is unchanged.

## Source selection and lint

The runner gets Tang compilation order from each selected native `product.gprj` and Qwen order from the checked `qwen_sources.tcl` and its synthesis consumers. It uses the existing Tang and Qwen configuration checkers to stage those sources. Verilator’s elaboration records identify the modules and parameters actually used. Both interfaces compile using the shipped RTL, without vendor blackboxes. Staging or hashing the selected sources does not mean they were all compiled: the compiler records show the actual component closure. This is not a full-top build or a test of the model arithmetic, cryptographic datapaths, vendor DDR/PLL/HBM or home VHDL entropy source.

The Tang FIFO passes lint without warnings. Qwen has five `SYNCASYNCNET` notices on reset-release registers and one `UNUSEDPARAM` notice on the synthesis-only `MEMORY_STYLE` parameter. CI checks the expected files, signals and counts. The reset notices remain open for physical review. These digital simulations exercise the listed components under coordinated endpoint reset. Whole-chip integration, independent reset release, metastability and routed timing require other evidence. These checks are not physical CDC/reset or security signoff.

## Run the checks

From the repository root, use Docker and a fresh output directory accessible to your container runtime. The toolchain file pins the official Verilator 5.050 image for Linux AMD64 and ARM64. The image pull uses the network. Compilation and simulation run offline with one CPU and 2 GiB of memory. [Toolchain pins](../tools/hardware_ci/toolchain.json)

```sh
RTL_CI_IMAGE=$(python3 -I -S -B -c 'import json; print(json.load(open("tools/hardware_ci/toolchain.json"))["container"])')
RTL_CI_WORK=$(mktemp -d)
docker pull "$RTL_CI_IMAGE"
docker run --rm --network none --cpus 1 --memory 2g \
  --mount "type=bind,src=$PWD,dst=/repo,readonly" \
  --mount "type=bind,src=$RTL_CI_WORK,dst=/out" \
  --env "HARDWARE_CI_CONTAINER=$RTL_CI_IMAGE" \
  --entrypoint python3 "$RTL_CI_IMAGE" -I -S -B \
  /repo/tools/hardware_ci/runner.py --repository /repo --output /out/fresh-rtl
```

To run one case during development, add `--configuration qwen3-1.7b` or `--configuration tang/baseline` to the runner command. Use `--plan` to inspect its source selection. A native installation of Verilator 5.050 and a C++ compiler can also run the suite. Use a new output path for every run. The runner records the installed tool versions; a native run does not use the pinned container environment. `--plan` does not compile RTL.

```sh
python3.12 -I -S -B tools/hardware_ci/runner.py --output /tmp/fresh-rtl-native
```

The driver’s own tests exercise its handling of coverage, warnings and failures using synthetic records, not hardware.

```sh
python3.12 -I -S -B -m unittest discover -s tools/hardware_ci -p 'test_runner.py' -v
```

CI uploads the commands, compiled-source identities, elaboration records, compiler and simulator logs, and execution results. These artifacts show which cases ran and where a failure occurred.
