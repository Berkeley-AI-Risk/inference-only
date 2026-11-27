# Reset-guarded four-bank greedy SimpleStories on Tang Mega

The Tang Mega 138K ran the protected K/V F-AWIC with its paired key/value scratch
read disabled during datapath reset. The guarded RTL starts from the
[original public four-bank source at b12eadc](https://github.com/Berkeley-AI-Risk/inference-only/blob/b12eadcffd05a6052d648ec23869bc369c4cd16a/demos/simplestories-v2-5m/variants/kv-protected/hardware/project/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_semantic_datapath.sv#L1022).
The single [RTL change](kv-read-reset.patch) gives the routed datapath SHA-256
`1aa05c713d12dc767885dfa99c3c2d56a35874dded5ab398946e3f57962b794b`.

## Board result

On November 26, 2026, the board ran the second guarded placement from volatile SRAM.
Each trial began and ended with an acknowledged idle CLEAR. APPEND supplied the
prompt, then consecutive STEP commands generated tokens from the growing tape.

| Prompt token | Observed STEP replies |
| ---: | --- |
| 378 | 200, 15, 103, 157, 32, 1429, 115, 789 |
| 27 | 85, 393 |
| 378 again | 200, 15, 103, 157, 32, 1429, 115, 789 |

The [27 captured request/reply pairs](uart-frames.txt) preserve the five bytes
of each UART frame in transmission order. The checker validates both directions
and their CRCs and compares the STEP results with independent greedy decoding
from the released integer model. Run from the repository root with Python 3.10+
and NumPy 1.26.4.

```sh
python -I -B evidence/simplestories-tang-reset-guard/check-board.py
```

The board trial covered startup after configuration, idle CLEAR and dependent
generation. The internal RAM enables were observed in simulation. Ownership of
every physical V scratch read by its current STEP after CLEAR remains an open
proof obligation. The 18 STEP replies are a functional comparison.

## Cached generation

On November 27, the same guarded image completed two greedy trials with
one input token (378) and 128 outputs per trial. All 256 token IDs matched
the public fixed-point reference. At 25 MHz, the pooled cached generation
rate was **7.04812 tokens/s**. The denominator is 36.037985125 s for 254
intervals between host-validated STEP replies. The local host sampled a
monotonic clock. The first STEP took 101.962 ms and 101.976 ms in the two
trials, measured from the start of that command to its validated reply.
[Common capture](COMMON.json) · [Trial 1 wire](wire/around1.json) · [Trial 2 wire](wire/around2.json)

The benchmark used a dedicated UART collector. The candidate browser profile
was checked offline against the image and receipt. The live benchmark observed
the four expected browser qualification tokens at the start of each trial.
The registration command itself was outside this physical run.

```sh
python3.12 -I -S -B evidence/simplestories-tang-reset-guard/check_speed.py
python3.12 -I -S -B tools/fpga_speed_benchmark.py --check
```

## Reset-edge comparison

A synchronous RAM samples its enable at the clock edge. With a pending paired
read on the first reset edge, the original datapath captured either value initially
stored at row 43 (`0000` or `ffff`). This internal observation produced no
different public reply in the startup witness. The guarded datapath holds its
previous V read register and deasserts both physical read enables. Both versions
read normally after reset, hold during CLEAR and read the changed word once CLEAR
releases. The [port fixture](port_tb.sv) holds the request fields fixed to isolate
the RAM port behavior. Icarus elaborates the real datapath and its scratch RAM
and omits unrelated child modules.

From the repository root, use Python 3, Icarus Verilog (`iverilog`, `vvp`) and
`patch`. The script checks both source hashes, applies the diff to a temporary
copy and checks the routed datapath hash before running the guarded comparison.

```sh
python3 -I -B evidence/simplestories-tang-reset-guard/replay-ports.py
```

## Image and timing

To reconstruct the guarded hardware project, choose a fresh directory outside
the checkout. The first command stages the 89 redistributable native inputs.
The second stages all 93 if you supply the four hash-matched Gowin source files
listed in the [vendor guide](../../demos/simplestories-v2-5m/VENDOR-SETUP.md).
Each command checks the original four-bank inventory, applies the guard and
checks the changed datapath and placement recipe against the board build.

```sh
python3.12 -I -B evidence/simplestories-tang-reset-guard/stage-source.py /tmp/tang-guard-public
python3.12 -I -B evidence/simplestories-tang-reset-guard/stage-source.py /tmp/tang-guard-full --vendor-dir /path/to/official
```

For a source build, run the matching Gowin IDE's `gw_sh run.tcl` from the
fully staged directory. A new route requires its own timing and board checks.

The routed image used Gowin placement option 4. Reported setup/hold slack was
+0.008/+0.143 ns for the 25 MHz inference core and +0.006/+0.133 ns for the
100 MHz DDR application clock. Gowin reported 145 failing setup/recovery
endpoints and 10 failing hold/removal endpoints, all inside its DDR controller.
The original image had 190 and 10 respectively. Each failing pin on the
guarded image also failed on the original. The worst vendor setup slack
changed from −5.699 to −6.379 ns.

The two routes retain the same two-stage synchronizers on all 38 FIFO pointer
bits that cross clocks. Across those buses, the largest guarded bound on the
spread in arrival times relative to the receiving clock was 6.340 ns against
a 10 ns period. This comparison used the routed delay models. The native
reports omit individual setup and hold slacks for the synchronizer paths.

The routed image SHA-256 is
`0e9a17722a3e9ab1336e27bbe25b576bddbc4a2ca3c507286665a8aa9a76468f`.
[Programming and token client](../../demos/simplestories-v2-5m/prebuilt/kv-protected-reset-guarded/README.md) · [Image, model and route identifiers](../../demos/simplestories-v2-5m/prebuilt/kv-protected-reset-guarded/RELEASE.json)
