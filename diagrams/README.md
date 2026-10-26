# Hardware diagrams

The overview drawings introduce the restricted interface and memory boundaries.
The detailed drawings expand the released hardware, with the same colors for
weights, activations, K/V state and control in both demonstrations.

| Detailed drawing | Technical explanation | Download |
| --- | --- | --- |
| SimpleStories-V2-5M baseline | [Architecture guide](../demos/simplestories-v2-5m/HARDWARE.md#detailed-baseline-diagram) | [SVG](simplestories-hardware-architecture.svg) · [PNG](simplestories-hardware-architecture.png) |
| Qwen3-1.7B AWS F2 baseline | [Hardware guide](../demos/qwen3-1.7b/HARDWARE.md#detailed-hardware-diagram) | [SVG](qwen-hardware-architecture.svg) · [PNG](qwen-hardware-architecture.png) |

These are functional diagrams, not chip floorplans. Arrows summarize selected
transfers; they do not show every wire. “Private” means controlled by the fixed
circuit rather than a host tensor interface, not physically unreadable memory.
The diagrams do not establish timing closure, whole-machine refinement or
resistance to physical tampering.

## Sources and count conventions

The SimpleStories drawing describes the baseline image identified in
[implementation.json](../evidence/current-greedy/baseline/analysis/implementation.json).
Its 90 mapped multiplier primitives include 64 projection lanes, two projection
scaling units, 19 scheduled runtime-operand units, and five supporting units. A dynamic role
uses runtime values for both operands in at least one scheduled operation; the
same unit can also perform fixed-coefficient work. Its
[recorded census](simplestories-hardware-architecture.inventory.json) lists the
mapped instances and the source-census identity. The renderer checks the census totals against
the public implementation record and image identity; it does not rerun synthesis
or independently reconstruct the census from RTL. The protected variant is
shown only as a callout, and the encrypted variant has a different datapath.

The Qwen drawing describes the released A0/B0/C0/H1 image in
[deployment.json](../demos/qwen3-1.7b/deployment.json).
Its [inventory](qwen-hardware-architecture.inventory.json) records the checked
design-file hashes, routed checkpoint identity and disjoint subsystem counts
from the public [hierarchical utilization report](../demos/qwen3-1.7b/evidence/implementation/utilization-hierarchical.rpt).
The renderer verifies those source/report hashes and several RTL configuration
facts. This design maps to 1,000 DSP48E2 blocks, not 1,000 independent
multipliers: floating-point operations can use several blocks, additions also
use blocks, and only one projection bank is selected at a time. Its resource
count therefore cannot be compared directly with SimpleStories' 90 multiplier
instances.

## Regenerate the detailed drawings

The scripts require Python 3.8 or newer and Matplotlib. The SimpleStories image
was rendered with Matplotlib 3.10.7; the Qwen image uses 3.11.2. Both use the
bundled DejaVu Sans font. From the repository root:

```sh
python3 diagrams/simplestories-hardware-architecture.py
python3 diagrams/qwen-hardware-architecture.py
```

These commands use local release files, not hardware, cloud services or private
build directories. They overwrite the accompanying SVG/PNG files, and the Qwen
script regenerates its inventory. Renderer or font changes may change the
output bytes; such regenerated files need a corresponding release-manifest
update before the package integrity check will accept them.
