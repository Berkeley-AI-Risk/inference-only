# Qwen3 1.7B protected K/V simulation

This compile-time simulation variant replaces the plain K/V store with trusted
on-chip roots and authenticated, retained K/V leaves. The published FPGA image,
`qwen_verified_machine` default, source inventories and board build remain plain.
The separate top is `rtl/qwen_protected_machine.sv`; it has no runtime protection
switch and keeps the same command and private-memory interfaces.

## Run the short offline regression

From a clean repository checkout with Python 3.12, Verilator and a C++17 compiler:

```sh
python3.12 -I -S -B demos/qwen3-1.7b/variants/protected-kv-simulation/run.py --output /tmp/qwen17-kv-results
```

Use a new output directory. The command elaborates both machine tops, separately
compiles plain and protected store-to-attention fixtures, and runs five directed
cases per configuration. It uses one compile worker and one simulator thread.
It needs no model weights, downloads, AWS access or private files. Logs and actual
child exits stay in the output directory; a failed or interrupted process is not
retried. `VERIFIED.json` is written only after both original terminal PASS records
and the emitted operand/fault observations agree.

The fixture publishes deterministic K/V through the actual writer, checks the
external bytes and independent SHA-256 commitments, then connects the actual
store reader to the public `qwen_attention_pair`. The software oracle observes
the valid/ready edges; it never substitutes attention operands.

| Case | Protected store | Plain control |
| --- | --- | --- |
| Honest write and read | Original K and V reach attention; the length-one result equals V | Same independent values |
| Stored K bit changed before read | Authentication fault while K is requested; no K is consumed | Changed K reaches attention |
| Stored V bit changed before read | Honest K is consumed; authentication fault blocks V | Changed V reaches attention and the length-one result |
| External K changed after payload capture | The retained original K is consumed | The retained original K is consumed |
| CLEAR with a delayed modeled return | Old return drains before a new generation is published and used | Same drain boundary |

The K mutation control checks operand use, not a changed final result: with one
context position, the softmax result is one regardless of K. The post-capture
case checks retention, not continuous integrity of external memory. CLEAR here
is the store's internal session signal with a modeled raw adapter, not the
application CLEAR acknowledgment or an actual CDC/HBM test.

For an external direct-child resource guard, first use `--build-only`, then run
one configuration with `--exec plain` or `--exec protected` against that output.
`--verify-logs PLAIN_LOG PROTECTED_LOG` reviews the guarded transcripts. The
external guard must separately require child zero with no stop or error.

## Source and interface scope

Only the eight K/V modules and separate machine-selection top are added. All
arithmetic, HardFloat, model authentication, SHA-256 pipeline and transport
implementations come from the existing public 1.7B design. `SOURCE-INPUTS.json`
hashes the new files and exact shared public dependencies. The runner checks
that the protected top differs functionally only in its module name and store
selection. No existing source inventory or selected clock is replaced.

The root owner enforces ordered publication and session epochs. The writer
authenticates the old page before editing, waits for external write completion,
then publishes its new root. The reader verifies a retained manifest and leaf
before releasing those retained bytes. External K/V remains plaintext. Raw
memory ports are private physical-integration contracts, not host memory or hash
services. Correct abort, visibility and quiescence acknowledgments remain duties
of the physical adapter; merely elaborating the machine does not validate them.

## Eighteen-token full-machine numerical replay

The [portable replay result](references/portable-long18-20261110.json) records
eighteen feedback-dependent tokens, 504 ordered layer checks, 9,126 tensor
boundaries, 27,581,184 BF16 comparisons and 504 K/V publications. Positions 15,
16 and 17 each have 28 publications, crossing the sixteen-position page boundary.
The simulator exited zero without a guard stop or error after 10,862 seconds.
The independent CPU oracle was regenerated from the fixed model. The simulation
used a previously compiled binary with the exact public compiler-input map.
The receipt distinguishes those execution inputs from later runner checks.

The [portable full-machine replay](full-machine/README.md) gives clean-checkout
capture, preparation, build and execution commands. Obtain the model separately
through [model preparation](../../INSTALL.md#prepare-the-fixed-model), regenerate
every expected tensor independently, and produce your own terminal and
verification receipts. The [reference constants](references/long18.json) bind
the model, ROMs, command tape and original numerical record; the independent
fixtures monitor RTL results and never drive numerical operands.

This is finite local simulation, not a full-context correctness theorem or a
board measurement. The short command above needs neither a model nor the larger
replay's compute budget.

## Recorded matched three-token cost

The [recorded connected-model comparison](references/three-token-cost.json)
reports three complete tokens with every captured tensor compared, at the same
production prefetch setting and 100:125 MHz core/memory clock recipe:

| Behavioral memory | Protected core clocks | Plain core clocks | Core-clock overhead |
| --- | ---: | ---: | ---: |
| Unstalled | 39,433,714 | 31,306,538 | ~26% |
| Randomized stalls | 52,360,543 | 44,191,574 | ~18% |

These are recorded whole-model simulated cycle counts. The short command above
tests the store-to-attention boundary and does not rerun this workload. The
record includes source pins, exact counts and scope; a portable full-model
driver is available above, but does not repeat these matched short cost cases.
These counts are not an FPGA speed,
area or power measurement.

## Cost and remaining qualification

The short runner records actual elapsed process times and binary identities.
Those intervals are not AWS charges. At production geometry, the root array
declares 28 × 2,048 × 256 bits, or 1,835,008 bytes, before metadata and physical
mapping. Authentication retains additional leaf/manifest storage and SHA work.
These source capacities are not a measured FPGA area or power result.

No protected FPGA synthesis, legal routing, setup/hold/bus-skew timing, physical
CDC/reset closure, vendor HBM validation or board benchmark is supplied by this
variant. The existing plain image's performance and resource results do not
qualify it. Read [the dependency notices](NOTICES.md) before redistribution.
