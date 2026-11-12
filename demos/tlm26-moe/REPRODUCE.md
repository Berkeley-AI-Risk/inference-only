# Reproduce the TLM26 MoE demonstration

Set `DEMO` to this demo's absolute path and `WORK` to a new directory outside the repository. Copy the source there before generating model files or receipts. The distributed `evidence/` records remain unchanged; new results go in `receipts/` and `build/` in the work copy.

```sh
python3 -B - "$DEMO" "$WORK" <<'PY'
from pathlib import Path
import shutil, sys
source = Path(sys.argv[1]).resolve(strict=True)
output = Path(sys.argv[2]).resolve()
release = next(p for p in source.parents if (p / 'tools/verify_release.py').is_file())
if output == release or output.is_relative_to(release):
    raise ValueError('Choose a work directory outside the release checkout')
shutil.copytree(source, output)
PY
cd "$WORK"
```

`copytree` refuses an existing destination. Preserve partial results and choose another fresh path for a new campaign.

The reference environment used Python 3.10, PyTorch 2.10.0 on the CPU, NumPy 1.26.4 and SentencePiece 0.2.1. RTL replay used Verilator 5.050 and a C++20 compiler. The fetch step verifies pinned hashes before upstream model code is imported. The assertion-based scripts refuse `-O` and `-OO`.

```sh
python3 -m venv .venv
. .venv/bin/activate
python -m pip install numpy==1.26.4 torch==2.10.0 sentencepiece==0.2.1
python -B scripts/reproduce.py fetch
python -B scripts/reproduce.py cpu
python -B scripts/reproduce.py rtl
python -B scripts/verify_board_receipt.py
python -B scripts/reproduce.py stage /tmp/tlm26-native-project
```

The CPU step regenerates the quantized image, fixed lookup tables, page digests and decoder. The RTL step compiles the production datapath with a simulated external memory and serial boot, then compares both complete transcripts with their recorded counterparts. The board checker validates the captured frames, CRCs, token histories, directed refusal, CLEAR sequence, model hashes and recorded median latency. It reads recorded data and does not access a board.

## Expert dispatch replay

The [recorded expert-dispatch result](evidence/expert-dispatch/README.md) checks all 340 launch/first-weight pairs in order. Verify that saved trace without a model, compiler or device:

```sh
python -B scripts/check_dispatch.py --trace evidence/expert-dispatch/stdout.log --expected evidence/expert-dispatch/expected.json --physical evidence/physical.json
```

The copied demo uses the two shared UART sources from the original release checkout. Point `--source-root` at that checkout and check the source pins without a model or compiler:

```sh
python -B scripts/reproduce.py dispatch-sources --source-root "$DEMO/../.."
```

After the `fetch` and `cpu` steps have generated the copied demo's pinned `build/` model and lookup tables, replay the same two histories into a new output directory:

```sh
python -B scripts/reproduce.py dispatch /tmp/tlm26-expert-dispatch --source-root "$DEMO/../.."
```

`dispatch` checks the published source and runtime hashes, builds the passive observer with the existing product testbench, then checks the full trace chronology. It retains build and native logs in the chosen directory and refuses an existing destination. Add `--prepare-only` to stage and inspect the commands without compiling or running them. Run native jobs only under your usual local resource supervision. No FPGA programming or cloud operation is involved.

The `stage` destination must be new. Staging fetches the pinned board dependencies and separately supplied vendor inputs and verifies all 28 native input hashes. Obtain vendor tools and IP under their applicable terms. Run `gw_sh build.tcl` in the staged directory with the tool installation described in the [build guide](README.md#tang-build-and-provisioning). A new native route needs its own timing review.

For a physical replay, follow the [provisioning and recovery instructions](README.md#tang-build-and-provisioning) on a reserved board. The commands above do not load an FPGA image or program flash.

The archived [clean replay](evidence/clean-replay.json) identifies its script and hardware sources. [Release adaptations](metadata/RELEASE-ADAPTATIONS.json) bind assertion-mode refusal guards in the original replay scripts. The dispatch source bindings identify the separate observer and replay extension; archived receipts and production RTL retain their recorded bytes.
